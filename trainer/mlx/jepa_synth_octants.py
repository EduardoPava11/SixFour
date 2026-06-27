"""v1.5 corpus bridge: real 64-cubed synthetic captures -> V8 octants -> masked-band records.

This grafts synth_capture.py (the gated 64-cubed synthetic corpus) onto the trainer. It
reconstructs the scene-linear L volume of a capture, slices it into 2x2x2 spatiotemporal
octants, and runs each through the SAME reversible lift the spec uses (jepa_data.lift_oct),
asserting `unlift_oct(coarse, detail) == cube` per record (Spec.JepaData.lawDataEngineRoundTrips).
Each octant becomes a MaskedBandExample / MaskedBandExamplePos for theta_B.

Why this matters: the v1 floor proved theta_B reproduces ONE golden byte (the single fixture).
This trains it on a REAL multi-record corpus and measures held-out generalization, plus it
runs the two keystone laws (sibling context strictly helps, position conditioning strictly
helps) that justify the 9-param and 11-param heads over a coarse-only / position-blind model.

The byte-exact lift is reused from trainer/jepa_data.py (gated against the spec golden), so the
data engine cannot drift from the spec by one integer.
"""
from __future__ import annotations

import os
import sys

import numpy as np

# the trainer package is on this dir; jepa_data.py is one level up (trainer/).
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from jepa_data import lift_oct, unlift_oct, manufacture  # noqa: E402
from synth_capture import synthetic_capture               # noqa: E402

from encoder_frozen import NUM_BANDS
from jepa_loss import masked_band_loss_sum
from masked_band_trainer import train_band_joint_stable
from q16 import to_q16


def lab_volume(seed: int, kind: str) -> np.ndarray:
    """Reconstruct the (F, 64, 64, 3) Q16 OKLab (L, a, b) volume of a capture.

    STEP 2: the corpus DOES carry real chroma -- palettes_q16 channels 1 (a) and 2 (b) reach
    abs ~17k on high-lab. The old l_volume kept only channel 0 (L), which discarded all chroma
    before it could ever reach the value-head target. We now keep all three channels.
    """
    cap = synthetic_capture(seed, kind)
    f, s = cap.indices.shape[0], 64
    # (L, a, b) per voxel = palette (L, a, b) at that voxel's index; reshape flat 4096 -> (64, 64, 3).
    vol = np.empty((f, s, s, 3), dtype=np.int64)
    for fr in range(f):
        lab = cap.palettes_q16[fr, cap.indices[fr], :]  # (4096, 3)
        vol[fr] = lab.reshape(s, s, 3)
    return vol


def _cube_at(vol: np.ndarray, f: int, r: int, c: int, ch: int) -> list:
    """The 8 voxels of a 2x2x2 octant of channel `ch`, in the fixed frame-major lift order."""
    return [
        int(vol[f, r, c, ch]),         int(vol[f, r, c + 1, ch]),
        int(vol[f, r + 1, c, ch]),     int(vol[f, r + 1, c + 1, ch]),
        int(vol[f + 1, r, c, ch]),     int(vol[f + 1, r, c + 1, ch]),
        int(vol[f + 1, r + 1, c, ch]), int(vol[f + 1, r + 1, c + 1, ch]),
    ]


def octant_records(seed: int, kind: str, frame_step: int = 8, space_step: int = 6):
    """Yield (cubeL, coarseL, detailL, (xblk, yblk), chroma) for 2x2x2 octants of a capture.

    Each of the THREE channels (L, a, b) is lifted by the SAME reversible lift and round-trip
    asserted (the data-engine law, now on chroma too). `chroma = ((coarseA, detailA),
    (coarseB, detailB))` carries the a/b lift so the value-head target and the chroma-bearing
    tokens can be reconstructed downstream. The L tuple is byte-identical to the old L-only
    behaviour, so the masked-band (theta_B) path is unchanged. Octant order is fixed
    (frame-major then row then col) so the lift is deterministic.
    """
    vol = lab_volume(seed, kind)
    F, S, _, _ = vol.shape
    for f in range(0, F - 1, frame_step):
        for r in range(0, S - 1, space_step):
            for c in range(0, S - 1, space_step):
                cubeL = _cube_at(vol, f, r, c, 0)
                cubeA = _cube_at(vol, f, r, c, 1)
                cubeB = _cube_at(vol, f, r, c, 2)
                cL, dL = lift_oct(cubeL)
                cA, dA = lift_oct(cubeA)
                cB, dB = lift_oct(cubeB)
                assert unlift_oct(cL, dL) == cubeL, f"L data engine drift on cube {cubeL}"
                assert unlift_oct(cA, dA) == cubeA, f"a data engine drift on cube {cubeA}"
                assert unlift_oct(cB, dB) == cubeB, f"b data engine drift on cube {cubeB}"
                chroma = ((cA, tuple(dA)), (cB, tuple(dB)))
                yield cubeL, cL, dL, (c // 2, r // 2), chroma


def build_corpus(specs, frame_step=8, space_step=6):
    """Build MaskedBandExamples from several (seed, kind) captures, cycling the masked band
    across 0..6 so every one of the 63 params receives gradient. Returns (examples, n_octants).

    An example is (coarseL, detailL, mask, chroma): the L coarse/detail drive the theta_B
    masked-band path; `chroma` carries the a/b lift for the value head (palette) target and the
    chroma-bearing ViT tokens."""
    examples = []
    n_oct = 0
    for k, (seed, kind) in enumerate(specs):
        for i, (_cube, coarse, detail, _xy, chroma) in enumerate(octant_records(seed, kind, frame_step, space_step)):
            mask = (i + k) % NUM_BANDS
            examples.append((coarse, tuple(detail), mask, chroma))
            n_oct += 1
    return examples, n_oct


# ---------------------------------------------------------------------------
# The two keystone laws, ported as closed witnesses from MaskedBandPrediction.hs.
# These are the rigorous proofs that the extra parameters are earned; the corpus
# generalization measurement below is supporting evidence.
# ---------------------------------------------------------------------------

def _fit_rows(width, num_bands, examples, build_phi, target_of, mask_of, steps, eta=0.2):
    """A tiny self-contained mean-gradient least-squares fit over a per-band row layout,
    used by the keystone-law witnesses (independent of the 63-fixed theta_b layout)."""
    ps = [0.0] * (num_bands * width)
    m = max(1, len(examples))
    for _ in range(steps):
        acc = [0.0] * (num_bands * width)
        for ex in examples:
            phi = build_phi(ex)
            mb = mask_of(ex)
            row = ps[mb * width:(mb + 1) * width]
            raw = sum(r * p for r, p in zip(row, phi))
            err = raw - to_q16(target_of(ex))
            base = mb * width
            for j in range(width):
                acc[base + j] += err * phi[j]
        ps = [p - eta * (a / m) for p, a in zip(ps, acc)]
    return ps


def law_sibling_context_strictly_helps(w: int = 7000) -> bool:
    """Two examples share the SAME coarse value but differ in one sibling and the target. A
    coarse-only predictor must emit one value (best summed loss >= 0.25*(t1~-t2~)^2); the
    sibling-aware 9-param head fits both and beats that floor. (MaskedBandPrediction.hs:347)"""
    v, m = 20000, 0
    s2 = 32768
    t1 = 0
    t2 = 6000 + (abs(w) % 12000)
    # detail: band 0 is the masked target, band 1 the distinguishing sibling.
    det1 = (t1, 0,  0, 0, 0, 0, 0)
    det2 = (t2, s2, 0, 0, 0, 0, 0)
    exs = [(v, det1, m), (v, det2, m)]
    coarse_floor = 0.25 * (to_q16(t1) - to_q16(t2)) ** 2
    ps = train_band_joint_stable(1200, exs)
    l_full = masked_band_loss_sum(ps, exs)
    return t1 == t2 or l_full < coarse_floor


def law_position_conditioning_strictly_helps(w: int = 7000) -> bool:
    """Two examples IDENTICAL in coarse and siblings but at DIFFERENT positions with DIFFERENT
    targets. A position-blind predictor is forced to one value (floor 0.25*(t1~-t2~)^2); the
    11-param position-aware head fits both via the (x,y) token. (MaskedBandPrediction.hs:578)"""
    from encoder_frozen import POSITION_FEATURE_COUNT, features_b_pos
    v, m = 20000, 0
    t1 = 0
    t2 = 6000 + (abs(w) % 12000)
    det1 = (t1, 0, 0, 0, 0, 0, 0)
    det2 = (t2, 0, 0, 0, 0, 0, 0)
    # position-conditioned examples: (coarse, detail, mask, (x, y))
    exs = [(v, det1, m, (0, 0)), (v, det2, m, (32768, 0))]
    blind_floor = 0.25 * (to_q16(t1) - to_q16(t2)) ** 2

    def phi(ex):
        vv, det, mm, xy = ex
        return features_b_pos(vv, [b for j, b in enumerate(det) if j != mm], xy)

    ps = _fit_rows(POSITION_FEATURE_COUNT, NUM_BANDS, exs, phi,
                   target_of=lambda ex: ex[1][ex[2]], mask_of=lambda ex: ex[2], steps=1500)

    # summed position-conditioned loss
    def loss(ps, ex):
        vv, det, mm, xy = ex
        row = ps[mm * POSITION_FEATURE_COUNT:(mm + 1) * POSITION_FEATURE_COUNT]
        raw = sum(r * p for r, p in zip(row, phi(ex)))
        t = to_q16(det[mm])
        return 0.5 * (raw - t) ** 2

    l_pos = sum(loss(ps, ex) for ex in exs)
    return t1 == t2 or l_pos < blind_floor


def held_out_ratio(kind: str, mask: int = 0, steps: int = 1000, frame_step: int = 4, space_step: int = 4):
    """Train theta_B on 80% of a capture's non-flat octants, return (held-out loss / floor, n).

    A SINGLE masked band gives a clean, well-powered population regression (one 9-param row,
    thousands of examples) so the generalization number is a measurement, not an overfit
    artifact. (The data-engine corpus above cycles all 7 masks to exercise all 63 params; this
    measurement deliberately does not, to keep the per-row sample count high.) Fully-flat
    octants (all detail bands zero) are dropped: the floor already nails them.

    Vectorized in numpy float64: the single-band problem is one 9-param row, so this is exactly
    the mean-gradient descent of train_band_joint_stable restricted to that row (eta = 0.2),
    just expressed as matrix ops so a 4096-octant fit runs in milliseconds instead of a minute.
    """
    from encoder_frozen import features_b
    rows = [(c, tuple(d)) for _cube, c, d, _xy, _ch in octant_records(3, kind, frame_step, space_step)]
    rows = [r for r in rows if max(abs(b) for b in r[1]) > 0]
    X = np.array([features_b(c, [b for j, b in enumerate(d) if j != mask]) for c, d in rows])
    t = np.array([to_q16(d[mask]) for c, d in rows])
    n = len(X)
    split = int(n * 0.8)
    Xtr, ttr, Xte, tte = X[:split], t[:split], X[split:], t[split:]
    floor = 0.5 * float(np.mean(tte ** 2))        # loss at theta = 0 (raw = 0)
    theta = np.zeros(X.shape[1])
    m = len(Xtr)
    for _ in range(steps):                          # mean-gradient GD, identical to the spec twin
        err = Xtr @ theta - ttr
        theta -= 0.2 * (Xtr.T @ err) / m
    trained = 0.5 * float(np.mean((Xte @ theta - tte) ** 2))
    return trained / floor, n


if __name__ == "__main__":
    fails = 0

    # --- data-engine round-trip on real captures (asserted inside octant_records) ---
    specs = [(7, "high-lab"), (11, "high-detail"), (23, "smooth-grey")]
    _, n_oct = build_corpus(specs, frame_step=8, space_step=8)
    print(f"  data engine: {n_oct} octant records lift + round-trip byte-exact "
          f"across {len(specs)} captures")

    # --- generalization is SMOOTHNESS-PROPORTIONAL (the I-JEPA signature) ---
    # Masked-band prediction can only beat the floor by exploiting correlation between the
    # held band and the visible context. On smooth scenes that correlation exists, so theta_B
    # generalizes to held-out octants; on high-frequency noise there is no linear signal and it
    # correctly cannot. We assert (a) a real gain on smooth scenes and (b) that the gain shrinks
    # as scenes get noisier -- a far stronger correctness signal than a single threshold.
    smooth_ratio, n_s = held_out_ratio("smooth-grey")
    noise_ratio, n_n = held_out_ratio("high-detail")
    print(f"  generalize: smooth-grey held-out loss {smooth_ratio:.1%} of floor (n={n_s}); "
          f"high-detail {noise_ratio:.1%} (n={n_n})")
    if not (smooth_ratio < 0.95):
        print("FAIL: theta_B did not beat the floor on smooth held-out octants"); fails += 1
    if not (smooth_ratio < noise_ratio):
        print(f"FAIL: gain not smoothness-proportional (smooth {smooth_ratio:.1%} "
              f"!< noise {noise_ratio:.1%})"); fails += 1
    else:
        print("  smoothness-proportional: more spatial correlation -> more masked-band gain")

    # --- the two keystone laws (rigorous closed witnesses, varied targets) ---
    if all(law_sibling_context_strictly_helps(w) for w in (1, 4000, 7000, 11000)):
        print("  lawSiblingContextStrictlyHelps: 9-param head beats coarse-only floor")
    else:
        print("FAIL: sibling context did not strictly beat the coarse-only floor"); fails += 1

    if all(law_position_conditioning_strictly_helps(w) for w in (1, 4000, 7000, 11000)):
        print("  lawPositionConditioningStrictlyHelps: 11-param head beats position-blind floor")
    else:
        print("FAIL: position conditioning did not strictly beat the blind floor"); fails += 1

    print("jepa_synth_octants: PASS" if fails == 0 else f"jepa_synth_octants: {fails} FAIL")
    raise SystemExit(1 if fails else 0)

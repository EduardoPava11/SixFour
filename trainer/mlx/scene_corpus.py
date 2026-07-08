"""scene_corpus.py — a MEANINGFUL structured 64³ capture corpus (the un-flooring training set).

The problem (proven in jepa_synth_octants.py:224-240 and the earlier flooring diagnosis): the trainer's
generalization is SMOOTHNESS-PROPORTIONAL. On the Zig `synth_burst` noise kinds (high-lab / high-detail)
the within-octant DETAIL is high-frequency and ~uncorrelated with context, so E[detail | context] ≈ 0 and
the model floors (it can only learn the octant MEAN). On scenes with COHERENT spatial + temporal structure
the detail IS a learnable function of position/motion, so the held-out cell AND detail margins go positive.

This module manufactures exactly that: `(F, side*side, 3) int32 OKLab-Q16` bursts (the SAME shape and dtype
`native_kernels.synth_burst` returns) whose content is low-frequency and temporally coherent — drifting
gradients, moving blobs, translating soft edges, low-frequency waves. Routed through the SAME
`quantize_frame` (256 colours/frame) as a real capture (jepa_synth_octants.lab_volume), so a scene clip is
STRUCTURALLY a real capture (byte-exact GIF round-trip, 256-palette per frame) — only the content is
coherent instead of noise. Everything downstream (the lift, the octant records, the byte-exact data-engine
law) is unchanged.

Archetypes (kind strings, all gamut-clamped to L∈[5243,60293], a,b∈±18350 Q16):
  scene-gradient : affine (L,a,b) gradients whose direction rotates slowly over the 64 frames.
  scene-blob     : smooth Gaussian bumps in L and chroma whose centres move along a seeded smooth path.
  scene-edge     : a soft sigmoid edge between two colour regions that translates+rotates over time
                   (the strongest learnable within-octant DETAIL: the boundary ramp is a function of position).
  scene-waves    : low-frequency 2-D sinusoids in L,a,b with seeded wavevectors, phase-drifting over time.
  scene-mixed    : a seeded blend of the above (diversity within one clip).

`scene_burst(seed, kind)` is the single seam, deterministic in seed. Use the kinds with the trainer:
  python3 train_loop.py --long --kinds scene-gradient,scene-blob,scene-edge,scene-waves ...
"""
from __future__ import annotations

import numpy as np

# The capture gamut (native_kernels.py:41-43), in Q16 (×65536 == 1.0).
L_MIN_Q16 = 5243
L_MAX_Q16 = 60293
CHROMA_MAX_Q16 = 18350
SIDE = 64
FRAMES = 64

SCENE_KINDS = ("scene-gradient", "scene-blob", "scene-edge", "scene-waves", "scene-mixed")


def _coords(side: int):
    u = np.linspace(0.0, 1.0, side, dtype=np.float64)
    X, Y = np.meshgrid(u, u, indexing="xy")          # (side, side) in [0,1]
    return X, Y


def _to_q16(Ln: np.ndarray, an: np.ndarray, bn: np.ndarray) -> np.ndarray:
    """Map normalized L∈[0,1], a,b∈[-1,1] frames (F,side,side) -> (F, side*side, 3) int32 Q16, gamut-clamped."""
    F, s, _ = Ln.shape
    L = L_MIN_Q16 + np.clip(Ln, 0.0, 1.0) * (L_MAX_Q16 - L_MIN_Q16)
    a = np.clip(an, -1.0, 1.0) * CHROMA_MAX_Q16
    b = np.clip(bn, -1.0, 1.0) * CHROMA_MAX_Q16
    out = np.stack([L, a, b], axis=-1)               # (F, side, side, 3)
    return np.rint(out).astype(np.int32).reshape(F, s * s, 3)


def _gradient(rng, X, Y, ts):
    """Affine colour gradients whose direction rotates slowly over the clip."""
    ph = rng.uniform(0, 2 * np.pi, size=3)
    spin = rng.uniform(0.3, 0.8, size=3)             # < 1 cycle over the clip: smooth
    off = rng.uniform(0.2, 0.8, size=3)
    amp = rng.uniform(0.25, 0.45, size=3)
    F = len(ts)
    Ln = np.empty((F,) + X.shape); an = np.empty_like(Ln); bn = np.empty_like(Ln)
    for f, t in enumerate(ts):
        chans = []
        for c in range(3):
            ang = ph[c] + 2 * np.pi * spin[c] * t
            proj = np.cos(ang) * (X - 0.5) + np.sin(ang) * (Y - 0.5)   # ~[-0.7,0.7]
            chans.append(off[c] + amp[c] * (proj / 0.7))
        Ln[f], an[f], bn[f] = chans[0], 2 * chans[1] - 1.0, 2 * chans[2] - 1.0
    return Ln, an, bn


def _blob(rng, X, Y, ts):
    """Two smooth Gaussian bumps (in L and chroma) whose centres move along seeded smooth paths."""
    n = 2
    cx0, cy0 = rng.uniform(0.25, 0.75, n), rng.uniform(0.25, 0.75, n)
    vx, vy = rng.uniform(-0.35, 0.35, n), rng.uniform(-0.35, 0.35, n)
    sig = rng.uniform(0.14, 0.26, n)
    baseL = rng.uniform(0.25, 0.5)
    ampL = rng.uniform(0.3, 0.5, n)
    ampa = rng.uniform(-0.8, 0.8, n); ampb = rng.uniform(-0.8, 0.8, n)
    F = len(ts)
    Ln = np.full((F,) + X.shape, baseL); an = np.zeros((F,) + X.shape); bn = np.zeros_like(an)
    for f, t in enumerate(ts):
        for k in range(n):
            cx = cx0[k] + vx[k] * (t - 0.5)
            cy = cy0[k] + vy[k] * (t - 0.5)
            g = np.exp(-((X - cx) ** 2 + (Y - cy) ** 2) / (2 * sig[k] ** 2))
            Ln[f] += ampL[k] * g
            an[f] += ampa[k] * g
            bn[f] += ampb[k] * g
    return Ln, an, bn


def _edge(rng, X, Y, ts):
    """A soft sigmoid edge between two colour regions, translating + rotating over time. The boundary
    ramp is the strongest LEARNABLE within-octant detail (detail is a function of position)."""
    ang0 = rng.uniform(0, 2 * np.pi)
    spin = rng.uniform(0.2, 0.5)
    sharp = rng.uniform(8.0, 16.0)                   # edge steepness (still resolvable, not a step)
    drift = rng.uniform(-0.3, 0.3)
    lo = rng.uniform(0.15, 0.4, 3); hi = rng.uniform(0.6, 0.9, 3)
    F = len(ts)
    Ln = np.empty((F,) + X.shape); an = np.empty_like(Ln); bn = np.empty_like(Ln)
    for f, t in enumerate(ts):
        ang = ang0 + 2 * np.pi * spin * t
        proj = np.cos(ang) * (X - 0.5) + np.sin(ang) * (Y - 0.5) - drift * (t - 0.5)
        e = 1.0 / (1.0 + np.exp(-sharp * proj))      # soft 0..1 boundary
        Ln[f] = lo[0] + (hi[0] - lo[0]) * e
        an[f] = 2 * (lo[1] + (hi[1] - lo[1]) * e) - 1.0
        bn[f] = 2 * (lo[2] + (hi[2] - lo[2]) * e) - 1.0
    return Ln, an, bn


def _waves(rng, X, Y, ts):
    """Low-frequency 2-D sinusoids (≤3 cycles) in L,a,b, phase-drifting smoothly over time."""
    kx = rng.uniform(0.5, 3.0, 3); ky = rng.uniform(0.5, 3.0, 3)
    ph = rng.uniform(0, 2 * np.pi, 3); dr = rng.uniform(0.4, 1.0, 3)
    off = np.array([0.45, 0.0, 0.0]); amp = np.array([0.35, 0.7, 0.7])
    F = len(ts)
    Ln = np.empty((F,) + X.shape); an = np.empty_like(Ln); bn = np.empty_like(Ln)
    for f, t in enumerate(ts):
        chans = []
        for c in range(3):
            w = np.sin(2 * np.pi * (kx[c] * X + ky[c] * Y) + ph[c] + 2 * np.pi * dr[c] * t)
            chans.append(off[c] + amp[c] * w)
        Ln[f], an[f], bn[f] = chans[0], chans[1], chans[2]
    return Ln, an, bn


_BUILDERS = {
    "scene-gradient": _gradient,
    "scene-blob": _blob,
    "scene-edge": _edge,
    "scene-waves": _waves,
}


def scene_burst(seed: int, kind: str, frames: int = FRAMES, side: int = SIDE) -> np.ndarray:
    """(frames, side*side, 3) int32 OKLab-Q16 — a coherent structured burst, deterministic in seed.

    Drop-in shape/dtype twin of native_kernels.synth_burst, so jepa_synth_octants.lab_volume can quantize it
    to a real-capture-shaped 256-palette clip. `scene-mixed` averages all four archetypes for diversity.
    """
    rng = np.random.default_rng(seed)
    X, Y = _coords(side)
    ts = np.linspace(0.0, 1.0, frames)
    if kind == "scene-mixed":
        acc = None
        for i, b in enumerate(_BUILDERS.values()):
            parts = b(np.random.default_rng(seed * 7 + i + 1), X, Y, ts)
            acc = parts if acc is None else tuple(a + p for a, p in zip(acc, parts))
        Ln, an, bn = (c / len(_BUILDERS) for c in acc)
    elif kind in _BUILDERS:
        Ln, an, bn = _BUILDERS[kind](rng, X, Y, ts)
    else:
        raise ValueError(f"unknown scene kind {kind!r}; one of {sorted(SCENE_KINDS)}")
    return _to_q16(np.asarray(Ln), np.asarray(an), np.asarray(bn))


def _self_check() -> int:
    fails = 0
    for kind in SCENE_KINDS:
        b = scene_burst(0, kind)
        if b.shape != (FRAMES, SIDE * SIDE, 3) or b.dtype != np.int32:
            print(f"FAIL {kind}: shape/dtype {b.shape}/{b.dtype}"); fails += 1; continue
        # gamut
        L, a, bb = b[..., 0], b[..., 1], b[..., 2]
        if L.min() < L_MIN_Q16 - 1 or L.max() > L_MAX_Q16 + 1:
            print(f"FAIL {kind}: L out of gamut [{L.min()},{L.max()}]"); fails += 1
        if max(abs(int(a.min())), abs(int(a.max())), abs(int(bb.min())), abs(int(bb.max()))) > CHROMA_MAX_Q16 + 1:
            print(f"FAIL {kind}: chroma out of gamut"); fails += 1
        # determinism
        if not np.array_equal(b, scene_burst(0, kind)):
            print(f"FAIL {kind}: not deterministic in seed"); fails += 1
        # TEMPORAL COHERENCE: consecutive frames are close (smooth motion -> learnable time axis).
        df = np.abs(np.diff(b.astype(np.int64), axis=0)).mean()
        # SPATIAL DETAIL PRESENT: within-2x2 variation is non-zero (there is detail to learn).
        f0 = b[0, :, 0].reshape(SIDE, SIDE)
        local = np.abs(f0[::2, ::2].astype(np.int64) - f0[1::2, 1::2]).mean()
        coherent = df < 0.04 * (L_MAX_Q16 - L_MIN_Q16)     # mean frame-to-frame step < ~4% of L range
        has_detail = local > 1.0
        print(f"  [{kind:>14}] gamut OK · temporal Δ/frame={df:7.1f} ({'coherent' if coherent else 'JUMPY'}) "
              f"· local detail={local:6.1f} ({'present' if has_detail else 'FLAT'})")
        if not coherent:
            print(f"FAIL {kind}: temporal jumps too large (not coherent)"); fails += 1
        if not has_detail:
            print(f"FAIL {kind}: no within-octant detail (nothing to learn)"); fails += 1
    print("scene_corpus: PASS" if fails == 0 else f"scene_corpus: {fails} FAIL")
    return fails


if __name__ == "__main__":
    raise SystemExit(1 if _self_check() else 0)

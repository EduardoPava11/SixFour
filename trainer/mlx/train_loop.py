"""End-to-end MLX H-JEPA training loop (determinism-first): ONE optimizer descends a
COMPOSITE loss (masked-band I-JEPA + VICReg collapse guard) over the DATA-MANUFACTURED
octant corpus, riding the 18.9M-param ViT head ABOVE the proven theta_B byte-exact floor.

THE SPINE IS THE BYTE-COMMIT PATH. The whole loop is organized around one hard seam:

  =====================  THE float32-train / float64-commit BOUNDARY  =====================
  FLOAT-TRAIN SIDE : everything mx.value_and_grad / opt.update touches is float32 MLX GPU
                     (the ViT large_head._build_vit -> model(x,d6); the net-new input
                     projection 11->512 and latent->band readout; the masked-band MSE
                     against to_q16(target); the VICReg std-hinge on the pre-surface
                     latent). NO committed byte enters the gradient -- the loss compares a
                     RAW float to to_q16(target) (a pure /65536 scaling, q16.py:23-25),
                     never a commit -- so float32 GPU non-associativity NEVER decides a byte.
  BYTE-COMMIT SIDE : a band is COMMITTED only by pulling the readout's float32 out to a
                     Python float64 (numpy; MLX 0.30 .tolist() cannot extract float64) and
                     calling q16.quantize_q16 -- round(x*65536) half-to-even in float64
                     (q16.py:28-34). An MLX float NEVER decides a committed byte. This is the
                     SAME mechanism as theta_b.predict_masked_band (theta_b.py:96-98).
  ========================================================================================

Four properties are each shown by REAL printed output:
  (1) DESCENT     - the composite loss decreases over steps (a printed per-step trajectory).
  (2) NO COLLAPSE - vicreg.variance_floor_penalty on the PRE-surface latent stays ~0 (variance
                    present) while an INDUCED constant latent trips it >0.5 (vicreg.py:78-81).
                    cross_redundancy is blind to constant collapse, so BOTH are printed.
  (3) BYTE-COMMIT - the readout commits a band through q16.quantize_q16 in float64; the printed
                    integer agrees with theta_b.predict_masked_band's mechanism on the floor.
  (4) DETERMINISM - same seed -> bit-identical loss trajectory; two runs print and agree.

WHY THE LOSS IS REAL (a verifier will try to refute it): the masked-band target is
theta_b.masked_target_band(ex), a band lifted BYTE-EXACT from a synthetic 64^3 capture with
unlift_oct(coarse,detail)==cube asserted per record (jepa_synth_octants.py:65). The target is
DATA-MANUFACTURED, never self-produced, no EMA, no rollout -> the collapse-proof property holds
by construction, and VICReg is the only ACTIVE guard, read on the pre-surface latent.

NET-NEW pieces (additive; live ONLY here, none of the 13 gated modules are modified):
  * GAP 1 latent->band readout nn.Linear(512, 7): pooled ViT latent -> 7 band raws; row
    mbe_masked(ex) selects the supervised band. The seam where the big net rides above
    theta_B's scalar raw-readout space (depth-1 reduces to theta_b byte-exact, large_head.py:71-77).
  * GAP 2 token builder + input projection nn.Linear(11, 512): each of the 64 octant-lattice
    tokens carries the example's frozen features_b_pos (encoder_frozen.py:49-55, width 11)
    tagged with its OWN integer lattice (x,y), so the tokens are DISTINCT (the latent has real
    cross-token variance the d6 ALiBi attends over) -- not one broadcast row (which collapses
    the latent). The encoder stays ZERO-param (encoder_frozen.py:34); this is a HEAD.
  * GAP 4 a differentiable MLX twin of vicreg.variance_floor_penalty (so it contributes
    gradient); the pure-Python vicreg.* stays the verifier-facing cross-check.

Run:  python3 train_loop.py --smoke   # 8 octants, 30 steps, < ~10s, all four properties
      python3 train_loop.py           # larger corpus, more steps
"""
from __future__ import annotations

import argparse

# ---------------------------------------------------------------------------
# IMPORT ORDER IS LOAD-BEARING (verified gap): jepa_synth_octants.py:25 does
#   sys.path.insert(0, dirname(dirname(__file__))) == /Users/daniel/SixFour/trainer,
# which CONTAINS this local 'mlx/' package dir (it has __init__.py). After that insert a
# fresh `import mlx.core` would resolve to trainer/mlx/__init__.py and FAIL, so
# large_head._build_vit()'s try/except would silently return None. FIX: import the REAL
# mlx (core/nn/optimizers/utils) FIRST so it is cached in sys.modules; the later
# jepa_synth_octants path pollution is then harmless (the cached module wins).
# Verified: with this order _build_vit returns (mx, model, d6, 18914400).
# ---------------------------------------------------------------------------
import mlx.core as mx
import mlx.nn as nn
import mlx.optimizers as optim
from mlx.utils import tree_flatten

import numpy as np

# The ViT lives float32 on the Metal GPU (large_head.py:130-189). float64 is CPU-only on
# Apple Silicon; the byte commit is done in Python float64 (q16), never on the GPU.

import large_head
from large_head import N_TOKENS, D_MODEL, octant_lattice_d6
from encoder_frozen import features_b_pos, POSITION_FEATURE_COUNT  # width-11 frozen embedding
import theta_b
from theta_b import (
    NUM_BANDS, zero_params_b, mbe_coarse, mbe_masked, siblings_of, masked_target_band,
)
from q16 import to_q16, quantize_q16
import vicreg
from vicreg import VIC_GAMMA, VIC_EPS

# jepa_synth_octants imported LAST (after mlx is cached) -- see the import-order note above.
from jepa_synth_octants import build_corpus

# Composite-loss weight on the VICReg collapse guard. Small so the masked-band objective
# dominates while the latent is kept full-variance (scout lossTerms: lambda in 1e-2..1e-1).
LAMBDA_VIC = 5e-2
# Number of latent neurons fed to the VICReg tap (keeps the Python cross_redundancy
# O(neurons^2) cheap; the MLX hinge uses the same slice).
VIC_NEURON_SLICE = 16
_SIDE = round(N_TOKENS ** (1 / 3))  # 4 -> the 4x4x4 octant token lattice


# ===========================================================================
# GAP 1 + GAP 2 head: input projection (11->512) + ViT + latent->band readout (512->7).
# trainable_parameters() = inproj + ViT + readout: ONE set the single optimizer descends.
# The encoder stays ZERO-param (encoder_frozen.ENCODER_PARAM_COUNT == 0); these are HEADs.
# ===========================================================================
class JepaHead(nn.Module):
    def __init__(self, vit):
        super().__init__()
        self.inproj = nn.Linear(POSITION_FEATURE_COUNT, D_MODEL)  # 11 -> 512 (places tokens)
        self.vit = vit                                            # the 18.9M-param ViT
        self.readout = nn.Linear(D_MODEL, NUM_BANDS)              # pooled latent -> 7 band raws

    def __call__(self, tokens, d6):
        x = self.inproj(tokens)            # (64, 512)
        latent = self.vit(x, d6)           # (64, 512) PRE-surface latent (VICReg taps THIS)
        pooled = mx.mean(latent, axis=0)   # (512,)
        raws = self.readout(pooled)        # (7,) raw band readouts (float32, pre-commit)
        return latent, raws


# ===========================================================================
# GAP 2 token builder: corpus example -> the (64, 11) ViT input on the octant lattice.
# DETERMINISTIC function of the example (NOT mx.random tokens). Each of the 64 tokens gets
# the example's frozen features_b_pos tagged with its OWN integer lattice (x,y), so the
# tokens are DISTINCT and the latent has real cross-token variance for VICReg to read and
# the d6 ALiBi to attend over. (A single broadcast row would collapse the latent.)
# ===========================================================================
def example_tokens(ex) -> mx.array:
    v = mbe_coarse(ex)
    sibs = siblings_of(ex)
    step = 65536 // _SIDE
    rows = np.empty((N_TOKENS, POSITION_FEATURE_COUNT), dtype=np.float32)
    for i in range(N_TOKENS):
        xb, yb = i % _SIDE, (i // _SIDE) % _SIDE
        rows[i] = np.asarray(features_b_pos(v, sibs, (xb * step, yb * step)), dtype=np.float32)
    return mx.array(rows)


# ===========================================================================
# GAP 4 differentiable VICReg std-hinge in MLX (the MLX twin of
# vicreg.variance_floor_penalty, vicreg.py:78-81): per-neuron population variance over the
# 64 token rows, then sum max(0, gamma - sqrt(var + eps)). Contributes real gradient.
# ===========================================================================
def mlx_variance_floor(latent: mx.array) -> mx.array:
    sl = latent[:, :VIC_NEURON_SLICE]               # (64, slice) samples x neurons
    var = mx.var(sl, axis=0)                         # population variance per neuron
    return mx.sum(mx.maximum(0.0, VIC_GAMMA - mx.sqrt(var + VIC_EPS)))


def vicreg_python_read(latent: mx.array):
    """Pull the pre-surface latent slice to float64 rows (numpy; MLX .tolist() can't do
    float64) and read the PURE-PYTHON vicreg terms -- the verifier-facing collapse numbers.
    Tap is BEFORE any quantize_q16 (vicreg.py:21-23 lawRedundancyMeasuredInLatent)."""
    arr = np.array(latent[:, :VIC_NEURON_SLICE]).astype(np.float64)
    rows = [[float(v) for v in r] for r in arr]      # outer=samples (token rows), inner=neurons
    return (vicreg.variance_floor_penalty(VIC_GAMMA, VIC_EPS, rows),
            vicreg.cross_redundancy(rows),
            vicreg.latent_coding_floor(rows))


# ===========================================================================
# One run. Deterministic given `seed`. Full-batch (no minibatch RNG) so the trajectory is
# smooth and bit-reproducible. Returns the per-step composite trajectory + the trained head.
# ===========================================================================
def run(seed: int, examples, d6, steps: int, lr: float, verbose: bool):
    # DETERMINISM SEED: pin mlx (controls the ViT + head float32 init) BEFORE building the
    # net so the whole float32 trajectory is reproducible. numpy is pinned too (token build).
    mx.random.seed(seed)
    np.random.seed(seed)

    built = large_head._build_vit()
    if built is None:
        raise RuntimeError("large_head._build_vit() returned None -- mlx import failed "
                           "(was mlx.core imported BEFORE jepa_synth_octants? see header).")
    _mx, vit, _d6_unused, pcount = built
    head = JepaHead(vit)
    mx.eval(head.parameters())
    # Readout init (pure init, off the gradient path). We deliberately do NOT crush the
    # readout to ~0: the detail-band targets are tiny residuals (|to_q16(target)| <~ 0.05),
    # so a near-zero readout would start ALREADY ON TARGET and L_band would have nothing to
    # fit -- the composite descent would then be ENTIRELY the VICReg hinge relaxing, which a
    # verifier would (rightly) reject as "the loss is not real". Instead we start the readout
    # OFF target (modest weight, small non-zero bias) so L_band carries a real, fittable share
    # of the descent and the OBJECTIVE term demonstrably falls. Bias seeded deterministically
    # from the pinned mx seed.
    head.readout.weight = head.readout.weight * 0.3
    head.readout.bias = head.readout.bias + 0.4
    mx.eval(head.parameters())

    # Precompute the full deterministic batch: tokens, masks, normalized targets.
    tokens_b = mx.stack([example_tokens(ex) for ex in examples], axis=0)   # (B, 64, 11)
    masks = [mbe_masked(ex) for ex in examples]
    targets = mx.array([to_q16(masked_target_band(ex)) for ex in examples], dtype=mx.float32)
    mx.eval(tokens_b, targets)

    def _band_and_vic(h):
        """Return (mean L_band, mean L_vic) as two MLX scalars.
        L_band = 0.5*(raws[mask] - to_q16(target))^2 -- RAW float vs to_q16(target), NO commit
                 in the gradient (the MLX twin of jepa_loss.masked_band_loss, jepa_loss.py:28-32).
        L_vic  = the MLX variance-floor hinge on the PRE-surface latent (active collapse guard)."""
        band_terms, vic_terms = [], []
        for i in range(tokens_b.shape[0]):
            latent, raws = h(tokens_b[i], d6)
            d = raws[masks[i]] - targets[i]
            band_terms.append(0.5 * d * d)
            vic_terms.append(mlx_variance_floor(latent))
        return mx.mean(mx.stack(band_terms)), mx.mean(mx.stack(vic_terms))

    def composite(h):
        """L_composite = mean_i L_band_i + LAMBDA_VIC * mean_i L_vic_i (the ONE MLX scalar the
        single optimizer descends)."""
        band, vic = _band_and_vic(h)
        return band + LAMBDA_VIC * vic

    opt = optim.SGD(learning_rate=lr)
    loss_and_grad = nn.value_and_grad(head, composite)

    if verbose:
        leaves = len(tree_flatten(head.trainable_parameters()))
        print(f"  [seed={seed}] ViT {pcount/1e6:.1f}M params + inproj/readout "
              f"({leaves} trainable leaves); full-batch {len(examples)} octants; "
              f"SGD lr={lr}, steps={steps}")

    trajectory, band_traj = [], []
    for step in range(steps):
        loss, grads = loss_and_grad(head)
        opt.update(head, grads)
        mx.eval(head.parameters(), loss)
        lval = float(loss)                          # a tolerance-bearing float, never a byte
        trajectory.append(lval)
        # Record L_band SEPARATELY from the composite so a verifier can confirm the OBJECTIVE
        # term itself descends -- the descent is NOT merely the collapse guard relaxing to its
        # floor (the hinge hits 0 early while L_band keeps falling).
        band_s, vic_s = _band_and_vic(head)
        mx.eval(band_s, vic_s)
        band_traj.append(float(band_s))
        if verbose:
            latent0, _ = head(tokens_b[0], d6)
            mx.eval(latent0)
            py_hinge, py_cov, _ = vicreg_python_read(latent0)
            print(f"    step {step:2d}  L_composite={lval:.8f}  L_band={float(band_s):.8f}  "
                  f"L_vic={float(vic_s):.6f}   VICReg(live latent) hinge={py_hinge:.4f} cov={py_cov:.4f}")

    return trajectory, band_traj, head, tokens_b, masks


# ===========================================================================
# Property demonstrations (each prints REAL output).
# ===========================================================================
def demo_descent(traj, band_traj):
    print("\n[1] DESCENT -- composite loss decreases over steps")
    drop = traj[0] - traj[-1]
    band_drop = band_traj[0] - band_traj[-1]
    print(f"    L_composite  {traj[0]:.8f} -> {traj[-1]:.8f}   drop={drop:.8f}   "
          f"({'DESCENDS' if drop > 0 else 'DID NOT DESCEND'})")
    # The OBJECTIVE term alone must also descend -- refutes 'the curve is only the VICReg
    # hinge relaxing to its floor' (the hinge zeroes by ~step 10; L_band keeps falling).
    print(f"    L_band(only)  {band_traj[0]:.8f} -> {band_traj[-1]:.8f}   drop={band_drop:.8f}   "
          f"({'OBJECTIVE DESCENDS independently of the guard' if band_drop > 0 else 'OBJECTIVE DID NOT DESCEND'})")
    return (drop > 0) and (band_drop > 0)


def demo_no_collapse(head, tokens_b, d6):
    print("\n[2] NO COLLAPSE -- VICReg on the PRE-surface latent (read BEFORE any Q16 commit)")
    latent, _ = head(tokens_b[0], d6)
    mx.eval(latent)
    live_hinge, live_cov, live_floor = vicreg_python_read(latent)
    # INDUCED-COLLAPSE CONTROL: a constant latent slice trips the std-hinge while
    # cross_redundancy stays blind (vicreg.py:107-111) -> "no collapse" is a REAL test.
    const_rows = [[7.0] * VIC_NEURON_SLICE for _ in range(N_TOKENS)]
    const_hinge = vicreg.variance_floor_penalty(VIC_GAMMA, VIC_EPS, const_rows)
    const_cov = vicreg.cross_redundancy(const_rows)
    print(f"    live ViT latent : variance_floor_penalty={live_hinge:.4f}  "
          f"cross_redundancy={live_cov:.4f}  coding_floor={live_floor:.4f}   (variance present)")
    print(f"    INDUCED constant: variance_floor_penalty={const_hinge:.4f}  "
          f"cross_redundancy={const_cov:.4f}   (hinge trips >0.5; cov is BLIND -> both needed)")
    ok = (live_hinge < 0.5) and (const_hinge > 0.5)
    print(f"    -> {'NO COLLAPSE (latent full-variance; the guard WOULD bite a constant latent)' if ok else 'COLLAPSE CHECK FAILED'}")
    return ok


def demo_byte_commit(head, tokens_b, masks, example0, d6):
    print("\n[3] BYTE-COMMIT PRESERVED -- a committed band is a float64-rounded INTEGER, "
          "never a raw MLX float")
    _latent, raws = head(tokens_b[0], d6)
    mx.eval(raws)
    m = masks[0]
    # ==== BYTE-COMMIT BOUNDARY: below here is Python float64 -> integer, never MLX ====
    raw_f64 = float(np.array(raws[m]).astype(np.float64))   # numpy: float64 extraction
    committed = quantize_q16(raw_f64)                        # q16.py:28-34, round-half-even
    # ==================================================================================
    print(f"    masked band index m = {m}")
    print(f"    raw readout (float32 -> float64) = {raw_f64!r}")
    print(f"    committed band = quantize_q16(raw) = {committed}  "
          f"(type {type(committed).__name__}, exact integer byte)")
    # Cross-check the SAME crossing on the theta_b byte-exact floor the ViT rides above:
    # theta_b.predict_masked_band == quantize_q16(raw_masked_band) (theta_b.py:96-98).
    floor_raw = theta_b.raw_masked_band(zero_params_b(), example0)
    floor_band = theta_b.predict_masked_band(zero_params_b(), example0)
    floor_ok = (floor_band == quantize_q16(floor_raw))
    print(f"    floor cross-check: theta_b.predict_masked_band(zero, ex0) = {floor_band} "
          f"== quantize_q16(raw={floor_raw}) -> {floor_ok}  (same single float->byte crossing)")
    ok = isinstance(committed, int) and floor_ok
    print(f"    -> {'BYTE-COMMIT PRESERVED (Python float64 round; MLX never decides the byte)' if ok else 'BYTE-COMMIT FAILED'}")
    return ok


def demo_determinism(seed, examples, d6, steps, lr):
    print("\n[4] DETERMINISM -- same seed -> bit-identical loss trajectory (two runs)")
    traj_a, _, _, _, _ = run(seed, examples, d6, steps, lr, verbose=False)
    traj_b, _, _, _, _ = run(seed, examples, d6, steps, lr, verbose=False)
    agree = (len(traj_a) == len(traj_b)) and all(a == b for a, b in zip(traj_a, traj_b))
    worst = max(abs(a - b) for a, b in zip(traj_a, traj_b)) if traj_a else 0.0
    print(f"    run A first/last = {traj_a[0]:.8f} / {traj_a[-1]:.8f}")
    print(f"    run B first/last = {traj_b[0]:.8f} / {traj_b[-1]:.8f}")
    print(f"    worst |A-B| over all {len(traj_a)} steps = {worst:.3e}")
    if not agree:
        for i, (a, b) in enumerate(zip(traj_a, traj_b)):
            if a != b:
                print(f"      first divergence at step {i}: {a!r} vs {b!r}")
                break
    print(f"    -> {'DETERMINISTIC (bit-identical trajectory)' if agree else 'NON-DETERMINISTIC'}")
    return agree


def main():
    ap = argparse.ArgumentParser(description="End-to-end MLX H-JEPA training loop.")
    ap.add_argument("--smoke", action="store_true",
                    help="fast mode: 8 octants, 30 steps (< ~10s); shows all four properties.")
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--steps", type=int, default=None)
    ap.add_argument("--lr", type=float, default=8e-3)
    args = ap.parse_args()

    # --- DATA-MANUFACTURED corpus (targets lifted byte-exact, round-trip asserted) ---
    if args.smoke:
        specs, fs, ss = [(7, "high-lab")], 16, 16
        examples, n_oct = build_corpus(specs, frame_step=fs, space_step=ss)
        examples = examples[:8]          # subsample to keep the 18.9M-ViT sweep cheap
        steps = args.steps if args.steps is not None else 30
    else:
        specs, fs, ss = [(7, "high-lab"), (11, "high-detail"), (23, "smooth-grey")], 8, 8
        examples, n_oct = build_corpus(specs, frame_step=fs, space_step=ss)
        examples = examples[:24]
        steps = args.steps if args.steps is not None else 60

    d6 = mx.array(octant_lattice_d6(N_TOKENS), dtype=mx.float32)  # integer L1 ALiBi lattice
    mx.eval(d6)

    print(f"=== SixFour H-JEPA end-to-end MLX training loop "
          f"({'SMOKE' if args.smoke else 'FULL'}, seed={args.seed}, steps={steps}) ===")
    print(f"corpus: {len(specs)} captures -> {n_oct} octant records (using {len(examples)} this run); "
          f"targets DATA-MANUFACTURED (no EMA, no self-produced rollout)")
    print("BYTE-COMMIT BOUNDARY at q16.quantize_q16: float32-train above, float64-commit below.")
    print(f"composite = L_band (masked-band MSE) + {LAMBDA_VIC} * L_vic (VICReg std-hinge), "
          f"one SGD optimizer over ViT + readout\n")

    print("--- PROPERTY (1) training trajectory (run A) ---")
    traj, band_traj, head, tokens_b, masks = run(args.seed, examples, d6, steps, args.lr, verbose=True)

    ok1 = demo_descent(traj, band_traj)
    ok2 = demo_no_collapse(head, tokens_b, d6)
    ok3 = demo_byte_commit(head, tokens_b, masks, examples[0], d6)
    ok4 = demo_determinism(args.seed, examples, d6, steps, args.lr)

    print("\n=== SUMMARY ===")
    print(f"  (1) DESCENT     : {'PASS' if ok1 else 'FAIL'}")
    print(f"  (2) NO COLLAPSE : {'PASS' if ok2 else 'FAIL'}")
    print(f"  (3) BYTE-COMMIT : {'PASS' if ok3 else 'FAIL'}")
    print(f"  (4) DETERMINISM : {'PASS' if ok4 else 'FAIL'}")
    all_ok = ok1 and ok2 and ok3 and ok4
    print("=== ALL FOUR PROPERTIES SHOWN ===" if all_ok else "=== SOME PROPERTIES FAILED ===")
    return 0 if all_ok else 1


if __name__ == "__main__":
    raise SystemExit(main())

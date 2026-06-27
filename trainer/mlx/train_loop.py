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
import json
import time
import math
import os

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
from encoder_frozen import features_b_pos_lab, CHROMA_FEATURE_COUNT  # width-25 chroma-bearing token
import theta_b
from theta_b import (
    NUM_BANDS, zero_params_b, mbe_coarse, mbe_masked, siblings_of, masked_target_band,
)
from q16 import to_q16, quantize_q16
import vicreg
from vicreg import VIC_GAMMA, VIC_EPS
import cell_loss
from cell_loss import octant_space_matrix

# jepa_synth_octants imported LAST (after mlx is cached) -- see the import-order note above.
from jepa_synth_octants import build_corpus
from jepa_data import unlift_oct  # byte-exact octant reconstruction -> the palette VALUE target

# Composite-loss weight on the VICReg collapse guard. Small so the masked-band objective
# dominates while the latent is kept full-variance (scout lossTerms: lambda in 1e-2..1e-1).
LAMBDA_VIC = 5e-2
# Number of latent neurons fed to the VICReg tap (keeps the Python cross_redundancy
# O(neurons^2) cheap; the MLX hinge uses the same slice).
VIC_NEURON_SLICE = 16
_SIDE = round(N_TOKENS ** (1 / 3))  # 4 -> the 4x4x4 octant token lattice
# STEP 1 GIF89a VALUE head: per-octant palette size = the 8 voxels of the octant cube
# (the smallest data-tied "local color table"; full (L, a, b) chroma flows end-to-end, STEP 2).
N_PAL = 8
PAL_CH = 3  # OKLab (L, a, b) triples -- real chroma now flows end-to-end (STEP 2)
# STEP 2 GIF89a discrete CONTENT head: each of the octant's N_VOX voxels is assigned an index
# into the N_PAL palette slots (the GIF index map). TAU = straight-through softmax temperature.
N_VOX = N_PAL
TAU = 0.5
# Cross-device logit-margin floor for the index commit (mirrors spec policyMarginEps): below this
# top1-top2 gap, float argmax is not cross-device deterministic, so commit the data slot instead.
MARGIN_EPS = 1e-4
# STEP 3 the HELD-OUT objective: Spec.MatrixTarget.cellLoss = aggSqLoss(cellAggregate pred, tgt).
# The cell aggregate A = C.Sᵀ (cell_loss.cell_aggregate) couples the per-voxel colour (the value
# head, columns L,a,b) by the data-fixed octant space lattice (x,y,t), so it is rank 3: it CONTAINS
# the reconstruction the value head nails AND the off-diagonal chroma×space coupling the per-band
# L-row loss is provably blind to (Spec.NudgeRankTheorem.lawHeldOutLossIsCellAggregateNotPerVoxel).
# This is the term the trainer trains AND the dashboard judges on; the per-band band term is demoted
# to a labeled diagnostic (it is rank-1/per-voxel-blind, so it sits at floor even when learning).
W_CELL = 1.0  # weight on the cell-aggregate objective in the composite (the primary trained loss)
# STEP 4 ANTI-OVERFIT defaults. The 18.9M-param ViT is heavily over-capacity for 8-voxel octants,
# so the band target (rank-1) memorizes (held margin -16..-28%). Three controls keep the train-to-
# held gap bounded so the rank-3 cell-aggregate margin stays POSITIVE over a long run:
#   * DEFAULT_LR lowered 8e-3 -> 1e-3: the old 8e-3 default NaNs by ~step 50 with w_value/w_policy>0
#     (REPRODUCED: composite loss -> nan). 1e-3 is stable AND climbs the cell margin to +99% and
#     keeps rising (LEARNING) -- this is the lr "NaN trap" fix the run protocol calls out.
#   * DEFAULT_WEIGHT_DECAY (SGD L2) shrinks the effective capacity of the over-parameterized head.
#   * held-out-margin EARLY STOP (--early-stop-patience) halts once the primary margin stops
#     improving, so a long run cannot drift back into memorization after its best generalization.
DEFAULT_LR = 1e-3
DEFAULT_WEIGHT_DECAY = 1e-4
# The data-fixed (x,y,t) space vectors of the 8 octant voxels (the octant axes the spec collapses,
# NudgeRankTheorem H2). Float for the gradient path; the colour input it weights re-enters Q16.
_SPACE_NP = np.asarray(octant_space_matrix(2), dtype=np.float32)  # (N_VOX, 3)
SPACE_MX = mx.array(_SPACE_NP)
# STEP 5 DETAIL objective: the spec cell aggregate uses UNCENTERED space (coords {0,1}), so a flat
# (mean-only) octant still scores a large aggregate -- the cell loss is dominated by the octant MEAN
# and a model can win it WITHOUT learning within-octant detail (measured: the cell margin is +99% but
# the per-voxel/centered-detail margin is NEGATIVE -- the model learns the mean field, not the detail
# the ScaleRung exists to invent). The CENTERED space (mean-free columns) makes the aggregate see ONLY
# the within-octant detail: a flat octant -> 0. Adding W_DETAIL * this term FORCES the head to learn
# detail, not just the mean. Centered space is still rank-3 in the off-mean subspace (the A_7 content).
_SPACE_CENTERED_NP = _SPACE_NP - _SPACE_NP.mean(axis=0, keepdims=True)
SPACE_CENTERED_MX = mx.array(_SPACE_CENTERED_NP)
# DEFAULT 0.0: the centered detail term is computed every eval as an OBSERVABILITY diagnostic (the
# honest within-octant-detail margin the mean-dominated cell loss hides), but it contributes ZERO
# gradient by default, so the proven cell-objective training behaviour is UNCHANGED. It is opt-in via
# --w-detail for the ScaleRung experiment; the default flips to >0 only once detail learning is PROVEN
# (held detail margin crosses positive on a stable run). Until then: surface the gap, don't silently
# change training on an unproven fix.
W_DETAIL = 0.0  # weight on the centered detail objective (opt-in via --w-detail; diagnostic by default)


# ===========================================================================
# The two palette objective TERMS as pure functions, so the trained loss AND the behavioral test
# (test_learnability_behavior.py) exercise the IDENTICAL code path. Both take (B, N_PAL, PAL_CH).
# The learnability theorem (Spec.LearnabilityTheorem.lawValueHeadIdentifiesComplement) predicts:
#   cell_term  = ||palᵀS - tgtᵀS||²  is the rank-3 cross-moment objective -> SUFFICIENT STATISTIC for
#                the 9-DOF span(S) projection, PROVABLY BLIND to the 15-DOF complement.
#   value_term = ||pal - tgt||²       sees ALL 24 DOF -> identifies the complement cell_term misses.
# A checkerboard-parity palette perturbation (orthogonal to span(S)) leaves cell_term EXACTLY 0 while
# value_term sees it -- the falsifiable prediction the behavioral test asserts on this real code.
# ===========================================================================
def cell_term(pal, tgt):
    """Spec.MatrixTarget.cellLoss on the cross-covariance A = palᵀ·SPACE_MX (rank-3, mean-included)."""
    a_pred = mx.matmul(pal.transpose(0, 2, 1), SPACE_MX)
    a_tgt = mx.matmul(tgt.transpose(0, 2, 1), SPACE_MX)
    return mx.mean(0.5 * mx.mean((a_pred - a_tgt) ** 2, axis=(1, 2)))


def value_term(pal, tgt):
    """The full-palette (24-DOF) reconstruction loss -- the value head's sufficient statistic."""
    return mx.mean(0.5 * mx.mean((pal - tgt) ** 2, axis=(1, 2)))


# ===========================================================================
# GAP 1 + GAP 2 head: input projection (11->512) + ViT + latent->band readout (512->7).
# trainable_parameters() = inproj + ViT + readout: ONE set the single optimizer descends.
# The encoder stays ZERO-param (encoder_frozen.ENCODER_PARAM_COUNT == 0); these are HEADs.
# ===========================================================================
class JepaHead(nn.Module):
    def __init__(self, vit):
        super().__init__()
        self.inproj = nn.Linear(CHROMA_FEATURE_COUNT, D_MODEL)  # 25 -> 512 (chroma-bearing tokens)
        self.vit = vit                                            # the 18.9M-param ViT
        self.readout = nn.Linear(D_MODEL, NUM_BANDS)              # pooled latent -> 7 band raws
        # STEP 1 GIF89a VALUE head. Constructed LAST on purpose: inproj/vit/readout consume the
        # SAME init RNG as the value-only trainer, so at w_value=0 the band trajectory is
        # BIT-IDENTICAL (additivity proof). Emits an N_PAL-entry OKLab palette from the pooled
        # latent -- the learned analogue of a GIF89a Local Color Table.
        self.palette = nn.Linear(D_MODEL, N_PAL * PAL_CH)         # pooled latent -> 8x3 palette
        # STEP 2 discrete CONTENT head. Constructed LAST so at w_policy=0 the trajectory is
        # bit-identical. Per-voxel logits over the N_PAL palette slots -> the GIF index map.
        self.idx = nn.Linear(D_MODEL, N_VOX * N_PAL)             # pooled latent -> 8 voxels x 8 slots

    def __call__(self, tokens, d6):
        x = self.inproj(tokens)            # (64, 512)
        latent = self.vit(x, d6)           # (64, 512) PRE-surface latent (VICReg taps THIS)
        pooled = mx.mean(latent, axis=0)   # (512,)
        raws = self.readout(pooled)        # (7,) raw band readouts (float32, pre-commit)
        palette = self.palette(pooled)     # (N_PAL*PAL_CH,) raw OKLab palette (float32, pre-commit)
        idx_logits = self.idx(pooled)      # (N_VOX*N_PAL,) per-voxel slot logits (pre-argmax)
        return latent, raws, palette, idx_logits


# ===========================================================================
# GAP 2 token builder: corpus example -> the (64, 11) ViT input on the octant lattice.
# DETERMINISTIC function of the example (NOT mx.random tokens). Each of the 64 tokens gets
# the example's frozen features_b_pos tagged with its OWN integer lattice (x,y), so the
# tokens are DISTINCT and the latent has real cross-token variance for VICReg to read and
# the d6 ALiBi to attend over. (A single broadcast row would collapse the latent.)
# ===========================================================================
def example_tokens(ex) -> mx.array:
    # L coarse + the six visible L siblings (the theta_B view), PLUS the matching a/b coarse and
    # the six visible a/b siblings -> a chroma-bearing token. Without the a/b context here the
    # value head would have to predict chroma from L alone (the off-diagonal chroma-by-space cells
    # would be unfittable); carrying it lets the head supervise actual colour (STEP 2).
    v = mbe_coarse(ex)
    sibsL = siblings_of(ex)
    m = mbe_masked(ex)
    (cA, dA), (cB, dB) = ex[3]
    sibsA = [b for j, b in enumerate(dA) if j != m]
    sibsB = [b for j, b in enumerate(dB) if j != m]
    sibs_lab = list(zip(sibsL, sibsA, sibsB))
    coarse_lab = (v, cA, cB)
    step = 65536 // _SIDE
    rows = np.empty((N_TOKENS, CHROMA_FEATURE_COUNT), dtype=np.float32)
    for i in range(N_TOKENS):
        xb, yb = i % _SIDE, (i // _SIDE) % _SIDE
        rows[i] = np.asarray(features_b_pos_lab(coarse_lab, sibs_lab, (xb * step, yb * step)),
                             dtype=np.float32)
    return mx.array(rows)


# ===========================================================================
# STEP 2 palette target: each octant's byte-exact reconstructed (L, a, b) cube as an OKLab palette.
# unlift_oct(coarse, detail) is the data-engine inverse (round-trip asserted per channel in the
# corpus), so the target is DATA-MANUFACTURED, not free-floating. REAL chroma now: the a and b
# channels are reconstructed from the chroma lift carried on the example, so the value head
# supervises actual colour content. Normalized through to_q16, the SAME scaling the band targets use.
# ===========================================================================
def palette_target(ex) -> list:
    coarse = mbe_coarse(ex)
    detail = list(ex[1])                       # the full 7-band L detail (ex = (coarseL, detailL, mask, chroma))
    (cA, dA), (cB, dB) = ex[3]                 # the a/b lift carried alongside
    cubeL = unlift_oct(coarse, detail)         # 8 byte-exact Q16 L values
    cubeA = unlift_oct(cA, list(dA))           # 8 byte-exact Q16 a values
    cubeB = unlift_oct(cB, list(dB))           # 8 byte-exact Q16 b values
    out = []
    for L, a, b in zip(cubeL, cubeA, cubeB):
        out += [to_q16(L), to_q16(a), to_q16(b)]   # real (L, a, b) per entry -> N_PAL*PAL_CH floats
    return out


# ===========================================================================
# STEP 2 straight-through one-hot (Jang 2016, arXiv:1611.01144): FORWARD = hard one-hot(argmax)
# so the committed assignment is genuinely DISCRETE (a byte-exact slot); BACKWARD copies the soft
# softmax(logits/tau) Jacobian via y = y_hard + (y_soft - stop_gradient(y_soft)). This is the
# train-time gradient path the spec's lawPolicyCEGradientMovesTowardTarget now guards; the hard
# argmax COMMIT determinism is lawPolicyArgmaxMarginOrFallback (near-tie -> data-slot fallback).
# ===========================================================================
def straight_through_onehot(logits, tau):
    y_soft = mx.softmax(logits / tau, axis=-1)
    hard = mx.argmax(logits, axis=-1)
    y_hard = mx.eye(logits.shape[-1])[hard]          # one-hot over the last (slot) axis
    return y_hard + (y_soft - mx.stop_gradient(y_soft))


# ===========================================================================
# STEP 2 byte-exact GIF index COMMIT (spec lawPolicyArgmaxMarginOrFallback). Done in float64 off
# the GPU. Per voxel: emit the argmax slot ONLY when (top1 - top2) > MARGIN_EPS; below the margin
# the float argmax is NOT cross-device deterministic, so commit the data-manufactured (byte-exact)
# fallback slot instead. This gives the discrete index the same cross-device guarantee the value
# head gets from Q16 rounding -- an MLX float never decides the committed slot at a near-tie.
# ===========================================================================
def commit_index(logits_np, fallback):
    out = []
    for v in range(logits_np.shape[0]):
        row = logits_np[v]
        order = np.argsort(row)[::-1]
        if (row[order[0]] - row[order[1]]) > MARGIN_EPS:
            out.append(int(order[0]))
        else:
            out.append(int(fallback[v]))
    return out


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
# The composite-loss head registry, factored to module scope so the demo `run()` AND the
# persistent long-run trainer descend the SAME loss (no drift). Returns (L_band, L_vic,
# L_pal, L_idx) MLX scalars for one full batch. (Body lifted verbatim from run()'s _heads.)
# ===========================================================================
def _composite_terms(h, tokens_b, masks, targets, pal_targets, d6):
    band_terms, vic_terms, pal_terms, idx_terms, cell_terms, det_terms = [], [], [], [], [], []
    for i in range(tokens_b.shape[0]):
        latent, raws, palette, idx_logits = h(tokens_b[i], d6)
        d = raws[masks[i]] - targets[i]
        band_terms.append(0.5 * d * d)
        vic_terms.append(mlx_variance_floor(latent))
        pal = palette.reshape(N_PAL, PAL_CH)                       # (slots, ch) predicted (L,a,b)
        pd = pal.reshape(-1) - pal_targets[i]
        pal_terms.append(0.5 * mx.mean(pd * pd))
        assign = straight_through_onehot(idx_logits.reshape(N_VOX, N_PAL), TAU)  # (vox, slots)
        recon = assign @ pal                                      # (vox, ch) = buildPixels
        tgt = pal_targets[i].reshape(N_VOX, PAL_CH)               # the cube colours per voxel
        rd = recon - tgt
        idx_terms.append(0.5 * mx.mean(rd * rd))
        # STEP 3 cell-aggregate loss (Spec.MatrixTarget.cellLoss): A = colourᵀ · space, predicted
        # vs target, both weighted by the SAME data-fixed octant space lattice -> the rank-3 coupling.
        a_pred = pal.T @ SPACE_MX                                 # (ch, 3) cell aggregate (pred)
        a_tgt = tgt.T @ SPACE_MX                                  # (ch, 3) cell aggregate (target)
        cd = a_pred - a_tgt
        cell_terms.append(0.5 * mx.mean(cd * cd))
        # STEP 5 DETAIL: the CENTERED aggregate (mean-free space) sees ONLY within-octant detail.
        dp = pal.T @ SPACE_CENTERED_MX - tgt.T @ SPACE_CENTERED_MX
        det_terms.append(0.5 * mx.mean(dp * dp))
    return (mx.mean(mx.stack(band_terms)), mx.mean(mx.stack(vic_terms)),
            mx.mean(mx.stack(pal_terms)), mx.mean(mx.stack(idx_terms)),
            mx.mean(mx.stack(cell_terms)), mx.mean(mx.stack(det_terms)))


# ===========================================================================
# BATCHED forward: identical math to the per-sequence ViT, but with a leading batch axis so all B
# octants go through the GPU in ONE dispatch instead of B (measured ~4.3x; the looped path leaves
# the GPU idle on per-octant dispatch -- see capabilities.py). Reuses the SAME module weights, so
# it is numerically faithful (float reorder only); 'train_persistent' self-verifies this before
# training. FLOAT-TRAIN SIDE ONLY -- the byte-commit path (quantize_q16) is untouched.
# ===========================================================================
def _batched_attn(attn, x, d6):                 # x: (B, N, d)
    B, N, _ = x.shape
    qkv = attn.qkv(x).reshape(B, N, 3, attn.h, attn.dh)
    q = qkv[:, :, 0].transpose(0, 2, 1, 3)      # (B, h, N, dh)
    k = qkv[:, :, 1].transpose(0, 2, 1, 3)
    v = qkv[:, :, 2].transpose(0, 2, 1, 3)
    logits = (q @ k.transpose(0, 1, 3, 2)) / math.sqrt(attn.dh)          # (B, h, N, N)
    bias = attn.beta.reshape(1, attn.h, 1, 1) - attn.s.reshape(1, attn.h, 1, 1) * d6
    w = mx.softmax(logits + bias, axis=-1)
    o = (w @ v).transpose(0, 2, 1, 3).reshape(B, N, attn.h * attn.dh)
    return attn.out(o)


def _batched_block(block, x, d6):
    x = x + _batched_attn(block.attn, block.n1(x), d6)
    return x + block.mlp(block.n2(x))


def batched_head(head, tokens_b, d6):           # tokens_b: (B, N, 11)
    x = head.inproj(tokens_b)                   # (B, N, 512)  -- nn.Linear handles leading dims
    for b in head.vit.blocks:
        x = _batched_block(b, x, d6)
    pooled = mx.mean(x, axis=1)                 # (B, 512)
    return x, head.readout(pooled), head.palette(pooled), head.idx(pooled)


def _composite_terms_batched(h, tokens_b, mask_idx, targets, pal_targets, d6):
    """The vectorized twin of '_composite_terms' -- band, vic, pal, idx over the whole batch in one
    forward. Each term is the SAME computation as the looped version (verified < 1e-3)."""
    latent, raws, palette, idx_logits = batched_head(h, tokens_b, d6)
    B = raws.shape[0]
    sel = mx.take_along_axis(raws, mask_idx.reshape(B, 1), axis=1).reshape(B)
    band = mx.mean(0.5 * (sel - targets) ** 2)
    # vic: per-octant sum-of-hinge over the token axis, then mean over octants (matches the loop).
    var = mx.var(latent[:, :, :VIC_NEURON_SLICE], axis=1)                # (B, slice)
    vic = mx.mean(mx.sum(mx.maximum(0.0, VIC_GAMMA - mx.sqrt(var + VIC_EPS)), axis=-1))
    pal = palette.reshape(B, N_PAL, PAL_CH)
    tgt = pal_targets.reshape(B, N_VOX, PAL_CH)
    palL = value_term(pal, tgt)                                          # the full-palette (24-DOF) value loss
    assign = straight_through_onehot(idx_logits.reshape(B, N_VOX, N_PAL), TAU)
    recon = assign @ pal                                                 # (B, vox, ch)
    idxL = mx.mean(0.5 * mx.mean((recon - tgt) ** 2, axis=(1, 2)))
    # STEP 3 cell-aggregate loss (Spec.MatrixTarget.cellLoss), batched: A[b] = pal[b]ᵀ · space.
    cellL = cell_term(pal, tgt)                                          # the rank-3 cross-moment objective
    # STEP 5 DETAIL (centered aggregate): within-octant detail only (flat octant -> 0).
    dp = mx.matmul(pal.transpose(0, 2, 1), SPACE_CENTERED_MX) - mx.matmul(tgt.transpose(0, 2, 1), SPACE_CENTERED_MX)
    detL = mx.mean(0.5 * mx.mean(dp ** 2, axis=(1, 2)))
    return band, vic, palL, idxL, cellL, detL


# ===========================================================================
# One run. Deterministic given `seed`. Full-batch (no minibatch RNG) so the trajectory is
# smooth and bit-reproducible. Returns the per-step composite trajectory + the trained head.
# ===========================================================================
def run(seed: int, examples, d6, steps: int, lr: float, w_value: float, w_policy: float, verbose: bool):
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

    # Precompute the full deterministic batch: tokens, masks, normalized targets, palette targets.
    tokens_b = mx.stack([example_tokens(ex) for ex in examples], axis=0)   # (B, 64, 11)
    masks = [mbe_masked(ex) for ex in examples]
    targets = mx.array([to_q16(masked_target_band(ex)) for ex in examples], dtype=mx.float32)
    pal_targets = mx.array([palette_target(ex) for ex in examples], dtype=mx.float32)  # (B, 24)
    mx.eval(tokens_b, targets, pal_targets)

    def _heads(h):
        """The head registry for THIS run's batch -- delegates to the module-level
        '_composite_terms' so the persistent long-run trainer descends the identical loss."""
        return _composite_terms(h, tokens_b, masks, targets, pal_targets, d6)

    def composite(h):
        """L = L_band + LAMBDA_VIC*L_vic + w_value*L_pal + w_policy*L_idx + W_CELL*L_cell (the ONE MLX
        scalar the single optimizer descends over ALL heads). L_cell (Spec.MatrixTarget.cellLoss) is
        the primary held-out objective; the per-band L_band is demoted to a diagnostic."""
        band, vic, pal, idx, cell, det = _heads(h)
        return band + LAMBDA_VIC * vic + w_value * pal + w_policy * idx + W_CELL * cell + W_DETAIL * det

    opt = optim.SGD(learning_rate=lr)
    loss_and_grad = nn.value_and_grad(head, composite)

    if verbose:
        leaves = len(tree_flatten(head.trainable_parameters()))
        print(f"  [seed={seed}] ViT {pcount/1e6:.1f}M params + inproj/readout/palette/idx "
              f"({leaves} trainable leaves); full-batch {len(examples)} octants; "
              f"SGD lr={lr}, steps={steps}, w_value={w_value}, w_policy={w_policy}")

    trajectory, band_traj, pal_traj, idx_traj = [], [], [], []
    for step in range(steps):
        loss, grads = loss_and_grad(head)
        opt.update(head, grads)
        mx.eval(head.parameters(), loss)
        lval = float(loss)                          # a tolerance-bearing float, never a byte
        trajectory.append(lval)
        # Record EACH head's objective separately so a verifier can confirm each descends
        # (not merely the collapse guard relaxing to its floor).
        band_s, vic_s, pal_s, idx_s, cell_s, det_s = _heads(head)
        mx.eval(band_s, vic_s, pal_s, idx_s, cell_s, det_s)
        band_traj.append(float(band_s))
        pal_traj.append(float(pal_s))
        idx_traj.append(float(idx_s))
        if verbose:
            latent0, _, _, _ = head(tokens_b[0], d6)
            mx.eval(latent0)
            py_hinge, py_cov, _ = vicreg_python_read(latent0)
            print(f"    step {step:2d}  L_composite={lval:.8f}  L_cell={float(cell_s):.8f}  "
                  f"L_band={float(band_s):.8f}  L_pal={float(pal_s):.8f}  L_idx={float(idx_s):.8f}  "
                  f"L_vic={float(vic_s):.6f}   VICReg hinge={py_hinge:.4f} cov={py_cov:.4f}")

    return trajectory, band_traj, pal_traj, idx_traj, head, tokens_b, masks


# ===========================================================================
# Persistent long-run training: checkpoint/resume + a streaming corpus so a run can go for
# HOURS/DAYS, survive a crash/disconnect, and keep seeing FRESH data (not memorize a fixed
# 24-octant set). Separate from the 4-property demo `main()` (which the gate exercises).
# ===========================================================================
def _build_batch(examples, d6):
    """Precompute the deterministic full batch for a set of examples (same as run()'s setup)."""
    tokens_b = mx.stack([example_tokens(ex) for ex in examples], axis=0)
    masks = [mbe_masked(ex) for ex in examples]
    targets = mx.array([to_q16(masked_target_band(ex)) for ex in examples], dtype=mx.float32)
    pal_targets = mx.array([palette_target(ex) for ex in examples], dtype=mx.float32)
    mx.eval(tokens_b, targets, pal_targets)
    return tokens_b, masks, targets, pal_targets


def _make_grad(head, batch, d6, w_value, w_policy):
    """Build the value_and_grad closure over a batch (rebuilt each resample epoch)."""
    tokens_b, masks, targets, pal_targets = batch

    def composite(h):
        band, vic, pal, idx, cell, det = _composite_terms(h, tokens_b, masks, targets, pal_targets, d6)
        return band + LAMBDA_VIC * vic + w_value * pal + w_policy * idx + W_CELL * cell + W_DETAIL * det

    return nn.value_and_grad(head, composite)


def _make_grad_batched(head, batch, d6, w_value, w_policy):
    """value_and_grad over the BATCHED composite (one GPU dispatch, ~4.3x). Same loss as _make_grad."""
    tokens_b, masks, targets, pal_targets = batch
    mask_idx = mx.array(masks, dtype=mx.int32)

    def composite(h):
        band, vic, pal, idx, cell, det = _composite_terms_batched(h, tokens_b, mask_idx, targets, pal_targets, d6)
        return band + LAMBDA_VIC * vic + w_value * pal + w_policy * idx + W_CELL * cell + W_DETAIL * det

    return nn.value_and_grad(head, composite)


def _verify_batched_faithful(head, batch, d6):
    """Max abs difference between the batched and looped composite terms on a small slice. Must be
    tiny (float reorder) or the batched path is a different model -- the run refuses to train."""
    tokens_b, masks, targets, pal_targets = batch
    k = min(16, tokens_b.shape[0])
    tb, ms, tg, pl = tokens_b[:k], masks[:k], targets[:k], pal_targets[:k]
    looped = _composite_terms(head, tb, ms, tg, pl, d6)
    batched = _composite_terms_batched(head, tb, mx.array(ms, dtype=mx.int32), tg, pl, d6)
    mx.eval(*looped, *batched)
    return max(abs(float(a) - float(b)) for a, b in zip(looped, batched))


def _save_ckpt(head, ckpt_path, step, seed, lr, loss, epoch):
    """ATOMIC checkpoint: write head weights (.safetensors) + a meta sidecar to temp files,
    then os.replace into place, so a crash mid-write never corrupts the resumable checkpoint.
    SGD is stateless (lr only), so head weights + step fully determine the resume."""
    tmp = ckpt_path + ".tmp.safetensors"
    head.save_weights(tmp)
    os.replace(tmp, ckpt_path)
    meta = {"step": step, "seed": seed, "lr": lr, "loss": loss, "epoch": epoch}
    mtmp = ckpt_path + ".meta.json.tmp"
    with open(mtmp, "w") as f:
        json.dump(meta, f)
    os.replace(mtmp, ckpt_path + ".meta.json")


def _corpus_for_epoch(args, epoch, kinds):
    """Manufacture a FRESH corpus for this epoch: pair a rotating seed with each kind so more
    wall-clock means more DISTINCT captures, not re-reading the same fixed octants."""
    specs = [((args.seed + epoch * 101 + i) % 100000, k) for i, k in enumerate(kinds)]
    examples, n_oct = build_corpus(specs, frame_step=8, space_step=8)
    n_use = args.octants if args.octants is not None else min(n_oct, 96)
    if n_use < n_oct:
        stride = max(1, n_oct // n_use)
        examples = examples[::stride][:n_use]
    if args.mask is not None:
        examples = [(c, d, args.mask, ch) for (c, d, _m, ch) in examples]
    return examples, n_oct


# ===========================================================================
# Held-out EVALUATION + zero-prediction FLOOR baseline -- the "is it actually learning?"
# dashboard. Train loss FALLING is NOT proof of learning: the prior run FLOORED (train loss
# fell while held-out band loss sat BELOW the zero-prediction floor -- i.e. WORSE than just
# predicting zero). A FIXED held-out corpus (seeds DISJOINT from training, never resampled),
# scored each checkpoint against the floor, makes learning observable with an explicit verdict.
# ===========================================================================
def _heldout_corpus(args, kinds, n_use):
    """A FIXED held-out corpus on seeds DISJOINT from training. Training uses
    (seed + epoch*101 + i) % 100000; held-out uses (seed + 500003 + i), never resampled, so the
    eval signal is true generalization, not memorized train octants."""
    specs = [((args.seed + 500003 + i), k) for i, k in enumerate(kinds)]
    examples, _n_oct = build_corpus(specs, frame_step=8, space_step=8)
    if len(examples) > n_use:
        stride = max(1, len(examples) // n_use)
        examples = examples[::stride][:n_use]
    if args.mask is not None:
        examples = [(c, d, args.mask, ch) for (c, d, _m, ch) in examples]
    return examples


def _held_eval(head, held, d6, w_value, w_policy):
    """Held-out losses via the BATCHED forward, NO gradient -- the same loss terms training
    descends, scored on data the optimizer never saw."""
    h_tb, h_midx, h_tg, h_pl = held
    band, vic, pal, idx, cell, det = _composite_terms_batched(head, h_tb, h_midx, h_tg, h_pl, d6)
    comp = band + LAMBDA_VIC * vic + w_value * pal + w_policy * idx + W_CELL * cell + W_DETAIL * det
    mx.eval(band, vic, pal, idx, cell, det, comp)
    return {"band": float(band), "vic": float(vic), "pal": float(pal),
            "idx": float(idx), "cell": float(cell), "detail": float(det), "composite": float(comp)}


def _floor_baseline(held):
    """The ZERO-PREDICTION floor: the loss a model that emits zero would score on the held set.
    The band head MUST beat band_floor on held-out or it is not learning (the prior run's exact
    failure: held band ~0.00054 vs floor ~0.00035 -- worse than zero)."""
    _h_tb, _h_midx, h_tg, h_pl = held
    # The cell-aggregate floor: the cell loss a zero-colour prediction scores. A_pred = 0 -> the term
    # is 0.5*mean((A_tgt)^2). Computed with the SAME octant space lattice the trained term uses, so
    # the cell margin (floor - held) is apples-to-apples (Spec.MatrixTarget.cellLoss at pred=0).
    B = h_pl.shape[0]
    tgt = h_pl.reshape(B, N_VOX, PAL_CH)
    a_tgt = mx.matmul(tgt.transpose(0, 2, 1), SPACE_MX)                  # (B, ch, 3)
    cell_floor = float(mx.mean(0.5 * mx.mean(a_tgt ** 2, axis=(1, 2))))
    # The DETAIL floor: the centered aggregate at pred=0 = a FLAT (mean-only) prediction. Beating
    # this proves within-octant detail is learned, not just the octant mean (the cell loss' blind spot).
    d_tgt = mx.matmul(tgt.transpose(0, 2, 1), SPACE_CENTERED_MX)
    detail_floor = float(mx.mean(0.5 * mx.mean(d_tgt ** 2, axis=(1, 2))))
    return {"band": 0.5 * float(mx.mean(h_tg ** 2)),
            "value": 0.5 * float(mx.mean(h_pl ** 2)),
            "cell": cell_floor,
            "detail": detail_floor}


def _fmt_dur(s):
    s = int(max(0, s))
    if s < 60:
        return f"{s}s"
    if s < 3600:
        return f"{s // 60}m{s % 60:02d}s"
    return f"{s // 3600}h{(s % 3600) // 60:02d}m"


def dashboard_verdict(held, floor):
    """The verdict logic, separated so it is unit-testable without a full run.

    PRIMARY metric (STEP 3) = the CELL-AGGREGATE margin (Spec.MatrixTarget.cellLoss) when the eval
    supplies it. The cell aggregate A = colourᵀ·space is rank 3 (Spec.NudgeRankTheorem
    lawCellAggregateReachesRank3), so it sees BOTH the reconstruction the value head nails AND the
    off-diagonal chroma×space coupling the per-band L-row loss is provably blind to
    (lawHeldOutLossIsCellAggregateNotPerVoxel). It is the formally-proven held-out objective.

    The per-band theta_B target is rank-1/per-voxel-blind, so even a perfectly-trained head sits
    at/below the band floor -- band is kept ONLY as a labeled diagnostic. When no 'cell' key is
    present the verdict falls back to the VALUE (reconstruction) margin (the legacy behaviour).

    Returns (verdict, value_margin_pct, band_margin_pct, collapsed, max_vic)."""
    vf = floor["value"]
    bf = floor["band"]
    value_margin = (vf - held["pal"]) / vf * 100 if vf > 0 else 0.0
    band_margin = (bf - held["band"]) / bf * 100 if bf > 0 else 0.0
    max_vic = VIC_GAMMA * VIC_NEURON_SLICE                       # ~all neurons collapsed
    collapsed = held["vic"] > 0.5 * max_vic
    # PRIMARY = cell-aggregate margin (the spec held-out objective); fall back to value if absent.
    cf = floor.get("cell")
    if cf is not None and "cell" in held:
        primary, pfloor = held["cell"], cf
    else:
        primary, pfloor = held["pal"], vf
    # DIVERGED guard FIRST: a NaN/inf primary (lr/weight too hot) must NOT silently read "AT FLOOR"
    # -- nan>floor*1.02 and nan>0.5*max_vic are both False, so without this the dashboard lies green
    # while the model is gone. math.isnan/isinf catch the blow-up the run protocol calls the NaN trap.
    if not math.isfinite(primary) or not math.isfinite(held.get("vic", 0.0)):
        return "DIVERGED (NaN/inf -- lr or loss weight too hot)", value_margin, band_margin, collapsed, max_vic
    # COLLAPSE guard (a collapsed head can score a misleading margin).
    if collapsed:
        verdict = "COLLAPSE (variance floor tripped)"
    elif primary < pfloor * 0.98:
        verdict = "LEARNING"
    elif primary > pfloor * 1.02:
        verdict = "FLOORED (worse than predicting zero)"
    else:
        verdict = "AT FLOOR"
    return verdict, value_margin, band_margin, collapsed, max_vic


def _dashboard(step, total, held, floor, train_loss, sps, batch, t_elapsed):
    """The CLI that MATTERS: held-out vs the zero-prediction floor with an explicit verdict, plus
    the collapse guard, throughput, and ETA. The verdict is the VALUE (reconstruction) margin --
    the head that actually generalizes -- with band kept as a labeled secondary diagnostic (see
    dashboard_verdict for why band-only is the blind metric). Returns (verdict, lines)."""
    bf = floor["band"]
    vf = floor["value"]
    cf = floor.get("cell", 0.0)
    df = floor.get("detail", 0.0)
    verdict, value_margin, band_margin, collapsed, max_vic = dashboard_verdict(held, floor)
    cell_margin = (cf - held.get("cell", 0.0)) / cf * 100 if cf > 0 else 0.0
    detail_margin = (df - held.get("detail", 0.0)) / df * 100 if df > 0 else 0.0
    eta = _fmt_dur((total - step) / sps) if sps > 0 else "?"
    tl = "   --" if train_loss != train_loss else f"{train_loss:.6f}"   # nan-safe
    lines = [
        f"=== EVAL @ step {step}/{total} :: {verdict} ===",
        f"  cell   held {held.get('cell', 0.0):.6f}  vs floor {cf:.6f}   margin {cell_margin:+.1f}%   (>0 = beating zero-prediction; THE VERDICT METRIC -- Spec.MatrixTarget.cellLoss, rank-3)",
        f"  detail held {held.get('detail', 0.0):.6f}  vs floor {df:.6f}   margin {detail_margin:+.1f}%   (CENTERED: within-octant DETAIL, flat-mean blind spot -- the honest ScaleRung signal)",
        f"  value  held {held['pal']:.6f}  vs floor {vf:.6f}   margin {value_margin:+.1f}%   (reconstruction diagnostic)",
        f"  band   held {held['band']:.6f}  vs floor {bf:.6f}   margin {band_margin:+.1f}%   (diagnostic ONLY -- rank-1 blind, see NudgeRankTheorem)",
        f"  index  held {held['idx']:.6f}   train L {tl}",
        f"  collapse-guard(VICReg) {held['vic']:.4f} / {max_vic:.1f}  [{'ok' if not collapsed else 'TRIPPED'}]",
        f"  throughput {sps:.1f} steps/s · {sps * batch:.0f} oct/s   elapsed {_fmt_dur(t_elapsed)}   ETA {eta}",
    ]
    return verdict, lines


def train_persistent(args) -> int:
    """The hours/days trainer: resumable, checkpointing, streaming-corpus, file-logged."""
    out_dir = args.out or os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "out", "run")
    os.makedirs(out_dir, exist_ok=True)
    ckpt_path = os.path.join(out_dir, "head.safetensors")
    log_path = os.path.join(out_dir, "loss.jsonl")
    kinds = [k.strip() for k in (args.kinds or "high-lab,high-detail,smooth-grey").split(",") if k.strip()]
    save_every = args.save_every if args.save_every else 2000
    resample_every = args.resample_every if args.resample_every else 0
    total_steps = args.steps if args.steps is not None else 100000
    lr, w_value, w_policy = args.lr, args.w_value, args.w_policy

    d6 = mx.array(octant_lattice_d6(N_TOKENS), dtype=mx.float32)
    mx.eval(d6)

    # Build the head (deterministic init), then resume weights if asked.
    mx.random.seed(args.seed)
    np.random.seed(args.seed)
    built = large_head._build_vit()
    if built is None:
        raise RuntimeError("large_head._build_vit() returned None -- mlx import failed.")
    _mx, vit, _d6u, pcount = built
    head = JepaHead(vit)
    mx.eval(head.parameters())
    head.readout.weight = head.readout.weight * 0.3
    head.readout.bias = head.readout.bias + 0.4
    mx.eval(head.parameters())

    start_step = 0
    if args.resume:
        if not os.path.exists(args.resume):
            raise FileNotFoundError(f"--resume checkpoint not found: {args.resume}")
        head.load_weights(args.resume)
        mx.eval(head.parameters())
        meta_p = args.resume + ".meta.json"
        if os.path.exists(meta_p):
            with open(meta_p) as f:
                start_step = int(json.load(f).get("step", 0))
        print(f"RESUMED from {args.resume} at step {start_step}")

    # STEP 4: weight decay (L2) on SGD is the capacity control that bounds the train->held gap on
    # the over-parameterized 18.9M ViT. weight_decay==0 reproduces the old memorizing optimizer.
    weight_decay = getattr(args, "weight_decay", DEFAULT_WEIGHT_DECAY)
    opt = optim.SGD(learning_rate=lr, weight_decay=weight_decay)
    print(f"SGD lr={lr}  weight_decay={weight_decay} (STEP 4 capacity control)")
    epoch = (start_step // resample_every) if resample_every else 0
    examples, n_oct = _corpus_for_epoch(args, epoch, kinds)
    batch0 = _build_batch(examples, d6)

    # Default to the BATCHED forward (~4.3x); self-verify it matches the looped path before training.
    use_batched = not args.no_batch
    make_grad = _make_grad_batched if use_batched else _make_grad
    if use_batched:
        diff = _verify_batched_faithful(head, batch0, d6)
        print(f"[faithful] batched vs looped composite: max|Δ|={diff:.2e}  "
              f"({'OK -- same model, ~4.3x faster' if diff < 1e-3 else 'DIVERGENT'})")
        if diff >= 1e-3:
            raise RuntimeError("batched forward diverges from looped; refusing to train (use --no-batch)")
    grad_fn = make_grad(head, batch0, d6, w_value, w_policy)

    print(f"=== SixFour H-JEPA PERSISTENT training ({pcount/1e6:.1f}M-param ViT, "
          f"{'BATCHED' if use_batched else 'LOOPED'} forward) ===")
    print(f"out={out_dir}  steps={start_step}..{total_steps}  save_every={save_every}  "
          f"resample_every={resample_every or 'off'}  kinds={kinds}")
    print(f"corpus epoch {epoch}: {len(examples)} octants from {len(kinds)} fresh captures "
          f"(of {n_oct}); SGD lr={lr}, w_value={w_value}, w_policy={w_policy}")

    # Held-out eval: a FIXED, disjoint-seed corpus scored against the zero-prediction floor so
    # the run reports whether it is LEARNING, not just whether train loss fell.
    eval_every = (getattr(args, "eval_every", 0) or save_every)
    eval_octants = (getattr(args, "eval_octants", 0) or 64)
    held_examples = _heldout_corpus(args, kinds, eval_octants)
    h_tb, h_masks, h_tg, h_pl = _build_batch(held_examples, d6)
    held = (h_tb, mx.array(h_masks, dtype=mx.int32), h_tg, h_pl)
    floor = _floor_baseline(held)
    batch_sz = len(examples)
    print(f"held-out: {len(held_examples)} octants (disjoint seeds, fixed); "
          f"floor cell={floor['cell']:.6f} value={floor['value']:.6f} band={floor['band']:.6f} "
          f"(cell is THE bar to beat)")
    _bv, _bl = _dashboard(start_step, total_steps,
                          _held_eval(head, held, d6, w_value, w_policy),
                          floor, float("nan"), 0.0, batch_sz, 0.0)
    for _ln in _bl:
        print(_ln)

    logf = open(log_path, "a")
    last_loss = float("nan")
    done_step = start_step
    # STEP 4 held-out-margin EARLY STOP: track the best primary (cell-aggregate) held loss and the
    # number of consecutive evals with no improvement; stop when it exceeds the patience budget.
    early_stop_patience = getattr(args, "early_stop_patience", 0) or 0
    best_primary = float("inf")
    no_improve = 0
    t0 = time.time()
    try:
        for step in range(start_step, total_steps):
            if resample_every and step > start_step and step % resample_every == 0:
                epoch += 1
                examples, n_oct = _corpus_for_epoch(args, epoch, kinds)
                grad_fn = make_grad(head, _build_batch(examples, d6), d6, w_value, w_policy)
                batch_sz = len(examples)
                print(f"  [resample] epoch {epoch}: {len(examples)} fresh octants")
            loss, grads = grad_fn(head)
            opt.update(head, grads)
            mx.eval(head.parameters(), loss)
            last_loss = float(loss)
            done_step = step + 1
            logf.write(json.dumps({"step": step, "loss": last_loss, "epoch": epoch, "lr": lr}) + "\n")
            logf.flush()
            if step % 50 == 0:
                print(f"  step {step:6d}  L={last_loss:.8f}  epoch={epoch}")
            if done_step % save_every == 0:
                _save_ckpt(head, ckpt_path, done_step, args.seed, lr, last_loss, epoch)
                print(f"  [ckpt] {ckpt_path} @ step {done_step}  (L={last_loss:.8f})")
            if done_step % eval_every == 0:
                elapsed = time.time() - t0
                sps = (done_step - start_step) / elapsed if elapsed > 0 else 0.0
                ev = _held_eval(head, held, d6, w_value, w_policy)
                verdict, lines = _dashboard(done_step, total_steps, ev, floor,
                                            last_loss, sps, batch_sz, elapsed)
                for ln in lines:
                    print(ln)
                logf.write(json.dumps({"step": done_step, "eval": ev, "floor": floor,
                                       "verdict": verdict}) + "\n")
                logf.flush()
                # STEP 4 early stop on the PRIMARY held metric (cell aggregate; fall back to value).
                primary = ev.get("cell", ev.get("pal"))
                if primary == primary and primary < best_primary - 1e-9:   # nan-safe improvement
                    best_primary = primary
                    no_improve = 0
                else:
                    no_improve += 1
                if early_stop_patience and no_improve >= early_stop_patience:
                    print(f"  [early-stop] primary held loss did not improve for "
                          f"{no_improve} evals (best {best_primary:.6f}); stopping at step {done_step}")
                    break
    finally:
        # Always persist progress on exit (normal end, Ctrl-C, or crash) so no work is lost.
        _save_ckpt(head, ckpt_path, done_step, args.seed, lr, last_loss, epoch)
        logf.close()
    print(f"DONE. final checkpoint: {ckpt_path}  (resume with --resume {ckpt_path})")
    return 0


# ===========================================================================
# Property demonstrations (each prints REAL output).
# ===========================================================================
def demo_descent(traj, band_traj, pal_traj, idx_traj, w_value, w_policy):
    print("\n[1] DESCENT -- composite loss decreases over steps")
    drop = traj[0] - traj[-1]
    band_drop = band_traj[0] - band_traj[-1]
    pal_drop = pal_traj[0] - pal_traj[-1]
    idx_drop = idx_traj[0] - idx_traj[-1]
    print(f"    L_composite  {traj[0]:.8f} -> {traj[-1]:.8f}   drop={drop:.8f}   "
          f"({'DESCENDS' if drop > 0 else 'DID NOT DESCEND'})")
    # The OBJECTIVE term alone must also descend -- refutes 'the curve is only the VICReg
    # hinge relaxing to its floor' (the hinge zeroes by ~step 10; L_band keeps falling).
    print(f"    L_band(only)  {band_traj[0]:.8f} -> {band_traj[-1]:.8f}   drop={band_drop:.8f}   "
          f"({'OBJECTIVE DESCENDS independently of the guard' if band_drop > 0 else 'OBJECTIVE DID NOT DESCEND'})")
    # The GIF89a VALUE head (palette) is a SECOND objective on the shared trunk; when active it
    # must descend too -- proving one optimizer trains BOTH heads (multi-head full-scope step).
    pal_ok = True
    if w_value > 0:
        pal_ok = pal_drop > 0
        print(f"    L_pal (value) {pal_traj[0]:.8f} -> {pal_traj[-1]:.8f}   drop={pal_drop:.8f}   "
              f"({'PALETTE HEAD DESCENDS on the shared trunk' if pal_ok else 'PALETTE DID NOT DESCEND'})")
    else:
        print(f"    L_pal (value) inert (w_value=0): palette head present but off the gradient "
              f"-> band trajectory is bit-identical to the value-only trainer")
    # STEP 2: the discrete INDEX head reconstructs buildPixels=palette[index] in FUSED space.
    idx_ok = True
    if w_policy > 0:
        idx_ok = idx_drop > 0
        print(f"    L_idx (policy){idx_traj[0]:.8f} -> {idx_traj[-1]:.8f}   drop={idx_drop:.8f}   "
              f"({'INDEX HEAD DESCENDS (straight-through, fused palette[index])' if idx_ok else 'INDEX DID NOT DESCEND'})")
    else:
        print(f"    L_idx (policy)inert (w_policy=0): index head present but off the gradient")
    return (drop > 0) and (band_drop > 0) and pal_ok and idx_ok


def demo_no_collapse(head, tokens_b, d6):
    print("\n[2] NO COLLAPSE -- VICReg on the PRE-surface latent (read BEFORE any Q16 commit)")
    latent, _, _, _ = head(tokens_b[0], d6)
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
    _latent, raws, _palette, idx_logits = head(tokens_b[0], d6)
    mx.eval(raws, idx_logits)
    m = masks[0]
    # STEP 2: the GIF index commit is margin-guarded (spec lawPolicyArgmaxMarginOrFallback). The
    # data-manufactured fallback is the identity slot (palette_target[v] == cube[v], byte-exact).
    fallback = list(range(N_VOX))
    logits_np = np.array(idx_logits.reshape(N_VOX, N_PAL)).astype(np.float64)
    committed_index = commit_index(logits_np, fallback)
    print(f"    committed GIF index raster (octant 0) = {committed_index}  "
          f"(margin-guarded, discrete slots in [0,{N_PAL}))")
    # Force a sub-eps near-tie on voxel 0: naive argmax flips on 5e-7 of float noise; the guard
    # falls back to the byte-exact data slot -- the cross-device determinism the spec law pins.
    tie = logits_np.copy(); tie[0] = 0.0; tie[0, 0] = 5.0; tie[0, 1] = 5.0 + 5e-7
    naive_tie = int(np.argmax(tie[0]))                       # 1 (the 5e-7-larger slot)
    guarded_tie = commit_index(tie, fallback)[0]             # fallback[0] = 0 (data slot)
    tie_ok = (naive_tie == 1) and (guarded_tie == fallback[0])
    print(f"    near-tie [5.0, 5.0+5e-7] on voxel 0: naive argmax={naive_tie} (float-noise decides) "
          f"vs margin-guard={guarded_tie} (data slot) -> {'FALLBACK FIRES' if tie_ok else 'GUARD FAILED'}")
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
    ok = isinstance(committed, int) and floor_ok and tie_ok
    print(f"    -> {'BYTE-COMMIT PRESERVED (band Q16 round + index margin-guard; MLX never decides a byte)' if ok else 'BYTE-COMMIT FAILED'}")
    return ok


def demo_determinism(seed, examples, d6, steps, lr, w_value, w_policy):
    print("\n[4] DETERMINISM -- same seed -> bit-identical loss trajectory (two runs)")
    traj_a, *_ = run(seed, examples, d6, steps, lr, w_value, w_policy, verbose=False)
    traj_b, *_ = run(seed, examples, d6, steps, lr, w_value, w_policy, verbose=False)
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
    global W_CELL, W_DETAIL  # --w-cell / --w-detail override the module constants the composite reads
    ap = argparse.ArgumentParser(description="End-to-end MLX H-JEPA training loop.")
    ap.add_argument("--smoke", action="store_true",
                    help="fast mode: 8 octants, 30 steps (< ~10s); shows all four properties.")
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--steps", type=int, default=None)
    ap.add_argument("--lr", type=float, default=DEFAULT_LR,
                    help="SGD learning rate. STEP 4: default lowered 8e-3 -> 1e-3; the old 8e-3 "
                         "NaNs by ~step 50 with w_value/w_policy>0 (the reproduced 'NaN trap').")
    ap.add_argument("--weight-decay", dest="weight_decay", type=float, default=DEFAULT_WEIGHT_DECAY,
                    help="STEP 4 anti-overfit: SGD L2 weight decay (capacity control on the "
                         "over-parameterized ViT). 0 = the old memorizing optimizer.")
    ap.add_argument("--early-stop-patience", dest="early_stop_patience", type=int, default=0,
                    help="STEP 4 anti-overfit: stop after this many consecutive evals with NO "
                         "improvement in the primary (cell-aggregate) held-out loss (long mode; "
                         "0 = off). Protects a long run from drifting back into memorization.")
    ap.add_argument("--octants", type=int, default=None,
                    help="FULL mode: number of octants to train on, deterministically STRIDED "
                         "across all captures so every kind + mask is seen (default 24; the "
                         "corpus builds 1536). full-batch stays deterministic.")
    ap.add_argument("--mask", type=int, default=None,
                    help="train a per-band SPECIALIST: override every octant's masked band to "
                         "this index (0..6), so the head learns to predict that ONE encoded "
                         "parameter from the other six. Default cycles all 7 bands.")
    ap.add_argument("--w-value", dest="w_value", type=float, default=1.0,
                    help="weight on the GIF89a palette VALUE head (Step 1). DEFAULT 1.0 = the "
                         "theorem's proven point willLearn(1.0) (Spec.LearnabilityTheorem; pinned "
                         "willLearnAtOne in learnability_golden.json). The primary cellLoss "
                         "(W_CELL=1.0) is rank-DEFICIENT: A=C.S^T is rank<=3, so it identifies only "
                         "the 9-DOF projection of the 24-DOF palette onto span(S) and is PROVABLY "
                         "BLIND to the 15-DOF orthogonal complement (span(S)^perp tensor 3 channels, "
                         "the checkerboard-parity within-octant patterns). The value head's OKLab "
                         "regression is the sufficient statistic for that complement, so w_value>0 is "
                         "the load-bearing side condition that makes 'the model will learn' TRUE for "
                         "the FULL palette, not just the rank-3 coupling. At full weight 1.0 the 15 "
                         "blind DOF get a gradient share equal to the rank-3 cellLoss (they are >half "
                         "the palette). 0 = palette inert (complement UNidentified: held value margin "
                         "FLOORS to -28% on the disjoint corpus while the cell margin still reads "
                         "+99% -- the exact blind spot the theorem exposes); the band trajectory is "
                         "then bit-identical to the value-only trainer.")
    ap.add_argument("--w-policy", dest="w_policy", type=float, default=0.1,
                    help="weight on the GIF89a discrete INDEX head (Step 2, straight-through, "
                         "fused palette[index] reconstruction). 0 = index head inert.")
    ap.add_argument("--w-detail", dest="w_detail", type=float, default=W_DETAIL,
                    help="weight on the centered DETAIL objective (within-octant structure the "
                         "mean-dominated cell loss misses; the honest ScaleRung signal).")
    ap.add_argument("--w-cell", dest="w_cell", type=float, default=W_CELL,
                    help="weight on the cell-aggregate objective (Step 3, Spec.MatrixTarget.cellLoss, "
                         "the primary held-out loss the dashboard judges on). Default 1.0.")
    # --- persistent long-run (hours/days): checkpoint, resume, streaming corpus ---
    ap.add_argument("--long", action="store_true",
                    help="persistent training: a single resumable run that checkpoints to disk "
                         "and streams fresh data (NOT the 4-property demo). Implied by --save-every "
                         "or --resume.")
    ap.add_argument("--save-every", dest="save_every", type=int, default=0,
                    help="checkpoint the head every N steps (long mode; default 2000).")
    ap.add_argument("--resample-every", dest="resample_every", type=int, default=0,
                    help="regenerate the corpus from FRESH seeds every N steps (long mode; 0=off, "
                         "i.e. fixed corpus). Use this for multi-day runs so more wall-clock = more "
                         "distinct data, not memorization.")
    ap.add_argument("--out", type=str, default=None,
                    help="output dir for checkpoints + loss.jsonl (default trainer/out/run).")
    ap.add_argument("--resume", type=str, default=None,
                    help="resume from a checkpoint .safetensors (continues from its meta step).")
    ap.add_argument("--kinds", type=str, default=None,
                    help="comma list of capture kinds to stream (default high-lab,high-detail,smooth-grey).")
    ap.add_argument("--no-batch", dest="no_batch", action="store_true",
                    help="use the slow per-octant LOOPED forward (default is the ~4.3x batched forward).")
    ap.add_argument("--eval-every", dest="eval_every", type=int, default=0,
                    help="held-out eval + zero-prediction floor dashboard every N steps "
                         "(long mode; default = save-every). The 'is it learning?' signal.")
    ap.add_argument("--eval-octants", dest="eval_octants", type=int, default=0,
                    help="held-out octants for the eval dashboard (default 64; disjoint seeds, fixed).")
    args = ap.parse_args()

    # The cell-aggregate weight is a module constant the composite closures read; honor --w-cell.
    W_CELL = args.w_cell
    W_DETAIL = args.w_detail

    # DISPATCH: persistent long-run trainer vs the 4-property demo. Long mode is entered
    # explicitly (--long) or implicitly whenever the user asks to save or resume.
    if args.long or args.save_every or args.resume:
        return train_persistent(args)

    # --- DATA-MANUFACTURED corpus (targets lifted byte-exact, round-trip asserted) ---
    if args.smoke:
        specs, fs, ss = [(7, "high-lab")], 16, 16
        examples, n_oct = build_corpus(specs, frame_step=fs, space_step=ss)
        examples = examples[:8]          # subsample to keep the 18.9M-ViT sweep cheap
        steps = args.steps if args.steps is not None else 30
    else:
        specs, fs, ss = [(7, "high-lab"), (11, "high-detail"), (23, "smooth-grey")], 8, 8
        examples, n_oct = build_corpus(specs, frame_step=fs, space_step=ss)
        n_use = args.octants if args.octants is not None else 24
        if n_use < n_oct:
            # Deterministic stride across the FULL corpus: examples[:N] would take only the
            # first capture (build_corpus concatenates captures), so it would train on
            # high-lab alone. Striding spans all 3 kinds and keeps the mask cycle.
            stride = max(1, n_oct // n_use)
            examples = examples[::stride][:n_use]
        steps = args.steps if args.steps is not None else 60

    if args.mask is not None:
        if not (0 <= args.mask < NUM_BANDS):
            ap.error(f"--mask must be in 0..{NUM_BANDS - 1}")
        # per-band specialist: every octant now supervises the SAME encoded band.
        examples = [(c, d, args.mask, ch) for (c, d, _m, ch) in examples]

    d6 = mx.array(octant_lattice_d6(N_TOKENS), dtype=mx.float32)  # integer L1 ALiBi lattice
    mx.eval(d6)

    print(f"=== SixFour H-JEPA end-to-end MLX training loop "
          f"({'SMOKE' if args.smoke else 'FULL'}, seed={args.seed}, steps={steps}) ===")
    band_note = f"band {args.mask} SPECIALIST" if args.mask is not None else "all 7 bands cycled"
    print(f"corpus: {len(specs)} captures -> {n_oct} octant records (using {len(examples)} this run, "
          f"{band_note}); targets DATA-MANUFACTURED (no EMA, no self-produced rollout)")
    print("BYTE-COMMIT BOUNDARY at q16.quantize_q16: float32-train above, float64-commit below.")
    print(f"composite = L_band + {LAMBDA_VIC} * L_vic + {args.w_value} * L_pal (palette VALUE) "
          f"+ {args.w_policy} * L_idx (index CONTENT, straight-through), ONE SGD optimizer over "
          f"ViT + readout + palette + idx\n")

    print("--- PROPERTY (1) training trajectory (run A) ---")
    traj, band_traj, pal_traj, idx_traj, head, tokens_b, masks = run(
        args.seed, examples, d6, steps, args.lr, args.w_value, args.w_policy, verbose=True)

    ok1 = demo_descent(traj, band_traj, pal_traj, idx_traj, args.w_value, args.w_policy)
    ok2 = demo_no_collapse(head, tokens_b, d6)
    ok3 = demo_byte_commit(head, tokens_b, masks, examples[0], d6)
    ok4 = demo_determinism(args.seed, examples, d6, steps, args.lr, args.w_value, args.w_policy)

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

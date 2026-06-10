"""atlas_net_mlx.py — the Color Atlas policy/value heads over the Look-NN backbone.

PROTOTYPE (hand-written; the shipped version is emitted by spec-codegen as
trainer/generated/atlas_net_mlx.py once the Haskell AtlasOracle/DeltaCodebook
modules exist — doc §7). Mirrors docs/COLOR-ATLAS.md §4.2:

  • Backbone reuse: the existing L3–L5 MLX graph (generated/look_net_mlx.py).
    Board tokens enter through the masked L3/L4 pathway — NO conv trunk
    (P1's Conv3d was rejected for violating σ-equivariance).
  • φ′ token-column extension: tokens are 13-D (10 base GMM dims through the
    existing σ-masked phi + 3 σ-INVARIANT curation scalars through a new
    3→64 column block masked onto the 22 achromatic hidden dims only).
  • Genome encoder 384→64, σ-masked with the TRANSPOSED SIGMA_DECODER_MASK
    structure — the node's own genome conditions the policy, so priors vary
    across the search tree (the P0 constant-prior defect resolution).
  • Fused ctx [128] = 64 board ‖ 64 genome, each split 22 achro / 21 rg / 21 by.
  • Node head 24→127 and value head 24→32→1 read the σ-INVARIANT projection
    (22 summed achro dims ++ ‖rg‖² ++ ‖by‖²) — invariant by construction.
  • Delta head 128→12 with the σ-pair row-swap constraint: 6×128 free rows,
    odd rows = even rows with chroma dims sign-flipped, so
    delta_logit[2i+1](s) = delta_logit[2i](σs) algebraically.
  • Policy over the 1,524-move vocab factorises: logits[slot*12+δ] =
    node[slot] + delta[δ].

σ-masks are applied at CALL time on raw stored weights (the house pattern).
"""
from __future__ import annotations

import sys
from pathlib import Path

import mlx.core as mx
import mlx.nn as nn

sys.path.insert(0, str(Path(__file__).resolve().parent / "generated"))
import look_net_mlx as ln  # noqa: E402  — the frozen-contract backbone

# ── Pinned dimensions (doc §2 tensor table) ────────────────────────────────
ATLAS_TOKEN_DIM = 13
TOKEN_EXT_DIM = 3              # the φ′ extension columns (σ-invariant)
CTX_DIM = 2 * ln.MODEL_DIM     # 128 = 64 board ‖ 64 genome
INV_PROJ_DIM = ln.HIDDEN_ACHROMATIC_DIM + 2   # 24 σ-invariant features
N_SLOTS = 127                  # addressable Haar slots (root unaddressable)
N_DELTAS = 12                  # deltaCodebook rows
N_VOCAB = N_SLOTS * N_DELTAS   # 1,524

_A = ln.HIDDEN_ACHROMATIC_DIM            # 22
_RG_END = _A + ln.HIDDEN_REDGREEN_DIM    # 43

# φ′ extension mask: σ-invariant inputs may feed ONLY the σ-fixed (achromatic)
# hidden dims — extends GMM_TOKEN_SIGMA_MASK with 3 fixed entries, preserving
# the lookNetSigmaTheorem composition.
_EXT_MASK = ln._block_diagonal_mask([False] * TOKEN_EXT_DIM, ln.SIGMA64_MASK)
# Genome encoder mask: transposed SIGMA_DECODER_MASK structure (384 → 64).
_GENC_MASK = ln._block_diagonal_mask(ln.SIGMA_DECODER_MASK, ln.SIGMA64_MASK)
# Sign of each fused-ctx dim under σ: +1 achromatic, −1 chromatic, ×2 halves.
_CTX_SIGN = mx.array(([1.0] * _A + [-1.0] * (ln.MODEL_DIM - _A)) * 2)


class DeltaHead(nn.Module):
    """128→12 with σ-pair row tying: stored weight is (6,128); the full 12-row
    weight interleaves [w_i, w_i⊙ctx_sign], so odd-row logits on s equal
    even-row logits on σs (row-swap equivariance, 768 free params)."""

    def __init__(self):
        super().__init__()
        self.half = nn.Linear(CTX_DIM, N_DELTAS // 2, bias=False)

    def __call__(self, ctx):                            # (B,128) → (B,12)
        w = self.half.weight                            # (6,128)
        full = mx.stack([w, w * _CTX_SIGN], axis=1).reshape(N_DELTAS, CTX_DIM)
        return ctx @ full.T


class AtlasNet(nn.Module):
    """Board tokens + genome → fused ctx → (policy logits over 1,524, value)."""

    def __init__(self):
        super().__init__()
        self.backbone = ln.LookNet()                    # L3 phi + L4 recursion (+L5, unused here)
        self.phi_ext = nn.Linear(TOKEN_EXT_DIM, ln.MODEL_DIM, bias=False)
        self.genome_enc = nn.Linear(ln.SIGMA_PAIR_DOF, ln.MODEL_DIM, bias=False)
        self.node_head = nn.Linear(INV_PROJ_DIM, N_SLOTS, bias=False)
        self.delta_head = DeltaHead()
        self.v1 = nn.Linear(INV_PROJ_DIM, 32)
        self.v2 = nn.Linear(32, 1)

    # ── board pathway: φ′ (masked) → weighted sum-pool → L4 recursion ──────
    def board_context(self, tokens, weights):
        """tokens (B,T,13), weights (B,T) Σ=1 → (B,64) recursion context."""
        base, ext = tokens[..., :10], tokens[..., 10:]
        w_phi = self.backbone.encoder.phi.weight * ln._PHI_MASK
        w_ext = self.phi_ext.weight * _EXT_MASK
        h = base @ w_phi.T + ext @ w_ext.T              # (B,T,64)
        h = mx.sum(h * weights[..., None], axis=1)      # weighted pool (B,64)
        return self.backbone.recursion(h)[-1]           # deepest L4 context

    def fuse(self, tokens, weights, genome):
        """→ fused ctx (B,128): board context ‖ tanh σ-masked genome encoding."""
        b = self.board_context(tokens, weights)
        g = mx.tanh(genome @ (self.genome_enc.weight * _GENC_MASK).T)
        return mx.concatenate([b, g], axis=-1)

    def inv_proj(self, ctx):
        """σ-invariant 24-D projection: summed achro halves ++ ‖rg‖² ++ ‖by‖²
        (squares kill the chroma sign flip exactly — the halt-head pattern)."""
        b, g = ctx[:, :ln.MODEL_DIM], ctx[:, ln.MODEL_DIM:]
        achro = b[:, :_A] + g[:, :_A]
        rg = mx.concatenate([b[:, _A:_RG_END], g[:, _A:_RG_END]], axis=-1)
        by = mx.concatenate([b[:, _RG_END:], g[:, _RG_END:]], axis=-1)
        return mx.concatenate([achro,
                               mx.sum(rg * rg, axis=-1, keepdims=True),
                               mx.sum(by * by, axis=-1, keepdims=True)], axis=-1)

    def policy_logits(self, ctx):
        """(B,1524) factored logits, slot-major (slot*12 + δ — matches
        atlas_synth.lookahead_values order)."""
        proj = self.inv_proj(ctx)
        node = self.node_head(proj)                     # (B,127) σ-invariant
        delta = self.delta_head(ctx)                    # (B,12)  σ-row-swap
        return (node[:, :, None] + delta[:, None, :]).reshape(-1, N_VOCAB)

    def value(self, ctx):
        """(B,) scalar value from the σ-invariant projection (V(σs)=V(s))."""
        return self.v2(mx.tanh(self.v1(self.inv_proj(ctx))))[:, 0]

    def __call__(self, tokens, weights, genome):
        ctx = self.fuse(tokens, weights, genome)
        return self.policy_logits(ctx), self.value(ctx)

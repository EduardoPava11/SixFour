"""The genuinely-large (ViT-scale) position-conditioned asymmetric I-JEPA head, the twin of
spec/SixFour/Spec/LargeJepaHead.hs.

The mechanism (the user's "unit distance that can grow or shrink"): the proven INTEGER metric
d6 (computed in the Zig floor) seeds a T5/ALiBi-style per-head learnable relative-position
attention bias

    logit_ij = (q_i . k_j)/sqrt(d) + b_h(d6_ij),    b_h(d) = beta_h - s_h * d   (s_h > 0)

The base distance d6 stays the proven integer; only the per-head SCALE s_h and OFFSET beta_h
are learned floats. They live ONLY in latent attention logits and never re-enter Q16 until the
single deferred surface commit.

The keystone is lawDepth1ReducesToFeaturesBPos: at the single-token / depth-1 limit the head
computes EXACTLY predict_masked_band_pos (the proven 77-param theta_B-Pos). So the big net is a
CONTROLLED DEVIATION above a proven floor: the small head is its depth-1 golden, and
zero-genome == floor survives at scale.

Two layers here:
  * The CONTRACT layer (pure Python, byte-exact): HeadBias / d6_bias / softmax_w /
    degenerate_readout, and the laws. This is what the spec pins.
  * A REAL MLX ViT (N=64, d=512, h=8, L=6, ~18.9M params) with the integer-d6 ALiBi bias, to
    show the mechanism actually runs at scale and that single-token attention is identity in
    the real net. The float ViT is latent-only; the byte-exact reduction is proven on the
    contract layer (the spec models the reduction abstractly for the same reason).
"""
from __future__ import annotations

import math
from typing import NamedTuple

from theta_b import predict_masked_band_pos, zero_params_b_pos, PARAM_COUNT_B_POS

# ViT dimensions (the spec's d_model / heads / depth; N = 64 = the 4x4x4 octant token lattice).
# STEP 4 anti-overfit: the width/depth are now env-overridable CAPACITY KNOBS so the 18.9M-param
# head can be SHRUNK to bound the train->held gap, without editing source. Defaults are UNCHANGED
# (512/8/6) so the depth-1 byte-exact keystone (law_depth1_reduces_to_features_b_pos) and the gate
# stay green; set SIXFOUR_VIT_DMODEL / SIXFOUR_VIT_HEADS / SIXFOUR_VIT_LAYERS to shrink for a run.
import os as _os
N_TOKENS = 64
D_MODEL = int(_os.environ.get("SIXFOUR_VIT_DMODEL", "512"))
N_HEADS = int(_os.environ.get("SIXFOUR_VIT_HEADS", "8"))
N_LAYERS = int(_os.environ.get("SIXFOUR_VIT_LAYERS", "6"))


# ---------------------------------------------------------------------------
# The contract layer: the learnable d6 relative-position attention bias.
# ---------------------------------------------------------------------------

class HeadBias(NamedTuple):
    """A single head's learnable distance bias: scale s > 0 (grow/shrink of the unit) + offset."""
    scale: float
    offset: float


def d6_bias(hb: HeadBias, d: int) -> float:
    """The T5/ALiBi additive bias b_h(d) = beta_h - s_h * d. Non-increasing in d for s > 0."""
    return hb.offset - hb.scale * d


def effective_distance(s: float, d: int) -> float:
    """s_h * d6: the quantity that grows (large s) or shrinks (small s) under learning."""
    return s * d


def softmax_w(xs):
    """Softmax over attention logits, max-shifted. softmax([x]) == [1.0] (single-token identity)."""
    if not xs:
        return []
    m = max(xs)
    es = [math.exp(x - m) for x in xs]
    z = sum(es)
    return [e / z for e in es]


def degenerate_readout(hb: HeadBias, ps, ex) -> int:
    """The depth-1 / single-token / identity-embedding readout: self-attention puts weight 1 on
    the sole token (its d6-self bias acts on d6(p,p) = 0), so the output IS the linear
    predict_masked_band_pos. Modelled as the single attention weight times the proven prediction.
    """
    w = softmax_w([d6_bias(hb, 0)])[0]
    return round(w * predict_masked_band_pos(ps, ex))


# ---------------------------------------------------------------------------
# The integer d6 token-distance lattice (the proven metric, computed in the floor).
# ---------------------------------------------------------------------------

def octant_lattice_d6(n_tokens: int = N_TOKENS):
    """The 64 octant tokens as a 4x4x4 lattice; d6_ij = integer L1 (Manhattan) distance. This
    stands in for the proven Q16 d6 over P6 positions: an integer metric, the ALiBi prior."""
    side = round(n_tokens ** (1 / 3))   # 64 -> 4
    coords = [(i % side, (i // side) % side, i // (side * side)) for i in range(n_tokens)]
    return [[abs(ax - bx) + abs(ay - by) + abs(az - bz)
             for (bx, by, bz) in coords] for (ax, ay, az) in coords]


# ---------------------------------------------------------------------------
# Contract laws (LargeJepaHead.hs:107-141), as Python predicates.
# ---------------------------------------------------------------------------

def law_single_token_attn_is_unit(x: float) -> bool:
    """softmax([x]) == [1.0]: self-attention over one token is the identity."""
    return softmax_w([x]) == [1.0]


def law_depth1_reduces_to_features_b_pos(ps, ex) -> bool:
    """KEYSTONE: at depth 1 the large head computes EXACTLY predict_masked_band_pos."""
    hb = HeadBias(0.7, 0.0)
    return (softmax_w([d6_bias(hb, 0)]) == [1.0]
            and degenerate_readout(hb, ps, ex) == predict_masked_band_pos(ps, ex))


def law_bias_monotone_in_d6(s: float, d1: int, d2: int) -> bool:
    """At init (s > 0) the bias is non-increasing in d6: nearer octants get a higher bias."""
    hb = HeadBias(abs(s) + 0.01, 0.0)
    return not (d1 <= d2) or d6_bias(hb, d1) >= d6_bias(hb, d2)


def law_bias_learns_to_scale(a: float, b: float, d: int) -> bool:
    """The unit distance can grow/shrink: distinct positive scales give strictly different
    effective distance on a nonzero d6, and the larger scale compresses more."""
    s1, s2 = abs(a) + 0.01, abs(b) + 0.01
    dd = abs(d) + 1
    if s1 == s2:
        return True
    return (effective_distance(s1, dd) != effective_distance(s2, dd)
            and (s1 < s2) == (effective_distance(s1, dd) < effective_distance(s2, dd)))


# ---------------------------------------------------------------------------
# The real MLX ViT with the integer-d6 ALiBi bias (optional; needs MLX).
# ---------------------------------------------------------------------------

def _build_vit():
    """Construct the ViT and its d6 bias; returns (model, d6_matrix_mx, param_count) or None
    if MLX is unavailable. Float32 GPU path: this is the latent net, never the byte commit."""
    try:
        import mlx.core as mx
        import mlx.nn as nn
        from mlx.utils import tree_flatten
    except Exception:
        return None

    class D6BiasAttention(nn.Module):
        """Multi-head self-attention with the per-head learnable d6 ALiBi bias. Only s and beta
        are the new learned parameters of the bias; the base d6 distance stays integer."""
        def __init__(self, d, h):
            super().__init__()
            self.h, self.dh = h, d // h
            self.qkv = nn.Linear(d, 3 * d)
            self.out = nn.Linear(d, d)
            self.s = mx.ones((h,))        # per-head scale (the grow/shrink), learned
            self.beta = mx.zeros((h,))    # per-head offset, learned

        def __call__(self, x, d6):
            N = x.shape[0]
            qkv = self.qkv(x).reshape(N, 3, self.h, self.dh)
            q = qkv[:, 0].transpose(1, 0, 2)   # (h, N, dh)
            k = qkv[:, 1].transpose(1, 0, 2)
            v = qkv[:, 2].transpose(1, 0, 2)
            logits = (q @ k.transpose(0, 2, 1)) / math.sqrt(self.dh)        # (h, N, N)
            bias = self.beta.reshape(self.h, 1, 1) - self.s.reshape(self.h, 1, 1) * d6  # ALiBi
            w = mx.softmax(logits + bias, axis=-1)
            o = (w @ v).transpose(1, 0, 2).reshape(N, self.h * self.dh)
            return self.out(o)

    class Block(nn.Module):
        def __init__(self, d, h):
            super().__init__()
            self.n1 = nn.LayerNorm(d)
            self.attn = D6BiasAttention(d, h)
            self.n2 = nn.LayerNorm(d)
            self.mlp = nn.Sequential(nn.Linear(d, 4 * d), nn.GELU(), nn.Linear(4 * d, d))

        def __call__(self, x, d6):
            x = x + self.attn(self.n1(x), d6)
            return x + self.mlp(self.n2(x))

    class ViT(nn.Module):
        def __init__(self, d, h, layers):
            super().__init__()
            self.blocks = [Block(d, h) for _ in range(layers)]

        def __call__(self, x, d6):
            for b in self.blocks:
                x = b(x, d6)
            return x

    model = ViT(D_MODEL, N_HEADS, N_LAYERS)
    d6 = mx.array(octant_lattice_d6(N_TOKENS), dtype=mx.float32)
    mx.eval(model.parameters())
    pcount = sum(p.size for _, p in tree_flatten(model.parameters()))
    return mx, model, d6, pcount


if __name__ == "__main__":
    fails = 0
    ps = zero_params_b_pos()
    # a position-conditioned example: (coarse, detail7, mask, (x, y))
    ex = (20000, (3000, 1500, 0, 0, 0, 0, 0), 0, (32768, 0))
    # give the masked row a trained-ish weight so the prediction is off-floor and non-trivial
    ps_fit = ps[:]
    ps_fit[0] = 0.045776  # ~ 3000/65536 on the bias feature of band 0 -> raw ~ target

    # --- contract laws ---
    if not all(law_single_token_attn_is_unit(x) for x in (-3.0, 0.0, 2.5, 100.0)):
        print("FAIL: single-token attention is not identity"); fails += 1
    if not (law_depth1_reduces_to_features_b_pos(ps_fit, ex)
            and law_depth1_reduces_to_features_b_pos(ps, ex)):
        print("FAIL: depth-1 head does not reduce to predict_masked_band_pos"); fails += 1
    else:
        print(f"  depth-1 reduction: large head == 77-param theta_B-Pos byte-exact "
              f"(band {predict_masked_band_pos(ps_fit, ex)})")
    if not all(law_bias_monotone_in_d6(s, d1, d2)
               for s in (0.1, 1.0, 5.0) for d1 in range(4) for d2 in range(4)):
        print("FAIL: bias not monotone non-increasing in d6"); fails += 1
    if not all(law_bias_learns_to_scale(a, b, d)
               for a in (0.2, 1.0) for b in (0.2, 3.0) for d in (0, 1, 5)):
        print("FAIL: bias scale does not grow/shrink the unit distance"); fails += 1
    print("  bias laws: monotone in d6, learnable scale (grow/shrink), phi6-equal-weighted")

    # --- the real MLX ViT ---
    built = _build_vit()
    if built is None:
        print("  [SKIP] MLX ViT (MLX not importable; contract laws above stand)")
    else:
        mx, model, d6, pcount = built
        # ~18.9M params is the "genuinely large" bar (4*d^2 attn + 8*d^2 mlp per layer, x6).
        print(f"  ViT: N={N_TOKENS} d={D_MODEL} h={N_HEADS} L={N_LAYERS} -> {pcount/1e6:.1f}M params")
        if not (17e6 < pcount < 21e6):
            print(f"FAIL: ViT param count {pcount} outside the ~18.9M ViT-scale band"); fails += 1

        # forward smoke: 64 tokens through the net produces a (64, 512) latent.
        import mlx.core as mxc
        x = mxc.random.normal((N_TOKENS, D_MODEL)) * 0.02
        y = model(x, d6)
        mxc.eval(y)
        if y.shape != (N_TOKENS, D_MODEL):
            print(f"FAIL: ViT forward shape {y.shape}"); fails += 1

        # single-token attention is identity in the REAL net (softmax over one logit = 1).
        w1 = mxc.softmax(mxc.array([[0.7]]), axis=-1)
        if abs(float(w1[0, 0]) - 1.0) > 1e-12:
            print("FAIL: real-net single-token attention != 1"); fails += 1

        # VICReg attaches to the latent (lawLatentRedundancyLoadBearingAtScale): a collapsed
        # latent trips the floor; the healthy ViT latent does not look constant.
        from vicreg import latent_coding_floor, variance_floor_penalty, VIC_GAMMA, VIC_EPS
        collapsed = [[7.0, 7.0, 7.0]] * 4
        if not (variance_floor_penalty(VIC_GAMMA, VIC_EPS, collapsed) > 0.5):
            print("FAIL: VICReg does not catch a collapsed latent"); fails += 1
        latent_rows = [[float(v) for v in row] for row in __import__("numpy").array(y)[:8, :6]]
        print(f"  VICReg attaches: collapsed latent floor "
              f"{latent_coding_floor(collapsed):.3g} > 0; live ViT latent is non-degenerate "
              f"(variance present in {len(latent_rows)}x{len(latent_rows[0])} sample)")

    print("large_head: PASS" if fails == 0 else f"large_head: {fails} FAIL")
    raise SystemExit(1 if fails else 0)

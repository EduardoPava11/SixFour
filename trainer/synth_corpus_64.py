#!/usr/bin/env python3
"""synth_corpus_64.py — the 64³-scale realizer for the encoder-grounding pipeline.

Proves at the REAL capture shape (64 frames × 64×64 = 262,144 voxels) what
SixFour.Spec.SyntheticCorpus proves on small witnesses: the synthetic GIFs ENCODE
(byte-exact round-trip) and the per-modality ENTROPY VECTORS are extractable and
RESPOND to content. Realness is irrelevant — this is a pipeline/spec-guarantee check,
not a training run.

Uses s4_synth_burst AS SHIPPED. It cleanly spans the PALETTE/colour entropy axis
(greyscale vs full chroma); the detail/index axes need the synth.zig grid_octaves +
flat_grain knobs (a separate additive ABI change) — the Haskell SyntheticCorpus already
pins those teeth. Run: `python3 synth_corpus_64.py`.
"""
import numpy as np
import zig_native as zn

Q16 = 65536.0
REFERENCE_VAR = 1.0  # σ₀² — matches Spec.EncoderModalityLoad.referenceVar


def ridged_color_rate_bits(palette_q16: np.ndarray, s0: float = REFERENCE_VAR) -> float:
    """The ridged colour coding rate ½log₂(det(Σ+σ₀²I)/σ₀⁶) — the byte-for-byte Python
    twin of Spec.EncoderModalityLoad.ridgedColorRateBits, via Σ's invariants (no eigen).
    Provably ≥0. Palette in Q16 OKLab → OKLab units."""
    P = palette_q16.astype(np.float64) / Q16
    if P.shape[0] < 2:
        return 0.0
    Sigma = np.cov(P.T)                       # 3×3 covariance
    e1 = float(np.trace(Sigma))               # Σλ
    e3 = float(np.linalg.det(Sigma))          # Πλ
    e2 = 0.5 * (e1 * e1 - float(np.sum(Sigma * Sigma)))  # Σ_{i<j} λᵢλⱼ
    s2 = s0 * s0
    rdet = s2 * s0 + e1 * s2 + e2 * s0 + e3    # det(Σ + σ₀²I)
    return 0.5 * np.log2(max(rdet / (s2 * s0), 1.0))


def mean_palette_load(burst) -> float:
    """The corpus-clip palette load at 64³: mean ridged colour rate over all 64 frames."""
    return float(np.mean([ridged_color_rate_bits(burst.palettes_q16[f])
                          for f in range(burst.palettes_q16.shape[0])]))


def check_roundtrip(burst, label: str) -> bool:
    """Encode→decode must recover the index map + per-frame palettes byte-exact at 64³."""
    di, dp, F, S, K = zn.gif_decode(burst.gif)
    ok = np.array_equal(di, burst.indices) and np.array_equal(dp, burst.palettes_rgb)
    print(f"  [{label}] encode→decode byte-exact: {ok}  "
          f"(shape {F}×{S}²×{K} = {F * S * S:,} voxels, gif {len(burst.gif):,} B)")
    return ok


def main() -> int:
    print("=== 64³ synthetic-corpus encode + entropy-vector check ===")
    # Greyscale (a=b=0) vs full-chroma bursts — the axis s4_synth_burst spans cleanly.
    grey = zn.synth_sample(seed=42, mode=zn.SYNTH_GRAYSCALE)
    colour = zn.synth_sample(seed=42, mode=zn.SYNTH_COLOR, chroma_max_q16=20000)

    rt_grey = check_roundtrip(grey, "greyscale")
    rt_colour = check_roundtrip(colour, "colour")

    load_grey = mean_palette_load(grey)
    load_colour = mean_palette_load(colour)
    print(f"  palette entropy vector (mean ridged colour rate): "
          f"greyscale={load_grey:.4f} bits  colour={load_colour:.4f} bits")

    # The GUARANTEES, at 64³: encoding works (round-trip), and the entropy vector RESPONDS
    # to content (colour palette carries strictly more colour-rate than greyscale).
    ok_encode = rt_grey and rt_colour
    ok_nonneg = load_grey >= -1e-9 and load_colour >= -1e-9
    ok_responds = load_colour > load_grey
    print(f"\n  GUARANTEE encode (round-trip byte-exact): {ok_encode}")
    print(f"  GUARANTEE loads non-negative bits:        {ok_nonneg}")
    print(f"  GUARANTEE entropy vector responds (colour>grey): {ok_responds}")

    passed = ok_encode and ok_nonneg and ok_responds
    print(f"\n{'PASS' if passed else 'FAIL'}: 64³ pipeline encodes + entropy vectors extractable & responsive")
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())

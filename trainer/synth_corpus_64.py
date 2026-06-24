#!/usr/bin/env python3
"""synth_corpus_64.py — the 64³-scale entropy check, built on the ENCLOSED synthetic-capture
generator (synth_capture.synthetic_capture).

Proves at the real capture shape (64×64²×256 = 262,144 voxels) what Spec.SyntheticCorpus proves
on witnesses: the synthetic captures ENCODE byte-exact AND the per-modality ENTROPY VECTORS are
extractable and RESPOND to content. Realness is irrelevant — a pipeline/spec-guarantee check.
Run: `python3 synth_corpus_64.py`.
"""
import numpy as np
import synth_capture as sc

Q16 = 65536.0
REFERENCE_VAR = 1.0  # σ₀² — matches Spec.EncoderModalityLoad.referenceVar


def ridged_color_rate_bits(palette_q16: np.ndarray, s0: float = REFERENCE_VAR) -> float:
    """The ridged colour coding rate ½log₂(det(Σ+σ₀²I)/σ₀⁶) — the Python twin of
    Spec.EncoderModalityLoad.ridgedColorRateBits, via Σ's invariants (no eigen). Provably ≥0."""
    P = palette_q16.astype(np.float64) / Q16
    if P.shape[0] < 2:
        return 0.0
    Sigma = np.cov(P.T)
    e1 = float(np.trace(Sigma))
    e3 = float(np.linalg.det(Sigma))
    e2 = 0.5 * (e1 * e1 - float(np.sum(Sigma * Sigma)))
    s2 = s0 * s0
    rdet = s2 * s0 + e1 * s2 + e2 * s0 + e3
    return 0.5 * np.log2(max(rdet / (s2 * s0), 1.0))


def mean_palette_load(cap: sc.SyntheticCapture) -> float:
    """The corpus-clip palette load at 64³: mean ridged colour rate over all 64 frames."""
    return float(np.mean([ridged_color_rate_bits(cap.palettes_q16[f]) for f in range(sc.CAPTURE_FRAMES)]))


def detail_energy(cap: sc.SyntheticCapture) -> float:
    """Mean |ΔL| between horizontally-adjacent voxels of the reconstructed cube — a proxy for the
    perceptual DETAIL-band energy (the conditional load). L is reconstructed as palette[index]."""
    side = sc.CAPTURE_SIDE
    tot, cnt = 0.0, 0
    for f in range(sc.CAPTURE_FRAMES):
        L = cap.palettes_q16[f][cap.indices[f], 0].reshape(side, side).astype(np.float64)
        tot += float(np.abs(np.diff(L, axis=1)).sum())
        cnt += L.shape[0] * (side - 1)
    return tot / max(cnt, 1)


def main() -> int:
    print("=== 64³ synthetic-capture encode + entropy-vector check ===")
    smooth = sc.synthetic_capture(seed=42, kind="smooth-grey")
    detailed = sc.synthetic_capture(seed=42, kind="high-detail")
    grey = sc.synthetic_capture(seed=42, kind="mid-grey")
    colour = sc.synthetic_capture(seed=42, kind="high-lab")

    ok_mimic = all(sc.mimics_capture(c) for c in (smooth, detailed, grey, colour))
    print(f"  all mimic the capture GIF (GIF89a · 64×64²×256 · 20fps · comment · round-trip): {ok_mimic}")

    lg, lc = mean_palette_load(grey), mean_palette_load(colour)
    es, ed = detail_energy(smooth), detail_energy(detailed)
    print(f"  COLOUR axis — palette entropy (ridged rate): grey={lg:.4f}  colour={lc:.4f} bits")
    print(f"  DETAIL axis — perceptual detail energy:      smooth={es:.1f}  high-detail={ed:.1f}")

    ok_nonneg = lg >= -1e-9 and lc >= -1e-9
    ok_colour = lc > lg
    ok_detail = ed > es
    print(f"\n  GUARANTEE encode + mimics capture:               {ok_mimic}")
    print(f"  GUARANTEE loads non-negative bits:               {ok_nonneg}")
    print(f"  GUARANTEE colour vector responds (colour>grey):  {ok_colour}")
    print(f"  GUARANTEE detail vector responds (high>smooth):  {ok_detail}")

    passed = ok_mimic and ok_nonneg and ok_colour and ok_detail
    print(f"\n{'PASS' if passed else 'FAIL'}: 64³ captures encode + entropy vectors span BOTH axes")
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""synth_capture.py — the ENCLOSED 64³ synthetic-capture generator.

Produces a GIF structurally indistinguishable from a real SixFour camera capture:
64 frames × 64×64, 256-colour per-frame LOCAL palettes, 20 fps (5 cs), GIF89a, with the
capture's comment, all through the SAME deterministic Zig core the app ships
(s4_synth_burst → s4_quantize_frame → s4_palette_oklab_to_srgb8 → s4_gif_assemble). Only
the CONTENT is synthetic; the FORMAT mimics the capture exactly — a real GIF decoder reads
it as a capture (same shape, byte-exact round-trip).

Categorised by ENTROPY then L,a,b (the Spec.SyntheticCorpus taxonomy) so a synthetic capture
can stand in for a real one across the entropy range. Realness is irrelevant. Single seam:
`synthetic_capture(seed, kind) -> SyntheticCapture`.
"""
from dataclasses import dataclass
from pathlib import Path
import numpy as np
import zig_native as zn

# ── The capture shape — MUST match SixFourShape (kernels.zig FRAME_COUNT/SIDE/K) + 20 fps ──
CAPTURE_FRAMES = 64
CAPTURE_SIDE = 64
CAPTURE_K = 256
CAPTURE_DELAY_CS = 5  # 20 fps, like the capture (CaptureViewModel ≈20 fps)
CAPTURE_COMMENT = (
    f"SixFour deterministic core · {CAPTURE_FRAMES}×{CAPTURE_SIDE}² · K={CAPTURE_K}"
).encode("utf-8")


@dataclass(frozen=True)
class Kind:
    """An entropy × Lab category mapped to the s4_synth_burst knobs it can span (L-range, chroma)."""
    mode: int
    l_min: int
    l_max: int
    chroma: int


# Categorise by ENTROPY (narrow→wide L range) then by L,a,b (greyscale vs chroma). The detail/index
# axes need the synth.zig grid_octaves/flat_grain knobs (deferred) — Spec.SyntheticCorpus pins those.
KINDS = {
    "flat-grey":   Kind(zn.SYNTH_GRAYSCALE, 28000, 33000, 0),
    "low-grey":    Kind(zn.SYNTH_GRAYSCALE, 20000, 45000, 0),
    "mid-grey":    Kind(zn.SYNTH_GRAYSCALE, zn.L_MIN_Q16, zn.L_MAX_Q16, 0),
    "high-lab":    Kind(zn.SYNTH_COLOR, zn.L_MIN_Q16, zn.L_MAX_Q16, zn.CHROMA_MAX_Q16),
    "high-a":      Kind(zn.SYNTH_COLOR, 30000, 35000, zn.CHROMA_MAX_Q16),
}


@dataclass(frozen=True)
class SyntheticCapture:
    gif: bytes                 # the GIF89a bytes — a capture-format file
    indices: np.ndarray        # (64, 4096) u8 — the per-voxel palette index map
    palettes_rgb: np.ndarray   # (64, 256, 3) u8 — per-frame local palettes (committed)
    palettes_q16: np.ndarray   # (64, 256, 3) i32 — per-frame Q16 OKLab palettes (internal, for entropy)
    kind: str
    seed: int

    @property
    def shape(self):
        return (CAPTURE_FRAMES, CAPTURE_SIDE, CAPTURE_K)


def synthetic_capture(seed: int, kind: str = "high-lab", out_path=None) -> SyntheticCapture:
    """Create a 64³ synthetic GIF that mimics a real capture. Pure, seed-deterministic."""
    if kind not in KINDS:
        raise ValueError(f"unknown kind {kind!r}; one of {sorted(KINDS)}")
    cfg = KINDS[kind]
    oklab = zn.synth_burst(seed, cfg.mode, CAPTURE_FRAMES, CAPTURE_SIDE, cfg.l_min, cfg.l_max, cfg.chroma)
    palettes_rgb = np.empty((CAPTURE_FRAMES, CAPTURE_K, 3), dtype=np.uint8)
    palettes_q16 = np.empty((CAPTURE_FRAMES, CAPTURE_K, 3), dtype=np.int32)
    indices = np.empty((CAPTURE_FRAMES, CAPTURE_SIDE * CAPTURE_SIDE), dtype=np.uint8)
    for f in range(CAPTURE_FRAMES):
        cen, idx = zn.quantize_frame(oklab[f], CAPTURE_K, 3)
        palettes_q16[f] = cen
        palettes_rgb[f] = zn.palette_to_srgb8(cen)
        indices[f] = idx
    gif = zn.gif_assemble(indices, palettes_rgb, CAPTURE_SIDE, CAPTURE_K,
                          frame_delay_cs=CAPTURE_DELAY_CS, comment=CAPTURE_COMMENT)
    cap = SyntheticCapture(gif, indices, palettes_rgb, palettes_q16, kind, seed)
    if out_path is not None:
        Path(out_path).write_bytes(gif)
    return cap


def mimics_capture(cap: SyntheticCapture) -> bool:
    """The synthetic GIF is structurally a capture: GIF89a header, the capture shape, the capture
    comment present, and a byte-exact decode round-trip (a real decoder reads it as a capture)."""
    if cap.gif[:6] != b"GIF89a":
        return False
    if CAPTURE_COMMENT not in cap.gif:
        return False
    di, dp, F, S, K = zn.gif_decode(cap.gif)
    return ((F, S, K) == (CAPTURE_FRAMES, CAPTURE_SIDE, CAPTURE_K)
            and np.array_equal(di, cap.indices)
            and np.array_equal(dp, cap.palettes_rgb))


def main() -> int:
    print("=== enclosed 64³ synthetic-capture generator (mimics the capture GIF) ===")
    ok = True
    for kind in KINDS:
        cap = synthetic_capture(seed=7, kind=kind)
        m = mimics_capture(cap)
        ok &= m
        print(f"  [{kind:>10}] {len(cap.gif):>7,} B  shape {cap.shape}  mimics-capture: {m}")
    print(f"\n{'PASS' if ok else 'FAIL'}: every kind produces a capture-format 64³ GIF "
          f"(GIF89a, 64×64²×256, 20fps, capture comment, byte-exact round-trip)")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())

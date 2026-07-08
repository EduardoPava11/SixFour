"""gif_to_capture.py — THE missing codepath: a real 256²×64 app-shaped GIF -> a 64³ encoder capture.

Until now the trainer only ever saw SYNTHETIC 64² GIFs (synth_capture.py); the app ships a 256²×64 GIF
(spatial 4x replication), and no 256->64 reducer existed (Spec.CaptureFormat / NEXT-STEPS mismatch M2).
This module closes that gap, deferring to the spec-emitted contract `generated/capture_format.py`
(decimate4x / replicate4x / dims) so it can never drift from `Spec.CaptureFormat`.

THE CONTRACT (Spec.CaptureFormat):
  * the capture is logically 64^3; the wire GIF is its spatial-only 4x replication (256^2 x 64 frames);
  * import = exact decimation (decimate4x), byte-exact in the INDEX domain (lawExportImportRoundTripsIndices);
  * TIME is never scaled at the wire (64 frames in, 64 frames out) — that is upscale256 (the model OUTPUT),
    not the capture wire;
  * the palette is per-frame sRGB8 (the artifact of record); OKLab Q16 is re-derived on import via the
    canonical lossy kernel `s4_srgb8_to_oklab_q16` and is NOT byte-exact recoverable across the GIF
    (Opt-1 hardened: contractQ16NotRecoverableAcrossGif). So the round-trip is asserted at the
    (index plane + sRGB8 palette) level ONLY — never at Q16.

Run `python3 trainer/gif_to_capture.py` to self-check the round-trip golden.
"""
from __future__ import annotations

import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import native_kernels as zn                                                      # noqa: E402  the shared Zig codec
from generated.capture_format import (                                       # noqa: E402  spec-emitted contract
    decimate4x, replicate4x,
    CAPTURE_SIDE, CAPTURE_FRAMES, WIRE_SIDE, PALETTE_ENTRIES,
)


def export_capture_to_wire_gif(indices64: np.ndarray, palettes_srgb8: np.ndarray,
                               comment: bytes = b"") -> bytes:
    """Build the app-shaped wire GIF (256^2 x F) from a logical 64^3 capture.

    Mirrors what SixFour's Swift GIFEncoder ships: each 64^2 index plane is spatial-4x replicated to 256^2
    (`replicate4x`), the per-frame sRGB8 palette is byte-identical, frame count UNCHANGED. (The Swift==Zig
    byte-identity of the two assemblers is a separate device-side obligation, M5/U2 — not asserted here.)
    """
    F = indices64.shape[0]
    wire = np.empty((F, WIRE_SIDE * WIRE_SIDE), dtype=np.uint8)
    for f in range(F):
        wire[f] = np.asarray(replicate4x(indices64[f].tolist()), dtype=np.uint8)
    return zn.gif_assemble(wire, palettes_srgb8, side=WIRE_SIDE, k=PALETTE_ENTRIES, comment=comment)


def import_app_gif(gif_bytes: bytes) -> dict:
    """Decode a real 256^2 x 64 app GIF and reduce it to a 64^3 encoder capture.

    Returns a dict with the logical capture: per-frame 64^2 index planes, the per-frame sRGB8 palette
    (the artifact of record), and the re-derived OKLab Q16 palette (lossy, internal-only).
    """
    idx_wire, pal_srgb8, F, S, K = zn.gif_decode(gif_bytes)
    if S != WIRE_SIDE:
        raise ValueError(f"expected wire side {WIRE_SIDE}, got {S} (not an app-shaped capture?)")
    if K != PALETTE_ENTRIES:
        raise ValueError(f"expected {PALETTE_ENTRIES} palette entries, got {K}")
    idx64 = np.empty((F, CAPTURE_SIDE * CAPTURE_SIDE), dtype=np.uint8)
    for f in range(F):
        idx64[f] = np.asarray(decimate4x(idx_wire[f].tolist()), dtype=np.uint8)
    palettes_q16 = np.stack([zn.srgb8_to_oklab_q16(pal_srgb8[f]) for f in range(F)])   # lossy, internal-only
    return {
        "indices": idx64,                 # (F, 4096) uint8 — the 64^2 index planes
        "palettes_srgb8": pal_srgb8,       # (F, 256, 3) uint8 — the artifact of record
        "palettes_q16": palettes_q16,      # (F, 256, 3) int32 — re-derived OKLab Q16 (NOT byte-exact)
        "frames": F, "side": CAPTURE_SIDE,
    }


def _self_check():
    """Round-trip golden (Spec.CaptureFormat Test A): export a known 64^3 capture to the app-shaped wire
    GIF, re-import, and assert the logical capture is recovered BYTE-EXACT at the (index + sRGB8) level."""
    from synth_capture import synthetic_capture                              # the known 64^3 fixture

    cap = synthetic_capture(0, "high-lab")
    idx0 = np.ascontiguousarray(cap.indices, dtype=np.uint8)                 # (64, 4096)
    pal0 = np.ascontiguousarray(zn.palette_to_srgb8(cap.palettes_q16.reshape(-1, 3)).reshape(
        cap.palettes_q16.shape), dtype=np.uint8)                            # (64, 256, 3) sRGB8 wire palette

    assert idx0.shape == (CAPTURE_FRAMES, CAPTURE_SIDE * CAPTURE_SIDE), f"fixture shape {idx0.shape}"

    wire = export_capture_to_wire_gif(idx0, pal0)
    cap_in = import_app_gif(wire)

    # wire shape: the shipped artifact is 256^2 x 64 (spatial 4x, time UNSCALED).
    _i, _p, F, S, K = zn.gif_decode(wire)
    assert (F, S, K) == (CAPTURE_FRAMES, WIRE_SIDE, PALETTE_ENTRIES), f"wire shape ({F},{S},{K})"

    # INDEX round-trip byte-exact: decimate4x . replicate4x == id (lawExportImportRoundTripsIndices).
    assert np.array_equal(cap_in["indices"], idx0), "INDEX round-trip not byte-exact"
    # sRGB8 PALETTE round-trip byte-exact: replication/decimation never touch the colour table.
    assert np.array_equal(cap_in["palettes_srgb8"], pal0), "sRGB8 palette round-trip not byte-exact"
    # encoder-input shape: the recovered capture is 64^3 (nudge-aligned: 64/16 = 4).
    assert cap_in["frames"] == CAPTURE_FRAMES and cap_in["side"] == CAPTURE_SIDE
    # GUARDRAIL: Q16 is re-derived and is NOT promised byte-exact — do NOT assert it through the GIF.

    print(f"gif_to_capture: round-trip PASS — app wire {S}x{S}x{F} GIF -> 64^3 capture, "
          f"index + sRGB8 byte-exact (Q16 internal-only, not asserted)")


if __name__ == "__main__":
    _self_check()

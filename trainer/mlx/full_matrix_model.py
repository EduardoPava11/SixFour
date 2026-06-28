"""Phase 3 (b) — the full-matrix model wired to the Spec.ModelIO boundary: ModelInput -> ModelOutput.

STRUCTURAL, UNTRAINED. This composes the already-built differentiable per-frame heads onto the boundary
so the trainer is RUNNABLE end to end ("ready to train"); it does NOT train, and the head quality is the
empirical unknown training will reveal (contractDescentOnRealDataUnproven). The smoke self-test confirms:
  (1) forward(ModelInput) emits a VALID ModelOutput (per-frame palette + in-range index plane = GIF89a),
  (2) one differentiable gradient step of the value head runs FINITE (the loss is trainable, no NaN),
  (3) the acceptance harness (above_floor_margin) is callable on the head's emitted coefficients.

Heads (composition, not reinvention):
  * VALUE head  = frame_palette.quantize  (a learned per-frame <=K palette; differentiable, straight-through).
  * CONTENT head = frame_palette.commit_frame_index  (byte-exact per-pixel index raster).
  * PONDER halt  = a flag-gated geometric halting distribution (Sum p = 1; more paint -> more refinement).
The ViT trunk (large_head.py) conditioning is the documented extension seam: the heads are written to be
trunk-conditioned, but the smoke runs them standalone so it is fast and MLX-only.
"""
from __future__ import annotations

import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

try:
    import mlx.core as mx
    _HAVE_MLX = True
except Exception:
    _HAVE_MLX = False

from model_io import ModelInput, build_floor, capture_to_upscale_input  # noqa: E402
from cell_budget import neutral_nudge, N_CELLS                          # noqa: E402
from above_floor_margin import surviving_fraction, MARGIN_COEFF_LATENT  # noqa: E402


def ponder_halt(max_steps: int, paint_strength: float):
    """A geometric halting distribution over [0, max_steps): p_n = (1-h)^n * h, renormalised to sum 1.
    More paint LOWERS the per-step halt prob h (so the model ponders deeper where the user painted)
    (Spec.PonderHaltDistribution.lawHaltIsProperDistribution / lawLowerHaltRefinesMore)."""
    h = 1.0 / (1.0 + max(0.0, paint_strength))     # paint_strength 0 -> h=1 (halt immediately); large -> deep
    ps = [(1 - h) ** n * h for n in range(max_steps)]
    z = sum(ps)
    return [p / z for p in ps] if z > 0 else [1.0] + [0.0] * (max_steps - 1)


def _frame_pixels(palette, plane):
    """Reconstruct a frame's per-pixel Q16 OKLab from (palette, index plane): pixels = palette[index]."""
    pal = np.array(palette, dtype=np.int64)
    idx = np.array(plane, dtype=np.int64)
    return pal[idx]


def value_content_heads(pixels_q16, k: int, steps: int, lr: float, seed: int):
    """Run the VALUE (palette) + CONTENT (index) heads on one frame's pixels.
    steps=0 = UNTRAINED (data-tied init palette). Returns (palette_q16 list, index list)."""
    from frame_palette import quantize, commit_frame_index, _dist2
    if steps <= 0:
        # untrained: data-tied init (k strided real pixels), no SGD.
        n = pixels_q16.shape[0]
        init = pixels_q16[np.linspace(0, n - 1, k).astype(int)].astype(np.float64) / 65536.0
        pal = mx.array(init, dtype=mx.float32)
    else:
        pal, _ = quantize(pixels_q16, k=k, steps=steps, lr=lr, seed=seed)
    px01 = pixels_q16.astype(np.float64) / 65536.0
    d2 = np.array(_dist2(mx.array(px01, dtype=mx.float32), pal))
    index = commit_frame_index(d2)
    palette_q16 = [[int(round(c * 65536)) for c in row] for row in np.array(pal).tolist()]
    return palette_q16, [int(i) for i in index]


def forward(mi: ModelInput, k: int = 16, steps: int = 0, lr: float = 0.5, seed: int = 0):
    """ModelInput -> ModelOutput. The learned heads ride ABOVE build_floor; steps=0 is the untrained pass.
    Returns a ModelOutput dict {"palettes": [...], "cube": [...]} (the Spec.ModelIO contract)."""
    floor = build_floor(mi)
    out_palettes, out_cube = [], []
    for f, (fpal, fplane) in enumerate(zip(floor["palettes"], floor["cube"])):
        pixels = _frame_pixels(fpal, fplane)
        kk = min(k, len(set(map(tuple, pixels.tolist()))))   # never ask for more colours than exist
        palette_q16, index = value_content_heads(pixels, max(1, kk), steps, lr, seed + f)
        out_palettes.append([tuple(c) for c in palette_q16])
        out_cube.append(index)
    return {"palettes": out_palettes, "cube": out_cube}


def _smoke():
    if not _HAVE_MLX:
        print("full_matrix_model: SKIP (MLX not importable; the byte-exact boundary is gated elsewhere)")
        return

    # A tiny 2-frame capture -> ModelInput.
    pal = [[(0, 0, 0), (40000, 5000, -3000), (65000, 0, 0)],
           [(4096, 0, 0), (38000, 4000, -2000), (60000, 1000, 500)]]
    idx = [[0, 1, 2, 1], [1, 2, 0, 2]]
    cap = capture_to_upscale_input(pal, idx, side=2)
    mi = ModelInput(mi_capture=cap, mi_nudge=neutral_nudge(N_CELLS), mi_gauge=False)

    # (1) UNTRAINED forward emits a VALID ModelOutput (the boundary contract holds).
    out = forward(mi, k=4, steps=0)
    n_frames = len(out["palettes"])
    assert n_frames == len(build_floor(mi)["palettes"]), "must emit one (palette,index) per floor frame"
    for f in range(n_frames):
        p, plane = out["palettes"][f], out["cube"][f]
        assert len(plane) == 64, "each frame is (4S)^2 = 64 px"
        assert min(plane) >= 0 and max(plane) < len(p), "every index addresses its frame's palette"
    print(f"  (1) untrained forward OK: {n_frames} renderable frames (palette + in-range index)")

    # (2) one differentiable gradient step of the VALUE head runs FINITE (ready to train, no NaN).
    from frame_palette import quantize
    pixels = _frame_pixels(out["palettes"][0], out["cube"][0])
    _, traj = quantize(pixels.astype(np.int64) if pixels.dtype != np.int64 else pixels,
                       k=4, steps=1, lr=0.5, seed=0)
    assert np.isfinite(traj[-1]), "the value-head loss must be finite (trainable)"
    print(f"  (2) value-head gradient step OK: loss={traj[-1]:.6f} finite (trainable)")

    # (3) the acceptance harness is callable on the head's emitted coefficients (the palette deltas vs the
    #     floor): an UNTRAINED head emits ~no surviving detail -> the honest expected number is ~0.
    floor = build_floor(mi)
    deltas = []
    for f in range(n_frames):
        for c_out, c_fl in zip(out["palettes"][f], floor["palettes"][f]):
            for a, b in zip(c_out, c_fl):
                deltas.append((a - b) / 65536.0)
    frac = surviving_fraction(deltas)
    print(f"  (3) acceptance harness wired: surviving_fraction(untrained)={frac:.4f} "
          f"(marginCoeffLatent={MARGIN_COEFF_LATENT:.2e}); the REAL number needs a TRAINED model.")

    # (4) ponder halting is a proper distribution; more paint refines deeper.
    d0 = ponder_halt(8, 0.0)
    d_paint = ponder_halt(8, 4.0)
    assert abs(sum(d0) - 1.0) < 1e-9 and abs(sum(d_paint) - 1.0) < 1e-9, "halt dist must sum to 1"
    assert d_paint[0] < d0[0], "more paint must lower the immediate-halt probability (refine deeper)"
    print("  (4) ponder halt OK: proper distribution; paint lowers immediate-halt (refines deeper)")

    print("full_matrix_model: STRUCTURAL forward wired to Spec.ModelIO (UNTRAINED, ready to train).")


if __name__ == "__main__":
    _smoke()

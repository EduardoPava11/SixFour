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


def _nudge_magnitude(nudge):
    """Total paint magnitude of a CellBudget (0 at the neutral nudge). The signal forward READS."""
    return sum(abs(v) for row in nudge for v in row)


def forward(mi: ModelInput, k: int = 16, steps: int = 0, lr: float = 0.5, seed: int = 0, theta=None):
    """ModelInput -> ModelOutput. The learned heads ride ABOVE build_floor; steps=0 is the untrained pass.
    READS mi_nudge / mi_gauge: when a conditioning `theta` is supplied AND the nudge is painted, the
    invented detail is added to the VALUE (palette); a NEUTRAL nudge (or theta=None) yields EXACTLY the
    floor-based output (lawNeutralNudgeIsAllFloor). Returns a ModelOutput dict (the Spec.ModelIO contract)."""
    floor = build_floor(mi)
    out_palettes, out_cube = [], []
    for f, (fpal, fplane) in enumerate(zip(floor["palettes"], floor["cube"])):
        pixels = _frame_pixels(fpal, fplane)
        kk = min(k, len(set(map(tuple, pixels.tolist()))))   # never ask for more colours than exist
        palette_q16, index = value_content_heads(pixels, max(1, kk), steps, lr, seed + f)
        out_palettes.append([tuple(c) for c in palette_q16])
        out_cube.append(index)
    out = {"palettes": out_palettes, "cube": out_cube}

    # READ mi_nudge: condition the invented detail on the paint. Neutral nudge or no theta => no change.
    if theta is not None and _nudge_magnitude(mi.mi_nudge) > 0:
        out = _apply_nudge_conditioning(out, mi.mi_nudge, mi.mi_gauge, theta)
    return out


def _apply_nudge_conditioning(out, nudge, gauge, theta):
    """Add the nudge-conditioned residual (full_matrix_train.condition_cell) to the VALUE palette of the
    painted region. The first non-neutral cell's 9-vec drives the first frame's leading 2x2x2 cell; a
    neutral nudge never reaches here (caller-gated), so the floor is preserved when unpainted."""
    from full_matrix_train import condition_cell
    from full_matrix_loss import cell_from_output
    side_out = int(round(len(out["cube"][0]) ** 0.5))
    budget = next((row for row in nudge if any(v != 0 for v in row)), [0] * 9)
    floor_cell = cell_from_output(out, 0, side_out, 0, 0)
    inv = condition_cell(floor_cell, budget, theta, gauge=gauge)
    # write the conditioned colours back as new palette entries the region's pixels point at.
    new = {"palettes": [list(p) for p in out["palettes"]], "cube": [list(c) for c in out["cube"]]}
    for vi, (L, a, b, x, y, t) in enumerate(inv):
        f = t
        px = (y) * side_out + (x)
        pal = new["palettes"][f]
        pal.append((L, a, b))                    # new VALUE colour
        new["cube"][f][px] = len(pal) - 1        # the region's pixel points at the invented colour
    return new


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

    # (2) the VALUE head genuinely DESCENDS on a NON-degenerate frame (more distinct colours than K, so
    #     the quantizer CANNOT reconstruct exactly -> real positive loss, strictly decreasing). This
    #     refutes the loss=0 vacuity the review flagged (a 2-colour frame reconstructs exactly = no-op).
    from frame_palette import quantize
    rng = np.random.default_rng(0)
    many = rng.integers(0, 65536, size=(256, 3)).astype(np.int64)    # 256 distinct OKLab-ish pixels
    _, traj = quantize(many, k=8, steps=30, lr=0.3, seed=0)          # K=8 << 256 distinct -> lossy
    assert np.isfinite(traj[-1]), "value-head loss must be finite"
    assert traj[0] > 0 and traj[-1] < traj[0], \
        f"value head must STRICTLY descend on a non-degenerate frame ({traj[0]:.6f} -> {traj[-1]:.6f})"
    print(f"  (2) value-head DESCENDS on a non-degenerate frame: recon_MSE {traj[0]:.6f} -> {traj[-1]:.6f} "
          f"(drop={traj[0]-traj[-1]:.6f}); genuinely trainable, not a loss=0 no-op")

    # (3) the acceptance harness on the REAL deterministic floor (piped upscale256 -> cell_from_output ->
    #     cell_margin/verdict). An UNTRAINED head does NOT beat the floor, so the verdict is FLOORED --
    #     proving the harness is wired AND honest (untrained CANNOT pass as LEARNING).
    from full_matrix_loss import cell_from_output
    from above_floor_margin import cell_margin, dashboard_verdict
    floor = build_floor(mi)
    side_out = int(round(len(out["cube"][0]) ** 0.5))
    model_cell = cell_from_output(out, 0, side_out, 0, 0)
    floor_cell = cell_from_output(floor, 0, side_out, 0, 0)
    target_cell = [(L, a + 4000, b - 4000, x, y, t) for (L, a, b, x, y, t) in floor_cell]  # held detail
    m = cell_margin(model_cell, target_cell, floor_cell)
    deltas = [(mc[i] - fc[i]) / 65536.0 for mc, fc in zip(model_cell, floor_cell) for i in range(3)]
    frac = surviving_fraction(deltas)
    verdict = dashboard_verdict(m, frac, collapsed=False, diverged=False)
    assert verdict in ("FLOORED", "MEAN-ONLY"), f"an UNTRAINED head must NOT pass as LEARNING (got {verdict})"
    print(f"  (3) acceptance harness wired on the REAL floor: untrained verdict={verdict} "
          f"(held={m['held']} vs floor={m['floor']}; correctly NOT LEARNING)")

    # (4) ponder halting is a proper distribution; more paint refines deeper.
    d0 = ponder_halt(8, 0.0)
    d_paint = ponder_halt(8, 4.0)
    assert abs(sum(d0) - 1.0) < 1e-9 and abs(sum(d_paint) - 1.0) < 1e-9, "halt dist must sum to 1"
    assert d_paint[0] < d0[0], "more paint must lower the immediate-halt probability (refine deeper)"
    print("  (4) ponder halt OK: proper distribution; paint lowers immediate-halt (refines deeper)")

    # (5) forward READS mi_nudge: a NEUTRAL nudge (or no theta) yields exactly the floor-based output; a
    #     PAINTED nudge with a conditioning theta changes the output (the input half is no longer inert).
    from cell_budget import paint_cell_pair
    base_out = forward(mi, k=4, steps=0, theta=None)
    theta = [0, 0, 0, 600, 0, 0, 0, 0, 0]                       # nonzero on the (a,x) channel
    neutral_cond = forward(mi, k=4, steps=0, theta=theta)       # neutral nudge -> still the floor output
    assert neutral_cond == base_out, "a neutral nudge must yield exactly the floor output (theta irrelevant)"
    mi_painted = ModelInput(mi_capture=cap, mi_nudge=paint_cell_pair(mi.mi_nudge, 0, 3, 5), mi_gauge=False)
    painted_cond = forward(mi_painted, k=4, steps=0, theta=theta)
    assert painted_cond != base_out, "a PAINTED nudge with theta must change the output (mi_nudge is read)"
    print("  (5) forward READS mi_nudge: neutral=floor, painted+theta conditions the output (input half live)")

    print("full_matrix_model: STRUCTURAL forward wired to Spec.ModelIO; mi_nudge READ (UNTRAINED, ready to train).")


if __name__ == "__main__":
    _smoke()

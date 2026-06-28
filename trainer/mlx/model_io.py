"""The model boundary: Spec.ModelIO.ModelInput -> ModelOutput (the one contract the trainer targets).

INPUT  = ModelInput { miCapture (a 64^3 UpscaleInput), miNudge (CellBudget), miGauge (phi6 bool) }.
OUTPUT = ModelOutput = UpscaleOutput = per-frame palettes (VALUE) + index planes (CONTENT) = GIF89a.
FLOOR  = build_floor(mi) = upscale256(mi.miCapture): the deterministic 256^3 the learned head rides above.

The learned PonderNet invention is applied ABOVE the floor where the user paints; this module is the
plumbing + the byte-exact floor (reusing trainer/mlx/upscale256.py, the Phase-1 oracle-verified port).
Mirrors spec/src/SixFour/Spec/ModelIO.hs.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Dict, List

from upscale256 import upscale256
from cell_budget import neutral_nudge, N_CELLS


# A 64^3 capture in the Spec.Upscale256.UpscaleInput schema (the dict the Phase-1 port consumes).
UpscaleInputDict = Dict[str, Any]


@dataclass
class ModelInput:
    """Spec.ModelIO.ModelInput. miGauge defaults False (the unification's open-decision call: fix one
    gauge value for the first corpus to cut variance; train both later)."""
    mi_capture: UpscaleInputDict             # the 64^3 capture (UpscaleInput dict)
    mi_nudge: List[List[int]] = field(default_factory=lambda: neutral_nudge(N_CELLS))  # 16^3 x 9 paint
    mi_gauge: bool = False                    # the phi6 gauge toggle


# Spec.ModelIO.ModelOutput = UpscaleOutput: {"palettes": [[ (l,a,b) ... ] ...], "cube": [[int ...] ...]}.
ModelOutput = Dict[str, Any]


def build_floor(mi: ModelInput) -> ModelOutput:
    """Spec.ModelIO.buildFloor = upscale256 . miCapture. The deterministic floor at ANY nudge: paint adds
    learned invention ABOVE this, it does not move the floor (lawNeutralNudgeIsAllFloor)."""
    return upscale256(mi.mi_capture)


def render_frame(out: ModelOutput, f: int):
    """Spec.ModelIO.renderFrame: the (palette, index plane) pair the UI draws for frame f."""
    return (out["palettes"][f], out["cube"][f])


def capture_to_upscale_input(palettes_q16, indices, side: int) -> UpscaleInputDict:
    """Assemble an UpscaleInput from a per-frame capture (e.g. synth_capture.SyntheticCapture).

    SINGLE-CUBE PER-FRAME assembly: cube A = cube B = the per-frame indices, paletteMap = identity, global
    = the per-frame palette, no anchors, empty exit, nothing killed, lambda = 0 (plain nearestQ16). It
    produces a VALID, deterministic floor.

    This is the MVP1-CORRECT floor, NOT a stopgap. The richer TWO-CUBE cascade (global-collapse cube A +
    cross-frame paletteMap) is the GLOBAL-palette path, which Spec.GlobalCollapseQ16 marks V2-DEFERRED
    (Feature.globalPaletteV2 = false, HARD MUST #1 = per-frame palettes only, "do not add new callers").
    So the global cascade is intentionally NOT built here -- building it would contradict the spec. The
    lambda=1 drift-prior / anchor parts of upscale256 ARE exercised + byte-exact-gated by the Phase-1
    golden (test_upscale256.py), just not driven from this synthetic per-frame capture.

    palettes_q16 : (T, K, 3) per-frame Q16 OKLab palettes.
    indices      : (T, side*side) per-frame palette indices.
    """
    frames = len(palettes_q16)
    palettes = [[tuple(int(c) for c in px) for px in pal] for pal in palettes_q16]
    cube = [[int(i) for i in plane] for plane in indices]
    k = len(palettes[0]) if palettes else 0
    return {
        "frames": frames,
        "side": side,
        "palettes": palettes,
        "map": [list(range(k)) for _ in range(frames)],   # identity paletteMap
        "global": palettes[0] if palettes else [],
        "cubeB": cube,
        "cubeA": cube,
        "killThreshold": 1 << 30,                          # nothing killed (L never exceeds this)
        "exitDrift": [],                                   # empty exit (no carried drift)
        "anchors": [],
        "lambda": 0,                                       # lambda=0 => quantizer is plain nearestQ16
    }


def _self_test():
    # A tiny 2-frame, side-2 capture: build a ModelInput and confirm the floor is the upscale of the
    # capture and is invariant to the (neutral) nudge.
    pal = [[(0, 0, 0), (65536, 0, 0)], [(4096, 0, 0), (61440, 0, 0)]]
    idx = [[0, 1, 1, 0], [1, 1, 0, 0]]
    cap = capture_to_upscale_input(pal, idx, side=2)

    mi = ModelInput(mi_capture=cap, mi_nudge=neutral_nudge(N_CELLS), mi_gauge=False)
    floor = build_floor(mi)

    # shape: 4T frames each (4S)^2 = 64 px.
    assert len(floor["palettes"]) == 4 * 2, "floor must have 4T frames"
    assert all(len(plane) == (4 * 2) ** 2 for plane in floor["cube"]), "each frame is (4S)^2 px"

    # the floor is invariant to the neutral nudge AND ignores paint (it is the zero-paint deterministic
    # output; learned invention rides above it). buildFloor is a pure function of miCapture.
    from cell_budget import paint_cell_pair
    mi_painted = ModelInput(mi_capture=cap, mi_nudge=paint_cell_pair(mi.mi_nudge, 0, 0, 9), mi_gauge=True)
    assert build_floor(mi_painted) == floor, "buildFloor must depend only on miCapture, not the nudge"

    # renderFrame returns a (palette, index plane) pair.
    p, plane = render_frame(floor, 0)
    assert len(plane) == 64 and len(p) >= 1
    print("model_io: ModelInput/ModelOutput boundary OK (floor = upscale256(capture), nudge-invariant)")


if __name__ == "__main__":
    _self_test()

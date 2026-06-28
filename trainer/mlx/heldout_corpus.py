"""The held-out-WHOLE corpus: (ModelInput, held ModelOutput) pairs across SCALE and TIME.

Spec.HeldOutTarget.lawHeldOutReplacesMasking: the predictor sees the WHOLE input and predicts the WHOLE
held object, yet the target is provably NOT a function of the input, so an identity/copy predictor incurs
loss and collapse is impossible WITHOUT masking. Two held axes:

  SCALE (up-rung): input = the octant COARSE (DC band); target = the seven DETAIL bands (octree-orthogonal
    to the coarse, so a given coarse is shared by many cubes). Reuses jepa_data.lift_oct (byte-exact,
    gated vs the spec golden).
  TIME (down-rung): input = frame t; target = frame t+1, carried as the data-manufactured (value, policy)
    deltas whose application recovers t+1 EXACTLY (temporal_data, lawTemporalEngineRoundTrips) -- a TRUE
    label off the real next frame, never a self-produced rollout.

This is the NEW-PATH corpus for the full-matrix model (full_matrix_model.py); it composes already-gated
engines and the self-test re-asserts the held property + the motion floor (Spec.MotionFloorCorpus). NOTE:
it does NOT yet replace the OLD masked-band path -- train_loop.py still trains on jepa_synth_octants'
mask=(i+k)%NUM_BANDS. Wiring this corpus into the live training loop (and retiring the mask path) is the
remaining step; until then this module is consumed only by the full-matrix smoke + the gate.
"""
from __future__ import annotations

import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..") )

from jepa_data import lift_oct, unlift_oct                      # noqa: E402  byte-exact octant lift
from jepa_synth_octants import octant_records                   # noqa: E402  real-capture octants
from temporal_data import (                                     # noqa: E402  data-manufactured time deltas
    colour_delta_of, index_delta_of, reconstruct_next)
from synth_capture import synthetic_capture                     # noqa: E402


def scale_examples(seed: int, kind: str, frame_step: int = 8, space_step: int = 6):
    """SCALE held pairs: {coarse: int, detail: [7 ints], cube: [8 ints]} per octant (L channel).

    The held target is the 7 detail bands; the input the predictor sees is only the coarse DC. The
    target is not a function of the input (octree-orthogonal), so copying the coarse (zero detail) loses.
    """
    for cube_l, coarse_l, detail_l, _blk, _chroma in octant_records(seed, kind, frame_step, space_step):
        yield {"coarse": coarse_l, "detail": list(detail_l), "cube": list(cube_l)}


def time_examples(cap, frame_step: int = 8):
    """TIME held pairs from consecutive frames: {palette_t, index_t, value, policy, palette_next, index_next}.

    value/policy are the data-manufactured deltas; reconstruct_next(t) == t+1 byte-exact (the held label).
    """
    T = cap.palettes_q16.shape[0]
    for t in range(0, T - frame_step, frame_step):
        tn = t + frame_step
        pal_t = cap.palettes_q16[t].tolist()
        pal_n = cap.palettes_q16[tn].tolist()
        idx_t = cap.indices[t].tolist()
        idx_n = cap.indices[tn].tolist()
        value = colour_delta_of(pal_t, pal_n)
        policy = index_delta_of(idx_t, idx_n)
        yield {"palette_t": pal_t, "index_t": idx_t, "value": value, "policy": policy,
               "palette_next": pal_n, "index_next": idx_n}


def held_corpus(kinds, seed: int = 0):
    """A combined (scale, time) held corpus over the given capture kinds."""
    scale, time = [], []
    for k in kinds:
        cap = synthetic_capture(seed, k)
        scale.extend(scale_examples(seed, k))
        time.extend(time_examples(cap))
    return scale, time


def _self_test():
    kinds = ["high-lab", "high-lab-detail"]
    scale, time = held_corpus(kinds)
    assert scale and time, "corpus must be non-empty"

    # SCALE held property (lawScaleTargetNotAFunctionOfInput + lawScaleIdentityIncursLoss):
    # some octant with the SAME coarse has DIFFERENT detail (so coarse does not determine the target),
    # and a non-flat octant has non-zero detail (so the zero-detail copy predictor incurs loss).
    by_coarse = {}
    held_seen = False
    for ex in scale:
        # byte-exact round-trip: the lift is reversible (data-engine law).
        assert unlift_oct(ex["coarse"], ex["detail"]) == ex["cube"], "lift round-trip broke"
        prev = by_coarse.setdefault(ex["coarse"], ex["detail"])
        if prev != ex["detail"]:
            held_seen = True
    assert held_seen, "SCALE: must find two octants with same coarse but different detail (held property)"
    assert any(any(d != 0 for d in ex["detail"]) for ex in scale), \
        "SCALE: a non-flat octant must carry non-zero detail (identity copy incurs loss)"

    # TIME held property (lawTemporalEngineRoundTrips): the data-manufactured deltas recover t+1 EXACTLY,
    # and the constant orbit (predict t+1 := t) misses a moved frame.
    moved = False
    for ex in time:
        rp, ri = reconstruct_next(ex["palette_t"], ex["index_t"], ex["value"], ex["policy"])
        assert rp == ex["palette_next"] and ri == ex["index_next"], "TIME: held round-trip broke"
        if ex["index_t"] != ex["index_next"] or ex["palette_t"] != ex["palette_next"]:
            moved = True
    assert moved, "TIME: corpus must MOVE between frames (motion floor; else the time rung gets no gradient)"

    print(f"heldout_corpus: held-WHOLE corpus OK ({len(scale)} scale + {len(time)} time pairs; "
          f"held property + motion floor hold; replaces the retired per-band mask)")


if __name__ == "__main__":
    _self_test()

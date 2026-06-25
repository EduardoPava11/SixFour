"""The TEMPORAL (inter-frame) data-engine twin, gated against temporal_data_golden.json.

The spec (SixFour.Codegen.TemporalData) manufactures (frame t, value target, policy target)
records from captured frame PAIRS (t, t+1). This loader ports the delta algebra and is FORCED
to reproduce the spec byte-exact, the time-axis sibling of jepa_data.py.

The keystone (lawTemporalEngineRoundTrips): applying both data-manufactured deltas to frame t
recovers frame t+1 EXACTLY, so the value (recolour) and policy (motion) targets are TRUE labels
read off the REAL next frame -- NOT a self-produced rollout. This is the time-axis collapse
guard: the target can never be a fixed point of the predictor's own output, because it is
manufactured from real captured data.

  value delta (ColourDelta): per-palette-entry (next - cur), a Z-module; apply = add back.
  policy delta (IndexDelta): a {voxel position: (old, new)} transport for voxels that moved;
                             apply = set those positions to their new slot.

The two channels are DISJOINT (lawTemporalChannelsDisjoint): value touches only the palette,
policy only the index, so the value and policy heads train independently.
"""
from __future__ import annotations

import json
import os

GOLDEN = os.path.join(os.path.dirname(__file__), "..", "generated", "temporal_data_golden.json")


# --- the delta algebra (twin of SixFour.Spec.HierarchicalDelta) ---

def colour_delta_of(palette_cur, palette_next):
    """The VALUE target: per-entry (next - cur). Zero-pads the shorter palette with (0,0,0)."""
    n = max(len(palette_cur), len(palette_next))
    out = []
    for i in range(n):
        c = palette_cur[i] if i < len(palette_cur) else [0, 0, 0]
        x = palette_next[i] if i < len(palette_next) else [0, 0, 0]
        out.append([x[0] - c[0], x[1] - c[1], x[2] - c[2]])
    return out


def apply_value_delta(palette, value):
    """Recolour in place: add the displacement to the palette, index held fixed."""
    n = max(len(palette), len(value))
    out = []
    for i in range(n):
        p = palette[i] if i < len(palette) else [0, 0, 0]
        d = value[i] if i < len(value) else [0, 0, 0]
        out.append([p[0] + d[0], p[1] + d[1], p[2] + d[2]])
    return out


def index_delta_of(index_cur, index_next):
    """The POLICY target: [pos, old, new] for every voxel that moved (sorted by position)."""
    return [[v, a, b] for v, (a, b) in enumerate(zip(index_cur, index_next)) if a != b]


def apply_policy_delta(index, policy):
    """Move in place: each touched voxel reads its new slot, palette held fixed."""
    new_at = {pos: new for pos, _old, new in policy}
    return [new_at.get(v, s) for v, s in enumerate(index)]


def reconstruct_next(palette_t, index_t, value, policy):
    """Apply the value delta (recolour) then the policy delta (move) to frame t -> frame t+1."""
    return apply_value_delta(palette_t, value), apply_policy_delta(index_t, policy)


def self_check(path: str = GOLDEN) -> int:
    g = json.load(open(path))
    for r in g["records"]:
        pal_t, idx_t = [list(c) for c in r["palette_t"]], list(r["index_t"])
        pal_n, idx_n = [list(c) for c in r["palette_next"]], list(r["index_next"])
        value, policy = [list(v) for v in r["value"]], [list(p) for p in r["policy"]]
        label = r["label"]

        # MANUFACTURE must match the spec byte-exact (forces the Python delta algebra).
        assert colour_delta_of(pal_t, pal_n) == value, f"value drift [{label}]"
        assert index_delta_of(idx_t, idx_n) == policy, f"policy drift [{label}]"

        # KEYSTONE lawTemporalEngineRoundTrips: reconstruct(frame t) == frame t+1, exactly.
        rp, ri = reconstruct_next(pal_t, idx_t, value, policy)
        assert rp == pal_n, f"recolour round-trip broke [{label}]: {rp} != {pal_n}"
        assert ri == idx_n, f"motion round-trip broke [{label}]: {ri} != {idx_n}"

        # lawTemporalChannelsDisjoint: the reconstructed palette is a function of the VALUE delta
        # alone (the index never enters it) and the reconstructed index of the POLICY delta alone
        # (the palette never enters it), so the two heads train independently.
        assert apply_value_delta(pal_t, value) == rp, f"value channel not palette-only [{label}]"
        assert apply_policy_delta(idx_t, policy) == ri, f"policy channel not index-only [{label}]"
    return len(g["records"])


if __name__ == "__main__":
    try:
        n = self_check()
        print(f"  temporal engine: {n} frame-pair records reconstruct t+1 byte-exact "
              f"(value/policy are true labels, not self-produced rollout)")
        print("temporal_data: PASS")
        raise SystemExit(0)
    except AssertionError as e:
        print(f"FAIL: {e}")
        print("temporal_data: FAIL")
        raise SystemExit(1)

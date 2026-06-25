"""Per-scale conditioning with the 16-cubed identity carve-out, the twin of
spec/SixFour/Spec/PerScaleWeights.hs (graft #2 of the v2 design).

The octree canon mandates PER-SCALE weights: each rung of the ladder carries its OWN learned
gain on its detail bands, not one tied block reused at every depth. A weighting is a
depth-indexed list of integer gains applied to the detail levels; the COARSE value (the
balance/DC carrier L) is never touched.

Two properties pin the canon, plus the build-plan carve-out:
  * lawNeutralIsFloor      - neutral (all-1) weighting is the exact reversible floor: zero
                             learned change => identity (bounded addition above a frozen floor).
  * lawPerScaleExceedsTied - a genuinely per-scale weighting ([1,3]) is unreachable by any tied
                             weight ([1,1] / [3,3]); per-scale strictly subsumes the tied block.
  * 16-cubed identity      - pure scale-invariance of the learned inventor is FALSE
                             (lawTransferDegradesUnderLawShift), so the coarsest rung (the 16³
                             floor) is pinned to gain 1: conditioning may reshape the finer
                             rungs but never the byte-exact floor.
"""
from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from jepa_data import lift_oct, unlift_oct  # noqa: E402  (gated against the spec golden)


def neutral(n: int) -> list[int]:
    """The neutral weighting for n levels: gain 1 everywhere = the reversible floor."""
    return [1] * n


def tied(n: int, k: int) -> list[int]:
    """The retired tied design: one weight k reused at every one of n levels."""
    return [k] * n


def apply_per_scale(weights, distilled):
    """Scale each detail level by its per-scale gain; the coarse value is untouched.

    `distilled` is (coarse, levels) where levels is a list (one per rung) of 7-tuple details.
    """
    coarse, levels = distilled
    scaled = [tuple(b * w for b in det) for w, det in zip(weights, levels)]
    return (coarse, scaled)


def with_sixteen_cubed_identity(weights, floor_level: int = -1):
    """The carve-out: force the 16-cubed floor rung's gain to 1, whatever conditioning proposed.

    The coarsest rung is the byte-exact floor; the learned inventor is NOT scale-invariant, so
    the conditioning is allowed on finer rungs only. Returns a copy with floor_level pinned to 1.
    """
    w = list(weights)
    if w:
        w[floor_level] = 1
    return w


# ---------------------------------------------------------------------------
# Laws (PerScaleWeights.hs:63-83), as Python predicates.
# ---------------------------------------------------------------------------

def law_neutral_is_floor(cube) -> bool:
    """Neutral weighting then synthesize recovers the input: zero learned change => identity.
    Realized on the gated single-rung lift (coarse + one 7-band detail level)."""
    coarse, detail = lift_oct(cube)
    distilled = (coarse, [tuple(detail)])
    _, scaled = apply_per_scale(neutral(1), distilled)
    return unlift_oct(coarse, list(scaled[0])) == cube


def law_per_scale_exceeds_tied() -> bool:
    """A genuinely per-scale weighting ([1,3]) is unreachable by either tied weight that agrees
    on one rung ([1,1] or [3,3]) on a non-constant two-level cube."""
    distilled = (0, [(0, 1, 2, 3, 4, 5, 6), (10, 20, 30, 40, 50, 60, 70)])
    per = apply_per_scale([1, 3], distilled)
    return per != apply_per_scale([1, 1], distilled) and per != apply_per_scale([3, 3], distilled)


def law_sixteen_cubed_is_identity() -> bool:
    """The carve-out pins the floor rung to gain 1 regardless of the proposed conditioning, and
    a neutral-everywhere weighting leaves the whole distilled cube unchanged."""
    proposed = [5, 9, 7]            # arbitrary learned conditioning
    pinned = with_sixteen_cubed_identity(proposed, floor_level=-1)
    distilled = (0, [(1, 0, 0, 0, 0, 0, 0)] * 3)
    floor_unchanged = pinned[-1] == 1
    neutral_identity = apply_per_scale(neutral(3), distilled) == distilled
    return floor_unchanged and neutral_identity


if __name__ == "__main__":
    fails = 0

    # neutral is the reversible floor on several real octant cubes.
    for cube in ([10, 20, 30, 40, 50, 60, 70, 80],
                 [0, 0, 0, 0, 0, 0, 0, 0],
                 [5, 5, 5, 5, 9, 9, 9, 9],
                 [40715, 40700, 40720, 40710, 40730, 40690, 40715, 40705]):
        if not law_neutral_is_floor(cube):
            print(f"FAIL: neutral weighting is not the floor on {cube}"); fails += 1
    if fails == 0:
        print("  neutral == floor: all-1 weighting round-trips byte-exact (zero learned change)")

    if not law_per_scale_exceeds_tied():
        print("FAIL: per-scale weighting did not exceed the tied block"); fails += 1
    else:
        print("  per-scale > tied: [1,3] is unreachable by [1,1] or [3,3] (strictly more expressive)")

    if not law_sixteen_cubed_is_identity():
        print("FAIL: 16-cubed floor was not pinned to identity"); fails += 1
    else:
        print("  16-cubed carve-out: floor rung pinned to gain 1 (conditioning reshapes finer rungs only)")

    print("per_scale: PASS" if fails == 0 else f"per_scale: {fails} FAIL")
    raise SystemExit(1 if fails else 0)

"""The cross-encoder information-floor losses, the twin of SixFour.Spec.DualEncoderJepa and
SixFour.Spec.MidLatentCrossPrediction. These are the L_cross and L_mid terms of the composite
H-JEPA objective.

A DualExample is (b_context, a_context, true_band): the same masked band seen with Encoder B's
visible context key AND Encoder A's. The loss machinery is a pure information floor:

  sse_best_const(vs)        = min_c sum (c - v)^2  -- the best a single constant can do.
  best_loss_under(key, exs) = group examples by the context key, fit the best constant per
                              group, sum. A more-informative key partitions finer, so its floor
                              is never larger.
  b_only_loss = floor under B's context alone;  joint_loss = floor under the joint (B, A) key.

Two keystones, same machinery at two scales:
  * lawCrossEncoderContextStrictlyHelps (surfaced rung) -- when A resolves a collision B leaves,
    joint_loss < b_only_loss; when A is redundant, they tie. The win comes from A carrying real
    information, not from the extra key.
  * lawMidCrossEncoderStrictlyHelps (the never-surfaced 32-cubed midpoint, where the top-down 16
    plan and bottom-up 64 flows meet) -- the same property on fresh midpoint witnesses, so it
    binds the midpoint objective rather than aliasing the surfaced-rung keystone.

Both targets are the bit-exact data-manufactured held band (no EMA, no L_close orbit).
"""
from __future__ import annotations

# A DualExample is the tuple (b_context, a_context, true_band).

def sse_best_const(vs) -> int:
    """The information floor: min over integer constants c of sum (c - v)^2."""
    if not vs:
        return 0
    lo, hi = min(vs), max(vs)
    return min(sum((c - v) ** 2 for v in vs) for c in range(lo, hi + 1))


def best_loss_under(key_fn, exs) -> int:
    """Best achievable loss for a predictor that may depend ONLY on key_fn: group, fit, sum."""
    groups: dict = {}
    for e in exs:
        groups.setdefault(key_fn(e), []).append(e[2])  # e[2] = true_band
    return sum(sse_best_const(vs) for vs in groups.values())


def b_only_loss(exs) -> int:
    """The information floor of Encoder B's context alone."""
    return best_loss_under(lambda e: e[0], exs)


def joint_loss(exs) -> int:
    """The information floor of the JOINT (B, A) cross-encoder context."""
    return best_loss_under(lambda e: (e[0], e[1]), exs)


def law_cross_encoder_strictly_helps() -> bool:
    """Surfaced-rung keystone: A resolves a B-collision (strict help) and ties when redundant."""
    helpful = [(5, 0, 10), (5, 1, 20)]    # same B-context, A separates, distinct held bands
    redundant = [(5, 0, 10), (5, 0, 20)]  # A does not vary -> no free win
    return (joint_loss(helpful) == 0
            and joint_loss(helpful) < b_only_loss(helpful)
            and b_only_loss(helpful) > 0
            and joint_loss(redundant) == b_only_loss(redundant))


def law_mid_cross_encoder_strictly_helps() -> bool:
    """Midpoint-local (32-cubed) keystone: the same property on fresh midpoint witnesses."""
    helpful = [(7, 0, 100), (7, 1, 200)]
    redundant = [(7, 0, 100), (7, 0, 200)]
    return (joint_loss(helpful) == 0
            and joint_loss(helpful) < b_only_loss(helpful)
            and b_only_loss(helpful) > 0
            and joint_loss(redundant) == b_only_loss(redundant))


if __name__ == "__main__":
    fails = 0

    # sse_best_const is the integer-constant information floor
    if sse_best_const([10, 20]) != 50:        # min at c=15: 25 + 25 = 50
        print(f"FAIL: sse_best_const([10,20]) {sse_best_const([10,20])} != 50"); fails += 1
    if sse_best_const([7, 7, 7]) != 0:
        print("FAIL: constant batch has nonzero floor"); fails += 1

    # a finer (more informative) key never has a larger floor
    exs = [(5, 0, 10), (5, 1, 20), (6, 0, 30)]
    if not (joint_loss(exs) <= b_only_loss(exs)):
        print("FAIL: joint floor exceeds B-only floor"); fails += 1

    if not law_cross_encoder_strictly_helps():
        print("FAIL: surfaced-rung cross-encoder does not strictly help"); fails += 1
    else:
        h = [(5, 0, 10), (5, 1, 20)]
        print(f"  L_cross: joint {joint_loss(h)} < B-only {b_only_loss(h)} when A resolves; "
              f"ties when A redundant")

    if not law_mid_cross_encoder_strictly_helps():
        print("FAIL: midpoint cross-encoder does not strictly help"); fails += 1
    else:
        print("  L_mid: same strict-help/redundancy property at the never-surfaced 32-cubed midpoint")

    print("dual_loss: PASS" if fails == 0 else f"dual_loss: {fails} FAIL")
    raise SystemExit(1 if fails else 0)

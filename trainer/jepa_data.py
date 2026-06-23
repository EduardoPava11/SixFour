#!/usr/bin/env python3
"""The I-JEPA data engine (Python side).

Manufactures the (context, mask, held-target) training records the MLX I-JEPA-head trainer
consumes, by the SAME reversible lift the spec uses. It is FORCED to match the spec: every
record it manufactures is asserted byte-exact against the spec-emitted corpus golden
(trainer/generated/jepa_data_golden.json, written by SixFour.Codegen.JepaData). If this
Python lift drifts from the spec by one integer, the self-test fails -- so the spec is the
design authority for the training data, not just a description of it.

The lift is a pure-integer S-transform; Python `//` is floor division, matching Haskell `div`,
so the port is bit-exact. Reversibility (reconstruct == cube) is proven in the spec
(Spec.JepaData.lawDataEngineRoundTrips); here we mirror manufacture + reconstruct.

Run `python3 trainer/jepa_data.py` to self-check against the golden.
"""
import json
import os

GOLDEN = os.path.join(os.path.dirname(__file__), "generated", "jepa_data_golden.json")


def s_lift(x, y):
    """The exact integer S-transform: low = y + floor((x-y)/2), high = x-y."""
    d = x - y
    return (y + (d // 2), d)


def s_unlift(lo, hi):
    """The exact inverse of s_lift."""
    y = lo - (hi // 2)
    return (y + hi, y)


def lift_quad(a, b, c, d):
    """2x2 -> RGBT (R=LL, G=LH, B=HL, T=HH)."""
    la, ha = s_lift(a, b)
    lc, hc = s_lift(c, d)
    ll, lh = s_lift(la, lc)
    hl, hh = s_lift(ha, hc)
    return (ll, lh, hl, hh)


def unlift_quad(r, g, b, t):
    la, lc = s_unlift(r, g)
    ha, hc = s_unlift(b, t)
    a, bb = s_unlift(la, ha)
    c, d = s_unlift(lc, hc)
    return (a, bb, c, d)


def lift_oct(cube):
    """2x2x2 -> (coarse, [7 detail]). Mirrors SixFour.Spec.OctreeCell.liftOct."""
    a, b, c, d, e, f, g, h = cube
    r0, g0, b0, t0 = lift_quad(a, b, c, d)
    r1, g1, b1, t1 = lift_quad(e, f, g, h)
    rr, dz = s_lift(r0, r1)
    return rr, [g0, b0, t0, g1, b1, t1, dz]


def unlift_oct(coarse, detail):
    """The exact inverse of lift_oct."""
    g0, b0, t0, g1, b1, t1, dz = detail
    r0, r1 = s_unlift(coarse, dz)
    a, b, c, d = unlift_quad(r0, g0, b0, t0)
    e, f, g, h = unlift_quad(r1, g1, b1, t1)
    return [a, b, c, d, e, f, g, h]


def manufacture(cube, mask):
    """Manufacture one training record from an octant. Returns (coarse, detail, target).
    The held-target = detail[mask]; the context = coarse + the 6 other bands."""
    coarse, detail = lift_oct(cube)
    return coarse, detail, detail[mask]


def load_golden(path=GOLDEN):
    with open(path) as fh:
        return json.load(fh)


def self_check(path=GOLDEN):
    """FORCE the Python data engine to match the spec: every golden record must be reproduced
    byte-exact, and reconstruct(manufacture)==cube (the round-trip the spec proves)."""
    g = load_golden(path)
    n = 0
    for rec in g["records"]:
        cube, mask = rec["cube"], rec["mask"]
        coarse, detail, target = manufacture(cube, mask)
        assert coarse == rec["coarse"], f"coarse drift: {coarse} != {rec['coarse']} (mask {mask})"
        assert detail == rec["detail"], f"detail drift: {detail} != {rec['detail']}"
        assert target == rec["target"], f"target drift: {target} != {rec['target']}"
        assert unlift_oct(coarse, detail) == cube, f"round-trip broke: cube {cube}"
        n += 1
    return n


if __name__ == "__main__":
    count = self_check()
    print(f"jepa_data: {count} records reproduce the spec corpus byte-exact + round-trip OK ✓")

"""The Gaussian-chroma (Z[i]) knob, carried into the trainer.

The trainer twin of SixFour.Spec.GaussianChroma. The value head (delta_surrogate.py)
treats a ColourDelta as [[l, a, b], ...] with the two chroma axes (a, b) as
independent floats. This module packs the chroma pair into ONE Gaussian integer
a + b*i and adds the operation that re-encoding unlocks: complex MULTIPLICATION is
a hue rotation of the chroma plane (the unit i = an exact 90-degree quarter-turn),
which two independent scalar channels have no single algebraic op for.

Integer-exact by construction (Gaussian multiply on int tuples, NOT Python complex
floats), mirroring the spec's `rmul (Gaussian ...)`. The spec is the authority; this
twin re-checks the SAME laws so the trainer cannot drift from the proven algebra.
Pure Python (no MLX) so it runs in the trainer gate everywhere.
"""
from __future__ import annotations


# --- the ring Z[i] on integer (a, b) chroma tuples (matches Spec.RefinementSystem.Gaussian) ---

GAUSS_I = (0, 1)            # the unit i: a quarter-turn of the chroma plane


def gadd(z, w):
    (a, b), (c, d) = z, w
    return (a + c, b + d)


def gmul(z, w):
    """(a+bi)(c+di) = (ac-bd) + (ad+bc)i — the exact Gaussian product."""
    (a, b), (c, d) = z, w
    return (a * c - b * d, a * d + b * c)


def gauss_norm(z):
    """The squared chroma radius a^2 + b^2 (preserved by a unit multiply, scaled otherwise)."""
    a, b = z
    return a * a + b * b


def pack_chroma(a, b):
    return (a, b)


def unpack_chroma(z):
    return (z[0], z[1])


# --- the knob's payoff: hue rotation as a structured, exactly-invertible recolour op ---

def hue_rotate(z, steps=1):
    """Rotate a chroma value by `steps` quarter-turns (multiply by i, steps times). Order 4."""
    for _ in range(steps % 4):
        z = gmul(GAUSS_I, z)
    return z


def hue_rotate_colour_delta(colour_delta, steps=1):
    """Apply a hue rotation to a ColourDelta [[l, a, b], ...]: L untouched, chroma rotated.
    Exactly invertible (4 steps = identity), so it is a lossless recolour augmentation the
    value head can train against."""
    out = []
    for l, a, b in colour_delta:
        ra, rb = hue_rotate((a, b), steps)
        out.append([l, ra, rb])
    return out


# --- the laws (the Python twin of the spec's GaussianChroma laws) ---

def _check():
    fails = 0
    samples = [(0, 0), (1, 0), (0, 1), (3, 4), (-5, 2), (7, -9), (-3, -8), (12, 5)]

    # 1. FAITHFUL: Z[i] addition == componentwise real-pair addition.
    for (a, b) in samples:
        for (c, d) in samples:
            if unpack_chroma(gadd(pack_chroma(a, b), pack_chroma(c, d))) != (a + c, b + d):
                print(f"FAIL: chroma add not faithful at {(a,b)}+{(c,d)}"); fails += 1

    # 2. The unit i is an exact 90-degree quarter-turn (a,b) -> (-b,a).
    for (a, b) in samples:
        if gmul(GAUSS_I, (a, b)) != (-b, a):
            print(f"FAIL: i*({a},{b}) != ({-b},{a})"); fails += 1

    # 3. The quarter-turn preserves the chroma norm (it is a rotation, not a scale).
    for z in samples:
        if gauss_norm(gmul(GAUSS_I, z)) != gauss_norm(z):
            print(f"FAIL: quarter-turn changed the norm at {z}"); fails += 1

    # 4. The quarter-turn has order 4: i^4 = 1.
    for z in samples:
        if hue_rotate(z, 4) != z:
            print(f"FAIL: quarter-turn not order 4 at {z}"); fails += 1

    # 5. Carried into the value head: a hue rotation is a lossless recolour cycle (4 = identity),
    #    and it leaves L untouched.
    cd = [[10, 3, 4], [-2, 7, -9], [0, -5, 2]]
    if hue_rotate_colour_delta(cd, 4) != cd:
        print("FAIL: 4 hue rotations is not the identity on a ColourDelta"); fails += 1
    if any(r[0] != c[0] for r, c in zip(hue_rotate_colour_delta(cd, 1), cd)):
        print("FAIL: hue rotation disturbed the L channel"); fails += 1

    print("gaussian_chroma: PASS" if fails == 0 else f"gaussian_chroma: {fails} FAIL")
    return fails


if __name__ == "__main__":
    raise SystemExit(1 if _check() else 0)

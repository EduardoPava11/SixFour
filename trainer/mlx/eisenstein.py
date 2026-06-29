"""
eisenstein.py -- the V2 colour substrate for the trainer, ported from the Haskell spec.

This is the Python wiring of the discrete-geometry + algebraic-number-theory colour
math that the V2 model (raw sRGB 8-bit, Lab DROPPED) trains under. It mirrors, byte-for-
byte on integer inputs, the runghc-green spec exploration files:
  - spec/exploration/V2TrainingLattice.hs   (Eisenstein norm, units, the squared-Euclidean
                                             lattice loss, snapToLambda, closestLambda)
  - spec/exploration/V2A2ClosestPoint.hs     (the true A2 closest-point onto Lambda)
  - spec/exploration/V2EisensteinPrime.hs    (3 ramifies: Lambda = the ideal (1-w))

WHAT THE TRAINER GETS:
  * lattice_loss(pred_rgb, tgt_rgb): the SQUARED-EUCLIDEAN training loss in the
    (luma) (+) (A2 chroma) embedding = (d luma)^2 + N(d chroma), N(a,b)=a^2-ab+b^2.
    This replaces OKLab dE; it is positive-definite (sqrt is a genuine metric) and the
    hexagonal A2 norm is sheared away from naive Euclidean (real discrete geometry).
  * closest_lambda(l, c): the byte-exact target snapper. A byte-exact RGB target is ALREADY
    on Lambda (luma - ca - cb = 3*blue, always), so RGB palette targets need no snap; the
    snapper matters for a nudge delta or a learned residual expressed in (luma, chroma) coords.
  * hue rotation by a unit is an isometry of the loss (a global hue spin cannot lower it).

Integer arithmetic matches Haskell exactly: Python // floors toward -inf (== Haskell div) and
Python % is non-negative for a positive divisor (== Haskell mod). Verified by __main__ below.
"""

from __future__ import annotations
from typing import Optional, Tuple

import numpy as np

# Eisenstein integer = (a, b) meaning a + b*w, with w^2 = -1 - w.
Eisen = Tuple[int, int]
Pt = Tuple[int, Eisen]
RGB = Tuple[int, int, int]

# The 6 units = norm-1 elements = the six 60-degree hue rotations.
UNITS: list[Eisen] = [(1, 0), (0, 1), (-1, -1), (-1, 0), (0, -1), (1, 1)]


# --- Eisenstein ring arithmetic (scalar; matches the Haskell spec) ------------

def eadd(x: Eisen, y: Eisen) -> Eisen:
    return (x[0] + y[0], x[1] + y[1])


def esub(x: Eisen, y: Eisen) -> Eisen:
    return (x[0] - y[0], x[1] - y[1])


def emul(x: Eisen, y: Eisen) -> Eisen:
    a, b = x
    c, d = y
    return (a * c - b * d, a * d + b * c - b * d)


def enorm(x: Eisen) -> int:
    """The algebraic norm = the squared hexagonal (A2) chroma length."""
    a, b = x
    return a * a - a * b + b * b


# --- sRGB 8-bit <-> (luma, Eisenstein chroma) --------------------------------

def luma(rgb: RGB) -> int:
    r, g, b = rgb
    return r + g + b


def chroma(rgb: RGB) -> Eisen:
    """R->1, G->w, B->w^2; gray collapses to the kernel (0, 0)."""
    r, g, b = rgb
    return (r - b, g - b)


def luma_chroma_to_rgb(l: int, c: Eisen) -> Optional[RGB]:
    """Invert (luma, chroma) to RGB. Integer ONLY on the index-3 sublattice
    Lambda = {l == ca + cb (mod 3)}. Invert-or-refuse (the /3 byte-exactness guard)."""
    ca, cb = c
    if (l - ca - cb) % 3 == 0:
        bb = (l - ca - cb) // 3
        return (bb + ca, bb + cb, bb)
    return None


def in_lambda(p: Pt) -> bool:
    l, c = p
    return luma_chroma_to_rgb(l, c) is not None


def snap_to_lambda(l: int, c: Eisen) -> Pt:
    """The OLDER luma-only snapper (moves luma by 0..2, NOT minimized). Superseded by
    closest_lambda; kept for parity with the spec."""
    ca, cb = c
    return (l - ((l - ca - cb) % 3), c)


# --- the true A2 closest-point onto Lambda (the wired target snapper) ---------

def metric_cost(p0: Pt, p1: Pt) -> int:
    """Same squared-Euclidean geometry as lattice_loss, in (luma, chroma) coords."""
    l0, c0 = p0
    l1, c1 = p1
    return (l1 - l0) ** 2 + enorm(esub(c1, c0))


def _candidates(p: Pt) -> list[Pt]:
    l, c = p
    return [(l + dl, c) for dl in range(-2, 3)] + [(l, eadd(c, u)) for u in UNITS]


def closest_lambda(l: int, c: Eisen) -> Pt:
    """The TRUE nearest Lambda point under the training geometry (the byte-exact target
    snapper). Tie-break: smaller luma displacement, then smaller chroma L1."""
    tgt = (l, c)
    valid = [cand for cand in _candidates(tgt) if in_lambda(cand)]

    def rank(cand: Pt):
        cl, (ca, cb) = cand
        return (metric_cost(tgt, cand), abs(cl - l), abs(ca) + abs(cb))

    return min(valid, key=rank)


def closest_lambda_rgb(l: int, c: Eisen) -> RGB:
    """Snap a (luma, chroma) target onto Lambda and return its byte-exact integer RGB."""
    ll, cc = closest_lambda(l, c)
    rgb = luma_chroma_to_rgb(ll, cc)
    assert rgb is not None, "closest_lambda must land on Lambda"
    return rgb


# --- the training loss (scalar + vectorized for MLX/numpy palettes) ----------

def train_loss_rgb(pred: RGB, tgt: RGB) -> int:
    """Scalar squared-Euclidean lattice loss (matches the Haskell trainLoss)."""
    da = esub(chroma(pred), chroma(tgt))
    return (luma(pred) - luma(tgt)) ** 2 + enorm(da)


def lattice_loss(pred: np.ndarray, tgt: np.ndarray) -> np.ndarray:
    """Vectorized squared-Euclidean lattice loss over arrays of RGB (last axis = 3).

    loss = (d luma)^2 + N(d chroma),  N(a,b) = a^2 - a b + b^2.
    Returns the per-element loss (shape = pred.shape[:-1]); mean it for the objective.
    Works with numpy or any array lib exposing the same ops (mlx.core arrays included)."""
    dl = pred[..., 0] + pred[..., 1] + pred[..., 2] - (tgt[..., 0] + tgt[..., 1] + tgt[..., 2])
    pa = pred[..., 0] - pred[..., 2]
    pb = pred[..., 1] - pred[..., 2]
    ta = tgt[..., 0] - tgt[..., 2]
    tb = tgt[..., 1] - tgt[..., 2]
    da = pa - ta
    db = pb - tb
    return dl * dl + (da * da - da * db + db * db)


def snap_palette_to_lambda(palette_lc) -> list:
    """Project a palette given in (luma, ca, cb) rows onto Lambda, returning byte-exact RGB rows.
    Use when a head emits chroma-coordinate targets/deltas; pure-RGB targets need no snap."""
    return [closest_lambda_rgb(int(l), (int(a), int(b))) for (l, a, b) in palette_lc]


# ===========================================================================
# Self-check (mirrors the runghc laws of the spec; run:  python eisenstein.py)
# ===========================================================================

def _laws() -> list[tuple[str, bool]]:
    sample = [(a, b) for a in range(-3, 4) for b in range(-3, 4)]
    laws: list[tuple[str, bool]] = []

    # N(xy) = N(x)N(y): the multiplicative norm (ANT backbone).
    laws.append(("normMultiplicative",
                 all(enorm(emul(x, y)) == enorm(x) * enorm(y) for x in sample for y in sample)))

    # N >= 0, and = 0 iff gray (the chroma kernel).
    laws.append(("normPositiveDefinite",
                 all(enorm(x) >= 0 for x in sample)
                 and all((enorm(x) == 0) == (x == (0, 0)) for x in sample)
                 and chroma((7, 7, 7)) == (0, 0) and enorm(chroma((7, 7, 8))) > 0))

    # 6 units, norm 1, hue rotation is an isometry; a non-unit scales.
    laws.append(("unitsAreSixHueRotations",
                 len(UNITS) == 6
                 and all(enorm(u) == 1 for u in UNITS)
                 and all(enorm(emul(u, x)) == enorm(x) for u in UNITS for x in sample)
                 and enorm(emul((2, 0), (1, 1))) != enorm((1, 1))))

    # closest_lambda: always byte-exact, idempotent on Lambda, no worse than snap, STRICT witness.
    targets = [(l, (a, b)) for l in range(-3, 7) for a in range(-3, 4) for b in range(-3, 4)]
    wt = (2, (0, 0))
    laws.append(("closestLambdaByteExactAndBeatsSnap",
                 all(in_lambda(closest_lambda(l, c)) for (l, c) in targets)
                 and all(closest_lambda(l, c) == (l, c) for (l, c) in targets if in_lambda((l, c)))
                 and all(metric_cost((l, c), closest_lambda(l, c)) <= metric_cost((l, c), snap_to_lambda(l, c))
                         for (l, c) in targets)
                 and metric_cost(wt, closest_lambda(*wt)) == 1
                 and metric_cost(wt, snap_to_lambda(*wt)) == 4))   # squared metric: down-by-2 -> 4

    # 3 ramifies: N(1-w)=3, (1-w)^2 = -3w, (1+w)(1-w)^2 = 3; integer RGB is always in Lambda.
    one_minus_w = (1, -1)
    one_plus_w = (1, 1)
    rgbs = [(r, g, b) for r in range(5) for g in range(5) for b in range(5)]
    laws.append(("threeRamifiesAndIntegerRgbInLambda",
                 enorm(one_minus_w) == 3
                 and emul(one_minus_w, one_minus_w) == (0, -3)
                 and emul(one_plus_w, emul(one_minus_w, one_minus_w)) == (3, 0)
                 and all(in_lambda((luma(c), chroma(c))) for c in rgbs)))

    # the loss IS squared luma + hex norm, sheared away from naive Euclidean.
    pred = np.array([[3, 1, 0], [4, 2, 1]])
    tgt = np.array([[0, 0, 0], [4, 2, 1]])
    ll = lattice_loss(pred, tgt)
    laws.append(("latticeLossSquaredEuclideanSheared",
                 int(ll[0]) == train_loss_rgb((3, 1, 0), (0, 0, 0))
                 and int(ll[1]) == 0
                 and enorm((2, 1)) == 3 and enorm((2, -1)) == 7        # hexagonal: sheared
                 and (2 * 2 + 1 * 1) == (2 * 2 + (-1) * (-1))))        # naive square-coord L2: equal

    # hue rotation by a unit leaves the chroma loss invariant (the training bias).
    cs = [(a, b) for a in range(-2, 3) for b in range(-2, 3)]
    laws.append(("hueRotationInvariantLoss",
                 all(enorm(esub(emul(u, cp), emul(u, ct))) == enorm(esub(cp, ct))
                     for u in UNITS for cp in cs for ct in cs)
                 and enorm(esub(emul((2, 0), (1, 0)), emul((2, 0), (0, 1)))) != enorm(esub((1, 0), (0, 1)))))

    return laws


def main() -> None:
    print("eisenstein.py  -- V2 colour substrate (ported from the runghc-green spec)")
    print("-" * 72)
    laws = _laws()
    for name, ok in laws:
        print(("PASS" if ok else "FAIL") + "  " + name)
    print("-" * 72)
    passed = sum(1 for _, ok in laws if ok)
    total = len(laws)
    allg = "  (all green)" if passed == total else "  (FAILURES present)"
    print(f"SUMMARY: {passed}/{total} laws PASS{allg}")
    print()
    print("witness: target (2,(0,0)) off Lambda;  snap ->", snap_to_lambda(2, (0, 0)),
          "cost", metric_cost((2, (0, 0)), snap_to_lambda(2, (0, 0))))
    print("                                       closest ->", closest_lambda(2, (0, 0)),
          "cost", metric_cost((2, (0, 0)), closest_lambda(2, (0, 0))))
    print("hex norm (2,1) =", enorm((2, 1)), " (2,-1) =", enorm((2, -1)),
          " (naive L2 of both = 5: the A2 metric is sheared)")


if __name__ == "__main__":
    main()

"""The VICReg collapse guard, the twin of spec/SixFour/Spec/NeuronRedundancy.hs.

When the head grows wide (the ViT of large_head.py), the intermediate latent it controls
(the 32-cubed / 128-cubed level that never surfaces) can dimension-collapse even against a
fixed target. This module is the active anti-collapse regularizer, a two-term coding-rate
floor measured on the latent BEFORE surfacing:

    cross_redundancy(batch)        - sum of squared OFF-DIAGONAL Pearson correlations.
                                     Zero iff neurons are pairwise decorrelated. The
                                     decorrelation (covariance) term.
    variance_floor_penalty(g, e)   - sum of max(0, g - sqrt(var + e)) per neuron. The
                                     per-neuron std hinge. Catches CONSTANT collapse, which
                                     the covariance term is blind to.
    latent_coding_floor            - the sum of both; zero iff the latent is full-variance
                                     AND pairwise-decorrelated (the objective's global min).

The decisive subtlety (lawConstantCollapseHasZeroCovarianceButPositiveVarianceHinge): a
batch of all-constant neurons reads cross_redundancy == 0 (a zero-variance column correlates
0 with everything, falsely "healthy") yet variance_floor_penalty > 0. BOTH terms are needed.

And the measure MUST be read on the latent, never after surfacing: a sub-quantum-correlated
batch reads redundant in latent space but collapses to constant (==> uncorrelated) once
rounded through reenter_q16 (lawRedundancyMeasuredInLatent).
"""
from __future__ import annotations

from math import sqrt

from q16 import quantize_q16

VIC_GAMMA = 1.0    # the per-neuron std floor (floors each neuron's differential entropy)
VIC_EPS = 1e-4     # the hinge ridge (keeps sqrt differentiable at zero variance)


def neuron_columns(batch):
    """Transpose: outer = samples, inner = neurons -> per-neuron columns across the batch."""
    return [list(col) for col in zip(*batch)]


def valid_batch(batch) -> bool:
    """At least two samples (variance defined) and rectangular with >= 1 neuron."""
    return (len(batch) >= 2 and len(batch[0]) > 0
            and all(len(row) == len(batch[0]) for row in batch))


def mean_of(xs) -> float:
    return sum(xs) / len(xs) if xs else 0.0


def variance_of(xs) -> float:
    """Population variance."""
    m = mean_of(xs)
    return mean_of([(x - m) * (x - m) for x in xs])


def correlation_of(xs, ys) -> float:
    """Pearson correlation; a constant (zero-variance) series is treated as decorrelated (0)."""
    mx, my = mean_of(xs), mean_of(ys)
    cov = mean_of([(x - mx) * (y - my) for x, y in zip(xs, ys)])
    vx, vy = variance_of(xs), variance_of(ys)
    return 0.0 if (vx <= 0 or vy <= 0) else cov / sqrt(vx * vy)


def cross_redundancy(batch) -> float:
    """Sum of squared off-diagonal cross-correlations of the neuron columns (each pair once)."""
    cols = neuron_columns(batch)
    n = len(cols)
    return sum(correlation_of(cols[i], cols[j]) ** 2
               for i in range(n) for j in range(i + 1, n))


def surface_column(col):
    """Surface a latent column through the single reenter_q16 crossing (for the latent-vs-
    surfaced law only; the intermediate latent is never actually surfaced)."""
    return [float(quantize_q16(x)) for x in col]


def variance_floor_penalty(gamma: float, eps: float, batch) -> float:
    """Sum of max(0, gamma - sqrt(var + eps)) per neuron: the std hinge that sees constant
    collapse. Hinge on the STD (not variance) so the gradient does not vanish at collapse."""
    return sum(max(0.0, gamma - sqrt(variance_of(col) + eps)) for col in neuron_columns(batch))


def latent_coding_floor(batch) -> float:
    """The full two-term floor: decorrelation + per-neuron variance hinge. Zero iff the latent
    is full-variance and pairwise-decorrelated."""
    return cross_redundancy(batch) + variance_floor_penalty(VIC_GAMMA, VIC_EPS, batch)


if __name__ == "__main__":
    fails = 0

    # lawRedundancyNonNegative + lawIdenticalNeuronsAreFullyRedundant
    identical = [[1, 1], [2, 2], [3, 3], [4, 4]]   # col0 == col1
    if not (cross_redundancy(identical) >= 1 - 1e-9):
        print("FAIL: identical neurons not fully redundant"); fails += 1

    # lawDecorrelatedNeuronsZeroRedundancy
    decorrelated = [[1, 1], [-1, 1], [1, -1], [-1, -1]]
    if not (cross_redundancy(decorrelated) <= 1e-9):
        print("FAIL: decorrelated neurons read redundant"); fails += 1

    # lawConstantCollapseHasZeroCovarianceButPositiveVarianceHinge — the decisive teeth
    collapsed = [[7, 7, 7]] * 4   # every neuron constant
    if not (cross_redundancy(collapsed) <= 1e-9):
        print("FAIL: constant collapse not invisible to covariance term"); fails += 1
    if not (variance_floor_penalty(VIC_GAMMA, VIC_EPS, collapsed) > 0.5):
        print("FAIL: variance hinge did not catch constant collapse"); fails += 1
    else:
        print(f"  collapse guard: cov={cross_redundancy(collapsed):.3g} (blind) but "
              f"hinge={variance_floor_penalty(VIC_GAMMA, VIC_EPS, collapsed):.3g} (catches it)")

    # lawRedundancyMeasuredInLatent — sub-quantum correlation visible only before surfacing
    ulp = 1 / 65536
    col = [0.1 * ulp, 0.2 * ulp, 0.3 * ulp, 0.4 * ulp]
    batch = [[a, a] for a in col]
    surfaced = [list(r) for r in zip(*[surface_column(c) for c in zip(*batch)])]
    if not (cross_redundancy(batch) > cross_redundancy(surfaced) + 0.5):
        print("FAIL: redundancy survives surfacing (must be read in latent)"); fails += 1
    else:
        print(f"  latent-only: redundancy {cross_redundancy(batch):.3g} in latent -> "
              f"{cross_redundancy(surfaced):.3g} surfaced")

    # the full floor is zero only for a full-variance, decorrelated latent
    healthy = [[1.0, 1.0], [-1.0, 1.0], [1.0, -1.0], [-1.0, -1.0]]  # decorrelated, std=1
    if latent_coding_floor(healthy) > 1e-6:
        print(f"FAIL: healthy isotropic latent has nonzero floor {latent_coding_floor(healthy)}"); fails += 1

    print("vicreg: PASS" if fails == 0 else f"vicreg: {fails} FAIL")
    raise SystemExit(1 if fails else 0)

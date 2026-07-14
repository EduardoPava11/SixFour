# Beauty-of-collapse findings (Phase A)

Reproducible source: `cabal test` → groups *OKLabMetric*, *Pair*, *Diversity*,
*BeautyCollapse* (`spec/test/Properties/`). These are *knowledge-increasing*
property tests: they port the implemented Rust oracle
(`studio/analysis-core`) into Haskell predicates and then interrogate the
beauty objective. Measured 2026-05-26; all 82 spec tests green.

Framing: **Birkhoff's Aesthetic Measure M = Order / Complexity** ("Unity in
Variety"). We measure, over unit-weighted OKLab candidate clouds,
- **UNITY** = complement-pair availability (`Spec.Pair`, threshold 0.05) ∈ [0,1],
- **VARIETY** = effective dimensionality (`Spec.Diversity`) ∈ [0,3],
- **M** = unity / variety.

## 1. The ports are faithful to the Rust oracle (golden cross-checks pass)

| Ported quantity | Haskell = Rust golden |
|---|---|
| `distSqWeighted` (w=[4,2,1]) | 0.04 / 0.02 / 0.01 ✓ |
| complement map (11→11) | red↔blue, orange→green, yellow→white, green→pink, purple→blue, pink→green, brown/black/white/gray fixed — **7/11 distinct** ✓ |
| `gaussianColorEntropy` (pal4) | −5.107467162247 ✓ |
| `effectiveDim` (trace identity) | 1.154985618198 ✓ |

The L>a>b hierarchy does real work: it reroutes **purple→blue** and
**brown→brown** (vs the unweighted purple→gray / brown→blue). Lightness-dominance
is intended, not a bug.

## 2. Battery snapshot

| scene | unity u | variety v | M = u/v | complexity |
|---|---|---|---|---|
| redblue+neu | 1.00 | 1.45 | **0.69** | 5 |
| all11-tight | 1.00 | 1.58 | 0.63 | 11 |
| all11-wide  | 1.00 | 1.61 | 0.62 | 11 |
| triad       | 0.67 | 1.93 | 0.35 | 3 |
| warm5       | 0.20 | 1.40 | 0.14 | 5 |
| mono-red    | 0.00 | 2.69 | 0.00 | 1 |

- **The Birkhoff maximizer is `redblue+neu`** (M=0.69): full complement coverage
  at minimal variety. This is direct empirical support for the **128-pair design**
  — pairing colours with their measured complements is what maximizes order.
- **`warm5` scores low (0.14) despite 5 categories**: warm colours' complements
  are cool and absent → low unity. Category *count* is not beauty; *pairing* is.
- **`mono-red` M=0**: a single category has no complement present → zero unity.

## 3. Headline: additive loss ≠ Birkhoff ratio (decision-grade for §7)

Sweeping the trade-off weight λ in the additive beauty `u − λ·v` and comparing its
scene-ranking to the ratio `u/v`:

> **worst concordance = 80% at λ = 0.** The two forms disagree on 20% of scene
> pairs. They are **not** order-equivalent — the loss-form choice changes which
> collapse is "more beautiful."

The disagreement is structural: `u/v` is scale-invariant along (u,v) rays;
`u − λv` is not. At λ=0 the additive form collapses to unity alone and ties all
three u=1.0 scenes, which the ratio breaks via variety. **Implication for
training:** prefer the ratio (or a constrained/learned λ); do not assume the
additive §7 sum is a faithful beauty proxy.

## 4. A naive collapse can destroy unity → a *learned* collapse is justified

Farthest-point (maximin) collapse, measured on the battery:
- **variety**: lowered in 4/6 scenes, raised in 1 — collapse generally condenses
  effective dimensionality (it does not merely pick extremes).
- **complement-pair availability (unity)**: **preserved in only 4/6 scenes.** In
  1/3 of scenes the classical collapse *drops a complement* and degrades unity.

This is the core warrant for the look-NN: the fidelity-floor collapse is not
unity-preserving, so a learned collapse must explicitly **protect complement
availability** while staying near the barycenter.

## 5. M is not monotone in scene-complexity

Birkhoff's naive intuition ("more complexity ⇒ lower M") does **not** hold here:
M is not non-increasing in the number of categories firing, because unity and
complexity co-vary (more categories can bring more complements). Beauty here is
governed by *pairing structure*, not raw category count.

## Carry-forward to Phase C (training regimen)

1. **Objective = ratio (Unity/Variety), not additive sum** — or a λ learned under
   the constraint that it tracks the ratio's ordering. (§3)
2. **Add an explicit unity-preservation term**: penalize loss of complement-pair
   availability through the collapse. (§4)
3. **The 128-complement-pair palette is empirically the order-maximizer** — keep it
   as the output primitive. (§2)
4. Use `effectiveDim` (variety) and `complementPairAvailability` (unity) as
   train/eval instruments; both are now oracle-faithful in `Spec`.

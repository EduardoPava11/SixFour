# ENTROPY INVARIANTS: the scale-to-scale entropy relationship is an ALGEBRAIC identity, not a fitted rate, and it names the price of every lossy collapse in bits

> Status: DESIGN OF RECORD · 2026-07-02 · Owner: SixFour
> Companions: `docs/DESTRUCTIVE-PYRAMID.md`, `docs/SCALE-TRANSITION-TRAINING.md`, `docs/GENE-COMPUTE-ECONOMY.md`, `CLAUDE.md`.
> Spec wins on any disagreement. Anchors are `file:line`, grep-confirmed against the substrate maps; PROPOSED laws are named as such and are not anchors. Start any spec browse at `SixFour.Spec.Map`.

---

## 1. THE THESIS + VERDICT

The thesis: the entropy relationship between adjacent scales is not an empirical rate you measure and fit, it is a pair of PROVABLE algebraic invariants discharged by lattice objects the spec already ships green. Two identities carry everything.

- **The chain rule** `H(fine) = H(coarse) + H(detail | coarse)`. Its witness is the lift BIJECTION `unliftF . liftF = id` (`RefinementSystem.lawLiftFRoundTrips:282`, byte-exact instance `OctreeCell.lawOctReversible:203`): a bijection is measure-preserving on counting measure, so `H(fine) = H(coarse, detail)` is an IDENTITY on any source distribution, no dataset, no training. The joint then decomposes by the ordinary Shannon chain rule.
- **The redundancy-free coarse** `I(coarse; fine) = H(coarse)`. Its witness is the deterministic pool `scalarCollapseLossy = ocCoarse . liftOct` (`OctreeCell.hs:235`): coarse is a function of fine, so `H(coarse | fine) = 0` definitionally, and `I = H(coarse) - H(coarse|fine) = H(coarse)`. `SuccessiveRefinement.lawMarkovByPooling:85` (surfaced depends only on coarse) is the second witness.

Read thermodynamically, the model is an entropy-difference / free-energy engine: the part of fine that is a deterministic function of coarse carries `I = H(coarse)` bits of RECOVERABLE structure (the reversible branch, zero-cost to replay), and the part collapsed many-to-one on any lossy decode carries `H(detail | coarse)` bits of DISSIPATED residual. Mutual information is the work-bearing channel; the erased residual is the heat.

**VERDICT: SOUND, and it SHARPENS the "lossy is a wash" finding rather than overturning it, after two circularity fixes and one category correction the critics forced.** The two identities are true textbook facts instantiated by green substrate. But the naive packaging of both keystones is circular (each reduces to `a == a`), the A7 direct sum was oversold as the chain-rule witness (it witnesses coordinate COMPLEMENTARITY, not additivity of entropies), and the Landauer/Szilard dressing has no physical teeth here (no temperature, no erasure cycle). Corrected, the framework does exactly one useful thing and does it rigorously: it certifies WHICH branch of the pyramid is the entropy-preserving isomorphism (lossless, reversible, work-bearing) and MEASURES the residual erased at every collapse (`scalarCollapseLossy`, the argmax palette realize) in discrete bits. A bijection cannot lower `H(coarse)` or synthesize detail below it (data-processing inequality), so the wash stands: the only lawful way to buy lossless rate is a real cross-band sub-additivity gap `G > 0`, and the only way below `H(coarse)` is to go lossy on a rate-distortion curve. The invariants do not rescue the lossy path. They price it.

---

## 2. THE INVARIANTS AND THEIR ALGEBRAIC WITNESSES

New Tier-0 module `Spec.EntropyDecomposition`, a thin join over `RefinementSystem.ReversibleLift` importing `SuccessiveRefinement` + `DetailEntropy` + `GaugeAction`. It lays entropy on a substrate that is already cabal-green; only the weighted-joint-histogram primitive is genuinely new (a few lines over `DetailEntropy.shannonBits:83`). Entropy is a functional of a DISTRIBUTION, so the class is parameterized by an explicit weighted source ensemble `p :: [(f, Double)]`, never a single capture (see §3).

```haskell
-- one new primitive: Shannon bits of an explicit weighted symbol distribution, >= 0.
-- reuses the proven-nonneg kernel shape of DetailEntropy.shannonBits:83.
hOfDist :: Ord a => [(a, Double)] -> Double            -- -sum p log2 p, p renormalized

class ReversibleLift f => EntropyDecomposition f where
  coarseOf :: f -> Integer            -- fst . liftF : the DC / sum-functional coordinate
  detailOf :: f -> [Integer]          -- snd . liftF : the b-1 mean-free A_{b-1} coordinates

  hFine              :: [(f,Double)] -> Double
  hFine p             = hOfDist p
  hCoarse            :: [(f,Double)] -> Double
  hCoarse p           = hOfDist [ (coarseOf x, w) | (x,w) <- p ]
  hJoint             :: [(f,Double)] -> Double                       -- INDEPENDENT joint over (coarse,detail)
  hJoint p            = hOfDist [ ((coarseOf x, detailOf x), w) | (x,w) <- p ]
  hDetailGivenCoarse :: [(f,Double)] -> Double                       -- computed INDEPENDENTLY, not by subtraction
  hDetailGivenCoarse p =
    sum [ pc * hOfDist [ (detailOf x, w) | (x,w) <- grp ]
        | grp <- groupByCoarse p, let pc = sum (map snd grp) ]
```

### 2.1 The chain rule, made a THEOREM not a definition

The critics caught the fatal shortcut: defining `hDetailGivenCoarse := hFine - hCoarse` makes `lawChainRuleBits` read `hFine == hFine`, a tautology that never touches the bijection or the pool. The repaired keystone splits into two laws, each with independent content:

```haskell
-- (A) BIJECTION law: fine entropy equals the entropy of the PAIRED (coarse, detail) coords.
--     Non-circular: hFine is measured on fine voxels, hJoint on the independent paired
--     coordinates; they are equal IFF liftF is injective on the support. Witnessed by
--     lawLiftFRoundTrips:282 / lawOctReversible:203 (measure-preserving relabeling).
lawEntropyPreservedByLift :: EntropyDecomposition f => [(f,Double)] -> Bool
lawEntropyPreservedByLift p = approx (hFine p) (hJoint p)

-- (B) CHAIN RULE on the joint histogram: exact identity of ANY distribution, with
--     hDetailGivenCoarse computed independently by groupByCoarse (NOT by subtraction).
lawChainRuleBits :: EntropyDecomposition f => [(f,Double)] -> Bool
lawChainRuleBits p = approx (hJoint p) (hCoarse p + hDetailGivenCoarse p)
```

**Algebraic witness, correctly scoped.** Law (A) is the bijection alone: `RefinementSystem.lawLiftFRoundTrips:282` and its byte-exact octant instance `OctreeCell.lawOctReversible:203`. A bijection `fine ~= (coarse, detail)` preserves counting measure, so `hFine == hJoint` exactly on the floored SET path (the shipped lift is a reversible set-bijection; that is all law (A) needs). Law (B) is pure Shannon algebra of the joint, true for every distribution including empirical ones.

**Where the A7 direct sum actually belongs (critic correction).** The split short exact sequence `0 -> A_{b-1} -> Z^b -> Z -> 0` (`RootLatticeDetail`: `sumFunctional:46`, kernel `inA:51`, `lawDetailKernelIsConstants:162` = `ker = Z.1`, `lawBandCountEqualsRank:131`) witnesses that `coarseOf` (the DC line `Z.1`) and `detailOf` (the mean-free root lattice `A_{b-1}`) are COMPLEMENTARY, non-overlapping coordinates: the direct sum `Z^b = Z.1 (+) A_{b-1}`. That is the precondition for the split to be WELL-DEFINED (the pieces do not double-count), and nothing more. It is NOT the witness for additivity of entropies. Additivity across the summands, `H(joint) = H(coarse) + sum_j H(band_j)`, holds ONLY if the bands are statistically independent, which is false in general. State that separately and gate it:

```haskell
-- LINEAR band decomposition holds ONLY under the band-independence hypothesis
-- (idealized Haar lift, independent detail bands). The general error term is the
-- submodularity gap G >= 0 (redundancy), the ONLY exploitable slack (see 5).
lawBandsAdditiveUnderIndependence :: EntropyDecomposition f => [(f,Double)] -> Bool
lawBandsAdditiveUnderIndependence p =
  bandsIndependent p  ==>  approx (hJoint p) (hCoarse p + sumPerBandEntropy p)
```

### 2.2 `I(coarse; fine) = H(coarse)`, made FALSIFIABLE with a negative control

The draft `lawMutualInfoIsCoarse` reduced to `hCoarse == hCoarse + x - x`, which passes for any functions, even a stochastic non-functional coarse. A law that cannot fail is not a law. The repair computes mutual information from the ACTUAL joint over `(coarseOf x, x)` and adds a negative control that MUST fail:

```haskell
iCoarseFine :: EntropyDecomposition f => [(f,Double)] -> Double
iCoarseFine p = hCoarse p + hFine p - hOfDist [ ((coarseOf x, x), w) | (x,w) <- p ]

-- coarse is a deterministic function of fine => H(coarse|fine)=0 => I = H(coarse).
lawMutualInfoIsCoarse :: EntropyDecomposition f => [(f,Double)] -> Bool
lawMutualInfoIsCoarse p = approx (iCoarseFine p) (hCoarse p)

-- NEGATIVE CONTROL: a stochastic coarse candidate (coarse not a function of fine)
-- MUST violate the law, proving it has teeth.
lawStochasticCoarseFailsMutualInfo :: [(NoisyPair,Double)] -> Bool
lawStochasticCoarseFailsMutualInfo p = not (approx (iCoarseFineNoisy p) (hCoarseNoisy p))
```

**Witness.** The identity rides on the deterministic surjection `scalarCollapseLossy:235` (`H(coarse|fine)=0`) plus `lawMarkovByPooling:85`. It is a theorem the instant `coarseOf` is a pure Haskell function, which it is (`fst . liftF`); the pool design is what the negative control certifies is REQUIRED, not decorative.

### 2.3 Gauge invariance: measure H on the orbit, never the labeling

Entropy of the rendered object must be computed on the observable orbit `gobserve x` (`GaugeAction.lawObservableIsOrbitInvariant:141`), the quotient `X / G`, never on the raw index labeling. Two regimes behave oppositely.

- **Index / detail channel.** The palette gauge is a PERMUTATION of symbols, the non-abelian `S_K` (`GaugeAction.lawPaletteGaugeIsNonAbelian:33`, concrete action `Gauge.gaugeAction:66`). Discrete Shannon entropy of a symbol histogram is already relabeling-invariant, so `hFine / hCoarse / hDetailGivenCoarse` on index multisets are automatically `S_K`-invariant. State it as `lawEntropyIsGaugeInvariant p g = approx (hFine p) (hFine (map (first (gact g)) p))`, discharged by `lawObservableIsOrbitInvariant:141`. Tie the metric side to `DescriptorQuasiIsometry.lawFloorKernelIsGaugeKernel:180` (metric kernel = gauge kernel) so entropy-zero coincides with gauge-collapse.
- **Palette (continuous OKLab) channel.** Relabeling invariance is not enough because the VALUES are continuous. Do NOT feed raw differential entropy here (§3). Route it through `EncoderModalityLoad.ridgedColorRateBits:62` (a determinant of the covariance, `S_K`-invariant AND >= 0).

### 2.4 Constructible via `runghc -isrc` today?

**Yes, the structural identities are constructible now.** `hOfDist` is a 6-line `-sum p log2 p`; `coarseOf = fst . liftF`, `detailOf = snd . liftF`, `groupByCoarse` is a fold. On a tiny explicit ensemble of octant vectors `V8 Int` with weights (4 to 6 cubes), `lawEntropyPreservedByLift`, `lawChainRuleBits`, and `lawMutualInfoIsCoarse` all evaluate and pass, because the bijection makes `hFine` and `hJoint` literal reindexings of one histogram, and the pool makes `H(coarse|fine)=0` by construction. `lawStochasticCoarseFailsMutualInfo` needs one hand-built noisy fixture. The three belong in `cabal test` beside `Properties/SuccessiveRefinement.hs`. `lawBandsAdditiveUnderIndependence` needs a `bandsIndependent` predicate and is honest only as a hypothesis-gated law (Tier-1).

---

## 3. ENTROPY HYGIENE

Three entropy notions live in the tree; only two may enter the class, and the single-capture reading needs a stated caveat.

- **Discrete Shannon (bits, >= 0).** `DetailEntropy.shannonBits:83`, `codedBits:94`, `detailEntropyBits:112`, proven non-negative `lawEntropyNonNegative:126`. This is the ONLY admissible input to `hFine / hCoarse / hDetailGivenCoarse`. `detailEntropyBits` is a per-band UNCONDITIONAL sum (an upper bound on `H(detail|coarse)`), which is exactly why it is kept DISTINCT from the true conditional (§5).
- **Differential (nats, can go NEGATIVE) is BANNED from the class.** `Diversity.gaussianColorEntropy:75` hits -9.559 nats on a tight palette (witnessed `EncoderModalityLoad.hs:129`). Feeding it into any `hCoarse` or `hDetail` breaks the non-negativity floor and the redundancy sign. This is a hard lint, not a preference: the class accepts only `hOfDist` (discrete) or `ridgedColorRateBits` (relative).
- **Relative / KL (bits, >= 0) is the sanctioned fix.** `EncoderModalityLoad.ridgedColorRateBits:62` = `(1/2) log2 det(I + Sigma/sigma0^2)`, a KL versus a fixed reference quantizer, proven `lawPaletteLoadNonNegative:119`, beats naive on a tight palette (`lawRidgedBeatsNaiveOnTightPalette`). This is the mission's prescribed cure, already instantiated for the palette axis, and the template for any continuous channel.

**Per-capture vs population, stated honestly.** The bijection theorem is a statement about the SOURCE ENSEMBLE `p`. A single 64^3 capture has no distribution: `shannonBits` on one cube is a within-capture SPATIAL histogram, a descriptive statistic, and the plug-in empirical entropy is downward-biased (Miller-Madow). Two honesties the critics sharpened:

1. The plug-in chain rule over ONE capture's joint histogram IS exactly additive, because `H(c,d) = H(c) + H(d|c)` is algebraic and holds on any distribution, empirical included, as long as all three terms come from the SAME joint histogram. So `lawChainRuleBits` is exact on the constructed fixture. The problem is not non-additivity.
2. The category slip to avoid: calling a one-capture `H` "the incompressible bound" for that realization. It is a biased estimate of the population bound, not the bound itself. Any CROSS-CAPTURE rate claim (see §5, the redundancy gap `G`) must use a bias-corrected estimator (Miller-Madow / NSB) on matched alphabets and report a sign confidence over a corpus, NEVER a per-capture boolean, because `G`'s sign on a single cube is dominated by mismatched estimator bias across the (large sparse fine / small coarse / per-band detail) alphabets, not by real cross-band structure.

---

## 4. THE MODEL AS AN ENTROPY-DIFFERENCE ENGINE (interpretation, not certified theorem)

The energy / work reading is a faithful transcription of standard information thermodynamics, and it is a useful intuition pump, but the critics are right that it has NO physical teeth in this codec: there is no temperature `T`, no bath, no measurement-feedback cycle, no erasure demon. Landauer and Szilard make bits-to-work LITERAL only with a physical bath at `T`; here `k_B T ln2 == 1` is a unit convention, so the "heat" and "work" labels are interpretation, not spec theorems. Present the accounting, mark its tier.

- **Work = mutual information.** The predictable part of fine that is a deterministic function of coarse carries `I(coarse;fine) = H(coarse)` bits, the reversible / recoverable structure (Szilard: information is extractable work, zero Landauer floor for a bijection). `lawWorkIsMutualInfo x = extractableWork x == hCoarse x`. INTERPRETIVE.
- **Residual = dissipated heat.** The many-to-one collapse (`scalarCollapseLossy`, argmax palette realize) is logically irreversible; its erased bits are exactly `H(fine) - H(coarse) = H(detail | coarse)`, the quantified residual. `lawResidualIsDissipatedHeat x = dissipatedHeat x == hDetailGivenCoarse x`. INTERPRETIVE; the bit count is real, the "heat" name is analogy.
- **Free energy = description length (this one has real teeth).** `F = codedDetail + hCoarse` is the MDL code length, and MDL is definitionally a free energy (`-log p` is energy, the complexity term is `-TS`). `lawFreeEnergyIsDescriptionLength x = freeEnergy x == hCoarse x + codedDetail x && freeEnergy x >= hFine x` (the source-coding floor, equality iff the redundancy gap `G = 0`). This is a genuine identity independent of the thermo dressing, and it is the correct single training objective for the scale-transition ladder (`docs/SCALE-TRANSITION-TRAINING.md`): minimize description length = minimize free energy.

**"Maximize I" is ill-posed while the lift is fixed (critic correction, folded).** The mission framing "the model MAXIMIZES the entropy difference `Delta H = I(coarse;fine)`" cannot stand as an objective: with the shipped FIXED pool, `I` is PINNED at `H(coarse)` by determinism, so `lawMaxEntropyDifference : deltaH == hCoarse` is a MEASUREMENT, not an argmax, there is no free parameter to optimize over. Drop the "InfoMax on the coarse channel" language for the fixed lift. An objective reappears ONLY if the pool becomes LEARNED, and then a learned pool is many-to-one, `H(fine)` is no longer bijection-invariant, and the whole entropy-iso scaffold must be re-proven or it is void. That is the honest tension, and it is exactly the determinism concession the destructive pyramid gates (`DESTRUCTIVE-PYRAMID.md` section 5).

---

## 5. REVISITING THE WASH UNDER THE INVARIANT LENS

The recorded finding: the shipped 256 is "fake 64^3 x 4", a deterministic lift carries no new information, self-supervised 16->64 super-res was correctly KILLED, and giving up byte-exactness on the analysis collapse "is a wash" unless it buys rate (`DESTRUCTIVE-PYRAMID.md` section 1). The invariants make this DECIDABLE.

**The identity restates the wash exactly.** `I(coarse;fine) = H(coarse)` says a deterministic lift of the 64^3 carries EXACTLY `H(64)` bits: the extra grid is mutual-information-redundant with coarse, and by the data-processing inequality no bijective lift can push `H(coarse)` below its own floor or synthesize detail. That is the information-theoretic proof that the killed super-res and the "fake 256" were correctly called.

**The decidable criterion for whether giving up determinism buys rate.** Because `H(fine)` is invariant under the bijection and the entropy SUM is fixed, no deterministic lift reallocates below `H(fine)`. Lossless rate is available if and only if there is genuine cross-band SUB-ADDITIVITY: the redundancy gap

```
G  =  codedDetail  -  hDetailGivenCoarse
   =  detailEntropyBits(held)  -  hDetailGivenCoarse
   =  sum_j H(band_j)  -  H(detail | coarse)   >=  0   (submodularity, Miller)
```

is the only exploitable slack. `codedDetail` (`detailEntropyBits:112`, the achievable per-band code, unconditional) MUST be kept distinct from `hDetailGivenCoarse` (the true conditional); collapsing them silently zeroes the only quantity that matters. Both are discrete Shannon and >= 0.

- `G = 0`: the pyramid is a PROVABLE wash. The chain-rule identity forbids any lossless gain from a deterministic recode.
- `G > 0`: lossless rate is available up to `G` by recoding the correlated bands jointly.
- Below `H(fine)`: requires going LOSSY on a rate-distortion curve, admissible ONLY inside `DescriptorQuasiIsometry.lawDescriptorLowerSeparation:173` (never collapse two genes closer than the sub-quantum gauge kernel). Past that separation the collapse is logically irreversible and no invariant makes it lossless.

**Honest verdict: SHARPENED, folding both critic verdicts.** Not overturned. The invariants cannot convert a lossy collapse into a lossless one, nor let a deterministic lift manufacture detail below `H(coarse)`. What they add is a NAMED price and a TYPED branch split: the reversible branch (the lift bijection) is certified an entropy isomorphism (lossless, work-bearing), the collapse branch has its erased bits COUNTED as `hDetailGivenCoarse`. The critics forced the load-bearing caveat: the decision gate `G > 0` is NOT a per-capture boolean. `G`'s sign on one cube is an estimator artifact (mismatched Miller-Madow bias across the fine / coarse / per-band alphabets); it becomes a real rate claim only as a bias-corrected estimate with sign confidence over a CORPUS. So the wash verdict is: a deterministic lift is a wash by theorem; giving up determinism buys rate iff a corpus-level, bias-corrected `G` is significantly positive AND the lossy REDUCE is a proven Markov degradation (the Equitz-Cover refinability precondition), the same condition `DESTRUCTIVE-PYRAMID.md` already gates the concession behind.

---

## 6. NEW LAWS AND BUILD PLAN

Tier-0 first; all constructible via `runghc -isrc` today unless flagged. Home: a NEW module `Spec.EntropyDecomposition` (wire into `spec.cabal` after `SuccessiveRefinement`, header + one `Spec.Map` line under an information-theory category, mirror `Properties.EntropyDecomposition`). Each law delegates a landed law rather than restating it, so no settled decision reopens.

| Law (PROPOSED) | Tier | Algebraic witness | Critic fix folded in | runghc today? |
|---|---|---|---|---|
| `lawEntropyPreservedByLift` | T0 | lift bijection `lawLiftFRoundTrips:282` / `lawOctReversible:203` (measure-preserving) | `hFine` vs INDEPENDENT `hJoint` over paired coords, not `a==a` | YES, octant fixtures |
| `lawChainRuleBits` | T0 | Shannon algebra of the joint; `hDetailGivenCoarse` computed by `groupByCoarse` | conditional computed INDEPENDENTLY, never by subtraction | YES, pure |
| `lawMutualInfoIsCoarse` | T0 | deterministic pool `scalarCollapseLossy:235`, `lawMarkovByPooling:85` | `I` from the real `(coarse,fine)` joint, not a tautology | YES |
| `lawStochasticCoarseFailsMutualInfo` | T0 | negative control (non-functional coarse) | proves the mutual-info law can FAIL, so it has teeth | YES, one noisy fixture |
| `lawEntropyIsGaugeInvariant` | T0 | `GaugeAction.lawObservableIsOrbitInvariant:141`, `Gauge.gaugeAction:66` | measure `H` on orbit `gact g`; index Shannon is `S_K`-invariant | YES |
| `lawFreeEnergyIsDescriptionLength` | T1 | MDL identity `F = hCoarse + codedDetail >= hFine` | real teeth (independent of thermo); floor equality iff `G=0` | YES, needs `codedDetail` wiring |
| `lawRedundancyIsSubmodularityGap` | T1 | `G = detailEntropyBits(held) - hDetailGivenCoarse >= 0` (Miller) | keeps `codedDetail` DISTINCT from the conditional; the exploitable slack | YES numerically, sign untrusted per-capture |
| `lawBandsAdditiveUnderIndependence` | T1 | A7 SES complementarity (`lawDetailKernelIsConstants:162`) | gated on band-independence hypothesis; submodularity gap = error term | needs `bandsIndependent` predicate |
| `lawWorkIsMutualInfo` / `lawResidualIsDissipatedHeat` | INTERP | none physical (no `T`) | downgraded from certified to INTERPRETATION; bit counts real, names analogy | YES as bit accounting |
| `lawRedundancyCorpusSignificant` | T2 | bias-corrected (Miller-Madow / NSB) `G` over a corpus | replaces the per-capture boolean gate; the real rate-buys decision | NO, needs corpus + estimator |

Dependency order: author `lawEntropyPreservedByLift` FIRST (it is the one law where the bijection earns its keep and it unblocks every other), then `lawChainRuleBits` and the `lawMutualInfoIsCoarse` + negative-control pair (Tier-0 gate-ready together), then `lawEntropyIsGaugeInvariant`. Tier-1 `lawFreeEnergyIsDescriptionLength` and `lawRedundancyIsSubmodularityGap` land once `codedDetail` is wired from `detailEntropyBits`. `lawBandsAdditiveUnderIndependence` waits on a `bandsIndependent` predicate. `lawRedundancyCorpusSignificant` is UNBUILT (needs a corpus and a bias-corrected estimator) and is the only law that can actually adjudicate the lossy concession.

---

## 7. OPEN DECISIONS FOR THE OWNER

1. **Ship the info-theory laws Tier-0-only first, or wait for the corpus estimator?** RECOMMENDED DEFAULT: ship the four Tier-0 laws now (they are pure, gate-ready, and certify the branch split), and keep `lawRedundancyCorpusSignificant` explicitly UNBUILT so no one reads a per-capture `G` as a rate decision.
2. **Keep the Landauer/Szilard laws in the module at INTERP tier, or cut them entirely?** RECOMMENDED DEFAULT: keep them, tagged INTERPRETATION with the "no `T`" caveat inline, because the bit accounting (work = `H(coarse)`, heat = `H(detail|coarse)`) is a genuine and clarifying decomposition, and `lawFreeEnergyIsDescriptionLength` is a real MDL identity worth a green law. Cut only the "maximize `Delta H`" framing, which is ill-posed under the fixed lift.
3. **Does the determinism concession get gated on `G > 0`?** RECOMMENDED DEFAULT: YES, but on the CORPUS-level bias-corrected `G` plus a proven Markov-degradation REDUCE, matching the gate `DESTRUCTIVE-PYRAMID.md` already sets. Never on a single capture.
4. **`bandsIndependent` predicate: build it, or drop `lawBandsAdditiveUnderIndependence`?** RECOMMENDED DEFAULT: drop the additive law for now. The bands are generally correlated (that correlation IS the redundancy `G`), so an independence-gated additivity law is rarely true and low-value; the submodularity gap law carries the useful content.
5. **Palette-channel entropy: enforce `ridgedColorRateBits` by lint, or by convention?** RECOMMENDED DEFAULT: by LINT. The negative differential entropy (-9.559 nats) is a real landmine; make `gaussianColorEntropy` a type error inside `Spec.EntropyDecomposition`, admitting only `hOfDist` or `ridgedColorRateBits`.

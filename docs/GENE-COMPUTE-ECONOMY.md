# GENE COMPUTE ECONOMY: DESIGN OF RECORD

2026-07-02. Three spec laws that turn the GeneAtlas from a set of genes that merely EXIST into a set of genes that COMPETE for a scarce resource: decode-compute. Each is synthesised from a design pass plus an adversarial critique, and grounded in a substrate report (the two reversible lifts, the rung driver, the packet ledger) plus a five-literature web report (successive refinement, anytime/contract algorithms, early-exit nets, scalable coding, resource-rational cognition). VERDICT UP FRONT: **author `AnytimeDecode` first** (it is pure over the shipped octant inverse, buildable today, and after the critique fix it is a real regression guard on the decode path rather than a theorem about `scanl`), **`PacketEconomy` second** (its economics are right but its keystone is one-sided and vacuous as drafted, and it must ride on a settled anytime contract before it can gate), **`BudgetHead` last** (the estimator is a learned float head with no code today, and its critique demotes the advertised keystone to a golden-plus-lint, so it lands only once the two data-side laws are green). None of the three is landable as first drafted; each critique's fix is folded into the plan below. This doc EXTENDS `docs/GENE-LAWS-DESIGN.md` (the DescriptorQuasiIsometry / PaintOrderPrior / GeneRecombination trio that governs the atlas): those three say which genes are ADMISSIBLE and COMPARABLE; these three say which genes get to SPEND the decode budget. It starts, as always, at `SixFour.Spec.Map`.

Anchors below are carried from the substrate report and the design/critique passes; every one was grep-confirmed against the tree (`RefinementSystem.hs:139-145` `liftVec`/`unliftVec`, `:130-135` `liftF`/`unliftF` class default, `:281-283` `lawLiftFRoundTrips`; `OctreeCell.hs:114-127` `liftOct`/`unliftOct`; `RefinementCarriers.hs:111-112` override, `:124-129` `lawOctLeafLiftIsLiftOct`; `SelfSimilarReconstruct.hs:145-150` `reconstruct256`, `:180-185` `lawWithinCaptureExact`, `:192-201` `lawBeyondCaptureInvented`, `:213-221` `lawZeroTailIsFloor`, `:238` `expandRungVolume`, `:287-292` `lawVolumeExpandFloorConstant`; `SwapCarrier.hs:404-408` `expressionSource`, `:457-461` `lawShowcaseIsInert`; `PonderBudget.hs:58-59` `budgetToMask`, `:74-77` `lawZeroBudgetIsFloor`, `:96-100` `lawLowerHaltRefinesMore`; `PonderHaltDistribution.hs:33-37` `haltDist`, `:46-47` `expectedSteps`, `:51-52` `geometricPrior`, `:71-77` `lawExpectedLossIsConvex`; `V21Transport.hs:334-340` `lawFlowAdditiveInRank`; `ScaleFiltration.hs:97-98` `lawBallsNested`, `:116-117` `lawOctantBranchingIs8`; `DetailPredictor.hs:98-99` `paramCount==21`, `:126-135` `rawBands`/`predictDetail`; `GeneSimilarity.hs:122` cloud, `:142-144` `expressedEnergy`; `kernels.zig:857` `s4_octant_lift`, `:887` `s4_octant_unlift`, `:924` `s4_cube_expand_rung`, `:945-947` the S-site fork; `DeviceTrainShaders.metal:191/317`; `DEVICE-MODEL-MAP.md:317-322,360-368`).

---

## 1. THE THESIS

**Encode is cheap; decode is expensive; therefore decode-compute is the scarce resource; therefore genes compete for it.** This is the whole economy in one line, and every clause is grounded, not asserted.

**Encode is cheap (frozen, O(1)-per-cell, parameter-free, byte-exact).** The tokenizer is the reversible lift and nothing learned crosses it. The prefix-difference scheme `liftVec (x:xs) = (x, zipWith subtract (x:xs) xs)` with inverse `unliftVec (c,ds) = scanl (+) c ds` (`RefinementSystem.hs:139-145`) is one integer pass, no division; the shipped spatial carrier is the Haar-averaging octant transform `liftOct`/`unliftOct` (`OctreeCell.hs:114-127`), whose device floor `s4_octant_lift`/`s4_octant_unlift` (`kernels.zig:857,887`) is a fixed 8-lane body with the sole reversible division being the `/2` dyadic floor. Ledger class is `I` (reversible, EXACT) for every lift/unlift pair (`DEVICE-MODEL-MAP.md:317-321`). The coarse token `x0` alone is already a valid coarsest reconstruction. Encoding is not where the cost lives.

**Decode is expensive (learned S-compute, per-rung, up the ladder).** Decoding iterates the rung driver `s4_cube_expand_rung(vol, side, details, out)` (`kernels.zig:924`): every coarse voxel expands to its `2x2x2` block via `s4_octant_unlift`, and `16^3 -> 32^3 -> 64^3 -> ... -> 256^3` is this one operator iterated (`:937-938`). At each expanded voxel the decoder OPTIONALLY injects `theta`-minted detail. The cost asymmetry is arithmetic: the free `I` replay is fixed `out^3` octant_unlift calls per rung; the `S` surcharge is the 21-MAC `theta . phi(v)` head (`DetailPredictor.hs:98-99,126-127`, 7 bands x 3 features) plus a Q16 commit, added only where the gene chose to invest detail. The top rung `128^3 -> 256^3` alone is ~2.1M voxels, roughly 8x the sum of all lower rungs. That factor is the phrase "decoding is expensive" in numbers.

**Therefore decode-compute is the scarce resource, and genes compete for it.** A frame or session has a finite decode-compute budget; the budget must be split across the rung ladder and across the genes that want to express detail. A gene's `expressedEnergy` (`GeneSimilarity.hs:142-144`, the proven integer gauge-invariant L1 mass of invented detail above the floor) is exactly how much `S`-work it will spend. **Human attention is a grant of decode-compute**: the resource-rational reading (Lieder and Griffiths, BBS 2020) models attention as the allocation of scarce processing when incoming data exceeds capacity, so an entitlement that steers where the next FLOP goes IS the attention surface. The economy is not winner-take-all; it is convex budget-splitting on diminishing-returns performance profiles.

**V1 budgets are ADVISORY.** The budget head ESTIMATES a per-rung packet schedule from the encoder before any full decode is committed, but the estimate only GATES which rungs attempt their `S`-packet; it never authorizes spend. Actual cost is re-measured locally per packet (`MTL4CounterHeap` GPU-time delta, `os_signpost` per packet class, `DEVICE-MODEL-MAP.md:391-400`) and capped independently (`:372-374`). A wrong estimate therefore lands the decode on a lower-distortion point of the SAME refinement ladder, never off it.

**The hard constraint: partial decode must never fail (the floor is always available).** This is what makes advisory safe and what makes competition non-destructive. Depth-0 (coarse = Showcase = `FloorExact`) is available at zero `S`/`K`/`I` cost for every input and never faults. It is proven three times today (`SwapCarrier.lawShowcaseIsInert:457`, `PonderBudget.lawZeroBudgetIsFloor:74`, `SelfSimilarReconstruct.lawZeroTailIsFloor:213`) but never unified; `AnytimeDecode` (2.1) names the one contract. Grounding: `Showcase` carries physically zero weight bytes and expresses as `FloorExact` (`SwapCarrier.hs:404-408,457-461`); the `details == null` fork inside the rung driver (`kernels.zig:945-947`) is the device witness that skipping every `S`-packet yields the deterministic nearest-neighbour floor (`lawVolumeExpandFloorConstant:287-292`).

---

## 2. SUCCESSIVE-REFINEMENT FOUNDATION

The distilled theory says the "never fail" guarantee is not a hope, it is a named property of layered codes, and the prefix-difference lift already sits inside it.

**Successive refinement (Equitz and Cover, IEEE T-IT 37(2), 1991).** Encode `X` once into a layered stream; a decoder reading a rate-`R1` prefix reaches distortion `D1`, and reading more (`R2 >= R1`) reaches `D2 <= D1`. The source is successively refinable iff BOTH stages sit on the single-shot rate-distortion curve at once (`R1 = R(D1)` and `R2 = R(D2)`) with no rate penalty for having committed to the coarse layer first. The exact condition is a Markov chain `X -> X_fine -> X_coarse`: the coarse reproduction must be a DEGRADED function of the fine one, not of the source. Every finite-alphabet source under Hamming distortion is refinable; under logarithmic loss EVERY source is. Mapping: a prefix-difference gene code is a successive-refinement code, and "partial decode must not fail" is exactly "each prefix is itself R-D optimal at its own rate," guaranteed precisely when the coarse layer is a degraded function of the fine.

**Anytime and contract algorithms (Russell and Zilberstein, AIJ 1995).** Interruptible algorithms may be stopped at any time and return the best-so-far with quality monotonically improving; contract algorithms are told the deadline in advance. Any contract algorithm converts to an interruptible one with a bounded penalty (the classic `<= 4x` slowdown). Optimal stopping = spend compute until marginal quality gain drops below marginal time cost (value of computation). Mapping: each gene is an anytime job with a performance profile; the budget head is the meta-level controller that spreads the shared decode budget where marginal reconstruction gain per FLOP is highest, and any interruption yields a valid best-so-far.

**Early-exit / adaptive-depth nets.** MSDNet (Huang et al., 2017) is the canonical anytime net: multi-scale features keep a coarse global feature available at EVERY depth, so every intermediate exit is valid, in both an anytime mode and a budgeted-batch mode. PonderNet (Banino et al., 2021) gives clean unbiased halting: `p_n = lambda_n * prod_{j<n}(1 - lambda_j)` (geometric), loss `= sum_n p_n * L(y, y_n) + beta * KL(p_n || geometric prior)`, the prior mean `1/lambda_p` being a tunable "compute per gene" dial. Mapping: MSDNet's coarse-feature-at-every-depth is the architectural analogue of requiring the coarse gene layer to be valid on its own, the same invariant that makes partial decode not fail; PonderNet's prior is the honesty price on the budget head (2.3).

**Scalable / progressive neural coding.** Base-plus-enhancement latents, nested quantization coarse-to-fine, latent elements ordered by R-D importance so truncation drops the least-important refinement first, and tail-drop training (random-length truncation, ProDAT 2025) that makes any prefix decodable with monotone quality. Mapping: this is the applied template for the gene stream and the empirical enforcement of graceful degradation.

**Why the prefix-difference lift ALREADY gives anytime decode.** `unliftVec = scanl (+) c ds` (`RefinementSystem.hs:143-145`) has the prefix property by construction: reading `k` detail bands yields exactly the `k+1`-sample prefix of reading all of them, because a later band never rewrites an earlier partial sum. That is prefix-optimality in the Equitz-Cover sense for scheme (1). The abstract "no finer rung invalidates a coarser one" content is proven today as nested balls `lawBallsNested:97-98` (a level-`n+1` ball is contained in the level-`n` ball) over the address filtration, and the additive-in-rank content is proven on the TIME axis as `lawFlowAdditiveInRank:334-340` (`disp H0 H2 == disp H0 H1 + disp H1 H2`). The halting bound is proven as `lawExpectedLossIsConvex:71-77` (stopping at any rung is no worse than the worst step, no better than the best). What is NOT proven is prefix-optimality at the spatial VALUE decode: the shipped decode is the averaging octant inverse `unliftOct` (scheme 2, `RefinementCarriers.hs:111-112` overrides the prefix-difference default), whose anytime property is the rung ladder, not a `scanl` truncation, and whose top rung is invented and non-injective (`lawBeyondCaptureInvented:192-201`). `AnytimeDecode` closes the scheme-(1) gap and honestly SCOPES the scheme-(2) claim.

---

## 3. THE THREE LAWS

### 3.1 `SixFour.Spec.AnytimeDecode`

**Module home.** New module, import-and-bridge; the cheap discharges land in the green modules it re-exports. Maintenance contract: add `SixFour.Spec.AnytimeDecode` to `spec.cabal` exposed-modules after `SixFour.Spec.SelfSimilarReconstruct` (`spec.cabal:112`) plus a mirror `Properties.AnytimeDecode` (near `:469`); a `Spec.Map` entry sibling to the `SelfSimilarReconstruct` block (`Map.hs:318`) tagged `DisplaySide`; Haddock header citing `RefinementSystem`/`SelfSimilarReconstruct`/`SwapCarrier` and Equitz-Cover.

**Purpose.** The "must not fail on partial decode" guarantee is PROVEN but SCATTERED (floor-decodability lives three times: `SwapCarrier.lawShowcaseIsInert:457`, `PonderBudget.lawZeroBudgetIsFloor:74`, `SelfSimilarReconstruct.lawZeroTailIsFloor:213`) and prefix-additivity is structural-only for the spatial value decode. This module names the ONE contract: reading `k` detail bands yields exactly the `k+1`-sample prefix of reading all of them (additive, prefix-optimal per Equitz-Cover), and depth-0 (coarse = Showcase = `FloorExact`) is ALWAYS available at zero cost and NEVER faults.

**Keystone (REPAIRED 2026-07-02, GHC-verified).** Two earlier drafts were both wrong. Draft 1 hardcoded `unliftVec = scanl (+)`, a theorem about `scanl`, unfalsifiable. Draft 2 re-targeted the class method `unliftF`/`unliftOct` "on the decode path", but a runghc probe over the shipped octant inverse proved that re-target UNSOUND: the octant prefix property returns FALSE for k=0..6, because `unliftOct` is the Haar-AVERAGING inverse (`RefinementCarriers.hs:111` overrides the additive default), so a k-band prefix is genuinely NOT a prefix of the full octant decode. The honest keystone states the prefix property on the additive prefix-difference inverse `unliftVec` (the real reversible carrier, `RefinementSystem.hs:143`), which is byte-exact and passes (100 QuickCheck + 25 enumerated in the verification probe). The octant decode's anytime guarantee is stated SEPARATELY as floor totality (`lawFloorAlwaysDecodable`, below), never as a false octant-prefix claim.

```haskell
-- HONEST keystone: reading k detail bands is a strict PREFIX of the full decode,
-- over the REAL additive prefix-difference inverse unliftVec (RefinementSystem.hs:143).
-- A non-additive carrier fails this; the AVERAGING unliftOct is deliberately NOT
-- claimed here (its anytime property is floor totality, lawFloorAlwaysDecodable).
lawDecodeIsAnytime :: (Integer, [Integer]) -> Int -> Bool
lawDecodeIsAnytime (c, ds) k0 =
  let k = max 0 (min k0 (length ds))
  in  takeBands (k + 1) (c, ds) == unliftVec (dropDetailBeyond k (c, ds))
```

Forbids a decoder whose partial (k-rung) output disagrees with the full decode truncated to depth `k`, i.e. any inverse that is TAIL-DEPENDENT: a global renormalization, a total-mass clamp, or a smoothing pass that reads the whole tail before emitting the coarse sample. All read future bands, so their k-prefix differs from their full-prefix. Non-vacuity is pinned by a witness law (below) exhibiting a concrete tail-dependent decoder the predicate rejects.

**Supporting laws.**

```haskell
-- Floor is ALWAYS defined and never faults, for EVERY input (the depth-0 fallback).
-- expandRungVolume side vol Nothing is TOTAL, = nearest-neighbour floor. (host-testable)
lawFloorAlwaysDecodable :: Int -> [Int] -> Bool
lawFloorAlwaysDecodable side vol =
  let out = expandRungVolume (max 1 side) vol Nothing
  in length out == 8 * s3 && all (>= 0) out
  where s3 = let s = max 1 side in s*s*s

-- Non-reflexive bridge (was X==X): a Showcase (weightless) payload's decode source
-- IS the reconstruct floor, closing the SwapCarrier <-> SelfSimilarReconstruct gap.
lawShowcaseDecodesToFloor :: SwapPayload -> Bool
lawShowcaseDecodesToFloor p =
  expressionSource p == FloorExact
    ==> expandRungVolume 1 (coarseOf p) Nothing == reconstructFloor (coarseOf p)

-- Non-vacuity witness, EXISTENTIAL over k (was a FALSE forall): a tail-dependent
-- renorm differs from the full-decode prefix at SOME k < length ds.
lawTailDependentDecodeIsBanned :: (Integer, [Integer]) -> Bool
lawTailDependentDecodeIsBanned (c, ds) =
  any (\k -> badRenorm (c, take k ds) /= take (k+1) (badRenorm (c, ds)))
      [0 .. length ds - 1]
  where badRenorm (c0, d) = let xs = scanl (+) c0 d in map (subtract (last xs)) xs

-- Halting before the INVENTED step (returning the 64^3 cube) is a valid exact decode,
-- one octree level coarser. Delegates lawWithinCaptureExact (SelfSimilarReconstruct:180).
lawHeldRungHaltsExact :: Int -> Int -> [Int] -> Bool
lawHeldRungHaltsExact = lawWithinCaptureExact

-- Halting at any rung is a bounded valid intermediate. Delegates PonderHaltDistribution:71.
lawAnyRungLossBounded :: [Double] -> [Double] -> Bool
lawAnyRungLossBounded = lawExpectedLossIsConvex

-- Separate scanl fact kept as a LEMMA, explicitly NOT the keystone (the critique's demand).
lawVecPrefixOptimal :: (Integer, [Integer]) -> Int -> Bool
lawVecPrefixOptimal (c, ds) k = take (k+1) (unliftVec (c, ds)) == unliftVec (c, take k ds)
```

**The failure it forbids, sharpened.** A future edit that swaps the octant inverse to a non-additive override (the class allows it, `RefinementSystem.hs:130`), or a graceful-degradation training bug that lets the invented tail perturb the `64^3` base rather than only expand it. `lawTailDependentDecodeIsBanned` proves the predicate has teeth: `badRenorm (100,[5,-3,7]) = [-9,-4,-7,0]`, and at `k=2`, `badRenorm (100,[5,-3]) = [-2,3,0] /= take 3 [-9,-4,-7,0]`, so the keystone correctly REJECTS the tail-dependent decoder.

**Critic verdict: SOUND-WITH-FIXES. Fixes folded in.** The critique's sharpest objection is vacuity plus wrong-target: `lawDecodeIsAnytime` hardcoded `unliftVec = scanl`, a theorem true for every input, and worse the GATHER map is explicit that the SHIPPED spatial decode is scheme (2) `unliftOct` (Haar averaging, `RefinementCarriers:111-112` overrides the default), NOT `unliftVec`, so the keystone certified anytime-safety of a lift not on the device decode path and could never regress. Two further defects: `lawShowcaseDecodesToFloor` concluded `X == X` (reflexive, closes nothing), and `lawTailDependentDecodeIsBanned` was FALSE as a forall (at `k >= length ds` the tail-drop is a no-op so both sides coincide). THE FIX (adopted): (1) re-target the keystone at the class method `unliftF`/`unliftOct` on the decode path so a non-additive override genuinely flips it, and keep `lawVecPrefixOptimal` as a SEPARATE `scanl` lemma, never called the keystone; (2) make `lawShowcaseDecodesToFloor` a real equation binding the Showcase floor to the `reconstruct256`/`lawZeroTailIsFloor` floor; (3) rewrite the witness as existential over `k < length ds`. Non-fatal, checked clean: `lawFloorAlwaysDecodable` is host-testable and fine; the scoping away from the invented seam is honest; the device UNBUILT items do not touch the scoped laws.

**Device realization.** Rung driver `s4_cube_expand_rung` (`kernels.zig:924`); each coarse voxel expands via `s4_octant_unlift` (`:887`). The anytime fork is `:945-947`: `details == null` is the deterministic zero-detail floor (class `I`, replayable) = the device witness of `lawFloorAlwaysDecodable`; `details != null` is the `theta`-minted `S` surcharge (`DeviceTrainShaders.metal:191/317`, 21 params) skipped on the floor path. Byte-exactness rides the `/2` dyadic floor only (`kernels.zig:857`, ledger `I pair EXACT`). UNBUILT: (a) no Swift caller yet guarantees passing `null` on decode fault, so "never faults" is a spec contract the device does not yet enforce; (b) the collapse direction `256^3 -> 64^3` needed to state the FULL rung-ladder equality above the held rung is UNBUILT; (c) the budget head that schedules which rungs get their `S` packet is UNBUILT (`expressedEnergy` `GeneSimilarity.hs:142` is the substrate).

**Golden vectors.** (1) Prefix (lemma): `c=100, ds=[5,-3,7]` gives full `unliftVec = [100,105,102,109]`; `k=2` gives `unliftVec (100,[5,-3]) = [100,105,102] == take 3 full`. (2) Floor totality: `expandRungVolume 2 (replicate 8 30000) Nothing == replicate 64 30000` (from `lawVolumeExpandFloorConstant:287`). (3) Showcase-to-floor bridge: a Showcase `SwapPayload` (empty `spWeights`) has `expressionSource == FloorExact` and decodes to the `reconstructFloor` value (`lawShowcaseIsInert:457`). (4) Discriminating witness: `badRenorm (100,[5,-3,7]) = [-9,-4,-7,0]`; at `k=2` the keystone REJECTS it.

**Single biggest soundness risk.** Overclaiming anytime across the INVENTED seam. The `64^3 -> 256^3` rung is non-injective (`lawBeyondCaptureInvented:192`): the synthesised `S`-detail is not a captured prefix, so "collapse(full 256^3) == halt-at-64^3" is FALSE above capture. The keystone is therefore SCOPED to the additive prefix-difference lift and the HELD rung plus floor; it must NOT be extended to assert the invented bands are prefix-optimal. If a future edit lets the invented tail perturb the `64^3` base, both `lawDecodeIsAnytime` and `lawHeldRungHaltsExact` silently become vacuous truths about a decoder that no longer degrades gracefully; guard with a companion `lawInventedTailDoesNotPerturbBase` before widening scope.

---

### 3.2 `SixFour.Spec.PacketEconomy`

**Module home.** New module, `DisplaySide` compartment. Maintenance contract: add `SixFour.Spec.PacketEconomy` to `spec.cabal` exposed-modules alongside `GeneSimilarity` (`:203`) plus a `Properties.PacketEconomy` test module (near `:417`); one `Spec.Map` entry after the `GeneSimilarity` line (`Map.hs:1123`); Haddock header in house style citing Equitz-Cover prefix-optimality and resource-rational allocation (BBS 2020).

**Purpose.** Decode-compute is the scarce resource genes compete for: finite decode-packets per frame/session, split across the rung ladder (`s4_cube_expand_rung`, `kernels.zig:924`). The budget head SCHEDULES an anytime knapsack over rungs; selection passes a gene on in proportion to MEANING delivered per decode-packet. This module makes "efficient genes are the elites" a law, and keeps the two fitnesses DISJOINT: the objective "does something" gate (machine-measured loss reduction above floor, ships now) is the admission filter; "human attention" (social, entitlement-gated) is a dormant within-cell selector that must NEVER fuse into one global scalar.

**Data types (reuse cited).**

```haskell
type Gene         = (PredictorShape, [Double])   -- GeneSimilarity.hs:68 expressGene input
newtype HeldTarget = HeldTarget { targetBytes :: [Int] }  -- REAL held bytes, never self-produced
type Schedule     = [Rung]                        -- prefix of the ladder; SelfSimilarReconstruct:131
type Packets      = Int                           -- I-packets + S-packets spent (DEVICE-MODEL-MAP:360)
type Meaning      = Int                           -- L1 loss reduction vs the floor decode, integer
newtype Entitlement = Entitlement [Int]           -- social/attention scope (dormant)

-- concrete TOTAL definitions so the goldens exercise the keystone's real type:
meaning   :: HeldTarget -> Gene -> Meaning   -- L1(decode(zeroParams), target) - L1(decode(gene), target)
packets   :: Schedule -> Packets             -- sum I (out^3 octant_unlift) + sum S (theta rungs x21 MAC)
admitted  :: HeldTarget -> Gene -> Bool
admitted t g = meaning t g > 0               -- strictly above floor = "does something"

dominates :: HeldTarget -> (Gene,Schedule) -> (Gene,Schedule) -> Bool
dominates t (gb,sb) (ga,sa) =
     meaning t gb >= meaning t ga && packets sb <= packets sa
  && (meaning t gb >  meaning t ga || packets sb <  packets sa)
```

Also reuse `zeroParams` (`GeneSimilarity.hs:89`), `expressionSource`/`FloorExact` (`SwapCarrier.hs:404`), `budgetToMask` (`PonderBudget.hs:58`), `expectedSteps` (`PonderHaltDistribution.hs:46`).

**Keystone (fixed, adopted).** The first draft was one-sided (`dominated ==> not isElite`): it only ever FORBIDS, never REQUIRES eliteness, so `isElite = const (const (const False))` (nothing ever elite) satisfies it identically and the whole Pareto frontier is decorative. The fix adds a liveness law and an admission-subset law so the empty predicate is illegal.

```haskell
-- Elite set contains no Pareto-dominated gene: another gene delivers >= meaning for <= packets
-- (strict in at least one axis). Wastes scarce decode-compute otherwise.
lawEfficiencyParetoDominated :: HeldTarget -> [(Gene,Schedule)] -> (Gene,Schedule) -> Bool
lawEfficiencyParetoDominated t pool a =
  any (\b -> dominates t b a) pool ==> not (isElite t pool a)

-- LIVENESS (the de-vacuifying companion): eliteness is non-trivial and admission-bounded,
-- so isElite = const False is now ILLEGAL and the Pareto law constrains a non-empty set.
lawEliteNonEmptyWhenAdmitted :: HeldTarget -> [(Gene,Schedule)] -> Bool
lawEliteNonEmptyWhenAdmitted t pool =
  any (admitted t . fst) pool ==> any (isElite t pool) pool

lawEliteSubsetAdmitted :: HeldTarget -> [(Gene,Schedule)] -> (Gene,Schedule) -> Bool
lawEliteSubsetAdmitted t pool a = isElite t pool a ==> admitted t (fst a)
```

**Supporting laws.**

```haskell
-- Selection weight orders EXACTLY as meaning-per-packet (integer cross-multiply, no divide).
lawMeaningPerPacketSelected :: HeldTarget -> (Gene,Schedule) -> (Gene,Schedule) -> Bool
lawMeaningPerPacketSelected t x@(gx,sx) y@(gy,sy) =
  (admitted t gx && admitted t gy) ==>
    (selectionWeight t x <= selectionWeight t y)
      == (meaning t gx * packets sy <= meaning t gy * packets sx)

-- ANYTIME KNAPSACK scoped to the HELD (within-capture) rungs: cumulative delivered meaning
-- is monotone in schedule-prefix length. NOT stated on the invented rung (non-injective).
lawScheduleAnytimeMonotoneHeld :: HeldTarget -> Gene -> Schedule -> Int -> Bool
lawScheduleAnytimeMonotoneHeld t g sch k =
  withinCapture sch ==>
    cumulativeMeaning t g (take k sch) <= cumulativeMeaning t g (take (k+1) sch)

-- COARSE LEGIBILITY WINS THE BUDGET: value provable at shallow depth is selectable under a
-- cap where a deep-only gene is not. Emergent pressure toward legible-at-shallow-depth genes.
lawCoarselyLegibleFitsBudget :: HeldTarget -> Gene -> Packets -> Bool
lawCoarselyLegibleFitsBudget t g cap =
  (meaningToDepth t shallowDepth g > 0 && packetsToDepth shallowDepth <= cap)
    ==> admittedWithin t cap g

-- FLOOR GENE = the Pareto origin: zero packets, zero meaning, admitted False, never elite, NEVER fails.
lawFloorGeneIsParetoOrigin :: HeldTarget -> Bool
lawFloorGeneIsParetoOrigin t =
  meaning t floorGene == 0 && packets [] == 0 && not (admitted t floorGene)
  where floorGene = (canonicalShape, zeroParams canonicalShape)  -- Showcase/FloorExact, SwapCarrier:460
```

**The failure it forbids.** An elite set that keeps a gene another gene weakly beats on both axes (wasted decode-compute); a selection rule that is NOT ordered by integer meaning-per-packet; a badly ordered schedule (fine-before-coarse) that regresses cumulative meaning on the held rungs; and a floor gene wrongly admitted or made elite. The disjointness of the two fitnesses is stated at the TYPE level (`admitted` has no `Entitlement` argument; a social `attentionRank` has no `HeldTarget` argument), NOT as a runtime law, because the drafted `lawAdmissionIsAttentionBlind` was reflexive `x == x` and carried a probable type error.

**Critic verdict: SOUND-WITH-FIXES. Fixes folded in.** The economics are right (held-target `meaning`, disjoint fitnesses, floor = Pareto origin, the self-produced-target risk correctly named). Three defects, one fatal to the keystone. (a) VACUITY: the keystone is one-sided so `isElite = const False` satisfies it identically and the Pareto frontier is decorative; FIX (adopted): add `lawEliteNonEmptyWhenAdmitted` and `lawEliteSubsetAdmitted` so eliteness is non-trivial and `const False` is illegal. (b) TAUTOLOGY: `lawAdmissionIsAttentionBlind` was `x == x` with a probable `implies`-precedence type error; FIX (adopted): DELETE it and state disjointness as a type-level fact in the Haddock, since the signatures already enforce it. (c) SOUNDNESS DRIFT: `lawScheduleAnytimeMonotone` was cited as resting on `lawFlowAdditiveInRank`, but that is the TIME axis, and the `64^3 -> 256^3` rung is invented/non-injective (`lawBeyondCaptureInvented`), so monotonicity there is unproven and can fail; FIX (adopted): scope it to the HELD (within-capture) rungs as `lawScheduleAnytimeMonotoneHeld`, resting on `lawWithinCaptureExact` and the `unliftVec` prefix identity, not the time axis. Authorability nit fixed: `meaning`/`packets`/`selectionWeight` are given concrete total definitions so the integer goldens exercise the keystone's real `Gene` type and it is QuickCheck-gateable.

**Device realization (all UNBUILT).** The budget head itself is UNBUILT (decode-cost report). Scheduling would ride `s4_cube_expand_rung` (`kernels.zig:924`) whose `S`-site fork at `:945-947` (`details != null` triggers the `theta_up` 21-param invention, `DeviceTrainShaders.metal:191` mint) is exactly one `S`-packet per rung; `details == null` is the free `I`-packet. `budgetToMask` (`PonderBudget.hs:58`) drives the per-octant refine/halt mask = which rungs spend their `S`-packet. Packet accounting (`MTL4CounterHeap` delta, `os_signpost` per class, `Feature.signpostPackets`) is the `DEVICE-MODEL-MAP.md:391-415` proposal, no code. `attentionRank` (social fitness) has NO device path and stays dormant until entitlements exist.

**Golden vectors (integer, byte-exact).** (1) Domination: A = (meaning 10, packets 4), B = (meaning 12, packets 3); `dominates B A` True so `isElite A` MUST be False (keystone witness). (2) Non-domination on efficiency: C = (20, 8) vs B = (12, 3), neither dominates; `20*3 = 60 < 12*8 = 96` so `selectionWeight C <= selectionWeight B` (`lawMeaningPerPacketSelected` witness). (3) Coarse-vs-deep under cap 4: shallow gene (meaning 8 at depth 1, packetsToDepth 2) `admittedWithin` True; deep gene (meaning 9 at depth 4, packetsToDepth 30) False. (4) Floor: `floorGene` gives meaning 0, packets 0, admitted False, never elite. (5) Liveness: a pool with one admitted gene yields a non-empty elite set.

**Single biggest soundness risk.** `meaning` MUST be loss reduction against a HELD, data-manufactured target, never a self-produced reconstruction and never `expressedEnergy`. Two ways it goes circular: (a) a self-produced target lets a gene inflate its own meaning by moving the target (the BYOL / L_close collapse already documented in the temporal-delta memory), making Pareto domination gameable and admission collapse to monoculture; (b) `expressedEnergy` (`GeneSimilarity.hs:142`) measures invented MASS above floor, the `S`-COST proxy, not value; conflating cost with value would reward genes for SPENDING packets, inverting the whole economy. The law therefore takes `HeldTarget` as an explicit argument and forbids any `meaning` implementation that reads the gene's own output as its reference.

---

### 3.3 `SixFour.Spec.BudgetHead`

**Module home.** New module, `MLX-MODEL | tag:MacTag` (a learned float head, Mac-side, off the byte-exact path, same class as `PonderHaltDistribution`/`PonderBudget`, emits no byte-golden of its own). Maintenance contract: add `SixFour.Spec.BudgetHead` to `spec.cabal` exposed-modules next to `PonderBudget` (`:145`) and `GeneSimilarity` (`:203`) plus a matching `Properties.BudgetHead`; one `Spec.Map` entry under the MLX-MODEL compartment; Haddock header stating the paint-order-independent estimate -> schedule -> packet chain.

**Purpose.** A gene is TWO-HEADED: its EXPRESSION (the 21-word `S`-weights `theta_up`, `DetailPredictor.paramCount = 7*3`, `:98-99`) and an ADVISORY BUDGET HEAD that estimates the gene's decode cost as a per-rung `I`/`K`/`S` packet schedule from the encoder, before any full decode is committed. The schedule lets a meta-controller split scarce decode-compute across competing genes (resource-rational allocation). It rides a tag-ADJACENT side field (see soundness fix) as a forward-compatible extension, `swapMinor` bump only, `swapMajor = 2` (`SwapCarrier:156`) unchanged. The head is ADVISORY: it may only gate WHICH rungs attempt an `S`-packet, never touch the coarse/DC, the volume buffer, or the octant operator. A wrong estimate lands the decode on a lower-distortion point of the SAME ladder, never off it. Honesty is TRAINED, not wire-enforced, via the PonderNet ponder-cost objective plus a compute penalty plus a geometric-prior KL.

**Keystone (fixed, adopted).** The drafted `lawAdvisoryBudgetNeverBlocksFloor` was vacuous: since `starveHead` just passes `Nothing` and `decodeWithBudget` is SPECCED to route the estimate solely through `expandRungVolume`'s `Maybe`, its clause (b) reduced to `expandRungVolume side vol Nothing == expandRungVolume side vol Nothing`, a restatement of the already-green `lawZeroTailIsFloor`. The teeth (a decoder that pre-allocates to the claimed length or subtracts `rpEstCost` from voxels in place) are never instantiated in Haskell, and the design ADMITS the law cannot see that wiring. The real enforcement is therefore a golden plus a compartment-lint at the Zig seam; the LAW form, if wanted, must quantify over an adversarial decoder family.

```haskell
-- (real teeth) Over an ADVERSARIAL decode-strategy family: every strategy that reads the
-- estimate OUTSIDE the Maybe [Detail] fork fails to reproduce the floor on a starved head.
-- This is the only formulation where the hazard (buffer pre-alloc, in-place cost subtraction)
-- is IN-SPEC rather than lint-only.
lawOnlyMaybeForkIsFloorSafe :: DecodeStrategy -> Int -> [Int] -> Bool
lawOnlyMaybeForkIsFloorSafe strat side vol =
  readsEstimateOutsideMaybe strat
    ==> runStrategy strat (starveHead defaultHead) side vol /= expandRungVolume side vol Nothing

-- (golden + Zig-seam lint, NOT the keystone) the reference decodeWithBudget on a starved head
-- reproduces the byte-exact floor. Pinned, not advertised as a theorem.
goldenStarvedHeadIsFloor :: Bool
goldenStarvedHeadIsFloor =
  decodeWithBudget (starveHead defaultHead) 1 [200] == replicate 8 200
```

**Supporting laws.**

```haskell
-- ADVISORY, not enforced: cap is THREADED into the decode so a lying/low estimate cannot
-- unlock spend beyond cap (was ill-typed: cap never reached the decoder).
lawBudgetHeadBoundsActualPackets :: BudgetHead -> Int -> Int -> [Int] -> Bool
lawBudgetHeadBoundsActualPackets bh cap side vol =
  spentCost (decodeWithBudgetCapped cap bh side vol) <= cap

-- A weightless/absent-head gene (Showcase) schedules zero S and expresses the depth-0 floor.
lawZeroBudgetHeadIsShowcaseFloor :: SwapPayload -> Bool
lawZeroBudgetHeadIsShowcaseFloor p =
  spProfile p == Showcase ==> ( null (bhSchedule (headOf p))
                              && expressionSource (normalizePayload p) == FloorExact )

-- Forward-compatible: a budget-BLIND decoder produces the identical expression (no MAJOR bump).
lawBudgetHeadForwardCompatible :: SwapPayload -> BudgetHead -> Bool
lawBudgetHeadForwardCompatible p bh =
     swapMajorOf (encodeWithBudget bh p) == swapMajor
  && expressionSource (extractBase (encodeWithBudget bh p)) == expressionSource (normalizePayload p)

-- NEW (critique fix): the advisory is stored tag-ADJACENT, excluded from the tag-identity hash,
-- so a nondeterministic learned-float estimate cannot perturb tag identity / dedup / the pullback.
lawBudgetAdvisoryDoesNotChangeTagIdentity :: SwapPayload -> BudgetHead -> BudgetHead -> Bool
lawBudgetAdvisoryDoesNotChangeTagIdentity p bh1 bh2 =
  tagIdentityHash (encodeWithBudget bh1 p) == tagIdentityHash (encodeWithBudget bh2 p)

-- Under-estimating lands on a COARSER prefix of the SAME ladder, never a different cube.
lawWrongEstimateMonotoneDegrade :: BudgetHead -> BudgetHead -> Rungs -> Bool
lawWrongEstimateMonotoneDegrade lo hi r =
  scheduleLeq lo hi ==> ( achievedDepth lo r <= achievedDepth hi r && achievedDepth lo r >= 0 )
```

**The failure it forbids.** A budget head that BLOCKS the decode (a short buffer on an under-estimate) or CORRUPTS it (voxels mutated in place by a claimed cost), a MISSING head defaulting to "refine everything" over an inert gene, an estimate in a required MAJOR-versioned field that breaks existing `s4_gif_decode`, a smaller estimate flipping to a corrupt reconstruction rather than a coarser one, and (the tag risk) a learned-float advisory folded into the tag bytes that breaks tag determinism and dedup.

**Critic verdict: SOUND-WITH-FIXES. Fixes folded in.** The sharpest objection is keystone vacuity: `starveHead` passes `Nothing` and `decodeWithBudget` is specced to route the estimate solely through the `Maybe`, so clause (b) is `floor == floor`, the teeth are never instantiated in Haskell, and the design admits the law cannot see the wiring; so the keystone bought no new safety and a corrupting device port passes it. Secondary genuine bugs: `lawBudgetHeadBoundsActualPackets` universally quantified `cap` but never PASSED it into `decodeWithBudget`, making it ill-formed (false at `cap=0`, vacuous at large `cap`); `lawBudgetHonestyIsPonderCost` never mentioned `bh` in its body, a restatement of KL >= 0 that passes regardless of head behavior, and cited an unbuilt `ponderObjective`. Soundness watch: riding the advisory on `spTag` risks tag identity if the mint ledger or `GeneSimilarity` pullback keys on tag bytes. THE FIX (adopted): (1) downgrade the keystone to a golden plus a Zig-seam compartment-lint (the real enforcement), and offer `lawOnlyMaybeForkIsFloorSafe` over an adversarial `DecodeStrategy` family as the in-spec law with actual teeth; (2) thread `cap` into `decodeWithBudgetCapped`; (3) DROP `lawBudgetHonestyIsPonderCost` as redundant with PonderNet (honesty is priced by the existing ponder objective, not a new head-blind KL restatement); (4) store the advisory tag-ADJACENT, excluded from the tag-identity hash, and add `lawBudgetAdvisoryDoesNotChangeTagIdentity`. Anchor corrections carried: `lawZeroBudgetIsFloor` is `:74` (not `:70`), `lawZeroTailIsFloor` `:213-221`.

**Device realization (mostly UNBUILT).** Estimator (float, learned): a Mac-side MLX head beside the `theta_up` `S`-mint (`DeviceTrainShaders.metal deviceTrainFused`, `DEVICE-MODEL-MAP.md:335`), UNBUILT, no `Codegen.BudgetHead` emitter. Schedule to decode: drives the refine/halt mask (`PonderBudget.budgetToMask:58`) feeding `s4_cube_expand_rung` (`kernels.zig:924`); the `details == null` fork (`:945`) IS the `I`-vs-`S` packet switch, so skipping a rung's `S`-packet passes `null` for a deterministic floor; the FORK is BUILT, the head that DECIDES is UNBUILT. Re-measure plus cap (`lawBudgetHeadBoundsActualPackets`): `Feature.signpostPackets` plus `MTL4CounterHeap` GPU-time cap (`DEVICE-MODEL-MAP.md:372-374`), PROPOSED, UNBUILT. Carrier: advisory field tag-adjacent, `swapMinor` bump only; the `Codegen.SwapCarrier` base block exists, the advisory extension is UNBUILT.

**Golden vectors.** The head emits no byte-golden (float, Mac-side); two pins it must carry. (1) Floor tooth (the keystone's foundation): `decodeWithBudget (starveHead defaultHead) 1 [200] == expandRungVolume 1 [200] Nothing == replicate 8 200` (reusing `lawVolumeExpandFloorConstant`'s pinned form, `SelfSimilarReconstruct:292`). (2) Forward-compat pair: one Showcase (to `FloorExact`, zero weight bytes) and one Grant (to `Learned` 21-word `theta`) payload each carrying a budget-advisory field, decoded by the BASE extractor, must yield the identical `expressionSource` as the un-augmented payload, and identical `tagIdentityHash` across two different advisory values (pins `lawBudgetAdvisoryDoesNotChangeTagIdentity`).

**Single biggest soundness risk.** The advisory boundary LEAKING into the decode data path. The safety holds only if the estimate is read-only w.r.t. reconstructed bytes: it may gate the `Maybe [Detail]` argument of `expandRungVolume` (the sole proven-total `S`/`I` fork, `kernels.zig:945`) and nothing else, never `side`, never `vol`, never the buffer length. If a device port ever computes cost FROM the volume in place (subtracting `rpEstCost` from voxels, or truncating output to the estimated length), a wrong estimate corrupts the floor and the guarantee goes vacuous. The Haskell law cannot see that wiring, so this must ALSO be a compartment lint asserted at the Zig seam: `decodeWithBudget` routes the estimate solely through the detail `Maybe`, checked in code, not only in the spec.

---

## 4. THE UNIFICATION

One page: five quantities that look independent are the SAME integer, and Showcase (depth-0) is the graceful-degradation fallback for all of them.

**The identity.**

```
decode-depth = A7 rung depth = halting read-depth = compute-packet count = attention grant
```

- **decode-depth** is how many detail rungs `s4_cube_expand_rung` (`kernels.zig:924`) has climbed above the coarse floor: `16^3 -> 32^3 -> 64^3 -> ... -> 256^3`, one octant_unlift level per step.
- **A7 rung depth** is the same integer read off the octree spine: branching is 8 (`ScaleFiltration.lawOctantBranchingIs8:116-117`), the densest dim-7 packing `A7` = 1 coarse plus 7 detail bands, and nested balls prove each finer level sits inside the coarser (`lawBallsNested:97-98`). Depth in the ball filtration IS depth on the rung ladder.
- **halting read-depth** is the same integer on the PonderNet spine: `expectedSteps` (`PonderHaltDistribution.hs:46`) is the expected rung depth, and more budget yields a deeper read (`lawLowerHaltRefinesMore:96-100`). Halting at rung `k` is a bounded valid intermediate (`lawExpectedLossIsConvex:71-77`).
- **compute-packet count** is the same integer as a resource: `packetsAboveFloor = readDepth - 1`, each finer rung costing one `K` (pool) or `S` (invent) packet, the coarse floor read being the free `I` packet (`DEVICE-MODEL-MAP.md:360-368`). `PacketEconomy.packets` sums exactly these.
- **attention grant** is the same integer as an entitlement: a grant of decode-compute is how many packets a gene is allowed to spend on a region, i.e. how deep it is allowed to read, i.e. its `expectedSteps` prior. Attention as scarce-processing allocation (BBS 2020) is literally the depth dial.

**Showcase = depth-0 IS the graceful-degradation fallback.** At depth 0 all five collapse to the same base: zero rungs climbed, `A7` rank 0 (coarse only), halting immediately (`lambda_p = 1`), zero packets spent, zero attention granted. That base is the `FloorExact` Showcase (`SwapCarrier.lawShowcaseIsInert:457`, physically zero weight bytes), the always-safe reconstruction the hard constraint demands. Every one of the three laws bottoms out here: `AnytimeDecode.lawFloorAlwaysDecodable`, `PacketEconomy.lawFloorGeneIsParetoOrigin`, `BudgetHead.lawZeroBudgetHeadIsShowcaseFloor`. Graceful degradation is not a separate mechanism; it is depth-0 of the one ladder.

**The S/K/I combinator reading.** The refinement ladder is a substructural-logic spine (carried from the SKI/PonderNet digest): `I` = the reversible coarse prefix, free, the floor read, always available; `K` = pool/contract (weakening, a lossy commit that discards detail); `S` = weighted expand/invent (the up-rung `theta`-mint, where new information is manufactured). The GENE lives on the `S` band: it is exactly the `theta_up` 21-param invention (`DeviceTrainShaders.metal:191`, `kernels.zig:945` `details != null`). So competition for decode-compute is competition for `S`-packets specifically: `I` is free and always granted (the floor), `K` is bounded pooling, and the scarce, minted, weight-bearing resource genes fight over is the `S` expansion. This is the earlier goal made precise: maximize the useful latent operations per packet of allowable computation = maximize MEANING per `S`-packet = climb the `PacketEconomy` Pareto frontier. The budget head estimates the `S`-schedule; the packet economy ranks genes by meaning-per-`S`-packet; the anytime contract guarantees that halting the `S`-climb at any rung still leaves a valid `I`-floor image underneath.

---

## 5. AUTHORING ORDER + WIRING

**Order and why.**

1. **`AnytimeDecode` FIRST.** It is pure over the shipped octant inverse `unliftF`/`unliftOct` on the integer floor, buildable TODAY with zero dependency on a budget head, a trained encoder, or any wire byte. After the critique fix it is a REAL regression guard on the decode path (a non-additive override flips it), not a theorem about `scanl`. No lock breaks: the floor bridge rides `lawZeroTailIsFloor`/`lawShowcaseIsInert`, no interaction with `EncoderFrozen` or mint-credit. Its critique is the cheapest to discharge (re-target the keystone at the class method, make the bridge non-reflexive, make the witness existential). It is the contract the other two bottom out on, so landing it first sets the floor guarantee before the economy references it. Tier-0.

2. **`PacketEconomy` SECOND.** `meaning`/`packets` ride the built `expressGene`/`predictDetail` fitness path and `zeroParams` floor, so the re-keyed keystone is landable without new device work. It lands second because its first-draft keystone is one-sided and VACUOUS and must be repaired (add the liveness and admission-subset companions, delete the reflexive attention-blind law, scope the monotonicity to held rungs), a larger edit than the AnytimeDecode re-target, and because its anytime-knapsack law depends ON TOP of a settled `AnytimeDecode` contract (`lawScheduleAnytimeMonotoneHeld` rests on the same held-rung exactness). Tier-0 for the Pareto/liveness core; the `attentionRank` social selector and any device packet counter are Tier-1 follow-ons.

3. **`BudgetHead` LAST.** The estimator is a learned float head with NO code today, and its critique demotes the advertised keystone to a golden-plus-Zig-seam-lint, so the pure laws that remain (`lawBudgetHeadBoundsActualPackets` capped, `lawBudgetHeadForwardCompatible`, `lawBudgetAdvisoryDoesNotChangeTagIdentity`, `lawWrongEstimateMonotoneDegrade`) are contract-only and reference the two data-side laws it sits above. Land it once AnytimeDecode and PacketEconomy are green. Tier-0 for the pure carrier/forward-compat/tag-identity laws; the estimator, the `Codegen.BudgetHead` emitter, and the packet counters are Tier-1.

**Per-module wiring (the maintenance contract).**

- **`AnytimeDecode`**: `spec.cabal exposed-modules += SixFour.Spec.AnytimeDecode` after `SelfSimilarReconstruct` (`:112`); `Spec.Map` one-line entry sibling to the `SelfSimilarReconstruct` block (`Map.hs:318`) tagged `DisplaySide`; `{- | Module / Description -}` header citing `RefinementSystem`/`SelfSimilarReconstruct`/`SwapCarrier` and Equitz-Cover; `gate-order.txt` inserts `Properties.AnytimeDecode` (near `:469`) AFTER `RefinementSystem`, `SelfSimilarReconstruct`, `PonderHaltDistribution`, `SwapCarrier` (it delegates all four). Golden module `AnytimeDecodeGolden`.

- **`PacketEconomy`**: `spec.cabal += SixFour.Spec.PacketEconomy` alongside `GeneSimilarity` (`:203`); `Spec.Map` entry after the `GeneSimilarity` line (`Map.hs:1123`) tagged `DisplaySide`; header stating the decode-packet -> meaning-per-packet -> Pareto chain; `gate-order.txt` AFTER `GeneSimilarity` (fitness), `SelfSimilarReconstruct` (held-rung exactness), `PonderBudget`, and `AnytimeDecode` (the anytime contract). Golden `PacketEconomyGolden`.

- **`BudgetHead`**: `spec.cabal += SixFour.Spec.BudgetHead` next to `PonderBudget` (`:145`)/`GeneSimilarity` (`:203`); `Spec.Map` entry under the MLX-MODEL compartment tagged `MacTag`; header stating the estimate -> schedule -> packet chain and the ADVISORY (tag-adjacent, not tag-identity) rule; `gate-order.txt` AFTER `PonderBudget`, `SwapCarrier`, `SelfSimilarReconstruct`, `PacketEconomy`, `AnytimeDecode`. Golden `BudgetHeadGolden`.

**Tier-0 vs Tier-1 and unbuilt-dependency flags.**

- Tier-0 (gate before any port ships): AnytimeDecode all scoped laws; PacketEconomy Pareto + liveness + held-rung monotonicity + floor-origin; BudgetHead capped-bound + forward-compat + tag-identity + monotone-degrade, plus the starved-head golden.
- Tier-1 (follow-on ports, not gate blockers): the Swift null-on-fault decode guarantee; the `256^3 -> 64^3` collapse direction; the learned MLX estimator + `Codegen.BudgetHead`; per-rung packet counters (`Feature.signpostPackets`, `MTL4CounterHeap` cap); `attentionRank` and any entitlement plumbing.
- Unbuilt-dependency flags: the BUDGET HEAD ITSELF is unbuilt (`expressedEnergy` `GeneSimilarity.hs:142` and `budgetToMask` `PonderBudget.hs:58` are the substrate, not the head); PER-RUNG PACKET COUNTERS are a `DEVICE-MODEL-MAP.md:391-415` proposal with no code; ATTENTION ENTITLEMENTS do not exist (the social `attentionRank` fitness is dormant, type-disjoint from admission, and has no device path); the FULL rung-ladder anytime equality above the held rung depends on the unbuilt collapse direction; a PER-RUNG `theta` STACK is implied by the cost model but the spec carries one shared 21-param predictor (`lawReusesOnBothRungs`), not a per-rung stack.

---

## 6. OPEN DECISIONS FOR THE OWNER

1. **Advisory carrier: tag-adjacent side field vs a separate advisory record.** The critique forced the estimate OFF the tag-identity hash. RECOMMENDED DEFAULT: a `swapMinor`-bumped tag-ADJACENT field excluded from `tagIdentityHash`, pinned by `lawBudgetAdvisoryDoesNotChangeTagIdentity`, so a nondeterministic learned-float estimate can never perturb dedup or the `GeneSimilarity` pullback. Do NOT fold it into `spTag` bytes.

2. **Per-rung theta: one shared predictor vs a per-rung stack.** The cost model treats each rung's `S`-packet as independent, but the spec ships ONE 21-param `theta` reused on both rungs (`lawReusesOnBothRungs`). RECOMMENDED DEFAULT: keep the single shared predictor until a measured need appears; state the packet SCHEDULE per-rung (which rungs fire) while the WEIGHTS stay shared, so the economy is expressible without reopening the self-similar ladder.

3. **Meaning reference: strict held-target only, or allow a cached target.** `meaning` must be against a HELD data-manufactured target to avoid the BYOL/L_close collapse. RECOMMENDED DEFAULT: strict held-target only, `HeldTarget` an explicit non-optional argument, and forbid any `meaning` reading the gene's own output; a cached target is a Tier-1 optimization gated behind a proof it is not gene-movable.

4. **Attention grant units: raw packet count vs normalized entitlement.** An attention grant IS decode-depth, but the social layer is dormant. RECOMMENDED DEFAULT: express grants as integer `packetsAboveFloor` (the same unit as `PacketEconomy.packets`) so attention and machine-cost share one currency, keep `attentionRank` type-disjoint from `admitted`, and defer any normalized/relative entitlement until entitlements exist.

5. **BudgetHead keystone form: golden-plus-lint only, or also the adversarial-family law.** The critique demoted the keystone to a golden plus Zig-seam lint; `lawOnlyMaybeForkIsFloorSafe` over a `DecodeStrategy` family is the only in-spec form with real teeth. RECOMMENDED DEFAULT: land BOTH, the golden as the cheap gate and the adversarial-family law as the theorem, and make the Zig-seam compartment-lint (estimate routed solely through the detail `Maybe`) a hard CI check, since the pure Haskell law alone cannot see the wiring hazard.

---

*This document extends `docs/GENE-LAWS-DESIGN.md`: those three laws (DescriptorQuasiIsometry, PaintOrderPrior, GeneRecombination) govern which genes are admissible and comparable in the atlas; these three (AnytimeDecode, PacketEconomy, BudgetHead) govern which genes get to spend the scarce decode-compute, and guarantee that spending less never breaks the picture.*

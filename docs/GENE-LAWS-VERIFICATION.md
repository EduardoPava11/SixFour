# GENE LAWS: VERIFICATION AND GO/NO-GO

2026-07-02. Proof report for landing the six gene laws. Each law was given an honest, buildable Haskell body, compiled against the REAL `spec/src` modules under GHC 9.2.8 (`cabal exec -- runghc -isrc`), run against pinned golden witnesses, cross-checked against the existing green invariants it delegates to, and stress-tested for non-vacuity with a deliberately-wrong foil that MUST fail where the correct body passes. A law is only landable if its keystone is constructible over real primitives, consistent with the shipped decode/carrier/ledger path, and non-vacuous. Pairs with `docs/GENE-LAWS-DESIGN.md` (design of record) and `docs/GENE-COMPUTE-ECONOMY.md` (§3.1 AnytimeDecode). Starts, as always, at `SixFour.Spec.Map`.

---

## 1. VERDICT

| Law | Constructible | Consistent | Non-Vacuous | Stubs | Verdict |
|-----|---------------|------------|-------------|-------|---------|
| DescriptorQuasiIsometry | YES | YES | YES | none | **LANDED** (in `spec/`, green `cabal test`) |
| PacketEconomy | YES | YES | YES | none | **PROVEN** |
| PaintOrderPrior | YES | YES | YES | pure `TouchOrder` model, prior linear constants (non-load-bearing) | **PROVEN** |
| GeneRecombination | YES | YES | YES | none | **PROVEN** |
| BudgetHead | YES | YES | YES | learned float head (Tier-1 UNBUILT) | **PROVEN_MODULO_STUB** |
| AnytimeDecode | PARTIAL | YES | YES | Showcase-to-floor coarse supplied externally | **REPAIRED** (doc §3.1 re-keyed 2026-07-02) |

**UPDATE 2026-07-02: DescriptorQuasiIsometry LANDED into `spec/` end-to-end.** New module `SixFour.Spec.DescriptorQuasiIsometry` (100% Haddock, warning-clean) plus `Properties.DescriptorQuasiIsometry` (9 tests: Vandermonde full-rank keystone, non-vacuity collision, two-sided bound over the validated corpus, upper Lipschitz, lower separation, honest quotient, sub-LSB slack, bounded distortion, collapsing-descriptor foil), wired into `spec.cabal` (exposed + test-suite), `Spec.Map`, and `test/Spec.hs`. Full `cabal test` = PASS. **AnytimeDecode §3.1 keystone REPAIRED** in `docs/GENE-COMPUTE-ECONOMY.md`: re-keyed off the unsound octant `unliftF`/`unliftOct` re-target (the averaging inverse fails the prefix property, GHC-proven) onto the additive `unliftVec` scheme-1 prefix carrier, with the octant anytime guarantee stated separately as floor totality.

**GO / NO-GO (updated): 1 LANDED (DescriptorQuasiIsometry), 4 CLEARED to land (PacketEconomy, PaintOrderPrior, GeneRecombination, BudgetHead), AnytimeDecode keystone REPAIRED and now landable.** The buildable content of AnytimeDecode was always green (25/25 enumerated + 4x100 QuickCheck); the repair fixed only the DESIGN doc §3.1 keystone symbol.

---

## 2. PER-LAW PROOF

### 2.1 DescriptorQuasiIsometry (PROVEN)

Probe: `scratchpad/DescriptorQuasiIsometryProbe.hs`. The floor/gate law that the others reference for the metric.

Imported: real `SixFour.Spec.GeneSimilarity` (`geneDistance`, `lawGaugeQuotient`, `lawProbeSeparates`, `lawPullbackPseudometric`), `SixFour.Spec.Q16` (`quantizeQ16`, `lawTerminalQuantizationIdempotent`), plus `expressGene` for the self-check.

Honest bodies: the two-sided quasi-isometry `c1 . dq <= dc <= c2 . dq` was stated on Q16 FLOOR representatives (`geneDistance sh (floorGene a) (floorGene b)`), constants pinned `loNum/loDen = 1/2` (c1 = 0.5), `hiNum/hiDen = 18/1` (c2 = 18), `slack = 0`, `kappa = 36`. `floorGene` (renamed `floorRep` at co-compile to avoid the PacketEconomy collision) is the honest quotient built from `quantizeQ16`.

Golden witnesses that ran: G1 integer Vandermonde det at s in {-1,0,1} = 2 (nonzero, full rank, separates); degenerate collinear s={0,0,0} det = 0 (rank-deficient, cannot separate). G2 `lawSlackBelowOneStep` True (0 < 2), kappa = 36.0. G3 collapse witness dq=1, dc=2, lower bound holds; WRONG collapsing descriptor FAILS. G4 discontinuity witness dq=1, dc=9, upper bound holds. G5 gauge witness (1e-12 vs zero) dq=0, dc=0. Enumeration over 15328 pairs: kernel dq=0 iff dc=0 True; two-sided QI True; keystone separates on real Phi True; measured min dc/dq = 2.0, max = 11.0 (inside the pinned c1=0.5, c2=18 envelope).

Existing invariants cross-checked (must-not-break, all True on shared inputs): `lawGaugeQuotient`, `lawProbeSeparates`, `lawPullbackPseudometric` (2 triples), `lawTerminalQuantizationIdempotent` (6 grid points), `lawFloorKernelIsGaugeKernel` (samples + 15328-pair enumeration).

Non-vacuity: C1 correct lower bound holds True, WRONG collapse fails True. C2 degenerate probe clouds agree True but Q16 floors differ True, so keystone FALSE on the degenerate design (as required) and TRUE on the real design for the same genes. Both bounds are THEOREMS, not merely empirical: the lower `dc >= dq/2` follows from the exact integer readouts at s in {-1,0,1} (per band |u|+|u+v+w|+|u-v+w| >= max(|u|,|v|+|w|) >= (|u|+|v|+|w|)/2, base-independent); the upper `dc <= 18 dq` from the +1-per-probe ceiling `dc <= 9 dq + 9 <= 18 dq` for dq>=1, and dq=0 implies dc=0.

Design reconciliations (folded into the probe, none block the law): (1) doc §4 `import GeneSimilarity (..., zeroParams)` is wrong, `zeroParams` is exported only by `DetailPredictor`. (2) doc `import DetailPredictor (..., toQ16)` is wrong, `toQ16` lives in `Spec.Q16`. (3) `toQ16 :: Int -> Double` is the inverse VIEW; the Double->Int floor quantiser is `quantizeQ16` (Q16.hs:19). (4) dc MUST be computed on FLOORED genes or a dq=0 pair with sub-LSB-distinct Doubles yields dc>0 and falsifies the upper bound at dq=0. The design should pin "stated on Q16 floor representatives, never raw fp32 theta".

### 2.2 PacketEconomy (PROVEN)

Probe: `scratchpad/PacketEconomyProbe.hs`. No stubs. 20 PASS / 0 FAIL.

Imported and resolved against the real signatures: `GeneSimilarity` (`lawFloorIsOrigin`, `expressedEnergy`), `SelfSimilarReconstruct` (`expandRungVolume`). Honest bodies: `Schedule`/`Rung` are a type the NEW module must DEFINE (see repair note below), given `data Rung` placeholder and `packets = length` (one packet per rung climbed, floor `packets [] == 0`). `meaning` bridges through the real `expressGene`/`predictDetail`.

Golden witnesses: `paramCount defaultShape = 21`. Floor `decodeBytes` all zero True. GOLDEN 4 `meaning tHeld floorGene = 0`, `packets [] = 0`, admitted False, `lawFloorGeneIsParetoOrigin` PASS. GOLDEN 1 meaning A=1032192 packets 4, meaning B=2064384 packets 3, `dominates B A = True`, `isElite A = False`, keystone PASS. GOLDEN 3 literal `mC*pB=60 < mB*pC=96` orders C<=B PASS; real `selWeightLeq C B` True (4644864 vs 16515072), `lawMeaningPerPacketSelected` both directions PASS. LIVENESS elite members=[1], `lawEliteNonEmptyWhenAdmitted` PASS, `lawEliteSubsetAdmitted` PASS.

Existing invariants cross-checked: `lawFloorIsOrigin` PASS (our `floorGene meaning == 0` delegates to exactly this: floor cloud all-zero plus self-distance 0), `expressedEnergy (zeroParams) == 0` PASS, `expandRungVolume side vol Nothing == floor` PASS on shared side=2, val=4242.

Non-vacuity (3 demonstrations): NV1 `isElite = const False` makes the liveness law False while correct passes (proves the liveness companion is needed since `const False` still vacuously satisfies the one-sided Pareto law). NV2 `badGene` TRUE meaning=-2064384 (admitted False, correctly rejected) but SELF-target meaning=+2064384 would be admitted and GAMED; self-target meaning == expressedEnergy conflates S-cost with value, proving `meaning` MUST take an explicit `HeldTarget`. NV3 Pareto-blind `isElite` keeps really-dominated A elite so FAILS the keystone while correct passes.

Two doc NEEDS_REPAIR nits (worked around, do not affect soundness): (1) the skeleton annotates `type Schedule = [Rung]  -- SelfSimilarReconstruct:131` but there is NO singular `Rung` at that line; the real type is the `Rungs` record. Schedule/Rung is a type the new module DEFINES, not imports; citation is wrong. (2) the literal golden integers meaning 10/12/20 are not producible by the cited `meaning` bridge over real `expressGene`/`predictDetail`: `reenterQ16` makes the smallest nonzero byte magnitude ~1311, so constant-gene meanings arrive in multiples of 1311 (observed 1032192, 2064384, 1548288) with a parity constraint. The numbers are valid at the integer-ALGEBRA level (60 < 96 orders C<=B) but are not literal primitive outputs; label them illustrative or supply Q16-scaled values.

### 2.3 PaintOrderPrior (PROVEN)

Probe: `scratchpad/PaintOrderPriorProbe.hs`. ALL PASS.

Imported: real `PonderHaltDistribution` (`geometricPrior:51`, `expectedSteps:47`, `lawLowerHaltRefinesMore`, `lawExpectedLossIsConvex`), `ScaleFiltration` (`lawOctantBranchingIs8:116`, `branching`), `PonderBudget` (`budgetToMask:58`), `CellNudge` (`CellBudget:48`, `paintCellPair`), `PairTree` (`paletteDepth:91`).

Stubs (none load-bearing on the keystone): `TouchOrder` modelled as `[CellIx]` (the Swift `NudgePaintView` touchOrder field is UNBUILT; task and doc sanction this pure model and the LAW is pure). The `haltSeed rank->lambda_p` map uses chosen linear constants `clamp01(0.15 + 0.10*rank)`, a prior-side KL-target modelling choice standing in for the unbuilt learned per-region budget head; it feeds ONLY the supporting `lawEarlierTouchReadsDeeper` and the float/int bridge, never the keystone. `packetsMagnitudeOnly` is the deliberately-wrong order-blind foil. The keystone rides the integer `packetsAboveFloor` schedule (`ceilingRank - rank` via `elemIndex` + `ScaleFiltration.branching`), fully built from real primitives.

Golden witnesses: ceilingRank (A7) = 7, paletteDepth = 8, nPairs = 9. G1 order [a,b] depth a=7 b=6, order [b,a] depth a=6 b=7, depths SWAP under order swap. G2 packets(rank0)=7 > packets(rank1)=6. G3 unpainted cell lambda_p == 1.0 exactly, 0 packets (`lawUnpaintedHaltsAtFloor`). G4 total packets 25 before and after permutation (`lawPacketBudgetConserved`, reallocates never inflates). G5 rank-0 => 7 never 8. A7 ceiling: long order (rank,packets) strict for ranks<8 and order-preserving tie beyond 7. KEYSTONE `lawPaintOrderTracksRankUnderPermutation` holds over ALL perms of a 5-cell order.

Existing invariants cross-checked: `lawLowerHaltRefinesMore` (real module, untouched) PASS, `lawExpectedLossIsConvex` holds on our seeds' halt distributions PASS, `lawOctantBranchingIs8` gives ceilingRank = `branching 2 3 - 1 = 7 = paletteDepth-1`, reconciling the A7 [0,7] ceiling, `budgetToMask(emptyBudget)` refines nothing (untouched cell => mask all-False => 0 packets).

Non-vacuity: the magnitude-only policy satisfies keystone False (expected False) and CANNOT swap `a`'s depth between [a,b] and [b,a] (False, expected False), so the wrong policy FAILS while the correct policy PASSES.

Two doc-vs-real signature reconciliations (design skeleton stale, not the code, no law repair): (1) `lawLowerHaltRefinesMore` is nullary (`:: Bool`) in the real module, not `(TouchOrder -> Bool)`. (2) `CellNudge.paintCellPair` has arity 4 (`CellBudget -> Int -> Int -> Int -> CellBudget`), not 5.

### 2.4 GeneRecombination (PROVEN)

Probe: `scratchpad/GeneRecombinationProbe.hs`. No stubs. 28/28 core checks pass, zero GHC errors/warnings.

Imported and resolved against real signatures: `GeneHash`, `DetailPredictor`, `GeneSimilarity`, `LedgerCRDT`, `SwapCarrier`, `Trade`, `Q16`. The re-keyed keystone `lawChildGrantableIffBothParentsHeld` is built entirely from real primitives (`geneHash` + `Trade.holdings` + integer lerp); the load-bearing part uses NO stub.

Golden witnesses (8/8): G1 lambda=0x8000 payload == per-word midpoint `floor((a+b)/2)` (`take 21 (cycle [32768,16384,8192])`). G3a lambda=0 `geneDistance child pa == 0` and child payload byte-identical to pa. G3b lambda=0x10000 `geneDistance child pb == 0` and byte-identical to pb. G5 `geneHash child(pa,pb) /= geneHash child(pb,pa)`, `gpParents == [idOf pa, idOf pb]` in order, payloads equal at midpoint so hashes differ ONLY via parent order. Keystone (3/3): holds on ledgerBoth, ledgerOne, [] with the correct AND-impl.

Existing invariants cross-checked (delegated green, all PASS on shared inputs): `GeneHash.lawBuiltGenealogyAcyclic` (child extends acyclic Merkle-DAG; DAG grew to 3 genes), `LedgerCRDT.lawStateHomomorphism`, `LedgerCRDT.lawHoldingsFromState` (bob), `GeneSimilarity.lawPullbackPseudometric` (paramsOf pa/pb/child), `lawGaugeQuotient`, `lawFloorIsOrigin`, `lawProbeSeparates`, `SwapCarrier.lawShowcaseIsInert`, `SwapCarrier.lawGrantOnlyFromSettledTrade`. Also: `stateOf led' == stateOf led` (crossover adds no trade, zero G-Set growth), and a grant-inserting mintChild strictly grows the G-Set (`Set.isProperSubsetOf`).

Non-vacuity (4/4): NV1 correct `mayGrantChild ledgerOne bob child == False` (bob holds only pa, no laundering). NV2 deliberately-WRONG OR-impl == True (would launder). NV3 keystone with correct impl PASSES on ledgerOne. NV4 keystone with wrong OR-impl FAILS on ledgerOne; genuine non-vacuity since the keystone is an `==` equivalence with RHS=False there, not a vacuous implication.

Three doc NEEDS_REPAIR items on the skeleton (§2.3), reported precisely, none blocking the proven LAW: (1) PHANTOM EXPORTS: `holdsGene` is NOT exported by `LedgerCRDT` or anywhere; the real primitive is `SixFour.Spec.Trade.holdings :: Ledger -> CreatorId -> Set GeneId`, so `holdsGene led who g` must be `Set.member g (holdings led who)`. `ParentGene`, `Child`, `BlendWeight`, `idOf`, `recombine`, `halfLambda`, `mayGrantChild` are all doc-invented, given honest total definitions (ParentGene=Child=GenePreimage, idOf=geneHash, BlendWeight=Int Q16). (2) BLEND-FORMULA SIGN CONTRADICTION: the prose says `lambda.thetaA + (1-lambda).thetaB` (gives thetaB at lambda=0) but its own golden #3 and `lawBlendAtEndpointsIsParent` require lambda=0 -> pa; the consistent convention is `child = (1-lambda).thetaA + lambda.thetaB`. (3) 0xFFFF IS NOT UNITY: the pinned lambda set uses 0xFFFF as the top endpoint but Q16 unity is 0x10000; with 0xFFFF the child head is [1,0,0] vs pb [0,0,0], NOT byte-exact. Pin 0x10000. Minor: `mayGrantChild` uses `gpParents child !! 0/!!1` (partial), total only because `recombine` always yields exactly 2 parents.

### 2.5 BudgetHead (PROVEN_MODULO_STUB)

Probe: `scratchpad/BudgetHeadProbe.hs`. Compiles clean against the real modules; every line PASS, no GHC errors/warnings.

Stubs (the learned float head is UNBUILT, no `Spec.BudgetHead` module exists, exactly as the doc marks it Tier-1): `BudgetHead` modelled as `newtype BudgetHead{bhSchedule::[Int]}` per-rung packet schedule; `decodeWithBudget` / `decodeWithBudgetCapped` / `spentCost` / `starveHead` / `defaultHead` reference decoders route the advisory SOLELY through the real `expandRungVolume Maybe [Detail]` fork; `Augmented` tag-adjacent carrier plus `encodeWithBudget` / `extractBase` / `swapMajorOf` / `tagIdentityHash` (= `encodeSwapBlock` of the real base payload); `DecodeStrategy` family plus `readsEstimateOutsideMaybe` / `runStrategy` adversarial family. No stub touches the float estimator's numeric behaviour, so the proven laws do not depend on the stubbed learned part.

Imported and resolved (constructibility): `SwapCarrier`, `SelfSimilarReconstruct`, `PonderBudget`, `OctreeCell.Detail`, `Lineage.GeneTag`, `Trade.GeneId/CreatorId`.

Golden witnesses: `decodeWithBudget (starveHead defaultHead) 1 [200] = [200 x8] = expandRungVolume 1 [200] Nothing = replicate 8 200`, `goldenStarvedHeadIsFloor` PASS. `swapMajorOf (encodeWithBudget defaultHead showcase) = 2` (unchanged by advisory). `expressionSource(base) = FloorExact`, `expressionSource(base of Grant+advisory) = Learned [7 x21]`.

Pure laws: `lawOnlyMaybeForkIsFloorSafe` (all strat x vol x side), `lawBudgetHeadBoundsActualPackets` (heads x caps x sides x vols), `lawBudgetHeadForwardCompatible` (showcase and grant x heads), `lawBudgetAdvisoryDoesNotChangeTagIdentity` (payloads x head-pairs) all PASS.

Existing invariants cross-checked: `SwapCarrier.lawShowcaseIsInert` (showcase and grant), `SelfSimilarReconstruct.lawVolumeExpandFloorConstant` (200,42,0,59999), `PonderBudget.budgetToMask(emptyBudget)` refines nothing, `expandRungVolume 2 (replicate 8 200) Nothing == replicate 64 200` all PASS.

Non-vacuity (5 foils): D1 correct starve = [200 x8], WRONG = [] (reads estimate to size buffer). D2 correct spentCost(cap=2, head wants 100)=2<=cap, WRONG=100>cap. D3 correct `expressionSource(showcase base)=FloorExact`, WRONG=Learned[1] (folded advisory into weights). D4 correct: two advisories share tag identity, WRONG: diverge (advisory leaked into tag). D5 `runStrategy TruncateToEstimate/PreallocEstimate (starve) = [] /= floor`; `MaybeForkOnly = [200 x8] == floor`. Every foil detected. No repair needed: every real cited signature matched the doc anchors (`swapMajor=2`, `expressionSource`, `FloorExact`, `expandRungVolume`, `lawVolumeExpandFloorConstant`, `budgetToMask`).

### 2.6 AnytimeDecode (NEEDS_REPAIR)

Probe: `scratchpad/AnytimeDecodeProbe.hs`. Constructible=PARTIAL, consistent=YES, non-vacuous=YES. The buildable/honest content IS green (25/25 enumerated + 4x100 QuickCheck), but the DOC keystone as written does not compile and its adopted fix is unsound, so the DESIGN needs repair.

Imported and resolved against real modules: `SelfSimilarReconstruct` (`expandRungVolume`, `unliftVec`, `liftVec`, `lawZeroTailIsFloor:213`, `lawVolumeExpandFloorConstant:287`, `lawWithinCaptureExact:180`), `SwapCarrier` (`lawShowcaseIsInert:457`), `PonderHaltDistribution` (`lawExpectedLossIsConvex:71`), `RefinementSystem` (`unliftVec`/`liftVec` prefix-difference lift `:144`), `RefinementCarriers` (`unliftF`/`OctLeaf8 ReversibleLift :112` via `OctreeCell.unliftOct`).

Honest bodies (not stubs): `takeBands`/`dropDetailBeyond`/`floorDecode` are total definitions over real `unliftVec`/`expandRungVolume`. The one honest stub is the Showcase-to-floor bridge `lawShowcaseDecodesToFloor`: the coarse cube is supplied EXTERNALLY because `SwapPayload` (SwapCarrier:135) has no coarse field and the doc's cited helpers `reconstructFloor`/`coarseOf` are exported nowhere. Bound honestly to `expandRungVolume 1 coarse Nothing` (the real Nothing=zero-detail floor path) and to the real `expressionSource == FloorExact` (delegating `lawShowcaseIsInert`), not a rigged reflexive equation. No UNBUILT component (learned budget head, Swift null-on-fault caller, 256->64 collapse) was stubbed.

Golden witnesses that ran: (A) golden(1) `unliftVec(100,[5,-3,7]) == [100,105,102,109]`; `take3 full == unliftVec(100,[5,-3]) == [100,105,102]`. golden(2) `expandRungVolume 2 (replicate 8 30000) Nothing == replicate 64 30000`. golden(3) Showcase expresses FloorExact, floor decode == `floorDecode [42]` (nearest-neighbour). golden(4) `badRenorm(100,[5,-3,7]) == [-9,-4,-7,0]`; at k=2 `badRenorm(100,[5,-3])==[-2,3,0] /= take 3 full == [-9,-4,-7]`. (B) non-vacuity: correct `lawDecodeIsAnytime` holds at k=0..3, badRenorm VIOLATES the anytime predicate at k in [0,1,2] (keystone rejects it), same inputs `unliftVec` satisfies it. (C) 14 must-not-break existing invariants PASS (`lawZeroTailIsFloor` on [0..7] and map(*13)[0..7], `lawShowcaseIsInert`, `lawVolumeExpandFloorConstant` at 30000 and 7, `lawWithinCaptureExact` delegated as `lawHeldRungHaltsExact` at d=1 k=0, d=1 k=1, d=2 k=1, `lawExpectedLossIsConvex` delegated as `lawAnyRungLossBounded` samples A/B, floor totality on padding). QuickCheck 4x100 OK. SUMMARY: 25/25 enumerated checks passed.

Design check (D): `unliftF full = OctLeaf8 (V8 16 17 9 17 6 5 11 4)`, `unliftF k=1 = OctLeaf8 (V8 12 12 9 9 10 10 10 10)`; the octant re-target holds over k=0..6 = **False** (FALSE means the doc's keystone re-target is UNSOUND; scheme-1 `unliftVec` is the honest carrier).

**Exact defects and the required design fix:**

1. KEYSTONE TYPE-BROKEN. Doc §3.1 keystone `lawDecodeIsAnytime :: OctLeaf -> Int -> Bool` with `unliftF leaf`: (a) no `OctLeaf` type exists, the carrier is `OctLeaf8` (RefinementCarriers:92); (b) the real signature is `unliftF :: (Integer,[Integer]) -> f` (RefinementSystem:134), i.e. it consumes a (coarse,detail) PAIR and returns the leaf, so `unliftF leaf` is a type error (wrong direction and arity); (c) `takeBands` and `dropDetailBeyond` are doc-invented, exported by no module.

2. THE ADOPTED FIX IS FALSE. §3.1 "Keystone (fixed, adopted)" claims the repair is to re-target the keystone at the class method actually on the decode path (`unliftF`/`unliftOct`) so a non-additive override genuinely flips it. But `unliftOct` (OctreeCell:122, the shipped averaging octant inverse) is ITSELF non-additive: it reads the whole detail tail to form every output lane. Section (D) on the real export shows `unliftF(10,[3,-5,7,-2,4,-6,8]) = V8 16 17 9 17 6 5 11 4` while `unliftF(10,[3]) = V8 12 12 9 9 10 10 10 10`; even lane 0 differs (16 vs 12), so the k=1 prefix already breaks. The re-targeted keystone therefore FAILS on the SHIPPED decoder, not merely on a hypothetical override. The doc contradicts itself: it demotes the correct `unliftVec` carrier to a lemma (`lawVecPrefixOptimal`) while promoting a predicate that is false for the real decode path.

3. `lawShowcaseDecodesToFloor` cites `reconstructFloor` and `coarseOf` (neither exported); `SwapPayload` carries no coarse cube, so the equation as drafted cannot be stated over the type. The honest external-coarse form works and was proven.

**Repair required before landing:** keep `lawDecodeIsAnytime` targeted at `unliftVec` (scheme 1) with signature `(Integer,[Integer]) -> Int -> Bool`; keep the scheme-2 octant decode OUT of the anytime prefix claim (its anytime property is the rung-ladder / floor totality via `expandRungVolume Nothing`, which IS proven here, not sub-band truncation); replace `reconstructFloor`/`coarseOf` with `expandRungVolume`-based floor plus an externally supplied coarse cube.

---

## 3. CROSS-LAW CONSISTENCY

Combined probe: `scratchpad/SixLawsAgreementProbe.hs`. Run: `cd /Users/daniel/SixFour/spec && cabal exec -- runghc -XDataKinds -isrc SixLawsAgreementProbe.hs`. CO-COMPILATION plus all four interaction checks PASS (verified re-run 2026-07-02: 4/4 interactions, 11/11 invariants). The six laws do NOT disagree.

**(1) Co-compilation: PASS.** All six honest law bodies, copied verbatim from the per-law probes, co-exist in ONE module linked against the REAL `spec/src` signatures. Three name collisions surfaced and were resolved by RENAME, not semantic change: Descriptor's `floorGene::[Double]->[Double]` renamed `floorRep` (collided with PacketEconomy's `floorGene::Gene`); the three per-probe `sh = defaultPredictorShape` unified to one; the per-probe `check` drivers unified to one `String -> Bool -> IO Bool`. No type/kind conflict across the 22 imported spec modules. Each keystone evaluated once and holds. The file typechecking and linking IS the co-compilation proof.

**(2) Interaction scenarios: 4/4 AGREE.**

2A. Recombined child (GeneRecombination) fed to DescriptorQuasiIsometry: PASS. Midpoint child of pa=[65536,32768,16384,...] and pb=0 has payload head [32768,16384,8192]; dq(child,pa)=dq(child,pb)=401408, dc=2215360; the two-sided QI bound holds against BOTH parents (large-magnitude Q16 genes well outside the [-100,100] words the Descriptor probe enumerated, a genuinely new stress point). Kernel dq=0 iff dc=0 consistent; keystone separates (byte-novel blend is not Q16-collapsed, lineage-distinct, grantable). Endpoint lambda=0 recovers pa exactly (dq=dc=0), so the two laws' kernels agree.

2B. Admitted gene -> BudgetHead advisory -> AnytimeDecode floor: PASS, after a corrected test. gGood is admitted (meaning=2064384>0). BudgetHead starve routes through the sole Maybe fork so the halted decode == `expandRungVolume Nothing` floor (valid, length 64). Finding on "meaning monotone on held rungs": the first construction measured meaning over a tail-zero-padded FULL-length buffer and produced a NON-monotone ladder [0,14,11,21,23] (dip at k=2). That is NOT a law disagreement, it is the WRONG decoder. AnytimeDecode's actual certificate (`lawDecodeIsAnytime`) is a PREFIX property: k+1 bands are byte-exact and never revised; the tail-hold buffer revises unfinalised tail positions, which no law claims monotone. Measured correctly on the HELD (byte-exact) prefix, the meaning ladder is [0,5,7,16,23], strictly monotone non-decreasing, k=0 floor gives meaning 0, top realises positive meaning. Both laws agree exactly on the held-prefix reading.

2C. BudgetHead advisory is tag-adjacent vs GeneHash/GeneSimilarity identity: PASS. Two advisories over one base yield identical tag-identity bytes (`lawBudgetAdvisoryDoesNotChangeTagIdentity`); swapMajor and expressionSource preserved (`lawBudgetHeadForwardCompatible`). The advisory is not an input to `recombine`/`geneHash`, so GeneRecombination's lineage grant is untouched (mayGrantChild ledgerBoth=True, ledgerOne=False) and gpParents=[idPa,idPb] stable; Descriptor's dq/dc recompute identically. Non-vacuity: the OR-laundering grant diverges, so the identity check bites.

2D. PaintOrderPrior halting depth vs PacketEconomy packet count: PASS, they are the SAME integer (unification identity, no conflict). For ranks 0..7 the (rank, PaintOrder depth, PacketEconomy packets) rows are (0,7,7),(1,6,6),...,(7,0,0): PaintOrder's `packetsAboveFloor = ceilingRank - r` equals PacketEconomy's `packets (sched n) = n` for every rank. Both cap at the SAME A7 ceiling `ceilingRank = paletteDepth-1 = 7`, which also matches AnytimeDecode's 8-octant floor (`expandRungVolume side=1` has 8 leaves, paletteDepth=8). Order-blind magnitude policy does not swap, confirming the identity is order-carried (non-vacuous).

**(3) Must-not-break: 11/11 HOLD** on the shared interaction inputs: GeneSimilarity `lawGaugeQuotient` / `lawProbeSeparates` / `lawPullbackPseudometric(pa,pb,child)` / `lawFloorIsOrigin`; Q16 `lawTerminalQuantizationIdempotent`; SelfSimilarReconstruct `lawZeroTailIsFloor` / `lawWithinCaptureExact` / `lawVolumeExpandFloorConstant`; SwapCarrier `lawShowcaseIsInert` / `lawGrantOnlyFromSettledTrade`; PonderHaltDistribution `lawLowerHaltRefinesMore` / `lawExpectedLossIsConvex`; PonderBudget `budgetToMask(emptyBudget)`; GeneHash `lawBuiltGenealogyAcyclic`; LedgerCRDT `lawStateHomomorphism` / `lawHoldingsFromState`.

**Disagreements: NONE.** The only initial FAIL was self-inflicted by an over-strong monotonicity hypothesis in the 2B test (tail-hold full buffer), not a contradiction between AnytimeDecode and PacketEconomy; corrected to the held-prefix reading the laws actually certify, and it passes. The six laws co-compile with no type/name conflict and agree on all four interaction scenarios; no per-law invariant is broken by the interactions. Carried caveats: AnytimeDecode stays NEEDS_REPAIR at the DESIGN level (the combined probe uses the honest scheme-1 `unliftVec` prefix carrier, which is exactly what makes 2B's held-rung monotonicity go through); BudgetHead's learned float head stays stubbed, so 2C proves tag-adjacency/identity non-interference for the buildable wire carrier, not the unbuilt estimator's numerics.

---

## 4. LANDING ORDER

Cleared to author into `spec.cabal` / `Spec.Map` NOW (five laws):

1. **DescriptorQuasiIsometry** (FIRST, the floor/gate). Pure over `expressGene`, buildable today, references no `s4_gif_decode` / `s4_gene_express` / trained encoder. Author fixes with it: import `zeroParams` from `DetailPredictor` not `GeneSimilarity`, `toQ16` from `Spec.Q16` not `DetailPredictor`, use `quantizeQ16` for the Double->Int floor, and PIN "dc/dq stated on Q16 floor representatives, never raw fp32 theta". This is the metric every other law's kernel-agreement (2A, 2C) rests on.
2. **PacketEconomy** (SECOND). Depends on the Descriptor metric for `meaning`/`dominates`. Author DEFINES `Schedule`/`Rung` in-module (do not cite SelfSimilarReconstruct:131), and labels the 10/12/20 goldens illustrative integer-algebra vectors OR replaces them with Q16-scaled (multiple-of-1311) values.
3. **PaintOrderPrior** (THIRD, contract-only). Adapt to the real signatures: `lawLowerHaltRefinesMore :: Bool` (nullary), `paintCellPair` arity 4. Keystone is the permutation-pair property; A7 ceiling reconciled at `branching 2 3 - 1 = 7 = paletteDepth-1`.
4. **GeneRecombination** (FOURTH). Re-key off payload bytes onto lineage: `holdsGene led who g = Set.member g (holdings led who)`; define `ParentGene`/`Child`/`BlendWeight`/`idOf`/`recombine`/`mayGrantChild` in-module; adopt `child = (1-lambda).thetaA + lambda.thetaB`; PIN 0x10000 (not 0xFFFF) as the byte-exact top endpoint.
5. **BudgetHead** (FIFTH, PROVEN_MODULO_STUB). Land the wire carrier and the four pure laws now; the learned float estimator stays Tier-1 UNBUILT and does not gate. Every cited real signature already matches, no repair.

Needs a design repair BEFORE authoring (one law):

6. **AnytimeDecode** (the other floor/gate the anytime story references). Repair: re-target `lawDecodeIsAnytime` at `unliftVec` (scheme 1), signature `(Integer,[Integer]) -> Int -> Bool`; keep the scheme-2 octant decode OUT of the prefix claim (its anytime property is rung-ladder / floor totality via `expandRungVolume Nothing`); replace `reconstructFloor`/`coarseOf` with `expandRungVolume`-based floor plus an externally supplied coarse cube. After the re-target its content is already green (25/25 + 4x100).

Dependency order: **AnytimeDecode and DescriptorQuasiIsometry are the floor/gate the others reference.** Descriptor is landable first and unblocks PacketEconomy and GeneRecombination (metric kernels) and the identity checks in 2A/2C. AnytimeDecode's floor totality is what PaintOrderPrior/PacketEconomy's A7 ceiling and BudgetHead's Maybe-fork starve reduce to (2B, 2D), so it should land immediately after its one-symbol re-target, in parallel with authoring the cleared five.

---

## 5. REPRODUCE

Harness (per-law, from `/Users/daniel/SixFour/spec`):

```
cd /Users/daniel/SixFour/spec
cabal exec -- runghc -isrc <probe.hs>
```

GHC 9.2.8. The per-law probes run as-is. The combined probe transitively imports `Shape.hs`, which uses the spec.cabal default-extension `DataKinds` (the package's ONLY default-extension, not 18), so it must be passed on the CLI: `cabal exec -- runghc -XDataKinds -isrc SixLawsAgreementProbe.hs`. VERIFIED re-run 2026-07-02: combined probe co-compiles, 4/4 interactions agree, 11/11 invariants hold. Probe file paths:

- AnytimeDecode: `/private/tmp/claude-501/-Users-daniel/e58f41e6-4db0-4fe3-aadf-06901e2831fa/scratchpad/AnytimeDecodeProbe.hs`
- PacketEconomy: `/private/tmp/claude-501/-Users-daniel/e58f41e6-4db0-4fe3-aadf-06901e2831fa/scratchpad/PacketEconomyProbe.hs`
- BudgetHead: `/private/tmp/claude-501/-Users-daniel/e58f41e6-4db0-4fe3-aadf-06901e2831fa/scratchpad/BudgetHeadProbe.hs`
- DescriptorQuasiIsometry: `/private/tmp/claude-501/-Users-daniel/e58f41e6-4db0-4fe3-aadf-06901e2831fa/scratchpad/DescriptorQuasiIsometryProbe.hs`
- PaintOrderPrior: `/private/tmp/claude-501/-Users-daniel/e58f41e6-4db0-4fe3-aadf-06901e2831fa/scratchpad/PaintOrderPriorProbe.hs`
- GeneRecombination: `/private/tmp/claude-501/-Users-daniel/e58f41e6-4db0-4fe3-aadf-06901e2831fa/scratchpad/GeneRecombinationProbe.hs`
- Cross-law (co-compilation + interactions): `/private/tmp/claude-501/-Users-daniel/e58f41e6-4db0-4fe3-aadf-06901e2831fa/scratchpad/SixLawsAgreementProbe.hs`

Re-run any single law by pointing runghc at its probe; re-run the whole consistency argument via the combined probe with `-XDataKinds`.

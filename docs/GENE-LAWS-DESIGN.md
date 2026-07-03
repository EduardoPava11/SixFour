# GENE LAWS: DESIGN OF RECORD

2026-07-02. Three spec laws that turn the GeneAtlas from a recorded set into a governed one, each synthesised from a design pass plus an adversarial critique, and grounded in four web reports on how a small on-device CNN encoder is actually built. VERDICT UP FRONT: **author `DescriptorQuasiIsometry` first** (it is pure over `expressGene`, buildable today, needs no `s4_gif_decode`/`s4_gene_express`/trained encoder, and only requires re-designating its real keystone), **`GeneRecombination` second** (its keystone is UNSOUND as designed and must be re-keyed from payload bytes to lineage before it can gate), **`PaintOrderPrior` last** (contract-only, but its keystone must be rebuilt as a permutation-pair property and its A₇ ceiling reconciled with real 16³ nudge sessions). None of the three is landable as first drafted; each critique's fix is folded into the plan below. Spec laws first, per the house pattern: law, Zig/Swift port, golden gate. This doc pairs with `docs/GENE-ARCHIVE-PLAN.md` (the archive skeleton these laws govern) and starts, as always, at `SixFour.Spec.Map`.

Anchors below are carried from the design/critique passes and the four reports; every one was grep-confirmed against the tree (`GeneSimilarity.hs:138` `geneDistance`, `:154` `lawPullbackPseudometric`, `:168` `lawGaugeQuotient`, `:201` `lawProbeSeparates`; `DetailPredictor.hs:89` `defaultPredictorShape`, `:126` `rawBands`; `PonderHaltDistribution.hs:46` `expectedSteps`, `:51` `geometricPrior`, `:96` `lawLowerHaltRefinesMore`; `CellNudge.hs:48` `type CellBudget = [[Int]]`; `RelationalMemory.hs:44` `d6`).

---

## 1. CNN ENCODER CONSTRUCTION PRIMER

The "so we can model properly" deliverable: the exact recipe for a small, on-device, integer, distance-respecting, JEPA-style CNN encoder, distilled from the four reports (encoder-anatomy, metric-embeddings, jepa-halting, integer-recombine). Each step is tagged HAVE (SixFour already has it), NEED (must build), or DECISION (owner choice pending). The learned object that would replace or ride atop `expressGene`/`predictDetail` is exactly this encoder; its admissibility gates are the three laws in §2.

**Step 0, fix the encoder boundary (where the embedding lives).** An encoder is `x → stem → [stage_i] → global-pool → z`; everything up to and including the global pool is the encoder, everything after is a task head. For contrastive/representation training you keep the pre-projection feature `h`, NOT the projected `z`: the projection head is trained to be augmentation-invariant and discards downstream-useful information, and `h` is >10% better downstream [SimCLR; encoder-anatomy §3]. SixFour analogue: the descriptor `geneDistance` cloud IS `h`; the archive cell is a quantised `z`. HAVE (the `expressGene` 63-point cloud is `h`, `GeneSimilarity.hs:122`); DECISION (delimit the encoder at the cloud, never at the cell, so distortion is measured pre-quantisation).

**Step 1, stem and width schedule.** Aggressive early downsample (ResNet 7×7/s2 + maxpool → /4; ConvNeXt 4×4/s4 patchify → /4), then geometric channel doubling per stage (C, 2C, 4C, 8C) so per-stage FLOPs stay balanced as HW quarters [encoder-anatomy §1-2]. Small templates: MobileNetV3-Large (~5.5M params, inverted-residual MBConv + SE ratio 4, hard-swish), EfficientNet-B0 (~5.3M, compound scaling α=1.2/β=1.1/γ=1.15), ConvNeXt-T (depths [3,3,9,3], dims [96,192,384,768]) [encoder-anatomy §2]. SixFour is far smaller (theta_B is 63 params, the up-rung nets 21p-6K per `project_sixfour_v3_ondevice_training`). NEED (a stem/stage schedule if the descriptor is ever learned rather than the linear `rawBands` head); today the "encoder" is the fixed reversible lift + linear θ head, so the schedule is trivially one layer. DECISION (owner: does the learned descriptor stay linear, keeping the no-permutation-symmetry gift of §2.3, or go multi-stage and pay Git-Re-Basin alignment).

**Step 2, make it integer and deterministic (the load-bearing on-device step).** FP conv on GPU is non-associative: `(a+b)+c ≠ a+(b+c)`, and warp-scheduler-order reductions drift run to run [integer-recombine §1; NVIDIA CCCL]. The strongest fix is a pure-integer MAC path: int32-accumulator convolution is bit-exact regardless of order because integer add IS associative. Q16 fixed-point with power-of-two scales makes requantise an arithmetic shift, no float divide [integer-recombine §1; Jacob et al. gemmlowp]. This is why SixFour's goldens are total, not tolerance-based, and it is the same discipline as the byte floor. HAVE (the Zig Q16 floor, `reenterQ16 = ByteCarrier.hs:92`, power-of-two = units in the Z[1/2] module discipline); NEED (an actual MPSGraph int-accumulator conv if the descriptor is learned; Apple does not document a float-conv order guarantee, so build integer-only or write the reduction kernel with a fixed tree order, `integer-recombine §1`).

**Step 3, enforce two-sided distance preservation (bi-Lipschitz / quasi-isometry).** An encoder "respects distance" iff `L₁·d_X(a,b) ≤ d_Z(f a, f b) ≤ L₂·d_X(a,b)`, distortion κ = L₂/L₁ ≥ 1, κ=1 an isometry; the additive quasi-isometry form allows slack `c` [metric-embeddings §0; SNGP JMLR 22-0479]. The upper bound (no blow-up) is cheap: spectral normalisation `W ← W/σ_max(W)` makes each layer 1-Lipschitz, composition bounds the net, but it gives ONLY the upper bound and the constant is loose [metric-embeddings §2a; Anil 1811.05381]. The lower bound (no collapse) is the hard, falsifiable half; SNGP recovers it by adding a residual connection so the map stays near identity, invertible flows get both bounds in closed form (κ ≤ ((1+L)/(1−L))^m), and isometric AEs regularise the Jacobian JᵀJ toward a constant-scaled orthonormal frame [metric-embeddings §2b-2c]. HARD LIMIT (Nash): exact isometry of a k-dim manifold needs O(k²) latent dims, so target BOUNDED κ, never κ=1, when compressing [metric-embeddings §2c]. This whole step IS law `DescriptorQuasiIsometry` (§2.1): NEED, but the acceptance test is buildable today over the fixed head.

**Step 4, respect distance under quantisation (the collapse alarm).** Discretisation threatens the lower bound: nearest-code assignment is piecewise-constant, so injectivity survives only between cells. VQ-VAE suffers codebook collapse (a fraction of codes used, entropy → 0, many distinct inputs → one code = a direct L₁-violation), caused by encoder drift outrunning sparse code updates [metric-embeddings §3; NSVQ]. Prefer a fixed lattice (FSQ/scalar quant) or product quantisation over plain VQ, and ALWAYS log codebook usage entropy as a collapse alarm [metric-embeddings §3, §4]. SixFour analogue: the archive cell IS a quantiser; `lawCellFunctionDeterministic`/`lawBinEdgesPinned` (`GENE-ARCHIVE-PLAN.md:§6`) pin the lattice; `DescriptorQuasiIsometry`'s lower-separation half IS the anti-codebook-collapse guarantee stated on floor representatives. HAVE (integer bin edges, coverage-monotone merge); NEED (the lower-bound law that says floor-distinct genes cannot share a cell).

**Step 5, the JEPA read-out and halting (compute allocation).** I-JEPA is asymmetric: a context encoder sees a large visible block, a target encoder sees the full image and is masked AFTER encoding (targets stay semantic), a deliberately narrow predictor (dim 384, an information bottleneck that is itself an anti-collapse mechanism) maps context→target in embedding space; loss = L2 distance in embedding space, and the energy IS that prediction error [jepa-halting §1-2; I-JEPA CVPR 2023]. Collapse is avoided by EMA + stop-grad OR by regularisers (VICReg/SIGReg) that shrink the low-energy volume; SixFour's stance is the frozen data-manufactured target (`EncoderFrozen`, the reversible lift as tokenizer), which removes the collapse symmetry structurally [jepa-halting §1; `CLAUDE.md` I-JEPA redirect]. PonderNet halting: per step λ_n = σ(linear(h_n)), stop-distribution p_n = λ_n∏_{j<n}(1−λ_j), reconstruction loss Σ p_n L(y,ŷ_n), KL pull to a geometric prior Pr_G(k) = (1−λ_p)^k λ_p biasing expected depth to 1/λ_p [jepa-halting §3; PonderNet]. SACT does per-region halting; the cleanest way to inject a user prior is the PRIOR side (make λ_p region-dependent), not the logit [jepa-halting §4]. This whole step IS law `PaintOrderPrior` (§2.2). HAVE (`geometricPrior`, `expectedSteps`, `HaltDist`, `lawLowerHaltRefinesMore`; the frozen tokenizer); NEED (the paint-order carrier and the per-region prior).

**Five-bullet summary.** (1) Encoder = stem → doubling stages → global pool → keep the pre-projection feature `h`, not the projected `z`. (2) Make it integer: int32-accumulator MACs + Q16 power-of-two scales = bit-exact regardless of GPU order (SixFour already lives here). (3) Two-sided distance: spectral-norm the upper bound cheaply, earn the lower bound via residual/near-identity or a Jacobian-isometry regulariser, target bounded κ not κ=1 (Nash). (4) Quantise onto a fixed lattice not a drifting VQ codebook, and monitor code entropy as the collapse alarm. (5) JEPA read-out = embedding-distance energy with a frozen data-manufactured target; PonderNet halting with per-region prior injection is the compute-allocation surface a paint UI drives.

---

## 2. THE THREE LAWS

### 2.1 `SixFour.Spec.DescriptorQuasiIsometry`

**Module home.** New module, `DisplaySide` compartment (tag next to `GeneSimilarity`/`CrossEncoderDistance` in `Spec.Map` §"the two semantics"). Imports `GeneSimilarity` (`expressGene`, `geneDistance:138`, `canonicalProbe:100`, `zeroParams`), `DetailPredictor` (`rawBands:126` linear-in-θ, `defaultPredictorShape:89`, `toQ16`), `CrossEncoderDistance` (`cloudDistance:77`), `RelationalMemory` (`d6:44`, the faithful metric), `CoarseIsPalette` (isometry boundary). Haddock cites SNGP κ=L₂/L₁ (JMLR 22-0479) and the additive quasi-isometry form.

**Purpose.** Promote `geneDistance` (a pullback pseudometric with only one-sided/one-witness facts today: `lawPullbackPseudometric:154`, single-gene `lawProbeSeparates:201`) to a genuine two-sided additive quasi-isometry between θ-gene space and the P6 archive cloud. This is the admissibility gate for a learned CNN/MPSGraph encoder standing in for `expressGene`: legal iff it neither collapses (distinct floor-representatives → distance 0, the VQ codebook-collapse / lower-bound violation) nor is discontinuous (a 1-LSB θ step → unbounded cell jump, the missing spectral-norm upper bound). It honestly quotients the gauge kernel that `lawGaugeQuotient:168` proves nonempty by stating the lower bound on Q16 floor representatives, never raw fp32 θ.

**Keystone (as first designed).**
```haskell
-- Additive quasi-isometry: c1*dq - slack <= geneDistance <= c2*dq,
-- dq = L1 distance between Q16 FLOOR REPRESENTATIVES (gauge-quotiented). All integer.
lawDescriptorIsQuasiIsometry :: PredictorShape -> [Double] -> [Double] -> Bool
lawDescriptorIsQuasiIsometry sh a b =
  let dq = thetaFloorDist sh a b     -- Q16-quotient gene metric, Int
      dc = geneDistance   sh a b     -- descriptor pullback distance, Int
  in  loNum*dq - loDen*slack <= loDen*dc   -- LOWER: no collapse (c1 = loNum/loDen)
   && dc*hiDen              <= hiNum*dq    -- UPPER: no discontinuity (c2 = hiNum/hiDen)

thetaFloorDist :: PredictorShape -> [Double] -> [Double] -> Int  -- L1 over toQ16-quantized words
loNum, loDen, hiNum, hiDen, slack :: Int                         -- pinned golden constants
```

**What it forbids.** Collapse: two genes whose Q16 representatives differ (`dq>0`) cannot both land in one archive cell (`dc=0`) beyond `slack/c1` steps. Discontinuity: `c2 < ∞` caps expansion so a small `dq` cannot produce a large `dc` jump. κ = c2/c1 is the distortion (SNGP). This is the only place in `spec/` asserting a REVERSE inter-metric inequality (today only `MetricLattice.lawLInfBoundedByL1:82` goes one way).

**Supporting laws.** `lawDescriptorUpperLipschitz` (non-expansion, spectral-norm analogue), `lawDescriptorLowerSeparation` (floor-distinct genes archive-separated, anti-collapse), `lawProbeDesignSeparatesBands` (the soundness root: two band-weight vectors agreeing on all 9 probes are Q16-equal = the Vandermonde full-rank / σ_min>0 proof that c1>0, byte-exact), `lawFloorKernelIsGaugeKernel` (`thetaFloorDist a b == 0 ⇔` shared Q16 representative = honest quotient), `lawDistortionIsOneAtAnalysis` (κ→1 at the scale where the encoders coincide).

**The failure it forbids, sharpened.** Codebook collapse of the learned descriptor (metric-embeddings §3): an encoder that memorises the single `lawProbeSeparates` witness while collapsing elsewhere. The universal (all-pairs) form retires that single-witness weakness, PROVIDED the generator samples `dq > slack/c1` (see the fix; near-floor generation is vacuous).

**Critic verdict: SOUND-WITH-FIXES. Fix folded in.** The critique's sharpest objection is vacuity → keystone demotion: the additive lower bound is trivially true for every pair with `dq ≤ slack·loDen/loNum`, and with `slack=63` that is a whole near-floor neighbourhood carrying ZERO anti-collapse content there. All falsifiable content lives in `lawProbeDesignSeparatesBands` (the integer Gram-det / σ_min>0 claim), so the advertised keystone is a corollary of a supporting lemma, and the collapse golden is a single pinned witness an encoder can match while collapsing at large `dq`. THE FIX (adopted): (1) re-designate `lawProbeDesignSeparatesBands` as the real Tier-0 keystone; the quasi-isometry inequality rides on it as a corollary. (2) Pin `slack < c1·(one representable Q16 step)` as a golden INTEGER inequality so the vacuity region is provably sub-LSB, and set the collapse witness at the minimum-separating `dq` (one LSB above the slack threshold), not an easy large-`dq` pair. (3) Drop the exact `dc==dq` claim from `lawDistortionIsOneAtAnalysis`/golden #6; its cited anchor `CoarseIsPalette.lawCoarsePaletteComparesToPerFrame:193` proves CROSS-encoder distance is zero (A≡B), a different quantity from θ↔cloud distortion, so state κ→1 as bounded distortion (c1=c2 up to the per-point d6 scale), not θ↔cloud identity, and cite a real isometry witness. `lawFloorKernelIsGaugeKernel` is sound but ALSO depends on full rank (rank<3 ⇒ floor kernel ⊊ gauge kernel ⇒ that law false), reinforcing that σ_min>0 is the one load-bearing golden.

**Device realization.** `expressGene`/`predictDetail:130` realised by the MPSGraph integer conv encoder (int32-accumulator MACs → `convolution2D`); associative integer reduction makes the forward pass bit-exact regardless of warp order, which is why the golden is total not tolerance-based [integer-recombine §1]. Single float→byte crossing is `reenterQ16 = ByteCarrier.hs:92`, mirrored by a Zig `s4_*` kernel and the Swift `CaptureGene` path; `thetaFloorDist`'s quantiser is `toQ16` on device. For a learned CNN descriptor the upper bound is enforced constructively by spectral normalisation (σ_max per layer); this law is the acceptance test the merged/offspring blob must pass (cf. QA-IBP: certify the quantised net directly, `integer-recombine §2`).

**Golden vectors.** (1) Design matrix Φ (9×3 per band) with integer Gram determinant / σ_min>0 (proves the new keystone; a degenerate probe set must make this FAIL). (2) Constants `loNum,loDen,hiNum,hiDen,slack` with the pinned integer inequality `slack < c1·step`. (3) Collapse witness at minimum-separating `dq` (one LSB above threshold), pinned `dc ≥ (loNum·dq − loDen·slack)/loDen`. (4) Discontinuity witness, unit-LSB θ step, `dc ≤ hiNum·dq/hiDen`. (5) Gauge witness (`lawGaugeQuotient` sub-quantum θ, all words 1e-12): `dq==0 ∧ dc==0`. (6) Isometry point restated as bounded κ→1, NOT `dc==dq`.

**Single biggest soundness risk.** The lower constant c1, resting entirely on `canonicalProbe` giving a full-rank, well-conditioned Vandermonde whose σ_min exceeds the Q16 step; if not, near-floor genes are separated by less than one LSB, `slack` swallows the signal, and `lawDescriptorLowerSeparation` is vacuously true while real collapse hides. Mitigation: `lawProbeDesignSeparatesBands` pins σ_min(Φ) as a golden integer bound, `slack` is provably < c1·(one representable step), and NO descriptor coordinate routes through the negative `gaussianColorEntropy` (`EncoderModalityLoad.hs:129`, −9.559 nats); route only through `d6`/the ≥0 `ridgedColorRateBits`.

---

### 2.2 `SixFour.Spec.PaintOrderPrior`

**Module home.** New module, `DisplaySide`/`MacTag` (the prior is a training-time KL target, prior-side). Imports `PonderHaltDistribution` (`geometricPrior:51`, `expectedSteps:46`, `HaltDist`, `lawLowerHaltRefinesMore:96`), `CellNudge` (`CellBudget = [[Int]]:48`), `ScaleFiltration` (branching-8 / A₇, `lawOctantBranchingIs8:116`), `PairTree` (`paletteDepth = 8:91`). Haddock states the paint-order → prior → packet chain.

**Purpose.** Bind the user's paint/nudge FIRST-TOUCH order to the PonderNet halting prior on the coarse-to-fine A₇ rung ladder. Today `CellBudget` is magnitude-only with overwrite semantics (`NudgePaintView.swift:67` overwrites by index, no sequence): it records how hard a cell was pushed but discards WHEN it was first touched. This adds one carrier `TouchOrder = [CellIx]` beside `miNudge` and makes the halt rate a monotone function of touch rank: first-touched cell gets the smallest `λ_p`, hence the largest `expectedSteps` = deepest read on the octant spine, hence the most I/K/S compute packets. Paint order enters purely on the prior side (reshape the KL target, not the logit, the cleanest injection point per jepa-halting §4), and the deployed per-cell packet count is a byte-exact integer schedule.

**Keystone (as first designed), SUPERSEDED by the fix.**
```haskell
-- Earlier first-touch => strictly lower halt rate => >= read-depth, byte-exact integer schedule.
lawPaintOrderSeedsHaltingPrior :: TouchOrder -> Bool
```
This single-argument form is REPLACED per the critique (below) with a permutation-pair keystone.

**Keystone (fixed, adopted).**
```haskell
-- The ONLY formulation that structurally forbids a magnitude-only policy:
-- under any permutation pi of the touch order, at FIXED CellBudget, each cell's
-- deployed packet depth tracks its rank under pi (order is genuinely consumed).
lawPaintOrderTracksRankUnderPermutation :: TouchOrder -> Perm -> CellBudget -> Bool
lawPaintOrderTracksRankUnderPermutation order pi bud =
  and [ rankUnder pi order c <= rankUnder pi order c'
          ==> packetsAboveFloor (applyPerm pi order) c
                >= packetsAboveFloor (applyPerm pi order) c'
      | c <- touched order, c' <- touched order ]
   -- strict while both ranks < paletteDepth; >= and never-inverted beyond rank 7 (A7 ceiling).
```

**What it forbids.** A paint-order-blind halting policy: any `haltSeed` assigning the same or reversed threshold to an early- vs late-touched cell, including (a) the current de-facto single-global-`λ_p` policy and (b) a magnitude-only reading where two cells pushed to equal `budget` but touched in different order resolve to the same depth. Because the two orders `[a,b]` and `[b,a]` carry IDENTICAL `CellBudget` magnitudes but must yield SWAPPED depths, no function of the magnitude field alone can satisfy the pair.

**Supporting laws.** `lawHaltSeedMonotoneInTouchRank` (strictly monotone floor-quantised schedule of rank, non-vacuity engine, steps by `seedQuantum`), `lawEarlierTouchReadsDeeper` (composes with `lawLowerHaltRefinesMore:96`: lower λ_p ⇒ ≥ expectedSteps), `lawPacketBudgetConserved` (fixed I/K/S budget: paint order REALLOCATES, never inflates, compute; integer-exact), `lawUnpaintedHaltsAtFloor` (untouched cell: λ_p=1.0 exactly ⇒ depth 1 ⇒ 0 packets, ties `PonderBudget.budgetToMask:58`), `lawPacketCeilingIsA7Rank` (per-cell ceiling = A₇ rank = 7 detail bands above the coarse floor, paletteDepth 8).

**The failure it forbids.** Under the fixed keystone: a magnitude-only policy that cannot distinguish `[a,b]` from `[b,a]`, plus a constant policy that collapses the strict chain. `packetsAboveFloor = readDepth − 1`, ceiling 7 = A₇ rank; the coarse floor read = the reversible I packet (cost 0), each finer rung = one K (pool) or S (invent) packet.

**Critic verdict: SOUND-WITH-FIXES. Fixes folded in.** The critique's sharpest objection is pigeonhole: `packetsAboveFloor ∈ [0,7]` gives only 8 distinguishable depths, but a nudge session over the 16³ Morton grid touches FAR more than 8 cells, so "earlier ⇒ strictly deeper" is IMPOSSIBLE past rank 7. The original keystone survived only via its `>=` conjunct (ties allowed), which is exactly the escape hatch that reintroduces vacuity: on any order longer than 8 the tail is all ties and the surviving strict-`<` chain is just `f(list-position)`, referencing neither `CellBudget` nor a second order, so it forbids only constants, not the magnitude-only policy the module claims to kill. And golden #2's strict `>` contradicts the `>=` keystone beyond rank 7 (mutually unsatisfiable on realistic input). THE FIX (adopted): (1) promote the permutation-pair golden into the keystone (above) so order is structurally consumed; a single-order property cannot. (2) Reconcile the [0,7] ceiling with reality: restrict strictness to `rank < paletteDepth`, state depth as a rank→[0,7] quotient with an explicit order-preserving (never-inverting) tie rule beyond rank 7, and change golden 2 to "strict while both ranks < 8, else `>=` and never inverted" so goldens 2/4/5 stop contradicting the keystone. Non-fatal, checked clean: `EncoderFrozen` intact (prior-side KL, no weights); byte-exact (integer schedule, no non-unit divide); no mint-credit coupling; the unbuilt TouchOrder Swift field is acceptable for a contract-only spec law.

**Device realization.** Swift `NudgePaintView.paint:67` must append first-touch cells to `touchOrder: [Int]` (today discards the sequence); new field beside `nudge` in `SixFourModelInput` (`Generated/SixFourModelIO.swift:57-67`), mirrored into `ModelIO.ModelInput` (`ModelIO.hs:40`). Metal/MPSGraph: per-cell halting is SACT-style per-region λ [jepa-halting §4]; `packetsAboveFloor` = count of detail-band rung kernels (`s4_octant_lift`) invoked for that cell, gated by `budgetToMask:58`; integer packet count ⇒ deterministic int32-accumulator rung invocation [integer-recombine §1].

**Golden vectors.** (1) Permutation witness `[a,b]` vs `[b,a]`, identical `CellBudget` → depths swap (non-vacuity; a magnitude-only policy fails). (2) Two-cell depth, rank-0 vs rank-1, equal magnitude → strict `>` WHILE both ranks < 8. (3) Unpainted floor: cell ∉ order → λ_p==1.0 exactly, 0 packets. (4) Budget conservation: Σ packetsAboveFloor == packetBudget. (5) Ceiling: rank-0 cell → 7, never 8.

**Single biggest soundness risk.** After the fix, the residual risk is the same collision RELOCATED into [0,7] by the ceiling: past rank 7 the tie rule must be provably order-preserving (never inverting), else two orders that differ only in their deep tail become indistinguishable and the permutation keystone is vacuous on the tail. Secondary: the float/integer seam between `expectedSteps` (a `Double`) and `packetsAboveFloor` (integer), define the packet schedule as a byte-exact integer schedule of rank DIRECTLY (mirroring the `geneDistance` int→float→int sandwich, `GeneSimilarity.hs:46-57`), keep `expectedSteps` as the training-time prior, add a bridging law that `round expectedSteps` is order-consistent with the integer schedule (never strictly inverts it). Routing deployment through `round expectedSteps` is unsound at the seam.

---

### 2.3 `SixFour.Spec.GeneRecombination`

**Module home.** New module, `DisplaySide` (same tag as `GeneHash`/`Trade`/`LedgerCRDT`). Imports `GeneHash` (`GenePreimage{gpPayload,gpParents}:79-82`, `geneHash:151`, `lawBuiltGenealogyAcyclic:271`), `DetailPredictor` (`rawBands:126` linear-in-θ, `paramCount==21`, `zeroParams`), `GeneSimilarity` (`expressGene:122`, `geneDistance:138`, `expressedEnergy:143`), `LedgerCRDT` (`grants`, `stateOf:65`, `mergeGrants:131`), `SwapCarrier` (`mayGrant:381`, `mintGrant:388`, `lawShowcaseIsInert:457`).

**Purpose.** Mint the missing OPERATOR the substrate has only recorded so far: a 2-parent crossover taking two Q16 weight blobs to a child `GenePreimage` with `gpParents=[pa,pb]`, extending the acyclic Merkle-DAG. SEXUAL = a per-word convex blend `λ·θA + (1−λ)·θB` over the 21-word theta-up gene, admissible WITHOUT Git-Re-Basin permutation alignment precisely because `rawBands` is LINEAR in θ (`DetailPredictor.hs:126`): a linear head has no hidden-unit permutation symmetry, so both parents already live in one shared basis (the degenerate always-connected case of Linear Mode Connectivity; Git-Re-Basin only bites on the deeper up-rung 6K nets, `integer-recombine §3`). BALANCED = recombination grows genealogy but is credit-neutral: the child rides its parents' existing grants and adds nothing to the `LedgerCRDT` G-Set. Credit is created ONLY at `mintGrant` off a settled trade (`SwapCarrier.hs:388`), never at a crossover.

**Keystone (as first designed), UNSOUND, must be re-keyed.**
```haskell
lawMintCreditConservedUnderCrossover
  :: LedgerCRDT -> GeneId -> ParentGene -> ParentGene -> BlendWeight -> Bool
-- (a) no laundering: grantable child forces BOTH parents already grantable to who
-- (b) economic mass conserved: stateOf led' == stateOf led
```

**Keystone (fixed, adopted), re-keyed on lineage.**
```haskell
-- Grantability of a BRED gene is decided by DAG membership the mint actually populates
-- (both parent GeneIds held), NOT by payload-in-holdings (which a byte-novel blend never is).
mayGrantChild :: LedgerCRDT -> GeneId -> Child -> Bool
mayGrantChild led who child =
     holdsGene led who (gpParents child !! 0)
  && holdsGene led who (gpParents child !! 1)   -- total over the unordered mate-pair

lawChildGrantableIffBothParentsHeld :: LedgerCRDT -> GeneId -> ParentGene -> ParentGene -> Bool
lawChildGrantableIffBothParentsHeld led who pa pb =
  let child = recombine defaultPredictorShape halfLambda pa pb
  in  mayGrantChild led who child
        == (holdsGene led who (idOf pa) && holdsGene led who (idOf pb))
-- clause (b) demoted to a mintChild-signature obligation: the constructor's return type
-- excludes the grant fold (a smoke check, never the keystone).
```

**What it forbids.** Minting a child that becomes tradeable to `who` without `who` holding BOTH mates (credit laundering through the DAG), and inserting any new grant into the CvRDT G-Set (`stateOf = Set.fromList . concatMap grants`, `LedgerCRDT.hs:65`). The child's economic identity lives in `gpParents` (the DAG the mint populates), which the grant fold now consults; the obvious-wrong `mintChild` that grants the child so it can be traded onward inflates the G-Set and is rejected.

**Supporting laws.** `lawCrossoverPreservesShape` (child stays on the 21-word manifold, forbids dimensionality drift), `lawChildParentsAreMates` (`gpParents child == [idOf pa, idOf pb]`, DAG acyclic, forbids self-parent/cycle), `lawExpressedEnergyBoundedByParents` (no energy creation; PER-PROBE-POINT form, see risk), `lawShowcaseChildIsInert` (two zero-weight Showcase parents yield a FloorExact child, reuses `lawShowcaseIsInert`), `lawBlendAtEndpointsIsParent` (λ=0 expresses pa, λ=1 expresses pb on the probe lattice, distance 0).

**The failure it forbids.** After the re-key: a re-labeled single-parent hold conjuring access credit to a bred gene. Because the child commits `[pa,pb]` even when byte-equal to one parent (λ∈{0,1}), single-parent holding cannot grant it, closing the endpoint leak; and the interior is non-vacuous because grantability is DAG membership, not an always-absent payload.

**Critic verdict: UNSOUND (as first designed). Full fix folded in.** The critique's sharpest objection: the original keystone splits into two dead regimes. For λ∈(0,1), `recombine` produces a byte-NOVEL blob never traded, so it is not in `holdings`; `mayGrant led' who (gpPayload child)` is FALSE for every input, making clause (a)'s implication VACUOUSLY true, and clause (b) holds BY CONSTRUCTION because the honest `mintChild` touches only the Merkle-DAG, never the grant fold, so a Bool law over a fixed `mintChild` cannot catch the grant-inserting variant it claims to forbid. For λ∈{0,1}, `λ·θA+(1−λ)·θB` returns a parent's θ BYTE-IDENTICAL, so `mayGrant led who childPayload == mayGrant led who pb`, which is TRUE when `who` holds pb alone; clause (a) then demands `mayGrant … pa` too, which need not hold, so the keystone is provably FALSE at the endpoints, contradicting `lawBlendAtEndpointsIsParent` and failing its own golden #3 → RED gate. So: vacuous where true, false where non-vacuous; the wall between explore and conjure-credit is never erected, because `mayGrant`/`stateOf` key on PAYLOAD-in-holdings but a bred child's economic identity lives in `gpParents`, which those folds never consult. THE FIX (adopted): re-key grantability on LINEAGE (`mayGrantChild` above), demote clause (b) from keystone to a `mintChild`-signature smoke obligation. Non-fatal, checked clean: `EncoderFrozen` intact (θ-up per-capture head, not the field encoder); byte-exact Q16 shift fine; `expressGene`/`predictDetail` built and deterministic; `s4_gene_recombine` is a trivial unbuilt lerp, not a blocker for the LAW.

**Device realization.** Zig `s4_gene_recombine` (new, trivial): a per-word Q16 lerp over 21 words; with a power-of-two λ the blend is byte-exact regardless of order (int accumulators, `integer-recombine §1`). Swift `recombine(parentA:parentB:lambda:)` on `CaptureGene` (extends `CaptureGene.swift`, which owns `ThetaUp` + `lossReduction:30-32`), emitting a child with `gpParents` set. Fitness path ALREADY built: `expressGene` runs `predictDetail` at 9 probes × 7 bands (`GeneSimilarity.hs:122`), the int→float→int sandwich, so `expressedEnergy`/`geneDistance` on an offspring are computable on-device today with no new kernel. `LedgerCRDT` merge is already device-portable (G-Set union), so the demoted clause needs no new object. Metal: none (21-word gene is a CPU vector op; only the up-rung 6K nets would touch MPSGraph, and crossover there is still a host-side blend).

**Golden vectors.** (1) Two pinned parents (diverse `[242,39,231]`-seed vs flat), λ=`0x8000` → child payload byte-exact = per-word midpoint with the fixed rounding rule. (2) `stateOf led' == stateOf led` (set-equality: the mint added zero G-Set elements). (3) `geneDistance child pa == 0` at λ=0, `child pb == 0` at λ=1 (endpoint recovery, now consistent with the re-keyed grant law because lineage still commits `[pa,pb]`). (4) `expressedEnergy child ≤ max(E pa, E pb) + slack` in the PER-PROBE-POINT form. (5) `geneHash child` FNV1a golden (`GeneHash.hs:151`) committing `[pa,pb]` in that order.

**Single biggest soundness risk.** The `reenterQ16` quantisation crossing (`ByteCarrier.hs:92`) inside `expressGene`: `rawBands` is linear in θ so `expressedEnergy` is convex up to the final round-to-byte, but energy is an L¹ SUM over 63 probe points × 7 bands and per-point LSB rounding accumulates, so a `+1 LSB` slack in `lawExpressedEnergyBoundedByParents` is a lie at scale (worst case ~63×7 LSB). Fix: state boundedness PER-PROBE-POINT (true single-LSB slack) and let the summed form carry the honest numPoints-scaled bound. Second-order: `gpParents` order is hash-significant (`GeneHash.hs:74`), so `recombine λ pa pb` and `recombine (1−λ) pb pa` express identically but hash differently; the credit law must treat the unordered mate-pair as one economic event (harmless to the G-Set by idempotence, but pollutes lineage otherwise). Honest gap: a recombined child has NO `lossReduction` until re-expressed against a real burst (`CaptureGene.swift:30`), so offspring arrive fitness-unknown and lineage admissibility, not measured fitness, is the only pre-expression gate.

---

## 3. AUTHORING ORDER + WIRING

**Order and why.**

1. **`DescriptorQuasiIsometry` FIRST.** It is pure over `expressGene`/`predictDetail` on the integer floor, buildable TODAY with zero dependency on `s4_gif_decode`, `s4_gene_express`, a trained encoder, or any wire byte; the CNN/MPSGraph/spectral-norm narrative is future motivation, not a prerequisite. No lock breaks: the honest quotient on `toQ16` representatives dodges `lawGaugeQuotient:168`, and there is no interaction with `EncoderFrozen` or mint-credit conservation. Its critique is the cheapest to discharge (re-designate an already-named lemma as keystone, pin two integer inequalities, drop one over-claimed anchor). It is also the admissibility gate every learned descriptor must eventually pass, so landing it first sets the contract before the encoder exists. Tier-0.

2. **`GeneRecombination` SECOND.** The operator (`recombine`) and the fitness path (`expressGene`) are built, and `LedgerCRDT`/`holdsGene` are spec-side today, so the re-keyed keystone is landable without new device work. It lands second because its first-draft keystone is UNSOUND and must be rewritten (lineage re-key) before it can gate green, a larger edit than the DescriptorQuasiIsometry re-designation, and because it should sit ON TOP of a settled descriptor contract (offspring admissibility references the same `geneDistance` the first law hardens). Tier-0 for the credit-conservation core; the `s4_gene_recombine` Zig lerp is a Tier-1 follow-on, not a gate blocker.

3. **`PaintOrderPrior` LAST.** Contract-only and prior-side (no weights, `EncoderFrozen` intact), so it is Tier-0-gateable in isolation, BUT its keystone must be rebuilt as a permutation-pair property and its A₇ ceiling reconciled with real 16³ sessions before it is non-vacuous, and its device realization depends on an UNBUILT component (the `TouchOrder` Swift field in `NudgePaintView`, plus the `SixFourModelIO.swift` mirror). It also depends on `PonderHaltDistribution` semantics that are themselves contract-only today. Land it once the two data-law modules are settled. Tier-0 for the pure laws; the Swift `touchOrder` field is Tier-1.

**Per-module wiring (the maintenance contract, `CLAUDE.md`).**

- **`DescriptorQuasiIsometry`**: `spec.cabal` exposed-modules `+= SixFour.Spec.DescriptorQuasiIsometry`; `Spec.Map` one-line entry under "the two semantics" category tagged `DisplaySide`, next to `GeneSimilarity`/`CrossEncoderDistance`; `{- | Module / Description -}` header citing SNGP κ=L₂/L₁; `gate-order.txt` inserts its test module AFTER `GeneSimilarity` (it delegates `geneDistance`/`expressGene`) and after `RelationalMemory` (delegates `d6`). Golden module `DescriptorQuasiIsometryGolden` for the design-matrix / constants / witnesses.

- **`GeneRecombination`**: `spec.cabal += SixFour.Spec.GeneRecombination`; `Spec.Map` entry in the swap-economy category (near `SwapCarrier`/`GeneHash`/`LedgerCRDT`) tagged `DisplaySide`; header stating the crossover → genealogy → credit-neutral chain; `gate-order.txt` AFTER `GeneHash`, `LedgerCRDT`, and `SwapCarrier` (it delegates all three), and after `GeneSimilarity` (fitness). Golden `GeneRecombinationGolden`.

- **`PaintOrderPrior`**: `spec.cabal += SixFour.Spec.PaintOrderPrior`; `Spec.Map` entry near `CellNudge`/`PonderHaltDistribution` tagged `DisplaySide`/`MacTag`; header stating the paint-order → prior → packet chain; `gate-order.txt` AFTER `PonderHaltDistribution`, `CellNudge`, `ScaleFiltration`, `PairTree`. Golden `PaintOrderPriorGolden`.

**Tier-0 vs Tier-1 and unbuilt dependencies.**

- Tier-0 (gate before any port ships): DescriptorQuasiIsometry all laws; GeneRecombination credit-conservation + shape/lineage laws; PaintOrderPrior pure permutation/depth laws.
- Tier-1 (follow-on ports, not gate blockers): `s4_gene_recombine` Zig lerp; Swift `recombine` on `CaptureGene`; the `TouchOrder` Swift field + `SixFourModelIO.swift` mirror; a learned MPSGraph descriptor with spectral-norm layers (only if DECISION in §5 goes multi-stage).
- Unbuilt-dependency flags: PaintOrderPrior's device path depends on `NudgePaintView.paint:67` gaining `touchOrder` (does not exist); a LEARNED descriptor for DescriptorQuasiIsometry depends on the unbuilt `Codegen.JepaHead` MLX emitter + int-accumulator conv (Map §"Python/MLX model"); GeneRecombination fitness on RECEIVED genes depends on re-expression against a real burst (no `lossReduction` on the wire, `GENE-ARCHIVE-PLAN.md` C7).

---

## 4. PROPOSED SKELETON (most-ready law)

The most-ready law is `DescriptorQuasiIsometry` (pure, buildable today, cheapest critique fix). Skeleton below folds in the critique fix: `lawProbeDesignSeparatesBands` is the Tier-0 keystone, the quasi-isometry inequality is a corollary, `slack < c1·step` is a pinned integer inequality, the `dc==dq` isometry claim is downgraded to bounded distortion. PROPOSAL, NOT YET WIRED (not in `spec.cabal`, no `Spec.Map` entry, no golden module).

```haskell
{- | PROPOSAL NOT YET WIRED, do not add to spec.cabal / Spec.Map until reviewed.

Module      : SixFour.Spec.DescriptorQuasiIsometry
Description : Promote 'geneDistance' (a pullback pseudometric) to a two-sided ADDITIVE
              QUASI-ISOMETRY between Q16-floor gene space and the P6 archive cloud: the
              admissibility gate a learned CNN/MPSGraph descriptor must pass (no collapse,
              no discontinuity). Lower bound stated on toQ16 floor representatives, honestly
              quotienting the gauge kernel 'lawGaugeQuotient' proves nonempty.
Reference   : SNGP kappa = L2/L1 (JMLR 22-0479); additive quasi-isometry L1*d - c <= d' <= L2*d.
-}
module SixFour.Spec.DescriptorQuasiIsometry
  ( thetaFloorDist
  , loNum, loDen, hiNum, hiDen, slack
  , lawProbeDesignSeparatesBands   -- ★ TIER-0 KEYSTONE (was a supporting lemma; the real theorem)
  , lawDescriptorIsQuasiIsometry   -- corollary that rides on the keystone
  , lawDescriptorUpperLipschitz
  , lawDescriptorLowerSeparation
  , lawFloorKernelIsGaugeKernel
  , lawSlackBelowOneStep           -- ★ the golden integer inequality that de-vacuifies the lower bound
  , lawDistortionBoundedAtAnalysis -- kappa -> 1 as BOUNDED distortion (NOT dc==dq)
  ) where

import SixFour.Spec.GeneSimilarity   (geneDistance, expressGene, canonicalProbe, zeroParams)
import SixFour.Spec.DetailPredictor  (PredictorShape, defaultPredictorShape, rawBands, toQ16)
import SixFour.Spec.CrossEncoderDistance (cloudDistance)
import SixFour.Spec.RelationalMemory (d6)

-- | L1 distance between the Q16 FLOOR REPRESENTATIVES of two genes (gauge-quotiented, integer).
thetaFloorDist :: PredictorShape -> [Double] -> [Double] -> Int
thetaFloorDist = undefined   -- sum |toQ16 a_i - toQ16 b_i| over the 21 words

-- | Pinned golden constants. INVARIANT (lawSlackBelowOneStep): slack*loNum < loDen*oneStep.
loNum, loDen, hiNum, hiDen, slack :: Int
loNum = undefined; loDen = undefined; hiNum = undefined; hiDen = undefined; slack = undefined

-- ★ TIER-0 KEYSTONE: two band-weight vectors agreeing on all 9 canonicalProbe points are
--   Q16-EQUAL. This IS the Vandermonde full-rank / sigma_min>0 proof that c1 > 0, byte-exact.
--   A degenerate (feature-collinear) probe set must make this FALSE.
lawProbeDesignSeparatesBands :: PredictorShape -> [Double] -> [Double] -> Bool
lawProbeDesignSeparatesBands sh a b = undefined
  -- (all-probes-agree sh a b)  ==>  (map toQ16 (rawBandsAll sh a) == map toQ16 (rawBandsAll sh b))

-- Corollary: the additive quasi-isometry, riding on the keystone above.
lawDescriptorIsQuasiIsometry :: PredictorShape -> [Double] -> [Double] -> Bool
lawDescriptorIsQuasiIsometry sh a b = undefined
  -- let dq = thetaFloorDist sh a b; dc = geneDistance sh a b
  -- in  loNum*dq - loDen*slack <= loDen*dc  &&  dc*hiDen <= hiNum*dq

-- Upper half alone (non-expansion / spectral-norm analogue).
lawDescriptorUpperLipschitz :: PredictorShape -> [Double] -> [Double] -> Bool
lawDescriptorUpperLipschitz sh a b = undefined  -- geneDistance sh a b * hiDen <= hiNum * thetaFloorDist sh a b

-- Lower half alone (anti codebook-collapse). Non-vacuous ONLY where dq > slack/c1 (see lawSlackBelowOneStep).
lawDescriptorLowerSeparation :: PredictorShape -> [Double] -> [Double] -> Bool
lawDescriptorLowerSeparation sh a b = undefined  -- loNum * thetaFloorDist sh a b - loDen*slack <= loDen * geneDistance sh a b

-- Honest quotient: the metric's kernel is EXACTLY the sub-quantum gauge kernel.
lawFloorKernelIsGaugeKernel :: PredictorShape -> [Double] -> [Double] -> Bool
lawFloorKernelIsGaugeKernel sh a b = undefined  -- (thetaFloorDist sh a b == 0) == sharesQ16Representative sh a b

-- ★ THE DE-VACUIFYING GOLDEN: the whole additive-slack region is provably sub-LSB.
lawSlackBelowOneStep :: Bool
lawSlackBelowOneStep = undefined  -- slack * loNum < loDen * oneRepresentableQ16Step

-- kappa -> 1 at the analysis scale as BOUNDED distortion (c1 = c2 up to per-point d6 scale),
-- NOT an exact dc==dq identity (that anchor was CrossEncoderDistance-zero, a different quantity).
lawDistortionBoundedAtAnalysis :: PredictorShape -> [Double] -> [Double] -> Bool
lawDistortionBoundedAtAnalysis sh a b = undefined
```

---

## 5. OPEN DECISIONS FOR THE OWNER

1. **Learned descriptor: stay linear or go multi-stage?** A linear `rawBands` head has no hidden-unit permutation symmetry, so crossover (§2.3) and metric bounds are cheap and Git-Re-Basin never bites. A multi-stage CNN buys capacity but reopens permutation alignment and spectral-norm bookkeeping. RECOMMENDED DEFAULT: stay linear until a measured need appears; the three laws are all stated so they degrade gracefully to the linear head, and the encoder-anatomy schedule is documented (§1) for the day the decision flips.

2. **`slack` value for DescriptorQuasiIsometry.** The design proposed `slack = 63` (probe-band point count). The critique proved that is a whole near-floor vacuity neighbourhood. RECOMMENDED DEFAULT: pin `slack` to the SMALLEST value that still absorbs one-LSB rounding per the golden `lawSlackBelowOneStep` (`slack*loNum < loDen*oneStep`), and set the collapse witness at the minimum-separating `dq` one LSB above threshold. Do not carry 63.

3. **PaintOrderPrior tie rule beyond A₇ rank 7.** Real 16³ sessions touch far more than 8 cells, so depth ties past rank 7 are unavoidable. RECOMMENDED DEFAULT: a Morton-order-stable, order-preserving (never-inverting) tie rule, pinned as a golden, so two orders differing only in their deep tail still cannot invert; strictness restricted to `rank < paletteDepth`.

4. **GeneRecombination λ domain.** Free fp32 λ vs power-of-two `BlendWeight`. RECOMMENDED DEFAULT: power-of-two Q16 λ so the lerp is an exact shift and byte-exact regardless of order (the Z[1/2]-units discipline); expose a small pinned set (0x0000, 0x4000, 0x8000, 0xC000, 0xFFFF) for the goldens.

5. **Received-gene fitness gate.** Bred/received offspring arrive with no `lossReduction` (not on the wire, C7). RECOMMENDED DEFAULT: keep the archive plan's `lawReceivedFillsEmptyNeverDisplaces` posture (lineage admissibility, not measured fitness, is the pre-expression gate); re-express against a real burst only when the gene is promoted out of the neutral stash.

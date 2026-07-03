# SCALE-TRANSITION TRAINING: the adjacent-scale relationship is the self-supervised target that gives a residual its meaning

> Status: DESIGN OF RECORD · 2026-07-02 · Owner: SixFour
> Companions: `docs/DESTRUCTIVE-PYRAMID.md`, `docs/GIF-NATIVE-MODEL.md`, `docs/GENE-COMPUTE-ECONOMY.md`, `CLAUDE.md`.
> Spec wins on any disagreement. Anchors are `file:line`, grep-confirmed against the gather reports; PROPOSED laws are named as such and are not anchors. Start any spec browse at `SixFour.Spec.Map`.

---

## 1. THE INSIGHT + VERDICT

The insight, three clauses. (a) A residual is meaningless in isolation: `fine minus predict(coarse)` is a near-zero low-variance band whose numbers say nothing until you know the coarse they were subtracted against. (b) The adjacent-scale relationship 32 to 64 (and 16 to 32) is itself a REAL, measurable object: coarse is a byte-exact octant-pool of fine (`OctreeCell.scalarCollapseLossy:235`), so the pair `(coarse, fine)` is fully observed, and the gap between them is measurable in real terms (byte L1, coded detail bits, d6), never only in an abstract co-trained latent. (c) That relationship IS a self-supervised training target: `predict(coarse) -> fine`, loss against the held real fine band, target manufactured by pooling and never by the predictor. The residual is what the target CONTEXTUALIZES.

**VERDICT: SOUND, and buildable on ~90% existing substrate, but two labels in the drafts were wrong and are corrected here before any law is authored.** This is the training signal that makes the destructive pyramid learnable: the pyramid (`docs/DESTRUCTIVE-PYRAMID.md`) DEFINES the residual `fine minus EXPAND(REDUCE(fine))`; this doc says what SUPERVISES the learned half of that residual and in what metric. It is the scale-axis analog of the temporal policy/value deltas (`ConstructionEncoder.hs:141,149`): one data-manufactured target, compared in a gauge-correct metric, never self-produced. It is SUPERVISED within the capture (pairs `{(16<->32),(32<->64)}`) and INVENTED above 64 (`SelfSimilarReconstruct.lawBeyondCaptureInvented:192`). The residual is `H(fine|coarse)` in the DIRECTIONAL, upper-bound sense (`<=`, never `=`), and conditioning on the coarse genuinely reduces it. The two corrections the critics forced: (1) the coarse-to-fine synthesizer is the coarse-ONLY 21-param head `DetailPredictor`, NOT the masked-infill head `predictMaskedBandPos` (which leaks 6 of 7 true fine bands as input and cannot run as a generator); (2) the loss and the "H(fine|coarse)" claim must be weighted/witnessed by a value-sensitive term (`DetailEntropy.detailEntropyBits`, `MoveSignal.hs:26` band-L1), NOT by `remainderRate`, which is a content-blind dimension count.

---

## 2. THE SUPERVISED PAIR

**Coarse pooled from fine is free ground truth.** The DOWN/analysis pool that produces coarse FROM fine is byte-exact and one pass: `liftOct` (`OctreeCell.hs:114`, `sLift:131` `sLift x y = (y+(x-y) div 2, x-y)`) is the exact 2x2x2 bijection into (1 coarse `ocCoarse`, 7 detail `ocDetail`), inverse `unliftOct:122`, reversibility `lawOctReversible:202`; `scalarCollapseLossy = ocCoarse . liftOct` (`:235`) is the one-level pool; `octantStep:297` pools a whole level EMITTING both the coarse cube and the detail bands in one pass. Full split/replay is `SuccessiveRefinement.split:55` / `refine:64`, bit-exact by `lawRefineRoundTrip:78` and `SelfSimilarReconstruct.lawWithinCaptureExact:180` (`refine . split == id`). Because coarse is deterministically COMPUTED from fine, the pair is fully observed: this is free supervision, the ZSSR / LapSRN regime, not a guess.

**One 64^3 capture yields the full supervised ladder.** The octant lift is 2x/axis and `levelsBetween 64 16 == 2` (`SelfSimilarReconstruct.hs:168`), i.e. two octant levels 16 -> 32 -> 64. One pool of the 64^3 capture gives 32^3; two pools give 16^3. Both adjacent pairs are ground truth:

> **SUPERVISED PAIR SET from one 64^3 capture = { (16^3 <-> 32^3), (32^3 <-> 64^3) }.** Each pair's residual is the held `ocDetail` bands, exact integers, exactly recoverable.

The V2.1 spatial-field twin is identical and byte-exact: `V21Pyramid.poolSpatial:87` block-sums 64x64 -> 16x16 (`lawCoarseIsBlockSumOfFine:139`, transitivity `lawPyramidTransitive:159`), and its honest partner `lawFineNotRecoverableFromCoarse:224` confirms the coarse is real lossy context, so the pair is informative, not redundant.

**The invention boundary above 64 (`lawBeyondCaptureInvented`).** Analysis descends only FROM the 64^3 capture, so nothing above it was ever observed: 64 -> 128 -> 256 detail is not derivable from the coarse alone (two different latent tails give two different 256^3, `SelfSimilarReconstruct.hs:192-201`). The correspondence hierarchy types the tiers: Analysis 16^3 Exact / Pivot 64^3 Lossy / Synthesis 256^3 Invented (`ScaleIndexedCorrespondence.correspondenceAt:60`, `lawCorrespondenceHierarchyMatchesScaleSpine:124`). **The supervision ceiling is exactly the 64^3 capture.** Above it there is no measurable target, only a prior (weight-tied extrapolation); it must be labeled invention, never "measurable", and must NEVER carry a training loss.

**The real metric (d6) and why it beats an abstract latent.** The relationship is measured in real terms three ways, all deterministic integers on the Q16 floor: byte L1 (`PacketEconomy.meaning:57`, floor-relative integer distance), coded detail bits (`DetailEntropy.detailEntropyBits`, zero on a flat octant, positive on a textured one), and d6 (`RelationalMemory.d6:44`, L1 over the 6 integer coords L,a,b,x,y,t; the graded cross-encoder gap is `CrossEncoderDistance.constructionDistortion:82`). A REAL metric matters because the SSL literature pins two failure modes of the alternative: an L2-optimal predictor returns the blurry MEAN of possible fines, a pure co-trained latent invites BYOL-style collapse. d6 sidesteps both: the target is data-manufactured by pooling (not co-evolving, so no collapse symmetry), and d6 is a fixed perceptual distance (not a mean-seeking L2). The one honesty tax: d6 is not byte-equal to the byte floor; it is a bounded relaxation (§4).

---

## 3. THE TRAINING TARGET

**The operator `predict(coarse) -> fine` (CORRECTED).** Two composed pieces, both built:
- FLOOR: `expandRungVolume side vol Nothing` (`SelfSimilarReconstruct.hs:238`), nearest-neighbour up-rung, "invents nothing" (`lawVolumeExpandFloorConstant:287`). Zig oracle `s4_cube_expand_rung` (`kernels.zig:924`, byte-exact, `details==null` fork `:945`).
- LEARNED DETAIL: `DetailPredictor.rawBands:126` = theta_j . phi(v), re-entered to Q16 by `predictDetail:133`, features `phi(v)=[1,v,v^2]` (`:113`), 21 params (7 bands x 3 features). `zeroParams` collapses to the floor by arithmetic (`lawZeroParamsIsFloorArithmetic:198`).

So `predict_theta(coarse) = expandRungVolume side vol (Just (DetailPredictor bands))`. **This uses the coarse-ONLY head `DetailPredictor`, which emits all 7 bands from the coarse value alone.** The critics caught the drafts pointing at `MaskedBandPrediction.predictMaskedBandPos:540`: that head predicts ONE masked band from (coarse + the SIX VISIBLE SIBLING true fine bands + position); as a coarse-to-fine generator it has ZERO fine bands available and would leak 6/7 of the target at prediction time. `lawSiblingContextStrictlyHelps` PROVES the infill head is strictly stronger BECAUSE it sees siblings, which is exactly why it is not the generator. `predictMaskedBandPos` stays a REPRESENTATION-PRETRAINING objective (masked-band infill, an I-JEPA within the octant, carrying the transfer teeth `lawTransferRecoversGapUnderSelfSimilarity:474` / `lawTransferDegradesUnderLawShift:488` and `lawPositionConditioningStrictlyHelps:578`); it is not `predict_theta`.

**Residual, loss, target.** `r = fine minus predict_theta(coarse)`. When `theta = zeroParams`, `r` reduces exactly to the mean-pool residual `ocDetail` (`lawZeroParamsIsFloorArithmetic:198`); the learned head only spends its 21 params where `detailEntropyBits > 0`. Two-term objective, the honest split from the metric verdict:
- STORE / TRAIN byte-exact: `L_byte = ` value-sensitive-weighted `(1/2)(rawBand minus ocDetail)^2` in Q16 (`DetailPredictor.bandLoss:147`), the weight being `detailEntropyBits` or `MoveSignal.hs:26` band-L1. **NOT `remainderRate`** (see §4). Target = the held real `ocDetail` from `refine . split`, taking no theta.
- GRADE (eval only, at first): `L_d6 = constructionDistortion(refine(predict_theta(coarse)), fine)` (`CrossEncoderDistance.hs:82`), reported for cross-scale comparability, gated by the QI bound (§4).

The two-term contradiction the critics flagged is RESOLVED by sequencing: train on `L_byte` alone; d6 is eval/regularizer only until `lawResidualStrictlyDecreasesUnderPredictorUpdate` is green on the byte objective, so the kappa=36 slack can never silently pull theta off the byte-exact target. Target is the real fine, so it is JepaTarget-safe / anti-collapse (§6).

**Per-scale conditioning (`PerScaleWeights`).** One weight-tied core theta is reused on both rungs, justified by `levelsBetween 64 16 == levelsBetween 256 64 == 2` (`DetailPredictor.lawReusesOnBothRungs:258`). Scale is applied by depth-indexed gains `applyPerScale:54` (weights detail bands only, coarse untouched; `neutral:44` is the floor, `lawNeutralIsFloor:63`), strictly richer than tied (`lawPerScaleExceedsTied:78`, `lawTiedSubsumed:72`). At ViT scale, d6 rides as a learnable relative-position bias (`LargeJepaHead.lawBiasLearnsToScale:48`, `lawBiasScalingNeverBypassesQ16`).

**The scale-axis analog of ConstructionEncoder temporal deltas.** On the time axis, `ConstructionEncoder` factors t -> t+1 into two orthogonal data-manufactured targets, `policyDelta:141` (index/motion, palette fixed) and `valueDelta:149` (recolour, index fixed), `lawInterFrameFactorsToPolicyValue:230`, compared in FUSED pixel space not raw palette/index (`lawPaletteIndexGaugeInvariant:250`). The scale axis copies the TEMPLATE exactly: `predict(coarse) -> fine` is one data-manufactured target, the held finer scale is never self-produced, and the comparison is in a gauge-correct metric (d6 / byte L1). Time deltas contextualize a frame against its neighbour; scale residuals contextualize a fine band against its coarse.

---

## 4. RESIDUAL CONTEXT

**The residual is conditioned on the coarse, in position and content.** `predict_theta` is a function of (coarse value, Morton position); swap the coarse and `r` changes. This is the compression identity of the learned-coding literature: the residual is the surprise left after the coarse is known, and conditioning on context never increases the bits. Concretely `H_code(fine | coarse, theta) <= H(fine)`, with the theta-free mean-pool residual `ocDetail` as the achievable ceiling. **State it as `<=`, never `=`:** the exact "bits = H(fine|coarse)" equality holds only under an optimal coder and a fixed quantizer; in practice cross-entropy is an upper bound. The residual is decodable only WITH its coarse (and, once learned, its theta): `decode(r, coarse, theta) = fine`, but `r` alone underdetermines `fine`, two different coarses with the same `r` give two different fines (reuse `unliftOct:122` plus a witness pair). This is why a residual in isolation is meaningless: it is a coordinate in the coarse's null-space, not a standalone value.

**The `remainderRate` correction (critical).** `SuccessiveRefinement.remainderRate` is `sum [7 * length b]` (`:74`, `:75,99`), a total-dimensions-minus-surfaced COUNT. It is identical for a flat cube and a textured one, zero data dependence, invariant to theta and to pixel content. So a `remainderRate`-weighted loss is a global constant scale (uniform weighting), and `lawConditioningReducesResidualEntropy` stated over `remainderRate` would be VACUOUS: a constant cannot decrease under conditioning. The content-dependent witness is `detailEntropyBits` (codes the band VALUES, zero on a flat octant) or `MoveSignal.hs:26` band-L1. Use those in the loss weight and in the entropy law; keep `remainderRate` only as a support-dimension UPPER BOUND, never as `H(fine|coarse)`.

**Byte-exact vs rate-distortion relaxation.** Store and train the residual BYTE-EXACT: the `ocDetail` bands are exact integers, reconstruction is bit-exact (`lawRefineRoundTrip:78`), the single float-to-int door is `reenterQ16` (`ByteCarrier.hs:92`, `lawByteOnlyFromQ16:109`). GRADE the learned predictor in d6, accepting the sanctioned relaxation: `DescriptorQuasiIsometry.lawDescriptorIsQuasiIsometry:162` bounds `c1 . dq minus slack <= dc <= c2 . dq` with pinned `c1=1/2, c2=18, slack=0`, distortion kappa=36 (`:114`), lower/no-collapse half resting on `lawProbeDesignVandermondeFullRank:133` (det=2). TWO honest caveats the critics sharpened: (a) that QI bound is pinned at Analysis scale on FULL descriptors, not on the near-zero low-variance residual band, where the lower half `c1 . dq minus slack` with tiny dq goes to ~0 and does NOT forbid d6 collapsing residuals toward the blurry mean; (b) kappa=36 is loose enough that a d6-trained predictor can wander 36x off the byte optimum. MITIGATION: train `L_byte` as the hard gate, keep d6 eval-only until green, and if d6 is ever promoted to a loss on the band, add a VICReg-style variance floor (the `SharedTargetCrossAgreement` pattern) to block mean-collapse and make d6 admissible on the band.

---

## 5. NEW LAWS

Tier-0 first; all constructible via `runghc -isrc` today unless noted. Each delegates a landed law rather than restating it, so no settled decision reopens. Home: a NEW sibling module `Spec.ScaleTransitionTarget` (§7), NOT an extension of the ~600-line `MaskedBandPrediction`.

| Law (PROPOSED) | Tier | Pins | Critic fix folded in | runghc today? |
|---|---|---|---|---|
| `lawScaleTransitionTargetIsRealFinerScale` | T0 | Target of `predict_theta(coarse)` equals the held `ocDetail`/fine from `refine . split`, theta-free | Delegates `JepaTarget.lawTargetIsDataManufacturedNotEncoded:114`; do not restate | YES, on octant fixtures |
| `lawResidualIsFineMinusPredictedCoarse` | T0 | `r = fine minus predict_theta(coarse)`, and `r == ocDetail` when `theta = zeroParams` | Uses coarse-ONLY `DetailPredictor` (not the leaky infill head); reduces to floor by `lawZeroParamsIsFloorArithmetic:198` | YES, pure arithmetic |
| `lawSupervisedBelowCaptureInventedAbove` | T0 | `{(16<->32),(32<->64)}` byte-exact-recoverable; `64->128->256` invented | Delegates `lawWithinCaptureExact:180` + `lawBeyondCaptureInvented:192`; hard supervision ceiling = 64^3 | YES, boolean partition |
| `lawResidualDecodableOnlyWithCoarse` | T0 | `decode(r, coarse, theta) = fine`; `r` alone underdetermines `fine` | Name requires coarse AND theta (r is theta-versioned, decode-only, never a target) | YES, `unliftOct:122` + witness |
| `lawResidualContextIsCoarseConditioned` | T0 | `predict_theta` is a function of (coarse, position); swapping coarse changes `r` | Extends `lawPositionConditioningStrictlyHelps:578` | YES |
| `lawConditioningReducesResidualEntropy` | T1 | `H_code(fine|coarse,theta) <= H(fine)` | `<=` not `=` (coder-dependent); witnessed by `detailEntropyBits`, NOT `remainderRate` | YES, needs an honest `H(fine)` baseline helper |
| `lawResidualStrictlyDecreasesUnderPredictorUpdate` | T1 | A finite-difference theta step lowers `L_byte` off-floor | Gate for promoting d6 from eval to loss; reuse `DetailPredictor.bandLoss:147` teeth | YES, hand-seeded theta fixture |
| `lawScaleResidualScoredInD6IsQuasiIsometric` | T1 | `L_d6` bounded by kappa . `L_byte` | Delegates `DescriptorQuasiIsometry.lawDescriptorIsQuasiIsometry:162`; state the band-scale caveat explicitly | YES, existing d6/probe harness |
| `lawLearnedSynthesisScaleInvariantUnderConditioning` | T2 | Pure scale-invariance FALSE, recovered under `applyPerScale` + position | Its natural home; compose `lawTransferDegradesUnderLawShift:488` + `PerScaleWeights` + `lawPositionConditioningStrictlyHelps:578` | YES, via transfer fixtures |

`lawLearnedSynthesisScaleInvariantUnderConditioning` is the keystone that MEMORY has carried in prose with no source (grep of `spec/src` is empty); this doc gives it a home. Its content is currently distributed across `PerScaleWeights` + the transfer teeth + `LargeJepaHead.lawBiasLearnsToScale:48`; the law names it as one conjunction.

---

## 6. INTERACTION

**With the destructive pyramid (`docs/DESTRUCTIVE-PYRAMID.md`).** That doc DEFINES the pyramid residual `residual_k = fine minus EXPAND(REDUCE(fine))` and the two modes (lossless integer / lossy under an RD witness). THIS doc supplies the training signal for the LEARNED half of that residual: what supervises the `S`-invent stage per rung, and in what metric. The destructive analysis pool IS `octantStep` / `scalarCollapseLossy`; the banked residual latent IS `r`; the supervised pairs `{(16<->32),(32<->64)}` are exactly the rungs where the pyramid has ground truth. Above 64^3 the pyramid's 128 residual is invented S-detail with no target, matching `lawSupervisedBelowCaptureInventedAbove`.

**With the GIF-native model (`docs/GIF-NATIVE-MODEL.md`).** The decoded octant voxels ARE the fine scale: the tokenizer half (frozen lift `liftOct . featuresB`) manufactures the collapse-proof target, and the learned `S` head is the only weighted object. The scale-transition loss is what trains that `S` head, per-rung, integers-only across the seam. It inherits the GIF-native seam contract: `predict_theta` runs GPU-float, argmax/re-entry snaps back to Q16 (`reenterQ16 ByteCarrier.hs:92`), byte-exactness holds within one pinned reduction order (not a cross-device theorem).

**With the landed laws.**
- `JepaTarget` (`:114/127/142/154`): the target is the held `ocDetail` from `refine . split == id`, takes no theta (`lawTargetFixedUnderPredictorTraining:127`), zero target-encoder params (`lawNoTargetEncoderNoEma:142`), constant predictor strictly off-floor (`lawCollapseIsRejected:154`). New laws DELEGATE, do not restate. The one guard the critics demanded stated explicitly: the persisted `r = fine minus predict_theta(coarse)` is a DECODE ARTIFACT, theta-versioned, and must NEVER become a training target; the instant a stage supervises on stored `r`, theta re-enters the target and JepaTarget collapse-immunity is lost. Anti-collapse holds ONLY within-capture; above 64^3 "fine" is not data and cannot be a JEPA target (`admissibleRolloutSource:91`, `lawConstantOrbitMissesMovedFrame:181`).
- `DescriptorQuasiIsometry`: `L_d6` is graded through the kappa=36 two-sided bound; store byte-exact, grade in the relaxed d6, the only sanctioned departure from byte-exactness (§4).
- `AnytimeDecode`: the residual store is meaningful only in the Exact/Lossy tiers (`correspondenceAt:60`); partial reconstruction stays valid, the floor is always decodable.
- `lawBeyondCaptureInvented` (`SelfSimilarReconstruct.hs:192`): the supervision ceiling; `lawSupervisedBelowCaptureInventedAbove` delegates to it (two latent tails -> two 256^3, `:199`).

---

## 7. BUILD PLAN + OPEN DECISIONS

**Dependency-ordered build.**
1. Mint `Spec.ScaleTransitionTarget` (compartment MLX-MODEL | MacTag); register in `S/Map.hs` scale category (`:158-320`, beside `PerScaleWeights` / `SelfSimilarReconstruct`). Import `OctreeCell.octantDistill:302`, `DetailPredictor` (the coarse-only head), `CrossEncoderDistance.constructionDistortion:82`, `DetailEntropy.detailEntropyBits`, `JepaTarget`.
2. Land the T0 quartet (`...IsRealFinerScale`, `ResidualIsFineMinusPredictedCoarse`, `SupervisedBelowCaptureInventedAbove`, `ResidualDecodableOnlyWithCoarse`, `ResidualContextIsCoarseConditioned`) as pure runghc laws delegating JepaTarget + `lawBeyondCaptureInvented`. Gate green.
3. Define the stored learned residual `r` keyed by (coarse, position), theta-versioned, decode-only. Land T1 `lawResidualStrictlyDecreasesUnderPredictorUpdate` on `L_byte`.
4. Land T1 `lawConditioningReducesResidualEntropy` (`<=`, add the `H(fine)` baseline helper, witness `detailEntropyBits`) and `lawScaleResidualScoredInD6IsQuasiIsometric` (delegate `DescriptorQuasiIsometry`).
5. State T2 `lawLearnedSynthesisScaleInvariantUnderConditioning` here (its natural home).
6. Codegen/port the residual + forward to Swift (mirror `MaskedBandForward.swift`); byte-golden the CPU-int pool/split against `s4_cube_expand_rung`. NOTE (critic fix): the Zig golden equivalence is against `predict_theta` (the committed `Just ds` re-entered), NOT the theta-free floor path.
7. Trainer loop: feed one 64^3 capture -> `octantStep` yields `{(16<->32),(32<->64)}` supervised pairs -> train theta on `L_byte`, eval `L_d6`; discharge the CONTRACT-ONLY status at `JepaTarget.hs:178`. One capture = the full supervised ladder.

**Open decisions for the owner (each with a recommended default).**

| Decision | Options | RECOMMENDED DEFAULT |
|---|---|---|
| Byte-exact vs lossy residual | (a) byte-exact store only; (b) lossy quantized residual under an RD witness | (a) byte-exact first. Lossy is gated behind the `docs/DESTRUCTIVE-PYRAMID.md` rate witness (must BUY rate, not merely accept loss); do not relax until a measured number beats LZW-on-source at fixed distortion. |
| Training scope: 1 channel vs 6 | (a) channel-0 (L) only, matching today's `CaptureGene.ThetaUp` which trains L only; (b) all 6 P6 coords (L,a,b,x,y,t) | (a) 1-channel (L) first. The backward realizer is real only for channel 0; expand to 6 once the loop is green on L, so the training identity is not aspirational ahead of the realizer. |
| Loss weight term | (a) `detailEntropyBits`; (b) `MoveSignal` band-L1; (c) `remainderRate` | (a) `detailEntropyBits`. Content-sensitive, zero on flat octants. Explicitly NOT `remainderRate` (content-blind count). |
| Operator head | (a) coarse-only `DetailPredictor` (21p); (b) autoregressive teacher-forced 7-band with the leak proven closed | (a) `DetailPredictor`. The infill head `predictMaskedBandPos` stays representation-pretraining only, never `predict_theta`, until a leak-closed AR order exists. |
| d6 role | (a) eval/regularizer only; (b) a loss term with a variance floor | (a) eval-only until `lawResidualStrictlyDecreasesUnderPredictorUpdate` is green on `L_byte`; promote to (b) only with a VICReg-style variance floor to block mean-collapse on the near-zero band. |
| Module home | (a) new `Spec.ScaleTransitionTarget`; (b) extend `MaskedBandPrediction` | (a) new sibling module; the alternative overloads a module already at ~600 lines. |

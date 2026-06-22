{- |
Module      : SixFour.Spec.Map
Description : The browsable, categorised index of the SixFour spec — START HERE.

This is the spec's landing page: a categorised map of every module, so the spec is *browsable* (open
the Haddock HTML and click through) and *navigable* as the app changes. It defines nothing — it only links.

Regenerate the browsable HTML + search with @spec/scripts/spec-docs.sh@ (Haddock + Hoogle). The categories
below mirror @docs/SIXFOUR-SPEC-BROWSABLE-WORKFLOW.md@; keep them in sync when adding a module.

== ★ The core: the NN design
The look-NN is the heart everything orbits. It takes the per-frame palettes (cat. 2), sees them collapsed
(cat. 3), and emits a genome in the palette-tree space (cat. 4), scored by a value oracle and searched.
The verdict (see @docs/SIXFOUR-256-SUPERRES-WORKFLOW.md@): __no JEPA core__ — the net is a __gated, gap-only
residual head__ on a deterministic statistical base; every cell still emits an exact 1-byte index.

  * "SixFour.Spec.Net"            — pinned NN shapes (io dims, MoR depth) → @NetContract@
  * "SixFour.Spec.LookNet"        — the look-NN top-level
  * "SixFour.Spec.LookNetE"       — Encoder (set → σ-equivariant context, L3)
  * "SixFour.Spec.LookNetR"       — Recursion / core (Mixture-of-Recursions, L4)
  * "SixFour.Spec.LookNetD"       — Decoder (state → 384-DOF σ-pair genome, L5)
  * "SixFour.Spec.LookNetCompose" — the σ-equivariance theorem (E∘R∘D)
  * "SixFour.Spec.LookNetEval"    — forward-pass evaluation
  * "SixFour.Spec.LookCore", "SixFour.Spec.Layer", "SixFour.Spec.Scale", "SixFour.Spec.AxisNet" — primitives
  * "SixFour.Spec.Loss"           — training loss (OT/reconstruction; GAN dropped)
  * "SixFour.Spec.PaletteOracle"  — the deterministic value head (Ou-Luo beauty + entropy)
  * "SixFour.Spec.PaletteSearch"  — MCTS over scored candidates
  * "SixFour.Spec.Preference", "SixFour.Spec.Look", "SixFour.Spec.Loom" — preference / authoring surface
  * "SixFour.Spec.LookCategory" — ★ north-star: named look taxonomy + on-device Bradley–Terry push-pull learning

== ★★ The Color Atlas — on-device personalization (north-star training surface)
The first spec footprint of the north-star: the user curates a 16³ board, picks become Bradley–Terry
comparisons, and a small per-user delta head is updated on device (proven on hardware, see
@docs/COLOR-ATLAS.md@ + the UPDATE block in @docs/STATUS.md@).

  * "SixFour.Spec.AtlasBoard"      — the 16³ curation board state
  * "SixFour.Spec.AtlasState"      — the Atlas session state
  * "SixFour.Spec.AtlasMove"       — the Move ADT (the user's curation actions)
  * "SixFour.Spec.AtlasOracle"     — the value oracle scoring board candidates
  * "SixFour.Spec.AtlasNetEval"    — ★ AlphaZero reframe: concrete forward for the policy/value
    heads (golden-vector oracle, ported from atlas_net_mlx.py); see SIXFOUR-ALPHAZERO-COLLAPSE-DESIGN
  * "SixFour.Spec.AtlasGame"       — ★ AlphaZero reframe: the unified GameMove ADT (Edit|Curate|Rung)
    over PaletteSearch/AtlasMove/CubeLadder; Compare lifted out as reward; Q16 terminal determinism
  * "SixFour.Spec.BoardQ16"        — ★ AlphaZero reframe: deterministic integer board-mass derivation
    (integer binning + counts + one-rounding Q16 mass) closing the float input gap to the policy argmax
  * "SixFour.Spec.GLRM"            — ★ AlphaZero reframe: the preference-training kill-switch (OLS over
    [coverage,beauty,‖chroma‖²]; STOP on no signal; drop degenerate gallery pairs)
  * "SixFour.Spec.GumbelSearch"    — ★ AlphaZero reframe: Sequential-Halving root selection + the Q16
    cross-tier comparison key (CPU tree ≡ GPU float value decision; sub-key wobble cannot flip a move)
  * "SixFour.Spec.Proposer"        — ★ the propose-candidates organ: compose orthogonal genome seed →
    value-rank → Sequential-Halving into one A/B Proposal (the three pieces, finally wired)
  * "SixFour.Spec.ValueHead"       — ★ the LEARNED BT value head: linear floor + gated tanh residual +
    on-device training step (nn-6; finite-diff-pinned gradient; linear is the zero-residual case)
  * "SixFour.Spec.AtlasCascade"    — the multi-stage proposal cascade
  * "SixFour.Spec.PersonalGenome"  — ★ pivot: the per-device θ lifecycle (cold start, per-pick
    learning, deterministic replay, KataGo-gated promotion) wrapping "SixFour.Spec.PreferenceUpdate"
  * "SixFour.Spec.DecisionLog"     — the replay-record wire format of picks
  * "SixFour.Spec.DeltaCodebook"   — the per-user delta-head codebook
  * "SixFour.Spec.PreferenceUpdate" — the on-device preference-update (gradient/weight) rule

== 1. Numeric & colour core
"SixFour.Spec.Shape", "SixFour.Spec.Color", "SixFour.Spec.ColorFixed", "SixFour.Spec.LinAlg",
"SixFour.Spec.Tensor", "SixFour.Spec.Gauge", "SixFour.Spec.Sinkhorn" (entropic OT + the
debiased Sinkhorn divergence — the discrete-measure fidelity that tightens the Bures
Gaussian-summary; shared by "SixFour.Spec.Loss" and "SixFour.Spec.Barycenter").

== 2. Per-frame palette — the NN INPUT
"SixFour.Spec.StageA", "SixFour.Spec.Palette", "SixFour.Spec.QuantFixed", "SixFour.Spec.GMM",
"SixFour.Spec.Bures", "SixFour.Spec.Diversity", "SixFour.Spec.Coverage", "SixFour.Spec.Significance",
"SixFour.Spec.SignificanceFixed".

== 3. Collapse → the global palette
"SixFour.Spec.Collapse", "SixFour.Spec.GlobalVolume", "SixFour.Spec.Cyclic",
"SixFour.Spec.Barycenter", "SixFour.Spec.Entropy". (Baseline = maximin pick;
"SixFour.Spec.Barycenter" is the free-support W₂ /particle-flow/ move — the next rung of the
GIFA→GIFB redesign — that lets atoms transport, not merely select; "SixFour.Spec.Entropy" is the
capture information analysis — RGBT pool weights + the per-frame↔global scope cost — that DECIDES
where global vs per-frame is justified, see @docs/SIXFOUR-CUBE-LADDER-GAP-ANALYSIS.md@. The NN
learns this barycenter.)

== 4. Palette structure / genome — the NN OUTPUT space (16² / 4⁴ / 2⁸)
"SixFour.Spec.SplitTree", "SixFour.Spec.PairTree", "SixFour.Spec.PairTreeFixed",
"SixFour.Spec.RGBTLift" (the @2×2 ↔ RGBT@ reversible integer lifting — the spatial sibling of the
1-D PairTreeFixed S-transform; the @(2×2)<->1@ bijection that makes the cube ladder lossless, see
@docs/SIXFOUR-RGBT4D-BUFFER-HARDENING-WORKFLOW.md@),
"SixFour.Spec.OctreeCell" (★ octree keystone — the @2×2×2 → 1@ structured-leaf
fixpoint @Fix (OctF l)@: collapse = catamorphism, lift = anamorphism, octant edge
@liftOct@ lifts "SixFour.Spec.RGBTLift" to @8→8@; PROVES "1 at the bottom" is a
structured @(coarse + 7 detail)@ band not a scalar — reversibility forces operadic
self-similarity, and per-scale weights are expressible),
"SixFour.Spec.LadderIdentity" (★ disambiguates the two operators both called "cube
ladder" and PINS @VolumeOctant@ ("SixFour.Spec.OctreeCell", ×8 volume / 7 detail) as
the learned token substrate vs @SpatialHaar@ ("SixFour.Spec.CubeLadder", ×4 area / 3
detail) as the Zig within-rung op — laws destructure the real operators to PROVE
they differ (closes audit blocker B2; role-split not deletion),
"SixFour.Spec.PerScaleWeights" (★ per-scale octree weights — the depth-indexed
gains that REPLACE @LookNetR@'s one weight-tied block; neutral weighting is the
reversible floor, and a per-scale weighting is strictly more expressive than any
tied one, so it subsumes and supersedes the retired Mixture-of-Recursions design),
"SixFour.Spec.ScalePonder" (★ per-scale structured halting — the refine-mask over
octree scales that REPLACES @LookNetR@'s scalar PonderNet halt; refine-all is the
reversible floor and a non-contiguous ponder is unreachable by any single
stop-depth, so adaptive per-scale pondering strictly exceeds the scalar halt),
"SixFour.Spec.LocalPonder" (★ per-(level,octant) adaptive deltas — "rungs
accelerate/decelerate in deltas": generalizes ScalePonder from LEVEL-uniform to a
PER-OCTANT @LocalMask@ (@applyLocal@). @lawLevelUniformSubsumed@ (per-level Ponder is the
all-octants-agree special case), @lawLocalExceedsLevel@ (keep one octant + drop its
sibling is unreachable by ANY per-level mask and changes the reconstruction — strictly
more expressive), @lawHaltingALevelZeroesItsBits@ (halting a varied level drives its
"SixFour.Spec.DetailEntropy" coded-bit budget from positive to ZERO — a MEASURED saving,
not a True-count)),
"SixFour.Spec.XYTLabDuality" (★ the @[x,y,t] ≅ [L,a,b]@ duality — the involutive
functor Φ (@x↦a,y↦b,t↦L@) splitting the cube into a UNIVERSAL/balance factor @t≅L@
and a SEARCH factor @(x,y)≅(a,b)@; the @Balance ⊣ Search@ adjunction whose unit is
the reversible RGBTLift Haar split — L is the balance the A/B searches destabilize),
"SixFour.Spec.LBalanceOperator" (★ L = the universal balance operator made
first-class: the coarse/DC value of an octant, gamut-closed (in the children's
range) and fixed on a uniform cell (the floor fixpoint) — the @t≅L@ factor the
white-balance + dynamic-range operator drives below the A/B chroma search),
"SixFour.Spec.OctreeGenome" (★ the octant-ladder GENOME — bijective octree code
(@genomeOf@/@paletteOf@ = octantDistill/Synthesize); law-pins the scale counts
@octreeLeafCount = 8^d@ and @octreeNodeCount = (8^d−1)/7@ that will drive the Atlas
head dims; makes @zero-genome == floor@ concrete (fills @ExportFamily@'s TODO law).
σ-symmetry / 256-palette mapping / cut-depth are DEFERRED design decisions that
parameterise these formulas),
"SixFour.Spec.SuccessiveRefinement" (★ the "surface one 16³, keep the remainder in
the net" code — Equitz-Cover successive refinement over the octant ladder: @split@
collapses the k finest levels into the surfaced cube + held detail bands, @refine@
replays them exactly; @lawMarkovByPooling@ = the coarse is a deterministic pool of
the fine, the no-rate-penalty guarantee; @remainderRate@ = the held info budget),
"SixFour.Spec.RemainderTail" (★ the discrete-surfaced / continuous-remainder TYPED
SPLIT that closes audit B6+B1 — 'Surfaced' (integers) reconstructs EXACTLY while
'Remainder' (continuous FlowAR tail) reconstructs only WITHIN @eps@ and is provably
NOT bit-exact, so "lossless by construction" is forbidden and losslessness is pinned
to RETAINING the remainder (@lawLosslessNeedsRemainder@); the tail is one-shot, not
autoregressed, and channel-bounded),
"SixFour.Spec.ByteCarrier" (★ the TYPE-ENFORCED device-byte vs Mac-float boundary —
phantom-tagged @Carried tag a@ (constructor hidden): @Q16 = Carried DeviceTag Int@
ships+runs, @Latent = Carried MacTag Double@ is Mac-side; the ONLY float→device
crossing is @reenterQ16@ (= AtlasGame.quantizeQ16, the zero-genome==floor seam), and
no @Latent -> Int@ is exported so @toByte someLatent@ is a COMPILE ERROR — CLAUDE.md's
"float must never carry a device byte" as a theorem, not a lint),
"SixFour.Spec.Dim6" (★ the 6-axis ALPHABET (L,A,B,x,y,t) every projection-ordering
permutes — one FLAT subset-enum spanning the colour/position boundary (vs
"SixFour.Spec.XYTLabDuality"'s two split 3-sets); @phi6@ = the @x↔a,y↔b,t↔L@ twist as
an involution; @isUniversal@ marks the @L,t@ carrier the encoding pins to the coarse
lane. The frontier-1a foundation that @ProjectionOrdering@ builds on),
"SixFour.Spec.ProjectionOrdering" (★ frontier-2: a VALID projection-ordering of the
six @Dim6@ axes as a smart-ctor newtype @Ordering6@ — carrier @(L:t)@ pinned coarse,
the search pairing @{x,y}<->{a,b}@ carried as a first-class XOR\/Z2 choice (@XorBit@:
two cosets, x->a\/y->b vs x->b\/y->a) so projections stay ORTHOGONAL and reversibility
is the @Z2@ inverse; @orderingHash@ = a @Word32@ projection-mode token (OptionTree\/
GenomeHash idiom); @composeOp\/identityOp\/invertOp@ = the group action as functions+laws,
not a typeclass until closure is proven. Vocabulary (cabal-repl enumerated): XOR-only = 2,
full coset = 16),
"SixFour.Spec.Dimensions" (★ the RULE OF DIMENSIONS — the traceable axis ledger
(L,t surfaced; a,b,x,y held) + @lawDimConserved@: surfaced + held == input dims
exactly, no dimension silently dropped),
"SixFour.Spec.OptionTree" (★ the Merkle-MCTS option tree — KataGo/AlphaZero @puct@
selection + @{N,W,P}@ edges over @GameMove@, nodes keyed by the surfaced Q16
@GenomeHash@ so equal looks dedup (@transposition@ = a Merkle DAG); @visitPolicy@ =
the visit-count training target; the surfaced-tier half of the AlphaZero/MuZero
hybrid, latent remainder never hashed),
"SixFour.Spec.ChromaRotation" (★ the swipe-TURN gauge — SO(2)/Cn rotation of the
@(a,b)@ chroma plane (L fixed): bit-exact quarter-turn subgroup @C4@ + @canonicalQuarter@
necklace gauge-fix (rotation-equivalent looks dedup, @lawCanonicalChromaGaugeFixed@);
detents C12/C8/C6 = 30/45/60deg as FLOAT-guidance re-entering the Q16 floor; gray
axis = the collapse-proximity degenerate fixed point),
"SixFour.Spec.DetentNudge" (★ the angle-gated ±1 swipe (frontier 1c) — a unit (a,b)
step is an 'AdmissibleStep' (smart-ctor) ONLY when its quarter-turn angle lands on the
chosen detent grid (@lawStepOnlyAtDetent@; @C6@/60deg rejects 90deg = the octant mirror
of @lawQuarterInDetent@); the increment is the unit ±1 rotated by @rotateQuarter@,
unit-length-preserving, and the opposite-sign step undoes it),
"SixFour.Spec.LatentNavigation" (★ the single-16³ STEERING model that REPLACES the
A/B pick — finger gestures as the non-abelian rigid-motion group @C4 ⋉ ℤ²@ on the
shared latent: @compose@ is non-commutative (@lawNonAbelian@), every single step has
an exact inverse, but undoing an earlier move by a later opposite swipe FAILS
(@lawUndoNeedsHistoryNotInverse@ = the @SE ≠ NW⁻¹@ fact) so undo = HISTORY REPLAY;
A/B is the degenerate 1-step case),
"SixFour.Spec.NudgeStep" (★ the ONE-DIRECTION-AT-A-TIME arrow wiring the steering
organs together — @LatentCube@ is the ONE shared cube-shaped @ByteCarrier.Latent@;
@project@ = __P__, the LOSSY MANY-TO-ONE readout to the shown 16³ Q16 built on the
single sanctioned @reenterQ16@ crossing (@lawProjectIsManyToOne@: distinct latents
collide); @nudge@ moves the shared latent by ONE gesture's @(a,b)@ search-shift
(@lawSingleNudgeIsOneStep@), then @nudgeThenProject@ re-projects a FRESH 16³
(@lawNudgeThenProject@); undo = history-replay (@lawNudgeUndoIsHistory@ DELEGATES to
@LatentNavigation.lawUndoNeedsHistoryNotInverse@ — P is non-invertible)),
"SixFour.Spec.LatentProjection" (★ __P__ as the STRUCTURAL POOLING readout (the
dimension-reducing complement to @NudgeStep@'s scalar @map reenterQ16@) — @project@
= @map reenterQ16 . poolToRung@ where the lossy half is octant pooling
(@SuccessiveRefinement.split@): @lawProjectionManyToOne@ (a concrete distinct-latent
collision via discarded detail), @lawProjectionThroughReentry@ (P factors through the
single @ByteCarrier.reenterQ16@ seam, no raw round), @lawProjectionIsPooling@
(DELEGATES @SuccessiveRefinement.lawMarkovByPooling@ — coarse is a deterministic pool
of fine), and @lawUndoNeedsReplayBecauseNonInjective@ (non-injective P ⇒ undo =
history-replay, complementing the non-commutativity proof)),
"SixFour.Spec.OctreeForward" (★ the CAPSTONE FSM — capture -> @surface@ (one 16^3
shown + held latent remainder, cut fixed at 2 levels from 64^3) -> @refineOne@
(show one finer band, lossless) -> @commit@ (the shipped terminal): composes
SuccessiveRefinement + OptionTree + ScalePonder + ChromaRotation as ONE contract;
every law delegates to an already-proven one so the composition preserves them),
"SixFour.Spec.SelfSimilarReconstruct" (★ the SELF-SIMILAR 256³ reconstruction — the
SAME octant operator applied twice: 16³→64³ replays HELD EXACT detail (delegates
@SuccessiveRefinement.refine@), 64³→256³ synthesises INVENTED CONTINUOUS detail (the
latent tail re-entered to Q16 via @ByteCarrier.reenterQ16@); same shape
(@OctreeCell.lawLadderSelfSimilar@), different DETAIL SOURCE as a type),
"SixFour.Spec.DeferredSurfacing" (★ the two-rung SEARCH discipline — rung 1 is a
LATENT-SPACE search (continuous @rawMaskedBand@, the @latentScore@), and the single
@reenterQ16@ crossing that SURFACES the bit-exact 16³+residual (@surfaceBand@ =
@predictMaskedBand@) is DEFERRED until AFTER rung 2: @lawDeferredSurfacingPreservesSubQuantum@
= the KEYSTONE/teeth (two candidates with DIFFERENT latents but the SAME surfaced byte ⇒
surfacing early collapses a distinction the search needs), @lawSurfaceComesAfterBothRungs@ =
both rungs latent then ONE terminal surface (no early commit), @lawSurfacedOutputIsExact@ =
the committed 16³+residual refines back bit-exact (delegates SuccessiveRefinement.lawRefineRoundTrip),
@lawSearchReusesBothRungs@ = one θ_B spans the pair (delegates MaskedBandPrediction.lawMaskedReusesOnBothRungs).
Composes MaskedBandPrediction's latent/surfaced seam; re-pins nothing),
"SixFour.Spec.SelfSupervisedRung" (★ the SELF-SUPERVISION split — TWO regimes, one per
rung: the within-capture @HeldRung@ (16³→64³) MANUFACTURES an exact label from the data via
the reversible lift (@lawHeldLabelIsDataManufactured@ = @refine.split==id@; scored by
@heldLoss@), the beyond-capture @InventedRung@ (64³→256³) has NO label and self-supervises by
CONSISTENCY (@inventedAccepts@ = @RedownsampleGate.passesGate@ — this is the gate's FIRST
consumer; @lawInventedScoredByConsistency@ rejects coarse drift, accepts invented high-freq):
@lawSupervisionMatchesRung@ = the dichotomy is total/exclusive, @lawOneOperatorTwoSupervisions@
= one θ_B, two scorers (what makes the rungs RELATED), @lawSelfSupervisedLabelIsLearnable@ =
the manufactured label is signal not noise. A JEPA learns with zero annotation; this types
WHERE the signal comes from. Re-pins nothing),
"SixFour.Spec.NeuronRedundancy" (★ REDUNDANCY of the intermediate-latent neuron outputs —
a rung @64³→[32³]→16³@ / @256³→[128³]→64³@ passes through an intermediate that never
surfaces; it is the only level the net organises, so the self-supervised efficiency pressure
(VICReg covariance / decorrelation — one view, NOT cross-view Barlow) applies there. @crossRedundancy@ = sum of squared off-diagonal
neuron cross-correlations (0 iff decorrelated): @lawIdenticalNeuronsAreFullyRedundant@ /
@lawDecorrelatedNeuronsZeroRedundancy@ = teeth, @lawRedundancyMeasuredInLatent@ = surfacing
destroys the sub-quantum correlation so it MUST be read in latent space (the
DeferredSurfacing argument). Information view = DetailEntropy. Re-pins nothing),
"SixFour.Spec.RungPivot" (★ the CANONICAL "rung" — the 64³ capture is the PIVOT; a rung is
one self-similar 2-octant-level hop carrying a NEVER-SURFACED intermediate latent one level
off the pivot: DOWN @64³→[32³]→16³+residual@ (Held), UP @64³+residual→[128³]→256³@ (Invented).
@lawIntermediateIsMidLevel@ = the 32³/128³ sit symmetrically (octreeDepth ±1, 32·128=64²),
@lawIntermediateNeverSurfaces@ = KEYSTONE, the intermediate is latent-only (surfacing collapses
sub-quantum info), @lawDownIsHeldUpIsInvented@ ties to SelfSupervisedRung, @lawRungEndpointExact@
= the down endpoint round-trips (refine.split==id). Types the 32³/128³ gap that was prose-only.
Re-pins nothing),
"SixFour.Spec.HJepaLevels" (★ WHERE ARE THE LEVELS — the H-JEPA hierarchy as a TYPE: three
orthogonal axes (SCALE × CHANNEL × TIME) but SCALE is the level SPINE, CHANNEL/TIME factor each
level. @lawScaleIsTheSpine@ = KEYSTONE/TEETH (only SCALE owns a never-surfaced symmetric
intermediate — 32·128=64², the one level the net organises = precondition for planning; delegates
RungPivot @lawIntermediateIsMidLevel@), @lawChannelFactorsEachScale@ (L is the fixed DC carrier;
delegates CarrierL @lawCarrierIsDC@), @lawTemporalIndexesEachScale@ (closed loop; delegates
TemporalLoop @lawTemporalLoopClosesExact@), @lawInterLevelPredictorIsCrossScale@ = the
plan→execution hop is the unique inter-level edge (Analysis 16³ → Synthesis 256³). A FLAT hierarchy
fails. Pure index/law module, no golden. Re-pins nothing),
"SixFour.Spec.DisplayDecoder" (★ the shown L-16³ is a LEARNED, lossy, NON-deterministic decode of the
free latent — a steering VIEW, provably NOT the architecture (HJepaLevels untouched). @lawCommitQuarantinedFromDisplay@
= KEYSTONE: the committed Q16 bytes are the latent's floor ALONE, blind to the display decoder (a forbidden
@commitLeaky@ that folded the display in DIVERGES — teeth), so the float preview can NEVER contaminate the
integer output; @lawDisplayIsLossyFloat@ = decoder-dependent float view (the accepted approximation);
@lawSteeringActsOnLatent@ = a chroma action moves the deterministic commit (the approximate preview drives a
real result). The "max decoupling" choice made SAFE under the Q16 contract. Re-pins nothing),
"SixFour.Spec.EncoderFrozen" (★ WHAT IS THE ENCODER (GIF → embeddings) — the four-phase gate.
Answer (c)-degenerate: the encoder is @liftOct@ (fixed Int bijection) ∘ @featuresB@ (fixed 9-D φ_B),
ZERO learnable params, so there is NO pre-training phase. @lawEmbeddingFeatureMapIsParameterFree@ =
the embedding is blind to θ_B (locks candidate (b) — a learned encoder — out by gate),
@lawPredictorIsTheOnlyLearnedObject@ = the 63-param θ_B rides ABOVE the embedding (encoderParamCount 0
vs predictorParamCount 63), @lawEmbeddingNeverBypassesQ16@ = INFER: the float embedding reaches a byte
ONLY through the single @reenterQ16@ crossing (1.5 → 98304), @lawRawEmbeddingCommitIsUnsafe@ = CONTINUOUS
teeth: 1.0 vs 1.0000001 floor to the SAME byte (sub-quantum) while 1.0 vs 2.0 differ (whole-unit) —
committing the raw float is unsafe, @lawNoPreTrainPhase@ = KEYSTONE: the frozen lift DEFINES the
embedding space AND manufactures the JEPA label, so encoder+predictor are one object. Consolidating GATE
over OctreeCell/MaskedBandPrediction/ByteCarrier; re-pins nothing),
"SixFour.Spec.ContinuousLoop" (★ CONTINUOUS-INFERENCE — the live steering loop as a proven state machine:
hold ONE latent, @step@ steers the latent + decodes a cheap quarantined preview and NEVER commits, commit is
on-demand. @lawStepNeverCommits@ = a tick stays continuous (not the Q16 bytes), @lawIdentityGestureIsFixpoint@
= the zero gesture leaves latent+commit invariant, @lawLoopClosesOverT@ = a full 64-frame period of no-gesture
ticks returns the latent (delegates TemporalLoop closure), @lawCommitInvariantUnderDisplayDecoder@ = KEYSTONE:
two DIFFERENT display decoders give DIFFERENT previews but the SAME committed bytes (the end-to-end quarantine,
the strongest form of DisplayDecoder.lawCommitQuarantinedFromDisplay). Composes DisplayDecoder+TemporalLoop;
re-pins nothing),
"SixFour.Spec.JepaTarget" (★ the I-JEPA CORRESPONDENCE as theorems — SixFour's JEPA target is a
DATA-MANUFACTURED exact label (the lift's held band), NOT a learned EMA target-encoder output, so no EMA and
no collapse. @lawTargetIsDataManufacturedNotEncoded@ (refine.split==id makes the label),
@lawTargetFixedUnderPredictorTraining@ = NO-COLLAPSE: the target is θ-free so training can't move it (what
I-JEPA's stop-grad/EMA enforces, here structural), @lawNoTargetEncoderNoEma@ (the target's encoder = the
param-free lift, encoderParamCount 0 ⇒ nothing to EMA), @lawCollapseIsRejected@ (a constant predictor incurs
strictly positive loss), @lawTargetCarriesInfoBeyondContext@. Assembles teeth from
SelfSupervisedRung/MaskedBandPrediction/EncoderFrozen/DetailMaskedPrediction; re-pins nothing),
"SixFour.Spec.PerAxisTraining" (★ the six-axis ledger verified BY TRAINING (not op-structure): each
of the 7 octant detail bands (search axes a,b,x,y + slots) is INDEPENDENTLY learnable.
@lawBandLearnedInIsolation@ (train band 0 → recovers 3000, band 1 stays floor), @lawPerBandTargetsAreIndependent@
(bands 0,1 learn 3000/5000 with no cross-talk), @lawEverySearchBandIsIndependentlyLearnable@ (all 7 bands
trainable). Closes the "attribution is op-structural not trained" gap. Pure law module over MaskedBandPrediction;
re-pins nothing),
"SixFour.Spec.SameObjectInvariance" (★ the frontier keystone — the SAME 64³ object
reconstructs identically under either XOR projection-ordering: @decodeUnder p . encodeUnder p
== decodeUnder p' . encodeUnder p'@ (@lawReorderingPreservesObject@), the orbit under the
@Z2@ is the object; @lawDifferentEncodingsSameObject@ = same object / orthogonal projection;
@lawEquivariance@ = swap-the-ordering == swap-the-input. Why the projection-choice is a safe
RL action. Delegates OctreeCell octant bijection + ProjectionOrdering XOR self-inverse),
"SixFour.Spec.CubeTensor" (★ the ONE canonical voxel-tensor object — Q16 OKLab over the
(x,y,t) lattice, channel-split (L carrier + a,b search), octant-Morton: @toChannelSoA@/
@fromChannelSoA@ is a LOSSLESS rename onto @SameObjectInvariance.Cube@
(@lawChannelSoARoundTrip@), @lawCarrierChannelIsL@ pins channel 0 = @Dim6.DimL@ carrier,
@lawSearchSwapFixesCarrier@ = the Z2 swap never moves L. The in-memory home the "soup"
was missing; lets VoxelReduce feed SameObjectJEPA and a projection become a query.
Additive rename, no golden re-pin),
"SixFour.Spec.ProjectionQuery" (★ RAG READ-AS-PROJECTIONS — a projection-ordering used
as a LOSSLESS retrieval QUERY against a stored @CubeTensor@, returning the SAME object
viewed differently: @queryByOrdering@/@queryByHash@ (the token-keyed read, the lock the
0-caller @orderingHash@ key was missing), @lawQueryReadConsistency@ = two ordering-keys
decode to the SAME object (the RAG correctness theorem, delegates
@SameObjectInvariance.lawReorderingPreservesObject@), @lawCarrierFixedAcrossQueries@ =
the L carrier band is identical under every query (L-anchored retrieval),
@lawHashKeyRejectsUnknown@ = the lock is not vacuous. Why a projection-query is a safe
RL READ. Swift landing = the un-built GeneStore.retrieve/nearest),
"SixFour.Spec.SameObjectJEPA" (the same-object ROUND-TRIP — a 'JepaPair' (smart-ctor
from ONE cube + two orderings, so context & target are GUARANTEED co-projections) with
@predictTarget@; @lawJepaPredictsTarget@ is a SANITY check NOT a learning objective
(@predictTarget = encodeUnder . decodeUnder@ ⇒ loss zero by Z2 round-trip, the predictor
never appears — DEMOTED, the real objective is "SixFour.Spec.DetailMaskedPrediction"),
@lawJepaSameObject@ = co-projections of one object, @lawJepaContextIsCube@ = context
faithfully encodes the source),
"SixFour.Spec.DetailMaskedPrediction" (★ the REAL masked-prediction (JEPA) objective —
mask an octant detail band, predict it from the COARSE context alone via
"SixFour.Spec.DetailPredictor" @f@. @lawConstantPredictorIncursLoss@ = an off-floor
masked target makes a CONSTANT (f-free) predictor incur STRICTLY POSITIVE loss AND one
SGD step reduces it (the existential failure the SameObjectJEPA round-trip lacks),
@lawTrainingDrivesLossDown@ = the mask is recoverable by learning, @lawFittingOneTargetMissesAnother@
= the masked band carries info beyond the context. Replaces the vacuous JEPA twin),
"SixFour.Spec.MaskedBandPrediction" (★ the PER-BAND masked-prediction (I-JEPA) objective,
option B — predict ONE masked octant band from the coarse value PLUS the six VISIBLE
sibling bands (@φ_B = [1,ṽ,ṽ²] ++ siblings@, 63 params): @lawMaskedContextExcludesTarget@
= the prediction never sees the masked band (the I-JEPA masking guarantee, teeth against a
leak), @lawSiblingContextStrictlyHelps@ = the KEYSTONE: on two examples sharing a coarse
value but differing in a sibling, the sibling-aware model beats the @0.25·(t̃₁−t̃₂)²@ floor
that bounds EVERY coarse-only predictor (why B is worth its params over A),
@lawMaskedGradientFiniteDiff@/@lawMaskedZeroParamsIsFloor@ = backprop + zero-genome==floor,
@lawMaskedReusesOnBothRungs@ = THE TWO-RUNG LAW: one trained θ_B (63 params) reused UNCHANGED
across the self-similar pair 16³→64³ and 64³→256³ (mirrors DetailPredictor.lawReusesOnBothRungs;
teeth = distinct visible context ⇒ distinct prediction with the masked target held fixed, rejects
any one-rung/context-ignoring predictor; delegates levelsBetween 64 16 == levelsBetween 256 64).
Converts B from a one-rung island into ONE RUNG of the self-similar ladder.
Additive sibling of DetailMaskedPrediction; DetailPredictor untouched),
"SixFour.Spec.MaskedBandTrainer" (★ the θ_B TRAINING contract as a byte-checkable twin for the MLX
descent: a fixed golden fixture (coarse 20000, target 3000) trained @trainerSteps@=2000 must take a
pinned trajectory. @lawZeroGenomeIsFloor@ = floor band 0 start, @lawTrainingDrivesLossDown@ = loss → <1e-3
of floor, @lawTrainedForwardIsGolden@ = THE TWIN: the committed band is exactly @goldenTrainedBand@=3000
(MLX-trained θ_B AND the device forward must reproduce it), @lawTrainingDescendsMonotonically@ = the descent
never increases loss. @lawStableTrainerSurvivesBatchDivergence@ = DEFECT+FIX (GHCi-verified): summed-gradient
@trainBandJoint@ DIVERGES to NaN on a batch of 8 high-ṽ examples (η·N·λ past stability); the additive mean-gradient
@trainBandJointStable@ converges on the same fixture (use it for real batches). Pure law module over MaskedBandPrediction;
trainBandJoint + all its goldens untouched; re-pins nothing),
"SixFour.Spec.CarrierL" (★ L CARRIES THE SIGNAL (frontier 1b) — the coarse/DC band is
the backbone, A/B search is the perturbation L re-balances: @lawCarrierIsDC@ (lBalance =
ocCoarse), @lawZeroSearchIsCarrierFloor@ (A/B=0 ⇒ pure-L constant floor),
@lawCarrierInvariantToSearch@ (L re-balances — coarse invariant to detail, delegates
octant reversibility), @lawSearchIsZeroOnConstant@ (flat L ⇒ zero search). Law module over
the real liftOct/unliftOct),
"SixFour.Spec.SteeringSpine" (★ the form-follows-function CAPSTONE — the one module
where the steering dataflow connects: @steerShown@ (nudge the shared latent then
project the structural pool P to the live 16³ @[Q16]@) and @commitReconstruct@ (the
self-similar lift to 256³); delegates every heavy proof to its organ
("SixFour.Spec.NudgeStep"/"SixFour.Spec.LatentProjection"/"SixFour.Spec.SelfSimilarReconstruct"),
adds @lawSpineShownIsCoarser@ (P is dimension-reducing — a pixel is a PROJECTION of
the one latent, not the latent); end-to-end Q16 is a TYPE guarantee),
"SixFour.Spec.RedownsampleGate" (★ the RSI verify gate scoped to the COARSE/DC band —
@passesGate@ pools a reconstructed cube via @octantDistill@ and checks the coarse
equals the given rung: @lawGateRejectsCoarseDrift@ (teeth — drifted DC is rejected,
not-vacuous) + @lawGateIgnoresInventedDetail@ (invented high-freq exempt, so genuine
super-res is never rejected, not-impossible); closes audit H2, runs on the integer
floor so eps=0),
"SixFour.Spec.PairedResidual" (★ capture-anchored super-res — the 256³ detail is a
residual KEYED BY the 64³ coarse value (@ResidualBook = Map Int Detail@, @residualFor@
= the codebook/token lookup), applied self-similarly (@pairedLift@ = @liftKeyed@ twice,
same book): @lawPairedRepoolsToCoarse@ (the 256³ re-pools to EXACTLY the 64³ for ANY
book — capture-anchored by octant reversibility, RedownsampleGate passes by
construction) + @lawDistinctBooksSameCoarse@ (residual in the gate's null space) +
@lawResidualPureValue@ + @lawUnseenKeyIsFloor@ (zero-genome==floor). "The residual IS
the token, keyed by the coarse value." Additive sibling to SelfSimilarReconstruct's
free latent-tail path),
"SixFour.Spec.DetailPredictor" (★ the LEARNED detail-predictor @f_θ : coarse → detail@
that REPLACES "SixFour.Spec.PairedResidual"'s stored table with a trainable parametric
function (@θ·φ per band@, @φ(v)=[1,ṽ,ṽ²]@), re-entered to Q16 via the single
"SixFour.Spec.ByteCarrier" @reenterQ16@ crossing; trained by finite-diff-pinned SGD
(the "SixFour.Spec.ValueHead" idiom) on the SUPERVISED @16³→64³@ rung and REUSED
unchanged on the unsupervised @64³→256³@ rung — self-similar transfer. @zeroParams ==
floor BY ARITHMETIC@ (no sentinel): @lawZeroParamsIsFloorArithmetic@ has four teeth
(floor / non-constant / step-decreases / differs-from-floor), each killing a different
wrong @f@),
"SixFour.Spec.SuperResPalette" (★ the per-frame ≤K-colour constraint on the 256³, as a
TYPE + a verified requantizer over "SixFour.Spec.Upscale256". @PaletteFrame@ (hidden-ctor
brand, value-level — build via @mkPaletteFrame@: Just iff ≤K distinct) + @requantizeSlice@
(LOSSLESS within budget, NEAREST-of-K reps over budget). @lawWithinBudgetLossless@ +
@lawNearestMinimizesError@ + @lawMultiColourLegitimate@ kill the clamp-to-one-colour cheat;
@lawUpscalePreservesLengthBudget@ (THE tie: Upscale256 never grows a frame's palette, so
the per-frame budget SURVIVES super-res — delegates @lawIndicesInRange@). "Invent free
detail" is bounded to free INDEX detail inside the ≤K table),
"SixFour.Spec.DetailEntropy" (★ the integer-histogram Shannon entropy over octant
@Detail@ bands — "bits = compressible surplus": @shannonBits@ = @−Σ p·log₂ p@ read
PER-BAND (@detailColumn@/@detailEntropyBits@), the missing Tier-0 estimator that makes
adaptive rung deltas a MEASURED bit saving. @lawSkewedStrictlyBelowUniform@ (a skewed =
well-predicted residual costs strictly fewer bits than uniform — rejects a
frequency-ignoring distinct-count fake) + @lawEntropyZeroIffSingleSymbol@ (flat band =
0 bits) + @lawPerBandDiffersFromPooled@ (per-band ≠ pooling all 7)),
"SixFour.Spec.CanonicalPhase" (the loop
gauge-fix — the rotation-invariant necklace canonical form that gives the semantic RGBT lanes a
reproducible phase on the C₆₄-symmetric GIF loop),
"SixFour.Spec.RGBTFeature" (the 1b feature layer — entropy-weighted temporal coherence over the
circular buffer, the substrate every tier reads), "SixFour.Spec.CubeLadder" (the 16³/64³/256³ tiers
as reversible 2D-Haar views on that substrate — lossless within capture via "SixFour.Spec.RGBTLift",
predictive only beyond), "SixFour.Spec.TemporalLoop" (EXACT 64-frame GIF-loop closure — a
period-2⁶ Q16 cosine LUT whose wrap is an integer identity — plus the low-frequency temporal
residual over the owned integer Haar; the shipped Q16 twin of the float "SixFour.Spec.Cyclic"),
"SixFour.Spec.VoxelReduce" (the JOINT spatio-temporal @(2×2)×(2×2)→1@ reduction @64³ ↔ 16³@ — one
named operator composing the spatial "SixFour.Spec.CubeLadder" per channel with the temporal
"SixFour.Spec.TemporalLoop" Haar per position; reversibility inherited from both owned laws, see
@docs/SIXFOUR-PER-FRAME-GENOME-AB-MIGRATION-WORKFLOW.md@),
"SixFour.Spec.DivergenceSchedule" (the A/B divergence schedule @Δ = |r_A − r_B|@ — the policy:value
mix-ratio gap that starts wide and narrows as Compares accrue, floored @> 0@ so A and B never
collapse; the start-diverse-then-converge knob + the MAP-Elites descriptor axis),
"SixFour.Spec.MoveRadiusSchedule" (★ the GEOMETRIC sibling of DivergenceSchedule: the annealed Q16
'SixFour.Spec.IsometryMove' magnitude (wide early → JND floor) + a hard cumulative-displacement cap —
the visible-reload-without-drift schedule; EXACT integer, no ε),
"SixFour.Spec.ABSurface" (the simplified 8-phase capture→A/B→export FSM = the user story; total δ,
Pick* self-loop in Picked, Export gated on a prior pick, the two 16×16 candidate cell rectangles),
"SixFour.Spec.SigmaPairFixed", "SixFour.Spec.SigmaPairHead", "SixFour.Spec.SigmaDecomp",
"SixFour.Spec.Quad4", "SixFour.Spec.Quad4Fixed", "SixFour.Spec.Bottleneck16",
"SixFour.Spec.LeafOverride", "SixFour.Spec.IsometryMove" (★ the EXACT delta-preserving A/B move:
sign-flips + integer translation on Q16 OKLab, the only no-tolerance lattice isometries, SIMT-native —
preserves intra/inter-frame colour deltas, stops the genome-game degradation), "SixFour.Spec.ThetaToDelta"
(★ canonical-path n=0: the closed-form
σ-aware taste-gradient map θ(770) → generator δ(384-DOF) that feeds LeafOverride / s4_leaf_override),
"SixFour.Spec.GenomePair" (★ pivot KEYSTONE — two orthogonal-by-
disjoint-support σ-valid A/B candidate displacements from the base genome, with a θ-independent
cold-start ranking), "SixFour.Spec.GenomeBlend" (★ pivot: federated transport — an extracted
foreign genome enters as ONE gated Bradley–Terry Compare, never a θ splice),
"SixFour.Spec.GenomeCarrier" (★ pivot: the genome-in-GIF S4GN byte codec — Int32 LE Q16 in a
GIF89a Application-Extension, CRC32-checked, total Absent\/Corrupt\/VersionMismatch extraction),
"SixFour.Spec.PaletteGesture", "SixFour.Spec.GroupRGBT".

== 5. The authoring STORY (Acts I–IV) — the user-facing pipeline the NN lives in
"SixFour.Spec.StageA" (Act I, @16²@ per-frame) · "SixFour.Spec.QuartetDelta" (Act II, @4⁴@ quartet core) ·
"SixFour.Spec.HaarRibbon" (Act III, @2⁸@ Haar abstraction) · "SixFour.Spec.Export" (Act IV, the global pack
@{16³,64³,256³}@) · "SixFour.Spec.Upscale256" (Act IV, the residual-seeded @256³@ super-res of the export pack).
See @docs/SIXFOUR-PALETTE-STORY-WORKFLOW.md@.

== 6. Dither & index encoding
"SixFour.Spec.Dither", "SixFour.Spec.SpatialDither", "SixFour.Spec.STBN3D", "SixFour.Spec.Indices",
"SixFour.Spec.FrontProjection", "SixFour.Spec.VoxelFit".

== 7. UI — the cell-field / display / grid
"SixFour.Spec.Display", "SixFour.Spec.PlaybackClock", "SixFour.Spec.Lattice", "SixFour.Spec.Boundary", "SixFour.Spec.InfluenceField", "SixFour.Spec.CellFiber",
"SixFour.Spec.CellGrid", "SixFour.Spec.CellShapes", "SixFour.Spec.CellMechanics", "SixFour.Spec.GridLayout",
"SixFour.Spec.GridAxis",
"SixFour.Spec.GridScript", "SixFour.Spec.MovableLayout", "SixFour.Spec.WidgetDescriptor", "SixFour.Spec.Ownership", "SixFour.Spec.Order",
"SixFour.Spec.CloudProjection", "SixFour.Spec.SevenSeg", "SixFour.Spec.Pipeline", "SixFour.Spec.Obfuscation".

== 8. Cross-cutting
"SixFour.Spec.Laws" — shared law combinators.

== 9. Codegen — emitters to the app (Swift / Zig / Python), golden-pinned
@SixFour.Codegen.Swift@, @.Shapes@, @.Golden@, @.Collapse@, @.RGBT4D@, @.PairTree@, @.QuartetDelta@, @.Genome@,
@.GenomeFixed@, @.PaletteValue@, @.MLX@, @.CoreML@, @.Burn@.

== 10. Look transfer / LUT extraction (R3D .cube)
The on-screen "look" and the exported 3D LUT are two projections of ONE OKLab palette→palette
transform derived from the captured palette's luminance-zone chroma profile (a port of
@~/lut-generator/src/python/gif_palette_lut.py@). See @docs/SIXFOUR-LOOK-LUT-WORKFLOW.md@.

  * "SixFour.Spec.ZoneProfile"  — luminance-zone mean a/b/chroma profile of a palette
  * "SixFour.Spec.LookTransfer" — the chrominance-only transfer (preview ≡ cube core)
  * "SixFour.Spec.RedFrontEnd"  — Log3G10 decode + RWG→Rec.709 + filmic tonemap (LUT-driven, Q16)
  * "SixFour.Spec.CubeLut"      — the 65³ .cube grid builder
-}
module SixFour.Spec.Map () where

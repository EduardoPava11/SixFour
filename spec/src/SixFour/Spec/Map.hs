{- |
Module      : SixFour.Spec.Map
Description : The browsable, categorised index of the SixFour spec — START HERE.

This is the spec's landing page: a categorised map of every module, so the spec is *browsable* (open
the Haddock HTML and click through) and *navigable* as the app changes. It defines nothing — it only links.

Regenerate the browsable HTML + search with @spec/scripts/spec-docs.sh@ (Haddock + Hoogle). The categories
below are the canonical browsable index; keep them in sync when adding a module (the maintenance contract in @CLAUDE.md@).

== ★ BACKEND COMPARTMENTS — the translation map (orthogonal cross-cut of the categories below)

The spec is the ONE source of truth that translates OUTWARD to four backends. Each compartment is
bounded by a PHANTOM TAG: organising by compartment IS organising by tag. A value crosses a boundary
only through a tagged seam; the only float->floor crossing is @ByteCarrier.reenterQ16@. (This is the
index cross-cut; physically the modules stay where they are, gated by golden vectors per backend.)

  * __THE WALLS (pure-spec, no backend code — they DEFINE the boundaries):__
      "SixFour.Spec.ByteCarrier" (@MacTag@ float vs @DeviceTag@ byte; no exported @Latent -> Int@;
      @reenterQ16Many@ = the batched float->floor door for a vector head), "SixFour.Spec.Sided"
      (@DisplaySide@ preview vs @CommitSide@ commit), "SixFour.Spec.BoundedP6" (in-domain @|v|<=B@
      by construction), "SixFour.Spec.DataParallel" (the 4th wall: @DataParallelTag@; a GPU op is a
      pure @PixelMap@ and every reduction declares its @DetClass@ @Exact@/@Tol@ = the determinism
      hierarchy as a type). The float->byte seam is @reenterQ16@ (= @AtlasGame.quantizeQ16@).

  * __ZIG FLOOR__ (tag: @DeviceTag@/@CommitSide@/@BoundedP6@ — bit-exact integer, shipped). Mechanism:
    golden-vector-gated HAND-PORT (@Codegen.Golden@ -> ~30 @s4_*@ kernels in @Native/src/kernels.zig@;
    NO @.zig@ emitter, by design). Modules: "SixFour.Spec.SubstrateDomain", "SixFour.Spec.BoundedP6",
    "SixFour.Spec.RGBTLift", "SixFour.Spec.CubeLadder", "SixFour.Spec.OctreeCell",
    "SixFour.Spec.V21Field" (V2.1 pre-collapse field: curves collapse to the GIF89a byte; byte-exact
    core = collapse\/opponent-delta\/metric, REUSING the OctreeCell octant spine; colour-ring-agnostic),
    "SixFour.Spec.V21Transport" (the RECOVERED TIME axis: a byte-exact 1-D optimal-transport
    displacement flow @T = F⁻¹∘F@ on the equal-mass per-frame value histograms; anchor + per-frame maps
    reconstruct all 64 slices, restoring the time↔value coupling the pooled field marginalises away),
    "SixFour.Spec.V21Pyramid" (the two-scale SPATIAL field pyramid: the @64×64@ sub-bins block-pool into
    @16×16@ bins; a byte-exact aggregate — pooling is transitive so bins == pooled sub-bins — that is lossy
    DOWNWARD, and whose @16²=256@ coarse bins ARE the realisable palette basis for the barycentric-coordinate
    value head),
    "SixFour.Spec.ByteCarrier", "SixFour.Spec.QuantFixed", "SixFour.Spec.ColorFixed",
    "SixFour.Spec.LeafOverride", + the @safeNudge@/domain half of "SixFour.Spec.RelationalResidual" and
    the Held rung of "SixFour.Spec.SelfSimilarReconstruct". @liftOct@ (the @2x2x2->1@ octant edge, the
    learned-token substrate) HAS its floor kernel @s4_octant_lift@\/@s4_octant_unlift@ (kernels.zig:857,
    built from the two quad kernels). __V2.1 GAP:__ "SixFour.Spec.V21Field" @collapseQ16@ has its floor
    kernel @s4_v21_collapse@; the bin-creation, opponent-delta and palette-delta kernels are still to add.
    "SixFour.Spec.V21Transport" is spec-green (@transportDisp@\/@pushforward@\/@reconstructFlow@) but its
    floor kernel @s4_v21_transport@ is still to add.

  * __PYTHON/MLX MODEL + TRAINER__ (tag: @MacTag@ — float latent, Mac-side, NOT shipped). Mechanism:
    a @Codegen.MLX@-style emitter (today emits the ABANDONED look-net). Modules: "SixFour.Spec.LargeJepaHead",
    the trainer twin in "SixFour.Spec.MaskedBandPrediction" + "SixFour.Spec.MaskedBandTrainer",
    "SixFour.Spec.JepaTarget", "SixFour.Spec.EncoderFrozen", "SixFour.Spec.NeuronRedundancy",
    "SixFour.Spec.DeferredSurfacing", the Jacobian half of "SixFour.Spec.MoveSignal",
    "SixFour.Spec.JepaData" (the I-JEPA DATA ENGINE: manufacture the @(context,mask,held-target)@
    records from octants via the reversible @liftOct@; KEYSTONE @lawDataEngineRoundTrips@ proves
    @reconstruct (manufacture cube m) == cube@ = the held band is a TRUE label, closing the
    non-invertibility trap a buggy generator would otherwise pass silently. The dependency root
    of spec-owned TRAINING), and the
    cohesive memory wall "SixFour.Spec.JepaMemory" (★ the I-JEPA MEMORY BUDGET pinned as ONE tested
    fact = the destructive-pivot tripwire: latent capacity @32³/128³@, the 14-int residual unit
    bound to its 77-param trained carrier, 7 detail bands, 64-512 tokens, @{L,t}@-carrier /
    @{a,b,x,y}@-search partition; re-pins no golden, fires the gate if a split drops a budget).
    __GAP (mostly):__ no I-JEPA-head MLX emitter (@Codegen.JepaHead@), no Python head-trainer twin,
    @coreai_export@ stub still aimed at the deleted L-net. (The DATA ENGINE now EXISTS:
    "SixFour.Spec.JepaData" + @trainer/jepa_data.py@ + @Codegen.JepaData@, gate-forced.)

  * __METAL GPU__ (data-parallel, shipped). Mechanism: hand-ported @.metal@ (NO @Codegen.Metal@ emitter
    yet). Modules: the palette quantizers, float "SixFour.Spec.Color", the ordered branch of
    "SixFour.Spec.SpatialDither", the accumulation of "SixFour.Spec.GMM", "SixFour.Spec.IsometryMove"
    (SIMT-claimed, strongest A/B-throughput candidate, no kernel today), "SixFour.Spec.Coverage".
    __GAP:__ a @Codegen.Metal@ emitter (template on the @InfluenceField@ dual-emit pattern).

  * __SWIFT + CORE AI DEVICE__ (tag: @DisplaySide@ + the device, Tier-2 shipped). Mechanism:
    @Codegen.Swift@ + golden-gated hand-port. DONE: the UI/FSM half + the 63-param @theta_B@ forward
    ("SixFour.Spec.MaskedBandForward", byte-exact). __GAP:__ the ENTIRE steering chain is 0% Swift
    ("SixFour.Spec.NudgeStep", "SixFour.Spec.LatentNavigation", "SixFour.Spec.SteeringSpine",
    "SixFour.Spec.TwoMoveOctave", the @bandEnergy@ half of "SixFour.Spec.MoveSignal",
    "SixFour.Spec.DisplayDecoder", "SixFour.Spec.ContinuousLoop"); the Core AI socket
    (@CoreAILInference@) is ORPHANED (TODO stub, aimed at the deleted L-net) — it is the SOCKET the
    large I-JEPA head must plug into once trained.

THE I-JEPA MODEL COMPARTMENT makes Core AI CHECKABLE: the large head is @MacTag@ float, but
@lawDepth1ReducesToFeaturesBPos@ pins its single-token limit to the SAME goldens the byte-exact
@theta_B@ forward already passes, and "SixFour.Spec.MaskedBandTrainer" pins the descent endpoints. So
a clean model compartment with EncoderFrozen as its lower wall and @reenterQ16@ as its only exit is
exactly what lets the float Core AI head be verified against the integer floor. Prereqs (ordered):
(1) @s4_octant_lift@ Zig kernel, (2) the data engine — DONE ("SixFour.Spec.JepaData" + @trainer/jepa_data.py@),
(3) the @Codegen.JepaHead@ MLX emitter + Python trainer twin, (4) wire the Core AI socket to the trained weights.

== ★ The core: the NN design
The LIVE learned core (CLAUDE.md, the 2026-06-22 I-JEPA redirect) is an __asymmetric I-JEPA__: the frozen
reversible lift is the param-free TOKENIZER ("SixFour.Spec.EncoderFrozen") that also MANUFACTURES the
collapse-proof target ("SixFour.Spec.JepaTarget", no EMA), and a genuinely LARGE position-conditioned
predictor ("SixFour.Spec.LargeJepaHead", @d6@ learnable attention) rides on top — TRAINED MLX ->
coreai-torch -> Core AI. The 63-param @theta_B@ ("SixFour.Spec.MaskedBandPrediction") ships hand-written
byte-exact; the float head re-enters the Zig Q16 floor. See the __BACKEND COMPARTMENTS__ section above for
the I-JEPA roster (@RelationalMemory@ the @d6@ metric, @JepaMemory@ the memory budget, @JepaData@ the data
engine) and its compartment.

The ENTROPY-EARNED ENCODER CHAIN (2026-06-23) — every encoder dimension earned by a theorem,
organised by entropy, mutation-verified (each law falsifiable by a killer mutant in @cabal repl@):

  * "SixFour.Spec.Q16"                  — the single float→int seam (@quantizeQ16@, round-half-even)
  * "SixFour.Spec.SynthesisPolicyValue" — ★ the GIF synthesis as TWO CONTENT heads: discrete index-code + continuous palette (AlphaGo policy/value analogy ONLY; true policy/value is INTER-FRAME). Fused-space gauge law (@lawReconstructionGaugeInvariant@); rungs labelled, @256³@ = separate deterministic endgame (@lawHeadsLiveAtLabeledRungs@); OKLab + relational order = SixFour-ADDED, GIF table is gauge-free sRGB @≤256@
  * "SixFour.Spec.HalfwayLatent"        — ★ the fuse IS the 32³ midpoint (@lawFuseIsMidpoint@: 64·512=32768)
  * "SixFour.Spec.EncoderModalityLoad"  — the 3 modality loads on one non-negative bit axis (ridged colour rate)
  * "SixFour.Spec.EncoderWidthAlloc"    — width = entropy share of the fixed 512 (Hamilton largest-remainder)
  * "SixFour.Spec.EncoderDepthAlloc"    — depth = octant rate-distortion ladder (cap @levelsBetween 64 4 = 4@)
  * "SixFour.Spec.EncoderEntropyFloor"  — the source-coding floor (learned ≥ entropy share)
  * "SixFour.Spec.EncoderCorpus"        — the corpus → loads → floor bridge (numbers respond to content)
  * "SixFour.Spec.EncoderGrounding"      — ★ the H-JEPA GROUNDING law: the perceptual load IS the JEPA target entropy
  * "SixFour.Spec.SyntheticCorpus"       — the synthetic entropy×Lab corpus: the spec guarantees encoding

RETIRED 2026-06-23 ("one truth", branch @spec/retire-ab-one-truth@): the EARLIER MLX look-NN
global-palette path (@Net@ / @LookNet*@ / @Loss@ / @PaletteOracle@ / @PaletteSearch@ / @LookCore@ / …)
AND the A/B preference Color Atlas (the AlphaZero reframe: @AtlasBoard@ / @AtlasGame@ / @AtlasNetEval@ /
@BoardQ16@ / @GLRM@ / @GumbelSearch@ / @Proposer@ / @ValueHead@ / @PersonalGenome@ / …) were DELETED —
the self-supervised JEPA-EBM is the only learned truth. The look-net deploy blob (Zig
@s4_load_look_net@ + Swift @loadLookNet@ + the trainer look-NN Python) was retired with them.

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
"SixFour.Spec.Collapse" (METAL-GPU: the float OKLab maximin BASELINE only — pooledCandidates /
farthestPointCollapse), "SixFour.Spec.GlobalCollapseQ16" (ZIG-FLOOR: the SHIPPED byte-exact Q16
collapse split out of Collapse (pivot) — PxQ16 / globalCollapseQ16 / reindexFrameQ16, the Zig
@s4_global_collapse@ reference via QuantFixed, + the HARD-MUST-1 PaletteScope gate. The float
baseline and the byte-exact device collapse have different determinism classes, so they split
along the seam), "SixFour.Spec.GlobalVolume", "SixFour.Spec.Cyclic",
"SixFour.Spec.Barycenter", "SixFour.Spec.Entropy". (Baseline = maximin pick;
"SixFour.Spec.Barycenter" is the free-support W₂ /particle-flow/ move — the next rung of the
GIFA→GIFB redesign — that lets atoms transport, not merely select; "SixFour.Spec.Entropy" is the
capture information analysis — RGBT pool weights + the per-frame↔global scope cost — that DECIDES
where global vs per-frame is justified. The NN
learns this barycenter.)

== 4. Palette structure / genome — the NN OUTPUT space (16² / 4⁴ / 2⁸)
"SixFour.Spec.SplitTree", "SixFour.Spec.PairTree", "SixFour.Spec.PairTreeFixed",
"SixFour.Spec.Loom" (the user-driven UNBALANCED merge-forest authoring verb — hand-folding the
2⁸ palette one @2→1@ merge at a time to any posterization N; the lossless-split sibling of the fixed PairTree),
"SixFour.Spec.RGBTLift" (the @2×2 ↔ RGBT@ reversible integer lifting — the spatial sibling of the
1-D PairTreeFixed S-transform; the @(2×2)<->1@ bijection that makes the cube ladder lossless),
"SixFour.Spec.Recursion" (the boot-only fixpoint foundation — @Fix@/@cata@/@ana@/@hylo@
declared ONCE so the multiresolution lift is NAMED, not re-derived per module; @hylo@-fusion +
round-trip laws pinned against a sample functor; deliberately NO @meta@/@apo@/@para@/@histo@/@futu@
(jargon-by-absence — no typed consumer; @hylo@ alone has one, OctreeCell @lawOctantBuildFlattenIsHylo@)),
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
head dims; makes @zero-genome == floor@ concrete.
σ-symmetry / 256-palette mapping / cut-depth are DEFERRED design decisions that
parameterise these formulas),
"SixFour.Spec.SuccessiveRefinement" (★ the "surface one 16³, keep the remainder in
the net" code — Equitz-Cover successive refinement over the octant ladder: @split@
collapses the k finest levels into the surfaced cube + held detail bands, @refine@
replays them exactly; @lawMarkovByPooling@ = the coarse is a deterministic pool of
the fine, the no-rate-penalty guarantee; @remainderRate@ = the held info budget),
"SixFour.Spec.SubstrateDomain" (the @|v| <= B = 2^29-1@ invertible-DOMAIN contract:
the lift round-trips for all 64-bit Int, but the SHIPPED i32 Zig substrate is only
TOTAL on this domain; @lawDomainFitsI32@ proves every band fits i32 in-domain and
@lawBoundIsTight@ proves B is tight (the 4B HH band of @liftQuad@ is the binding case);
mirrors the Zig @SUBSTRATE_BOUND@ / @RC_OUT_OF_RANGE@ total-function guard so the oracle
and the kernel share ONE domain),
"SixFour.Spec.RelationalResidual" (ZIG-FLOOR: the bit-exact 6D-point SUBSTRATE the relational
memory rides on — the @P6 (L,a,b,x,y,t)@ point, the @+/-1@ @nudge@, and the @safeNudge@ DOMAIN
GUARD (the @RC_OUT_OF_RANGE@ sibling). The I-JEPA memory half split out below),
"SixFour.Spec.RelationalMemory" (MLX-MODEL: the I-JEPA RELATIONAL MEMORY UNIT split out of
RelationalResidual (pivot STEP 4): the @d6@ metric (Q16 L1, a real metric = the attention
ground-distance / memory KEY) + the @phi6@ pairing @a<->x,b<->y,L<->t@ + the LEARNED
@7 bands x {x,y} = 14@-int position residual (@relationalResidualLen@ = the user's @16-2=14@,
carriers @{L,t}@ held out). Rides on the RelationalResidual substrate; budget carried by
@JepaMemory@),
"SixFour.Spec.LargeJepaHead" (★ the genuinely-LARGE ViT-scale position-conditioned
asymmetric I-JEPA head as a CONTROLLED DEVIATION above the proven small predictor: @d6@
seeds a T5-style LEARNABLE relative-position attention bias @b_h(d)=beta-s*d@ (@s>0@) so the
unit distance can GROW/SHRINK in the higher-dim relations (@lawBiasLearnsToScale@); KEYSTONE
@lawDepth1ReducesToFeaturesBPos@ collapses the big head to @predictMaskedBandPos@ at the
single-token limit, so @lawPositionConditioningStrictlyHelps@ is inherited and the float
scale never bypasses Q16; no-EMA + VICReg-load-bearing delegated. Trains MLX -> coreai-torch
-> Core AI = the flip condition),
"SixFour.Spec.TwoMoveOctave" (the GLOBAL-coarse-octave-then-LOCAL-fine-octave @(a,b)@
two-move chroma navigation: AXIS-AWARE @+/-1@ moves (via @RelationalResidual.nudge@, so
@(+2,0)/=(+1,+1)@ and a diagonal's two orderings differ at the intermediate 16³ = the "mid
funnel"), the 12 ordered magnitude-2 paths over 8 endpoints, one composed @d6@ as the
per-two-move SIGNAL. OCTAVE answer: VALUE distance LINEAR (@d6@), SCALE distance OCTAVE
(@levelsBetween@=log2); @s_h@ the learned octave scale stays in @LargeJepaHead@. KEYSTONE
@lawDiagonalOrderingsDifferAtIntermediate@. Reuses NudgeStep/DetentNudge/DisplayDecoder),
"SixFour.Spec.MoveSignal" (the CONTENT-RESPONSIVE move signal v1, closing the
@moveMagnitude@-is-a-constant gap = HARD #1: @signalAt = sensitivity(move) * bandEnergy(landing
octant)@, the deterministic texture-energy factor (band L1 norm of the reversible-lift detail,
zero on a flat octant) times a learned SENSITIVITY pinned to 1 in v1 (the trained Jacobian
multiplies in later). KEYSTONE @lawTexturedMoveStrictlyExceedsFlat@ = the property the constant
@moveMagnitude@ cannot have. Float, DISPLAY-SIDE, quarantined from the commit
(@lawSignalQuarantinedFromCommit@ delegates DisplayDecoder). Reuses DetailEntropy/CarrierL),
"SixFour.Spec.BoundedP6" (TYPE-ENFORCED domain: a @BoundedP6@ is in-domain @|v|<=B@ BY
CONSTRUCTION (constructor HIDDEN, only @mkBoundedP6 :: P6 -> Maybe BoundedP6@ builds one), so a
committing op typed to CONSUME a @BoundedP6@ cannot receive an unchecked @P6@ -- out-of-domain
commit is a COMPILE error, not the runtime @safeNudge@/Zig @RC_OUT_OF_RANGE@ refusal. The
"SixFour.Spec.ByteCarrier" pattern applied to the substrate domain. Additive leaf),
"SixFour.Spec.Sided" (TYPE-ENFORCED quarantine: a phantom @Sided DisplaySide@/@CommitSide@ tag
(orthogonal to ByteCarrier's @MacTag@) with hidden constructor, so a DISPLAY-side float (a render
or a "SixFour.Spec.MoveSignal" signal) PHYSICALLY cannot reach @commitS@ -- promotes the runtime
@lawCommitQuarantinedFromDisplay@/@lawSignalQuarantinedFromCommit@ into one compile boundary.
@commitS (signalAtS x)@ does not type-check. Additive leaf),
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
"SixFour.Spec.ConstructionEncoder" (★ ENCODER A of the dual-encoder H-JEPA — the GIF's
"construction instructions" (a Q16 colour @cPalette@ + a Morton-order @cIndex@ map) as a
semantic embedding that @buildPixels@ EXECUTES to a @SameObjectInvariance.Cube@:
@lawConstructionExecutesToPixels@ = the encoder IS the palette lookup,
@lawBuildIsTotalOnValid@ = a valid construction builds exactly @8^d@ voxels,
@lawBuildRespectsIndex@ = the index map carries information (the section-injectivity
GifDualView rides). @cIndex@ = discrete CONTENT code (a lossless VQ-style codebook map),
@cPalette@ = colour; policy/value are RESERVED for the inter-frame delta, NOT a single frame.
Q16 substrate twin of the float @Palette@/@Indices@. Additive),
"SixFour.Spec.HierarchicalDelta" (★ "abstract the H" — the inter-frame DELTA as a hierarchical
object: ONE @HierarchicalDelta@ interface (@coarseBand@/@fineBand@ that reassemble losslessly,
@lawHierarchyLosslessSplit@) instantiated by TWO different carriers — VALUE @ColourDelta@ (abelian
ℤ-module, deltas ADD) and POLICY @IndexDelta@ (transport group, deltas COMPOSE; provenance-carrying
so invertible) — plus @bandedDeltaTarget@ = the data-delta octant pyramid reusing the frozen ladder.
@lawHierarchicalDeltaTargetIsDataManufactured@ + @lawDeltaBandsArePerBandDataProvenance@ strengthen
@JepaTarget.admissibleRolloutSource@ (the rollout-provenance design rule) per-STEP→per-BAND (closes the
coarse-to-fine L_close escape). Additive; re-pins nothing),
"SixFour.Spec.RootLatticeDetail" (★ ALGEBRA of the band count — the "1 coarse + (b-1) detail"
structure IS the split exact sequence @0 → A_{b-1} → ℤ^b → ℤ → 0@: coarse = the rank-1 sum
functional Σ, detail = its kernel @A_{b-1}@ (the densest-packing root lattice, mean-free /
vanishing-zeroth-moment). @lawBandCountEqualsRank@ makes the band count @b-1@ a THEOREM for ANY
branching (b=8 octant → 7 = rank A_7 via @lawOctantIsA7@), @lawRootCoordsRoundTrip@ = A_{b-1} is the
free ℤ-module on the simple roots, @lawDetailKernelIsConstants@ = detail captures exactly the
mean-free part. The @MeanFree@ newtype (hidden constructor; built ONLY via @mkMeanFreeFromRootCoords@
or the checked @mkMeanFreeChecked@, NEVER by subtracting a mean = dividing by the non-unit @b@)
carries @Σ=0@ in the TYPE (@lawMeanFreeIsSigmaZero@). Gates the IDEALIZED LINEAR Haar skeleton, not
the floored kernel. Additive),
"SixFour.Spec.GaugeAction" (★ the model's three GAUGE freedoms as ONE finite GROUP ACTION whose
OBSERVABLE is the orbit invariant (rendered image = quotient X/G): the palette gauge @S_K@ (permute
colours + remap index) and the @ℤ/2@ channel/ordering involution (swapAB\/XOR\/phi6), each with
@lawObservableIsOrbitInvariant@. INVARIANT THEORY, not Galois: @lawPaletteGaugeIsNonAbelian@ pins
@S_K@ ≠ the cyclic Frobenius @Gal(F_256/F_2)=ℤ/8@. Subsumes @lawPaletteIndexGaugeInvariant@,
@lawReorderingPreservesObject@, @lawPhi6Involution@. Additive),
"SixFour.Spec.ScaleFiltration" (★ the 16→64→256 = 2⁴→2⁶→2⁸ spine as a descending sublattice chain
+ octree-ball ULTRAMETRIC — the model's ONLY non-archimedean metric. The s-adic @valuation@ =
octant-path divergence depth; @lawValuationUltrametric@ = the STRONG triangle, @lawUltrametricIsIsosceles@
= the isosceles theorem, @lawL1NotUltrametric@ proves d6/ℓ¹ (archimedean) is genuinely DIFFERENT
(closes the "d6 is 2-adic" overclaim). @lawDescendingChainIndex@ = refine by b = sⁿ (= 8 octant).
Finite-depth (no completion claim). Additive),
"SixFour.Spec.RingReduction" (★ @reenterQ16@ generalized — the single float→device crossing as a
RING REDUCTION between a fine "big" grid (MLX float twin) and the coarse Q16 device grid: @embed@
(section) + @reduce@ (round half-to-even). @lawReduceEmbedId@ = retraction (grid fixpoints),
@lawReduceIdempotent@ = terminal quantization, @lawReduceBatchedIsElementwise@ = no cross-band
coupling. HONEST BOUNDARY @lawReduceIsNotAdditive@: @reduce@ is a QUANTIZER, not a ring hom (0.5+0.5
rounds to 1 ≠ 0). Subsumes @lawByteOnlyFromQ16@/@lawReentryIsFloor@/@lawTerminalQuantizationIdempotent@.
Additive),
"SixFour.Spec.MetricLattice" (★ d6 generalized to an ℓ^p lattice norm with the exponent @p@ a KNOB:
@p = 1@ = the model's taxicab d6 (unit ball = CROSS-POLYTOPE, @2d+1@ points), @p = ∞@ = Chebyshev
(unit ball = HYPERCUBE, @3^d@ points). Metric axioms hold for both (@lawTriangle@/@lawNormFaithful@…);
@lawUnitBallsDiffer@ proves the knob is real (geometries differ at @d ≥ 2@); @lawLInfBoundedByL1@ the
norm inequality. @p = 2@ (Euclidean → dual-lattice/sphere-packing) is a documented un-gated extension.
Re-homes the d6 metric laws. Additive),
"SixFour.Spec.AnchorDiagnostic" (★ experiment #1 of the L-anchor model review, made a THEOREM: ONE
@ChannelDetail@ interface @channelEnergy@ with TWO lenses as instances — L scored by DISCRETE GEOMETRY
(@MetricLattice@ @d6@\/@ℓ¹@ lattice norm) and chroma by ALGEBRAIC NUMBER THEORY (@GaussianChroma@
@ℤ[i]@ field norm). @0@ energy = at the root-lattice floor (nothing to learn). KEYSTONE
@lawIsoLuminantSignalIsInChromaRingNotL@: a constant-L\/varying-chroma octant has its whole signal in
the chroma ring while L is at floor, so an L-only target (@palette_target@ a=b=0) is provably BLIND to
it = the structural reason the masked-band head can sit at the zero floor. Contrast laws pin the other
regimes (@lawLumaRampSignalIsInL@ where L-anchoring is right, @lawFlatSceneFloorsAllChannels@ where the
data engine is the culprit). Reuses frozen @liftOct@; emits no golden. Additive),
"SixFour.Spec.DualCube" (★ THE PIVOT off L-anchoring: the colour cube @(L,a,b)@ and space cube
@(x,y,t)@ as TWO copies of one @ℤ ⊕ ℤ[i]@ module (real BALANCE axis + Gaussian SEARCH plane),
EXCHANGED by the φ6 involution @phi6@ (built on @XYTLabDuality@ φ + @GaussianChroma@ ℤ[i]). KEYSTONE
@lawCubesExchangedByPhi6@: @colorCube (phi6 p) == spaceCube p@; @lawPhi6IsModuleAutomorphism@ makes φ6
a ℤ⁶ symmetry ⇒ @lawNoPrivilegedCarrier@: L (colour balance) and t (space balance) are φ6-images, so
anchoring on L is ARBITRARY not canonical. Replaces the asymmetric @{L,t}@-carrier/@{a,b,x,y}@-search
story (CarrierL/RelationalMemory) with a SYMMETRIC dual-cube carrier. @lawBalanceRealSearchGaussian@ =
the two lenses (ℓ¹ lattice on the real axis, ℤ[i] norm on the Gaussian plane). Additive),
"SixFour.Spec.ChannelProduct" (★ ABSTRACT AGAIN: all NINE colour×space comparisons as FREE channels
(@L:t,L:x,L:y,a:x,a:y,a:t,b:x,b:y,b:t@) = the complete 3×3 bilinear matrix @M[c][s]=colour(c)·space(s)@,
which is GIF89a (separable @value×content@ = RANK 1, @lawComparisonIsSeparable@) AND transformer
attention (outer product @q⊗k@, @lawComparisonIsOuterProduct@) AND generalizes @DualCube@ (whose φ6
diagonal = the φ6-FIXED cells, @lawDiagonalIsPhi6Fixed@). Two lenses per block: balance @L:t@ = @ℤ@
lattice product (geometry); search block @{a,b}×{x,y}@ = the @ℤ[i]@ Gaussian product @(a+bi)(x+yi)@
(@lawSearchBlockIsGaussianProduct@, number theory). KEYSTONE @lawAllChannelsSeeWhatLAnchorMisses@: two
points differing only in chroma are IDENTICAL to the L-anchored single row but DISTINCT under the full
nine — the provable expressiveness gap behind band-at-floor. PonderNet+transformer = adaptive-depth
attention over this matrix; H-JEPA target rides on it. Additive),
"SixFour.Spec.HeldOutTarget" (★ THE CRUX of the holistic full-matrix H-JEPA: the JEPA target is HELD
OUT from the input across SCALE (coarse in, the 7 octree-orthogonal DETAIL bands held) and TIME
(frame t in, frame t+1 held), the structural REPLACEMENT for per-pair masking. Predict the WHOLE held
set with NO mask, yet @lawScaleTargetNotAFunctionOfInput@/@lawTimeTargetNotAFunctionOfInput@ (same
input, different target exists) + @law*IdentityIncursLoss@ (copy/floor predictor loses) make it
collapse-proof. KEYSTONE @lawHeldOutReplacesMasking@; @lawTargetIsWholeNotMaskedPair@ (all 7 bands, not
1 masked). Reuses frozen @liftOct@. The two held axes = the two RungPivot rungs. Additive),
"SixFour.Spec.MatrixTarget" (★ the HOLISTIC target object: the whole 9-channel ChannelProduct matrix
at the held scale/frame, predicted in one shot. RANK-1 HONEST (@lawMatrixTargetIsRank1@ /
@lawGeneratorIsSixNotNine@: the matrix is rank 1, real DOF = the 6-D P6 generator, holism = value×content
COUPLING not extra DOF). KEYSTONE @lawMatrixLossSeesOffDiagonal@: a prediction differing only in chroma
is invisible to the L-row loss (@lRowLoss@=0) but visible to the full @matrixSqLoss@ (>0), so fitting the
whole matrix forces learning the chroma the L-anchor floored. @lawTargetIsFullMatrixNotMaskedPair@.
Builds on ChannelProduct + HeldOutTarget. Additive),
"SixFour.Spec.NudgeRankTheorem" (★ THREE hypotheses as theorems. RANK: per voxel @M=colorVec⊗spaceVec@
is rank ≤1 (@lawSingleVoxelRank1@, all 2×2 minors 0 = the 6-DOF generator) but the CELL-aggregate
@A=Σ colour⊗space=C·Sᵀ@ reaches rank 3 (@lawCellAggregateReachesRank3@, 3 φ6-diagonal voxels give I,
det 1) ⇒ the 9-pair nudge is honest at the CELL not the VOXEL (@lawNineIndependentAtCellNotVoxel@), so
the held-out @MatrixTarget@ loss must be the full-rank aggregate (@lawHeldOutLossIsCellAggregateNotPerVoxel@,
a mispaired-chroma swap is invisible per-voxel but @aggSqLoss=4>0@). COLLAPSE: @liftOct@ = two spatial
@liftQuad@ + one temporal @sLift@ (@lawOctantAxesAreSpaceTime@), the octant axes ARE @(x,y,t)@ and the
@Int@ payload is one OKLab channel (@lawColourIsTheLiftedValue@, three independent passes); 64³→16³ folds
space-time /4 while colour rides lossless (@lawTwoLevelsCollapseSpaceTimeNotColour@); BOTH levels mix both
axes (@lawBothLevelsAreMixedSpaceTime@ REFUTES one-spatial-one-temporal) and the value/collapsed split is a
φ6 GAUGE (@lawValueSplitIsPhi6Gauge@ REFUTES intrinsic colour, reuses DualCube). RESIDUAL: down (16³→64³)
and up (64³→256³) residuals are the SAME @[[Detail]]@ + SAME @octantLift@ (@lawResidualTypeScaleInvariant@)
both ∈ A₇=ker Σ (@lawResidualIsA7AtEveryLevel@), so the down band is a legit conditioning SEED richer than
the zero floor (@lawDownResidualConditionsUpInvention@) — but NOT the answer (@lawDownResidualIsNotUpGroundTruth@
REFUTES copy-as-ground-truth via @lawBeyondCaptureInvented@'s non-injectivity). Reuses ChannelProduct/
MatrixTarget/OctreeCell/RGBTLift/DualCube/SelfSimilarReconstruct/RootLatticeDetail; emits no golden. Additive),
"SixFour.Spec.PonderBudget" (★ THE USER NUDGE: a PAINTABLE per-octant detail-budget field over an
empty 256³; the user paints sections to refine and the BRUSH is the 3-D octant TWICENESS @[2×2×2 ↔ 1]@
twice — one stroke = a two-level subtree (@twicenessSpan = 8^levelsPerStep = 64@ finest octants, the
@reconstruct256@ span, @lawTwicenessBrushIsTwoLevels@). Octant refines iff budget>0; ZERO field = the
byte-exact FLOOR (@lawZeroBudgetIsFloor@), paint-up invents EXACTLY that block (@lawBudgetMonotoneInvention@
+ @lawBudgetIsLocal@), clamped non-negative (no sub-floor). Touches only the LocalPonder refine mask,
never the coarse/DC. HONEST: monotone-in-invention ≠ monotone-in-quality; byte-exact only at the floor.
Additive),
"SixFour.Spec.CellNudge" (★ the THEOREM-CORRECTED nudge (Option C): a per-cell NINE-channel paint over
the 16³ COARSE captured grid (the scale the user actually paints), honest at the cell because the
cell-aggregate is rank 3 (@lawNineHonestAtCell@ via NudgeRankTheorem) while the per-voxel basis stays the
6-D generator. Supersedes PonderBudget's single-scalar/256³ guess. @lawNineChannelsAtCell@ (the 9
ChannelProduct pairs), @lawLossIsCellAggregate@ (MatrixTarget must score the aggregate, not per-voxel),
@lawGaugeExplicit@ (which 9 is a φ6 gauge toggle). Brush unchanged: one 16³ cell governs a 4096-leaf 256³
subtree (@lawCellGovernsSuperResSubtree@ = twicenessSpan², two rungs 16→64→256). Additive),
"SixFour.Spec.V21FieldUI" (★ the V2.1 UI as FUNCTIONS over the probability field: the deterministic
CELL-COUNT layer. @budgetCells@ apportions a cell budget over a Morton-aligned quadtree\/octree by region
uncertainty (@disagree@ = non-mode mass, @0@ on a spike, the saliency twin of V21Field
@lawHistUniformIsSpike@) via exact-integer Hamilton @apportion@; @allocateWidgets@ forces a widget set onto
pairwise-DISTINCT counts (the OPPOSITION law: two widgets never claim the same number of cells) with a
staircase repulsion, feasible iff @total ≥ k(k-1)\/2@ (@lawWidgetOppositionFloor@). @lawBudgetConserves@\/
@lawWidgetBudgetPartitions@ are the UI twins of @lawHistTotalPreserved@; @lawWidgetsOpposeEqualCounts@\/
@lawWidgetSalienceOrders@ are the repulsion. Bleed (the render layer where splats overlap) is a separate
METAL-GPU module on top. Ships hand-written Swift, golden-gated. Additive),
"SixFour.Spec.PonderHaltDistribution" (★ the STRONG PonderNet: a proper geometric HALTING DISTRIBUTION
over refinement steps (Σ p_halt = 1, @lawHaltIsProperDistribution@), the EXPECTED matrix-loss objective
@Σ p_n L_n@ (@lawExpectedLossIsConvex@), a truncated-geometric prior (@lawGeometricPriorSumsToOne@) the run
is KL-regularized toward (@lawKLZeroAtSelf@). NUDGE TIE: lowering the halt probabilities (more painted
CellNudge budget) raises the expected steps = more refinement (@lawLowerHaltRefinesMore@), so the paint and
the halting are one mechanism. Additive),
"SixFour.Spec.VarianceFloorGuard" (★ the collapse guard: a VICReg per-FACTOR std hinge on the colour q
and space k comparison factors. @lawEitherCollapseTripsGuard@: a flat colour OR a flat space factor trips
the combined guard, full variance in both clears it (neither factor can collapse to a point). Tested at
the std boundary @lawHingeAtBoundary@. Additive),
"SixFour.Spec.MotionFloorCorpus" (★ the TEMPORAL collapse guard as a law: the corpus must carry a real
inter-frame MOTION floor (@lawCorpusHasMotionFloor@: persistence @t+1:=t@ loses on motion) AND off-floor
TEXTURE (@lawCorpusHasOffFloorTexture@), else the rungs are vacuous; @lawStaticCorpusStarvesGradient@ is
the refutation it guards (a static loop zeroes the persistence loss). Additive),
"SixFour.Spec.ScaleSpineRungs" (★ the binding keystone: the model has exactly TWO held-out rungs = the
two HeldOutTarget axes, SCALE (super-res 256³, Invented) + TIME (t+1, Held), both scoring the
cell-aggregate matrix (@lawRungTargetIsCellAggregate@) via the same 2-level twiceness operator
(@lawBothRungsSelfSimilar@). @lawTwoRungsAreTheTwoHeldAxes@, @lawScaleInventedTimeHeld@. Additive),
"SixFour.Spec.Model" (★★ THE SINGLE SOURCE — start here for the Held-Out Full-Matrix H-JEPA. Assembles
the model boundary (re-exports @ModelIO@ + @CellNudge@), re-exports the load-bearing laws that survived the
model-spec unification (@lawJointObjectiveIdentifiesFullPalette@ = IDENTIFIABILITY not reachability,
@lawParadigmIsStructurallySound@ = STRUCTURAL not trained, @lawHeldOutReplacesMasking@, the floor + boundary
laws), and PINS the two CONTRACT-ONLY honesty markers (@contractDescentOnRealDataUnproven@,
@contractEmpiricalSoundnessUnproven@) into the build. @modelLawLedger@ is the authoritative
load-bearing-vs-contract taxonomy; @lawNoEmpiricalOverclaim@ FAILS if a "the-model-works" law is
re-introduced as load-bearing — the structural guard against a lying-green regression. See @SIXFOUR-MODEL.md@.
Emits no golden. Additive),
"SixFour.Spec.ModelIO" (★ the MODEL I/O CONTRACT, the wireable boundary: INPUT = 64³ capture
(@Upscale256.UpscaleInput@) + the 16³ 9-channel paint (@CellNudge@) + φ6 gauge; OUTPUT = the 256³ as
@Upscale256.UpscaleOutput@ = per-frame palettes (VALUE) + index planes (CONTENT) = GIF89a, rendered by
@renderFrame@. @lawOutputIsPerFrameValueContent@ (UI-renderable),
@lawNeutralNudgeIsAllFloor@ (unpainted = the lossless floor, byte-exact via Upscale256.lawK0PaletteExact),
@lawInputIsPaintable@ +
@lawNudgeGovernsSuperRes@ (the 9-channel paint maps to the 256³ build). The TRAINER targets a
@ModelOutput@, so one boundary serves UI render, 256³ build, and training. Additive),
"SixFour.Spec.CurateRealize" (the curated-volume → indexed-GIF realization, LAUNCH L1.2: the
interleaved Q16 volume the octant ladder built (@SelfSimilarReconstruct.expandRungVolume@) slices
into per-frame pixels (the layout pin, exact) and quantizes with the SAME verified
@QuantFixed.quantizeFrameQ16@ the shipped renderer runs; FRAME-LOCAL by law (t-slab streaming
licensed), lossless on ≤k-colour frames, and the ladder floor of flatness realizes to one colour.
Resolves the Upscale256 fork honestly: @upscale256@ consumes the V2-deferred global-palette cube,
so the LIVE curate floor is ladder-expand + this realization. Additive),
"SixFour.Spec.AboveFloorMargin" (★ the TRAINING GO/NO-GO de-risk: invented detail can survive the Q16
commit (@reenterQ16@ = @round(x*65536)@) and move the output OFF the deterministic floor, and the margin
is FINITE (½ a Q16 LSB rounds to the floor under round-half-to-even; 1 LSB survives). The floor is not
absorbing above the margin because the octant lift is a reversible bijection (distinct detail ⇒ distinct
cube). @marginCoeffQ16@/@marginCoeffLatent@ name the number the trainer must exceed; the 7 surviving
bands read as A_7 root coords are a legal mean-free residual. @lawFloorMarginIsFinite@,
@lawAboveFloorMarginReachable@, @lawSurvivingDetailIsA7@. Emits no golden. Additive),
"SixFour.Spec.ModelForward" (★ the NUDGE-CONDITIONED FORWARD CONTRACT that closes ModelIO's unused-field
gap: @forward = octantLift floor (commit (gate budget (net …)))@. The paint BUDGET gates (zero ⇒ floor
for ANY head); the opaque learned @PonderHead@ decides the A_7 coordinates (codomain pinned to the lattice
chart, so it cannot leave). @lawZeroNudgeForwardIsFloor@ (byte-exact unpainted floor), @lawNudgeMovesOutput@
(delegates AboveFloorMargin reachability), @lawResidualStaysInA7@, @lawForwardCommitIsQ16@ (sole reenterQ16
crossing, no drift). @forwardFromInput@ consumes @ModelInput.miNudge@/@miGauge@. Emits no golden. Additive),
"SixFour.Spec.RefinementSystem" (★ THE CAPSTONE of the ANT generalization — the spine triad
@CommutativeRing → RModule → ReversibleLift@ that makes the model's structures instances of one
base-ring abstraction. Current model = the @R=ℤ@ (Q16), rank-3 (OKLab), @b=8@ (dyadic octant) corner;
the SAME laws hold over @R=ℤ[i]@ (Gaussian integers — the chroma knob) and a non-dyadic @b=3@ lift,
proving GENERALIZATION not rename. NO @recip@ (field axiom absent by design — byte-exactness forbids
dividing by non-units); INSTEAD the apex carries the FINITE enumerated unit group @units@ (@ℤ*={±1}@,
@ℤ[i]*={±1,±i}@) + the partial @unitInverse@, so "not a field" is a CHECKABLE fact
(@lawUnitsClosedUnderMul@, @lawUnitInverseOnlyOnUnits@, @lawNonUnitsHaveNoInverse@) and the Gaussian
units ARE the quarter-turns (@lawGaussianUnitsAreQuarterTurns@ ties GaussianChroma). @lawModuleSmul*@
(free-module = ColourDelta abstracted), @lawLiftRoundTrips@ (the bijection), @lawLiftDetailCount@ =
b-1 = rank A_{b-1} (ties RootLatticeDetail). Additive),
"SixFour.Spec.RefinementCarriers" (★ WIRES the capstone spine to the PRODUCTION carriers so the
abstraction GOVERNS, not parallels: @ColourDelta@ is a real @RModule ℤ@ (instance in HierarchicalDelta;
4 module laws strict, additive-inverse modulo trailing-zero @canonColourDelta@) and
@lawColourModuleActsAsRecolour@ ties @madd@/@smul@ to the @applyValueDelta@ call site; the octant
@OctLeaf8@ is a real @ReversibleLift@ whose @liftF@ IS @OctreeCell.liftOct@ (@lawOctLeafLiftIsLiftOct@),
OVERRIDING the generic prefix-difference default (@lawOctLeafOverridesDefault@). Uses the new
@ReversibleLift@ @liftF@/@unliftF@ methods. Additive),
"SixFour.Spec.GaussianChroma" (★ the @ℤ[i]@ CHROMA KNOB the capstone unlocked, carried toward the
trainer: pack the two OKLab chroma axes @(a,b)@ into ONE Gaussian integer @a+b·i@ (L stays real) ⇒
@GColourDelta@ is a second fixed-shape @RModule ℤ@ (every module law strict, incl. additive inverse —
unlike ragged @ColourDelta@). FAITHFUL re-encoding (@lawChromaAddAgreesWithRealPairs@) that UNLOCKS a
hue-rotation operator two scalar channels lack: complex multiply rotates\/scales the chroma plane,
the unit @i@ = an exact 90° quarter-turn (@lawChromaUnitIsQuarterTurn@), norm-preserving
(@lawChromaUnitRotationPreservesNorm@), order 4 (@lawChromaQuarterTurnOrderFour@). Additive),
"SixFour.Spec.ChromaUnitGauge" (★ the ℤ[i]-UNITS-ARE-LOAD-BEARING bridge: the Gaussian unit group
@ℤ[i]*={1,i,−1,−i}@ acts on the chroma plane EXACTLY as the model's bit-exact quarter-turn gauge
@ChromaRotation.rotateQuarter@ — the operation @DetentNudge.stepDelta@ actually consumes. NOT a rename of
"rotate 90°" but a proven identity between two independently-defined maps: @lawGaussianUnitActsAsQuarterTurn@
(@rmul (units!!q)@ == @rotateQuarter q@ on every chroma point), @lawUnitGroupIsoQuarterTurn@ (ℤ[i]* multiply
↔ index add mod 4 ↔ quarter-turn composition, so @ℤ[i]*≅C4@), @lawCanonicalQuarterIsUnitOrbit@ (the model's
@canonicalQuarter@ dedup IS the unit-group orbit). Teeth @lawNonUnitIsNotAQuarterTurn@: a non-unit @1+i@
scales the norm, so only the norm-1 unit group lands on a quarter-turn. Makes the @ℤ[i]@ units load-bearing
via a REAL typed consumer (the analogue of BlindComplementIsA7's @mkMeanFreeChecked@). Emits no golden. Additive),
"SixFour.Spec.ChromaUnitMinimizer" (★ LIFTS GaussianChroma's learned hue-rotation unit from DEMONSTRATED to
PROVEN: the convex value objective's UNIQUE minimizer is the @ℤ[i]@ unit @g=i@ when the target palette is a
quarter-turn of the source. Assembled from two real consumers: the objective IS @Convergence.valueLoss@ on the
chroma embedding (@lawObjectiveIsConvergenceValueLoss@, inheriting its strictly-convex unique-min), made
rigorous by the CLOSED FORM @lawContinuousLossIsDistanceToI@ (@contLoss == ½·|g−i|²·‖source‖²@, a quadratic
zero only at @g=i@); and @g=i@ IS the model's bit-exact quarter-turn (@ChromaUnitGauge.lawGaussianUnitActsAsQuarterTurn@,
consumed by DetentNudge). TEETH: @lawNonUnitMultiplierStrictlyLoses@ (a non-unit @1+i@ scales the norm,
strictly loses) + @lawOtherUnitsStrictlyLose@ ({1,−1,−i} are other quarter-turns, each strictly loses ⇒
minimizer uniquely @i@ among @ℤ[i]*@). Capstone @lawValueMinimizerIsZiUnitI@. No new forced algebra (only the
existing @ℤ[i]@ + @rotateQuarter@). Emits no golden. Additive),
"SixFour.Spec.TransportGroup" (★ the POLICY channel's algebra — @IndexDelta@ as a NON-ABELIAN
transport group acting on the index set, the counterpart to the VALUE channel's abelian @ColourDelta@
ℤ-module. @tcomp@ chains, @tinv@ reverses, @tbetween@ data-manufactures; @lawTransportActionHomomorphism@
+ @lawTransportInverse@ + @lawTransportNonAbelian@; KEY @lawCompositionIsChainingNotAddition@ proves
policy deltas compose by CHAINING not addition ([2,0,1] ≠ [2,4,0]) — the law that forbids ever
modeling the policy channel as additive. Completes the ANT generalization. Additive),
"SixFour.Spec.TemporalData" (★ the TIME-AXIS data engine — manufactures @(frame t, value target,
policy target)@ records from a captured @(t, t+1)@ pair (the temporal sibling of @JepaData@'s
spatial corpus). KEYSTONE @lawTemporalEngineRoundTrips@ = @reconstructNext (manufacture ct ctNext)
== ctNext@ (a lossy temporal generator FAILS it, closing the non-invertibility trap on time);
@lawTemporalChannelsDisjoint@ = value touches only the palette, policy only the index (the two
heads train independently); @lawTemporalBandingReconstructs@ = the multi-scale bridge to
@HierarchicalDelta.bandedDeltaTarget@. Additive),
"SixFour.Spec.DeltaSurrogate" (★ the differentiable training surrogates for the two delta heads +
the proof each HARD COMMIT re-enters its byte-exact carrier. VALUE = OKLab REGRESSION
(@ValueSurrogate@/@valueLoss@ squared metric, @lawValueLossIsRegression@); POLICY = per-voxel
CLASSIFICATION (@PolicySurrogate@ softmax+CE, NOT an L2 over slot numbers). KEYSTONE
@lawPolicySurrogateDecodesToTransport@ = the argmax commit equals the data-manufactured @IndexDelta@
(the learned-continuous ↔ proven-discrete bridge, closed for policy); @lawPolicyArgmaxDeterministic@
= lowest-index tie-break (no float commits a byte). @lawPolicyCEGradientMovesTowardTarget@ = the
TRAIN-TIME BACKWARD path (@policyGradStep@: one CE step strictly lowers loss + the argmax converges
to the byte-exact data slot); @lawPolicyArgmaxMarginOrFallback@ = the LOGIT-MARGIN commit
(@commitWithMargin@/@policyMarginEps@: at a sub-eps float near-tie, fall back to the data slot rather
than a device-dependent argmax). Collapse-safety inherited from the
data-manufactured carriers. Additive),
"SixFour.Spec.LearnabilityTheorem" (★ THE IDENTIFIABILITY THEOREM: the capstone
@lawJointObjectiveIdentifiesFullPalette@ proving the joint objective (rank-3 cell aggregate + value head)
IDENTIFIES the data-manufactured target — the optimum is UNIQUE and VISIBLE to the objective — walking the
STATISTICAL moment ladder (mean < variance/covariance < higher < full distribution) over the cell aggregate
@A=C·Sᵀ=Σ colour⊗space@ = the 2nd CROSS-MOMENT. Conjoins SIGNAL (@lawLearnableSignalExists@→AnchorDiagnostic)
∧ EXPRESSIVITY (@lawTargetExpressibleAboveFloor@→AboveFloorMargin/RootLatticeDetail) ∧ rank-3 IDENTIFIABILITY
(@lawCellLossIdentifiesRank3Subspace@→MatrixTarget/NudgeRankTheorem, @cellLoss@ = sufficient statistic for
9 of 24 colour DOF) ∧ NO-COLLAPSE (@lawNoCollapseKeepsCrossMomentFullRank@→VarianceFloorGuard). NET-NEW
@lawValueHeadIdentifiesComplement@: @cellLoss@ is rank-DEFICIENT, exactly ANCILLARY on the 15-DOF
complement of @span(S)@ — the checkerboard-parity witness @cb=(-1)^(x+y+t)@ gives @cellLoss=0@ yet
@valueLoss>0@, so the full palette is identified IFF @w_value>0@. Capstone TRUE at w_value=1, FALSE at
w_value=0 (the load-bearing side condition + the concrete improvement: turn the value head on). CONTRACT-ONLY
boundary @contractDescentOnRealDataUnproven@: this proves IDENTIFIABILITY, NOT that GD reaches the optimum on
real data (the retired DESCENT conjunct rested on one MaskedBandTrainer fixture and was removed in the
model-spec unification — see @SIXFOUR-MODEL.md@). Ported to the trainer byte-exact via
@Codegen.LearnabilityTheorem@→@trainer/generated/learnability_golden.json@. Additive),
"SixFour.Spec.Convergence" (★ the CONVERGENCE teaching, sibling of LearnabilityTheorem: the palette
objective is a CONVEX QUADRATIC whose UNIQUE global minimum is the target IFF w_value>0, so GD reaches it
with NO spurious local minima — closing the learnability theorem's delegated-descent caveat with a GENERAL
guarantee. Same discrete-geometry switch: cell Hessian ∝ S·Sᵀ is rank-3 (non-strict, non-unique min,
checkerboard in null space); value Hessian = 2I (strict, unique); composite strict IFF the full-rank value
term is weighted. @lawCellLossConvex@/@lawValueLossConvex@/@lawCompositeConvex@, @lawCellMinimizerNotUnique@,
@lawValueMinimizerUnique@, capstone @lawCompositeUniqueMinIffValueWeighted@, @lawConvexNoSpuriousLocalMin@,
@lawGradStepContractsToTarget@, @lawConvergenceGovernedByLatticeRank@. Emits no golden. Additive),
"SixFour.Spec.HeadConvergence" (★ the ViT value-head descent teaching, HONESTLY DECOMPOSED: head =
@readout ∘ trunk@; the READOUT (last linear layer over fixed features) is convex in its weights
(@lawReadoutLossConvexInWeights@, Convergence output-convexity pushed through the affine @W↦W·φ@) and a
gradient step contracts to the unique min (@lawReadoutGradStepDecreases@, unique iff the feature is
informative — the feature-rank analogue of the lattice-rank story), so the last layer PROVABLY converges
(@lawReadoutConvergesGivenFeatures@). The TRUNK is PROVEN OUTSIDE that guarantee: a ReLU unit violates
Jensen (@lawTrunkLossCanBeNonConvex@), so end-to-end fine-tuning stays DEMONSTRATED (P4), not proven —
the scope boundary is itself a theorem (@lawHeadDescentScopeIsReadoutNotTrunk@). Emits no golden. Additive),
"SixFour.Spec.TrunkLinearization" (★ the HONEST PARTIAL trunk-convergence bound HeadConvergence left open: a
CONDITIONAL theorem. IF the trunk is in the LINEARIZED (lazy\/frozen-tangent) regime — output affine in ALL
params around an anchor (@lawLinearizedOutputAffineInParams@) — THEN training reduces EXACTLY to the convex
readout problem (@lawLinearizedLossIsReadout@: the linearized loss IS @HeadConvergence.readoutLoss@ over the
Jacobian as fixed features and the param delta as variable), which converges (@lawLinearizedLossConvexInParams@
+ @lawLinGradStepDecreases@ + delegates @HeadConvergence.lawReadoutConvergesGivenFeatures@). The genuine NTK
reduction, checked not asserted (imports HeadConvergence as a real consumer). NAMED precondition, with TEETH:
@lawLinearizationFailsAcrossKink@ — the lazy surrogate of a ReLU unit disagrees with the true unit across the
kink (the activation flips), exactly the region @HeadConvergence.lawTrunkLossCanBeNonConvex@ proves non-convex,
so the precondition is non-vacuous and the bare trunk is the uncovered case. Capstone
@lawConditionalTrunkConvergence@: the reduction is PROVEN, unconditional trunk convergence stays DEMONSTRATED
(P4). Emits no golden. Additive),
"SixFour.Spec.Generalization" (★ the GENERALIZATION teaching, why held-out follows train (not memorization):
the data-manufactured target is a SEED-INDEPENDENT pure function @T@ of the input, so train & held draw from
the SAME map — NO distribution shift. Held error decomposes into exactly two NAMED parts: input COVERAGE +
the irreducible masked-band residual (visible-context conditional mean, the +88% reachable oracle), NEVER a
shift gap. @lawTargetMapIsSeedIndependent@ (teeth: a seed-leaking target would break it), @lawNoDistributionShift@,
@lawHeldErrorIsCoverageNotShift@ (on-support exact), @lawHeldReachableFromContext@ (delegates AboveFloorMargin),
capstone @lawModelGeneralizesUpToCoverage@. Lifts the empirical test_detail_reachable to a theorem. Emits no golden. Additive),
"SixFour.Spec.BlindComplementIsA7" (★ the ANT-LOAD-BEARING bridge: the cell objective's BLIND complement IS
the mean-free @A_7@ detail lattice — NOT a rename of the rank argument but a REAL typed consumer. The
checkerboard @cb(v)=(−1)^popcount(v)@ that @cellLoss@ cannot see (Convergence null space) has @Σ cb = 0@, so
"SixFour.Spec.RootLatticeDetail" @mkMeanFreeChecked@ ADMITS it as a @MeanFree@/@A_7@ vector; a non-mean-free
@e_0@ is REFUSED (teeth). So what the rank-3 cell loss misses = the @A_7@ subspace the value head recovers
(LearnabilityTheorem), making the lattice load-bearing in identifiability/convergence. @lawCheckerboardIsMeanFree@,
@lawBlindDirectionIsLatticeVector@, @lawNonLatticeDirectionRefused@, capstone @lawCellBlindComplementIsA7@.
Emits no golden. Additive),
"SixFour.Spec.IdentifiabilityIsA7Bridge" (★ the owner-requested FOLD, staged additively: conjoins
"SixFour.Spec.ParadigmSoundness" @teachingIdentifiability@ with "SixFour.Spec.BlindComplementIsA7"
@lawCellBlindComplementIsA7@ so the @A_7@ membership of the recovered complement (load-bearing only via the
@mkMeanFreeChecked@ typed consumer) becomes a guard on the master theorem's IDENTIFIABILITY conjunct, ready
to inline into @ParadigmSoundness@. HONEST scope: claims only @cb ∈ S^⊥∩A_7@ (not that all 15 blind DOF are
lattice). Teeth reuse @lawNonLatticeDirectionRefused@ (a non-mean-free @e_0@ cannot masquerade). Capstone
@lawIdentifiabilityComplementIsA7@. Emits no golden. Additive),
"SixFour.Spec.CoverageMonotone" (★ the PROVABLE part of the generalization-coverage story, separated from the
empirical threshold: "SixFour.Spec.Generalization" names coverage only as a DATA CONDITION; this proves coverage
is a MONOTONE set function over its @generator@/@targetMap@ — if run A's seen inputs ⊆ run B's, then B's
held-error set ⊆ A's (more data weakly REDUCES held error). Plain set-monotonicity, NO numeric multi-day
threshold (that stays empirical). @lawCoverageMonotone@ (the antitone-in-error lemma); teeth
@lawForgetfulLearnerBreaksMonotone@ (a forgetful learner FAILS it ⇒ non-vacuous), @lawDisjointInputAlwaysInError@
(a constant-detail tuple the generator can never emit stays in error for every run ⇒ no conjuring),
@lawOnSupportZeroHeldError@ (on-support exactness inherited); capstone @lawCoverageIsMonotoneSetFunction@.
Emits no golden. Additive),
"SixFour.Spec.BlindComplementGeometry" (★ the PRECISE geometry behind BlindComplementIsA7, the honest
audit refinement: the cell-blind complement @S^⊥@ (5-dim/channel, 15 across OKLab) and the lattice @A_7@
(7/channel, 21) are DISTINCT — neither contains the other — so "the 15-DOF blind complement IS @A_7@" is
too strong. @lawCheckerboardInBlindAndA7@ (the sound CORE: cb ∈ S^⊥∩A_7), @lawBlindDirectionOutsideA7@
(S^⊥⊄A_7: the origin bump @e_0@ is BLIND to @cellLoss@ yet Σ=1, refused by @mkMeanFreeChecked@ — the very
vector BlindComplementIsA7 calls "not the blind complement"), @lawA7DirectionSeenByCell@ (A_7⊄S^⊥: @x−y@ is
a legal residual the cell loss SEES), @lawBlindAndA7DimsDiffer@ (exact @rankQ@: 15≠21, overlap 12). Capstone
@lawBlindMeetsA7InMeanFreeBlind@: the @A_7@ algebra is load-bearing on the mean-free blind OVERLAP
@S^⊥∩A_7@ (12-DOF, where cb lives), not the whole blind complement. Reuses @Convergence.cellLoss@ +
@RootLatticeDetail.inA@. Emits no golden. Additive),
"SixFour.Spec.LatticeRankComputed" (★ the AUDIT that de-vacuifies the rank claim the whole
convergence\/identifiability story rests on: "SixFour.Spec.Convergence" @lawConvergenceGovernedByLatticeRank@
asserts @spaceRank == 3@ but @spaceRank@ is a HARDCODED literal @3@ (Convergence.hs:200), so the conjunct is
literally @3 == 3@. This module @computeRank@s @Convergence.spaceLattice@ AS DATA by exact rational Gaussian
elimination: @lawSpaceLatticeRankIsThree@ (measured, not asserted), @lawComputedRankMatchesConvergenceLiteral@
(the literal was correct — now proven), @lawDegenerateLatticeRankIsTwo@ (the TEETH a constant @=3@ cannot
pass: drop-t and collinear-t lattices compute @2@), @lawCheckerboardInLeftNullSpace@ (@Sᵀ·cb=[0,0,0]@ by
exact integers — the membership Convergence only asserts in prose), @lawInSpanPerturbationSeen@
(@Sᵀ·colX=[4,2,2]≠0@ ⇒ the test discriminates). Capstone @lawRankClaimIsComputedNotAsserted@. Elementary
linear algebra kept elementary (NOT Euclidean-domain\/Galois dress). Imports only @Convergence@. Emits no
golden. Additive),
"SixFour.Spec.ParadigmSoundness" (★★ THE MASTER THEOREM: the one browsable capstone conjoining ALL NINE
necessary teachings of the self-supervised paradigm — SIGNAL (AnchorDiagnostic d6/ℤ[i]) ∧ EXPRESSIVITY
(AboveFloorMargin/A7) ∧ IDENTIFIABILITY (LearnabilityTheorem) ∧ CONVERGENCE (Convergence, the GENERAL
unique-min-reachable guarantee, not the golden fixture) ∧ NO-COLLAPSE (VarianceFloorGuard) ∧ ANTI-CHEAT
(JepaTarget: data-manufactured target, collapse rejected, constant orbit misses a moved frame) ∧ DETERMINISM
(ByteCarrier/Q16 byte-exact re-entry) ∧ HEAD-CONVERGENCE (HeadConvergence: the actual ViT readout converges,
trunk scoped out) ∧ GENERALIZATION (Generalization: held follows train, no distribution shift). Scoped to
STRUCTURAL soundness: @lawParadigmIsStructurallySound@ TRUE at w_value=1, @lawStructuralSoundnessNeedsValueHead@
proves it FALSE at w_value=0 (load-bearing side condition). NOT an empirical-training claim — the gap that the
model actually trains on real captures is @contractEmpiricalSoundnessUnproven@ (the only run floored). Each
conjunct DELEGATES to a green teaching, so a regression in ANY teaching breaks here. Emits no golden. Additive),
"SixFour.Spec.ValueWeightThreshold" (★ the AUDIT CLOSE on the convergence side condition: proves the
@w_value > 0@ threshold @paradigmStructurallySound@ guards on, and that @Convergence.lawCompositeUniqueMinIffValueWeighted@
witnesses only at the two points 0 and 1, is EXACT over the WHOLE weight domain. The cell-blind checkerboard
shift makes the shifted-vs-target gap linear in the weight (@shiftedGap w = 4·w@, slope = the full-rank
@valueLoss = 4@), so the target is the unique global min IFF @w > 0@ for EVERY weight. Closes the two regimes
the two-point witness left open: @lawFractionalWeightStillUnique@ (0<w<1 still unique), @lawNegativeWeightBreaksGlobalMin@
(w<0 is fatal — target not even the min, stronger than the w=0 tie). @lawShiftedGapIsLinearInWeight@ (exact
closed form, non-degenerate slope), capstone @lawConvergenceThresholdIsExactlyZero@, bridge
@lawParadigmGuardIsExactlyConvergenceThreshold@ (the guard == @convergesAt@ weight-by-weight). Reuses
@Convergence.composite@/@checkerboard@/@valueLoss@ + @ParadigmSoundness.paradigmStructurallySound@. Emits no golden. Additive),
"SixFour.Spec.ParadigmRobustness" (★ the AUDIT CLOSE on the SEED residue of PARAMETRIZATION-GAP-1:
@ParadigmSoundness.teachingConvergence@ is a @:: Bool@ constant pinned at ONE hardcoded 24-element seed, so the
master theorem's convergence conjunct is single-witness on the INPUT/TARGET axis. Lifts the pinned constant to a
universally-quantified predicate @paradigmConvergesAt :: Double -> [Double] -> Bool@ (the @(wv>0 && teachingConvergence)@
clause with the frozen seed freed), reusing @Convergence.lawCompositeUniqueMinIffValueWeighted@/@lawConvexNoSpuriousLocalMin@'s
already-seed-parametrized signatures. Proves it for ALL seeds: @lawConvergesAllSeedsAtPositiveWeight@ (True at wv=1,
QuickCheck over randomized seeds — a lucky-seed result fails), @lawDivergesAllSeedsAtZeroWeight@ (False at wv=0
universally, load-bearing for every seed not one), @lawPinnedConstantIsOneInstance@ (@paradigmConvergesAt 1 pinnedSeed
== teachingConvergence@, the constant is representative not cherry-picked), keystone
@lawSeedChoiceIsWithoutLossOfGenerality@ (the conjunct's truth is seed-INVARIANT, so the pin is harmless),
corollary @lawSeedWeightThresholdIsZeroForAllSeeds@ (the weight threshold is exactly 0 for every seed). The SEED
axis of the capstone — NOT a rename of @ValueWeightThreshold@ (the WEIGHT axis) nor @GlobalUniqueness@ (the
DIRECTION axis). Reuses @Convergence@ laws + @ParadigmSoundness.teachingConvergence@. Emits no golden. Additive),
"SixFour.Spec.GlobalUniqueness" (★ the AUDIT CLOSE on OVERCLAIM-CONVERGENCE-1: the docstring claimed a UNIQUE
global minimum but @Convergence@/@ValueWeightThreshold@ examine only the ONE cell-blind checkerboard direction.
Global uniqueness over all 24 DOF is STRICT convexity of @composite w@ for @w>0@, which the @≤@-chord laws
(convexity only) never give. Proves it directly: the Jensen gap splits exactly @jensenGapCell + w·jensenGapValue@
(@lawJensenGapDecomposesByRank@); the full-rank value gap @= ½λ(1−λ)‖p−q‖² > 0@ for distinct @p,q@
(@lawValueGapStrictPositiveFullRank@) while the rank-deficient cell gap is FLAT along @cb@
(@lawCheckerboardDirectionCellBlind@). Hence STRICT @<@ for arbitrary distinct @p,q@ at @w=1@
(@lawStrictGapArbitraryDistinctAtUnitWeight@), uniqueness genuinely needs @w>0@ even in the cell-blind direction
(@lawStrictConvexityNeedsValueWeightInBlindDirection@: @w=0@ ties, @w>0@ strict), strict in EVERY direction not
one witness (@lawStrictlyConvexEveryDirectionAtPositiveWeight@), capstone the target is the UNIQUE global min iff
@w>0@ (@lawTargetUniqueGlobalMinIffValueWeighted@; degeneracy @p==q@ excluded by @lawDegenerateDirectionGivesEquality@).
Strict-vs-non-strict convexity is a real distinction the chord laws never make — NOT a rename of @ValueWeightThreshold@
(that swept the WEIGHT axis on one fixed direction; this sweeps the DIRECTION axis). Reuses @Convergence.composite@/@cellLoss@/@valueLoss@/@checkerboard@. Emits no golden. Additive),
"SixFour.Spec.NudgeContamination" (★ the collapse-safety QUARANTINE for a USER nudge — a taste
steer enters ONLY the invented detail (the latent tail) and CANNOT move the self-supervised energy,
which lives in the gated coarse/DC band. @applyTaste@ re-feeds the cube's ORIGINAL coarse (structural
type quarantine); @lawUserNudgeIsTasteOffEnergy@ = @redownsample (applyTaste …) == redownsample cube@
+ gate still passes (the priority-1 law the L,a,b nudge design language rests on);
@lawLeakyCoarseNudgeDriftsEnergy@ = teeth (a coarse-pan DOES drift, gate rejects);
@lawTasteNudgesShareGateNullSpace@ = taste == invented detail, one null space. Composes
@RedownsampleGate@. Additive),
"SixFour.Spec.DeltaGesture" (★ binds a UI drag to the two delta carriers so the ALGEBRA is the
hand-feel: @stackColourDrags@ ADDS (@lawColourDragAdds@/@lawColourDragCommutes@, abelian ℤ-module,
the elastic SwatchVector) vs @chainIndexDrags@ COMPOSES (@lawIndexDragComposes@/@lawIndexDragOrderMatters@,
non-abelian transport, the directional TransportRibbon with no stack verb). Composes @HierarchicalDelta@. Additive),
"SixFour.Spec.TriScaleBench" (★ the tri-scale comparison contract — a 16³ change is comparable to a
256³ change ONLY at the coarse band. @twoRungLift@ = one octant operator twice;
@lawSixteenComparableAtCoarseOnly@ = re-downsampling the 256³ recovers the 16³ seed + 64³ capture
exactly, tail-blind; @lawTailHasNoCoarseFootprint@ = two tails ⇒ same coarse, different 256³ (so the
comparison is well-posed at coarse, a category error at fine). Composes @RedownsampleGate@/@NudgeContamination@. Additive),
"SixFour.Spec.GestureAxis" (★ the keystone ARROW: a screen swipe ↦ a Dim6 search axis + signed step,
COMMITTED through the domain guard. @gestureSafeNudge@ = @DetentNudge.stepDelta@ routed through
@RelationalResidual.safeNudge@ axis-by-axis (the compose no module did); @lawGestureRoutesThroughGuard@ +
@lawGestureRefusesAtEdge@ (refuses at @a=B@) = can't bypass the @RC_OUT_OF_RANGE@ guard;
@lawGestureTargetsSearchAxes@ = moves only @{a,b}@, carrier @{L,t}@ fixed; @lawGestureColourHasPositionTwin@ =
@phi6@ pairs @a↔x,b↔y@. SWIFT-COREAI/DisplaySide. Additive),
"SixFour.Spec.ScaleSurface" (★ the grid EXCEPTION for the Tri-Scale Bench — the @256³@ super-res
surface renders into the SAME on-screen footprint as the @64³@, decoupling DISPLAY footprint (cells)
from CONTENT resolution (pixels). @rungDisplayCells@ uniform (= @previewCells@); @lawSuperResShareFootprintWith64@
= @256³@ == @MovableLayout.Field64@'s footprint ("256×256 same size as 64×64"); @lawFootprintIndependentOfResolution@
= the exception as a theorem; @lawSuperResIsDensityNotSize@ = 4× density not size. Re-pins NOTHING (the
ColorIdentity alphabet + move-golden untouched). SWIFT-COREAI/DisplaySide. Additive),
"SixFour.Spec.PerceptualEncoder" (★ ENCODER B of the dual-encoder H-JEPA — the GIF as a
PERCEPTUAL point cloud over the six axes @(L,a,b,x,y,t)@: @perceptualEmbed@ maps each
@Cube@ voxel to a @P6@ (colour from the channels, position @(x,y,t)@ from @mortonToXYT@
de-interleave), @perceptualDistance@ = @RelationalMemory.d6@. @lawPerceptualEmbedsAllSixAxes@
= total + injective position lift, @lawPerceptualReusesD6@ = distance is d6 and
position-aware. Thin read-only adapter over the in-flight L/t memory. Additive),
"SixFour.Spec.GifDualView" (★ KEYSTONE of the dual-encoder H-JEPA — one @GifObject@, two
encoders, the commutative square proving they are the SAME object: @viewA@/@decodeA@ =
construction (palette+index via @palettizeExact@), @viewB@/@decodeB@ = perceptual cloud.
@lawSameObjectBothViews@ = both views decode to the SAME pixels, @lawSectionEmbedsLossless@
= Encoder B is a lossless section (with teeth), @lawRetractionRoundTrip@ = @palettizeExact@
is a section of @buildPixels@. Unbounded-budget (lossless) end; the budget gap is
CrossEncoderDistance. Additive),
"SixFour.Spec.CrossEncoderDistance" (★ the DISTANCE between the two semantics — the lossy
fixed-budget retraction @palettizeBudget@, @constructionDistortion@ = the @d6@-sum gap
between Encoder A's budgeted rebuild and Encoder B's faithful cloud, @axisDistortion@ = that
gap projected per "SixFour.Spec.Dim6" axis. @lawPerAxisDistortionSumsToTotal@ = the six
axis-distortions partition the total exactly ("the distance between L,a,b,x,y,t"),
@lawDistortionZeroIffLossless@ = zero iff palettizable within budget,
@lawDistortionIsPseudometric@ = a genuine metric (delegates @RelationalMemory.d6@). Additive),
"SixFour.Spec.CoarseIsPalette" (★ the @16²=256@ bridge as a COMPILE-TIME theorem —
@PaletteCells = 16*16@, @coarseEqPalette :: PaletteCells :~: 256@ is @Refl@ (GHC proves it);
a coarse 16³ frame has 256 cells = a palette, so @coarseToPaletteStack@ reshapes the cube
into 16 typed @QPalette PaletteCells@. @lawCoarseFrameSizeIsPaletteSize@ = 16 is the unique
palette-sized side (teeth: 64,256 are not), @lawCoarseIsStackOfPalettes@ = bijective reshape,
@lawCoarsePaletteComparesToPerFrame@ = at 16³ the construction palette EQUALS the perceptual
colours (encoders coincide; the Analysis-rung exactness). Additive),
"SixFour.Spec.ScaleIndexedCorrespondence" (★ the H-JEPA ANSWER — the correspondence between
the two encoders is a HIERARCHY indexed by the scale spine: @correspondenceAt@ assigns
@Exact@ at Analysis 16³ (delegates @CoarseIsPalette@), @Lossy@ at the 64³ Pivot (delegates
@CrossEncoderDistance@), @Invented@ at Synthesis 256³ (delegates @SelfSimilarReconstruct@).
@lawCorrespondenceHierarchyMatchesScaleSpine@ = the three DISTINCT kinds match the scale
spine (delegates @HJepaLevels.lawScaleIsTheSpine@) — "there is a hierarchy here". Additive),
"SixFour.Spec.DualEncoderJepa" (★ the REDESIGNED I-JEPA — a DUAL-ENCODER objective predicting
a masked band of one encoder from the VISIBLE CONTEXT OF THE OTHER. @bOnlyLoss@/@jointLoss@ =
the information floors of B-context vs joint (A,B) context. @lawCrossEncoderContextStrictlyHelps@
= KEYSTONE: the joint predictor strictly beats B-alone when A resolves a collision (with
redundancy teeth proving it is a real separation), @lawDualTargetIsDataManufactured@ = no EMA
no collapse (delegates @JepaTarget@), @lawDualReusesScaleSpine@ = the cross-prediction IS the
H-JEPA hop (delegates @HJepaLevels@), @lawNoEncoderBypassesQ16@ = both commit through
@reenterQ16@ (delegates @EncoderFrozen@). Additive),
"SixFour.Spec.MinimalInstructionSet" (★ the MINIMUM decode-instruction set for "16³+data" in
BOTH encoder forms — A: 16 ordered palettes / NO index map (@lawSixteenPalettesSuffice@,
delegates @CoarseIsPalette.decodeAPalettesOnly@ + @ConstructionEncoder.identityIndex@); B: the
L carrier over (x,y,t) with chroma demoted to data, a LOSSY skeleton (@bSkeleton@,
@lawBSkeletonIsLossy@ closed witness, @lawChromaIsSearchResidual@ delegates @Dim6@). The duality
is ASYMMETRIC (@lawDualMinimalProjections@: A→B exact, B→A Invented; rides
@DualEncoderJepa.lawCrossEncoderContextStrictlyHelps@). Additive),
"SixFour.Spec.DitherLevel" (★ DITHER = the per-pixel continuous latent z (H-JEPA §4.6),
realized by a MOMENT-CONSERVING DECODER (@realizeStream@ via golden ordering): unbiased loop
mean (@lawRealizationUnbiased@) but NOT reversible at finite T (@lawRealizationIsNotReversible@,
distinct p → same stream), flicker peaks at p=0.5 (@lawDitherFlickerPeaksAtHalf@). Float
display side (METAL-GPU), NOT the Q16 floor. Delegates @Spec.Dither@. Additive),
"SixFour.Spec.MidLatentCrossPrediction" (★ the MIDPOINT-LOCAL cross-encoder objective — predict
one encoder's 32³ latent band from the other's 32³ context: @lawMidCrossEncoderStrictlyHelps@
(joint beats B-alone, both clauses, on midpoint witnesses), @lawMidObjectiveIsMidpointLocal@
(the organisable level, NOT the 16³→256³ hop; delegates @HJepaLevels@+@RungPivot@),
@lawMidTargetIsDataManufactured@ (no EMA; delegates @JepaTarget@). Additive),
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
"SixFour.Spec.DeviceTrainStep" (★ the V3.0 ON-DEVICE per-capture training gate: the capture manufactures
its OWN supervision pair (@supervisionPair = liftOct@, lossless by octant reversibility —
@lawSupervisionPairIsExact@), and the mean-gradient descent @trainDevice@ (η=0.2, 600 steps — the
@trainer/mlx/superres.py train_detail@ twin, batch-stable from the start) recovers the manufactured detail
EXACTLY through the Q16 crossing: @lawDeviceTrainedDetailIsGolden@ = THE TWIN (committed bands ==
@goldenDeviceDetail@ — the MPSGraph AND Metal-4 device trainers gate on these POST-COMMIT bytes; float
trajectories may differ per backend, the committed integers may not; fixture float32-robust by
construction), @lawTrainedDetailSurvivesCommit@ (delegates "SixFour.Spec.AboveFloorMargin"
@survivesCommit@ — the fine-tune moves off the floor for real), plus floor-start / loss-down / monotone /
batch-stable. Obligation @contractDeviceGoldenUnrunOnHardware@ (run the fixture ON the iPhone, B1/B2 in
@docs/V3-BUILD-WORKFLOW.md@). Law module over DetailPredictor+OctreeCell; emits
@DeviceTrainGolden.swift@ via "SixFour.Codegen.DeviceTrain"),
"SixFour.Spec.GeneTaxonomy" (★ the V3.0 GENE REGISTRY — every learned blob categorised by lifecycle
class (Germline=shipped base/Somatic=per-capture/Identity=per-user/Meme=shareable AirDrop layer) ×
train site × size, zero-gene==floor claimed per entry; THE CASCADE BOUNDARY AS A LAW:
@foldsIntoRungDispatch@ (weights+grads ≤ 32 KiB threadgroup) with @lawFoldBoundaryIsRealOnBothSides@ —
θ_up(21)/θ_cell(9) FOLD into the rung dispatch, time-rung(5,772)/value-pref(29,249) do NOT; sizes
DERIVED not asserted (@lawSizesAreDerivedNotAsserted@ imports DetailPredictor.paramCount +
MaskedBandPrediction.paramCountB); class⇒site coherence + germline-never-trains-on-device. Contract
registry — proofs live in the genes' own modules; emits no golden),
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
@{16³,64³,256³}@) · "SixFour.Spec.CaptureFormat" (Act IV, the ONE capture-wire contract: the app's exported GIF
@256²×64@ = the encoder's @64³@ input via @decimate2D ∘ replicate2D == id@; time UNSCALED at the wire — NOT
@upscale256@; sRGB8+index canonical, Q16 internal-only — @lawCaptureFormatSound@) · "SixFour.Spec.Upscale256" (Act IV, the residual-seeded @256³@ super-res of the export pack — a SEPARATE DETERMINISTIC ENDGAME consuming the @64³@ policy+value, zero learned trunk params; rungs labelled in @SynthesisPolicyValue.lawHeadsLiveAtLabeledRungs@)
· "SixFour.Spec.AtlasCascade" (Act IV, the two-cube cascade @ExitState@ — QUAD-literal carry/reset for the @64³ → 256³@ warm start).

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
@.GenomeFixed@, @.PaletteValue@, @.MLX@, @.CoreML@, @.Burn@, @.MaskedBand@ (the byte-exact theta_B forward),
@.Governance@ (the port-ready swap-economy slice: the derived sizes + a golden roster→ranked-order
contract; STAGED — not yet wired into the driver, awaiting the identity\/CloudKit decisions),
@.JepaData@ (the I-JEPA data-engine emitter), @.JepaHead@ (the theta_B training-trajectory
endpoints + 77-param position-head forward golden; @trainer/mlx/@ gate-forced), @.TemporalData@
(the inter-frame @(t,t+1)@ value/policy delta golden; @reconstructNext==ctNext@ true labels).

== 10. Look transfer / LUT extraction (R3D .cube)
The on-screen "look" and the exported 3D LUT are two projections of ONE OKLab palette→palette
transform derived from the captured palette's luminance-zone chroma profile (a port of
@~/lut-generator/src/python/gif_palette_lut.py@).

  * "SixFour.Spec.ZoneProfile"  — luminance-zone mean a/b/chroma profile of a palette
  * "SixFour.Spec.LookTransfer" — the chrominance-only transfer (preview ≡ cube core)
  * "SixFour.Spec.RedFrontEnd"  — Log3G10 decode + RWG→Rec.709 + filmic tonemap (LUT-driven, Q16)
  * "SixFour.Spec.CubeLut"      — the 65³ .cube grid builder

== 11. Economy & governance — the swap/guild social layer
The closed, no-money economy over the gene weights: users swap tiny 16³-GIF-fronted genes, and
reputation\/affiliation\/governance are pure FOLDS of the trade ledger (no money ⇒ no IAP tax). The
app-social layer (destined for Swift + CloudKit public DB + Game Center), still pure spec today.

  * "SixFour.Spec.Trade"      — the SUBSTRATE: an append-only trade ledger with HYBRID grant
    semantics (accept GRANTS, never strips ⇒ holdings monotone); the demand\/reliability scalars the
    rank\/trust axes fold from it.
  * "SixFour.Spec.GuildScale" — the EARNED social-body sizes: council = largest odd within Miller's
    span (7), guild cap = Dunbar cohesion ceiling (150), schism past the cap; odd is load-bearing
    (breaks ties + unique majority-judgment median).
  * "SixFour.Spec.Governance" — a guild's CONSTITUTION as a pure ranking function (@govern@):
    meritocracy \/ gerontocracy \/ majority-judgment \/ monarchy over ledger-folded members; the
    council is the top 'councilSize'. Default majority judgment ties only on equal grade multisets.
  * "SixFour.Spec.Lineage" — the content-addressed gene GENEALOGY DAG (creator + parents per gene);
    @influence = |descendants|@ is the lineage rank scalar, acyclic by construction.
  * "SixFour.Spec.SwapCarrier" — ★ the swap-economy WIRE: a second GIF89a Application-Extension
    block (@S4GX@, coexists with @S4GN@) carrying one tradeable gene + its lineage tag; the Trade
    hybrid model as BYTES (a Showcase serializes NO weights and expresses as the floor; @mintGrant@
    consults the ledger, so a working Grant exists only for the creator or a settled trade's parties).
  * "SixFour.Spec.GeneSimilarity" — gene similarity as a PULLBACK pseudometric (the GeneAtlas
    retrieval metric): a flat θ is never compared word-by-word — it is EXPRESSED on a pinned probe
    lattice (real @predictDetail@, Q16 commit inside) into a P6 cloud and @cloudDistance@ is pulled
    back (pseudometric by theorem; gauge quotient: identical expression ⇒ distance 0; the
    int→float→int sandwich is the port map).
  * "SixFour.Spec.DescriptorQuasiIsometry" — the descriptor ADMISSIBILITY GATE: promotes the
    'GeneSimilarity' pullback PSEUDOmetric to a TWO-SIDED additive quasi-isometry on the Q16 floor
    (no COLLAPSE, no DISCONTINUITY), so a learned encoder may stand in for @expressGene@ only if it
    preserves distance both ways. Keystone = the per-band probe design is a full-rank Vandermonde
    over ℤ (det 2), the algebraic certificate that @c1>0@; distortion @κ = c2\/c1@ bounded, never
    an identity.
  * "SixFour.Spec.PacketEconomy" — DECODE-COMPUTE is the scarce resource genes compete for:
    encode is cheap, decode spends S\/K\/I packets (@I@=free floor read, @K@=pool, @S@=weighted
    invent where the gene lives), and a gene is an elite only if not Pareto-dominated on
    (meaning UP, packets DOWN). The two fitnesses are DISJOINT (objective "does something" above a
    HELD target = admission; social attention dormant), so no global scalar collapses the atlas;
    selection order is integer meaning-per-packet (cross-multiply, no divide).
  * "SixFour.Spec.CombinatorExactSequence" — S\/K\/I ARE the three canonical maps of the octant
    short exact sequence @0 -> detail -> fine -> coarse -> 0@: K = the surjection (forgets detail,
    'scalarCollapseLossy'), I = the splitting (the reversible lift 'liftOct'\/'unliftOct', exact iso,
    work 0), S = a SECTION (invent a detail representative, @K.S=id@ on the coarse). The gene lives
    on S because a section is the only one of the three not canonically determined by the sequence;
    @S.K/=id@ and the residual @v@ vs @S(K v)@ is what training minimizes.
  * "SixFour.Spec.GeneRecombination" — SEXUAL, BALANCED crossover: a per-word Q16 lerp of two
    parent θ blobs (linear head ⇒ no Git-Re-Basin), child commits BOTH parents (acyclic DAG),
    grantable only to someone holding BOTH parents (lineage-keyed, closes single-parent laundering);
    'recombine' has no @Ledger@, so crossover mints no credit.
  * "SixFour.Spec.PaintOrderPrior" — the paint FIRST-TOUCH order seeds the PonderNet halting prior
    on the A7 rung ladder: earliest touch ⇒ lowest @λ_p@ ⇒ deepest read ⇒ most packets. Keystone is
    a PERMUTATION-PAIR property, so a magnitude-only policy (ignoring order) is structurally
    forbidden; packets are conserved under permutation (reallocated, never inflated).
  * "SixFour.Spec.AnytimeDecode" — partial decode NEVER fails: reading k bands is a strict PREFIX of
    the full decode over the additive 'unliftVec' (a successive-refinement code), and depth-0 (the
    coarse floor = Showcase = FloorExact) is always reachable via the total zero-detail octant expand.
    A tail-dependent decoder is provably rejected.
  * "SixFour.Spec.BudgetHead" — the two-headed gene's ADVISORY budget head (learned estimator
    Tier-1 stub): it estimates a per-rung packet schedule but only gates the @Maybe [Detail]@ fork
    of the decode, so a wrong estimate lands on a coarser point of the SAME ladder, never off it
    (keystone = only the Maybe-fork routing is floor-safe, an adversarial 'DecodeStrategy' family).
    The advisory rides tag-adjacent, excluded from tag identity, swapMinor-only.
  * "SixFour.Spec.GeneHash" — the CONTENT-ADDRESS itself: a 'GeneId' is FNV-1a over a canonical
    preimage that INCLUDES the parents, so the address commits to ancestry. 'mint'\/'buildFrom' can
    only remix pre-existing genes, which turns Lineage's "acyclic by construction" into a THEOREM
    ('lawBuiltGenealogyAcyclic'). Injective serialisation ('lawCanonicalRoundTrip'); byte-exact to
    hand-port.
  * "SixFour.Spec.DerivationLog" — genealogy as a FOLD of an append-only derivation log (the lineage
    sibling of the trade ledger). Self-verifying content-addressed events; the fold is
    ORDER-INDEPENDENT + IDEMPOTENT + MONOTONE (a Merkle-CRDT in miniature), so concurrent creators
    converge to the same DAG with no coordination. 'logFromOps' bridges GeneHash transcripts to a
    gossip-able log that folds back acyclic ('lawReconstructedGenealogyAcyclic').
  * "SixFour.Spec.LedgerCRDT" — PROOF that the trade ledger is a Grow-only-Set CvRDT: the grant set is
    a join-semilattice (union merge, commutative\/associative\/idempotent), the fold a monotone
    homomorphism, so it earns STRONG EVENTUAL CONSISTENCY (Shapiro et al.) — same trades ⇒ same
    holdings regardless of gossip order. 'lawHoldingsFromState' pins it to the shipped 'Trade.holdings'.
  * "SixFour.Spec.SigChain" — TAMPER-EVIDENT authorship: a per-creator append-only, hash-linked chain
    of __Ed25519__-SIGNED authorship attestations, so Lineage's @gtCreator@ becomes public-key-verifiable.
    The hash chain and the signatures each do load-bearing work (a re-signed interior splice is still
    caught by the successor's back-pointer).
  * "SixFour.Spec.Sha512" — SHA-512 (FIPS 180-4), hand-written & byte-exact (NIST known-answer vectors),
    the hash Ed25519 is built on.
  * "SixFour.Spec.Ed25519" — Ed25519 (RFC 8032), hand-written & byte-exact on the twisted-Edwards curve
    over @2^255-19@, gated against RFC 8032 + OpenSSL known-answer vectors. Real public-key signatures,
    zero third-party dependency — the signing primitive under SigChain.
  * "SixFour.Spec.Affiliation" — GUILDS as connected components of the trade graph (affiliation is
    behavioural — who you swap with); the partition is exact, oversize components schism at 'guildCap'.
  * "SixFour.Spec.Role" — the specialist↔generalist spectrum = @effectiveGenomeDim@ (participation
    ratio of a creator's genes in genome space; same math as "SixFour.Spec.Diversity" @effectiveDim@,
    lifted to N-D). Metric proven now on synthetic extremes; named cut-points await a real corpus.
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none
module SixFour.Spec.Map () where

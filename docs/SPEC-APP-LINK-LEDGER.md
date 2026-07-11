# SPEC→APP LINK LEDGER (2026-07-11)

Daniel's directive: "chase every missing link and promote them." This ledger is
the audit of ALL 270 spec modules against their app-side adoption, and the
disposition of every missing link — promoted, queued with scope, or explicitly
dispositioned with the reason in Daniel's own prior rulings. Nothing is
silently skipped. (Full per-module tables: the 3-slice audit of 2026-07-11;
tallies below. Statuses: LIVE = wired on a live path; GATED = twin exists
behind an off flag; KERNEL/CONTRACT-ONLY = floor or contract exists, no
runtime consumer; SPEC-ONLY = proven math, zero app trace; MAC-SIDE/WALL = by
design.)

**Tally (270): LIVE ≈93 · GATED 13 · KERNEL-ONLY 1 · CONTRACT-ONLY 10 ·
SPEC-ONLY ≈84 · MAC-SIDE ≈45 · WALL ≈28.** The spine is mostly linked; the
misses cluster in five product areas: the loop seam, ingest (import half of
self-containment), training honesty, paint/gesture intent, and super-res.

---

## A. PROMOTION QUEUE (every actionable missing link, ordered)

### Wave 1 — small, pure, this-session (no UI composition; unit-committed)
> **STATUS: COMPLETE 2026-07-11 (commits a0f76d6, a1c0e68) — all 5 promoted,
> suite 478/478 green.**
1. **CaptureFormat import half** — `decimate2D` exists (Generated contract) but
   there is no first-class ingest: GIF file → canonical 64-side `Loop`.
   Promote: `Loop` gains the canonical-ingest view (decode + decimate),
   law-tested. Closes self-containment's missing direction (re-ingest for
   training/editing).
2. **AboveFloorMargin** — the training GO/NO-GO margin (invented detail must
   beat half-Q16-LSB to survive the commit) is contract-only while θ_up
   TRAINS LIVE unchecked. Promote: the margin becomes the checked criterion in
   the somatic-training verdict.
3. **SuperResPalette (+ScaleSurface brand)** — Upscale256 is live but its ≤K
   palette brand is unenforced. Promote: enforce + test on the 256³ output
   path.
4. **QuartetDelta** — Swift twin + golden exist, zero callers. Promote:
   compute the 4-frame palette-motion readout at commit (data first — log +
   available to Review; UI surfacing follows the device-fit rule later).
5. **LabTransition** — pool-before-valve ordering is convention, not contract.
   Promote: a checked assertion at the ladder-pool → OKLab boundary + test.

### Wave 2 — kernel/record work (next sessions; spec-read first, then port)
6. **TemporalLoop** (the ONE KERNEL-ONLY) — proven seamless 64-frame loop
   closure (period-2⁶ Q16 cosine + low-freq temporal residual); temporal-Haar
   half ships, closure kernel uncalled. Promote at burst composition; pairs
   with **CanonicalPhase** (loop first-frame gauge — loop identity/dedup),
   which needs its kernel written. THE looping-GIF mechanic.
7. **PaintOrderPrior capture half** — record first-touch ORDER in the paint
   grid (today only magnitude survives, so the proven order→halt prior is
   unexpressible). Small data-model change, real training payoff. With
   **MixSKI** (paint = section of the K-chain) it makes v3 somatic training
   consume paint intent.
8. **DetailEntropy** — integer histogram entropy over detail bands (bit-budget
   honesty); new s4 kernel from spec, golden-gated.
9. **PairedResidual** — capture-anchored 256³ super-res (residual codebook
   keyed by coarse value). The export-quality spine; replaces the dead
   NetSynth256 scaffold direction.
10. **LabBleed codegen** — emit the RGB↔Lab coefficient matrix from the spec
    instead of hand-copies per tier (kills a tier-drift bug class).
11. **GMM** — assemble the (μ,Σ,w) palette mixture the device already has
    moments for, as the look-NN input surface (feeds the Temporal PaletteNet
    plan).
12. **AtlasCascade** — the spec claims a byte-for-byte Swift mirror of the
    64³→256³ cascade ExitState that was never written. Write it (with 9).
13. **Gif89aDecode factorization / CoarseIsPalette / ConstructionEncoder** —
    deepen the ontology: 16² coarse frame IS a palette (encoder A≡B), the
    rung→{palette,index,dither} factorization as Loop-level laws.

### Wave 3 — interaction models (DESIGN GATE: device-fit mockup BEFORE build,
per feedback_sixfour_device_first_ui; each needs Daniel's screen sign-off)
14. **ContinuousLoop + DisplayDecoder + LatentNavigation/NudgeStep/
    LatentProjection/MoveSignal** — the proven live-steering model (one
    latent, quarantined lossy preview, commit-on-demand with bit-identical
    committed bytes). A whole coherent UX sitting unbuilt; the spec's own
    "continuous-infer" phase.
15. **CubeBrush** — rung-typed depth-granting paint (pointwise-max semilattice,
    order-free undo) replacing the flat mask.
16. **ChromaRotation + DetentNudge** — the chroma-turn gesture chain
    ("Frontier 1c's missing wiring").
17. **FidelityLadder / ChoiceTraining / TwoMoveOctave / PaletteGesture /
    WidgetDescriptor / HaarRibbon+Loom (V2-global) / PullField** — product
    decisions; queued behind 14–16.

### Verification debts (not promotions)
- GeneLibrary LIVE* four (Governance/GuildScale/Lineage/GenomeCarrier):
  shipped twins, no UI caller found — reachability pass owed.
- NetSynth256 (OctreeGenome): contract-only scaffold, already on the Stage 2
  delete list.
- ScaleIndexedCorrespondence: header unread in the sweep; classify on touch.

## B. DISPOSITIONS (missing links that stay missing, with reasons)
- **GATED 13** (MultiScaleCapture/Integrate, HaltDepth, RenderSelect,
  GlobalCollapseQ16, GroupRGBT, V21Field/UI/Transport, RedFrontEnd,
  CaptureDiversity, RungReadDisplay, LadderExport-adjacent): STAGED by
  Daniel's own flag decisions (V2 global palette, device-only ladder bring-up,
  v21 field, LUT deprecation). Not misses; they flip with their arcs.
- **MAC-SIDE ≈45** (Encoder*/Jepa*/Ponder*/TriScale*/Sinkhorn/Bures/…): the
  trainer's half of the train/deploy split — by design.
- **WALL ≈28** (Q16, Sided, ByteCarrier-walls, GaussianLadder, EventEncoding,
  proof capstones): boundary definitions and theorems whose MECHANISMS are
  already live; nothing to port.
- **Proof-only SPEC-ONLY** (Generalization, LearnabilityTheorem,
  ParadigmSoundness/Robustness, ValueWeightThreshold, TrunkLinearization,
  XYTLabDuality, SameObjectInvariance, identifiability folds, …): mathematics
  ABOUT the system, not components OF it. Their value is realized when the
  trainer they de-risk runs (Stage 3+).
- **Superseded / retired lineages** (StageA → QuantFixed; GestureAxis and the
  Core-AI display side — retired 2026-06; OctreeForward → ABSurface;
  H-JEPA-target family (MatrixTarget/HeldOutTarget/GifDualView/HJepaLevels/
  MidLatentCrossPrediction/JepaTarget/LargeJepaHead) → the rebuild's model
  plan replaces the full-matrix H-JEPA direction, plan §1.1): absorbed or
  superseded by newer rulings.
- **Social layer LOW** (Affiliation, DerivationLog, Ed25519, Sha512, SigChain,
  Role, LedgerCRDT, gene-theory family GeneDensity/3D, GeneRecombination,
  GeneSimilarity, PacketEconomy): the swap-economy arc — dormant with
  GeneLibrary quarantine pending Daniel's Stage 2 call.
- **Model-math SPEC-ONLY** (RootLatticeDecoder, SpineRing, OctreeCell,
  HalfwayLatent, LBalanceOperator, MetricLattice, NudgeRankTheorem,
  HierarchicalDelta, Indices, CubeTensor, MinimalInstructionSet,
  SuccessiveRefinement, SynthesisPolicyValue, RGBTFeature, RungPivot,
  ScaleSurface-display-rule, SteeringSpine, RemainderTail,
  RedownsampleGate, ProjectionOrdering/Query, MotionFloorCorpus,
  DitherLevel, LocalPonder, PonderBudget-halt-half, CanonicalPhase†,
  DetailEntropy†, PairedResidual†, AtlasCascade†, GMM†, LabBleed†,
  LabTransition†, CoarseIsPalette†, ConstructionEncoder†): † = promoted above
  (waves 1–2); the rest serve Stage 3+ model work and activate with it —
  tracked, not lost.

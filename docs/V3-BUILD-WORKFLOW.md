# V3.0 — on-device training + the 16³ decision surface (build workflow)

> **HISTORICAL (banner added 2026-07-13).** Pre-Swift-pivot workflow; Zig paths read as
> `SixFour/Kernels/`. The live arc is [`REBUILD-2026-07-10-PLAN.md`](REBUILD-2026-07-10-PLAN.md).


> Status: LIVING · Created: 2026-07-01 · Owner: SixFour
> Companions: `SIXFOUR-MODEL.md` (the frozen V2 boundary), `docs/NEXT-STEPS.md`,
> `docs/MODEL-BUILD-WORKFLOW.md`. Spec wins on any disagreement.

## 1. What V3.0 is

The idea is unchanged; the training location moves.

- **Capture**: 64 frames → the V2.1 statistics field (64-bin per-channel histograms,
  `v21AccumulateHistKernel`, `Shaders.metal:269`) + the transport flow that recovers
  the time axis (`encodeV21Flow`, `Metal/Pipeline.swift:294`). Already shipping.
- **Propose**: the model reads the field (+flow) and emits a **16³ GIF proposal**
  (16 frames of 16×16, the palette-basis scale).
- **Decide**: the user iterates at 16³ until they like it — paint via
  `CellNudge.CellBudget` (16³×9, `Editing/NudgePaintView.swift`) + accept/again.
  Every decision is cheap because it happens at the coarse scale.
- **Build**: the self-similar ladder realises the approved 16³:
  **64³→16³ :: 256³→64³** — pooling down is exact (`s4_cube_lift_level`), the
  up-rung inventor is learned and **weight-tied across rungs** with thin per-scale
  conditioning (`Spec.PerScale`, per `sixfour-self-similar-16-to-256`).
  16³→64³ is the shipped GIF; 64³→256³ is the export rung. Zero paint = the
  deterministic `Upscale256` floor, byte-exact (unchanged law).

**The V3.0 twist**: every capture manufactures its own supervision pair on the
phone — the real 64³ and its exact 16³ pool. So the up-rung inventor can be
**fine-tuned per capture, on device**, before it is asked to invert the user's
approved 16³. What cannot be manufactured on the phone (corpus-scale encoder
training) stays offline on the Mac.

## 2. Contract rulings (Tier 2 is unchanged)

- **`mlx-swift` stays banned** in the shipped app. The WWDC26 "MLX on phone" route
  is out. The A19 GPU Neural Accelerators are reached instead through **Metal 4**
  (MTLTensor + machine-learning command encoder + MPP TensorOps) — an Apple system
  framework, hand-written kernels, exactly the house discipline.
- **MPSGraph remains the proven fallback** (AtlasTrainer precedent: Bradley–Terry
  training, 12.4 ms/step on the iPhone 17 Pro, bit-identical Mac↔iPhone loss
  trajectory). MPSGraph-first, Metal-4-second is the de-risked order; both are
  contract-clean.
- **Float re-enters the Zig Q16 floor.** On-device gradients are float32; the
  commit goes through `reenterQ16` and `AboveFloorMargin` exactly as the
  determinism-floor rule already demands. The Mac trainer's "Q16 commit must be
  Python float64" note (`TRAINER-BUILD-PLAN.md:83`) is a Mac-tooling artifact —
  on device the commit is native Zig integer code, which is the more canonical
  substrate, not less.
- **Neural-accelerator caveat**: Metal 4 tensor math on A19 need not be
  bit-identical to MPSGraph. Parity strategy: MPSGraph is the loss-trajectory
  golden backend; the Metal 4 path gates on commit-level byte-equality (post-Q16),
  not on float-trajectory equality.

## 3. The training boundary (which net trains where)

| Object | Params | Trains | Substrate | Supervision |
|---|---|---|---|---|
| Frozen lift / tokenizer (`encoder_frozen.py`, Zig `liftOct`) | 0 | never (frozen by law) | Zig (exists) | — |
| **V3 field encoder**: field+flow → 16³ proposal | new (~10⁵–10⁶) | **OFFLINE, Mac MLX** | MLX; ships as weight blob + hand-written Swift/Metal forward | AirDropped capture bundles (`v21_ingest.py`) + synth corpus |
| **Up-rung inventor** (`superres.py` f_θ 21p; context MLP 75→64→21 ≈ 6K) | 21–6K | **ON DEVICE, per capture** | Shader ML / ML command encoder, fused after the field dispatch; MPSGraph fallback | the capture's own (64³, pool 16³) pair; loss = `cellLoss` |
| 9-θ cell conditioner (`full_matrix_train.py`, convex) | 9 | ON DEVICE, per capture | same dispatch | same pair, conditioned on `CellBudget` |
| Temporal rung / delta value+policy heads | tiny | ON DEVICE, optional | separate dispatch (needs assembled flow) | (t, t+1) deltas from `V21Flow` |
| Preference head (Bradley–Terry, Atlas precedent) | tiny | ON DEVICE, per user | MPSGraph (event-driven, not per-frame) | the user's accept/again decision stream at 16³ |
| 18.9M ViT `JepaHead` | 18.9M | **RETIRED from the device path** (offline teacher at most) | — | floored, over-capacity, target machinery is Python-bound |

**Shader ML fold-in rule**: a net folds into the capture dispatch chain iff its
training data is fully materialised in GPU memory by that chain. The up-rung
inventor and the 9-θ conditioner qualify (field + pooled cubes are on-GPU);
the preference head does not (its events arrive at UI tempo); the field encoder
never qualifies (its corpus lives on the Mac).

## 3.5 The gene registry + the cascade (landed as `Spec.GeneTaxonomy`)

Every learned blob is a **gene**, categorised on three axes (class × site × size),
pinned in `Spec.GeneTaxonomy.geneRegistry` with laws (sizes derived from the
pinning modules, class⇒site coherence, zero-gene==floor claimed per entry):

| Gene | Params | fp32 | Class | Trains | Folds into rung dispatch? |
|---|---|---|---|---|---|
| `theta-up` (f_θ inventor) | 21 | 84 B | Somatic | device, per capture | **YES** |
| `theta-cell` (9-θ conditioner) | 9 | 36 B | Somatic | device, per capture | **YES** |
| `time-rung` (temporal MLP d=64) | 5,772 | 23 KB | Somatic | device, per capture | no (separate dispatch) |
| `theta-b` (masked band) | 63 | 252 B | Germline | Mac MLX | (ships hand-written fwd) |
| `field-encoder` (budget) | ≤1 M | ≤4 MB | Germline | Mac MLX (D1) | no (quantized inference) |
| `value-pref` (Atlas value head) | 29,249 | 114 KB | Identity | device, per user | no (MPSGraph dispatch) |
| `sigma-look` (σ-pair genome) | 384 | 1.5 KB | Meme | not trained (curated) | — |
| `metric-organ` | 9 | 36 B | Meme | Mac | — (the one live OrganSlot) |

Classes: **Germline** = shipped base, immutable per release; **Somatic** = lives and
dies with the capture bundle; **Identity** = per-user, persistent, private;
**Meme** = the shareable AirDrop/GeneStore layer. `OrganSlot` grows a case per gene
only when its trainer + tests exist (the no-stubs rule in `Organs/Organ.swift`).

**The cascade**: integer floor ops alternating with learned float layers, the Q16
commit sealing every seam. Zig stays the CPU source of truth + oracle; rung ops get
byte-exact Metal *integer* twins (the established pattern —
`v21AccumulateHistKernel` is already gated against `s4_v21_accumulate_hist`), so a
whole rung can run on-GPU: `[int lift] → [tensor-op learned layer] → [int commit +
unlift]` in one command buffer. A gene's *training* folds inside that dispatch only
if weights+grads fit the 32 KiB threadgroup budget
(`foldsIntoRungDispatch`; `lawFoldBoundaryIsRealOnBothSides` keeps the boundary
honest with members on both sides).

## 4. Ordered build phases

### Phase A — spec the boundary (first, as always)
- A1 `Spec.V3Boundary`: `ModelInput` gains the field + flow carrier (today
  `miCapture` is GIF-derived only). The 16³ proposal becomes a first-class
  output type (it is the palette BASIS scale, not a content resolution —
  the burst-SR 16→64 misreading stays dead).
- A2 `Spec.DeviceTrainStep`: the on-device step contract — supervision pair
  manufactured by exact pooling (`lawSupervisionPairIsExact`), loss =
  `cellLoss` (never `matrixSqLoss`), commit = `reenterQ16`, margin =
  `AboveFloorMargin`, collapse guards reused (`VarianceFloorGuard`).
  Keystone golden: fixed init + fixed capture + N steps → loss trajectory,
  emitted for Swift (`DeviceTrainGolden.swift`) like `MaskedBandGolden`.
- A3 codegen: `DeviceTrainContract.swift` via `Codegen.Swift`; gate stays
  `cabal test` + hermetic codegen.

### Phase B — the device trainer
- B1 `SixFour/Train/DeviceTrainer.swift` on **MPSGraph** (resurrect the
  AtlasTrainer pattern from the worktree spike), training f_θ + 9-θ against the
  A2 golden. Simulator-gated (`targetEnvironment`), device-verified.
- B2 the fused rung dispatch. **B2.1 SEED LANDED 2026-07-01**:
  `Metal/DeviceTrainShaders.metal` + `Train/RungDispatch.swift` — Metal INTEGER
  twins of the rung ops (`octantLiftKernel`/`octantUnliftKernel`, byte-exact vs
  the Zig oracle on 256 random blocks incl. negatives — the `fdiv2` floor-div
  hazard pinned) and `deviceTrainFusedKernel`: [int lift → fp32 θ_up descent →
  Q16 commit] in ONE dispatch, committing exactly `DeviceTrainGolden.committed`
  (the third backend on the same bytes; simulator-verified, plain Metal compute).
  **B2.2 SIMT LANDED 2026-07-01**: `deviceTrainSimtKernel` — THE DETERMINISTIC-SIMT
  STANDARD for rung kernels (one power-of-two threadgroup; strided pair
  assignment; FIXED-ORDER tree reduction so the fp32 descent is
  bitwise-reproducible — asserted, not hoped; barriers only at phase seams; gate
  = post-commit bytes). 2,048-pair × 600-step batch trains in ~10 ms even on the
  sim GPU; threadgroup working set 21.6 KiB — the `GeneTaxonomy` 32 KiB fold
  budget, literally allocated. Tests: golden bytes (4th backend), bitwise
  reproducibility across runs, per-pair lift parity vs the Zig oracle at 2,048
  pairs, θ/loss agreement with the CPU Double twin.
  **B2.3 LANDED 2026-07-01**: `captureOctantsKernel` + `RungDispatch.trainOnVolume`
  — the capture-shaped OKLab Q16 volume (`s4_synth_burst` layout = the real
  capture buffer layout; lane order (dt, drow, dcol) so the octant z axis IS the
  time axis) → all (frames/2)·(side/2)² octant blocks gathered on-GPU → the SIMT
  descent, in ONE command buffer (two encoders, tracked-resource ordering; the
  blocks never visit the CPU). Tests: per-channel gather parity vs the CPU
  reference; fused-vs-blocks-path BITWISE equality (fusion adds zero drift); the
  flagship — 64×64×64 synth capture, 32,768 pairs × 600 steps trains in ~200 ms
  on the sim GPU, learns (loss < floor), bitwise-reproducible.
  **B2.4 LIVE WIRE LANDED 2026-07-01**: `Train/CaptureGene.swift` +
  `Feature.v3SomaticTrain` (ON) + `CaptureSession.finishBurst` — every burst now
  trains its own somatic θ_up at the capture seam (tiles → Q16 volume via the
  sanctioned round-half-to-even crossing → the fused B2.3 dispatch) and carries
  it as `BurstResult.thetaUp` (optional; absence == the deterministic floor).
  Gates: Q16 volume assembly round-trips the synth ints EXACTLY; the tiles path
  is BITWISE the volume path; the gene JSON-round-trips (bundle persistence
  ready). Device-side behavior on a real burst: unvalidated until a physical
  capture run. **Remaining in B**: the physical-device test run, and the
  optional Metal-4 MTLTensor forward. Phase C (the 16³ decision surface) is
  next — `BurstResult.thetaUp` is its input.
- B3 measure: `lawAboveFloorMarginMeasured` finally gets its number — does the
  per-capture-adapted up-rung beat the deterministic floor on held-out cells
  of the same capture? This is the V3.0 go/no-go.

### Phase C — the 16³ decision loop (the app surface)
- **C1 SURFACE LANDED 2026-07-01** (grid-first, PICO-8 cart bypassed per owner):
  `GridLayout.decisionScene` — seven proven regions, one per user-changeable
  model-boundary knob (preview scrub / 16³ paint / channel strip / φ6 gauge /
  somatic-gene toggle / again / accept), all eight layout laws green on first
  placement (spec 1357) → codegen'd into `GridLayoutContract.decisionScene`
  (+ runtime selfCheck now spans both scenes) →
  `UI/Screens/Decide/DecideSurface.swift` composes them via `place(_:in:)`
  (GRID lint PASS: no free frames, no raw offsets, lattice-pt padding).
  `DecideModel` = NudgePaintModel (miNudge+miGauge) + gene toggle (defaults to
  gene presence; nil pins the floor) + one time axis (preview scrub t drives
  paint layer t/4). Tests: knobs resolve, ModelInput assembly, gene default,
  scrub→layer derivation.
  **C1 FSM WIRED 2026-07-01** (spec 1360): `ABSurface` gains `Deciding` +
  `BeginDecide/DecideAccept/DecideAgain` — entry gated from `Captured`
  (`lawDecideEntryGated`), accept lands in `Picked` so `lawExportGatedOnPick`
  is UNTOUCHED (a decide-accept IS a committed pick), again/retake bail to
  `Live`; second golden trace (`goldenDecideHappyPath`, with a reject loop)
  emitted + folded by both `assertSpecParity()` and `DecideMachineTests` (CI).
  Live route: burst → `finishBurst` trains θ_up → engine (`burstTiles/thetaUp`)
  → σ at `commit` → gated DECIDE button on the review bench (`beginDecide`) →
  `DecidingPhaseField` → `DecideSurface`; accept stashes
  `σ.acceptedInput + acceptedUseGene` (the 256³ build's future input).
  **C1 EXPERIENCE WIRED 2026-07-01** (post-device-run UX round): the decide
  surface now shows the REAL objects — (a) the paint grid's underlay is the
  actual 16³ proposal (`Surface.coarseSubstrate`, the lossless coarse tier,
  already built at commit), so the user paints ON the thing they are deciding;
  (b) the preview hero is the true reconstruction: `OctantCube.expandProposal`
  runs the REAL octant up-rungs 16³→64³ with θ_up inventing on L (gene) or zero
  detail (floor) — the gene toggle now visibly changes pixels, and what is shown
  IS what accepting would ship (`OctantCube` = CPU rung port on
  `RGBT4DLift.sLift/sUnlift`, gated vs the Zig oracle + NN-floor identity +
  gene-touches-only-L). Paint still conditions only the recorded input (the
  learned model consumes it later — honest, documented in the header).
  Seam relief shipped the same round: the V2.1 flow encode (device-measured
  ~19 s) moved OFF the burst path — detached task → `flowCallback` → engine
  (`v21FlowVersion`) → σ → the Done bundle rebuilds when the flow lands.
  `BurstResult.flow` is now always nil by design.
  **C1 remaining**: the first preview render builds the 64³ lazily on-main
  (~0.1–0.8 s debug; consider async build), paint→preview conditioning awaits
  the trained model. C2: preference head on the verdict stream.
- KNOWN pre-existing failure (NOT this work): `FrontProjectionTests` 4096-byte
  mismatch on the current working tree; its golden + subsystem are untouched by
  the V3 diff. Triage separately.
- C2 log decisions; train the preference head on-device (Atlas pattern) to
  warm-start future proposals. Optional until C1 feels right.

### Phase D — the offline encoder (Mac, parallel to B/C)
- D1 MLX field encoder: input = `field_SxSx3xN.npy` + flow (loader exists,
  `v21_ingest.py`), output = 16³ proposal (per-frame palettes + indices).
  Train on the AirDrop corpus + `s4_synth_burst` synthetics.
- D2 deploy: weight blob → hand-written forward (Swift/Accelerate or a Metal 4
  tensor kernel — benchmark on device), golden-gated. Never CoreML, never
  mlx-swift. Replaces the interim floor-as-proposal from C1.

## 5. The PICO-8 UI port

The cart stays the sketchpad; the port target is the **app's decision surface**,
composed on the proven lattice. The substrate already exists end-to-end:
`Lattice.hs`/`GridLayout.hs` → `LatticeContract.swift`/`GridLayoutContract.swift`
→ `ScreenLattice.place(_:)` (the one sanctioned `.position`).

1. **Sketch `decisionScene` in the cart** (that is its job): 16³ proposal viewer
   (16×16 interactive), 64³ preview (64×64), nudge palette strip, accept/again
   cells. Press **C**, paste into `GridLayout.hs` as `decisionScene`.
2. **Prove it**: extend the five GridLayout laws over the new scene
   (`lawWidgetsClearCorners`, disjoint, touch-floor, safe-area), `cabal test`,
   `cabal run spec-codegen` → `GridLayoutContract.decisionScene`.
3. **Sync the cart** (`check_sync.py` learns the second scene, `verify.sh`).
4. **Compose in Swift**: a `DecidingPhaseField` = `ZStack(topLeading)` of
   `.place("proposal") / .place("preview") / .place("nudge") / .place("accept")`.
   New widgets needed: `Proposal16View` (16×16 cell grid + frame scrub on the
   4pt lattice) and the accept/again cells; `NudgePaintView` embeds as-is.
   The PICO-8 *look* (chunky cells, 16-colour restraint) is `Theme.swift` +
   `CellAlgebra` shimmer — no new rendering tech.
5. **Parity**: `render_grid.py` gains `decisionScene`; the top backlog item
   (Haskell `cellOnScreen` golden vector) closes the cart↔spec↔Swift triangle.

## 5.5 Gap audit (2026-07-01, 56-agent workflow — 25 confirmed, 0 refuted)

All 9 device-test blockers FIXED (spec 1360 + Swift suites green):
- **Async flow identity**: flow deliveries are epoch-gated (a late encode can
  never be attributed to a newer capture); `v21Flow` cleared at capture start +
  reset; the Done bundle rebuilds on a VERSION, not nil-ness; a burst SKIPS its
  flow encode while the previous ~19 s encode still holds its ~800 MB buffer
  (jetsam guard — that burst exports via the temporal-proxy fallback).
- **Shutter re-entrancy**: `capture()` refuses unless the engine is idle/done.
- **Error recovery**: `Retake` now bails from `Error` (spec-first; TRY AGAIN
  actually works instead of dead-ending the app).
- **Decide surface**: gauge button repaints (nested-ObservableObject forward);
  reconstructions build OFF-MAIN (capture-frame fallback until ready); the gene
  arm honours the gene's trained channel; the accepted decision clears at every
  new commit.

Confirmed but deliberately deferred: seam stall ~0.3–0.6 s (per-capture
RungDispatch PSO builds + sync train on the delegate queue), AVCapture
interruption watchdog (a burst that never reaches 64 frames leaves the
continuation stuck), 9-segment channel picker below the HIG floor (→ 3×3 cell
grid), the accepted decision is recorded but not yet consumed at export
(awaits the 256³ build), export bundle built on the MainActor.

## 6. Honest gaps

- Nothing in V3.0 is trained yet; `contractDescentOnRealDataUnproven` and
  `contractEmpiricalSoundnessUnproven` stand until B3/D1 produce numbers.
- The Metal 4 tensor API + neural-accelerator behaviour on A19 is unbenchmarked
  in this codebase; B1 (MPSGraph) is the schedule hedge.
- The field encoder's architecture (D1) is undesigned; the 16³ proposal type
  (A1) must land first so the encoder has a contract to target.
- The cart's decisionScene does not exist yet; C1 blocks on step 5.2.

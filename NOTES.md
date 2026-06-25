# NOTES — design decisions, session log

> NOTES.md is a chronological session log (history), NOT current status. For current build-state, canon = CLAUDE.md (the contract) + SixFour.Spec.Map (the spec index) + the module doc-comments. (docs/STATUS.md was deleted; do not recreate.)

Running notes on architectural pivots and their tensor evidence. Entries are
newest first.

---

## 2026-06-25: the H-JEPA trainer — from spec contracts to a running, observable trainer (branch `spec/hierarchical-delta` → master)

> **Session theme (Daniel):** "how close are we to running a trainer?" → build it. Then: make a CLI,
> show me it's actually training, show me the input GIF + the 16³/64³/256³ spine, and build the super-res.

The design was H-JEPA but lived almost entirely in the Haskell spec (contracts + laws, no weights).
This session REALIZED it: a 15-module hand-written MLX/numpy trainer in `trainer/mlx/`, each module a
byte-exact twin of its `Spec.*`, plus 3 spec-emitted goldens making the spec the authority for the
data **and** the trainer. 14 commits, fast-forward merged to master.

**Tech debt removed first.** Deleted 8 dead retired-direction trainers (Atlas/Bradley-Terry + look-net,
all broken at import); none on the gate/CI path so the gate stayed green.

**The trainer, built in layers (each a byte-exact spec twin, gated by `trainer/mlx/gate_trainer.py`):**
- **v1 floor** — `q16` (the single float→byte Q16 crossing), `encoder_frozen` (the **zero-param** feature
  map — `encoderParamCount==0`), `theta_b` (the 63-param masked-band predictor + the 77-param position
  head), `jepa_loss` (exact gradient), `masked_band_trainer` (reproduces `goldenTrainedBand` 3000
  byte-exact; batch-divergence guard), `autograd_check` (MLX autodiff == the analytic gradient, Δ=0).
- **v1.5 corpus** — `jepa_synth_octants`: real 64³ synth captures → octant masked-band records via the
  gated reversible lift. Empirical finding: generalization is **smoothness-proportional** (held-out loss
  89.2% of floor on smooth scenes, 99.6% on noise — the I-JEPA signature).
- **v2 wide head + collapse guard** — `vicreg` (the two-term coding-rate floor; constant collapse is
  invisible to the covariance term, caught by the std-hinge), `large_head` (the 18.9M-param ViT + the
  integer-d6 ALiBi bias; its **depth-1 limit reduces to `theta_b` byte-exact** — the controlled-deviation
  keystone), `per_scale` (per-scale conditioning + the 16³-identity carve-out).
- **v3 spec-forced goldens** — `Codegen.JepaHead` → `jepa_head_golden.json` (the θ_B trajectory +
  single-active-term forward witnesses, byte-exact across tiers by construction) and `Codegen.TemporalData`
  → `temporal_data_golden.json` (the `(t,t+1)` value/policy delta engine; `lawTemporalEngineRoundTrips`).
- **The composite objective, complete** — `L = L_band^A + L_band^B + latentCodingFloor + L_cross + L_mid`
  (`jepa_loss` + `vicreg` + `dual_loss`), and the two delta heads (`delta_surrogate`: VALUE = OKLab
  regression, POLICY = per-voxel classification; keystone `lawPolicySurrogateDecodesToTransport`
  demonstrated against the temporal golden).
- **The end-to-end loop** — `train_loop.py`: ONE optimizer descends the composite loss over the corpus on
  the real 18.9M ViT, organized around the **float32-train / float64-commit seam** (no committed byte ever
  enters the gradient). `--smoke` proves 4 properties: descent (with an lr=0 control), no-collapse
  (positive control), byte-commit preserved, determinism. Built + adversarially verified by a workflow.

**The encoder is FROZEN, not trained** (`EncoderFrozen.lawNoPreTrainPhase`). It manufactures the
collapse-proof target; the only learned object is the predictor. Its two jobs map to the rungs
(`RungPivot`): DOWN = Held (masked-band fit on real data = the training), UP = Invented (super-res,
consistency-gated).

**Sanity tests on a geometric object** — `test_centered_cube` (a 64³ cube compresses losslessly to the
16³ coarse with ZERO detail; 4³ block → one coarse pixel) and `test_cube_learning` (the floor nails the
flat 99.5%; θ_B learns the 0.5% surface, held-out cut to 13% of floor). The division of labour between
compression (the reversible lift) and prediction (the learned head), made quantitative.

**The CLI** — `trainer/mlx/cli.py` + `scripts/s4train` (stdlib argparse, zero new deps; each subcommand
forwards to the owning module): `gate / train / floor / corpus / cube / cube-learn / goldens / regen /
autograd / superres / report`.

**Observability** — `train_viz.py` + `s4train report`: a self-contained `index.html` (base64-embedded so
the input GIF animates in a browser) with (A) loss charts (`L_composite` + `L_band`-alone + a flat lr=0
control = optimizer-driven proof), (B) the input GIF + montage, (C) the **16³ · 64³ · 256³** scale spine.

**The up-rung super-res** — `superres.py`, the twin of `Spec.DetailPredictor` reused per
`lawDownIsHeldUpIsInvented`: `f_θ : coarse → detail` (21 params), trained on the down-rung, reused on the
up-rung to invent 256³ detail. HONEST measured finding: the coarse-only head invents the **conditional-mean**
detail (a modest structured high-freq pattern, NOT rich texture — energy 0 → 1.19e9 on a capture,
re-downsamples to the EXACT 64³; stays at floor on the cube). Rich invented texture is the larger
sibling-aware ViT's job. The report's 256³ panel shows floor vs invented vs the diff, labeled honestly.

**Doc-debt cleared** — rewrote `verify-doc-claims.sh` lean (it gated the deleted `docs/STATUS.md` + ~17
stale checks → now 19 CURRENT facts, exits 0 so `s4 all`'s `doc` verb is unbroken); rewrote `TRAINING.md`
as the real runbook; fixed README/SETUP/spec docstrings/find-stubs.sh (removed 8 dead `docs/*.md` links +
the look-net framing). `spec/scripts/gate.sh` green throughout.

---

## 2026-06-24: inter-frame policy/value deltas + the `detailBand` band-extractor unification + module-debt cleanup (branch `spec/encoder-grounding`)

> **Session theme (Daniel):** H-JEPA depth — now that we have a loop, give it something to ponder;
> integrate DEEPLY (shared structure, not I/O plumbing); and clean the technical debt before committing.

Built spec-first, additive, gated. **922 spec tests green** (from 920), build + Haddock warning-clean, both
byte-exact goldens (`jepa_data_golden.json`, `MaskedBandGolden.swift`) untouched, Python corpus self-check
green. Branch is a strict descendant of master (clean fast-forward).

**INTER-FRAME t→t+1 = Option 2 (policy/value deltas), DATA-MANUFACTURED.** The circular time axis is supervised
by predicting the NEXT captured frame's own data, split into an orthogonal POLICY (index/motion) and VALUE
(palette/recolour) channel. `Spec.ConstructionEncoder`: `policyDelta`/`valueDelta` +
`lawInterFrameFactorsToPolicyValue` (the two channels compose in either order, neither alone reaches t+1) +
`lawPaletteIndexGaugeInvariant` (compare in FUSED `buildPixels` space — raw palette slot-by-slot is gauge-broken).
`Spec.JepaTarget`: `lawTemporalDeltaTargetIsDataManufactured` + `lawNoSelfProducedRolloutTarget` (a
`RolloutTargetSource` model: the orbit-closure `L_close = ‖R⁶⁴ z₀ − z₀‖²` gradient term is FORBIDDEN — its global
minimum is the trivial constant orbit, the BYOL/EMA collapse symmetry smuggled onto the time axis). Decided via
research+design workflows; a PonderNet fits ONLY as adaptive Synthesis-ascent depth halted by a θ-free data
threshold — design captured, not built.

**`detailBand` — ONE canonical band selector (the deep integration).** Three parallel destructures of the 7-band
`Detail` (`MaskedBandPrediction.bandAt`, `JepaData.detailAt`, `DetailEntropy.detailColumn`) collapsed into a single
`OctreeCell.detailBand`/`detailToList` that all three route through, so "they read the same band" is STRUCTURAL,
not an extensional coincidence three laws had to police. `JepaData.lawHeldTargetIsMaskedTarget` (the held label IS
the masked target); `OctreeCell.lawDetailBandSelectsSlot`. Byte-identical (both goldens survive); the
`EncoderGrounding` keystone now rests on the shared primitive. NOTE: the higher-altitude `cata distillAlg .
buildCube` re-root of `octantDistill` was ATTEMPTED and REVERTED — `octantDistill`'s real contract is PARTIAL
distillation (descend k levels of a full cube, input length ≫ 8^k), which a catamorphism-to-leaves does not model;
the `PairedResidual` 256³→64³ consumer caught it at ship depth (the byte-identity proof had only covered
length==8^k). The shared primitive is the right altitude the contract honestly supports.

**MODULE-DEBT CLEANUP (from a 161-module grading audit).** Gate-honesty — wired previously-ungated ("lying-green")
laws into the gate: `Spec.TemporalLoop` (new `Properties.TemporalLoop`, all 8 loop-closure/residual laws),
`Spec.Export` (4 downsample/cube-ladder laws), `Spec.Laws` (`lawWuShapesOut` → `Properties.Wu` at ship shape
64³/K=256, `lawSinkhornBalancedColumns` → `Properties.Sinkhorn`), `Spec.Boundary` (`lawConstantsPinned`). Map lint —
added `AtlasCascade` + `Loom` to `Spec.Map`. **Deleted `Spec.ExportFamily`** — abandoned scaffolding (14
`error "TODO"` stubs, never in cabal, zero importers; its temporal-S-transform / 256-synth / {16³,64³,256³} pack
functionality already gated in `TemporalLoop` / `Upscale256` / `Export`). Repointed stale `@ExportFamily@`
references in `OctreeGenome` (which already superseded its `lawZeroGenomeIsFloor`) + `NetSynth256.swift`. The audit's
"not deletable" verdict on ExportFamily was overturned by direct verification.

---

## 2026-06-23: retire the A/B preference-EBM → one truth, then EARN the encoder architecture by entropy theorems (branch `spec/retire-ab-one-truth`)

> **Session theme (Daniel):** "delete code that is not aligned — I want one truth (the
> self-supervised JEPA-EBM, the A/B choices retired); then the encoders must EARN their capacity
> with proven computational theorems, organised by entropy; and ensure the work is verifiable."

Built spec-first, additive (except the sanctioned A/B deletion), gated. **891 spec tests green, 148
modules compartment-tagged, hermetic codegen no-drift.** Branch is a strict descendant of master
(clean fast-forward). Builds on the reconciled dual-encoder base (`5e4d487`).

**ONE TRUTH (`96f4436`, `ad5e49c`, `1ad9e20`):** extracted `Spec.Q16` (the single float→int seam)
and landed the VICReg variance-hinge in `NeuronRedundancy` (`varianceFloorPenalty`, the active
collapse floor covariance is blind to). Then **retired the A/B preference-EBM + look-net** — 47
`Spec.*` + 8 `Codegen.*` modules deleted (AtlasGame/ValueHead/Preference/LookNet*/GumbelSearch/…),
keeping only the self-supervised JEPA-EBM. Removed stray duplicate root `Generated/`/`Resources/`.

**THE SYNTHESIS AS POLICY+VALUE (`5cb7252`):** `Spec.SynthesisPolicyValue` — the GIF synthesis IS
AlphaGo policy+value, already typed in `ConstructionEncoder`: `cIndex` = POLICY (the index map,
integer argmax), `cPalette` = VALUE (the Q16 palette); `buildPixels = value[policy]`. New tooth
`lawPaletteRelationallyOrdered` (colours d6-ordered). Bound to `Upscale256.UpscaleOutput`.

**FUSE == MIDPOINT (`78b368c`):** `Spec.HalfwayLatent` — `lawFuseIsMidpoint`: the ViT waist
(`vitTokens·vitDModel = 64·512 = 32768`) IS the never-surfaced 32³ Down-rung midpoint, binding the
architecture-map waist to the octant spine. The fuse (Encoder A ⊕ Encoder B) = the nudge target.

**THE ENCODER-EARNING CHAIN — every dimension earned by a theorem, organised by entropy:**
- `EncoderModalityLoad` (`1690789`) — the 3 modality loads on ONE non-negative bit axis. The fix:
  the palette load is the RIDGED coding rate `½log₂(det(Σ+σ₀²I)/σ₀⁶)` (≥0 by construction), NOT the
  raw differential entropy (which goes NEGATIVE — verified −9.559 — and would invert a softmax).
- `EncoderWidthAlloc` (`554a921`) — width = entropy share of the fixed 512 via Hamilton
  largest-remainder; sums to EXACTLY 512 (teeth: naive `round` ⅓-tie → 513). Earned: colourful
  (192,128,192), greyscale (216,80,216).
- `EncoderDepthAlloc` (`7b56621`) — depth = octant levels with positive detail, cap `levelsBetween
  64 4 = 4` (proven, NOT "L=6 coincidence"). Teeth: a cut at L destroys `[3584,448,56,7]` dims.
- `EncoderEntropyFloor` (`b24a5a7`) — the source-coding lower bound: learned may EXCEED the
  entropy-share floor, never drop below (dual of `varianceFloorPenalty`). static=floor, learned=surplus.
- `EncoderCorpus` (`f22a15e`) — the corpus → loads → floor bridge; the floor is a REAL function of
  corpus content. The clips that size the encoder are the clips `JepaData` trains on (one lift, double duty).

**VERIFIABILITY (mutation audit in `cabal repl`):** every law in the earning chain was
mutation-tested — all 13 law/mutant pairs are FALSIFIABLE (each killer mutant flips its law to
`False`); zero vacuous laws. "Green ≠ verified" — these laws have receipts.

**CROSS-TIER RETIREMENT COMPLETED (the spec deletion propagated to every tier so the app builds):**
the spec-only A/B + look-net deletion (`ad5e49c`) had left orphaned consumers across all tiers; this
session finished them. (1) Look-net deploy path: Zig `s4_load_look_net` + `S4LookNetWeights` +
`fixture_test.zig`, the C header decl, the Swift `loadLookNet` binding, the trainer look-NN Python
(`export_look_net_blob`/`train_look_net_mlx`/`look_net_loss_mlx`/`eval_l_quality`/`check_golden`/
`regimen`), and the `net_shape.py` drift check. (2) The A/B Color Atlas APP subsystem (Daniel's
informed call — it was the LIVE primary post-capture surface, not a gated feature): deleted
`SixFour/Atlas/` (11), the A/B `Palette/` + UI views (`ABCandidatePhaseField`/`AtlasBoardView`/
`AtlasGalleryView`/`AtlasTrainingField`/`GeneLogView`), and 12 A/B golden tests; made `PhaseField`'s
`.captured`/`.picked` route to an INERT placeholder (the post-capture UX is now empty until a
JEPA-based surface is built), hardwired `CaptureViewModel`'s curated-palette to nil, removed
`SixFourNative.boardMassQ16`. **iOS app: TEST BUILD SUCCEEDED; spec gate: all green.** Map.hs
re-indexed (8 new encoder modules added, the retired look-NN + Color Atlas sections removed).

**OPEN:** (a) the per-modality integer widths/depths are earned in FORM but the specific numbers await
a measured CORPUS (no camera here); (b) **the app has NO post-capture UX** — building the JEPA-based
post-capture surface that replaces the A/B game is the real next project; (c) residual stale prose in
`Spec.Map` (scattered deleted-module refs in §4) is doc debt, non-blocking.

---

## 2026-06-23: dual-encoder H-JEPA + dither/midpoint + minimal-instruction-set (branch `spec/dual-encoder-hierarchies`) — SUNSET, awaiting reconciliation

> **Session theme (Daniel):** "redesign the I-JEPA — two semantic encoders of the same GIF;
> explore the distance between L,a,b,x,y,t; 64³↔16³+data scalable through a 32³ latent; the
> dither hierarchy on the 64³ GIF; the minimum decode-instruction set." Built spec-first,
> additive, gated. **NOT committed to master; lives on branch `spec/dual-encoder-hierarchies`,
> awaiting reconciliation with a parallel branch Daniel is driving.**

**WHAT LANDED — 10 new `Spec.*` modules + 10 `Properties.*`, all ADDITIVE. `gate.sh` GREEN
(1288 spec tests, exit 0, 186 modules compartment-tagged, hermetic codegen no-drift, lints +
Zig/Python cross-language goldens). NO golden re-pinned. NO edit to any owned module.**

Arc 1 — DUAL-ENCODER H-JEPA (the two encoders are ONE object):
- `ConstructionEncoder` (Encoder A: Q16 `cPalette` + Morton `cIndex` → `buildPixels`; `identityIndex` = the A-form "no index" core, `lawIdentityIndexIsPaletteInOrder`).
- `PerceptualEncoder` (Encoder B: `Cube → [P6] (L,a,b,x,y,t)` via `mortonToXYT`; `perceptualDistance` = `RelationalMemory.d6`).
- `GifDualView` (KEYSTONE `lawSameObjectBothViews`: both views decode to the SAME pixels).
- `CrossEncoderDistance` (`constructionDistortion` + per-axis `axisDistortion` = "the distance between L,a,b,x,y,t"; `lawPerAxisDistortionSumsToTotal`).
- `CoarseIsPalette` (TYPE-LEVEL `16*16==256` via `Refl`; `coarseToPaletteStack`; `decodeAPalettesOnly`; depth-5 32³ rung `lawMidpointIsPaletteStack`).
- `ScaleIndexedCorrespondence` (the H-JEPA hierarchy `Exact@16³/Lossy@64³/Invented@256³` on the `HJepaLevels` spine; `LatentMidpoint` as a NON-`Bounded` kind so the keystone literal stays green).
- `DualEncoderJepa` (redesigned objective `lawCrossEncoderContextStrictlyHelps`: joint A+B context beats B alone; data-manufactured target, NO EMA).

Arc 2 — HIERARCHY REDESIGN (two design studies, then build):
- `DitherLevel` (dither = the per-pixel latent z, H-JEPA §4.6; `realizeStream`; `lawRealizationUnbiased` / `lawRealizationIsNotReversible` (only the loop MEAN recovers; per-frame bit destroyed) / `lawDitherFlickerPeaksAtHalf` / `lawContinuousReducesToDiscrete` / `lawGoldenOrderingTamesLatent`). **METAL-GPU float** (`Dither.hs` is `OKLab Double`); NOT on the Q16 floor.
- `MidLatentCrossPrediction` (the 32³-local cross-encoder objective; `lawMidCrossEncoderStrictlyHelps` carries BOTH clauses; midpoint-local, NOT the 16³→256³ hop).
- `MinimalInstructionSet` (the "16³+data" minimum decode instructions, BOTH forms: A = 16 palettes / no index `lawSixteenPalettesSuffice`; B = `(L,x,y,t)+data` LOSSY `lawBSkeletonIsLossy`; the ASYMMETRIC duality `lawDualMinimalProjections`: A→B exact, B→A Invented).

**Findings the studies confirmed against code (corrections to the initial framing).**
- A-form decode rule is octant-MORTON (`mortonToXYT 4 i`), NOT raster `(i mod 16, i div 16)` — raster would bit-scramble (the substrate stores Morton across `cIndex`/`coarseToPaletteStack`/`perceptualEmbed`).
- "16 palettes, no index" is CONDITIONAL on complete-256 per-frame (`CompleteVoxelVolume`); real frames often fail it (flat regions). `decodeAPalettesOnly` is a reshape (always correct); droppability is the conditional claim. `Significance` is population, not completeness.
- B-form `(L,x,y,t)` is LOSSY: `L→(a,b)` is ill-posed colorization; chroma is Invented/predicted, never an exact inverse.
- Dither `(palette+p)→stream` is NOT reversible; only the T-window MEAN survives. It is a display decoder (METAL-GPU), not a floor op.
- The 32³/128³ midpoints were ALREADY canon (`RungPivot.lawIntermediateNeverSurfaces`); this work ROUTES the cross-encoder objective THROUGH them, it does not introduce them.

**Design canon (intentionally NOT in the repo, per the no-`docs/`-plan-files rule):**
`~/.claude/projects/-Users-daniel/jepa_wf_artifacts/dual_encoder_dither_midpoint_study.md` and
`.../minimal_decode_instruction_set_study.md` (each self-critiqued via an adversarial workflow).

**RECONCILIATION (Daniel has a parallel branch to merge against this one).**
1. **Fully ADDITIVE.** 10 NEW module files + 10 NEW test files. NO golden re-pinned. NO edit to `RelationalMemory`/`RelationalResidual`/`HJepaLevels`/`RungPivot`/`Dither`/`SpatialDither`/`STBN3D`/`JepaTarget`/`SuccessiveRefinement`/`SelfSimilarReconstruct` (all read-only delegations). The other branch's edits to those modules do NOT collide with this branch's modules.
2. **Shared append-only files (trivial 3-way merge, keep BOTH sides' additions):** `spec/spec.cabal` (library `exposed-modules` + `spec-tests` `other-modules`), `spec/test/Spec.hs` (imports + the test-tree list), `spec/src/SixFour/Spec/Map.hs` (one categorised line per module). If the parallel branch also adds modules, both lists simply grow; resolve by keeping all entries (no semantic conflict).
3. **EMA FORK (the one real tension).** This branch keeps the DATA-MANUFACTURED, no-EMA target (`lawDualTargetIsDataManufactured`, `lawMidTargetIsDataManufactured`, delegating `JepaTarget`). COMPATIBLE with an EMA-on-the-PREDICTOR variant. CONFLICTS only if the parallel branch replaces the manufactured TARGET band with a float EMA target (that breaks byte-exactness + reintroduces collapse). Reconciliation rule: keep EMA OFF the target band; the frozen lift stays the tokenizer/target-manufacturer.
4. **DEFERRED follow-on (backend-port territory, not spec law):** the full typed `ContinuousConstruction` realize-to-frames (binds `SpatialDither.ditherFrameQ16`; `bluePick` is unexported — needs a widened export) + `PerceptualEncoder.perceptualEmbedMean` with the BLOCKING `[Double]` 32³-midpoint (`lawPerceptualMidpointNeverSurfaces`). Their PROVABLE CORES already landed as `DitherLevel` laws (mean-recovery = "B sees the loop mean"; reduces-to-discrete = the continuous extension of the byte-exact corner).
5. Chroma "+data" residual stays on the DECIDED 64³ STBN3D/nearest-2 path, NOT a 32³ latent.

**Verification performed.**
- `cabal test spec-tests` → 1288 / 1288 green.
- `bash spec/scripts/gate.sh` → exit 0 (tests + hermetic codegen no-drift + 186 modules compartment-tagged + lints + Zig + Python cross-language goldens).
- `cabal haddock sixfour-spec` → warning-clean for every new/amended module.
- Per-module law review during the build (one `cabal test -p <Module>` per module, all green).

**Left untouched on purpose.** `Native/src/color_fixture_test.zig` (pre-existing modification from
the byte-exact thread, another session). Stray repo-root `Generated/` + `Resources/` are a
`spec-codegen` wrong-cwd MISFIRE (untracked, never tracked; the real tracked outputs live in
`SixFour/Generated/`); NOT committed, safe to `rm -rf Generated Resources` from the repo root.

---

## 2026-06-22: doc-staleness sweep after the I-JEPA redirect + compartment pivot + module splits (branch `model/relational-residual`)

This session landed three structural changes that staled the docs, and this sweep reconciles them. (1) THE I-JEPA REDIRECT: the relational-residual -> LargeJepaHead asymmetric I-JEPA head is now the LIVE learned core (frozen reversible lift = param-free tokenizer + collapse-proof JepaTarget; trained MLX -> coreai-torch -> Core AI), landing the new live modules RelationalMemory, LargeJepaHead, JepaTarget, JepaMemory (the memory-budget tripwire), JepaData (data engine, KEYSTONE lawDataEngineRoundTrips), MaskedBandPrediction/MaskedBandTrainer, DeferredSurfacing, NeuronRedundancy, MoveSignal, TwoMoveOctave, BoundedP6, Sided, DataParallel; the look-NN is now the ABANDONED V2-deferred path, NOT the core. (2) THE COMPARTMENT PIVOT: every Spec module carries a `-- COMPARTMENT: <c> | tag:<t>` line and Spec.Map grew a BACKEND COMPARTMENTS super-category (4 phantom-tag walls ByteCarrier/Sided/BoundedP6/DataParallel), enforced by scripts/check-compartments.sh. (3) MODULE SPLITS: RelationalResidual -> RelationalResidual (Zig P6/nudge/safeNudge substrate) + RelationalMemory (MLX d6/14-int residual/metric laws); Collapse -> Collapse (float maximin baseline, Metal) + GlobalCollapseQ16 (byte-exact Q16 collapse, Zig). GATE HARDENING: spec/scripts/gate.sh is now the single gate (cabal test + hermetic codegen via spec-codegen + git diff --exit-code + check-compartments + lints + Zig cross-language goldens with -Drequire_fixtures=true + python3 trainer/jepa_data.py); ~1249 spec tests + 72 Zig test blocks green. The doc sweep re-pointed all moved-symbol Haddock cross-refs (Collapse.globalCollapseQ16 -> GlobalCollapseQ16; RelationalResidual.d6 -> RelationalMemory) and stripped every broken @docs/*.md@ link (the docs/ dir was emptied this session; canon = CLAUDE.md + Spec.Map + module doc-comments, do not recreate the deleted plan files).

---

## 2026-06-22: I-JEPA link + Core AI to be TRAINED (the large head) (branch `model/relational-residual`)

> **Session theme (Daniel's direction):** "find the link between this encoding and the I-JEPA architecture.
> Core AI is to be trained." Workflow waw4p81tr (I-JEPA + Core AI web-searched).

**THE LINK (precise, web-grounded vs Assran et al. 2023).** SixFour was already I-JEPA in shape: masking =
`MaskedBandPrediction` (predict 1 masked band from coarse + 6 visible siblings; `lawSiblingContextStrictlyHelps`);
latent-space loss = `DeferredSurfacing` (predict in latent, defer the single reenterQ16 surface); the EMA
target-encoder = the DATA-MANUFACTURED target (`JepaTarget`, the lift's held band) = a DEGENERATE I-JEPA (no
EMA, collapse structurally impossible). The MISSING piece I-JEPA weights most = the predictor's POSITION
CONDITIONING (mask token + positional embedding = "predict the embedding AT this location"). **That is exactly
`RelationalResidual`:** the 6D point `P6 (L,a,b,x,y,t)` + the `d6` metric + the `phi6` pairing (a<->x,b<->y,L<->t)
promote position from an implicit Morton index to a carried relational coordinate. phi6 makes it DEEPER than
I-JEPA: the conditioning position is the DUAL of the predicted colour.

**REALIZED AS A THEOREM (1199 -> 1200).** Added `RelationalResidual.dColour` + `lawPositionDistinguishesSameColour`:
two voxels with the SAME colour but different position are INVISIBLE to colour-only distance (dColour==0) yet
DISTINCT under d6 (==0 iff positions also match). So position carries info colour/the index cannot = the I-JEPA
positional value, proven. Additive; no settled law touched.

**ARCHITECTURE DECISION: ASYMMETRIC I-JEPA.** Frozen lift = TOKENIZER (and manufactures the collapse-proof
target), a LARGE learned position-conditioned PREDICTOR grows ON TOP. This does NOT reverse `EncoderFrozen`
(encoder stays parameter-free; `encoderParamCount==0`, `lawNoPreTrainPhase`, `lawPredictorIsTheOnlyLearnedObject`
all still hold; the predictor just grows). A full learned EMA TARGET encoder (symmetric I-JEPA) is NOT adopted
(it reintroduces the collapse problem the manufactured target eliminated) without explicit go.

**"CORE AI IS TO BE TRAINED" = train the large head on Mac, deploy to Core AI inference.** Core AI cannot train;
the path is MLX (Mac) -> `coreai-torch` (torch.export -> to_coreai -> save_asset .aimodel) -> Core AI inference
on device, float re-entering the Zig Q16 floor. A ViT-scale position-conditioned I-JEPA head DOES meet the
documented Core AI FLIP CONDITION, so Core AI is UN-RETIRED as a ROADMAP. coreai-torch is beta-absent here
(deploy-time gate, not a design blocker).

**APPLIED (this commit, all additive / docs-only, 1200 green):** `RelationalResidual` gains `dColour` +
`lawPositionDistinguishesSameColour`; CLAUDE.md gains a dated REDIRECT amendment (Core AI un-retired as the large
I-JEPA head, asymmetric path, EncoderFrozen NOT reversed, tiny-theta_B + zero-dep rules stand); `EncoderFrozen`
header scope-noted (candidate-b rejection scoped to the tiny path; large head lives above the encoder).

**NEXT (ordered, spec-first).** (1) add the positional channel to the predictor's context (a new `featuresBPos`,
ADDITIVE, do NOT re-pin the 63-param featuresB/golden) + `lawPositionConditioningStrictlyHelps` (mirrors the
sibling keystone). GATED: (2) MLX trainer for the large position-conditioned head (the thing that actually trips
the flip condition); (3) coreai-torch -> .aimodel -> device inference (beta + device only); (4) un-orphan the
Core AI seam ONLY when a real trainer + weights exist. CONFIRM before symmetric path (learned EMA target encoder)
- it flips lawNoPreTrainPhase + makes NeuronRedundancy/VICReg load-bearing.

---

## 2026-06-22: Core AI seam RETIRED via retag (disposition resolved) (branch `chore/retire-coreai-seam`)

> **Session theme (Daniel's direction):** "investigate this with a workflow, there is nuance." Workflow
> w6mwkczx5 (Core AI web-searched) reconciled every meaning of "L" and resolved the disposition.

**VERDICT: RETIRE the Core AI seam via retag (not delete, not repoint at DisplayDecoder).** Reconciliation of
"L": CarrierL = DETERMINISTIC carrier (no net); the encoder's only learned object is the 63-param theta_B
(hand-written, MaskedBandForward.swift); the grayscale-L look-net the seam was built to run was ABANDONED
2026-06-17 (look_net_trained.s4ln deleted, global-palette path V2-deferred Feature.globalPaletteV2=false);
DisplayDecoder is a spec-only quarantine STUB (no net, no trainer). Verified: look_net_trained.s4ln absent,
globalPaletteV2=false, predictL has ZERO callers.

**THE NUANCE (why not mechanical):** the 2026-06-20 amendment was NOT bad design, it was a correctly-built
bridge whose far bank was demolished (look-net abandoned + encoder resolved to need no learned L). The trap
avoided: repointing at DisplayDecoder is a SHAPE-match not a NEED-match (its quarantine guarantee means its
float can never reach a committed byte = ZERO determinism pressure = the opposite of a Core AI justification;
plus it is a one-line stub). Core AI's real niche is LARGE frozen models + ANE scheduling; for a 63-param net
the repo's hand-written-forward (theta_B) and MPSGraph (A/B) precedents are strictly better and keep the
zero-third-party ethos.

**APPLIED (non-destructive, comment/header only, no golden touched):** retagged CoreAILInference.swift,
export_l_coreai.py, coreai_export/README.md as ORPHANED 2026-06-22; demoted the CLAUDE.md 2026-06-20 Core AI
amendment to a SUPERSEDED footnote (kept as historical record) and rewrote the deploy-L spine bullet to
"Deploy theta_B: hand-written Swift forward, no Core AI." No files deleted (audit trail + iterative-not-replacement).

**FLIP CONDITION:** resurrect Core AI ONLY if a genuinely LARGE on-device generative-L head ("L = generative GPT
over the cube ladder") is roadmapped with a real trainer + weights (Core AI's actual niche). Currently
superseded and unscheduled.

---

## 2026-06-22: Full encoder alignment = hand-written theta_B forward (Core AI NOT needed) (branch `align/coreai-lnet`)

> **Session theme (Daniel's direction):** "continue with the full alignment." A workflow (wnzclasdm,
> Core AI web-searched) resolved what the Core AI L-net IS, then I built the real alignment gap.

**RESOLUTION (verified from canon): the current JEPA encoder does NOT need Core AI.** The encoder is the
FROZEN reversible lift (encoderParamCount==0, EncoderFrozen.hs) + the 63-param theta_B masked-band predictor
(the ONLY learned object). theta_B is a 9-wide dot product per band = a hand-written Swift forward per
CLAUDE.md ("on-device NN inference = hand-written forward pass, never a CoreML black box"). The Core AI seam is
ORPHANED: it targets a "frozen grayscale-L net" that was never trained (load_frozen_l_net = NotImplementedError,
no look_net_trained.s4ln); the only blob is the defunct 384-DOF color look-net (look_net.s4ln); and the
.aimodel toolchain is beta-absent (coreai-torch missing; coremltools 9 emits .mlpackage, a separate runtime, no
bridge to Core AI). Core AI is device + iOS-27 only, absent from the simulator (coreai-models issue #49).

**THE REAL ALIGNMENT GAP CLOSED.** The encoder chain: RGB->OKLab (unified+gated) -> frozen lift (Zig s4_haar,
on device) -> featuresB (9-D) -> theta_B forward -> Q16 re-entry -> GIF (byte-exact on device). Hops featuresB +
theta_B existed ONLY in the Haskell spec with ZERO device port. Closed:
- `Codegen.MaskedBand` -> `SixFour/Generated/MaskedBandGolden.swift` (fixed theta_B + 5 cases -> rawMaskedBand +
  the committed Q16 byte, computed by the spec; wired in spec.cabal + app/Spec.hs; regen via cabal run spec-codegen).
- `SixFour/Native/MaskedBandForward.swift` (hand-written: featuresB + theta_B dot, left-fold to match Haskell
  `sum` order; commit = round-half-to-even = the single reenterQ16 crossing).
- `SixFourTests/MaskedBandForwardTests.swift` (the committed Q16 BYTE is BIT-EXACT vs golden, no tolerance; raw
  within tolerance; shape sanity).

**VERIFIED.** Python replica of the forward reproduces all 5 golden bytes EXACTLY (raw to 1e-12); cabal test
**1191 passed** (codegen module compiles, suite intact); **TEST BUILD SUCCEEDED** (arm64). On-device run is
Daniel's step (same as the GIF parity test).

**NEEDS-DECISION (user) + OWED.** (1) Core AI seam disposition: RETIRE / REPOINT at the quarantined
DisplayDecoder (the shown L-16^3, the only live object fitting Core AI's "float inference behind the Q16 floor"
contract) / DEFER. Recommendation: defer + retag the orphaned files; do not delete (iterative-not-replacement);
CLAUDE.md's 2026-06-20 Core AI amendment is UNTOUCHED pending this. (2) Owed: `s4_lift_oct` octant golden so
featuresB consumes exactly the spec's 7 bands (Hop 2 gap); a theta_B `.s4ln` blob writer (its own tiny 63-float
blob, NOT the 384-DOF look-net layout) + the MLX trainer (`trainBandJointStable`, mean gradient).

---

## 2026-06-22: Device GIF make/encode verification strategy (branch `deploy/device-gif-verify`)

> **Session theme (Daniel's direction):** "ensure the device can form the GIF and the encoder can run on the
> device. do we airdrop binaries or write a test? Core AI is to be web-searched." A workflow produced the
> strategy; I built + compile-checked the camera-free harness.

**STRATEGY: TEST, not airdrop.** The proof of record is an on-device `xcodebuild test` of the `SixFourTests`
bundle against committed Haskell goldens. Airdrop is rejected (a hand-built Mach-O cannot link the per-slice
arm64 Zig lib, cannot host Core AI's bundle-asset loading, and yields no pass/fail gate); it is kept only as a
human-eyeball fallback for the non-bit-exact Core AI float output. The simulator has no camera, so the input is
the deterministic golden or `s4_synth_burst` (the synthetic-data-harness exception to compile-only-no-run).

**THREE LAYERS.** L1 MAKE+ENCODE (byte-exact): `golden_input.halfs` -> `encodeBurst` (ditherMode 0 FS,
FC=2/SD=32/K=256/Lloyd=15) == `golden.gif`. L1b FULL-SHAPE LIVENESS: `synthBurst` a real 64x64x64 burst ->
quantize -> palette -> assemble -> valid GIF89a (no camera). L2 ENCODER (reversible lift): already shipped on
device (`ZigHaarTests` round-trip n=1..256). L3 L-NET via Core AI: device + iOS-27-beta only, self-skips until
`L.aimodel` + `predictL` exist.

**CONFIRMED the kernel is REAL (not a stub).** `s4_gif_encode_burst` is implemented (fold
widen->oklab->quantize->dither->palette->`s4_gif_assemble`) and byte-exact vs `golden.gif` (Zig
`gif_fixture_test`, in the 71/71). The Swift doc claiming `RC_NOT_IMPLEMENTED` was STALE; fixed. So the iPhone
arm64 makes the GIF byte-for-byte like the Mac (same Zig lib). L1 is transitively proven; the Swift test
confirms the FFI surface + runs it on real hardware.

**BUILT + compile-checked (TEST BUILD SUCCEEDED, arm64).** `SixFourNative.synthBurst` (only missing binding;
s4_synth_burst was already in the bridging header), `scripts/embed-gif-golden.py` ->
`SixFourTests/GifGoldenFixture.swift` (embedded base64 goldens, matching the Generated/*Golden.swift convention,
no resource bundling), `SixFourTests/DeviceGifParityTests.swift` (L1 + L1b + determinism). No iPhone simulator
installed here, so the device run is Daniel's step:
`xcodebuild test -scheme SixFour -destination 'platform=iOS,id=<UDID>' -allowProvisioningUpdates -only-testing:SixFourTests/DeviceGifParityTests`
(signing: `DEVELOPMENT_TEAM=QFTX3897B7` pinned; one-time add Apple ID in Xcode->Accounts).

**Core AI (web-cited).** WWDC26 Core ML successor; dev-beta, GA ~Sept 2026, iOS/Xcode 27, Apple-silicon device
only, ABSENT from the simulator (apple/coreai-models issue #49). On-device API: `AIModelAsset(url:)` ->
`AIModel(asset:)` (AOT-specialize + cache) -> `InferenceFunction` (inspect `InferenceFunctionDescriptor` /
`NDArrayDescriptor`) -> inputs as `NDArray`/`InferenceValue` -> `function.run(inputs:states:outputViews:)` ->
read output `NDArray`. Current scaffold uses the older `AIModel(contentsOf:)` spelling; `predictL` is a nil
stub. L3 verification = a `#if canImport(CoreAI)` device-only smoke test: assert `isAvailable`, load+specialize
`L.aimodel`, run one fixed input, assert non-nil/finite/correct-length (float is NOT cross-device bit-exact),
then route through the Zig zero-genome==floor short-circuit and assert the floor-routed GIF bytes are bit-exact
(the only golden-able tail). Build first: `export_l_coreai.py` (wire look_net.s4ln -> L.aimodel), bundle it,
implement `predictL`.

**NEXT (ordered):** (1) Daniel runs L1/L1b/L2 on the iPhone 17 Pro. (2) export `L.aimodel`. (3) implement
`CoreAILInference` (asset->specialize + predictL NDArray/run). (4) `CoreAILInferenceTests` (L3, isAvailable-gated).
(5) Daniel re-runs on the iOS 27 beta for L3.

---

## 2026-06-22: Canonical RGB->OKLab unification (kill train/capture input skew) (branch `color/unify-forward-oklab`)

> **Session theme (Daniel's direction):** "your findings are the work. continue. engineering by strict
> enforcement and structure." Acting on the pretrain/Core-AI design workflow's load-bearing finding: the
> FORWARD RGB->OKLab transform had FOUR divergent implementations, and the one the model trains on diverged
> from the bit-exact substrate. This is the JEPA-level analogue of the overflow bug: a frozen param-free
> encoder cannot adapt, so if training preprocesses colour differently from capture, it learns on a picture
> the device never produces.

**FINDING (verified by execution).** Four forward RGB->OKLab impls: (1) Zig `s4_linear_to_oklab_q16`
(integer matmul + icbrtQ16) = canonical, (2) Haskell `ColorFixed.linearToOklabQ16` = PROVEN==Zig
(color_fixture_test.zig), (3) device `ColorScience` float cbrtf -> oklabToQ16 round = DIVERGES, (4) trainer
`train_metric.py` numpy np.cbrt = DIVERGES. Ran the numpy path vs the Zig kernel on sample colours: max
divergence 35 Q16 LSBs on 9 of 10. Only the integer pair was pinned.

**STRICT ENFORCEMENT (one transform, gated).**
- Trainer: bound `s4_linear_to_oklab_q16` in zig_native.py; DELETED train_metric.py's numpy
  `srgb_to_linear`/`linear_srgb_to_oklab`; `gif_frames_to_oklab` now routes 8-bit frames through the canonical
  `s4_srgb8_to_oklab_q16`, so training preprocessing == device substrate byte-for-byte.
- NEW GATE `trainer/test_color_canonical.py` (4/4 pass): the Zig forward == the Haskell oracle golden
  (color_golden.json) byte-exact; numpy np.cbrt PROVABLY fails the golden (teeth proving why it is forbidden);
  regression guard blocks re-adding np.cbrt. The trainer is now a golden-gated consumer.
- Device: `SixFourNative.haarLevelColors` (the 16-colour shutter cascade) computed OKLab via float cbrtf
  despite its own doc claiming "through the verified Zig kernels"; swapped to `srgb8ToOklab`
  (s4_srgb8_to_oklab_q16). Compile-check: TEST BUILD SUCCEEDED (arm64).

**VERIFIED.** Trainer gate 4/4 PASS (run); the 35-LSB skew reproduced then eliminated (new path == kernel);
device build SUCCEEDED. The shipped GIF render already routes through `s4_gif_encode_burst` (canonical
linear->OKLab internally), so it was never skewed.

**RESIDUAL / NEXT (device-verified audit, not done here).** Remaining `oklabToQ16(float-OKLab)` committed
callsites (DeterministicRenderer / CaptureViewModel / SurfaceView) quantize Metal-FLOAT OKLab rather than
running the integer transform on the linear input; classifying which are model-committed vs display-only, and
routing the committed ones through `s4_linear_to_oklab_q16`, is a Metal-pipeline refactor that needs iPhone 17
Pro device verification. UI-display float OKLab (PaletteGrid/Cloud/Tree etc.) can stay float. Also still owed:
the well-formedness typed decode (`decodeBurstToCubeTensor` + `lawShortBurstRejected`), the portable
YCbCr10->linear decode, and the Core AI seam TODOs (predictL, .s4ln loader, fixed shape).

---

## 2026-06-22: Invertibility-on-silicon break-hunt + total-function redesign (branch `test/invertibility-silicon`)

> **Session theme (Daniel's direction):** "is the design invertible? could it work / does it work." Empirically
> verified the reversible core round-trips (Haskell 16/64/256 cubed on adversarial integers; Zig 33/33 incl. the
> negative floor-div sign trap), THEN ran an adversarial break-hunt across the real silicon path (Zig + Metal
> unified memory + SIMT/tensors + Core AI, agents reading Zig + Apple docs), found a real break, chose the fix
> philosophy (total function / reject), mapped form-follows-function, and actioned the redesign. Three workflows
> (9 / 42 / 4 agents). Zig tests 33 to 71; all additive; in-domain behaviour byte-unchanged.

**CONFIRMED BREAK (silent corruption on the SHIP path).** The owned Zig kernel gated only `isPow2(n)`; magnitude
was unchecked. On the shipped ReleaseFast build (`build-ios.sh:45` maps Xcode Release to `ReleaseFast`), an
out-of-domain Q16 value reachable through the user/Core-AI-controlled `s4_leaf_override` delta made `d = x - y`
(i32) WRAP SILENTLY: returned `RC_OK`, the LEAF round-tripped (wrap is bijective mod 2^32, so the leaf golden AND
the 64-bit Haskell oracle were BOTH blind), but the surfaced intermediate node was poison (detail -294,967,296
for true 4e9; parent INT_MIN). Debug/ReleaseSafe panicked loud; only the ship mode corrupted silent. LESSON: an
endpoint-only `reconstruct(analyze(x)) == x` test is insufficient for a multi-level lift; intermediates must be
asserted against i64 wide-truth (that is what the next level / the 16-colour shutter / Core AI actually read).

**TOTAL-FUNCTION REDESIGN (form follows function).** The form of the model is a bit-exact integer S-transform; a
function FITS it iff it is pure-integer, TOTAL, and invert-or-refuse. All 10 reversible exports made total
(`s4_haar_analyze/reconstruct/level_nodes`, `s4_rgbt_lift/unlift_quad`, `s4_cube_lift/unlift_level`,
`s4_haar_split/join_level`, `s4_leaf_override`). Added `RC_OUT_OF_RANGE = 7`; `SUBSTRATE_BOUND` B = 2^29-1,
`DETAIL_BOUND` 2B. Bound proof: the RGBT quad's 2nd-level high band is the binding 4B case = 2^31-4 (fits i32);
B+1 gives 2^31 (overflow), so B is tight; real OKLab Q16 is ~2^17, >4096x headroom, zero in-domain change.
`liftChecked`/`unliftChecked` compute the pair-lift in i64 then narrow-or-refuse (the check itself cannot
overflow; does NOT lean on the Debug-only panic). Domain guards at every C-ABI head; `s4_leaf_override` rejects
`|g+delta| > B` at the producer (the cheapest refusal point for the taste / Core-AI channel).

**TESTS (derived from the form).** 7 adversarial Zig files. The overflow/leaf-override witnesses now assert the
kernel RETURNS `RC_OUT_OF_RANGE` (refuses) instead of documenting silent wrap. New `totality_test.zig`: T1
totality (all 10 refuse out-of-range), T3 intermediate-truth via i64 oracle, T5 ship-mode parity, T6
domain-boundary knife-edge (B passes + round-trips, B+1 refuses). Plus CPU-proxy tests for the future
Metal/SIMT port hazards (in-place race, missing inter-level barrier, fp16 tensor bit-loss, unified-memory
premature read) which the CORRECT kernel survives and a naive port provably fails.

**VERIFIED (re-run independently, not on the agent's word).** 71/71 tests pass in Debug, ReleaseSafe AND
ReleaseFast. Direct ReleaseFast proof: the break witness returns rc=7 (refused, no corruption);
`s4_leaf_override(INT_MAX+1)` refused; in-domain analyze/reconstruct round-trip == id byte-exact. All
cross-language goldens (haar/rgbt4d/temporal) present and passing byte-for-byte. All 10 public function
doc-headers state the domain + refusal contract; `RC_OUT_OF_RANGE` documented.

**RESIDUAL (honest).** The on-device Metal/SIMT/Core-AI hazards are pinned by CPU-PROXY tests only; the real
`threadgroup_barrier`, the unified-memory completion-fence, and the float-to-Q16 `reenterQ16` quarantine still
need DEVICE tests on an iPhone 17 Pro once those layers exist (none are built yet). FOLLOW-UP: add a matching
Haskell-spec domain law so the oracle documents the same +-B domain the Zig kernel now enforces (the Haskell
`Int` is unbounded and would not refuse, so the cross-language golden compares in-domain only).

---

## 2026-06-22: Reversible-seam hardening + rubric-soundness review (branch `spec/harden-reversible-seams`)

> **Session theme (Daniel's direction):** review the prior JEPA-session work with a workflow, anchored on
> reversibility being the core feature; harden the weak spots; then, before committing, review the work
> AGAIN with a workflow asking "is the strategy sound? this spec is a RUBRIC, the actual tests determine
> validity." Two review workflows (9 + 10 agents) with spec-internal fixes between them. Suite
> **1180 → 1187**; all additive, golden-gated; `spec-codegen` produced ZERO drift to `Generated/`.

**REVIEW 1 (categorize + teeth, workflow `wbauq2fyq`).** Categorized the 21 new modules into 6 groups by
relation to the reversible core (ON-PATH / CONSUMES / OFF-PATH). Verdict: the reversible KERNEL is sound and
trap-free (`refine . split == id`, sub-quantum witnesses correctly closed-`Bool`), but the SEAMS binding it to
the object/rung/super-res wrappers delegated by prose, not teeth. Four confirmed defects.

**FIXES LANDED (13 files).**
- SameObjectJEPA test: `"OBJECTIVE:"` → `"SANITY"` (the law is an f-free Z2 identity the header demotes; the
  marker is reserved for the genuine objective in DetailMaskedPrediction).
- CubeTensor: `lawCubeTensorRoundTripsThroughKernel` (per-channel `octantSynthesize∘octantDistill`) +
  `lawCorruptBridgeFailsRoundTrip` (negative teeth).
- RungPivot: `lawRungRoundTripsThroughType`, `lawMkRungRejectsSideMismatch`, `lawLatentNeuronsStayContinuous`
  (the `Rung`/`mkRung`/`latentNeurons` types were exported but exercised by NO law (dead structure)).
- MaskedBandPrediction: `lawMaskedConsumesSiblingContext` + rewrote `lawMaskedReusesOnBothRungs` (was
  reflexive + drove distinctness off the COARSE value with siblings zeroed; now rides a visible sibling, so an
  option-A coarse-only model is provably excluded). Made it closed-`Bool`; rippled into SelfSupervisedRung +
  DeferredSurfacing (both ALIASED it through by analogy; the ripple WAS the proof of the delegation finding).
- SelfSupervisedRung: `lawOneOperatorTwoSupervisions` now also wires the numeric transfer law.
- SuperResPalette: `lawOverBudgetBeatsClamp` (k reps strictly beat a single-colour clamp; certifies the
  over-budget representative choice that was certified by nothing).

**REVIEW 2 (rubric soundness, workflow `w06do6gb2`), the load-bearing finding.** Judged each law not on
Haskell teeth but on "does passing it constrain the real MLX/Zig/Swift artifact?" Verdict **GO-WITH-TWEAKS**,
with an honest reckoning: of 9 new laws, **6 have an EMPTY falsifier set over every real artifact** (they
exercise Haskell-only constructs: the `Rung`/`IntermediateLatent` types, the Mac-side SoA bridge, a `[Double]`
latent list, with no on-device counterpart and no golden). Two of the three with real grip
(`lawMaskedConsumesSiblingContext`, rewritten `lawMaskedReusesOnBothRungs`) constrain θ_B's DESIGN SHAPE but
emit no golden yet, so their bit-exact bite is INDIRECT. Only `lawOverBudgetBeatsClamp` fully clears the bar
today. One honesty tweak applied pre-commit: relabelled the numeric conjunct in `lawOneOperatorTwoSupervisions`
as "θ generalises across coarse INPUT ranges" (transfer fixtures zero the siblings, so it is NOT a
sibling-reuse claim; an option-A model passes it).

**STRATEGIC CONCLUSION (carry forward).** This commit is correct spec-internal HYGIENE; it is NOT progress on
the Zig/MLX/Swift build, and the kernel↔wrapper seam it hardens is already the best-covered seam in the repo.
The real, un-ported, golden-free build risk is untouched and is the NEXT gate: (1) emit a `predictMaskedBand`
golden (fixed θ_B + fixed (coarse, siblings) → fixed Q16 byte, with a SIBLING-VARYING example) so the GOOD
masked-band laws bind the artifact, not just intent; (2) stand up the 4D reversible-dithering DATA ENGINE with
`s4_split`/`s4_redownsample` Zig kernels + a fixture (a non-invertible `_lift_quad` would pass every law added
here); (3) pin the CubeTensor Morton↔row-major order permutation with a golden. Per Daniel's principle: a law
earns its keep only when passing it constrains the real artifact.

---

## 2026-06-22 — JEPA world-model spec: encoder + four loops settled EMPIRICALLY (branch `spec/jepa-world-model`)

> **Session theme (Daniel's direction):** a GHCi-empirical, "nothing locked in" investigation of the JEPA
> learned world model — the encoder (GIF→embeddings), the two rungs of the `(2×2):(2×2)→1 + residual` op,
> the Hierarchical-JEPA levels, the L-16³ chroma-bleed UX, and the train / infer / continuous-infer loops.
> Several fan-out workflows, each adjudicated by agents RUNNING the real spec in `cabal repl`, not by
> reasoning. Multiple prior claims were overturned by the runs. Spec suite **1126 → 1180**; all additive,
> golden-gated; no shipped contract re-pinned. Two commits: `919df9d` (13 modules) + `ad45725` (PerAxisTraining).

**THE ARCHITECTURE (settled, refuting the prior sketch).** ONE fixed reversible kernel + ONE learned
predictor. The `liftOct` `(2×2):(2×2)→1` op is the FROZEN encoder (GIF→embeddings = `liftOct ∘ featuresB`,
ZERO params, NO pre-training); the only learned object is the 63-param masked-band predictor `θ_B` that
regresses the lift's held detail-band RESIDUAL. The "two predictors f + g" framing was **REFUTED in GHCi** —
"cross-scale f" and "temporal g" are the SAME fixed S-transform kernel on different coordinate slots
(`lawTemporalLiftMatchesHaar`), zero learned params. A rung = the op run twice around the 64³ pivot, exposing
the never-surfaced 32³/128³ mid-latent.

**14 new `Spec.*` modules (each: laws → golden gate → `Map` entry):**
- `CubeTensor`, `ProjectionQuery` — the voxel-tensor RAG read-as-projections (a projection-ordering is a
  lossless retrieval query; first lock on the 0-caller `orderingHash`).
- `RungPivot`, `HJepaLevels` — the canonical 64³-pivot rung + the H-JEPA level spine: three axes
  (SCALE × CHANNEL × TIME) but only SCALE is a level (only it has a never-surfaced symmetric intermediate).
- `MaskedBandPrediction` (per-band θ_B + two-rung reuse + numeric self-similar transfer), `MaskedBandTrainer`
  (byte-checkable training twin, golden `3000`; + `trainBandJointStable` fixing a real bug — below).
- `DeferredSurfacing` (latent search, surface 16³+residual after rung 2), `SelfSupervisedRung`
  (Held exact-label vs Invented consistency-gate; first consumer of `RedownsampleGate.passesGate`),
  `NeuronRedundancy` (within-latent VICReg covariance).
- `DisplayDecoder`, `ContinuousLoop` — the shown L-16³ is a LEARNED, quarantined decoder (NOT the
  architecture); the live steering loop commits invariant under the display decoder (end-to-end quarantine).
- `EncoderFrozen` (the encoder has zero params — a gate against a learned encoder), `JepaTarget`
  (the I-JEPA correspondence: data-manufactured target ⇒ no EMA, no collapse).
- `PerAxisTraining` — the six-axis ledger verified BY TRAINING (each of the 7 detail bands independently
  learnable), not just by the op layout.

**Overturned by GHCi (the value of running, not asserting):**
- Barlow Twins REJECTED as the learning objective (predictor-free ⇒ vacuous by SixFour's own bar); committed
  to cross-prediction with decorrelation demoted to a within-latent guard. The geometry (32³:128³ as a
  self-similar pair) is sound; the loss form is not Barlow.
- Self-similar reuse is CONFIRMED but CONDITIONAL (~99.9% under shared law, degrades under law-shift); the
  earlier "worse than floor" claim did NOT reproduce.
- The displayed L-16³ is a quarantined learned decode of the free latent, provably unable to move committed
  bytes — answering "I want to show an L-16³ but it need not be the architecture."
- Real bug found + fixed: `trainBandJoint`'s summed gradient with fixed η DIVERGES to NaN on a batch of 8
  high-ṽ examples; `trainBandJointStable` (mean gradient) converges on the same fixture. Additive — the
  original trainer and every golden trained against it are untouched.

**NEXT (out of spec scope — a bigger implementation phase):** the 4D reversible-dithering DATA ENGINE
(emit `(coarse, held, palettes, index-maps)` records; the standing #1 unblocker), then the Zig kernels
(`s4_split`/`s4_redownsample`/`s4_passes_gate`), the MLX `θ_B` trainer, and the on-device hand-written forward.

## 2026-06-18 (late) — Per-frame PIVOT: VoxelReduce, global→V2 deferral, the A/B game (merged `e2b812c`)

> **Session theme (Daniel's direction):** the global-palette collapse "takes away from the
> spatio-temporal" — retire it from MVP1 and build the real product: capture → two ORTHOGONAL 16×16
> candidate looks A and B → user plays the game (each pick folds taste, the next pair narrows) →
> export the full {16³,64³,256³} stack carrying the genome → learnings persist. ~13 commits across
> two merges (`b232bb2`, `e2b812c`); spec suite 877 → **911**; iOS BUILD + GRID lint green throughout.

**The reframe.** The product is NOT one global palette. It is per-frame palettes reduced by a
reversible `(2×2)×(2×2)→1` lift into a PAIR of orthogonal 16³ genomes the user A/B-tests, with a
learned reversal to 256³. Most of it already existed as buried/ungated spec. Four workflow docs map
it: `SIXFOUR-PER-FRAME-GENOME-AB-MIGRATION-WORKFLOW` (pillars + phases), `-REUSE-FIRST-NO-NEW-DEBT`
(compose owned primitives, don't re-port), `-GLOBAL-PALETTE-RETIREMENT` (the V2-deferral map),
`-AB-GAME-EXPORT-LEARNINGS` (the user story + G1–G7).

**Built (each: gate the spec → reuse-first port → golden/laws → honest doc):**
- **Phase 1 — `VoxelReduce`** (64³↔16³ reversible) owned in ALL FOUR languages: Haskell
  (`lawVoxelReduceBijective`), Zig (`s4_haar_split_level` reusing a factored-out `sLift`; −4 inline
  S-transform copies), Swift (reuses the golden-gated `RGBT4DLift`). Composition of owned bijections.
- **Global → V2 deferral (NO deletion).** ONE gate `Feature.globalPaletteV2 = false` makes MVP1
  per-frame ONLY. A reachability re-map found **FIVE** entry points (capture router + Review
  Ship/group-pick/cut-lever/Atlas), all guarded + a stale-`.global` sanitizer. Retagged
  DEPRECATED→V2-DEFERRED; freeze-lint stays a freeze; `verify-doc-claims` ANCHOR-1b asserts the flag
  ships OFF. Per-frame path proven independent → gating can't break it.
- **The A/B game (G1–G7).** `DivergenceSchedule` (Δ=|r_A−r_B| start-wide-converge); `GenomePair`
  Swift port (EXACT-orthogonal, `genomeInner δ_A δ_B == 0`); `ABCandidates` + `CandidatePickView`
  (16×16 `CellSprite` tiles, GRID-conformant) wired to the BUILT n=0 taste loop (pick→`btUpdate`
  θ→re-propose); `ABExportFamily` {16³,64³,256³}+genome; `GenomeCarrier` S4GN codec; `GeneArchive`
  warm-start; `NetSynth256` SCAFFOLD; `ABSurface` 8-phase FSM.

**Findings worth keeping:**
- **Silent orphan specs.** `GenomePair`, `ABSurface`, `GenomeCarrier` were in `spec.cabal` but had no
  `Properties.*` test — their laws (incl. the A/B orthogonality KEYSTONE) had never run; `ABSurface`
  wasn't even compiled. Now all gated (+23 laws). *Check `Properties.X` exists before trusting a module.*
- **The GRID lint is a HARD build phase for ALL of `SixFour/UI`** — every `spacing:`/`.frame(`/`.padding(`
  point literal must go through `GlobalLattice.pt()/.gif()`; grids render via `CellSprite`. It failed
  the first picker build.
- **Reuse-first paid off every phase** — VoxelReduce reused `RGBT4DLift`; the A/B port reused
  `haarReconstruct`/`leafOverride`; the taste loop reused `PersonalTaste`. The new code was small.

**Honest remainders (documented, not faked):** G6 `NetSynth256` is a no-op scaffold (==floor at zero
genome) — the learned weights need the on-device TRAINER, not a port. G7 movable candidate widgets
deferred — promoting to `ColorIdentity.candidateA/B` ripples the codegen `MoveContract` + the
disjoint-defaults golden + `MovableLayoutTests`, unverifiable on a no-simulator box.

---

## 2026-06-18 — Canonical path DECIDED + n=0 taste loop built & testable (branch `docs/nn-debt-cleanup-2026-06-18`)

> **Session theme:** stop the candidate oscillation. Decide ONE canonical core, clean the docs that
> would mislead about it, and build the n=0 personalization loop end-to-end so it can be tested on
> device. 10 commits; spec suite 834 → 877; Zig 29 → 31; doc gate green at every commit.

**The decision (`docs/SIXFOUR-CANONICAL-PATH.md`, via a 15-agent research+reconcile workflow):** ONE
Gumbel-AlphaZero policy+value predictor as a *bounded addition above a frozen Q16-idempotent maximin
floor*, read at search budgets **n=0 / n=1 / n=8–16** — which subsume the deterministic / residual /
AlphaZero candidates (supervised MSE Look-NN rejected). `lawTerminalQuantizationIdempotent` is the
spec-backed unifier: learning re-ranks/tints, never rewrites the floor. v1 ships value-only over a
frozen policy; the enriched taste organ (Laplace posterior, Double-Thompson, IPO/KTO, Oklch+ warp)
has zero repo footprint and is demoted to PROPOSE-SPEC. The critic caught a real latent bug: the
anti-collapse β-ramp gates on `awHumanCompares`, which **does not exist** (`awCompares` counts
synthetic too) → blocking prerequisite.

**Built this session (each: existing/new spec → owned impl → golden → honest doc):**
- **board-q16** (`s4_board_mass_q16`): deterministic Q16 board mass, closes the float-input hole. WIRED.
- **glrm** (`GLRM.swift`): preference kill-switch, refuses to train on no-signal picks. WIRED into `AtlasTrainingSession`.
- **s4_leaf_override** + **ThetaToDelta** (spec-first): the σ-pair generator-space tint. ⚠️ OWNED-BUT-UNWIRED (step 3+).
- **DECN v2** (additive `CMPE` chunk): 770-D embeddings per Compare, version-stable. Spec binary + Swift JSON twin.
- **n=0 taste loop** (`PersonalTaste` + `AtlasState.choose`): on each A/B pick, freeze embeddings → `btUpdate` θ → persist → recolour palette by a **leaf-space** tint (maximin floor isn't σ-pair) → log `category=atlas.taste`, surfaced in `AtlasGalleryView`. The first end-to-end personalization loop. Test on device: `log stream --predicate 'category=="atlas.taste"'`.

**Debt cleanup (self-audit workflow):** closed a false-green (`Spec.ThetaToDelta` claimed a Properties
test that didn't exist → wrote it, found+fixed a float-`==` law bug); added the **§A WIRED vs
OWNED-BUT-UNWIRED ledger** (the anti-look-net-trap artifact); reconciled counts/dates/DONE markers;
documented the arm64-only headless build incantation in CLAUDE.md.

**NEXT (canonical path build plan):** 2b-iii `GenomePair` (real orthogonal A/B candidates) → step 3
pin the value-net `NetIOSpec` (`atlas-value-spec-drift`) → step 4 `awHumanCompares` split → **step 5
the keystone `no-metal-golden-gate`** (first byte-exact Zig↔Metal golden, the GPU SIMT precedent).
See memory `sixfour-canonical-path.md`.

---

## 2026-06-17 — MLX look-net ABANDONED; AlphaZero reframe; Haskell backbone built (S2/S3/M2/M4/M5)

> **Session theme:** the supervised MLX look-net did not train well and was abandoned (trained
> outputs deleted). The core reframes AlphaZero-shaped: a policy+value net over a turn-based state
> machine where the moves are the reversible 2x2->1 LAB-collapse, the cube ladder 16^3<->64^3<->256^3
> is the abstraction, and a Bradley-Terry A/B preference is the reward. Everything bare-metal on
> SIMT + Metal (Zig CPU reference, MSL GPU, golden-vector parity; never mlx-swift, never CoreML).
> Done spec-first: the entire FULLY-VERIFIABLE lane is complete in Haskell (Tier 0). Suite
> **834 -> 870** tests; Zig 29/29; doc gate green throughout.

### The arc (workflows -> design docs -> build)
- **State inspection** (exhaustive workflow, 57 agents): `docs/SIXFOUR-STATE-INSPECTION-2026-06-17.md`.
  Verdict: deterministic spine shipped; learned + super-res halves spec-only/dormant. Also closed
  the Zig-export-surface debt (declared the 4 `s4_cube/rgbt_lift` header symbols, lit the skipped
  `rgbt4d_fixture_test` so Zig 28+skip becomes 29/29) and reconciled STATUS counts.
- **Look+value unification** design: `docs/SIXFOUR-LOOK-VALUE-UNIFICATION.md` (shared sigma-trunk +
  equivariant-policy / invariant-value heads). The merge-decision ADR
  (`docs/SIXFOUR-MERGE-DECISION-ADR.md`) is now OBSOLETE: it assumed reusable MLX weights.
- **AlphaZero collapse** design (exhaustive workflow, 36 agents): `docs/SIXFOUR-ALPHAZERO-COLLAPSE-
  DESIGN.md`. Resolved 4 cross-facet conflicts (one V, not three; determinism at the Q16 terminal,
  not per-move; one `GameMove` ADT; policy half honestly unbuilt so v1 = value-only + frozen policy).
  Algorithm: Gumbel-AlphaZero (Sequential Halving over <=8) + KataGo aux targets + GLRM kill-switch;
  MuZero rejected (dynamics are known + reversible).
- **SIMT/Metal web research** (recorded in design section 5.5): Zig does NOT compile to Metal (its
  GPU backend is SPIR-V/Vulkan; bridging needs banned deps) so "Zig + Metal" IS the golden-parity
  gate; MSL signed `/` truncates toward zero (the `@divFloor` trap); `simd_sum` reassociates floats,
  so the cross-tier contract is a Q16 integer key on a fixed-order reduction, not a float.

### Teardown (executed, gate-safe)
Deleted `trainer/out/{look_net_trained.s4ln, atlas_net_trained.npz, synth_looknet_grayscale.gif}`.
The doc gate PINNED `look_net_trained.s4ln` at 133923 B (removed that check first, isolating cause),
and `fixture_test.zig` loads `look_net.s4ln` (the regenerable GOLDEN fixture, KEPT, byte-different
from the trained blob; the loader test still passes). Stale dead-MLX prose corrected in 4 maps;
`HANDOFF-LNN-app-io-and-ui.md` deleted (verified referenced by no gate). STATUS line 185 reframed.

### Built this session (Tier 0 Haskell, +36 properties, all green)
- `Spec.AtlasNetEval` (S2, +5): the policy/value head forward oracle ported from `atlas_net_mlx.py`;
  sigma-invariant value + sigma-equivariant (delta-row-swap) policy PROVEN exactly.
- `Spec.AtlasGame` (S3, +8): the unified `GameMove = Edit | Curate | Rung` over PaletteSearch /
  AtlasMove / CubeLadder (non-invasive). `Compare` lifted out as reward; `applyRung Ascend T64 =
  Nothing` (synth-beyond forbidden); determinism anchored at `lawTerminalQuantizationIdempotent`.
- `Spec.BoardQ16` (M2, +8): integer binning + integer counts (permutation-invariant, proven via
  shuffle) + one-rounding Q16 mass, replacing the float `1/n` histogram that leaked into the argmax.
- `Spec.GLRM` (M4, +8): the preference-training KILL-SWITCH (hand-written OLS; STOP unless a stable
  fit over [coverage, beauty, ||chroma||^2] clears the R^2 floor; degenerate gallery pairs to 0
  weight). This is the brake the failed MLX run never had.
- `Spec.GumbelSearch` (M5, +7): Sequential-Halving root selection + the Q16 cross-tier key.
  `lawArgmaxKeyDependsOnlyOnKeys`: a GPU float that differs sub-key from the CPU still picks the same
  move (the formal antidote to `simd_sum` reassociation).

### NEXT (device-only; design section 5.5 says what to honor)
S4 `Cube.metal` byte-exact parity gate (floor-div helper, negative-fixture round-trip); M1 rewrite
`AtlasTrainer` value graph to linear-770 (MPSGraph on-device, re-measure ms/step); M3 hand-Metal
forward gated ordinally vs `Spec.AtlasNetEval`; then L-phase (policy head + corrected sigma
involution, KataGo aux heads, Mac expert iteration with true visit-count targets).

See memory: `sixfour-alphazero-pivot.md`.

---

## 2026-06-16 (later) — Genome-A/B "taste camera" pivot: design + 5 spec keystones implemented

> **Session theme:** a hard product simplify — **the NN genome is front-and-center, the UI collapses
> to capture → A/B(two competing 16³) → export-family {16³,64³,256³}**, every device trains its own
> genome on-device, and exported GIFs CARRY the genome (federated transport). Done spec-first via
> three multi-agent workflows, then 5 of the 6 new `Spec.*` modules IMPLEMENTED (not stubs).
> **All Haskell spec (Tier 0). Zig/Swift untouched — `zig build` still passes standalone.**

### The arc (three workflows → design docs)
- **Whole-repo map refresh** (workflow): the archived `APP-MAP.md` / `SIXFOUR-ARCHITECTURE-MAP.md`
  were stale post-RGBT-4D; refreshed both into `docs/` (un-archived) with a 13-item stale-claims
  ledger (e.g. "GIFB has 0 callers" → FALSE; VoxelCubeView DELETED not shelved; maximin-is-canon).
- **Genome-A/B pivot design** (workflow, 16 agents w/ adversarial critique): `docs/SIXFOUR-GENOME-AB-
  PIVOT-WORKFLOW.md` (8-phase `Spec.ABSurface` FSM, 6 spec modules, gated build order, decision
  ledger). Critics caught 5 real blockers, resolved: orthogonality lives in the **384-D Haar-
  COEFFICIENT** space by **band-disjoint support** (exact-0, no Gram-Schmidt); carrier is **Int32
  Q16** not int16; federated adoption is **one logged Compare**, never a θ splice; 64³ hero on base
  genome g0; "sub-band axes" are palette-Haar only (NOT coupled to spatial RGBT).
- **Research integration** (workflow): mined `~/CubeGIF` (a working float/NEAT predecessor of this
  exact A/B loop) + its 9 papers → `docs/SIXFOUR-GENOME-AB-PIVOT-RESEARCH-AMENDMENT.md` +
  `docs/SIXFOUR-RESEARCH-PAPERS-INDEX.md`. Verdict: R1/R2 are NOT gaps (σ-pair=generator, band-
  disjoint=orthogonality already decided); real wins = KataGo **aux-targets** + **gated promotion**
  (R3) + a new period-64 Q16 **`Spec.TemporalLoop`** for exact loop closure (R5).

### Implemented this session (each: full impl, `-Wall` clean own-file, all laws `True` in GHCi, wired into `spec.cabal` + `Spec.Map`)
- **`Spec.GenomePair`** (keystone) — `sampleOrthogonalPair`: two band-disjoint σ-valid candidate
  displacements; exact-0 `genomeInner`; θ-independent `captureMeasureRanking` cold start. 10 laws.
  (Inner A·B = 0.0 exactly; norms = 1024·√24 ≈ 5016 on a 128-generator palette.)
- **`Spec.TemporalLoop`** (NEW, R5) — period-64 Q16 cosine LUT, `loopIndex = mod 64 = .&.63`, exact
  `temporalCos(t+64)==temporalCos t`; low-freq temporal residual = owned integer-Haar low band
  (`liftPairT` pinned byte-equal to `analyzeFixed`). 8 laws. Distinct from float `Spec.Cyclic`.
- **`Spec.PersonalGenome`** — per-device θ lifecycle over real `PreferenceUpdate.btUpdate`; cold
  start, `replay`≡`btFit`, `personalBeta`=n/(n+50), KataGo gated promotion (`gatePasses` strict
  majority on last K=8). 8 laws (incl. `lawRegularizedObjectiveDecreases` via L-smoothness η≤1/L).
- **`Spec.GenomeBlend`** — federated receiver: foreign genome enters as ONE gated `applyPick`
  Compare, never a splice; `Extracted`=Present/Absent/Corrupt → outcomes. Gate resists *regression*
  not mere disagreement (both branches verified). 6 laws.
- **`Spec.GenomeCarrier`** — boot-only GIF89a S4GN byte codec: 24B header + 384×Int32-LE-Q16 + CRC32
  → 1564 body / 7 sub-blocks; total NoBlock/Corrupt/VersionMismatch extraction. 6 laws; **CRC32
  validated against the canonical `crc32 "123456789"==0xCBF43926`** vector.

### Build-order correction & open items
- **None of the 5 needed the planned step-1 `Quad4.paletteToVec` refactor** — their import cones are
  all pre-existing (LeafOverride/SigmaPairFixed/PairTreeFixed/Preference/PreferenceUpdate).
- **Documented stubs (parse-verified, NOT wired into cabal):** `Spec.ABSurface`, `Spec.ExportFamily`
  — the larger FSM + R-operator-ladder modules, for the next session. `ABSurface` needs the
  `Display.hs` clock-half split first.
- **VERIFICATION LEVEL (honest):** per-module `ghc -Wall -fno-code` typecheck + GHCi law evaluation
  + `cabal build --dry-run` (config resolves). The **full `cabal build` / `cabal test` gate was NOT
  run** this session, and no `Properties.*` test modules or codegen/Zig twins were written yet.
  STATUS.md not touched (this is design+spec scaffold, not shipped behaviour).

---

## 2026-06-16 — Tensor-math SOTA → the RGBT-4D reversible cube-ladder pivot (spec → shipped Swift)

> **Session theme:** a deep tensor-math SOTA review became an architectural pivot. The capture is a
> 64³ space-time colour mass; **RGBT IS the reversible 4-channel lifting** that makes a *lossless*
> 16³/64³/256³ cube ladder (and 256³ synthesis from the coarse tier) possible. Built spec-first,
> golden-gated, to a flag-gated Swift port. **All on master; 834 Haskell tests; the Swift port is
> standalone-verified + compiles in-target.**

### The arc (what shipped to master)
- **Tensor-math SOTA review** (deep-research, adversarially verified): adopted **`Sinkhorn`**
  (debiased divergence — discrete-OT fidelity tightening Bures), **`Barycenter`** (free-support W₂
  particle-flow collapse move), **`Entropy`** (the capture's information coordinates: RGBT pool
  weights + per-frame↔global scope cost). MoR design validated (NeurIPS 2025). Seams 4/5 = gaps.
- **The pivot = 1b + 2b** (`docs/SIXFOUR-CUBE-LADDER-GAP-ANALYSIS.md` + the hardening workflow): a
  *universal feature layer* (1b) with *semantic 4D R/G/B/T axes* (2b). Justification: **RGBT is the
  reversible `(2×2)↔1` lifting** — the semantic distinctness of the 4 sub-bands IS the invertibility;
  2a (symmetric) cannot be reversible.
- **Keystones, proven:** `RGBTLift` (the `(2×2)↔1` integer bijection, exact), `CanonicalPhase` (the
  loop gauge-fix via the necklace canonical form — proving it CAUGHT the naïve argmax+lowest-index
  rule failing under ties).
- **The pipeline:** `GroupRGBT.circularWindows` (stride-1 width-4 SIMT buffer; role-orbit +
  rotation-equivariance), `RGBTFeature` (1b layer, completeness-preserving), `CubeLadder`
  (16³/64³/256³ tiers — **LADDER BIJECTIVE within capture**, loss isolated to NN synthesis beyond
  capture). Q16 FNV golden pins.
- **Phase 5 (shipped iOS):** `SixFour/RGBT4D/RGBT4DLift.swift` — hand-written zero-dep port,
  flag-gated `AppSettings.rgbt4dEnabled` (default OFF ⇒ bytes unchanged). `floorDiv` restores
  Haskell's floor division (the one cross-language hazard).
- **Codegen golden (debt D1 closed):** `Codegen.RGBT4D` emits `RGBT4DGolden.swift`; the Swift test
  rides the spec-codegen drift gate instead of hardcoding values.

### Topology / findings worth keeping
- **Time is a circle.** Because the GIF loops, the data lives in **R³ × S¹** — the buffer must wrap,
  there is no privileged frame (gauge), and 2b's semantic phase needs `CanonicalPhase` to fix it.
- **The `wT` flicker blind spot:** the temporal weight is centroid-trajectory variance, so it reads
  ~0 on mean-preserving hue-flip flicker. FIX: define `wT` from mean inter-frame Sinkhorn divergence.
- **Entropy analysis (first measurement):** scope + RGBT weights are **capture-dependent** (adaptive
  justified); pool strategy is **regime-dependent** (centroid for smooth drift, OT-barycenter for
  multi-modal/burst); `color-burst` flips PerFrame@64³ → Global@16³ (scope is tier-dependent).

### ⚠ Caveats for the next session
- **Phase 5 is DEVICE-UNVERIFIED.** No simulators in this env; the build was forced to x86_64 while
  the prebuilt Native lib is arm64-only → link fails *here*. The port compiles in-target and its
  logic is standalone-verified exact; run `RGBT4DGoldenTests` on the iPhone 17 Pro simulator.
- **No consumer is wired** — `rgbt4dEnabled` is dormant; the shipped render path is byte-identical.
- **The Metal `simd_shuffle` kernel (Phase 5b) is unbuilt** (needs GPU); the seam-5 color-harmony
  loss remains an open evidence gap.

### Next (see `docs/SIXFOUR-RGBT4D-REMAINING-WORKFLOW.md`)
1. End-to-end `Spec.RGBT4D` pipeline (buffer→feature→ladder) — the remaining verifiable spec step.
2. The Metal kernel (device), then a consumer behind the flag (the three GIF89a products).
3. Fix `wT` (inter-frame divergence); Phase 6 statistical sweep; follow-up research on seams 4/5.

---

## 2026-06-15 — Spec-first declutter: from a Haskell bloat audit to a decisions-per-act cap law

> **Session theme:** the cluttered Review screen is a *symptom of a flat spec*. The fix is
> not rearranging buttons — it is adding the missing spec **layer** that bounds how many
> decisions an act may expose. Heavily workflow-driven (multi-agent ground → design →
> implement → **adversarial review**); the review repeatedly caught vacuous laws / false
> "byte-identical" / decorative controls before they reached a commit. **All on master,
> 785 Haskell tests + simulator BUILD SUCCEEDED.**

### The arc (what shipped to master)
- **Bloat audit** (`wf-haskell-bloat-audit`) → the spec is **not** bloated, it is
  *spec-ahead-of-implementation*. Deleted only 1 genuinely stranded module
  (`Spec.AddressPicker`); KEPT core proofs (`LookNetCompose` σ-equivariance, `LookCategory`
  north-star). **Lesson: TEST_ONLY ≠ bloat in a verified repo.**
- **Activate, don't delete.** `Spec.QuartetDelta` (palette-story Act II, 4⁴) shipped as the
  Review **motion-outline overlay** + its **frame-locked threshold slider**.
- **Cell-widget framework.** Utility widgets = **N×M GIF-pixel cells** (`docs/SIXFOUR-CELL-WIDGET-LANGUAGE.md`
  registry; app is 100% cell-authored). The **frame-locked 20 fps detent** (`CellDetent` +
  `lawTicksFrameMonotone`/`lawDetentTriadCoincident`) unified across every drag widget;
  **`LINT-DETENT`** gates it (caught a real cellTick misuse on first run).
- **Acts × Widget matrix** (`docs/SIXFOUR-ACTS-AND-WIDGETS.md`) — reconciled the two "Act"
  numbering systems: lifecycle acts (Live→Capture→Browse→Render→Review) vs palette-story acts
  (16²/4⁴/2⁸/export = the **curation sub-acts inside Review**).
- **2⁸ collapse-lever cut slider** (preview-only). cut→export found to need a **byte-exact
  genome-contract extension** (Swift-only, b16-first) — designed (`docs/SIXFOUR-CUT-EXPORT-CONTRACT.md`),
  deferred behind greenlight.
- **Form-follows-function reshape** (`docs/SIXFOUR-HOLISTIC-FORM-FUNCTION.md`): Review's
  8-button toolbar → **Ship · Refine · Retake**. "One cube, two gestures": SEARCH (navigate)
  + MODIFY (write the table).
- **THE KEYSTONE — `Spec.ActDecisions`** (`docs/SIXFOUR-LAYERED-ACTS-AND-SCREEN-MAP.md`).
  The clutter hole was a *void* between `Spec.Display` (which act?) and `Spec.CellMechanics`
  (how does one touch feel?): **no law bounded an act's decision count** — Review's 8 buttons
  violated zero laws. New layer `Act → ≤3 Decisions → Surface → one Completion` with the
  keystone **`maxDecisionsPerAct = 3`**, EMPIRICALLY proven (a 4th decision fails `cabal test`).
  8 laws, all skeptic-verified non-vacuous (golden = hand-written literals; `lawNoButtons`
  asserts exactly 4 cell-field surfaces; `ShutterTap` dropped from Live's decisions = the
  completer). **Spec-first: NO UI router yet.**
- **Act III browsing** = a real `Browsing` Display phase + `BrowsingPhaseField` + `picks→4⁴`
  wiring (merged from `feat/act3-browsing`).
- **Build/signing.** Pinned `DEVELOPMENT_TEAM` in `project.yml` (xcodegen was wiping it);
  documented the gitignored-pbxproj-drift + the vanishing-sim-runtime traps (compile via
  `generic/platform=iOS Simulator ARCHS=arm64`).

### ⚠ Caveats for the next session
- **Act III flow is DEVICE-UNVERIFIED.** Re-targeting `BurstComplete→Browsing` inserts a
  mandatory browse step + a `SurfaceView.pendingOutput` engine deferral that the simulator
  cannot exercise (no camera/burst). Merged per user request; if it misbehaves on device,
  revert `e7bc25d`'s flow change (the spec/UI scaffold can stay).
- **Device build** needs the Apple ID in Xcode → Accounts (team `QFTX3897B7` is pinned but
  the account must be logged in) + `xcodegen generate` after any branch switch.

### Next
1. **The router slice** — wire the Swift UI to render affordances ONLY from
   `ActDecisionsContract.swift`, so a control with no `Decision` row is *unrepresentable*
   (the spec stops describing the UI and starts generating it; the payoff of the cap law).
2. cut→export byte-exact contract extension (greenlit design, Swift-only b16-first).
3. The deferred Refine wizard sub-FSM (one decision per screen, Search→Modify).

---

## 2026-06-10 — Swipe-to-LOOK + R3D `.cube` LUT extraction (one transform, two projections)

> **Session theme:** "a look IS a LUT." Brought the GIF→LUT idea from
> `~/lut-generator/src/python/gif_palette_lut.py` into SixFour as ONE data-driven OKLab
> palette→palette transform with two projections: the live capture screen recolours on a
> horizontal **swipe**, and Review exports the SAME transform as a 65³ `.cube` for grading R3D
> in DaVinci Resolve. Spec-first, byte-exact, golden-gated. **750 Haskell tests + 28 Zig tests
> green; drift gate 24 symbols; iOS BUILD SUCCEEDED** (compile-only per the camera-app rule).

### Design decisions
- **OKLab, not CIELAB.** The python analyses in CIELAB; we port to OKLab so the whole transform
  reuses the existing byte-exact Q16 colour core (`Spec.ColorFixed`). A primaries coincidence
  (sRGB ≡ Rec.709 primaries, differing only in gamma) makes OKLab→linear land exactly in linear
  Rec.709 — so the Rec.709 output is correct. The cost: every zone edge/threshold is in OKLab L
  ∈ [0,1] units (NOT the python's L\* ∈ [0,100]); the luminance-preservation law pins this.
- **Transcendentals as spec-generated embedded 1-D LUTs.** Log3G10 decode + filmic `exp` would
  break integer determinism, so the Haskell spec generates `log3g10_decode_lut.bin` /
  `filmic_tonemap_lut.bin` (+ a Q16 `srgb_encode_lut.bin` for 6-decimal output) and Zig
  `@embedFile`s them — the `gamma_lut.bin` pattern. No float on the core path.
- **Q16 6-decimal `.cube`** (not 8-bit) for banding-free R3D; golden stays exact (Q16 ints).
- **Swipe = render param only.** The look recolours the palette; the index tile is untouched, so
  the 4 pt cell grid is structurally intact. The swipe is a clear background layer behind the
  widgets (the hero is `allowsHitTesting(false)`), so it never contends with the palette's
  tap-to-shoot / hold-to-move.

### Keystone laws (the feature pivots on these)
- ★ **luminance preservation** — the transform is chrominance-only (output L == input L).
- ★ **preview ≡ cube** — the live 256-colour preview and the 65³ voxel call a byte-identical
  `transferOklabQ16`; a regression there breaks the build.
- ★ **.cube grid ordering** (R fastest) — prevents an R/B-swapped LUT.

### Where it lives
Spec `Spec.{ZoneProfile,LookTransfer,RedFrontEnd,CubeLut}` + `Properties.*` (laws) +
`Fixtures.hs` (blobs + `lut_golden.json`). Zig `s4_zone_profile_q16` / `s4_look_transfer_q16` /
`s4_build_cube_q16` + `lut_fixture_test.zig`. Bridge `SixFourNative.{srgb8ToOklab,lookZoneProfile,
lookTransfer,extractLUT}`. UI `LookVariant`, `AppSettings.captureLook`, `LivePhaseField.lookSwipe`
+ look-name `CellText`, `SurfaceView` palette re-grade, `ReviewPhaseField` Export LUT + `LUTFile`.
Full design: `docs/SIXFOUR-LOOK-LUT-WORKFLOW.md`.

---

## 2026-06-07 — The GIFA cube becomes CELLS; capture→GIFA morph wired; raymarcher deleted

> **Session theme:** "render the cell grid EVERY time." The whole capture→GIFA experience now
> renders through the ONE cell-grid path — live preview, loading sweep, and the GIFA review cube
> are each a `cellColor(at:)` population function over `CellSprite`/`CellBitmap`. The Metal voxel
> raymarcher is **deleted**. Spec **584 green**; iOS build SUCCEEDED; 166 Swift tests pass except
> one **pre-existing** `FrontProjectionTests` ImageIO-decode failure (confirmed failing on the
> clean branch with this work stashed — not introduced here).

### How it was built (workflow-driven, riskiest-first)
Three multi-agent workflows (review → broad UI/UX design → cell-grid design), each with an
adversarial-verify stage that caught load-bearing bugs **before** code:
- **The orbit raymarcher is only pixel-exact when flat** — its √2/2 basis lands ~1.76 art-px/voxel
  at the hero. Proven (`Spec.VoxelFit.lawOrbitHeroNotPixelExact`) and retired in favour of an
  integer shear table. 8-bit cubes are *dimetric* (integer slopes), never rotated cameras.
- **`halfSpan` is the wrong window divisor** (the shear isn't centred on 0) → a centered `cubeBox`
  `(cu,cv,h)`, re-verified inverse≡forward-scatter to 0 mismatches across all 9 rungs.
- **`artPerVoxel=2` would gap the flat face** → the rasterizer is **cell-scale (1 voxel = 1 cell)**,
  so flat is a solid 64×64 byte-identical to the GIF (`lawRasterizeFrontIsGif`).

### What shipped (on `grid/ownership`, this session)
- **`Spec.VoxelFit`** (NEW, 584 tests): the discrete integer projection ladder + per-cell rasterizer
  (`cubeBox`, `cellProject`, `cubeRasterMap`) with laws: front == 2D GIF ∀ rung, box clips nothing,
  flat = 4096 cells, rotation reveals side faces. Codegen → `VoxelFitContract.swift` (+golden box /
  cell-count tables, `selfCheck`) + `VoxelFitContractTests`.
- **The cube AS cells** — `Surface.bakeCube` forward-scatter z-buffer → `CubeRaster` → `CellSprite`
  (same path as the preview). Near face plays the cursor frame; X/Y **discrete rung sliders** shear
  depth to reveal the (x,t)/(y,t) faces; integer pitch keeps it crisp as it shrinks-to-fit.
- **Live hero = the REAL camera** (`σ.previewTile` index cells, replacing a synthetic palette scroll).
- **Loading = REAL streamed partials** — `DeterministicRenderer.onPartial` surfaces the true
  `quantize→dither→significance→palette` buffers into `σ.indexCube` (the discarded quantize indices
  are now retained); the serpentine sweep shows the GIFA actually forming, in true colour.
- **Review = the TRUE per-frame GIFA** (`σ.palettesPerFrame`, 64×256, not frame-0 replicated).
- **One addressing function** `Surface.cellGlobal(x,y,t)` backs every cube reader.
- **DELETED (aggressive cleanup):** `VoxelCubeView.swift` (708L), `GIFPlayer`/`PlayerTransport`
  (dead legacy player + `GIFCanvas`), the `voxel_raymarch` Metal kernel (~200L), AppSettings
  `voxel*`/`playerMode` keys, `VoxelRestPoseIdentityTests`. Stale `6pt/384` comments fixed; the
  `SIXFOUR-CAPTURE-GIFA-FLOW` doc marked superseded by the `Surface` architecture.
- **Correction to the plans (kept):** the collapse/GIFB path is **NOT** dead — it's the look-NN's
  output target, reachable via `paletteScope == .global` (STATUS.md already recorded this). Left intact.

### Open / next
- Flat-cube on-screen size (~195pt) vs preview 256pt — slight morph shrink, easy to tune.
- Rung-stop count (`flat → quarter → iso`) — confirm the granularity feels right.
- The review **Share** button is still a placeholder (`accessibilityHidden`); wire `gifURL` through σ.

---

## 2026-06-05 — SUNSET / handoff: ethos-debt cleanup + display-FSM proven

> **Entry point for the next session.** This session ran a workflow-audited ethos &
> technical-debt sweep, then fixed/proved the high-value items. Everything is committed
> and pushed to `origin/master` (HEAD `73c530f`); working tree clean; `cabal test` =
> **517 green**, iOS **BUILD/TEST SUCCEEDED**, drift gate + GRID lint pass.

### What shipped (6 commits, newest first)
- `73c530f` — resolution log in `docs/SIXFOUR-DEBT-RECONCILIATION.md` **§0** (the live
  status table — read this first; it maps each of the 18 live findings → fixed/open).
- `8c560e7` — FrontProjection **golden** (`SixFourFrontProjection`) + `FrontProjectionGoldenTests`
  + a **runtime DEBUG log** in `GIFPlayer.frontProjectedFrames` (os.Logger category
  `frontprojection`) that checks RULE-CUBE-2D-IDENTITY on device.
- `176186d` — `Spec.FrontProjection` proves the 2D-GIF == cube-near-face identity
  (reuses `PlaybackClock threeDFrontFace == twoDFrame`).
- `98a032a` — `DisplayContractTests`: **cross-contract** parity (Display ↔ PlaybackClock ↔
  Lattice agree — the seam per-file selfCheck/drift-gate miss).
- `6dabded` — `DisplayContract.swift` codegen (FSM constants + `goldenCursorTrace`).
- `a4532a8` — **`Spec.Display`** proves the FSM `M=(Σ,ι,δ,λ,Π,κ)`, **T1–T9 + composition**
  (`spec/src/SixFour/Spec/Display.hs`, `spec/test/Properties/Display.hs`).
- `81dadd2` — Tier 1 cleanup: lattice-govern bare point dims, delete dead
  `GlassOverContent.swift`, rewrite DISPLAY-FSM §2.4.2 (glass retired), and a **codegen
  Sendable fix** (`CellContract.Golden`) that unblocked the contested-cell build.

### Hard constraint learned (do not forget)
- **The simulator has NO camera**, so the capture flow can't be driven there. Verify via
  **unit tests** (they run fine — contract tests don't touch the capture path) and
  **logs** (os.Logger / `print` in tests). A final **device A/B** is the only way to
  confirm visuals.

### Open / next steps (priority order)
Open/next-steps are tracked in docs/STATUS.md (Open debt table) as of 2026-06-05.

The full audit (ethos restatement, all 18 live + 15 dismissed findings, exact fixes) is in
`docs/SIXFOUR-DEBT-RECONCILIATION.md` (now archived under `docs/archive/`); the audit workflow
is `scripts/wf-ethos-debt-audit.js`.

---

## 2026-05-29 — Next session: FULL GIF creation in Zig (per-frame LAB palette, 20 fps)

> **Entry point for the next session.** The owned Zig core (`Native/`) currently ships
> exactly one kernel — `s4_load_look_net` (blob parser, `Native/src/root.zig:64`). This
> brief scopes the next real kernel: the **full GIF-creation pipeline in fixed-point Zig**,
> driven by the existing Swift capture/Metal/display layer. Decision lineage:
> [[sixfour-zig-quantized-core]] (integerize the palette pipeline with a deterministic
> argmin tie-break so GIF↔tensor round-trips are bit-exact MLX↔device). **Reproduce the
> existing algorithms faithfully — do NOT invent new ones.** The Haskell spec (`spec/`)
> is the verified source of truth and emits the contracts + golden vectors we gate against.

### 1. GOAL + acceptance
Product flow: **Swift/AVFoundation capture → 64 frames → per-frame 256-colour OKLab
palette that BALANCES the camera input (max LAB diversity/coverage, NOT MSE) → 64×64 GIF
frames → shown to the user @ 20 fps gold standard.** Zig owns the deterministic quantized
core; Swift keeps capture + Metal decode + display.

- **Accept (quality):** GIF quality ≈ current float Swift/Metal path — negligible loss.
  Per-frame palette is **surjective** (all 256 colours used) and **significant** (every
  slot ≥ `minPopulation` pixels). Coverage metric (not MSE) is the objective.
- **Accept (timing):** capture @ 20 fps (`activeVideo{Min,Max}FrameDuration = 1/20`),
  display @ 20 fps (5 centiseconds/frame in the GIF + a 20 fps `Timer`), nearest-neighbor
  upscale. Extraction+encode run **post-burst, offline** (no real-time deadline on Zig).
- **Accept (bit-exact):** once integerized, Zig output is bit-identical to the Haskell
  golden vectors (goldens shift from tolerance → EXACT) and reproducible Python/Swift↔Zig.

### 2. ALGORITHM MAP (concrete algo · canonical file:line to read · how verified)

**A. Per-frame palette extraction (cluster → select → nearest-centroid → significance)**
- **Wu variance-cut seeding** — 32³ moment histogram (hist + 9 moment tables), cumulate
  along L,a,b, greedily split highest-WCSS box on highest-variance axis until K=256.
  Read `SixFour/Palette/WuQuantizer.swift:99` (quantize), `:256` (bestSplit), `:233`
  (WCSS); CPU wrapper `Metal/KMeansPalettePipeline.swift:378`. Spec: `spec/src/SixFour/Spec/StageA.hs:77`.
  Verified: `SixFourTests/WuQuantizerTests.swift`, `Properties/Significance.hs`.
- **Lloyd K-means** — assign to nearest centroid (squared OKLab L2, strict `<` tie→idx0),
  accumulate linear+outer-product sums, divide by count (keep old centroid if count==0).
  15 iters GPU / 3 iters CPU+spec. Read Metal `Shaders.metal:375` (assign+accumulate,
  tie-break `:402`), `:443` (finalize), `:489` (finalize-stats covariance). Spec
  `StageA.hs:96` (lloydStep). Verified: `MetalKMeansTests.swift`, Haskell `varianceCutReference`.
- **Farthest-point (maximin) seeding** — diversity objective: seed0 = argmax dist-from-mean,
  then iteratively argmax min-dist-to-chosen. Read `KMeansPalettePipeline.swift:402`;
  spec `Significance.hs:269`. Verified: `lawSigMaximinVariety`.
- **Nearest-centroid assignment** — argmin squared OKLab L2 with **strict `<`, lowest
  index wins**. SIMD8 path `Palette/NearestCentroid.swift:67` (mask replace + horizontal
  reduction `:91`); scalar oracle `:165`; GPU `Shaders.metal:402`. Spec `Significance.hs:245`.
  Verified: `NearestCentroidTests.swift:46`.
- **Significance split-fill (rebalance)** — every slot count ≥ `minPopulation`; for each
  deficient slot pull the pixel NEAREST to palette[k] from a surplus slot (count > min).
  Terminates since 4096 ≥ 256·2. Read `Palette/SignificantSplitFill.swift:34` (rescue),
  `:78` (cells: mean/σ/count/provenance). Spec `Significance.hs:304`. Verified:
  `lawSigAllSignificant`, `lawSigMassConservation`, `SignificantSplitFillTests.swift`.
- **Covariance** — E[xxᵀ]−μμᵀ, upper triangle (LL,La,Lb,aa,ab,bb), empty→(1e-6,0,0,1e-6,0,1e-6).
  Read `Shaders.metal:489`/`:420`; assembly `KMeansPalettePipeline.swift:232`; spec `Significance.hs:193`.

**B. LAB/OKLab transforms + diversity/coverage objective**
- **OKLab transform** — sRGB↔linear (piecewise gamma) · M1 (lin→LMS) · cbrt · M2 (→OKLab);
  inverse uses M2⁻¹, cube, M1⁻¹. 18 bit-exact Ottosson constants. Read
  `spec/src/SixFour/Spec/Color.hs:45`, Swift `Color/ColorScience.swift:34`. Verified:
  `Properties/Color.hs` round-trip ≤1e-5 over 33³ grid, `ColorScienceTests.swift`.
- **Gamut coverage (16³ voxel grid)** — bin OKLab into 4096 voxels (`floor((v+0.5)·n)`),
  coverage = occupied/4096; this is the diversity objective maximized by farthest-point.
  Read `Spec/Coverage.hs:40`, `Spec/Bottleneck16.hs:44`, Swift `Editing/ClusterStatisticsOps.swift:306`.
  Verified: `Properties/Coverage.hs` (∈[0,1], monotone-under-union).
- **Diversity measures** — weighted covariance → Gaussian entropy ½ln((2πe)³|Σ|),
  effective-dim (trΣ)²/tr(Σ²)∈[0,3]. Read `Spec/Diversity.hs:38`, Swift `ClusterStatisticsOps.swift:288`.

**C. GIF encoder (LZW + per-frame palette table + STBN3D dither + 64×64 + timing)**
- **LZW (8-bit alphabet, variable code size, LSB-first)** — dict init [0..255], clearCode=256,
  endCode=257, first new=258; code size 9→12, increment when nextCode==(1<<codeSize); sub-blocks
  ≤255 bytes, 0x00 terminator. Read `Encoder/GIFEncoder.swift:190`; spec `gen/SixFour/Gen/GifWire.hs:203`.
  Verified: `GIFEncoderTests.swift` round-trip via `decodeLZWBlocks():274`.
- **GIF89a frame builder (per-frame Local Color Tables, no GCT)** — header 'GIF89a',
  LSD (packed 0x70), NETSCAPE2.0 loop, then 64× {GCE 0x04+delay, Image Descriptor 0x2C…0x87,
  768-byte LCT, LZW data}, trailer 0x3B. Read `GIFEncoder.swift:32`; spec `GifWire.hs:73`.
  Verified: byte-level structure tests in `GIFEncoderTests.swift:15`.
- **OKLab→8-bit sRGB** — `byte = clamp(round(x*255),0,255)` per channel after `okLabToSRGB`.
  Read `GifWire.hs:177`; Swift via `simd` + `okLabToSRGB`.
- **STBN3D blue-noise dither** — pre-computed 8³ mask (void-and-cluster, toroidal Gaussian
  σ²=1.5), tiled 8×8×8→64³; threshold picks nearest2 farther centroid. **Load
  `SixFour/Resources/stbn3d-8.bin` (512 bytes) — never regenerate.** Read
  `Generated/STBN3DContract.swift:28` (loadTiled), `Palette/Dither.swift:291` (blueNoiseSIMD);
  spec `Spec/STBN3D.hs:76`. Error-diffusion (Floyd–Steinberg/Atkinson) `Dither.swift:148`/`:334`,
  spec `Spec/Dither.hs:22`.
- **Brands gating the encode** — `CompleteVoxelVolume` (per-frame surjectivity, `Spec/Indices.hs:59`,
  Swift `SignificantVoxelVolume.swift`) + `SignificantSplitFill.rescue`. Encode consumes the
  witness at `GIFEncoder.swift:56`.

**D. Capture → frame → display + 20 fps timing**
- **20 fps burst** — `AVCaptureVideoDataOutput` delegate (x420 10-bit YCbCr), frame-rate
  clamped 1/20. Read `Capture/CaptureSession.swift:382` (clamp), `:499` (captureBurst),
  `:651` (delegate).
- **Metal YCbCr10→OKLab** — crop/downsample/linearize (colorSpaceTag OETF) → linear→OKLab →
  unsharp-L (0.6). Read `Metal/Pipeline.swift:25`/`:243` (readback OKLabTile). Stays Swift/Metal.
- **GIF display @ 20 fps** — `Timer` interval 1/20, `Image(...).interpolation(.none)`
  nearest-neighbor; reduceMotion freezes frame 0. Read `UI/Screens/Review/GIFReviewView.swift:115`,
  per-frame status `TimelineView(.animation(1/20))` `:54`. Encode delay 5cs `GIFEncoder.swift:40`.

### 3. ZIG INTEGERIZATION BOUNDARY

**Becomes fixed-point Zig (the owned quantized core):**
1. **Wu histogram + variance-cut seeding** (32³ moment tables → greedy split → centroids).
2. **Lloyd K-means** (fixed-point atomic-style accumulation; keep-old-on-empty; matched scale).
3. **Nearest-centroid argmin** — i32 squared distance, **DETERMINISTIC tie-break: strict
   `<`, lowest index wins** (mirror Swift/Haskell exactly). Output UInt16 indices [0,256).
4. **Split-fill rebalance** — distance-based donor pull (nearest-to-palette[k] from surplus).
5. **LZW + GIF89a serialization** — byte-for-byte port of `GIFEncoder.swift:190`/`GifWire.hs:203`
   (LSB-first, sub-block chunking, little-endian fields, minCodeSize=8).
- Fixed-point: Q16/Q24; `toFixedPoint(f32)→i32`, `distanceFixed→i64`. OKLab cube-root via
  Newton-Raphson if conversion is done Zig-side (or accept float centroids from Swift and
  convert). Fixed-point accumulation scale must match Metal's ×2^16 / ÷65536 (`Shaders.metal:460`/`:507`).

**Stays Swift/Metal (the seam):**
- AVFoundation capture + 20 fps timing (`CaptureSession`), Metal YCbCr→OKLab + unsharp
  (`Pipeline.swift`), live 10 fps preview, GIF display `Timer` (`GIFReviewView`).
- **STBN3D mask generation** — load the pre-computed `stbn3d-8.bin`; Zig tiles it, never regenerates.
- Blue-noise GPU dither path (`BlueNoisePalettePipeline.swift`) stays Metal. (Error-diffusion
  CPU dither MAY be ported but is optional — it is a Swift-only refinement, not in the spec.)
- `CompleteVoxelVolume` + `SignificantSplitFill` type-safe gates orchestration in Swift.

**Reuse the established C-ABI + bridge pattern** (cite `s4_load_look_net`):
- Static lib: `Native/build-ios.sh` → `zig build-lib src/root.zig -target {aarch64-ios,
  aarch64-ios-simulator} -O{ReleaseFast,ReleaseSafe}` → `libsixfour_native.a`.
- Header: `Native/include/sixfour_native.h` (C signatures). Bridge:
  `SixFour-Bridging-Header.h`. Swift wrapper: `SixFour/Native/SixFourNative.swift`.
  Link wired in `project.yml` (`preBuildScript` → build-ios.sh, `LIBRARY_SEARCH_PATHS`,
  `OTHER_LDFLAGS=-lsixfour_native`). Proposed new exports (caller-allocated outputs, no
  alloc crosses FFI):
  - `s4_quantize_frame(pixels[4096*3] f32, centroids[K*3] f32, K, out_indices[*]u16) i32`
  - `s4_gif_encode(frames u8*, frames_len, palettes (RGB8) , palette_count, out_path) i32`
- **Zig 0.16 facts:** `pub const panic = std.debug.no_panic` (no stack-trace symbols in the
  host binary); `align(1)` ptrs OK for scalar f32 loads on arm64 (SIMD/Metal consumers must
  re-pack); default integer wraparound `+%` (argmin comparisons are naturally checked);
  `zig build-lib` arm64-ios + simulator both green (s4_load_look_net shipped & tested).

### 4. REPRODUCTION RISKS / bit-exactness watch-list
- **Tie-break = strict `<`, lowest-index-wins** everywhere (scalar, SIMD8 lane-scan, GPU,
  Zig). Any `>` / `≤` / lazy handling flips indices on exact ties. (`NearestCentroid.swift:91`.)
- **Fixed-point scale parity** with Metal ×2^16/÷65536 (`Shaders.metal:460`,`:507`).
- **Lloyd iteration count** (15 GPU / 3 CPU+spec) — pick a mode and match it.
- **Empty-cluster = keep old centroid** (`Shaders.metal:454`, `StageA.hs:106`).
- **Covariance order** = (LL,La,Lb,aa,ab,bb); population divisor /n (NOT n−1).
- **Voxel bin** = `floor((v+0.5)·n)` truncation-as-floor; mixed round/floor misaligns coverage.
- **OKLab→sRGB = round (not truncate)**, then clamp; 18 M1/M2 constants bit-exact (1 ULP compounds).
- **LZW edge cases:** LSB-first bit order; code-size increment threshold `nextCode==(1<<codeSize)`
  (off-by-one corrupts); sub-blocks ≤255 bytes + 0x00 terminator; all multi-byte fields little-endian.
- **STBN3D determinism** — load `stbn3d-8.bin`, never regenerate (Euclidean ≠ toroidal mask).
- **Surjectivity check is PER-FRAME** (set cardinality == K for each frame), not global union.
- **Constants from contract, not hardcoded** — `minPopulation=2`, confidence Z=1.959963984540054,
  binsPerAxis=32 flow from `Significance.hs` codegen → Swift `SignificanceContract.swift`.
- **Order-of-eval** in fixed-point Lloyd accumulation — enforce row-major pixel scan
  (rounding makes addition order-dependent).
- **Cross-frame remap** not implemented; if introduced it must compose with quantization in
  Zig to keep commuting at fixed-point precision.

### 5. VERIFICATION STRATEGY (how to gate the Zig port)
- **Golden vectors from the Haskell spec** — `cabal run spec-codegen` already emits forward
  goldens (`trainer/generated/look_net_golden.json`, `Generated/*Contract.swift`). Add
  quantization + LZW + GIF-bytes goldens via `Codegen.Golden`. **Once integerized, flip the
  Swift↔spec goldens from tolerance (≤5e-3 / 1e-5) to EXACT byte/index equality.**
- **Cross-language fixture test** (mirror `Native/src/fixture_test.zig`, which checks the
  S4LN blob byte-exactly): Python/Swift writes a synthetic frame + centroids (+ expected
  indices/GIF bytes) as a fixture; Zig reproduces bit-exactly; `zig build test` gates it
  (skip-if-absent like the current fixture). Then an iOS integration test feeds Zig's
  quantize output into `PaletteGenerator.generate()` → dither → encode and asserts the GIF
  is byte-identical to the Swift path (`GIFEncoderTests.swift` round-trip on all 64 frames).
- **On-phone benchmark (iPhone 17 Pro, iOS 26)** — confirm 20 fps capture + 20 fps display
  hold, and measure quality (coverage, per-frame MSE diagnostics already surfaced in
  `GIFReviewView` perFrameStatus) ≈ current float path. Extraction+encode are offline, so
  only correctness/quality is gated here, not latency.

### 6. OPEN QUESTIONS for the user
1. **Fixed-point width:** Q16 or Q24 for OKLab? (Q16 cheaper; Q24 safer on the cbrt cube-root
   round-trip near gamut edges.) Need a target last-bit tolerance that does NOT flip indices.
2. **OKLab conversion locus:** does Zig do sRGB→OKLab (needs Newton-Raphson cbrt) or does
   Swift/Metal hand Zig float OKLab pixels + centroids and Zig only does integer argmin/LZW?
   (The capture survey says OKLab pixels already exist post-Metal — leaning toward the latter.)
3. **LZW in Zig now, or later?** It is the highest-risk byte-exact port but has no float
   nondeterminism. Port it together with quantization, or land quantize first and keep the
   Swift encoder until goldens are EXACT?
4. **Lloyd iteration count to standardize** for the device path: 15 (GPU parity) or 3 (spec)?
5. **Seeder of record:** Wu variance-cut vs farthest-point as the shipped default for the
   "balances the camera input / max diversity" objective (the 3-way selector currently
   picks K-means/Wu/Octree — which one is the Zig core's primary)?

---

## 2026-05-29 — Haskell→MLX alignment audit: open gaps (flags only)

> **Closure status (2026-05-29, branch `feat/haskell-mlx-alignment`, 6 commits, 289 spec
> tests green + golden/loss gates pass).** CLOSED: #2 Spec.Loss→MLX port, #3 loss golden
> (float64-CPU gate @1e-6 — MLX is f32, Haskell f64; reduced in f64 to hold 1e-6),
> #5 decoder→384 SigmaPairHead, #6 option4Theorem, #7 SIGMA_PAIR pins, #8 MLX smoke-test
> arm, #9 MLX↔torch check, #10 non-finite guards, #11 PonderNet halting loss, #14
> NetSlot.LOOK, #15 deploy-blob serializer (writer+format+round-trip; producer
> `trainer/export_look_net_blob.py`). PARTIAL: #1 — loss *target* ported+gated, but the MLX
> training *loop* script isn't written (also blocked by #4). BLOCKED: #4 training data empty
> (`trainer/data/*` = 0 files → can't actually train). DEFERRED (research-gated): #12/#13
> GRAM stochastic core + `spec-measure` on real captures. NEW FOLLOW-UP: the native loader
> `s4_load_look_net` is a declared C ABI contract (`Native/include/sixfour_native.h` +
> Swift seam) but NOT yet implemented in Zig nor wired into `project.yml` (bridging header +
> link) — this is the "first real kernel" of the owned Zig core ([[sixfour-zig-quantized-core]]).

Audit of the **MLX training** and **NN-design** seams. No code changed — this is a
flag log (the repo keeps deferred work as prose here, not as inline markers). Each item
is phrased to double as a **work-list for a follow-on dynamic workflow**: locus
(`file:line`), acceptance criterion, and dependency edges. Verified firsthand 2026-05-29.

**Healthy baseline (not gaps).** The *forward* path is bit-exact: `Codegen.MLX`
(`spec/src/SixFour/Codegen/MLX.hs`) is the real, primary 194-line `mlx.nn` emitter (NOT a
numpy stub); the golden gate (`trainer/check_golden.py`) matches MLX & PyTorch to the
Haskell oracle at 1e-6; σ-equivariance is proven in Haskell and verified bit-exact. Every
gap below is on the **training** and **design-pivot-wiring** side, never the forward math.

### A. Training pipeline — the core hole
1. **No look-NN trainer exists.** `trainer/` has only `train_metric.py` (Stage-A PSD
   metric); there is no `train_look_net_mlx.py`. The "MLX is the primary trainer"
   contract (`CLAUDE.md:23`) is currently true only for the metric organ, not the look-NN.
   *Accept:* an MLX training loop produces look-NN weights. *Dep:* needs B (decoder dims) + #2.
2. **`Spec.Loss` not ported to MLX/Python.** `spec/src/SixFour/Spec/Loss.hs` defines
   fidelity (Bures-W) + coverage + Ou-Luo beauty; no fidelity/coverage/beauty/bures/
   `lookNetLoss` anywhere in `trainer/*.py` (outside `generated/`). *Accept:* MLX loss fn
   matches `Spec.Loss` within tol on a golden case. *Dep:* needs loss golden vectors (#3).
3. **No loss/gradient golden vectors.** `trainer/generated/look_net_golden.json` +
   `check_golden.py` cover the **forward pass only** (`check_golden.py:77` is
   `torch.no_grad()`; no loss/backward/grad). Training numerics are unverifiable against
   Haskell. *Accept:* `Codegen.Golden` emits loss (and ideally grad) reference cases.
4. **Training data empty.** `trainer/data/captured_frames/` and `…/reference_gifs/` are
   both 0 files; the metric trainer `SystemExit`s with no GIFs. *Accept:* a documented
   data-acquisition path (real captures from the on-device session dir, or synthetic).

### B. SigmaPairHead design pivot — spec is ahead of codegen (the long pole)
5. **Decoder emits the committed 384-DOF SigmaPairTree.** CLOSED: `look_net_mlx.py:33`
   and `look_net_torch.py:33` read `DECODER_OUT_DIM = 384 # = SIGMA_PAIR_DOF` and reconstruct
   the 256-leaf σ-pair palette. The spec derives it at LookNetD.hs:117/315 (== 384).
6. **`option4Theorem` dead-ends at `Quad4ReconAchroma`.** The `Spec.Pipeline` composition
   theorem is not re-instantiated at `SigmaPairHead` (see NOTES 2026-05-28 open Q#2 +
   "Risks"). *Accept:* a `SigmaPairHead` instance proves conditional σ-equivariance.
7. **`SIGMA_PAIR_*` codegen pins emitted everywhere.** CLOSED: `SIGMA_PAIR_DOF=384 / DEPTH=7
   / LEAVES=256` emitted at look_net_mlx.py:40-42, look_net_torch.py:40-42, net_shape.py:37,
   NetContract.swift:48, contract.rs:23-25. Sources: Burn.hs:58-61, Shapes.hs, CoreML.hs:89-98,
   MLX.hs, Swift.hs:319.

### C. MLX-specific verification gaps
8. **MLX σ-equivariance is verified in `smoke_test.py` Step 3b** (smoke_test.py:73-106:
   imports mlx.core + look_net_mlx, transfers torch state_dict, asserts mlx_delta == 0). CLOSED.
9. **Direct MLX-vs-PyTorch forward comparison present** — smoke_test.py Step 3c (:108-123)
   is a same-weights MLX↔torch allclose at rtol 1e-5. CLOSED.
10. **NaN / non-finite guard implemented in `run_torch` and `run_mlx`** (check_golden.py:101-103
    and :132-134 append (name+":nonfinite", inf) on non-finite output). CLOSED.
11. **PonderNet halting loss trained via KL(halting-dist ‖ geometric-prior)** in
    Spec.Loss.haltingLoss (Loss.hs:343), mirrored in look_net_loss_mlx.py and actively trained
    in train_look_net_mlx.py:103 (total += lam_halt·halt). CLOSED.

### D. GRAM stochastic core — design-only, research-gated (defer)
12. **Stochastic L4 core deferred** (`spec/GRAM_MAPPING.md`); VI target `y` unresolved
    (2026-05-28 open Q#5). Current `LookNetR` core is deterministic Mixture-of-Recursions.
13. **`spec-measure` on real captures still pending** (2026-05-28 open Q#1) —
    `sigmaSymFraction` measured only on synthetic palettes, so the SigmaPairHead decision
    (and B above) lacks on-device evidence. *This gates B and D; do it first if data exists.*

### E. Extra missing threads (beyond the four categories)
14. **The look-NN is not a first-class `NetSlot`.** `trainer/generated/net_shape.py` /
    `Spec.Net.hs` register only `NetSlot.METRIC`; look-NN dims (`MODEL_DIM`, `CORE_DEPTH`,
    `DECODER_OUT_DIM`, `MAX_TOKENS`) live only inside the model files via
    `CoreML.emitLookNetConstants`, not in the shape-contract registry. *Accept:* a
    `NetSlot.LOOK` (or similar) with a `NetIOSpec`, pinned like the metric.
15. **No deploy-blob serializer.** `MLX.hs:13` intentionally omits a `build_mlpackage`
    analog (MLX weights → plain binary blob for the hand-written Swift forward pass), but
    nothing yet *writes* that blob. It is the unwritten second half of the missing
    `train_look_net_mlx.py` (#1). *Accept:* a documented MLX-weights→blob format + writer.

### Dependency order for the closure (Phase 2 dynamic workflow)
```
B (SigmaPairHead 384-DOF) ─► regen golden (Codegen.Golden) ─► A (trainer + Spec.Loss port)
                                                                      │
C (MLX verify arm, NaN guard) ── mostly independent ──────────────────┘
D (GRAM core) ── research-gated on #13 ── defer
```
Plan with full Phase-2 workflow sketch: `~/.claude/plans/snug-zooming-dewdrop.md`.

---

## 2026-05-28 — σ-pair decoder pivot (Quad4 rejected → SigmaPairHead adopted)

**Session goal.** Unify three new spec primitives — the 16³ OKLab histogram
bottleneck (`Spec.Bottleneck16`), the σ-eigenspace split (`Spec.SigmaDecomp`),
and a 4-ary opponent-quadrant decoder (`Spec.Quad4`) — into one coherent
look-NN pipeline, and decide between binary PairTree and 4-ary Quad4 for the
L6 reconstruction stage.

**What the session committed.** Seven commits on top of `80b9843`:

| Commit | Lines | What |
|---|---|---|
| `3cb1be5` | +1198 | Substrate: GMM + Bures (W₂ on Gaussians) |
| `e09c791` | +3376 | Look-NN spec: 9-layer pipeline (L1…L9), 768-coeff PairTree |
| `c4f8e8e` | +2361 | Tooling: spec-tui, spec-gif, spec-gen |
| `a96d1c5` | +848  | Bottleneck16 + SigmaDecomp + Quad4 (the redesign primitives) |
| `ab27a16` | +548  | Spec.Pipeline (Stage / SigmaEquivariant type-class framework) |
| `06f8746` | +519  | LinAlg + Quad4Fit (tensor measurement on Quad4) |
| `f7667b8` | +341  | SigmaPairHead (σ-pair-symmetric decoder, tensor-verified) |

Net **+10,497 / -701** across 100 files. **191 spec tests pass.**

### The pivot in one paragraph

`ab27a16` encoded the σ-equivariance claim of the plan addendum (§A) as a
Haskell type-class framework. The composition theorem `option4Theorem`
typechecks — proving that *if* every stage is `SigmaEquivariant`, the whole
pipeline is. The user noted this proof is **structural only**: it certifies
shapes commute, not that the architecture has the right representational
power. The follow-up commit `06f8746` built the Quad4 design matrix
`B ∈ ℝ^{768 × 511}` explicitly and measured its image via Modified
Gram-Schmidt. **Finding:** Quad4's residual on σ-symmetric synthetic palettes
was *indistinguishable* from its residual on random palettes (median ≈ 6 %
both, contrast ratio ≈ 1). Quad4's image cuts ℝ⁷⁶⁸ at some generic angle
that captures concentrated palette content equally well regardless of σ
structure — it is **not** preferentially σ-aligned. The plan's claim "Option
4's Quad4 decoder yields σ-symmetric output by construction" was false at
the tensor level.

`f7667b8` introduced **`Spec.SigmaPairHead`** to fix this: instead of
freely-parameterised 256 leaves, emit only **128 σ-pair GENERATORS** via a
depth-7 binary Haar pyramid, and define the 256-leaf palette as
`[c_0, σ(c_0), c_1, σ(c_1), …]`. The σ-pair structure is now algebraic; every
odd leaf is the σ-reflection of its even predecessor for *any* genome. The
design matrix `B ∈ ℝ^{768 × 384}` is full rank (384) — exactly the dimension
of the σ-symmetric palette subspace — and the empirical residuals are:

| | SigmaPairHead | Quad4 |
|---|---|---|
| Rank | 384 (full) | 511 (full) |
| σ-symmetric residual (median) | **0.0** (≈ 1e-15) | 0.06 |
| Random palette residual (median) | 0.09 | 0.06 |
| **Contrast (random / σ-symmetric)** | **≈ 10²⁸** | ≈ 1 |

The contrast ratio is the architectural signature. SigmaPairHead is **10²⁸×
better** at fitting σ-symmetric content than random palettes; Quad4 has no
σ-preference at all.

### Why this matters

The "128 σ-balanced pairs" headline of `LOOK_NN.md` was always aspirational.
A free-parameter tree (binary or 4-ary) achieves σ-symmetric output only via
a learning signal — the architecture itself provides no guarantee.
SigmaPairHead is the structural inhabitant the headline required. Its DOF
(384) is exactly the σ-symmetric subspace dimension — **zero wasted DOF on
σ-antisymmetric content the constraint forbids**.

### Open questions left for the next session

1. **`spec-measure` exe on real captures.** The σ-symmetric / random
   distinction was measured on synthetic palettes drawn from a [0.2, 0.8] ×
   [-0.2, 0.2]² box. The decision-relevant question — what does the
   `sigmaSymFraction` distribution look like on on-device captures from
   `~/Library/Application Support/SixFour/sessions/` — is still pending
   (Tasks #3, #4 in the TaskList).

2. **Re-instantiate `option4Theorem` at `SigmaPairHead`.** The Pipeline
   composition theorem in `Spec.Pipeline` is currently parameterised over
   `Quad4ReconAchroma`. Should be straightforward to add a
   `SigmaPairHead`-instance and prove the conditional σ-equivariance for the
   updated pipeline.

3. **The L5 decoder.** The encoder L3 → L4 → L5 → L6 chain needs to emit a
   384-coefficient `SigmaPairTree` instead of a 768-coefficient
   `HaarPalette`. Cheap: drop the lowest Haar level.

4. **Codegen pin for the new dimensions.** `Spec.Codegen.Burn` should emit
   `SIGMA_PAIR_DOF = 384`, `SIGMA_PAIR_DEPTH = 7`, `SIGMA_PAIR_LEAVES = 256`
   into `studio/look-nn/src/generated/contract.rs`. One commit (Task #2).

5. **Stochastic core (GRAM-style, `spec/GRAM_MAPPING.md`).** Still design-
   only, still deferred. The VI target `y` open question is unresolved.

### Architectural diagram (post-session)

```
L1 Pool      :  CyclicStack → samples                                (Det)
L2 GMM       :  samples → tokens (μ, Σ, w)                           (Det)
L3 Encoder E :  10 → dM = 64                                         (Learn)
L4 Core R    :  dM → dM   (PonderNet over Mixture-of-Recursions)     (Learn)
L5 Decoder D :  dM → 384  (SigmaPairTree genome — was 768 PairTree)  (Learn)
L6 Reconstruct: SigmaPairTree → 256-leaf σ-pair palette              (Det,  NEW)
L7 Remap     :  per-frame K → K                                      (Det)
L8 GlobalIdx :  T·H·W + remap → T·H·W ∈ [0, K)                       (Det)
L9 Dither    :  index field + STBN3D → GIF index field               (Learn/Det)
```

Genome budget: **dM = 64** (encoder bottleneck) → **384** (decoder output) →
256 σ-pair-structured leaves. Both PairTree (768) and Quad4 (511) are
retained in the spec library as documented alternatives — they're not wired
into the pipeline, but their spec modules and tensor measurements are kept
as evidence of why SigmaPairHead won.

---

## Review summary (this session)

**Code added (Haskell):** 9 new modules in `spec/src/SixFour/Spec/`:
`Bottleneck16`, `SigmaDecomp`, `Quad4`, `Pipeline`, `LinAlg`, `Quad4Fit`,
`SigmaPairHead`, plus extensions to `Indices` (`GlobalSurjective` brand),
`Cyclic` (constant-trajectory AC-power fix), `Codegen.Burn` (Rust contract
emit). Total ~2.6 k LoC of spec, ~1.3 k LoC of property tests.

**Code added (Rust):** `studio/look-nn/` crate (272 LoC), `analysis-core`
extensions for Bures + GMM (~480 LoC). Golden-checked against Haskell spec.

**Tooling added:** Three executables (`spec-tui`, `spec-gif`, `spec-gen`)
with their own gen/viz/gen-test source dirs (~1.7 k LoC), plus a `gen-tests`
test-suite (9 tests green).

**Tests added:** 191 spec tests total (was 79 before commit `3cb1be5`).
Highlights: 16-law layer report at production 64³ × 3 seeds; Bures iteration
convergence; σ-eigenspace orthogonality / Parseval; PairTree round-trip;
Quad4 σ-equivariance; SigmaPairHead structural σ-pair guarantee; tensor
residual reports printed live with `§A.4` verdicts.

**Risks / things to watch.**
- Modified Gram-Schmidt is not the most numerically stable QR; if matrix
  conditioning degrades in a future variant, may need to upgrade to
  Householder QR or pull in a BLAS-backed LA library (license-gated).
- The `option4Theorem` proof in `Spec.Pipeline` is currently dead-end at
  Quad4ReconAchroma — needs the SigmaPairHead update before the
  type-class framework actually points at the new decoder.
- `spec/dist-newstyle/` is sometimes 300 MB; `.gitignore` covers it but
  watch out for `spec/analysis/dist-newstyle/` (covered by the
  `spec/**/dist-newstyle/` rule added in commit `3cb1be5`).
- The branch name `feat/significance-settings-instrument` is stale —
  significantly outscoped its original purpose.

**Verification performed.**
- `cabal test spec-tests` → 191 / 191 green.
- `cargo build -p analysis-core -p look-nn` in `studio/` → clean.
- `cabal run spec-codegen` → 8 files + 1 resource, no diffs against the
  shipped Swift / Python / Rust contracts.
- Manual review of every commit's diff against the plan's named files
  (`~/.claude/plans/flickering-dazzling-dewdrop.md`).

# SixFour Model Build Workflow (handoff plan, 2026-06-26)

Derived from the deep model review. This expands every TODO from that review into ordered,
self-contained tasks. Each task states its goal, what it depends on, the exact files it touches,
the concrete steps, the laws/goldens it must add, the gate command, and the acceptance bar
("Done when"). Nothing here is started; the working tree is clean on `master`.

Punctuation note: this doc avoids em-dashes on purpose (owner preference).

## Progress (updated 2026-06-26)

Done and committed on `master` (spec gate green at each step, app compile-checks arm64):
- **W0.1** `Spec.AboveFloorMargin` (`c78c2e1`) — margin is finite (1 Q16 LSB survives, half-LSB
  snaps to floor), floor non-absorbing above it, surviving detail is A_7-legal. Verdict: GO.
- **W1.1** `Spec.ModelForward` (`c78c2e1`) — nudge-conditioned forward frame; closes ModelIO's
  unused `miNudge`/`miGauge`. Budget gates, opaque head decides A_7 coords.
- **W1.2** `Codegen.ModelIO` → `SixFourModelIO.swift` (`3f9b121`) — wireable boundary, drift-gated.
- **W2.1** `ModelRender.swift` (`8a49c5c`) — render surface, `palette[index]` byte-exact.
- **Floor bridge** `ModelFloor.swift` (`cbd0579`) — adapts the existing byte-exact 64³ cube into
  `SixFourModelOutput` so the render previews the REAL floor. (Inserted before W2.2 per owner choice;
  the 256³ super-res floor / Swift `upscale256` port stays deferred to Phase 3.)

Spec totals: 1144 tests, 180 Spec modules, 29 generated files.

NEXT: **W2.2** (the paint tool) — the last Phase 2 task, then the GREENLIGHT GATE before Phase 3.

## Owner rules that constrain ordering (do not violate)

1. **No training until the model is wireable** (CLAUDE.md / NEXT-STEPS). App boundary first.
2. **Spec is the design authority.** Never hand-edit `SixFour/Generated/*`. Write a `Codegen.*`
   emitter, register it in `spec/app/Spec.hs`, regenerate, commit the generated file. The gate's
   hermetic step (`spec/scripts/gate.sh:30-33`) runs `cabal run spec-codegen` then
   `git diff --exit-code -- SixFour/Generated trainer/generated ...` and fails on drift.
3. **Byte-exactness is the product.** Float invention must re-enter the Zig Q16 floor
   (`reconstruct256`) before GIF bytes. Byte-exact is guaranteed only at the zero-nudge floor.
4. **Do not train on `MatrixTarget.matrixSqLoss`** (per-voxel, rank-1-blind). The loss is
   `MatrixTarget.cellLoss` (cell-aggregate, rank-3).
5. **Zero third-party deps in the shipped Tier-2 app.** On-device inference is a hand-written
   forward pass or first-party Core AI, never a Core ML black box.

## Dependency graph (read top to bottom; same-row tasks are parallel)

```
Phase 0  W0.1 above-floor reachability law        (cheap de-risk, gates training go/no-go)
            |
Phase 1  W1.1 modelForward contract  ->  W1.2 Codegen/ModelIO.hs emitter
            |                                   |
Phase 2  W2.1 Swift render  ----------------  W2.2 Swift paint tool      (both need W1.2)
            |
        === GREENLIGHT GATE: app is wireable, owner approves training ===
            |
Phase 3  W3.1 corpus fix --> W3.2 data loader --> W3.3 cellLoss+golden
                                  |                      |
                             W3.4 two-rung heads <-------+
                                  |
                             W3.5 per-factor VICReg
                                  |
                             W3.6 PonderNet halting
                                  |
                             W3.7 new trainer gate
            |
Phase 4  W4.1 smoke run --> W4.2 resume verify --> W4.3 empirical margin --> W4.4 long run
            |
Phase 5  W5.1 fixed-depth unroll --> W5.2 coreai-torch export + Q16 re-entry --> W5.3 device verify
```

---

## Phase 0 - De-risk before any compute

### W0.1 - `lawAboveFloorMarginReachable` (the go/no-go for training)
- **Goal:** prove, in-spec and free, that the learned up-rung *can* produce 256-cube detail that
  survives the Q16 commit and differs from the deterministic floor. If no legal nudge can move a
  single committed voxel off the floor, training cannot beat the floor and Phase 3+ is wasted.
- **Depends on:** nothing.
- **Files:** new `spec/src/SixFour/Spec/AboveFloorMargin.hs`; `spec.cabal` (exposed-modules);
  `spec/src/SixFour/Spec/Map.hs` (one index line under the NN category); `spec/test/Spec.hs`
  (register the law).
- **Steps:**
  1. Construct a witness: a `CellBudget` with one painted cell + a legal A₇ residual at the finest
     level (use `RootLatticeDetail.fromRootCoords` so it is a real lattice vector, not arbitrary).
  2. Run it through the commit path: `reconstruct256` (`SelfSimilarReconstruct.hs:140`) which is
     `octantLift` twice, then the Q16 commit.
  3. Assert: committed output at the painted subtree differs from `buildFloor` at >= 1 voxel
     (`lawAboveFloorMarginReachable`), AND the zero-nudge witness still equals the floor (reuse
     `ModelIO.lawNeutralNudgeIsAllFloor`). The pair is the real teeth: reachable when painted,
     identical when not.
  4. Add a refutation law `lawFloorIsNotAbsorbing`: the Q16 commit of (floor + minimal A₇ residual)
     is not always the floor (name the smallest residual that survives the round to nearest).
- **Gate:** `bash spec/scripts/gate.sh` green; new laws in the count.
- **Done when:** both laws green AND you have written the minimal surviving residual magnitude into
  the module doc (this number is the floor of what the trainer must learn to exceed). If the minimal
  surviving residual does not exist, STOP and redesign the residual basis before Phase 3.

---

## Phase 1 - Spec completion (the missing forward contract)

### W1.1 - `Spec.ModelForward` (wire the nudge into a typed forward contract)
- **Goal:** close the gap the review found. Today `ModelIO.buildFloor = upscale256 . miCapture`
  (ModelIO.hs:56) ignores `miNudge`/`miGauge`, and those fields are referenced nowhere else. The
  learned coefficients are not specifiable, but the STRUCTURE around them is. Spec it.
- **Depends on:** W0.1 (you need the reachability result to state the residual type honestly).
- **Files:** new `spec/src/SixFour/Spec/ModelForward.hs`; `spec.cabal`; `Map.hs`; `test/Spec.hs`.
- **Steps:**
  1. Define the decomposition `modelOutput = commit (floorResidual <+> ponderResidual)` where
     `commit = reconstruct256`, `floorResidual` is the deterministic floor, and `ponderResidual ::
     CellBudget -> Bool -> Residual` is an OPAQUE function (the learned part) typed so its codomain
     is the A₇ per-level basis (`RootLatticeDetail`). The learned model supplies coefficients only;
     the type forbids it from leaving the lattice.
  2. Laws to add:
     - `lawZeroNudgeForwardIsFloor`: `ponderResidual neutral g = mempty` so `modelOutput = buildFloor`
       (ties to `ModelIO.lawNeutralNudgeIsAllFloor`; this is the byte-exact anchor).
     - `lawResidualStaysInA7`: every `ponderResidual` output is `inA` at every level (delegates
       `NudgeRankTheorem.lawResidualIsA7AtEveryLevel`).
     - `lawForwardCommitIsQ16`: the only float-to-device path is the commit, which is `reconstruct256`
       returning `[Int]` (delegates `SelfSimilarReconstruct`), so the forward output is byte-exact at
       the floor and integer everywhere.
     - `lawNudgeMovesOutput`: a painted nudge changes the committed output (delegates W0.1).
  3. Re-export `modelOutput` from `ModelIO` (or have `ModelIO` import it) so there is ONE boundary
     the UI, the 256-builder, and the trainer all consume.
- **Gate:** `bash spec/scripts/gate.sh` green.
- **Done when:** `grep -rn "miNudge" spec/src` shows it consumed by `ponderResidual`, not only
  declared; the four laws are green.

### W1.2 - `Codegen/ModelIO.hs` emitter (NEXT-STEPS step 1)
- **Goal:** emit the `ModelInput`/`ModelOutput`/`renderFrame` contract to Swift so the app can
  consume it, drift-gated.
- **Depends on:** W1.1 (emit the forward decomposition, not just the floor).
- **Files:** new `spec/src/SixFour/Codegen/ModelIO.hs` (export `emitModelIOContract :: Text`);
  `spec.cabal` (add to the library `other-modules`/`exposed-modules` used by `spec-codegen`);
  `spec/app/Spec.hs` (import + one `writeUtf8 (swiftOutDir </> "ModelIOContract.swift")
  emitModelIOContract` line, mirroring lines 64-95); update the count string at Spec.hs:115
  ("wrote 28 files" -> 29).
- **Steps:**
  1. Model the emitter on an existing one (`Codegen/Swift.hs` `emitCellContract` is a good shape).
     Emit Swift structs for `ModelInput` (capture handle + 16x16x16 x 9 nudge + gauge Bool) and
     `ModelOutput` (per-frame `[palette]` + `[indexPlane]`), plus a `renderFrame(_:Int) ->
     (palette, indexPlane)` signature comment and the cell/subtree constants
     (4096-leaf-per-cell, from `CellNudge.lawCellGovernsSuperResSubtree`).
  2. Run `cd spec && cabal run spec-codegen`; commit the new `SixFour/Generated/ModelIOContract.swift`.
- **Gate:** `bash spec/scripts/gate.sh` (the hermetic-codegen step now diff-checks the new file).
- **Done when:** `cabal run spec-codegen` is idempotent (second run leaves git clean), gate green,
  `SixFour/Generated/ModelIOContract.swift` committed.

---

## Phase 2 - App wiring (Tier-2 Swift, zero deps)

### W2.1 - Swift render surface
- **Goal:** draw the model output. `renderFrame f` returns `(palette, indexPlane)`; draw
  `palette[index]` per frame. Zero paint = the byte-exact floor.
- **Depends on:** W1.2.
- **Files:** new `SixFour/Native/ModelRender.swift` (or under the existing render group); consumes
  `Generated/ModelIOContract.swift`; `project.yml` only if a new group is needed; then
  `xcodegen generate`.
- **Steps:** implement the per-frame `palette[index]` blit against the generated contract; at zero
  nudge, assert output equals the `Upscale256` floor (golden-checkable against `lawK0PaletteExact`).
- **Gate:** `xcodegen generate` then the arm64 build line from CLAUDE.md (BUILD SUCCEEDED is the bar;
  no camera in sim). `git checkout SixFour/Generated/BuildStamp.swift` before committing.
- **Done when:** app builds arm64, zero-nudge render is byte-identical to the floor.

### W2.2 - Swift paint tool (Tier-2 nudge surface)
- **Goal:** the 16x16x16 control grid over 16 frames, 9 paint channels per cell
  (`ChannelProduct` pairs), a phi6 gauge toggle (`miGauge`). One brush stroke = the octant twiceness
  (a 4096-leaf 256-cube subtree, `CellNudge.lawCellGovernsSuperResSubtree`).
- **Depends on:** W1.2 (and benefits from W2.1 for live preview).
- **Files:** new `SixFour/Native/PaintTool.swift` + a SwiftUI surface under the existing
  `GlassControls`/`SFTheme` layer; `project.yml`; `xcodegen generate`.
- **Steps:** map a brush stroke to `CellNudge.paintCellPair` semantics (CellNudge.hs:74); the brush
  granularity is the self-similar rung (8^levelsPerStep = 64 finest octants), not a pixel radius
  (`PonderBudget`); persist the budget; the gauge toggle flips which 9 pairs the paint names.
- **Gate:** arm64 build; round-trip a painted budget through save/load.
- **Done when:** painting changes the rendered frame (visually above floor), zero paint returns to
  the byte-exact floor, gate green.

> === GREENLIGHT GATE === App is wireable. Get explicit owner approval before Phase 3 (owner rule 1).

---

## Phase 3 - Trainer rebuild (the new full-matrix H-JEPA)

Current state: `trainer/mlx/train_loop.py` trains the OLD masked-band theta_B and hardcodes chroma
to 0 at line 174. Reuse the infra (batched forward ~4.3x, checkpoint/resume, streaming corpus,
float32-GPU/float64-CPU discipline); replace the model.

### W3.1 - Corpus fix + verification (do FIRST, or it floors again)
- **Goal:** the corpus must carry real (L,a,b) chroma AND real inter-frame motion.
- **Depends on:** none (can start in parallel with Phase 1-2, but lands before W3.3).
- **Files:** `trainer/synth_capture.py`, `trainer/synth_corpus_64.py`, `trainer/zig_native.py`
  (synth knobs if needed).
- **Steps:**
  1. Confirm `high-lab` chroma path reaches the loader (it generates `CHROMA_MAX_Q16` today but the
     old `palette_target` discards it).
  2. Add a corpus assertion harness implementing `MotionFloorCorpus.lawCorpusHasMotionFloor` and
     `lawCorpusHasOffFloorTexture`: reject any clip where `predict t+1 := t` is optimal (static =
     zero temporal gradient, `lawStaticCorpusStarvesGradient`).
- **Gate:** corpus harness prints motion floor > 0 and off-floor texture > 0 for the training mix
  (the existing 64-cube entropy check already proves colour>grey and high-detail>smooth in gate.sh).
- **Done when:** the mix passes both motion and texture floors; iso-luminant/static clips are
  rejected at generation.

### W3.2 - Data loader (scale + temporal pairs)
- **Goal:** map 64-cube captures to the two held-out rungs.
- **Depends on:** W3.1.
- **Files:** new `trainer/mlx/full_matrix_data.py` (reuse `temporal_data.py` for the t/t+1 axis);
  `trainer/jepa_data.py`.
- **Steps:** emit (a) ScaleRung pairs (64-cube -> 256-cube target, *Invented*) and (b) TimeRung
  pairs ((t, t+1), *Held*), per `ScaleSpineRungs` (`lawTwoRungsAreTheTwoHeldAxes`,
  `lawScaleInventedTimeHeld`). The held-out target across SCALE and TIME REPLACES masking
  (`HeldOutTarget.lawHeldOutReplacesMasking`); there is NO per-pair I-JEPA masking.
- **Gate:** reproduce `trainer/generated/temporal_data_golden.json` byte-exact (existing golden);
  add a scale-pair golden if one is needed (emit via a new `Codegen` if the trainer must match spec).
- **Done when:** loader yields both rungs, temporal golden reproduced byte-exact.

### W3.3 - `cellLoss` implementation + golden
- **Goal:** the honest loss. Cell-aggregate rank-3 squared error, NOT per-voxel.
- **Depends on:** W3.2.
- **Files:** new `trainer/mlx/cell_loss.py`; a new emitter `spec/src/SixFour/Codegen/CellLoss.hs`
  + `app/Spec.hs` line + `trainer/generated/cell_loss_golden.json`.
- **Steps:**
  1. Port `MatrixTarget.cellLoss` (MatrixTarget.hs:85) = `aggSqLoss (cellAggregate pred)
     (cellAggregate tgt)` where `cellAggregate` sums per-voxel color (x) space outer products into a
     3x3 (NudgeRankTheorem.hs:123).
  2. Emit a golden from the spec's witness (`lawHeldOutLossIsCellAggregateNotPerVoxel`: aggSqLoss = 4
     where per-voxel = 0) and assert the MLX loss reproduces it.
- **Gate:** `bash spec/scripts/gate.sh` (golden diff) + the new trainer gate (W3.7).
- **Done when:** MLX `cell_loss` matches the spec witness (4 vs 0) and the golden is committed.

### W3.4 - Two-rung heads on the 18.9M ViT
- **Goal:** route the existing ViT latent (`large_head.py`) to a super-res decoder (Invented) AND a
  temporal predictor (Held). Same weights, two output projections.
- **Depends on:** W3.3.
- **Files:** `trainer/mlx/large_head.py`, `trainer/mlx/superres.py`, `trainer/mlx/per_scale.py`,
  `trainer/mlx/train_loop.py` (compose terms).
- **Steps:** add two head projections off the shared latent; outputs are GIF89a directly (per-frame
  palette VALUE + index CONTENT, per `ModelIO`), no separate trainer tensor. Loss = `cellLoss` on
  both rungs. Keep the batched path (a per-octant Python loop starves the GPU,
  `capabilities.py`); verify batched == looped (`max|Δ| < 1e-3`) before training, as the old loop did.
- **Gate:** batched/looped agreement self-check; trainer gate.
- **Done when:** both heads produce GIF89a output, batched==looped, loss is `cellLoss`.

### W3.5 - Per-factor VICReg (replace per-neuron)
- **Goal:** the collapse guard the spec wants. Today VICReg is per-neuron latent variance; the spec
  wants a per-FACTOR std hinge on the colour `q` and space `k` vectors (either collapsing trips it).
- **Depends on:** W3.4.
- **Files:** `trainer/mlx/vicreg.py`, `trainer/mlx/train_loop.py` (it is already in the loss at
  `LAMBDA_VIC=5e-2`; change WHAT it reads).
- **Steps:** port `VarianceFloorGuard.varianceHinge = max 0 (gamma - sqrt(var+eps))` applied
  separately to the `q` and `k` factor vectors; combine (`combinedGuard`,
  `lawEitherCollapseTripsGuard`). Add `MotionFloorCorpus` as a data-side guard (W3.1).
- **Gate:** unit test reproducing `lawEitherCollapseTripsGuard` (flat trips >0.5, varied passes <1e-9).
- **Done when:** flat `q` OR flat `k` trips the guard in MLX, matching the spec law.

### W3.6 - PonderNet halting
- **Goal:** proper geometric halting; the `CellNudge` budget lowers halt probability = more
  refinement (`lawLowerHaltRefinesMore`). User paint and adaptive compute become one number.
- **Depends on:** W3.5. This is the largest single task.
- **Files:** new `trainer/mlx/ponder.py`; `trainer/mlx/train_loop.py`; possibly a
  `Codegen/PonderHalt.hs` golden so the device unroll (Phase 5) matches.
- **Steps:** port `PonderHaltDistribution.haltDist` (sums to 1 by construction, PonderHalt.hs:33)
  and `geometricPrior`; expected loss = sum over steps of p_n * loss_n + KL-to-prior; read at the
  step depth the budget selects. Keep it differentiable in float32.
- **Gate:** test `sum(haltDist) == 1` within 1e-9 (the spec law) in MLX; KL>=0.
- **Done when:** halting distribution is proper, budget monotonically increases expected steps.

### W3.7 - New trainer gate module
- **Goal:** the old `gate_trainer.py` gates the old heads. Add a new-model gate.
- **Depends on:** W3.3-W3.6.
- **Files:** new `trainer/mlx/gate_full_matrix.py` (or extend `gate_trainer.py`).
- **Steps:** assert cellLoss golden, temporal golden, per-factor VICReg trip, halt-distribution sum,
  batched==looped, and a 4-prop smoke (loss decreases on a tiny batch).
- **Gate:** `python3 trainer/mlx/gate_full_matrix.py` all green.
- **Done when:** all new-model invariants gated in one command.

---

## Phase 4 - Train

### W4.1 - Smoke run
- **Goal:** prove the loop learns before spending days.
- **Steps:** 100 steps, 1 small batch, streaming corpus on; loss must decrease and stay above the
  zero-prediction floor (the old run's failure was sitting BELOW it). Checkpoint written.
- **Done when:** loss decreases monotonically over the smoke window, checkpoint saved.

### W4.2 - Resume verify
- **Goal:** multi-day safety. Reuse the proven `train_persistent` path
  (`--long --save-every --resample-every --resume --out`).
- **Done when:** stop/resume continues the loss trajectory (the old infra showed 0.48 -> 0.10
  across a restart; reproduce the continuity property).

### W4.3 - Empirical above-floor margin (the W0.1 follow-through)
- **Goal:** W0.1 proved the floor is reachable in principle. Now measure whether the TRAINED model
  produces detail that survives the Q16 commit above the floor.
- **Files:** implement `lawAboveFloorMarginMeasured` as a spec+trainer harness (NEXT-STEPS section 3).
- **Done when:** measured 256-cube detail exceeds the deterministic `Upscale256` floor by a reported,
  non-trivial margin. If the margin is within Q16 rounding, STOP: the up-rung learns nothing; revisit
  the residual basis or accept the floor as the product.

### W4.4 - Long run
- **Goal:** the days-of-training run.
- **Steps:** scale steps, `--resample-every` to avoid memorization, monitor VICReg guard (must stay
  off), motion floor (corpus must keep moving), and held-out cellLoss on a frozen eval set.
- **Done when:** held-out cellLoss improves and the collapse guard never trips on the eval latents.

---

## Phase 5 - Core AI port (iPhone 17 Pro / iOS 27, future)

Platform facts (verified 2026-06): iOS 27 replaces Core ML with Core AI (keeps `.mlmodel`
support); Core AI converts PyTorch via `coreai-torch` and supports standard transformers with
prepackaged SDPA kernels; iPhone 17 Pro (12GB) is the flagship target. The 18.9M ViT is tiny.

### W5.1 - Fixed-depth ponder unroll
- **Goal:** PonderNet's data-dependent halting is dynamic control flow, the classic conversion
  friction point. Unroll to a fixed max depth and mask, rather than convert a `while halt<thresh` loop.
- **Done when:** the head runs at a fixed max-ponder-depth with halt masking, numerically matching
  the dynamic loop within tolerance.

### W5.2 - `coreai-torch` export + Q16 re-entry
- **Goal:** honor owner rules 3 and 5. Export the head via `coreai-torch` to a first-party Core AI
  asset (NOT a Core ML black box). Core AI float is not cross-device bit-exact, so its output MUST
  re-enter the Zig Q16 floor (`reconstruct256`) before GIF bytes; byte-exact holds only at the
  zero-nudge floor. Architect as "Core AI proposes, Q16 disposes". Decompose any custom op into
  supported primitives.
- **Done when:** exported asset loads behind `#if canImport(CoreAI)`; committed float output, after
  Q16 re-entry, is deterministic and byte-identical to the floor at zero nudge.

### W5.3 - Device verification
- **Goal:** Core AI is absent from the simulator SDK and is developer-beta; verify on real hardware.
- **Done when:** on a physical iPhone 17 Pro, painted output renders above floor and zero-nudge
  output is byte-identical to the Mac spec golden.

---

## Quick reference: the laws each phase leans on

| Concern | Law | File |
|---|---|---|
| Zero nudge = byte-exact floor | `lawNeutralNudgeIsAllFloor`, `lawK0PaletteExact` | ModelIO.hs, Upscale256.hs |
| Loss is cell-aggregate not per-voxel | `lawHeldOutLossIsCellAggregateNotPerVoxel` | NudgeRankTheorem.hs |
| Cell reaches rank 3 | `lawCellAggregateReachesRank3` | NudgeRankTheorem.hs |
| Residual stays in A7 | `lawResidualIsA7AtEveryLevel` | NudgeRankTheorem.hs + RootLatticeDetail.hs |
| Held-out replaces masking | `lawHeldOutReplacesMasking` | HeldOutTarget.hs |
| Two rungs = scale + time | `lawTwoRungsAreTheTwoHeldAxes`, `lawScaleInventedTimeHeld` | ScaleSpineRungs.hs |
| Collapse guard trips | `lawEitherCollapseTripsGuard` | VarianceFloorGuard.hs |
| Corpus must move | `lawStaticCorpusStarvesGradient` | MotionFloorCorpus.hs |
| Halting is a proper distribution | `lawHaltIsProperDistribution`, `lawLowerHaltRefinesMore` | PonderHaltDistribution.hs |
| Brush = octant twiceness | `lawCellGovernsSuperResSubtree` | CellNudge.hs |

## Commands

```bash
# spec gate (laws + hermetic codegen + lints + cross-lang goldens)
bash spec/scripts/gate.sh
# regenerate Swift/Python contracts after any Codegen change
cd spec && cabal run spec-codegen && cd ..
# app build (arm64, headless bar = BUILD SUCCEEDED)
xcodegen generate && xcodebuild -scheme SixFour \
  -destination 'generic/platform=iOS Simulator' \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES EXCLUDED_ARCHS=x86_64 build-for-testing
git checkout SixFour/Generated/BuildStamp.swift   # drop the build stamp before commit
# new-model trainer gate (after Phase 3)
python3 trainer/mlx/gate_full_matrix.py
```

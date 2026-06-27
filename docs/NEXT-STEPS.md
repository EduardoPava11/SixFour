# SixFour — Next Steps (handoff, 2026-06-26)

Branch: everything below is on `master` (the L-anchor pivot merged at `6575d2e`).
Gate state at handoff: `bash spec/scripts/gate.sh` green, **1137 tests, 178 Spec modules**.

## Honest status: what is real vs not (read this first)

- **The Held-Out Full-Matrix H-JEPA is SPEC-COMPLETE and PROVEN.** "Proven" means the
  Haskell laws hold and the gate is green. It does **NOT** mean trained, run, or wired to the app.
- **The new model has NEVER been trained.** The only training this session was the OLD
  L-anchored masked-band run, which **floored**: held-out eval showed `L_band ~0.00054` vs the
  zero-prediction floor `~0.00035` (i.e. worse than predicting zero). See `AnchorDiagnostic`.
- **The trainer (`trainer/mlx/`) still implements the OLD architecture** (masked-band `θ_B`,
  predict 1 of 7 octant detail bands). It does NOT implement the new full-matrix H-JEPA. The new
  model is spec-only. See `trainer/TRAINER-NOTES.md`.
- **The 256³ build exists and ships** (`Spec.Upscale256.upscale256`), but it is the
  DETERMINISTIC floor super-res, not the learned model.
- **`Spec.ModelIO` is a spec CONTRACT** (types + laws). No codegen emits it to Swift yet, so
  the app cannot consume it. The Swift paint tool / render surface do not exist.

## The model spec (verifiable, on master)

| Module | File | Commit | Key law(s) |
|---|---|---|---|
| DualCube | `spec/src/SixFour/Spec/DualCube.hs` | `b376690` | `lawNoPrivilegedCarrier`, `lawCubesExchangedByPhi6` |
| ChannelProduct | `…/ChannelProduct.hs` | `818fa6b` | `lawComparisonIsSeparable` (rank-1), `lawAllChannelsSeeWhatLAnchorMisses` |
| HeldOutTarget | `…/HeldOutTarget.hs` | `f46a75d` | `lawHeldOutReplacesMasking` |
| MatrixTarget | `…/MatrixTarget.hs` | `1ee30de`,`6a233ab` | `lawMatrixLossSeesOffDiagonal`, `cellLoss` |
| NudgeRankTheorem | `…/NudgeRankTheorem.hs` | `99fb5d4` | 13 laws: rank (`lawCellAggregateReachesRank3`), collapse (`lawValueSplitIsPhi6Gauge`), residual (`lawDownResidualConditionsUpInvention`) |
| CellNudge | `…/CellNudge.hs` | `1f3bca6` | `lawNineHonestAtCell`, `lawLossIsCellAggregate`, `lawCellGovernsSuperResSubtree` |
| PonderHaltDistribution | `…/PonderHaltDistribution.hs` | `862e68a` | `lawHaltIsProperDistribution`, `lawLowerHaltRefinesMore` |
| VarianceFloorGuard / MotionFloorCorpus / ScaleSpineRungs | `…/{VarianceFloorGuard,MotionFloorCorpus,ScaleSpineRungs}.hs` | `bad8b49` | `lawEitherCollapseTripsGuard`, `lawStaticCorpusStarvesGradient`, `lawTwoRungsAreTheTwoHeldAxes` |
| ModelIO | `…/ModelIO.hs` | `b4dc216` | `lawOutputIsPerFrameValueContent`, `lawNudgeGovernsSuperRes` |

## Next steps (ordered, specific)

### 1. App-wiring (do this FIRST — owner rule: no training until wireable)
- Write a codegen emitter `spec/src/SixFour/Codegen/ModelIO.hs` that emits the `ModelInput` /
  `ModelOutput` / `renderFrame` contract to `SixFour/Generated/ModelIOContract.swift`. Register
  it in the codegen driver so `cabal run spec-codegen` emits it and the gate's hermetic-codegen
  step enforces no drift (`spec/scripts/gate.sh`).
- Swift paint tool (Tier-2): a **16×16×16 control grid over 16 frames** (`CellNudge.CellBudget`),
  **9 paint channels per cell** (the `ChannelProduct` pairs), a **φ6 gauge toggle** (`miGauge`).
  One brush stroke = the octant twiceness (a 4096-leaf 256³ subtree, `lawCellGovernsSuperResSubtree`).
- Swift render: `renderFrame f` returns `(palette, indexPlane)`; draw `palette[index]` per frame.
  Zero paint = the byte-exact floor (`Upscale256`, `lawK0PaletteExact`).

### 2. Trainer (only after wiring + explicit greenlight)
See `trainer/TRAINER-NOTES.md`. The new trainer does not exist yet.

### 3. Measure the super-res margin (currently a TODO, NOT done)
- The learned 256³ detail above the deterministic `Upscale256` floor is UNVERIFIED and may be
  thin; the Q16 commit can snap invented detail back to the floor. A `lawAboveFloorMarginMeasured`
  must be implemented and run before claiming the up-rung learns anything.

## Open risks (do not forget)
- **MatrixTarget.matrixSqLoss is per-voxel** (kept only for the contrast law). The REAL loss is
  `MatrixTarget.cellLoss` (cell-aggregate). `NudgeRankTheorem.lawHeldOutLossIsCellAggregateNotPerVoxel`
  proves per-voxel is blind to a chroma↔space mispairing. Do not train on `matrixSqLoss`.
- **The nudge is 6-write / 9-read**: the byte-exact basis is the 6-D P6 generator (per voxel,
  rank-1); the 9-channel paint is honest only at the cell (rank-3). `CellNudge` + `cellLoss` agree.
- **Per-frame palette** is a hard product rule (`Feature.globalPaletteV2 = false`); the 256³ keeps
  it (`Spec.SuperResPalette`).

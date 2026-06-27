# Trainer Notes — the full-matrix H-JEPA (handoff, 2026-06-26)

## The trainer does NOT yet implement the new model

- `trainer/mlx/train_loop.py` is the **OLD** masked-band `θ_B` path (predict 1 of 7 octant
  detail bands from coarse + 6 siblings). KEEP it for reference; it is NOT the new architecture.
- The new model (Held-Out Full-Matrix H-JEPA, spec-complete on `master`) has **never been trained**.
- Do not "resume" the old run and call it the new model. The old run floored on purpose-broken data.

## Why the last run floored (verified, not a guess)

- `trainer/mlx/train_loop.py:174` `palette_target` emits `[to_q16(L), 0.0, 0.0]` — **chroma is
  hardcoded to 0**. The model was fed luma only.
- `Spec.AnchorDiagnostic` PROVED an L-only target is blind to iso-luminant chroma: for a constant-L,
  varying-chroma octant, **L-energy = 0 (lattice floor), chroma-energy = 2600 (ℤ[i] norm)**.
- So the band head sat at the floor because it anchored on the empty channel. This is `Fact B`
  (the trainer stopgap), not `Fact A` (the proven L-is-DC theorem, which stays).

## What the new trainer must do (specific)

- **Input**: `Spec.ModelIO.ModelInput` = 64³ capture (`Upscale256.UpscaleInput`) + the 16³×9
  `CellNudge.CellBudget` paint + the φ6 gauge.
- **Output / target**: `Spec.ModelIO.ModelOutput` = `Upscale256.UpscaleOutput` (per-frame palette +
  index planes). The model emits GIF89a directly; no separate trainer tensor.
- **Loss**: `Spec.MatrixTarget.cellLoss` (cell-AGGREGATE squared error, rank-3). NOT per-voxel —
  `NudgeRankTheorem.lawHeldOutLossIsCellAggregateNotPerVoxel` proves a per-voxel loss is blind to a
  chroma↔space mispairing (`aggSqLoss = 4` on a witness the per-voxel loss scores 0).
- **Two rungs** (`Spec.ScaleSpineRungs`): `ScaleRung` (super-res 64³→256³, **Invented**) +
  `TimeRung` (frame t→t+1, **Held**). The held-out target across SCALE and TIME replaces masking
  (`Spec.HeldOutTarget`); there is NO per-pair I-JEPA masking.
- **Collapse guards in the loss**: `Spec.VarianceFloorGuard` (per-factor std hinge on the colour `q`
  and space `k` vectors — either collapsing trips it) + `Spec.MotionFloorCorpus` (the corpus must
  move).
- **PonderNet**: `Spec.PonderHaltDistribution` (proper geometric halting, Σp=1, KL-to-prior). The
  `CellNudge` budget lowers the halt probability = more refinement (`lawLowerHaltRefinesMore`), so
  the user's paint and the adaptive compute are one number.

## Data — fix this BEFORE training, or it floors again

- The synthetic corpus generator `trainer/synth_capture.py` must produce **(a) real (L,a,b) chroma**
  and **(b) real inter-frame MOTION**. The old corpus was often iso-luminant and/or static.
- Static loops are a trap: `Spec.MotionFloorCorpus.lawStaticCorpusStarvesGradient` proves the
  persistence baseline (`predict t+1 := t`) is optimal on a static clip, so the temporal rung gets
  zero gradient. Verify the corpus with `lawCorpusHasMotionFloor` + `lawCorpusHasOffFloorTexture`.

## Throughput + harness (already built — REUSE, do not rebuild)

- **Batched forward, ~4.3x measured** (`trainer/mlx/capabilities.py`; `batched_head` +
  `_composite_terms_batched` in `train_loop.py`): looped ~145 octants/s vs batched ~610 octants/s at
  B=256. The new trainer must batch too (a Python per-octant loop will starve the GPU again).
- **Checkpoint / resume / streaming corpus** (`train_loop.py` `train_persistent`, flags
  `--long --save-every --resample-every --resume --out`). Verified: loss continued `0.48 -> 0.10`
  across a stop/resume. SGD is stateless so head weights + step = a faithful resume.
- Run the gate: `python3 trainer/mlx/gate_trainer.py` (the old-model gate; a new gate module is
  needed for the new heads).

## Honest open risks for the trainer

- **Super-res margin unverified**: the learned 256³ detail above the deterministic `Upscale256`
  floor may be thin, and the Q16 commit can crush invented float detail back toward the floor.
  Byte-exactness holds ONLY at the zero-nudge floor. Measure it (`lawAboveFloorMarginMeasured`,
  not yet implemented) before claiming the up-rung learns.
- **6-vs-9 nudge**: train on the 6-D P6 generator (the byte-exact basis, rank-1 per voxel), expose
  9 channels at the cell (`CellNudge`, rank-3 aggregate). `cellLoss` is the loss that matches the
  9-cell surface; a per-voxel loss does not.

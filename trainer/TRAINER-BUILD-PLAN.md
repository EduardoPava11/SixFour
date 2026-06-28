# Trainer Build Plan — align the MLX trainer to `Spec.ModelIO`

Scope: build the new full-matrix H-JEPA trainer so its **input/output types are literally `Spec.ModelIO`'s**
(`ModelInput → ModelOutput`), ending at **"ready to train" + a measurement harness**. **No training runs are
part of this plan.** Source of truth: `SIXFOUR-MODEL.md` + `spec/src/SixFour/Spec/Model.hs`. Produced by the
`trainer-alignment-map` workflow (5 mappers + synthesis).

## The crux (what is and isn't aligned)

The objective is already right; the **boundary** is not. No trainer code consumes `ModelInput` or emits
`ModelOutput` — the atomic example is still a per-octant proxy tuple (`train_loop.py:223,244-254`), heads emit
an 8-colour octant proxy not a per-frame 256-colour palette + 256² index plane, and "above-floor" is measured
against a **zero baseline**, not the deterministic `buildFloor`.

### Already aligned — DO NOT rebuild
- `Codegen.ModelIO` → `SixFourModelIO.swift` (gate-enforced hermetic codegen). NEXT-STEPS step-1 codegen is **done**.
- Swift `ModelRender.swift` (W2.1) renders `palette[index]` byte-exactly; `ModelFloor.swift` adapts the 64³ cube.
- `trainer/mlx/cell_loss.py` is a byte-exact twin of `MatrixTarget.cellLoss`, already the **primary** trained
  objective (`W_CELL=1.0`). Per-voxel `matrixSqLoss` is correctly **not** trained.
- Value head at `--w-value 1.0` (the proven identifiable point); VICReg collapse guard; q16 byte-commit split.
- Harness: batched forward, checkpoint/resume/streaming corpus, `cli.py` (`s4train`), `gate_trainer.py`.
- Reusable axis kernels: `superres.py` (scale), `temporal_rung.py`/`temporal_data.py` (time),
  `frame_palette.py` (the closest thing to emitting a real per-frame palette — **promote, don't rewrite**).

## Acceptance criteria (what discharges the contract markers)
1. **PRIMARY** (`contractDescentOnRealDataUnproven`): a measured held-out cell-aggregate margin **> 0 against the
   deterministic `buildFloor`** (not the zero baseline), reversing the prior floored run.
2. **HEADLINE** (`contractEmpiricalSoundnessUnproven`): a new `lawAboveFloorMarginMeasured` + harness reports the
   **fraction of emitted detail coefficients with `|x| ≥ marginCoeffLatent` (1/65536)** that survive the Q16 commit
   — a measured, gated number, not a `()` marker.
3. **GATE**: `spec/scripts/gate.sh` invokes `gate_trainer.py` (it currently does **not**); the new module +
   full-matrix head self-tests + the Python `upscale256` golden run there.
4. **BYTE-EXACT FLOOR**: Python `upscale256.py` reproduces a Haskell `UpscaleOutput` golden exactly; at
   `neutralNudge`, emitted `ModelOutput == buildFloor` byte-for-byte.
5. **GUARDS HELD**: no pass while `COLLAPSE` (vic > threshold) or `DIVERGED` (non-finite).
6. **WIREABILITY** (owner rule): the Swift paint tool produces a `CellBudget` the boundary accepts.

## Phases (ordered, file-level)

### Phase 0 — Finish app-wiring (owner rule: "no training until wireable")
Only the **paint tool** remains (codegen + render + floor adapter already exist).
- **`SixFour/Editing/ModelPaint.swift`** (new) — a 16³ control grid × 9 paint channels + φ6 gauge toggle; one
  stroke = the 4096-leaf subtree; read contract constants from `SixFourModelIO.swift`. Zero paint = floor.
  → `Spec.ModelIO.miNudge`/`CellBudget`, `lawNudgeGovernsSuperRes`, `miGauge`.
- Compile-check only (camera-app rule: never run the sim).

### Phase 1 — The Python deterministic floor (biggest missing primitive; blocks 2–5)
- **`trainer/mlx/upscale256.py`** (new) — byte-exact `UpscaleInput → UpscaleOutput`; `build_floor(mi) =
  upscale256(mi.miCapture)`; every float→byte through `q16.py`. → `buildFloor`/`lawK0PaletteExact`.
- **`trainer/generated/upscale256_golden.json`** + `test_upscale256.py` + wire into `gate.sh`. → `UpscaleOutput` shape.

### Phase 2 — `ModelInput`/`ModelOutput` records + data engine on the boundary
- **`trainer/mlx/model_io.py`** (new) — `ModelInput`/`ModelOutput` dataclasses + an assembler lifting a
  `SyntheticCapture` into one holistic `UpscaleInput` (not shattered octants). → `ModelInput`, `UpscaleInput`.
- **`trainer/mlx/cell_budget.py`** (new) — 16³×9 paint with `paintCellPair` locality, `neutralNudge`, φ6 bool,
  4096-leaf subtree localization. → `CellBudget`, `cellSubtreeLeaves=4096`, `lawNeutralNudgeIsAllFloor`.
- **`trainer/mlx/heldout_corpus.py`** (new) — replace the retired per-band mask with held-WHOLE pairs across
  **scale** (coarse→7 detail via real `liftOct`) and **time** (frame t→t+1). → `HeldOutTarget.lawHeldOutReplacesMasking`.

### Phase 3 — Full-matrix heads + trunk rewire (octant-proxy → GIF89a-scale)
- **`value_head.py`** — promote `frame_palette.py`'s per-frame ≤256-colour quantizer onto the `large_head.py`
  trunk (keep `w_value>0`). → `UpscaleOutput.outPalettes` (VALUE).
- **`content_head.py`** — per-frame 256² index plane via straight-through commit. → `outCube` (CONTENT), `renderFrame`.
- **`scale_rung.py`** / **`time_rung.py`** — lift the two axis stubs onto the boundary, same holistic target.
- **`ponder.py`** — PonderNet geometric halting (`Σp=1`, KL-to-prior, paint lowers halt). **Net-new; keep behind a flag.**
- Rewire `train_loop.run` to consume `ModelInput`/emit `ModelOutput`; keep trunk, encoder_frozen, harness.

### Phase 4 — Loss + floor alignment (surgical; cell_loss already primary)
- Demote `L_band` out of the default gradient: `--w-band` default `0.0` (verdict-only diagnostic).
- Swap the zero floor for `buildFloor`: `_floor_baseline['cell']` = cell-aggregate of `upscale256(miCapture)`
  (`train_loop.py:595-616`); cross-check float MLX `cell_term` vs byte-exact `cell_loss`.

### Phase 5 — Measurement harness + gate (the acceptance number; plan ENDS here)
- Add `lawAboveFloorMarginMeasured` to `Spec.AboveFloorMargin` + the `Model.hs` ledger, kept **`ContractOnly`**
  (so `lawNoEmpiricalOverclaim` still holds — a green spec gate never reads as "the model works").
- **`trainer/mlx/above_floor_margin.py`** (new) — apply `survivesCommit` to emitted coefficients; report the
  surviving fraction + the held-out cell margin vs `buildFloor`; extend `dashboard_verdict` (margin>0 AND
  fraction reported AND no collapse/diverge).
- Wire `gate_trainer.py` into `gate.sh`; add head/margin self-tests.
- Update the stale "the full-matrix trainer does not yet exist" narrative once it does.

## Risks
- **MLX float64 is CPU-only** — keep `upscale256`/q16 commit on Python `round`; MLX gets the gradient-only twin.
- **Mean-dominated margin**: the cell margin can read +99% while the within-octant *detail* margin is negative
  (learns the mean, not detail). The `survivesCommit` measurement must be a **required**, not opt-in, gate term.
- **Q16 can snap invented detail back to the floor** (margin in (½ LSB, 1 LSB]); the surviving fraction may read
  ~0 even after a clean descent. This plan makes that number *measurable*; it does not guarantee it's positive.
- **PonderNet is entirely net-new** — largest new-code risk; keep it flag-gated.
- **`w_policy` (CONTENT head) is outside the cited identifiability laws** — keep it, don't claim it's defended.
- **Swift 256³ floor not ported** — `ModelFloor.swift` previews the 64³ rung; the Python harness carries the
  256³ byte-exact check until a Swift `upscale256` exists (see open decisions).

## Open decisions for the owner
1. **Swift 256³ floor**: port `upscale256` to Swift now (app asserts `renderFrame==buildFloor` at 256³) vs keep
   the deferred tiled decode + rely on the Python harness.
2. **φ6 gauge**: train both gauge values or fix `miGauge=False` initially to cut variance?
3. **`lawAboveFloorMarginMeasured`**: pure `ContractOnly` (number lives in the trainer gate) vs also a Haskell teeth fixture.
4. **Painted-target manufacture rule**: how a non-zero `CellBudget` maps to a ground-truth 256³ — must stay
   data-manufactured (no EMA/self-rollout) to preserve the anti-cheat conjunct.
5. **Corpus realism gate**: how much real `(L,a,b)` chroma + inter-frame motion the synthetic corpus must carry
   (`lawCorpusHasMotionFloor`/`lawCorpusHasOffFloorTexture`) to avoid re-flooring on iso-luminant/static data.

---

## Measured results (the training educated us)

`contractAboveFloorMarginMeasured` is now an actual number, not a `()` marker. Three experiments, all
honest, all gated:

| Experiment | Predictor | Held verdict | Why |
|---|---|---|---|
| `full_matrix_train_loop` (linear) | coarse + intra-octant position | **FLOORED** | only ~13% of detail is determined by the features even when memorising |
| `full_matrix_train_loop` (mlp) | + block position, nonlinear | **FLOORED** | MLP no better than linear → no nonlinear signal in these features |
| `context_super_res` | 5×5 surrounding **coarse field** | **FLOORED** | 1% generalisation despite 36–46% overfit on a small set |

**The bottleneck is the DATA, not the architecture.** The decisive evidence: a high-capacity MLP
*overfits* detail from a 5×5 context window (~36–46% train-loss drop on a small set) but only
*generalises* ~1% to a held capture. So the model **can** fit detail from context — the context→detail
mapping in the *synthetic* corpus is simply **not a transferable prior**. A bigger model (the 64-token
ViT) would overfit harder and still floor on held data.

**Implication for the next phase:** the path to flipping `FLOORED → LEARNING` is **better data**, not a
bigger predictor — real capture frames (natural images, where high-frequency detail *is* inferable from
low-frequency context, which is what makes super-resolution work) or a synthetic corpus deliberately
generated with a coarse→detail structure. Building the ViT trunk before fixing the data would just
produce a more expensive FLOORED.

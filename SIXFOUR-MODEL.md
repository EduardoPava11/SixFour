# SIXFOUR-MODEL.md — the single source for the model

This is the one place to start reading "the model": the **Held-Out Full-Matrix H-JEPA**. It is the
narrative companion to the Haskell module `SixFour.Spec.Model` (`spec/src/SixFour/Spec/Model.hs`), which
is the machine-checked single source. If this doc and the spec ever disagree, the spec wins — and
`Spec.Model`'s `lawNoEmpiricalOverclaim` is what keeps this doc honest.

The architecture here is **frozen** (per `docs/NEXT-STEPS.md`); this document consolidates and labels, it
does not redesign.

---

## 1. What a green gate means (read this first)

`bash spec/scripts/gate.sh` green proves the **design and the plumbing**: the Haskell laws hold and every
cross-language contract (Swift / trainer / Zig / Python) is byte-exact. It does **not** prove the **learned
model works**. The model has never been trained successfully — the only run to date floored (held-out
`L_band ≈ 5.4e-4` vs the zero-prediction floor `≈ 3.5e-4`), and the new full-matrix trainer does not yet
exist.

So read every model law **through the taxonomy** in §4. A passing `LoadBearing` law is a real theorem; a
passing `ContractOnly` marker carries no truth value at all — it is a documented obligation.

---

## 2. The architecture (frozen)

```
                 ┌─────────────────────────── ModelInput ───────────────────────────┐
  64³ capture ──▶│ miCapture : Upscale256.UpscaleInput                               │
  user paint  ──▶│ miNudge   : CellNudge.CellBudget  (16³ control grid × 9 channels) │──▶ MODEL
  φ6 toggle   ──▶│ miGauge   : Bool                  (colour-by-space vs the dual)    │
                 └──────────────────────────────────────────────────────────────────┘
                                                │
                                                ▼
                 ┌────────────────────────── ModelOutput ───────────────────────────┐
                 │ = Upscale256.UpscaleOutput                                        │
                 │ per-frame palettes (VALUE) + index planes (CONTENT) = GIF89a      │──▶ renderFrame f
                 └──────────────────────────────────────────────────────────────────┘
```

- **INPUT** = the 64³ capture + the user's 16³×9 paint + the φ6 gauge.
- **OUTPUT** = per-frame palettes + index planes = GIF89a directly (no separate decode type).
- **FLOOR** = zero paint ⇒ `buildFloor` = the deterministic `Upscale256` super-res, byte-exact
  (`Upscale256.lawK0PaletteExact`).
- **LEARNED** = the PonderNet invention rides **above** the floor where the user paints; one painted 16³
  cell governs its `(256/16)³ = 4096`-leaf 256³ subtree.
- **TRAINER** targets a `ModelOutput`, so one boundary serves the UI render, the 256³ build, and training.

---

## 3. The live modules (index)

| Module | Role |
|---|---|
| `Spec.Model` | **single source**: assembles the boundary, re-exports load-bearing laws, pins the contract markers, carries the taxonomy ledger |
| `Spec.ModelIO` | the wireable I/O contract (`ModelInput`, `ModelOutput`, `buildFloor`, `renderFrame`) |
| `Spec.CellNudge` | the 16³×9 paint surface (`CellBudget`, `paintCellPair`) + the cell-aggregate honesty laws |
| `Spec.Upscale256` | the deterministic byte-exact super-res floor the learned model rides above |
| `Spec.LearnabilityTheorem` | the **identifiability** capstone (`lawJointObjectiveIdentifiesFullPalette`) + the net-new checkerboard-parity complement witness |
| `Spec.ParadigmSoundness` | the **structural** master theorem (`lawParadigmIsStructurallySound`) |
| `Spec.HeldOutTarget` | the held-out target replaces masking across scale + time |
| `Spec.NudgeRankTheorem` / `Spec.MatrixTarget` | the rank-3 cell-aggregate loss (the real training objective `cellLoss`) |
| `Spec.AboveFloorMargin` | proves a 1-Q16-LSB invention survives the commit and moves off the floor |
| `Spec.VarianceFloorGuard` / `Spec.JepaTarget` | collapse guards (VICReg hinge; data-manufactured target) |
| `Spec.Codegen.ModelIO` | emits the Swift `SixFourModelIO.swift` model contract |

App-side: `SixFour/Generated/SixFourModelIO.swift` (emitted), `SixFour/Editing/ModelRender.swift`
(renders `palette[index]`). **Not yet built:** a Swift 256³ floor builder (Phase 3) and the hand-written
paint tool (W2.2).

---

## 4. The load-bearing vs contract-only taxonomy

This mirrors `Spec.Model.modelLawLedger` exactly (the machine-checked copy).

### LoadBearing — real theorems over the real kernels
- `lawOutputIsPerFrameValueContent` — the output is renderable per-frame value × content.
- `lawNeutralNudgeIsAllFloor` — zero paint = the byte-exact deterministic floor.
- `lawJointObjectiveIdentifiesFullPalette` — the rank-3 cell aggregate + the value head **identify** the
  full palette, conditional on `w_value > 0` (TRUE at `w_value=1`, FALSE at `w_value=0`).
- `lawValueHeadIdentifiesComplement` — the net-new checkerboard-parity witness: `cellLoss = 0` (blind) yet
  `valueLoss > 0` (seen).
- `lawParadigmIsStructurallySound` — structural soundness (identifiable, convergent readout, no-collapse,
  byte-exact crossing).
- `lawAboveFloorMarginReachable` — a 1-Q16-LSB invention survives `reenterQ16` and the reversible lift.

### DimensionalIdentity — true compile-time constant, load-bearing but not behavioural
- `lawCellGovernsSuperResSubtree` — `(256/16)³ = 4096`: the self-similar paint→subtree scale. Kept (not
  retired) because `ModelIO` consumes it; honestly labelled as an identity, not a behavioural theorem.

### StructuralWitness — strength is the argument, not the computation
- `lawHeldOutReplacesMasking` — the **scale** axis runs the real `liftOct`/`unliftOct` kernels (strong); the
  **time** axis is a minimal `Int` witness of motion ambiguity (thin until a real per-frame model exists).

### ContractOnly — UNPROVEN until trained (carries no truth value)
- `contractDescentOnRealDataUnproven` — that gradient descent **reaches** the identified optimum on a real
  captured corpus. Identifiability ≠ reachability.
- `contractEmpiricalSoundnessUnproven` — that the trained model **works** on real captures. The only run
  floored; the full-matrix trainer does not exist. See `docs/NEXT-STEPS.md` (W4.3).

---

## 5. What the unification retired (the record)

The model spec had accreted two grand capstones whose **names asserted an empirical outcome** the project
has never demonstrated, plus several purely-definitional tautologies. The unification:

| Was | Now | Why |
|---|---|---|
| `lawModelWillLearn` (LearnabilityTheorem) | `lawJointObjectiveIdentifiesFullPalette` + `contractDescentOnRealDataUnproven` | dropped the DESCENT conjunct (it rested on one retired `MaskedBandTrainer` fixture and was contradicted by the floored run); the capstone proves IDENTIFIABILITY, not reachability |
| `lawParadigmIsSound` (ParadigmSoundness) | `lawParadigmIsStructurallySound` + `contractEmpiricalSoundnessUnproven` | scoped to STRUCTURAL soundness; "sound" no longer reads as "the trained model works" |
| `lawNoSelfProducedRolloutTarget` (JepaTarget) | **deleted** | 3 of 4 conjuncts restated a hardcoded truth-table (`admissibleRolloutSource`); the real motion content survives in `constantOrbitPenalised` |
| `lawTemporalDeltaTargetIsDataManufactured` | `lawConstantOrbitMissesMovedFrame` | stripped the two `x==x` record-update conjuncts; kept the real motion witness |

The honest boundary is now **load-bearing**: `Spec.Model` references both contract markers as values, so
deleting either breaks the build, and `lawNoEmpiricalOverclaim` fails if a `WillLearn`/`ModelWorks`-style
law is re-introduced as `LoadBearing`.

---

## 6. The next real step

Not another law. The gaps are empirical (see `docs/NEXT-STEPS.md`): build the new full-matrix trainer,
train it, and **measure** whether the learned 256³ detail actually beats the deterministic `Upscale256`
floor (the `contractDescentOnRealDataUnproven` obligation). Until that number exists, the model is
spec-complete and unproven.

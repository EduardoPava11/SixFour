# SPEC-VS-APP CHANGE-MAP — how much of the app moves under the recent spec arc

> **SUPERSEDED 2026-07-13.** Snapshot of the 2026-07-03..05 spec arc, written pre-Swift-pivot
> (it cites deleted `Native/src/*.zig` paths). The living spec→app ledger is
> [`SPEC-APP-LINK-LEDGER.md`](SPEC-APP-LINK-LEDGER.md); this file is kept as the historical
> record of the A-contradiction analysis and the "do NOT touch" rulings.


> Status: LIVING · Created: 2026-07-05 · Owner: SixFour
> Produced by a 10-agent workflow (9 spec-stack audits + 2 cross-cuts, Opus 4.8)
> measuring the 2026-07-03…07-05 spec arc against the working tree. Every claim is
> `file:line`-cited against app code. Spec wins on any disagreement; where the app
> CONTRADICTS the spec it is flagged. Sizes: S=hours, M=a session, L=multi-session,
> XL=architectural/roadmap.

## 1. Verdict — what changes, by subsystem

**The substrate is done; the load-bearing wiring is not.** The app has faithfully
built every *frozen, zero-parameter carrier* the spec names and left almost every
*learned / influence-driven consumer* unbuilt or discarded.

| Subsystem | Remaining | Character of the work |
|---|---|---|
| Capture | ~20% | Breadth, not spine. Yin ladder correct + wired. Missing: 6 of 8 bands, opponent axes, velocity/entropy. |
| Color | ~60% | **Deepest contradiction.** CNN wants integer root chart `(R+G+B, R−G, G−B)`; app feeds OKLab float + a linear/gamma fork. |
| Training | ~70% | 1 of 7 yang heads built. Certified-order floor computed then thrown away. |
| Render/export | ~80% | **Structural pivot.** PullField (one-GIF-three-rungs) has zero app presence; live spine ships uniform-4× "fake 256²". |
| UI | ~75% | Post-capture flow is prior-gen: single scrub, binary mask, 2-arm decide. Arc wants view-toggle + cube brushes + tournament. |

Frozen carriers, the `CaptureFormat` wire contract, the `ABSurface` FSM, and the
paint-gate Q16 commit are done — **do not reopen** (§4).

## 2. Ranked change-map (deduped)

### A. Contradictions — fix or consciously re-scope FIRST

- **A1 — Influence field computed then discarded. `L`** `haltFloor()`/`s4_certified_order`
  reduced to `haltCertified = …filter{$0>=0}.count` (`CaptureSession.swift:860`), logged
  only (`:882`). Per-slot ORDER thrown away. Training runs hard-coded `steps:2500`
  (`BandHeadTrainer`). Root of 4 demands: HaltPrior keystone, PullField "bytes follow
  influence", tournament pruning, W=1 skip. **Highest leverage single fix.**
- **A2 — CNN color input is OKLab-float, not the root chart. `L`** `CaptureGene.swift:39-62`
  quantizes Ottosson OKLab (`ColorScience.swift:34-64`); `α₂=G−B` exists nowhere. Blocks
  every yang-head correctness claim. Sites: `Pipeline.swift`, `Shaders.metal`,
  `ColorScience.swift`, `CaptureGene.swift`, `RungDispatch.swift`.
- **A3 — Uniform 4× replicate = "fake 256²". `L`** `SixFourExport.replicate`
  (`ExportContract.swift:21-31`, applied `DeterministicRenderer.swift:247-250,457-460`)
  expands one 64² by the same factor everywhere; PullField wants per-region resolution.
  Kernel survives; its *uniform application* contradicts the field.
- **A4 — Empty budget routes to "invent everywhere". `M`** `NudgePaintView.swift:85-102`
  returns nil → `OctantCube.upRung:74` treats nil as live everywhere — inverse of
  `lawZeroPaintVolumeIsFloor`. Masked only by out-of-spec `useGene` (`CurateSurface.swift:111`).
- **A5 — Mixed arm is floor-vs-invention, not a pull of measured bins. `L`**
  `DecideSurface.swift:162-168`. MixSKI/FidelityLadder: v1 content = REAL bins (16³/32/64),
  the learnable object is the FIELD not invented content.
- **A6 — Binary paint mask vs depth-typed cube set. `M`** `NudgePaintModel.deviceMask`→`[Bool]`
  (`NudgePaintView.swift:85-102`); `lawPaintUnderdeterminesDepth` proves non-injective
  (3⁸→2⁸). Must become `deviceCubes(budget:)`.
- **A7 — Integer opponent coeffs hand-copied, not codegen'd. `M`** `kernels.zig:3126-3128`,
  `SixFourNative.swift:664`; no `OpponentContract` in `Generated/`.
- **A8 — Stored chart `b=R+G−2B` where CNN wants `G−B`. `S`** `V21Field.hs:171`/`kernels.zig:3127`;
  one-line flip per site.
- **A9 — `ABSurface` two-tile A/B screen retired. `S` (non-breaking)** FSM parity holds; serves
  ChoiceTraining. Cosmetic.
- **A10 — Stale `PhaseField` doc over vestigial edges. `S`** `PhaseField.swift:8-12`. Doc-only.

### B. Missing / partial, by downstream blocking weight

B1 `renderPull` one mixed-res GIF **XL** · B2 three-view toggle **L** · B3 rung-typed cube
brushes **L** · B4 tournament + Bradley-Terry **XL** · B5 `S_x`/`S_y` heads + swap-tying **L** ·
B6 the 6 missing mixed-difference bands **L** · B7 MIX depth-vector head **XL** · B8 `RootLatticeDecoder`
A₇ CVP **L** · B9 changed-rectangle encoder **L** · B10 train 16→32 rider (9/8 law) **L** ·
B11 LabBleed `bleedCell`+ρ knob **L** · B12 pull-color from sums-block mean **L** · B13 256³ super-res
subtree **L** · B14 W=1 skip **M** · B15 mass/inverse-variance loss weight **M** · B16 opponent (a,b)
axes + entropy in ColorHead **M** · B17 Pascal (1,2,1) coarse-velocity **M** · B18 Swift callers for
`s4_newton_predict`/`s4_residual_loss` **M** · B19 integer opponent inverse + congruences **M** ·
B20 unify linear/gamma alphabet **M** · B21 time-reversal augmentation **M** · B22 φ6 gauge consumed **M** ·
B23 Documents no-GC liability **M** · B24 dead renderer files **M** · B25 `s4_ladder_delay_cs` as shipped-byte
source **S** · B26 out-of-range paint guard **S**.

## 3. Dependency spine — what unlocks what

**Influence spine (color/render):**
`A1 keep per-slot ORDER` → `B1 renderPull` (replaces A3) → {B12 pull-color, B9 changed-rect, B8 CVP};
and `A1` → HaltPrior budget via `B18` → PonderNet halt. A1 is simultaneously the halting keystone and
the precondition for the whole PullField pivot.

**Color spine (precedes ALL yang training):**
`A2 root chart + B20 unify alphabet + A8 flip α₂` → `B16 (a,b) fiber axes` → `B6 six missing bands` →
`B5 S_x/S_y + swap-tying` → {B15 weighted loss, B14 W=1, B10 16→32 rider}. **Do A2/A8/B16/B20 as ONE
seam-migration** (same files: `ColorScience`, `Shaders.metal`, `kernels.zig`, `CaptureGene`) — half-migrating
leaves two incompatible alphabets.

**UI spine (post-capture):**
`B2 view toggle` → `B3 cube brushes` (replaces A6) → superlevel masks into `expandProposal` →
`A5 real-bin arm` → `B4 tournament+BT` → `B7 mix head`. Constraints: **A4 (empty=floor) before any typed
paint**; **view-toggle before mix-head training**; A1 influence pruning gates which regions the tournament asks about.

**Convergence:** B4 + B7 are where all three spines meet (need root-chart heads + depth field + live pick
stream). Last, XL, roadmap-bracketed — nothing above waits on them.

## 4. What NOT to touch (spec-frozen / conformant)

- **YIN encoder / sums carrier** — `ColorHead.poolSums64`/`poolSpatial2`/`ingest`, `s4_pool_sums_*`.
  `lawEncoderIsAllOnesConv`, correct. Becomes load-bearing under PullField; code unchanged.
- **`ABSurfaceMachine`** — `abStep`+gate laws+`assertSpecParity` (`:83-173`). Only compartment-tagged hard obligation, met.
- **`CaptureFormat` wire contract** — replicate/decimate round-trip, per-frame LCT, `globalPaletteV2=false`,
  `captureCellSpan=4`. Codegen'd + golden-gated (`trainer/gif_to_capture.py`). Do not hand-edit.
- **Paint-gate Q16 core** — `lawNudgeMovesOutput`, `lawMaskUpsampleIsBlockReplication`, `lawForwardCommitIsQ16`
  (round-half-to-even), `lawResidualStaysInA7`. `PaintGateTests`. (Extends to ternary under B3; block-local commit is right.)
- **`ModelRender`** — integer `palette[index]`, display-only OKLab→sRGB (`:22-51`).
- **`s4_gif_assemble`** (`kernels.zig:1861`) — survives PullField untouched; caller changes (B9 sub-rects), contract doesn't.
- **`s4_certified_order`** (`kinematic.zig:45`) — observable correct; only consumption (A1) is broken. Don't touch the kernel.
- **PaletteKinetics/SpineRing conformant pieces** — slot `16·by+bx`, `lawMassPoolsExactly`, Morton-as-address.
- **`CaptureBundle` JSON** — stores inputs, orthogonal to render algebra; survives.

Caveat: sums carrier + `haltFloor` are correct but on the wrong color basis / discarded respectively —
leave the CODE, fix the CONSUMERS (A1, A2). The `V21` sidecar export is live+correct but is what PullField
*replaces* — "don't touch now, retire later," not permanently frozen.

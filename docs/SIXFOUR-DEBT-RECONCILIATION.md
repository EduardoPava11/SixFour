# SixFour — Ethos & Technical-Debt Reconciliation

_Reconciled cleanup plan — 2026-06-05. Glass retired app-wide today; total pixelation won._
_Produced by the `sixfour-ethos-debt-audit` workflow (46 agents): 33 findings → 18 live, 15 dismissed, each adversarially verified against current state._

## 0. Resolution log (live updates)

| Debt | Status | Where |
|------|--------|-------|
| INV-ATOM-ONLY-GIFPX-1/2, LAW-ATOM-FORCED-* (bare point dims) | ✅ fixed | `81dadd2` (Tier 1) |
| INV-T4-UNIFORM-ATOM (HaarShutterView free `cellPt`) | ✅ fixed | `81dadd2` |
| GLASSOVERCONTENT-DEAD-CODE | ✅ deleted | `81dadd2` |
| INV-CONTRADICTION-LAW2-GLASS + 3 siblings (§2.4.2 stale-doc) | ✅ rewritten | `81dadd2` |
| (bonus) `CellContract.Golden` Swift 6 `Sendable` break | ✅ codegen fix | `81dadd2` |
| SPEC-DISPLAY-UNBUILT / INV-SPEC-DISPLAY-MODULE / INV-UNIF-SPEC-DISPLAY-UNBUILT (T1–T9) | ✅ proven | `a4532a8` + `6dabded` (contract) |
| INV-UNIF-FRONT-PROJECTION-SPEC-GAP | ✅ closed (spec+golden+test+log) | `176186d` + `8c560e7` |
| INV-T2-ONE-CLOCK (CADisplayLink swap) | 🧪 test-gated, refactor pending | `98a032a` (gate) |
| DATAKIND-UNJUSTIFIED-AXISNET | ⏸ deferred (misclassified — load-bearing σ-equivariance) | — |
| INV-ZIG-BYTE-EXACT-MISSING-GOLDENS (items 9/12) | ☐ open (needs test-fixture bundling) | — |
| VISION-SEARCH-KEYSTONE-GAP | ☐ open (Phase-2 SEARCH) | — |

The runtime refactors (FSM steps 3–5) are each **test-gated** now (see `DisplayContractTests`,
`FrontProjectionGoldenTests`, `Spec.FrontProjection`), so they can be done safely on a
camera-less simulator and confirmed by tests; a final device A/B remains for the visuals.

## 1. Ethos Restatement

- **One cube, projected honestly.** The 64³ index cube is the single source of truth; the 2D GIF hero, the palette grid, and the shutter are all Haar projections of that one state — never independent representations.
- **One atom.** `gifPx = 6 pt` (= 18 device-px @3×) is the sole pitch. Widgets grow by using **more** cells, never a bigger cell. Any element that declares its own point size is a "dual-pitch" violation. All cell↔point math lives in one owner: `GlobalLattice`.
- **The grid is the render surface.** Content is flat indexed cells, byte-exact sRGB8. **No glass on any surface** as of today. Chrome is cell-rendered (pixelated), never glassy.
- **Haskell is the source of truth; spec-first with golden gates.** Every cross-language claim (Zig ↔ Haskell ↔ Swift) is pinned by a generated golden vector. Swift and Zig mirror the spec; they never lead it.
- **NN proposes, SEARCH generates options, the user picks, the spec proves each projection.** Selection (collapse + preference) is not search — the keystone SEARCH phase is still owed.
- **Rigor only where failure is "pager-on-fire."** Stay at golden vectors + Layer 0–2; escalate to DataKinds/type-level proofs **only** when a shape-composition theorem becomes load-bearing. Elegance is not a justification. Contested-cell resolution (clean / shimmer / sentinel, never blend) is proven-good and is **not** debt.

---

## 2. Live Debt by Ethos Pillar

### Pillar A — One Atom (design language / `gifPx`)

| ID | Location | Invariant violated | Fix | Severity | fixClass |
|----|----------|--------------------|-----|----------|----------|
| INV-ATOM-ONLY-GIFPX-1 | `SixFour/UI/Components/AddressPickerView.swift:173` | `stepButton` uses bare `44×28` — neither is an integer multiple of gifPx (44÷6=7.33, 28÷6=4.67). | Replace `.frame(width: 44, height: 28)` with `.frame(width: GlobalLattice.gif(8), height: GlobalLattice.gif(5))` (48×30 pt; 48 meets touch floor). | high | mechanical-safe |
| INV-ATOM-ONLY-GIFPX-2 | `SixFour/UI/Components/GlobalPaletteEditorView.swift:92` | `grainButton` uses bare `44×30`; 44 pt = 7.33 gifPx (legacy 2-pt-cell artifact), 30 pt hardcoded. | Replace with `.frame(width: GlobalLattice.gif(8), height: GlobalLattice.gif(5))`. | high | mechanical-safe |
| LAW-ATOM-FORCED-VIOLATION-1 | `SixFour/UI/Screens/Capture/CaptureView.swift:181` | `livePaletteGrid` passes bare literal `cellPt: 12`, bypassing `GlobalLattice`. Size (192 pt) is correct per `ScreenLattice.swift`; only the literal is wrong. | Replace `cellPt: 12` with `cellPt: GlobalLattice.pt(6)` (or `GlobalLattice.gif(2)`). | low (corrected) | mechanical-safe |
| LAW-ATOM-FORCED-DIRECT-LITERAL-CELLPT | `CaptureView.swift:181` + `HaarShutterView.swift:13` | Bare `cellPt` literals (12 pt, 24 pt) bypass the single `GlobalLattice` owner (Law #5). Values correct per ADR-5; expression is the violation. | Express through lattice: palette `GlobalLattice.gif(2)`, shutter `GlobalLattice.gif(4)`. | low (corrected) | mechanical-safe |
| INV-T4-UNIFORM-ATOM | `SixFour/UI/Components/HaarShutterView.swift:13` | `var cellPt: CGFloat = 24` exposes a **free per-view pitch**. Both call sites comply (24 = 6×4) and the view is Review-scoped (EXEMPT-REVIEW-PITCH), but the parameter itself permits dual-pitch. | Store a `blockFactor` (=4) and compute `cellPt = GlobalLattice.gif(blockFactor)`; make the Review exemption explicit so callers can't set arbitrary pitch. | medium (corrected) | mechanical-safe |

### Pillar B — The Grid Is The Render Surface (no glass)

| ID | Location | Invariant violated | Fix | Severity | fixClass |
|----|----------|--------------------|-----|----------|----------|
| GLASSOVERCONTENT-DEAD-CODE | `SixFour/UI/Components/GlassOverContent.swift:28` | Fully-implemented L1 glass component with **zero production callers** (`grep 'GlassOverContent(' ` finds only the declaration). Its L1 glass layer no longer exists. | Delete the file. If historical reference is wanted, move to `docs/archive/`. All chrome is now flat cells (`GlassControls.swift:59–63` use `HStack`). | medium | mechanical-safe |
| INV-CONTRADICTION-LAW2-GLASS | `docs/SIXFOUR-DISPLAY-FSM.md:159-191` vs `docs/SIXFOUR-DESIGN-LANGUAGE.md:104,738` | DISPLAY-FSM §2.4.2 still formalizes Law #2 as "glass over content" (`encode∘glass=encode`) and cites `GlassOverContent.swift` as the L1 realization; DESIGN-LANGUAGE v2.0 retires glass on **every** surface (line 738). | Rewrite §2.4.2: remove the glass-layer law; restate Law #2 as "Content (L0) is flat indexed cells, byte-exact GIF; no glass on cells; all chrome is cell-rendered." Cite the 2026-06-05 retirement and the archived glass spec. | high (corrected medium) | mechanical-safe |
| SIXFOUR-DISPLAY-FSM-GLASS-CONTRADICTION | `docs/SIXFOUR-DISPLAY-FSM.md:159-191` | Same contradiction as above, raised from the design-language pillar; DISPLAY-FSM marked "pre-implementation" but never updated for the retirement. | Resolve jointly with `INV-CONTRADICTION-LAW2-GLASS` — single edit to §2.4.2 + archive pointer. | high (corrected medium) | mechanical-safe |
| GLASS-LAW2-CONTRADICTION | `docs/SIXFOUR-DISPLAY-FSM.md:159-191` | Spec-methodology view of the same stale Law #2 glass sanction. | Same §2.4.2 rewrite; mark DISPLAY-FSM superseded-in-part by DESIGN-LANGUAGE v2.0. | high (corrected medium) | mechanical-safe |
| INV-UNIF-LAYER-LAW-CONTRADICTION | `docs/SIXFOUR-DISPLAY-FSM.md:159-191` | Representation-unification view: §2.4.2 says L1 glass "awaits an on-device build"; glass was retired 2026-06-05. The `encode∘glass=encode` law is now vacuously true. | Change "awaits an on-device build" → "retired 2026-06-05 per SIXFOUR-TOTAL-PIXELATION.md; law holds vacuously (no glass exists)." | low (corrected) | mechanical-safe |

> **Note:** the four glass-contradiction items above all point at `SIXFOUR-DISPLAY-FSM.md §2.4.2`. They collapse into **one** documentation edit plus the `GlassOverContent.swift` deletion.

### Pillar C — Haskell-Is-Truth / Spec-First (golden gates)

| ID | Location | Invariant violated | Fix | Severity | fixClass |
|----|----------|--------------------|-----|----------|----------|
| SPEC-DISPLAY-UNBUILT | `spec/src/SixFour/Spec/Display.hs` (absent) | The display FSM `M=(Σ,ι,δ,λ,Π,κ)` is undefined in Haskell; T3 (`reconstructFixed ∘ analyzeFixed = id`) and the three-projection-share-state law are unproven. Blocked behind the glass §2.4.2 reconciliation. | After §2.4.2 is corrected, build `Spec.Display` with `DisplayState=(Palette,IndexCube,Cursor)`, `projGif/projPalette/projShutter` pattern-matching ONE state, and `lawProjectionsShareState` (`projShutter = map oklabToSrgb8 (levelNodesFixed 4 P)`). Emit goldens; wire `cabal test`. | high (corrected) | spec-work |
| INV-SPEC-DISPLAY-MODULE | `spec/src/SixFour/Spec/Display.hs` (absent) | Module must prove T1–T9 and codegen `DisplayContract.swift` pinning `logicRateHz=20`, `panelRates=[60,120]`, `holdCounts=[3,6]`, per-view blockFactors, golden tick-trace. | Same as above; import proven modules (PlaybackClock, Lattice, PairTreeFixed, Gauge, QuantFixed, Dither, ColorFixed, CellFiber, CellGrid); most reductions are one-line citations. | high | spec-work |
| INV-UNIF-SPEC-DISPLAY-UNBUILT | `docs/SIXFOUR-DISPLAY-FSM.md:405-406,422-449` | Reuse map marks `Spec.Display` "to write" (and stale-marks CellFiber/CellGrid "to write" though they now exist, completed 2026-06-05). T1–T9 prove nowhere. | Build `Spec.Display.hs` per §6.1 signature; add `Properties/Display.hs`; fix the reuse map to show CellFiber/CellGrid as built. Precondition: §2.4.2 glass reconciliation. | high | spec-work |
| INV-UNIF-FRONT-PROJECTION-SPEC-GAP | `SixFourTests/VoxelRestPoseIdentityTests.swift:49-92`; `docs/archive/SIXFOUR-REPRESENTATION-UNIFICATION.md:89-94` | "2D GIF IS the front projection of the 3D index cube" is verified **only** in a Swift-local test; no Haskell source-of-truth golden. | Add `spec/src/SixFour/Spec/FrontProjection.hs` proving `frontSlice(cube,cursor)(x,y)=cube[cursor][y*64+x]` with `f(z)=(cursor-63+z) mod 64`, plus `lawFrontIsCurrentFrame` / `lawRestPoseEqualsGifFrame`. Emit a golden and gate the Swift test against it. | high | spec-work |
| INV-ZIG-BYTE-EXACT-MISSING-GOLDENS | `SixFourTests/GlobalRenderTests.swift:49`; `Native/src/kernels.zig:985,1259` | `s4_gif_assemble` claims byte-for-byte parity with `GIFEncoder.swift`/`Gen.GifWire` but `GlobalRenderTests` asserts only magic prefix + self-determinism, not bytes==golden. `s4_srgb8_to_oklab_q16` has no dedicated golden in any tier. (Tracked: TECH-DEBT-LEDGER Band 4 items 9, 12.) | Item 9: add `Codegen/GifGolden.hs` (or bundle `gif_golden.gif`), create `ZigGifAssembleGoldenTests`. Item 12: add a Zig golden in `kernels.zig` or a Haskell round-trip property in `ColorFixed.hs` for sRGB8→linear→OKLab. Correct the ledger line number (1086→1259). | medium | spec-work |

### Pillar D — NN Proposes, SEARCH Generates (vision)

| ID | Location | Invariant violated | Fix | Severity | fixClass |
|----|----------|--------------------|-----|----------|----------|
| VISION-SEARCH-KEYSTONE-GAP | `docs/SIXFOUR-VISION.md:54-61` | The SEARCH phase (`capture → per-frame → collapse → SEARCH → DPP gallery → swipe`) does not exist. Collapse + preference are selection, not search; the gallery has no candidate set to diversify. Documented/acknowledged as the keystone gap. | Phase-2 spec work: MCTS tree, playout grammar (lossless Haar folds), exploit↔explore schedule, halting, leaves→gallery. Golden traces. Tracked, intentional — not a hidden bug. | medium | spec-work |

### Pillar E — Rigor Only Where Load-Bearing (spec methodology)

| ID | Location | Invariant violated | Fix | Severity | fixClass |
|----|----------|--------------------|-----|----------|----------|
| DATAKIND-UNJUSTIFIED-AXISNET | `spec/src/SixFour/Spec/AxisNet.hs:1-7,67,71-76` | `DataKinds`/`KindSignatures` promote `ColorAxis` (AxisL/A/B) with a `KnownAxis` reification class, but no shape-composition theorem is load-bearing: AxisNet is never instantiated in the active pipeline and all correctness is runtime QuickCheck. Methodology §2 forbids exactly this. | Refactor to runtime `ColorAxis` values; drop `DataKinds`/`KindSignatures`; make `axisVal` a plain function. Semantics unchanged; confirm no properties break. | medium | mechanical-safe |

### Pillar F — One Clock (display FSM)

| ID | Location | Invariant violated | Fix | Severity | fixClass |
|----|----------|--------------------|-----|----------|----------|
| INV-T2-ONE-CLOCK | `SixFour/UI/Components/VoxelCubeView.swift:230-232,257` | A live 60 Hz `Timer` (`displayHz=60`, `rotateClock`) drives cube auto-rotate, separate from `PlaybackClock`'s 20 Hz Timer; no `CADisplayLink` exists in the codebase. **Corrected:** this is an auxiliary animation timer, not a δ_capture/δ_review frame-advance clock, so it does not break T2 today; the `CADisplayLink` unification depends on unwritten `Spec.Display.hs`. | Defer to the `Spec.Display` build: introduce one `CADisplayLink(preferredFrameRateRange: 20/20/20)` as κ shared by PlaybackClock and the cube; read `targetTimestamp` for auto-rotate; retire `displayHz`/`rotateClock`. | medium (corrected) | spec-work |

---

## 3. Prioritized Execution Order

### Tier 1 — Mechanical-Safe (batch-apply, no design call)

These are pure substitutions or single documentation edits. Apply together, run the Swift + Haskell test suites once.

**Swift lattice fixes (one PR):**
1. `AddressPickerView.swift:173` → `GlobalLattice.gif(8) × GlobalLattice.gif(5)` _(INV-ATOM-ONLY-GIFPX-1)_
2. `GlobalPaletteEditorView.swift:92` → `GlobalLattice.gif(8) × GlobalLattice.gif(5)` _(INV-ATOM-ONLY-GIFPX-2)_
3. `CaptureView.swift:181` → `cellPt: GlobalLattice.pt(6)` _(LAW-ATOM-FORCED-VIOLATION-1 + DIRECT-LITERAL)_
4. `HaarShutterView.swift:13` → store `blockFactor=4`, derive `cellPt = GlobalLattice.gif(4)`; mark EXEMPT-REVIEW-PITCH explicitly _(INV-T4-UNIFORM-ATOM + DIRECT-LITERAL shutter half)_

**Dead-code deletion (same or adjacent PR):**
5. Delete `GlassOverContent.swift` (or move to `docs/archive/`) _(GLASSOVERCONTENT-DEAD-CODE)_

**Documentation reconciliation (one edit, resolves four findings):**
6. Rewrite `SIXFOUR-DISPLAY-FSM.md §2.4.2` (lines 159–191): drop the glass-layer law, restate Law #2 as flat-cells-only, cite the 2026-06-05 retirement + `docs/archive/SIXFOUR-GLASS-LANGUAGE.md`, change "awaits an on-device build" → "retired (law holds vacuously)". Fix the reuse map (line ~405) to show CellFiber/CellGrid as **built**. _(resolves INV-CONTRADICTION-LAW2-GLASS, SIXFOUR-DISPLAY-FSM-GLASS-CONTRADICTION, GLASS-LAW2-CONTRADICTION, INV-UNIF-LAYER-LAW-CONTRADICTION)_

**Spec hygiene:**
7. `AxisNet.hs` → de-promote `ColorAxis` to runtime values, drop `DataKinds`/`KindSignatures` _(DATAKIND-UNJUSTIFIED-AXISNET)_ — mechanical but run the full Haskell suite to confirm no property regresses.

### Tier 2 — Judgment-Required (needs a design call before code)

_None._ Every live finding resolved to either a mechanical substitution or genuine spec-work. The historically "contested" calls — `paletteCellPt=24` Review exemption, the contested-cell shimmer/sentinel rule, the 768-vs-384 DOF distinction — were all checked and dismissed (see appendix). No item requires a fresh design decision; the glass retirement and the Review-pitch exemption are already decided policy.

### Tier 3 — Spec-Work (Haskell, ordered by dependency)

Do **after** Tier 1 step 6 (the §2.4.2 glass reconciliation unblocks the FSM spec).

1. **`Spec.Display.hs`** — build `M=(Σ,ι,δ,λ,Π,κ)`, prove T1–T9, codegen `DisplayContract.swift` (pin `logicRateHz=20`, `panelRates=[60,120]`, `holdCounts=[3,6]`, per-view blockFactors, golden tick-trace). Add `Properties/Display.hs`; wire `cabal test`. _(SPEC-DISPLAY-UNBUILT, INV-SPEC-DISPLAY-MODULE, INV-UNIF-SPEC-DISPLAY-UNBUILT)_
2. **`Spec.FrontProjection.hs`** — prove `frontSlice`/`f(z)` and `lawRestPoseEqualsGifFrame`; emit golden; gate `VoxelRestPoseIdentityTests.swift`. _(INV-UNIF-FRONT-PROJECTION-SPEC-GAP)_ Can proceed in parallel with #1.
3. **`INV-T2-ONE-CLOCK`** — once `Spec.Display` pins κ, replace VoxelCubeView's 60 Hz Timer with the shared `CADisplayLink`. Depends on #1.
4. **Zig goldens** — Band 4 item 9 (`ZigGifAssembleGoldenTests` + `GifGolden.hs`) and item 12 (sRGB8→OKLab golden / `ColorFixed.hs` property); fix ledger line 1086→1259. _(INV-ZIG-BYTE-EXACT-MISSING-GOLDENS)_ Independent; medium priority.
5. **SEARCH (Phase 2)** — spec the MCTS tree, playout grammar, exploration schedule, halting, leaves→gallery with golden traces. _(VISION-SEARCH-KEYSTONE-GAP)_ Largest body of new work; sequence last.

---

## 4. Dismissed Appendix

Each was adversarially checked and is **not** debt:

- **INV-NO-GLASS-EVERYWHERE-1** (`GlassOverContent.swift:43`) — `GlassEffectContainer` on line 43 is never instantiated; it's the formalization of a superseded spec, a doc-cleanup item, not a live code bug. (Overlaps the live `GLASSOVERCONTENT-DEAD-CODE` deletion.)
- **INV-SPEC-LATTICE-UNBUILT-1** (`SIXFOUR-DESIGN-LANGUAGE.md:5,95`) — `Spec.Lattice.hs` is built (339 LOC, 13 tests green); the "[PLANNED]" tag is stale. Already-fixed.
- **LAW-ATOM-FORCED-VIOLATION-2** (`HaarShutterView.swift:13`) — conflates the capture `CellShutter` with the Review `HaarShutterView`; `cellPt=24` is the named EXEMPT-REVIEW-PITCH exemption, not a violation. False-positive.
- **SPEC-DISPLAY-FSM-UNBUILT** (`GlobalLattice.swift:26` + DISPLAY-FSM:422-441) — accurately notes Spec.Display absent, but the FSM is pre-implementation and glass-superseded; captured by the live spec-work items. Stale-doc, not separate debt.
- **SPEC-LATTICE-UNBUILT-ENFORCEMENT** (`DESIGN-LANGUAGE:5,95` + `GlobalLattice.swift:24`) — `lawEveryGovernedDimIsCells` exists (Spec.Lattice.hs:332-339) and is tested in `LatticeContract.swift`. Moot.
- **CONTRADICTION-DISPLAY-FSM-VS-DESIGN-LANGUAGE-GLASS** (FSM:159-192 vs DL:104,120) — the glass retirement is a documented deliberate decision in DL §0.0/§9.7, not an unresolved contradiction. (Doc edit covered by live item.) Already-fixed.
- **DATAKIND-DEFAULT-EXTENSION** (`spec.cabal:102-108`) — blanket `DataKinds/GADTs/TypeFamilies` defaults are load-bearing for `Pipeline.hs` (`option4Theorem`, `sigmaPairHeadTheorem`) and `Layer.hs`, explicitly sanctioned by methodology §2. False-positive (distinct from the genuinely-unjustified `AxisNet` use).
- **INV-NN-384-DOF-PALETTE-TREE-CONFUSION** (`PairTreeGolden.swift:11-12`) — 768 DOF is correct for the depth-8 production palette (3·256); 384 is the upstream NN σ-pair genome. Two different pipeline stages, not conflated. False-positive.
- **INV-GLASS-CONTRADICTION-DESIGN-LANGUAGE-RETIRED** (`DESIGN-LANGUAGE:587` / FSM:159) — same glass doc mismatch; `GlassOverContent` is dead, needs archival not annotation. Moot (folded into live deletion).
- **INV-T1-CLOCK-DIVIDES** (`PlaybackClock.swift:62-63`) — 20 Hz Timer trivially satisfies 60%20==0 / 120%20==0; only the formal proof infra is unbuilt (a spec-work item, not a live violation). Stale-doc.
- **INV-NO-BLEND-SENTINEL** (`ContestedCellGridView.swift:9-14`) — `lawNoSynthesis` implemented and golden-verified; finding documents compliance. False-positive.
- **INV-EFFECT-ZONE-SHIMMER** (`ContestedCellGridView.swift:30-40`) — `lawShimmerIsClaimant` proven and golden-gated; documents a satisfied invariant. False-positive.
- **INV-UNIF-GLASS-OVER-CONTENT-DEAD** (`GlassOverContent.swift:1-50`) — dead code, glass retired; the real residue is the FSM doc edit (live item). Moot.
- **INV-UNIF-INDEX-NONOPTIONAL-INCONSISTENCY** (`CaptureViewModel.swift:53`; `VoxelCubeView.swift:74`; `GIFPlayer.swift:126`) — all three render paths unconditionally populate `frameIndicesForVoxels`; the Optional type is legacy, not a live violation; VoxelCubeView is shelved. Already-fixed.
- **INV-UNIF-SCOPE-RENDER-SWAP-DOCS** (`CaptureViewModel.swift:479-483,555-636`) — capture-time scope is already enforced via immutable `CaptureOutput`; proposed type-brand guards a non-existent risk. Stale-doc.

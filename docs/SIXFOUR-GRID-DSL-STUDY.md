# SIXFOUR Grid UI DSL — Orientation Map

**Date:** 2026-06-06
**Status:** orientation map (study output). Cites real `file:line` across the Haskell spec, the Swift on-device impl, and the generated contracts + gates.

---

## 1. Thesis — the grid IS the UI language

SixFour has no widget toolkit; it has a **grid DSL**. The whole 100×218-atom screen is one field of 4pt cells, and *every* element — the 64×64 preview hero, the 16×16 palette/shutter, the ring gauge, the wordmark, the background — is expressed as a **rectangular claim on that field** rendered through a **no-blend cell algebra**. A cell's colour is exactly one claimant's colour; two owners claiming one cell is not averaged into a blend — it is surfaced as a loud `contestedSentinel`, i.e. **contention is a visible bug, not a mixture**. The DSL is specified in Haskell (`Spec.Lattice`, `Spec.GridLayout`, `Spec.CellFiber`, `Spec.CellGrid`), codegen'd to Swift contracts (`LatticeContract`, `GridLayoutContract`, `CellContract`), realised on device by one SIMD cell field driven by **one 20fps clock** (`SurfaceClock`), and policed by `lint-grid.sh` (single atom, placement-by-claim, no-blend draw vocab). The end-state the DSL is reaching for is **`color = ownership`**: a total map `owner:(x,y) → Owner` over the whole field, with each owner's region rendered in that owner's identity colour. Today the DSL proves a *disjoint partial* cover (two named owners), and the no-blend engine exists but is not yet keyed by an `Owner` type — that final join is the open work (§5).

---

## 2. The three tiers

### Tier A — Haskell spec (source of truth)

| Atom | Role | `file:line` | Owns |
|---|---|---|---|
| `gifPx = 4` | THE 4pt atom; unit cell of the whole field | `spec/src/SixFour/Spec/Lattice.hs:107` | the (x,y) granularity an Owner map ranges over |
| `cols=100 / rows=218` | screen lattice extent (402/4 × 874/4) | `Lattice.hs:129,133` | the total (x,y) domain any cover must tile |
| `previewCells = 64` | hero preview = 64 atoms (cube law) | `Lattice.hs:170` | the PREVIEW owner's region size (64×64 frames) |
| `shutterCells = 16` | shutter/palette footprint; `disc·2+ring·2=16` | `Lattice.hs:185` (+`216,220`) | the PALETTE/shutter owner's region size (16×16) |
| `ringCells=20 / ringTicks=64` | diversity gauge, one tick per frame | `Lattice.hs:192,196` | the RING-GAUGE owner's region size |
| `wordmarkRows=11 / Cols=60` | wordmark title band | `Lattice.hs:200,204` | the WORDMARK owner's region size |
| `controlCells / segmentCells / touchFloorCells` | gear=12; segment/HIG floor=11 (44pt) | `Lattice.hs:179,207,175` | GEAR owner size + the interactivity-legality bound |
| `cellsToPt` | the single atom-count → point conversion | `Lattice.hs:225` | the only place a region size becomes physical size |
| `LRegion {lrWidget,lrPriority,lrInteractive}` | one widget's rectangular claim + owner-id + tiebreak | `GridLayout.hs:66` (`lrWidget` `:71`) | ONE owner's region + identity (the proto-Owner record) |
| `Scene = [(String, LRegion)]` | named set of widget regions = one screen | `GridLayout.hs:77` | the whole field's claim set |
| `captureScene` | as-built cover: preview (widget 0) + palette (widget 1, interactive) | `GridLayout.hs:88` | the concrete 2-owner cover that ships |
| `sceneGrid` (unexported) | folds claims into `Map (Int,Int) Cell`, keyed by `lrWidget` as `Color` | `GridLayout.hs:112` | the ACTUAL (x,y)→claim map — already owner-keyed, internal-only |
| `sceneContested` | every cell two+ widgets collided on | `GridLayout.hs:120` | the visible-contention surface |
| `Color` (Q16 OKLab) | the fiber value; `Ord`-canonical, source-free | `CellFiber.hs:85` | the per-cell colour value (the WHAT) |
| `Cell = Set Color` | bounded join-semilattice carrier | `CellFiber.hs:89` | the multi-claim state of one place; `|cell|>1` = contention |
| `render :: Cell → Color` | ⊥↦neutral, singleton↦self, ≥2↦sentinel | `CellFiber.hs:165` | how an owner's identity shows verbatim; double-claim → loud bug |
| `isContested` | `Set.size c > 1` | `CellFiber.hs:115` | detection of a double-owned cell |
| `contestedSentinel` / `neutralColor` | loud magenta marker / mid-grey ⊥-anchor | `CellFiber.hs:159,152` | identity of a CONTENDED / an UNOWNED cell |
| `shimmerAt` | time-multiplex claimants on the 20fps clock | `CellFiber.hs:176` | the only sanctioned multi-owner display path (one real claimant/tick) |
| `Place {placeRow,placeCol}` | a coord in the 64×64 GIF field | `CellGrid.hs:80` | the spatial position (the WHERE) |
| `Widget` (newtype Int) | THE UNIT OF OWNERSHIP, abstract id | `CellGrid.hs:111` | the owner identity itself — un-instantiated |
| `Owner = Place → Maybe Widget` | which widget owns each cell | `CellGrid.hs:118` | **the literal `owner:(x,y)→Owner` map the model wants** |
| `EffectZone = Place → Bool` | where overlap is sanctioned shimmer, not a bug | `CellGrid.hs:123` | the exception carve-out for multi-ownership |
| `contestedPlaces` | every place 2+ widgets collided | `CellGrid.hs:159` | the field-level contention audit (empty ⇔ well-formed) |
| `GridScript`/`Order`/`GridAxis` | EMBEDDING∘COLOR∘ORDER fill spine; verified bijection | `GridScript.hs:48` / `Order.hs:61` / `GridAxis.hs:72` | *within* one owner's region, the slot→cell placement |
| `AxisNet` (`ColorAxis`/`projectAxis`) | OKLab L/a/b σ-decomposition | `AxisNet.hs:67,106` | PERCEPTUAL colour — a **rival** meaning of "color" to disambiguate (§5) |

### Tier B — Swift on-device impl

| Atom | Role | `file:line` | Owns |
|---|---|---|---|
| `SFColor` (Q16 OKLab) | fiber value carrier; the proposed owner-identity slot | `SixFour/UI/CellAlgebra.swift:15` | the WHAT at one cell |
| `SFCell` | canonical dedup set of `SFColor` claims | `CellAlgebra.swift:21` | the set of claims at one place |
| `SFCell.join` | set union (idem/comm/assoc) | `CellAlgebra.swift:40` | how two owners' claims combine (into contested, never blend) |
| `SFCell.isContested` | `claims.count > 1` | `CellAlgebra.swift:46` | detection of a double-owned cell |
| `SFCell.render` | 0↦neutral, 1↦that claim, ≥2↦sentinel | `CellAlgebra.swift:51` | colour as a function of the owner-set |
| `SFCell.shimmer` | claimant `tick%n` on the 20fps clock | `CellAlgebra.swift:63` | the 20fps time-multiplex of contested owners |
| `renderCell(_:tick:inEffectZone:)` | contested+zone↦shimmer, else loud sentinel; clean↦verbatim | `CellAlgebra.swift:83` | per-cell colour at tick t — the fn that would consume an Owner map |
| `SurfaceClock` (κ) | THE ONE 20fps `CADisplayLink`, pinned to `logicRateHz` | `SixFour/UI/Surface/SurfaceClock.swift:22` (`fire` impl, range `:52`) | the whole-field 20fps refresh cadence |
| `SurfaceColor.oklabQ16ToSrgb8` | fixed-point OKLab→sRGB8, byte-exact vs Zig | `SixFour/UI/Surface/SurfaceColor.swift:80` | the colour bake: stored Q16 → the sRGB8 a cell wears |
| `LivePhaseField.previewHero` | always a 64×64 cell tile (cube law) | `SixFour/UI/Surface/LivePhaseField.swift:72`, placed `:44` | the PREVIEW owner's responsibility |
| `LivePhaseField.paletteShutter` | 16×16=256 palette grid that IS the shutter | `LivePhaseField.swift:101`, placed `:48` | the PALETTE owner (fused with shutter on live) |
| `TintedCheckerField` | full-screen checker ground; inverts at 20fps via heartbeat | `LivePhaseField.swift:140` | the BACKGROUND owner — but NOT a `place()`-d region |
| `ContestedCellGridView` | the cell algebra made visible (≤256-cell Canvas) | `SixFour/UI/Components/ContestedCellGridView.swift:25` | on-screen render of a contested grid; `cellAt`/`effectZone` injected, unconstrained |
| `CellField / setCell` | whole-screen SIMD byte bitmap; sole HUD cell writer | `SixFour/UI/Components/CellField.swift:27` | the background-field SIMD substrate |
| `PixelGrid / fillCell` | flat indexed cells, no AA/opacity/stroke | `SixFour/UI/Components/PixelGrid.swift:101` | the no-blend LOOK every colour is drawn under |
| `PaletteGridView` | 16×16 axis-assignable palette view | `SixFour/UI/Components/PaletteGridView.swift:16` | the PALETTE owner's responsibility surface |
| `GridRegion {widget,priority,interactive}` | one owner's rectangular cell claim | `SixFour/Generated/GridLayoutContract.swift:10` (`widget` `:16`) | a named owner's rectangle; `widget` = owner-id |
| `View.place(_:)` | THE sole placement primitive (one sanctioned `.position`) | `SixFour/UI/ScreenLattice.swift:22` (by-name `:36`) | binds a widget to its owned rectangle — **but discards `region.widget`** |

### Tier C — Generated contracts + gates

| Atom | Role | `file:line` | Owns |
|---|---|---|---|
| `SixFourLattice` + per-widget counts | generated 4pt-atom lattice; `previewCells=64`, `shutterCells=16`, … | `SixFour/Generated/LatticeContract.swift:17` (counts `:45,48`) | the size/region vocabulary of every owner |
| `SixFourLattice.selfCheck()` | runtime re-assert of all geometry invariants | `LatticeContract.swift:63` | proves the lattice is internally consistent |
| `GridLayoutContract.captureScene` | the shipped cover: preview(widget0) + palette(widget1) | `GridLayoutContract.swift:29` | the actual ownership map for the live scene (2 owners) |
| `overlaps(_:_:)` | AABB contention test | `GridLayoutContract.swift:40` | detects a cell that would be owned twice |
| `isDisjoint(_:)` | no two regions overlap | `GridLayoutContract.swift:46` | **the disjoint-cover law** (over placed regions) |
| `selfCheck()` | disjoint + in-bounds + touch-floor + distinct priorities | `GridLayoutContract.swift:57` | full scene-level ownership contract |
| `CellContract.render` (no-blend) | empty↦neutral, single↦verbatim, ≥2↦sentinel | `CellContract.swift:6` | per-cell ownership semantics |
| `CellContract.neutralColor` / `.contestedSentinel` | unowned anchor / loud contention marker | `CellContract.swift:20,22` | identity of UNOWNED / CONTENDED cell |
| `CellContract.golden[]` | empty/clean/contested fixture battery + shimmer | `CellContract.swift:24` | proves no-synthesis + shimmer-is-real-claimant |
| `SixFourCellShapes.ringTickEndpoints` | golden 64-tick gauge geometry (floor, bit-portable) | `SixFour/Generated/CellShapesContract.swift:13` | the RING-GAUGE owner's per-tick cell geometry |
| `lint-grid.sh` LINT-PLACEMENT | placement only via `.place()` on a `GridRegion` | `scripts/lint-grid.sh:59` | enforces ownership-by-claim |
| `lint-grid.sh` LINT-SINGLE-LATTICE | one pitch owner (`GlobalLattice`/`SixFourLattice`) | `scripts/lint-grid.sh:72` | one authority over cell↔point math |
| `lint-grid.sh` LINT-GOLDEN / is_primitive | spec+contract sources exist; names `ContestedCellGridView` the contention surface | `scripts/lint-grid.sh:17,44` | build-time presence of the DSL + the legitimate contention view |
| `s4.sh` + `gate-order.txt` | codegen→verify→native→lint→gen→build | `scripts/s4.sh` (order `scripts/gate-order.txt`) | regenerate contracts, prove laws, then build against them |
| `verify-doc-claims.sh` | greps STATUS.md load-bearing facts | `scripts/verify-doc-claims.sh` | the STATUS-truth gate — **no ownership-map assertion yet** |

---

## 3. Invariants already proven

These laws hold today (Haskell, re-asserted in Swift `selfCheck()` / golden tests):

- **NO-BLEND / no-synthesis.** `render` ∈ {neutral, sentinel, an actual claim} — never a mixture. `lawNoSynthesis` (`CellFiber.hs:218`); Swift `SFCell.render` (`CellAlgebra.swift:51`) gated by `CellContract.golden` (`CellContract.swift:24`).
- **Contested detection is exact & total.** `isContested ⇔ ≥2 claims`, and a contested cell ALWAYS renders to the loud sentinel. `lawContestedDetect`/`lawRenderContested` (`CellFiber.hs:115,159`).
- **Shimmer is a real claimant.** The 20fps shimmer of a contested cell only ever shows a genuine claimant, in canonical ascending (L,a,b) order. `lawShimmerIsClaimant` (`CellFiber.hs:176`; contract `CellContract.swift:8`).
- **Disjoint cover (partial).** No two `captureScene` regions share a cell; `lawSceneDisjoint` (`GridLayout.hs`) = `isDisjoint` (`GridLayoutContract.swift:46`). The algebraic and AABB views agree: `lawDisjointMatchesRects` (`GridLayout.hs:51`).
- **Disjoint ownership ⇒ zero contention.** A grid of claims at pairwise-distinct places has zero contested cells. `lawDisjointNoContest` (`CellGrid.hs:227`).
- **Inherited totality (T9).** Pointwise lift of the total fiber join over the finite total base is total (`CellGrid.hs:206`).
- **Touch responsibility.** Every interactive region clears the 44pt HIG floor; `selfCheck` floorOK (`GridLayoutContract.swift:57`) tied to `44 % gifPx == 0` (`LatticeContract.swift:67`).
- **Geometry self-consistency.** Atom=4, exact horizontal tiling + sub-atom vertical bleed, shutter closure `disc·2+ring·2=16`, wordmark fits preview. `SixFourLattice.selfCheck()` (`LatticeContract.swift:63`).
- **One clock, 20fps pin.** A single `CADisplayLink`, `min=max=preferred=logicRateHz=20` (`SurfaceClock.swift:52`); `PlaybackClock`'s `Timer` deleted.
- **One placement API.** `.place(_:)` is the only sanctioned `.position`; re-basing the atom relays the whole app (`ScreenLattice.swift:22`).
- **Ring-tick portability.** 64 gauge ticks recomputed from sin/cos and asserted byte-equal to the Haskell golden (`CellShapesContract.swift`).

---

## 4. Ownership seeds already in the code

The `color = ownership` model is ~70% latent in existing code:

- **`Owner = Place → Maybe Widget`** — the literal `owner:(x,y)→Owner` map, already typed. `CellGrid.hs:118` (with `Widget` as "THE UNIT OF OWNERSHIP", `CellGrid.hs:111`).
- **`lawDisjointNoContest`** PROVES disjoint ownership ⇒ disjoint cover with zero contention — the "no cell owned twice" invariant, already discharged. `CellGrid.hs:227`.
- **`contestedPlaces` / `sceneContested`** — the field-wide "doubly-claimed cell is a bug made visible" report; well-formed ⇔ empty. `CellGrid.hs:159`, `GridLayout.hs:120`.
- **`contestedSentinel` + `lawRenderContested`** — contention is surfaced as a loud reserved colour, NOT a blend. `CellFiber.hs:159,228`; Swift `CellAlgebra.swift:51`; contract `CellContract.swift:22`.
- **`sceneGrid` is already owner-keyed.** It folds each claim into `Map (Int,Int) Cell` keyed by `lrWidget` as a `Color` — owner identity *literally encoded as a colour*, just internal/unexported and using a widget-id not a real `Owner` enum. `GridLayout.hs:112`.
- **`LRegion.lrWidget` / `GridRegion.widget`** — an explicit per-owner id (preview=0, palette=1) on a proven-disjoint partition; the closest existing thing to an Owner map. `GridLayout.hs:71`, `GridLayoutContract.swift:16`.
- **`LRegion.lrInteractive` + `lawPriorityDistinct`** — a per-owner responsibility flag (touch duty) + deterministic tiebreak so a (proven-impossible) collision still has a single winner, never a blend. `GridLayout.hs:73`, `GridLayout.hs:158`.
- **`captureScene`** names the two real owners `"preview"` and `"palette"` with their concrete regions — the 2-owner seed of the full cover. `GridLayout.hs:88`, `GridLayoutContract.swift:29`.
- **`EffectZone` + `shimmerAt` + `renderGridAt`@20fps** — the sanctioned-overlap-vs-bug distinction and the 20fps refresh are already wired into the observer. `CellGrid.hs:123,173`.
- **Per-widget cell counts** pin each owner's responsibility-region SIZE: `previewCells=64` (frames), `ringTicks=64` (one tick per frame), `shutterCells=16`, `controlCells=12`. `LatticeContract.swift:45-53` ≡ `Lattice.hs:170,185,192,196`. `gridSide=16` (`GridAxis.hs:97`) == `shutterCells=16` — the palette owner is dimensionally consistent across modules.
- **`lint-grid.sh`** already reifies contention as a first-class UI surface (names `ContestedCellGridView`, `scripts/lint-grid.sh:44`) and enforces placement-by-claim (`:59`).

---

## 5. Gaps blocking `color = ownership`

1. **No total `owner:(x,y)→Owner` function in Swift or in the generated contracts.** `Owner = Place → Maybe Widget` exists in `CellGrid.hs:118` but is **not ported**: `ContestedCellGridView` takes loose `cellAt`/`effectZone` closures with no enforced disjointness or totality (`ContestedCellGridView.swift:25`). `GridLayoutContract` gives `region → widget` but no inverse total map.
2. **The cover is DISJOINT but never proven TOTAL.** `isDisjoint` (`GridLayoutContract.swift:46`) + in-bounds permit unowned/background cells. There is no partition-completeness law that *every* one of the 100×218 cells is owned exactly once.
3. **`captureScene` lists only 2 owners.** The other ≥5 the model names — shutter (fused), gear/settings, background field, ring gauge, wordmark — exist as Lattice atom-counts and chrome masks but have **no `GridRegion`** (`GridLayoutContract.swift:29` vs `LatticeContract.swift:45-53`), so they are absent from the disjoint-cover proof.
4. **`GridRegion.widget` is discarded at render.** `place(_:)` reads `col/row/w/h` only (`ScreenLattice.swift:22`); nothing maps `widget → colour`, and `CellField`/`TintedCheckerField` are tinted by scene data, not by owner identity.
5. **Colour ≠ owner-identity in the live field.** Today colour encodes *scene data* (`σ.palette`); the model wants colour to encode *which owner controls the cell*. This needs a closed `Owner` enum `{Preview, Palette, Shutter, Gear, Background, Ring, Wordmark}` + `ownerColor: Owner → SFColor`, and `render` keyed off it. The two "Color" meanings (`CellFiber.Color` as opaque join key vs `AxisNet`/`GridAxis.IndexedColor` as perception) must be deliberately reconciled.
6. **The no-blend engine is UNWIRED to the Surface.** `SFCell`/`renderCell`/`contestedSentinel` (`CellAlgebra.swift`) implement claim/contested/no-blend, yet no `*PhaseField` imports them — the contention-visible law lives only in `ContestedCellGridView`, not on the live field. The region-level `isDisjoint` build-fail and the per-cell `contestedSentinel` runtime marker are **two separate contention mechanisms with no bridge**.
7. **No `Owner → Responsibility` law.** "PREVIEW owns the 64×64 frames", "PALETTE owns the 16×16 palette" are prose in `DESIGN-MAP.md` and doc-comments, enforced only by which renderer draws where — never a spec law.
8. **Two grid worlds not unified.** The 64×64 GIF field (`CellGrid.Place`, 4096 cells) and the 100×218 screen lattice (`GridLayout`, where the disjoint proof lives) are different bases with separate contention proofs; the ownership map needs a decision on which base it covers.
9. **No 20fps refresh law at the ownership-map level.** `CellContract` documents the 20fps shimmer of a *single* contested cell, but no contract states the *whole* owner-map over 100×218 is re-evaluated as one SIMD pass at 20fps.
10. **`verify-doc-claims.sh` has ZERO ownership assertions** (no `isDisjoint`/`captureScene`/`contestedSentinel` check, `scripts/verify-doc-claims.sh`) — a regression in the disjoint-cover or no-blend law would not be caught by the STATUS gate.
11. **DOC DRIFT to fix.** `STATUS.md:81,91` lists `Spec.Lattice` Cardinal-Law enforcement as `[PLANNED]/unbuilt`, and `DESIGN-LANGUAGE.md` is v2.0/6pt — yet `LatticeContract.swift`/`GridLayoutContract.swift` are live, codegen'd, law-bearing, and lint-required, and the authoritative atom is 4pt (`TOTAL-PIXELATION.md` + `LatticeContract.swift:17`). The ledger denies the substrate the ownership map builds on. (`GlobalLattice.swift` prose comments are likewise stale: 6pt/201×437 vs live 4pt/100×218.)

---

*The DSL already proves the hard half — disjointness, no-blend, totality of the observer, one clock, one atom, one placement API. The remaining work is to instantiate `Owner`, make the cover total over a single chosen base, bind colour to owner-identity, and wire the latent `CellAlgebra` engine into the live Surface so that contention is a runtime sentinel, not just a build-time `isDisjoint` failure.*

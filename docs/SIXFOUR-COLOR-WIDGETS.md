# SixFour — Movable Color Widgets (authoritative design)

> Status: DESIGN (this doc is the contract). Source of truth is Haskell
> (`spec/src/SixFour/Spec/MovableLayout.hs`); the Swift mirror is generated
> (`SixFour/Generated/MoveContract.swift`) and never hand-edited. Gated by
> `cabal test` + the project.yml drift gate + `scripts/lint-grid.sh`.

## 1. The thesis

A **ColorWidget** is a widget whose cells are a **projection of the ONE color
cube** (the 64³ index cube + palette). **Movability is a property of being a
ColorWidget** — not a runtime flag. Chrome (build stamp, gear, action row, the
heartbeat checker ground, the determinism badge) is *not* a ColorWidget, so it
is **immovable by construction**: there is simply no placement state for it.

There are exactly **three** color identities — the closed, movable set:

| Identity        | Cells   | Pt     | Data projection of the cube                              | Interactive |
|-----------------|---------|--------|---------------------------------------------------------|-------------|
| `Field64`       | 64×64   | 256    | preview (live, quantized) ≡ gif-render (review) — ONE id | no          |
| `Palette16`     | 16×16   | 64     | the 256-colour palette ≡ the capture shutter            | yes (shutter) |
| `DiversityRing` | 20×20   | 80     | per-frame palette diversity gauge (re-introduced)       | no          |

The cube is the only state; these three are different Haar projections of it.
The DATA each shows is phase-specific (live tile / index cube / per-frame
palette), but the **identity, footprint, and POSITION are constant across all
phases**. One user-set position per identity, global, phase-independent.

## 2. Synthesis decisions (how the three candidates were resolved)

This design takes the **strongest law set** (Candidate 1/3: 8 laws including the
exhaustiveness/classification law), the **reuse discipline** (Candidate 2: do
NOT reinvent geometry — `move` is closed over the *existing*
`GridLayout.lawSceneDisjoint` / `regionsOverlap`; the Swift mirror reuses
`GridLayoutContract.isDisjoint`), and the **interaction quality** (Candidate 3:
clamp-along-the-edge for feel, live valid/invalid cell feedback, snap-back via
`@GestureState` auto-reset).

Explicit conflict resolutions:

- **Typeclass vs. plain scene rows.** Candidate 2 argued a typeclass is
  over-engineering. We KEEP a small closed typeclass, because the prompt
  requires classification to be Haskell-first and because the closed
  `ColorIdentity` enum is *exactly* what makes "chrome is immovable" a theorem
  (`lawClassExhaustive`) rather than a convention. But the class is **thin**:
  it supplies only footprint / default dock / interactivity / id / priority —
  all *imported from `Spec.Lattice`*, never free literals — and the move algebra
  is ONE total operator over all identities (Candidate 2's correct insight that
  the operator does not vary per identity).

- **Snap model.** Candidate 1/3 put `snap = id` on atoms (rounding lives at the
  Swift boundary). Candidate 2 put an integer-floor `snapToAtom` in the spec and
  proved it idempotent. We adopt **Candidate 2's explicit `snapToAtom` in the
  spec** so idempotence is a real, non-trivial theorem (`lawSnapIdempotent`),
  and the Swift mirror calls the generated `snapToAtom` — no hand-rolled
  rounding that could drift.

- **Clamp behavior.** Candidate 3's clamp-along-the-edge (clamp BEFORE the
  disjoint test) wins on feel: dragging past the screen edge slides along it
  instead of rejecting. Clamp-first also makes `lawMoveInBounds` hold for both
  accepted and rejected results.

- **Review placement.** All three flagged that Review currently uses
  VStack-centering, not `.place()`. We resolve the asymmetry the same way:
  convert Review's `gifaHero`/`paletteStrip` to `ZStack(alignment:.topLeading)`
  + `.place(region(for:at:))`, so ALL phases honor the one shared `Placement`.
  The determinism badge + action row stay VStack/overlay-pinned chrome.

- **Lint concession.** The transient drag-follow needs ONE `.offset` (live touch
  point, not layout). We do NOT whitelist the whole file; we tag that single
  line `// LINT-ALLOW-POSITION` (the lint matches per-line, see
  `scripts/lint-grid.sh:63`). At rest, position is ALWAYS via `.place()`.

## 3. The ColorWidget typeclass (Haskell-first)

New module `spec/src/SixFour/Spec/MovableLayout.hs`, depending on (not
duplicating) `Spec.GridLayout` and `Spec.Lattice`.

```haskell
-- The closed alphabet of color identities — the ONLY movable widgets. Chrome is
-- not in this type, so chrome is immovable BY CONSTRUCTION.
data ColorIdentity = Field64 | Palette16 | DiversityRing
  deriving (Eq, Ord, Enum, Bounded, Show)

allIdentities :: [ColorIdentity]
allIdentities = [minBound .. maxBound]

-- A ColorWidget IS a projection of the one cube with a fixed cell footprint.
-- Every member supplies its footprint, default dock, interactivity, owner id,
-- and priority — all sourced from Spec.Lattice, never free literals.
class ColorWidget w where
  cwFootprint   :: w -> (Int, Int)   -- (side, side) in cells
  cwDefaultCol  :: w -> Int
  cwDefaultRow  :: w -> Int
  cwInteractive :: w -> Bool
  cwWidgetId    :: w -> Int
  cwPriority    :: w -> Int

instance ColorWidget ColorIdentity where
  cwFootprint   Field64       = (previewCells, previewCells)   -- (64,64)
  cwFootprint   Palette16     = (shutterCells, shutterCells)   -- (16,16)
  cwFootprint   DiversityRing = (ringCells,    ringCells)      -- (20,20)
  cwDefaultCol  Field64       = 18   -- == GridLayout preview dock
  cwDefaultRow  Field64       = 22
  cwDefaultCol  Palette16     = 42   -- == GridLayout palette dock
  cwDefaultRow  Palette16     = 145
  cwDefaultCol  DiversityRing = 40   -- thumb band, disjoint from preview+palette
  cwDefaultRow  DiversityRing = 170  -- 170·4=680 ≥ 62 top; (170+20)·4=760 ≤ 840 bottom
  cwInteractive Palette16     = True
  cwInteractive _             = False
  cwWidgetId                  = fromEnum
  cwPriority                  = fromEnum
```

`Field64`/`Palette16` defaults are the *same* docks `GridLayout.captureScene`
already proves; `DiversityRing` is the new dock proven disjoint by
`lawDefaultsDisjoint`.

## 4. The one-shared-layout model

```haskell
-- The WHOLE movable state: three positions, global, phase-independent.
type Placement = Map ColorIdentity (Int, Int)   -- identity -> (col,row) in atoms

defaultPlacement :: Placement
defaultPlacement = Map.fromList
  [ (i, (cwDefaultCol i, cwDefaultRow i)) | i <- allIdentities ]

-- Turn one placement entry into a GridLayout region (reuses the proven struct).
placedRegion :: ColorIdentity -> (Int,Int) -> LRegion
placedRegion i (c,r) =
  let (w,h) = cwFootprint i
  in LRegion { lrCol=c, lrRow=r, lrW=w, lrH=h
             , lrWidget=cwWidgetId i, lrPriority=cwPriority i
             , lrInteractive=cwInteractive i }

-- The Scene a placement induces — reuses Spec.GridLayout's disjoint algebra.
placementScene :: Placement -> Scene
placementScene p =
  [ (show i, placedRegion i pos) | (i,pos) <- Map.toList p ]
```

"One shared layout across all phases" is formal: there is **no per-phase
position**, only `Placement`; each phase's Π reads the SAME three entries.
`Field64`'s single position serves preview AND gif-render because the cube
readers (`Surface.cellGlobal` / `gifCell`) are pure `(x,y,t)` projections and
`place(region)` is purely geometric — neither depends on phase.

## 5. The move operator (the proof)

```haskell
-- Snap a signed point delta to whole atoms (toward origin); idempotent on multiples.
snapToAtom :: Int -> Int -> Int
snapToAtom atom px = (px `quot` atom) * atom

-- Clamp a placement so its whole footprint stays inside the 100×218 lattice.
clampInBounds :: ColorIdentity -> (Int,Int) -> (Int,Int)
clampInBounds i (c,r) =
  let (w,h) = cwFootprint i
  in ( max 0 (min c (cols - w)), max 0 (min r (rows - h)) )

-- THE MOVE OPERATOR. Move identity i by a CELL delta d:
--   1. clamp the result so the footprint is fully in-bounds (clamp-first = slide
--      along the edge, better feel + makes in-bounds hold on reject too);
--   2. ACCEPT iff the resulting Scene is disjoint (reuse lawSceneDisjoint);
--   3. else SNAP BACK (return the input Placement unchanged).
-- Total; the in-bounds clamp happens BEFORE the disjoint test, so an accepted
-- move is always BOTH in-bounds AND disjoint.
move :: Placement -> ColorIdentity -> (Int,Int) -> Placement
move p i (dc,dr) =
  case Map.lookup i p of
    Nothing      -> p
    Just (c0,r0) ->
      let cand = clampInBounds i (c0+dc, r0+dr)
          p'   = Map.insert i cand p
      in if lawSceneDisjoint (placementScene p') then p' else p
```

The Swift mirror (`MoveContract.move`) is byte-identical and reuses
`GridLayoutContract.isDisjoint` for the acceptance test — Swift adds NO geometry
authority. (Swift converts a point translation to a cell delta via the generated
`snapToAtom(_:atom:) / gifPx` before calling `move`.)

## 6. The laws (golden-pinned, `Properties.MovableLayout`)

1. **lawClassExhaustive** — every `ColorIdentity` in `[minBound..maxBound]` has
   an in-bounds default footprint and (if interactive) clears the 11-cell touch
   floor; the three defaults form a disjoint `placementScene`. Pins "movability
   = being a ColorWidget".
2. **lawMovePreservesDisjoint** (disjoint-preservation, the keystone) —
   `∀ p i d. lawSceneDisjoint (placementScene p) ⇒ lawSceneDisjoint
   (placementScene (move p i d))`. Accept keeps it disjoint by the guard; reject
   returns `p` unchanged. QuickChecked over arbitrary deltas.
3. **lawMoveInBounds** (bounds clamp) — every region of `move p i d` is fully
   inside 100×218 (clamp runs before the accept test; reject returns the
   already-in-bounds `p`).
4. **lawSnapIdempotent** — `snapToAtom a (snapToAtom a px) == snapToAtom a px`
   for all `px`, `a>0`; and `clampInBounds i . clampInBounds i == clampInBounds i`.
5. **lawMoveAtomAligned** — the result col/row of any move is an exact integer
   atom (no sub-atom drift) ⇒ crisp cell rendering.
6. **lawDefaultsDisjoint** — `placementScene defaultPlacement` re-passes ALL the
   existing GridLayout laws (disjoint, in-bounds, interactive touch-floor, safe
   area, distinct priorities); proves the new 3-widget seed ships valid and that
   `DiversityRing`'s dock does not collide.
7. **lawRejectIsIdentity** — a contested clamped move returns the *literal* prior
   `Placement` (`move p i d == p`); golden-pinned with a witness delta that
   drives `Palette16` onto `Field64` (snap-back is exact, no partial move).
8. **lawMoveOnlyTouchesTarget** — `move p i d` agrees with `p` on every identity
   `≠ i` (a move never perturbs the other two widgets).

**Golden pin — `goldenMoveTrace`:** start from `defaultPlacement`, apply a fixed
script `[(DiversityRing,+(10,0)) accept; (Palette16,+(0,-100)) reject→snap-back;
(Field64,+(20,0)) accept-or-clamp]`, and pin the resulting `Placement` as a
Swift literal `MoveContract.goldenAfter`. `Properties.MovableLayout` folds the
Haskell `move` over the script and asserts equality with the literal; a Swift
parity test (folded in `Surface.assertSpecParity`, DEBUG) re-folds the generated
`move` and compares to the SAME literal — cross-language bit-pin of the operator,
exactly as `Surface.assertSpecParity` already folds the Display golden trace.

## 7. The gesture

ONE `.movable(_ identity:, settings:, surface:)` ViewModifier shared by all three
identities (chrome never applies it). Composition:

```
LongPressGesture(minimumDuration: 0.3)
  .sequenced(before: DragGesture(minimumDistance: GlobalLattice.gif(1)))   // 1 cell = 4 pt
```

- `@GestureState private var drag: CGSize = .zero` — transient lift offset; auto-
  resets to `.zero` on end, so a rejected move visibly **snaps back** with no
  extra state. The lifted widget renders at its placed region `+ .offset(drag)`,
  tagged `// LINT-ALLOW-POSITION` (the one live-touch exception).
- `.onEnded`: convert the pt-translation to a cell delta via
  `MoveContract.snapToAtom(Int(t.width), atom: gifPx) / gifPx` (same for height),
  build the current scene from `settings.widgetPlacement`, call
  `MoveContract.move`, and write the result to `AppSettings` only if accepted;
  else do nothing (snap-back).
- Live feedback while lifted: a valid/invalid cell footprint outline drawn as
  `CellSprite`/`CellShapes` (no glass, no `.opacity` except 0) so LINT-DRAW-VOCAB
  passes.

**Shutter integrity (Palette16, the hard case).** Keep the EXISTING
`Button { surface.step(.shutterTap) }` as the OUTERMOST wrapper
(`LivePhaseField.swift:113`); attach `.movable` to the INNER `grid`, NOT the
Button. SwiftUI gesture precedence: once the sequenced LongPress *completes*, the
Button's tap action is suppressed (a lift never fires a burst); a clean tap
(<0.3 s) never enters long-press completion, so `.shutterTap` fires exactly as
today. `minimumDuration: 0.3` guarantees a tap never lifts; `minimumDistance: 1
cell` means sub-atom jitter during a tap-hold never starts a drag. Gate the
shutter's movability on `surface.phase == .live` so a burst-in-progress palette
is inert. `Field64`/`DiversityRing` have no tap action, so they take `.movable`
directly: long-press lifts, drag moves, release snaps; a plain tap does nothing
(correct). `lawRejectIsIdentity` + a unit test ("long-press-release ⇒ zero
`.shutterTap`; fast tap ⇒ exactly one") back this in code.

## 8. Persistence (AppSettings, injectable suite preserved)

Three versioned keys + three stored properties + three init reads, following the
existing `didSet → defaults.set` / init-read pattern verbatim. Encode each
position as a human-readable `"col,row"` String.

```swift
// Key enum (after debugOwnershipOverlay):
static let field64Position       = "sixfour.field64Position.v1"
static let palette16Position     = "sixfour.palette16Position.v1"
static let diversityRingPosition = "sixfour.diversityRingPosition.v1"
```

A tiny `struct GridPoint: Equatable { var col: Int; var row: Int }` is the stored
type (cleaner than a tuple for `@Observable`/round-trip tests). Expose ONE
computed facade `var widgetPlacement: [ColorIdentity: GridPoint]` (read/write)
backed by the three stored properties so callers use the SAME `Placement` shape
the spec uses.

Defaults come from the generated contract, NOT hand-typed literals:
`MoveContract.defaultCol(_:)/defaultRow(_:)` (emitted from the typeclass), so the
seed positions cannot drift from the spec. `init` parses each key with a
`parsePosition(stored, defaultCol:, defaultRow:)` helper; absent/garbage → spec
default (the existing fallback discipline).

**Defense-in-depth:** on load, re-validate the parsed `Placement` through
`MoveContract.placementScene` + `isDisjoint`; if a corrupted store encodes an
overlapping scene, fall back to `defaultPlacement` — a corrupt store can never
produce an overlapping live layout. Tests inject
`AppSettings(defaults: UserDefaults(suiteName:))`, assert round-trip, and assert
an overlapping persisted position is rejected on load (inductive invariant:
default is disjoint; every *accepted* move preserves disjointness).

## 9. The Swift mirror + wiring

New file `SixFour/UI/MovableColorWidget.swift`:

```swift
enum ColorIdentity: Int, CaseIterable { case field64 = 0, palette16, diversityRing }

protocol ColorWidget {                          // mirror of the Haskell class
    var identity: ColorIdentity { get }
    static var footprint: (w: Int, h: Int) { get }   // from generated MoveContract
    static var interactive: Bool { get }
}
```

- The generated `MoveContract.swift` supplies `footprint(_:)`,
  `defaultCol/Row(_:)`, `interactive(_:)`, `priority(_:)`, `snapToAtom(_:atom:)`,
  `clampInBounds(_:_:_:)`, `placementScene(_:)`, `move(_:_:dCol:dRow:)`,
  `selfCheck()`, and `goldenAfter`.
- `region(for: identity, at: placement) -> GridRegion` builds a `GridRegion`
  (the struct `GridLayoutContract` emits) from footprint + the live position, fed
  straight to the existing `place(_ region:)` — zero new placement math, no new
  sanctioned `.position` site.
- `.movable(_:settings:surface:)` carries the gesture + live valid/invalid cell
  overlay + snap/persist.

Wiring the ONE shared position into every phase (each phase reads the SAME
`settings.widgetPlacement`):

- **LivePhaseField:** `previewHero.place(region(for:.field64,at:placement))
  .movable(.field64,…)`; `paletteShutter` Button stays outer, inner grid gets
  `.place(region(for:.palette16,…)).movable(.palette16,…)`; add a new
  `diversityRing` (CellRing fed by a σ diversity metric)
  `.place(region(for:.diversityRing,…)).movable(.diversityRing,…)`.
- **RenderingPhaseField:** `resolveHero` → `region(for:.field64,…)` + `.movable`;
  add the ring (palette not shown here, by current design).
- **ReviewPhaseField:** convert the VStack-centered `gifaHero`/`paletteStrip` to
  `ZStack(alignment:.topLeading)` + `.place(region(for:…))` + `.movable` for all
  three; keep `determinismBadge` + `actionRow` as immovable bottom chrome.
- `@Bindable var settings` makes the `@Observable` placement drive re-layout
  automatically, so moving a widget in `.live` persists and is visible in
  `.review` — one global position across phases.

**DiversityRing gauge source:** a pure `Surface` reader (no new state, rides the
existing κ heartbeat) returning a normalized diversity metric of the cursor
frame's palette (LAB spread / significance-fill fraction of
`palettesPerFrame[cursor]`). First wire may be `palettesPerFrame[cursor].count /
256`; refine to true LAB coverage later.

## 10. File-by-file build order

### Phase A — Spec (Haskell source of truth) — gate: `cabal build && cabal test`
1. **NEW `spec/src/SixFour/Spec/MovableLayout.hs`** — `ColorIdentity` (closed
   enum), `ColorWidget` class + instance (footprints/defaults imported from
   `Spec.Lattice`), `Placement`, `defaultPlacement`, `placedRegion`,
   `placementScene` (reuses `Spec.GridLayout.LRegion` + `lawSceneDisjoint`),
   `snapToAtom`, `clampInBounds`, `move`; the 8 laws + `goldenMoveTrace`.
2. **EDIT `spec/spec.cabal`** — add `SixFour.Spec.MovableLayout` to
   `exposed-modules`; add `Properties.MovableLayout` to the test `other-modules`.
3. **NEW `spec/test/Properties/MovableLayout.hs`** — `once`-wrapped properties
   for all 8 laws on `defaultPlacement` + the golden trace; real QuickCheck
   generators for `lawMovePreservesDisjoint` / `lawMoveInBounds` /
   `lawMoveOnlyTouchesTarget` over arbitrary placements + deltas.
4. **EDIT `spec/test/Spec.hs`** — `import qualified Properties.MovableLayout`;
   register `MovableLayout.tests` (mirror the `GridLayout.tests` registration).
5. **Run `cabal test`** — all existing 584 + the new MovableLayout tests green.

### Phase B — Codegen — gate: `cabal run spec-codegen` (writes `MoveContract.swift`)
6. **EDIT `spec/src/SixFour/Codegen/Swift.hs`** — add `emitMoveContract :: Text`
   (mirror `emitGridLayoutContract` structure): emit `ColorIdentity` ints,
   footprint/default/interactive/priority tables, `snapToAtom`, `clampInBounds`,
   `placementScene`, `move` (reusing `GridLayoutContract.isDisjoint`),
   `selfCheck()`, and the `goldenAfter` literal.
7. **EDIT `spec/app/Spec.hs`** — import `emitMoveContract`; add
   `writeUtf8 (swiftOutDir </> "MoveContract.swift") emitMoveContract`
   (mirror the `GridLayoutContract.swift` write at line 76).
8. **Run `cabal run spec-codegen`** — emits `SixFour/Generated/MoveContract.swift`
   (GENERATED — never hand-edit; the project.yml drift gate auto-covers it).

### Phase C — Swift (Tier-2 app) — gate: `xcodegen generate` + `xcodebuild`
9. **EDIT `SixFour/Settings/AppSettings.swift`** — 3 Key entries; `struct
   GridPoint`; 3 stored properties (`didSet → "col,row"`); the
   `widgetPlacement` facade; init parse with `MoveContract.default*` fallback +
   re-validation through `MoveContract.placementScene`/`isDisjoint`.
10. **NEW `SixFour/UI/MovableColorWidget.swift`** — `ColorIdentity`, `ColorWidget`
    protocol, `region(for:at:)`, the `.movable(_:settings:surface:)` modifier
    (LongPress.sequenced(before: Drag), `@GestureState`, snap via
    `MoveContract.snapToAtom`, `MoveContract.move`, persist/snap-back, valid/
    invalid cell overlay). The single `.offset(drag)` line tagged
    `// LINT-ALLOW-POSITION`.
11. **EDIT `SixFour/UI/Components/CellSprite.swift`** (or a small new view) — wrap
    `CellRing` into a `DiversityRing` view fed by the σ diversity metric.
12. **EDIT `SixFour/UI/Surface/Surface.swift`** — add a pure diversity-metric
    reader for the ring gauge (no new state); extend `assertSpecParity()` to fold
    the `MoveContract.goldenAfter` parity in DEBUG.
13. **EDIT `SixFour/UI/Surface/LivePhaseField.swift`** — replace
    `.place("preview")`/`.place("palette")` with `.place(region(for:at:))` +
    `.movable`; keep the shutter Button outer, gesture on the inner grid; add the
    DiversityRing.
14. **EDIT `SixFour/UI/Surface/RenderingPhaseField.swift`** — `resolveHero` via
    `region(for:.field64,at:)` + `.movable`; add DiversityRing.
15. **EDIT `SixFour/UI/Surface/ReviewPhaseField.swift`** — convert VStack-centered
    `gifaHero`/`paletteStrip` to `ZStack(.topLeading)` + `.place(region(for:…))`
    + `.movable` for all three; keep determinism badge + action row as immovable
    chrome.
16. **EDIT `SixFour/UI/Surface/SurfaceView.swift`** (if needed) — ensure each
    phase field receives `settings` (`surface.settings`) and `@Bindable`.
17. **Run `xcodegen generate`** (two new Swift files added: MovableColorWidget.swift
    + Generated/MoveContract.swift) then `xcodebuild … build` — passes the
    pre-build drift gate + `scripts/lint-grid.sh`.

### Phase D — Docs / gate
18. **EDIT `docs/STATUS.md`** — add a BUILT line: three movable ColorWidgets
    (Field64/Palette16/DiversityRing) share one global `Placement`; `move` proven
    disjoint+in-bounds+idempotent in `Spec.MovableLayout`, golden-pinned in
    `MoveContract`; DiversityRing re-introduced.
19. **EDIT `scripts/verify-doc-claims.sh`** — gate the new load-bearing fact
    (grep `MoveContract.move` + `Properties.MovableLayout` registered + the three
    `*Position.v1` AppSettings keys present).

## 11. Risks & mitigations

1. **Long-press swallows the shutter tap** → gesture on the INNER grid, not the
   Button; sequenced LongPress(0.3)→Drag; `lawRejectIsIdentity` + a unit test
   prove tap vs. lift behavior.
2. **Review was composition-centered, not placed** → convert to
   `ZStack(.topLeading)` + `.place(region(for:…))`; `lawDefaultsDisjoint`
   re-passes every GridLayout law on the 3-widget scene.
3. **Corrupted defaults encode an overlapping scene** → re-validate on load
   through `MoveContract`, fall back to `defaultPlacement`.
4. **Swift `move` drifts from spec** → emit `move`/`clamp`/`placementScene` from
   Codegen (never hand-written) + `goldenAfter` parity folded in
   `assertSpecParity`.
5. **Lint rejects the drag offset** → confine the only `.offset` to the lifted-
   overlay live-touch path with `// LINT-ALLOW-POSITION` (per-line, no file
   whitelist); rest position always via `.place()`.
6. **DiversityRing gauge source undefined** → pure σ-derived metric of the cursor
   frame's palette; no new state, rides the κ heartbeat.
7. **Tight travel (Field64 has only 36 free cols)** → `clampInBounds` guarantees
   in-bounds and `move` rejects collisions; worst case is a snap-back, never a
   broken layout (proven by `lawMoveInBounds` + `lawMovePreservesDisjoint`).

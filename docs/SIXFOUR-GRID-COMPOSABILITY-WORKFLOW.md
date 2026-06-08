# SIXFOUR Grid Composability — Widget Plug-in Workflow

**Status:** design (2026-06-08). **Scope:** how to plug NEW movable widgets into the
cell-grid UI without losing the proven-disjoint, golden-pinned, zero-dep guarantees;
the Elm/TEA verdict for placement state; the per-frame/global palette widget + the GIFC
compressed rung; and the green-frame-follow bug.

Companion to **`docs/SIXFOUR-GRID-DSL-STUDY.md`** (the orientation map: tiers, the
`owner:(x,y)→Owner` totality gap §5). This doc does NOT re-derive the DSL — it specifies
the *composability seam* the study calls "the open work."

---

## 1. Current framework — what the cell-grid actually is today

The whole screen is ONE field of 4pt atoms (`gifPx = 4`, `Spec/Lattice.hs:107`;
`SixFourLattice` `LatticeContract.swift:17`), 100 cols × 218 rows. Every element is a
**rectangular claim** on that field rendered through a no-blend cell algebra. Four pieces
hold it together:

1. **Placement primitive.** `View.place(GridRegion)` (`SixFour/UI/ScreenLattice.swift:22`)
   is the ONE sanctioned placement API — it frames to `region.w·atom × region.h·atom` and
   `.position`s at the region midpoint. `lint-grid.sh:59` (LINT-PLACEMENT) forbids any
   other `.position`. A `GridRegion` is `{name,col,row,w,h,widget,priority,interactive}`
   (`Generated/GridLayoutContract.swift:10`).

2. **Closed movable alphabet.** `ColorIdentity` is a generated, golden-pinned closed enum
   `{field64=0, palette16=1, diversityRing=2}` (`Generated/MoveContract.swift:16`). Chrome
   (gear, wordmark, stamp) has NO identity → immovable by construction (`lawClassExhaustive`).
   Per-identity geometry is six switch-emitted functions: `footprint`/`defaultCol`/
   `defaultRow`/`interactive`/`widgetId`/`priority` (`MoveContract.swift:27–66`), all
   fanned out from `Spec/MovableLayout.hs`'s `ColorWidget` typeclass over `allIdentities`.

3. **The disjoint PROOF.** `Spec/GridLayout.hs` is the golden algebra: `captureScene`
   (`GridLayout.hs:88`) is proven disjoint + in-bounds + interactive-floor-safe by
   `cabal test` (`lawSceneDisjoint`, `lawInteractiveTouchFloor`, `lawSafeAreaClearance`).
   The move operator `MoveContract.move(placement,id,dCol,dRow)` (`MoveContract.swift`,
   mirrors `MovableLayout.hs:170–186`) clamps-in-bounds then accepts iff the induced scene
   is disjoint (`GridLayoutContract.isDisjoint`), else returns input unchanged (exact
   snap-back). Every accepted move is BOTH in-bounds AND disjoint, proven once in Haskell.

4. **The TEA spine.** `Surface` (`SixFour/UI/Surface/Surface.swift`) is a per-screen
   Elm/TEA machine: **Model** = `phase: SurfacePhase`, `palette`, `indexCube`, `cursor`
   (all integers, no float on the spine); **Msg** = `SurfaceEvent`; **Update** =
   `surfaceStep(phase,event)→phase` (pure, total, no-op default, `.fault→.error`);
   **View** = `PhaseField.field(for:)` dispatch. The FSM is bit-pinned to
   `Spec/Display.hs` via `Surface.assertSpecParity()` re-folding the golden trace.

**Persistence is the weak seam.** Placement lives OUTSIDE the reducer in
`AppSettings.widgetPlacement` (`AppSettings.swift:177`) — a computed `[ColorIdentity:(col,row)]`
assembled from THREE hand-typed properties `field64Position`/`palette16Position`/
`diversityRingPosition` (`AppSettings.swift:159–171`), each with its own `didSet` →
UserDefaults key. A 4th widget today = hand-edits in four spots (key, property, didSet,
init-parse). This is the composability tax.

---

## 2. Elm/TEA verdict — applicable, already adopted, do NOT fold placement wholesale

**Verdict: TEA is already the architecture, and it is the right one.** The phase machine
IS textbook Elm (Model/Msg/Update/View, pure total reducer, golden-pinned trace). Do not
replace it; do not reach for a library (§3).

**How far to extend it to placement:** placement gates NO phase transition — moving the
palette never changes `.live`→`.capturing`. Folding the whole placement MAP into
`SurfacePhase`/`surfaceStep` therefore buys nothing and ADDS observable churn at 20fps. So
keep placement a **sibling store**, consistent with ADR-2 (per-screen FSMs).

**The minimal, justified TEA touch** — exactly two additions, no more:
- A single message `SurfaceEvent.move(ColorIdentity, dCol:Int, dRow:Int)` whose reducer arm
  is `placement = MoveContract.move(placement,id,dCol,dRow)` (pure; geometry stays generated).
- A transient in-flight lift made observable: `var liftedDrag: (id:ColorIdentity, dCol:Int,
  dRow:Int)?` on `Surface` (nil at rest). This is the structural green-frame fix (§7): the
  dragged `.offset` and the green overlay read ONE field, so they cannot diverge.

`SurfacePhase` stays a pure token enum (placement is data, not a phase), so the Display
golden trace is untouched.

---

## 3. Framework suggestions — TCA / external Elm are OFF-CONTRACT

CLAUDE.md Tier-2 rule: the shipped iOS app has **ZERO third-party dependencies** — Apple
frameworks + `simd` only. Therefore:

- **The Composable Architecture (TCA), swift-composable-architecture, any Elm-lib, Redux
  port via SPM** → forbidden in shipped code. Do not add them.
- The PATTERN is hand-rolled and already present: `Surface` (Model) + `SurfaceEvent` (Msg)
  + `surfaceStep` (pure Update) + `PhaseField` (View). Extend that, not a dependency.
- Deps may exist only Tier-0 (`spec/` Haskell) or Tier-1 (`trainer/`). The spec IS the
  "framework": it generates the reducer's contracts and pins them with golden vectors.

Hand-rolled reducer idiom for the new lift state (no library):

```swift
extension Surface {
  func widget(_ msg: WidgetMsg) {       // single mutation point, mirrors `step`
    switch msg {
    case .lift(let id):            liftedDrag = (id, 0, 0)
    case .drag(let id, let dc, let dr): liftedDrag = (id, dc, dr)
    case .drop(let id):
      if let l = liftedDrag, l.id == id {
        widgetPlacement = MoveContract.move(widgetPlacement, id, dCol: l.dCol, dRow: l.dRow)
      }
      liftedDrag = nil
    }
  }
}
```

---

## 4. RECOMMENDED architecture — the generated WIDGET-DESCRIPTOR table

(Judge verdict: **generated-descriptor-table-first**, primary; with the one-observable
green-frame graft from TEA-reducer-first. Robustness retention is the decider — this lens
leaves `move`/`isDisjoint`/`lawDefaultsDisjoint`/`goldenAfter` byte-identical.)

**Idea:** the spec already carries widget data as a ROW-SHAPED `ColorWidget` typeclass over
the closed enum; codegen merely EXPLODES it into six parallel switches
(`Codegen/Swift.hs:1314–1349`, `map …Case ML.allIdentities`). Collapse those into ONE
generated `WidgetDescriptor` table and add two ORTHOGONAL columns — `cwRenderMode` and
`cwPaletteScope` — that describe rendering WITHOUT touching geometry. The enum stays closed;
we widen what each member CARRIES, never who the members ARE. The disjoint proof is untouched.

### 4.1 Spec change (`Spec/MovableLayout.hs`)

```haskell
data RenderMode  = FieldHero | PaletteGrid | DiversityGauge | GifcCompressed
                   deriving (Eq, Ord, Enum, Bounded, Show)
data PaletteScope = PerFrameScope | GlobalScope
                   deriving (Eq, Ord, Enum, Bounded, Show)

class ColorWidget i where
  ...                                  -- existing six methods unchanged
  cwRenderMode   :: i -> RenderMode    -- NEW orthogonal column
  cwPaletteScope :: i -> PaletteScope  -- NEW orthogonal column
```

Existing laws (`lawDefaultsDisjoint`, `lawClassExhaustive`, `lawMovePreservesDisjoint`,
`lawInteractiveTouchFloor`) are UNCHANGED — render mode is orthogonal to geometry, so no
proof weakens. Add one cheap exhaustiveness law:
`lawRenderModeTotal = all (\i -> cwRenderMode i ∈ [minBound..maxBound]) allIdentities`.

### 4.2 Codegen change (`Codegen/Swift.hs emitMoveContract`)

Replace the six `++ map …Case ML.allIdentities` blocks (`Swift.hs:1314–1349`) with ONE
emitter printing a `WidgetDescriptor` struct + a `descriptors: [ColorIdentity:
WidgetDescriptor]` literal + the `RenderMode`/`PaletteScope` enums. Keep `footprint(_:)`
etc. as `descriptors[i]!.w` SHIMS for call-site compat. `goldenScript`/`goldenAfter`
re-emit byte-identical (render mode never touches `move`), so `assertSpecParity` keeps
passing with NO new vector unless a new IDENTITY shifts `defaultPlacement`.

### 4.3 Swift consumption

- **Persistence collapses.** Replace the three hand-typed position properties with ONE
  store whose getter/setter loop `ColorIdentity.allCases`, reading/writing
  `defaults.set(_, forKey: "sixfour.widget.\(i.rawValue)")`. A new case auto-persists.
  (One-time migration: read the three old keys once, write the new map — else existing
  installs reset to defaults, masked as "corrupt store".)
- **`WidgetView(identity, surface, settings)`** switches on `descriptors[id]!.renderMode`
  to pick the CellSprite/PixelGrid closure. A render-mode-REUSING widget needs no new arm.
- **Defensive grafts (from protocol-registry lens):** a debug `selfCheck` asserting the
  `descriptors` table covers `ColorIdentity.allCases` (kills the phase-field-forgets-a-widget
  silent gap), and a registration-time assertion that a render mode's declared footprint
  `== MoveContract.footprint(id)`.

### 4.4 Exact flow

```
Spec/MovableLayout.hs  (add row + 2 columns)
   │  cabal test           ← PROOF GATE (lawDefaultsDisjoint etc.) — blocks Swift build
   ▼
cabal run spec-codegen     ← regenerates Generated/MoveContract.swift (descriptors table)
   │
   ▼
AppSettings (allCases loop) + WidgetView (arm if new shape) + PhaseField (1 line)
```

This is the §5 "color = ownership" totality from `SIXFOUR-GRID-DSL-STUDY.md` advanced one
notch: the descriptor table is the row-keyed owner record the study's `LRegion`/`Widget`
gestured at, now carrying render identity too.

---

## 5. Plug-in recipe — add a NEW movable widget

Net cost for a render-mode-REUSING widget: **1 Haskell row + codegen + 1 line per phase.**

1. **Spec** (`Spec/MovableLayout.hs`): add the enum case to `data ColorIdentity` (auto-joins
   `allIdentities = [minBound..maxBound]`). Add ONE row to each `ColorWidget` method incl.
   the two new columns:
   ```haskell
   cwFootprint   MyWidget = (16,16)
   cwDefaultCol  MyWidget = 4          -- a dock DISJOINT from field64@(18,22),
   cwDefaultRow  MyWidget = 40         --   palette16@(42,145), diversityRing@(40,170)
   cwInteractive MyWidget = False
   cwRenderMode  MyWidget = PaletteGrid
   cwPaletteScope MyWidget = GlobalScope
   ```
2. **Prove**: `cd spec && cabal test` — must pass `lawDefaultsDisjoint` / `lawClassExhaustive`
   / `lawInteractiveTouchFloor`. This is the gate; the Swift build is blocked behind green.
3. **Regen**: `cabal run spec-codegen` → `Generated/MoveContract.swift` regenerates the
   descriptors table + enum case.
4. **Persistence**: NONE. The `allCases` loop auto-persists the new key.
5. **Render**: if `renderMode` reuses an existing arm (`PaletteGrid`/`FieldHero`/
   `GifcCompressed`), nothing. Else add ONE `case` to `WidgetView`.
6. **View wiring** (the one irreducible per-widget hand-edit — a widget's pixels are bespoke):
   in the owning `*PhaseField`:
   ```swift
   WidgetView(.myWidget, surface: surface, settings: settings)
     .place(region(for: .myWidget, at: surface.widgetPlacement))
     .movable(.myWidget, settings: settings, surface: surface)
   ```
7. **Gate**: `scripts/s4.sh all` (runs codegen→verify→native→lint→gen→build in dependency
   order, `scripts/gate-order.txt`).

---

## 6. The two concrete widgets

### 6a. 16×16 palette widget — per-frame AND global, ONE identity

Do NOT add a second identity for the two modes — that forces a redundant second proven
region over the SAME cells. Instead the single `palette16` widget reads the EXISTING
`AppSettings.paletteScope: PaletteScope {perFrame|global}` (`AppSettings.swift:120`,
default `.perFrame`) at RENDER time:

```swift
// WidgetView `PaletteGrid` arm:
let colors = settings.paletteScope == .global
  ? surface.palette                      // the single committed GIFB table (AppSettings.swift … Surface.palette:140)
  : surface.palettesPerFrame[surface.cursor]  // 256 colours, frame-synced via PlaybackClock (Surface.swift:146,161)
PixelGrid(cells: 16, origin: .bottomLeft) { r, c in
  // SAME GridLayout.layoutN(side:16, x:axisX, y:axisY, colors:) → Order → fill path
}
```

Both feed the IDENTICAL `GridScript.surfaceColors` / `GridLayout.layoutN` pipeline — only
the source array differs. Per-frame vs global is a 2-line `if`, not a new dock, not a new
persisted position, not a re-proof. The scope toggle is an existing `CellSelector`.

### 6b. GIFC 16×16×16 compressed rung — reuse `Export.downsample2D`

GIFC is the compressed ladder rung: `previewSide = sourceSide/upscaleFactor = 64/4 = 16`,
`packSides = [16,64,256]` (`Spec/Export.hs:59–64`). It shares GIFB's GLOBAL palette
(index-domain downsample — no colour invented), so NO new palette state.

1. **Spec**: `Gifc16` case, footprint (16,16), dock e.g. (4,40) disjoint from the three,
   `cwInteractive=False`, `cwRenderMode=GifcCompressed`, `cwPaletteScope=GlobalScope`.
2. **Port `downsample2D`** (`Export.hs:114–134`, mode-lowest tie-break via `modeLowest`
   `:124`) into a NEW `emitExportContract` → `Generated/ExportContract.swift` (~25 lines,
   pure integer, `Ord`-generic). PIN with a golden vector — a fixed 8×8 index input → its
   4×4 mode-downsample, with a tie hitting lowest-index — asserted in `ExportContract.selfCheck`
   (the existing module already has `lawDownsampleConstantBlock`/`lawDownsampleGamutClosed`
   witnesses, `Export.hs:134,141,147`).
3. **Surface accessor** `gifCellCompressed(x,y,t) -> SIMD3<UInt8>?`: take the 4×4 source
   block `indexCube[t*4096 + (y*4+dy)*64 + (x*4+dx)]`, `downsample2D`-mode it to one index,
   look it up through the GLOBAL `palette` (like `cellGlobal` `Surface.swift:199`, NOT
   `gifCell`/`palettesPerFrame` `:214` — GIFC shares GIFB's palette). On-demand is correct
   first; cache as `@ObservationIgnored` lazy invalidated when `indexCube` is set if profiling
   demands it.
4. **Render arm**: `CellSprite(cols:16, rows:16, cellPt: GlobalLattice.gifPx) { c,r in
   surface.gifCellCompressed(c, r, surface.cursor) }`.
5. **Temporal 16-frame rung** — a UI choice the spec does NOT pin (`packSides` is spatial).
   Reuse the ONE PlaybackClock (honoring T2 — no second clock): map the 64-frame cursor to a
   16-frame stride, `t = cursor & 0x3C` (frames 0,4,…,60). Document this in the descriptor
   comment and pin it with a one-line spec note to avoid drift.

---

## 7. Green-frame bug — root cause + minimal fix

**Symptom:** on lift-drag, the green/red drop outline "does not follow" the finger.

**Root cause (confirmed in code).** `MovableColorWidget.swift:84–85` applies `.offset(drag)`
to the content, THEN `.overlay { if lifted { dropOverlay } }`. SwiftUI's `.offset()` moves
a view's VISUAL appearance but NOT its layout frame; `.overlay()` then anchors to the
UNCHANGED layout frame. So as `drag` updates and the widget content slides, the outline
stays pinned at the original un-offset position — it lags. (A second latent divergence: the
overlay RE-COMPUTES `dCol/dRow` from `drag` at a SEPARATE site, `:148–149`, so its accept/reject
can disagree with `commit`'s.)

**Minimal fix.** Apply `.overlay` BEFORE `.offset` so the outline rides the same offset as
the content — they move together, frame-locked.

```swift
func body(content: Content) -> some View {
    guard enabled else { return AnyView(content) }
    let base = content
        .overlay { if lifted { dropOverlay } }   // overlay FIRST — rides the offset with the content
        .offset(drag)                            // LINT-ALLOW-POSITION: transient lift-follow (auto-resets)
        .contentShape(Rectangle())
    // … gesture chain unchanged
}
```

Risk: low — pure modifier reorder; gesture mechanics, `@GestureState` snap-back,
`MoveContract.move` validation, and `.exclusively(before: TapGesture)` precedence are all
unaffected; the overlay is internal-only feedback (no spec parity at risk).

**Structural durability (the §2 + §4 graft).** The reorder fixes the LAG. To also kill the
two-sites-disagree divergence permanently, route the overlay AND the offset through ONE
observable `surface.liftedDrag` (§2): the gesture dispatches the snapped delta into it, both
the `.offset` and `dropOverlay`'s accept/reject color READ it, and the second `dCol/dRow`
computation at `:148–149` is deleted. One source ⇒ they can never diverge. Scope the
observable read to the moved widget's subview so the 20fps drag does not re-render the whole
surface.

---

## 8. Phased implementation plan (spec-first; gate = `scripts/s4.sh all`)

Each phase is spec-first per `docs/SIXFOUR-SPEC-METHODOLOGY.md` (stay Layers 0–2 + golden
vectors; escalate only on pager-on-fire invariants). Gate after every phase.

1. **Phase 1 — Green-frame fix (no spec).** Reorder `.overlay`/`.offset` in
   `MovableColorWidget.swift`. Gate: `s4.sh lint gen build`. Smallest, highest-value, ships
   independently. **Acceptance:** outline tracks finger; red on a rejected drop.

2. **Phase 2 — Observable lift state (TEA graft).** Add `Surface.liftedDrag` +
   `SurfaceEvent.move` + `Surface.widget(_:)` reducer arm (Swift only; `surfaceStep` phase
   table untouched, Display golden unchanged). Route `.movable` to dispatch; delete the
   duplicate overlay computation. Gate: `s4.sh verify build`. **Acceptance:** `assertSpecParity`
   still green; overlay/offset read one field.

3. **Phase 3 — Descriptor table codegen.** Edit `Spec/MovableLayout.hs` (add `RenderMode`/
   `PaletteScope` columns + `lawRenderModeTotal`), rewrite `emitMoveContract` to emit the
   `WidgetDescriptor` table + shims. `cabal test` (goldenAfter byte-identical) → `cabal run
   spec-codegen`. Gate: `s4.sh codegen verify`. **Acceptance:** `MovableLayoutTests` re-assert
   the two new descriptor fields; `goldenAfter` unchanged.

4. **Phase 4 — Persistence collapse + migration.** Replace the three position properties with
   the `allCases`-keyed store; add a one-time read-old-three-keys → write-map migration.
   Add the `descriptors`-covers-`allCases` + footprint-equality debug selfChecks. Gate:
   `s4.sh build`. **Acceptance:** existing installs keep saved positions; new widget needs 0
   AppSettings edits.

5. **Phase 5 — `WidgetView` + palette per-frame/global arm.** Add `WidgetView` switching on
   `renderMode`; the `PaletteGrid` arm reads `settings.paletteScope`. Rewire `LivePhaseField`/
   `ReviewPhaseField` to `WidgetView`. Gate: `s4.sh lint gen build`. **Acceptance:** palette
   toggles per-frame↔global with no second identity.

6. **Phase 6 — GIFC.** Add `Gifc16` row (Phase 3 path), `emitExportContract` for
   `downsample2D` + golden vector, `Surface.gifCellCompressed`, the `GifcCompressed`
   `WidgetView` arm, one `ReviewPhaseField` line. Gate: `s4.sh all`. **Acceptance:** GIFC
   16×16 renders the mode-downsampled global palette, movable + disjoint-proven.

---

## 9. Risks / open questions

- **Observable churn at 20fps.** `liftedDrag` on `@Observable Surface` invalidates each drag
  tick. MUST scope the read to the moved widget's subview (precedent: `@ObservationIgnored`,
  `PlaybackClock.swift:43`) or the whole surface re-renders. Open: confirm SwiftUI scopes the
  invalidation as expected.
- **UserDefaults migration.** Collapsing three position keys into one map risks silently
  resetting users (masked by the disjoint-fallback as "corrupt store"). The read-old-keys
  shim is mandatory and one-shot.
- **GIFC temporal axis is unproven.** `packSides` pins SPATIAL downsample only; "which 16
  frames" (`cursor & 0x3C` stride) is a UI decision needing a one-line spec note to prevent
  drift.
- **View wiring stays bespoke.** The descriptor table makes DATA generic; a widget's PIXELS
  are not. "Plug in with zero Swift edits" is NOT achieved — the one `.place().movable()` line
  per phase is the honest irreducible floor.
- **`cwRenderMode`/`cwPaletteScope` couple geometry spec to rendering.** A purist could split
  them into `Spec.WidgetRender` to keep `MovableLayout` purely geometric. Deferred — folding
  is cheaper and the laws stay orthogonal.
- **Cover still disjoint-not-total** (`SIXFOUR-GRID-DSL-STUDY.md §5`). This doc does not close
  the `owner:(x,y)→Owner` totality gap (background/chrome have atom counts but no `GridRegion`).
  The descriptor table is a step toward it, not the finish.
- **Two scopes simultaneously.** `paletteScope` is a single global setting. If two palette
  widgets ever needed different scopes at once, scope must move from `AppSettings` into
  per-identity state — partially undoing 6a's "one widget, two modes" win.

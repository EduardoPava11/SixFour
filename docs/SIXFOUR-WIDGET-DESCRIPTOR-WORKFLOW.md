# SixFour — Widget-Descriptor Workflow

> Fold geometry + mechanics + render into **ONE generated descriptor table** so
> "add a movable widget" collapses to **one descriptor row + `cabal run
> spec-codegen`** — no scattered switch-emitters, no hand-typed `AppSettings`
> position props. Keep the disjoint PROOF and `goldenAfter` **byte-identical**.

House style: terse, law-citing, `file:line`-grounded, copy-pasteable seams.
Sibling docs: `docs/SIXFOUR-GRID-COMPOSABILITY-WORKFLOW.md` (recommends this
table), `docs/SIXFOUR-CAPTURE-SCREEN-GEOMETRY` / ADR-5, `docs/SIXFOUR-DISPLAY-FSM.md`.

---

## 0. Goal + the 4 locked decisions (2026-06-08)

**Goal.** Today six per-identity switch-emitters in `Codegen/Swift.hs` (footprint
/ defaultCol / defaultRow / interactive / widgetId / priority) PLUS five more
(holdTicks / tickEvery / pulseBasePeriod / pulseBaseLo / pulseBaseHi) emit
eleven parallel `switch i { … }` bodies. Persistence carries **three** hand-typed
`GridPoint` props in `AppSettings.swift`. Adding a widget touches a dozen sites.
Collapse them to **one `WidgetDescriptor` record**, one generated table, and an
`allCases`-keyed JSON store.

**The four LOCKED decisions (honor exactly):**

1. **DETENT FEEL = LAYERED.** `CellTick` (`UISelectionFeedbackGenerator`) on
   EVERY cell boundary crossed while lifted, PLUS an `EdgeStop`
   (`UIImpactFeedbackGenerator(style: .rigid)`) when the drag **clamps at the
   lattice edge** OR steps into a **blocked** (would-reject / red) cell. The
   "click-click of moving cell-to-cell" plus resistance at the wall.
   `mcTickEvery` governs the tick cadence; the new `cellStepBlocked` predicate
   governs `EdgeStop`.

2. **BOUNDARY = STEPPED ROUNDED-RECT.** A 1-cell-thick outline tracing a rounded
   rectangle whose corners are stepped in whole cells to approximate the iPhone
   screen corner radius. Pixel-honest, no anti-aliasing.

3. **DOWNWARD GROWTH = EXPLICIT SECTION HEIGHTS.** Each user-story step declares a
   NAMED section of N cells. The top section is pinned at the safe area; the
   bottom rounded corners move down as sections append. The boundary only ever
   extends downward. *(See §6 + Risk R1: sections **partition** the fixed
   `Lattice.rows`; they do not OVERRIDE it — the critic's blocking correction.)*

4. **ONE DESCRIPTOR ROW** carries footprint`(w,h)`, dock`(col,row)`, interactive,
   widgetId, priority, holdTicks, tickEvery, pulse`(period,lo,hi)`, liftHaptic,
   **renderMode**, **paletteScope**. `renderMode`/`paletteScope` are ORTHOGONAL
   to geometry — they never enter `placedRegion`/`LRegion`, so the move/disjoint
   proof is unaffected.

**Source-of-truth constants (verified, NOT the prompt's sample literals):**
- `Lattice.cols = 402 div 4 = 100`, `Lattice.rows = 874 div 4 = 218`
  (`Lattice.hs:93,106,128-133`; SCREEN-derived — the in-bounds authority).
- `goldenAfter = .field64:(36,22) / .palette16:(42,145) / .diversityRing:(50,170)`
  (`MoveContract.swift:117`). DiversityRing default dock is `(40,170)`
  (`MovableLayout.hs:118,121`); `goldenScript` moves it `+(10,0)` → `(50,170)`.
- Mechanics (`CellMechanics.hs:317-319`): **all** `mcHoldTicks=6`; `Field64
  tickEvery=2`, others `1`; pulses `Field64 (40, q16/6, q16/2)`, `Palette16 (30,
  q16/5, q16*5/8)`, `DiversityRing (34, q16/5, q16*9/16)` where `q16=65536`.
  **Emit these from `WD.*` accessors, never hand-typed**, or `goldenPulse`/
  `selfCheck()` drift (Risk R4).

---

## 1. The `WidgetDescriptor` record

New module `spec/src/SixFour/Spec/WidgetDescriptor.hs`. It **FOLDS** the existing
owners — `ColorWidget` (`MovableLayout.hs:104-125`) and `mechanicsFor`
(`CellMechanics.hs:316-319`) — into one row per identity. Neither owner is
deleted; both stay the source of truth and the descriptor is *derived* from them.
Two NEW closed enums (`RenderMode`, `PaletteScope`) live HERE — they are the only
per-identity literals new to this file.

```haskell
{- |
Module      : SixFour.Spec.WidgetDescriptor
Description : ONE descriptor row per ColorIdentity — geometry + mechanics FOLDED
              from their owners, plus the two orthogonal render/scope columns.
-}
module SixFour.Spec.WidgetDescriptor
  ( RenderMode(..), allRenderModes, renderModeName
  , PaletteScope(..), allPaletteScopes, paletteScopeName
  , WidgetDescriptor(..)
  , descriptorFor, allDescriptors
  , lawDescriptorCoversIdentities
  , lawDescriptorMatchesClass
  , lawDescriptorMatchesMechanics
  , lawDescriptorIdsDistinct
  ) where

import SixFour.Spec.MovableLayout
  ( ColorIdentity(..), allIdentities
  , cwFootprint, cwDefaultCol, cwDefaultRow, cwInteractive, cwWidgetId, cwPriority )
import SixFour.Spec.CellMechanics
  ( Mechanics(..), mechanicsFor, Haptic(..), hapticName
  , PulseSpec(..), psPeriodTicks, psMinQ16, psMaxQ16 )

-- | How a widget's cells decode the cube (ORTHOGONAL to geometry — never read by 'move').
data RenderMode = Colorized | PaletteSwatches | DiversityGauge
  deriving (Eq, Ord, Enum, Bounded, Show)
allRenderModes :: [RenderMode]; allRenderModes = [minBound .. maxBound]
renderModeName :: RenderMode -> String
renderModeName Colorized       = "colorized"
renderModeName PaletteSwatches = "paletteSwatches"
renderModeName DiversityGauge  = "diversityGauge"

-- | Per-frame palette vs the one global palette. Tokens MUST equal the existing
-- 'PaletteTreeView' enum rawValues ("perFrame"/"global") — do NOT add a 3rd enum (Risk R6).
data PaletteScope = PerFrame | Global
  deriving (Eq, Ord, Enum, Bounded, Show)
allPaletteScopes :: [PaletteScope]; allPaletteScopes = [minBound .. maxBound]
paletteScopeName :: PaletteScope -> String
paletteScopeName PerFrame = "perFrame"
paletteScopeName Global   = "global"

-- | ONE row: geometry (read by move) + mechanics + the two orthogonal columns.
data WidgetDescriptor = WidgetDescriptor
  { wdIdentity     :: !ColorIdentity   -- enum key (rawValue == fromEnum)
  , wdFootprint    :: !(Int, Int)      -- GEOMETRY (read by move)
  , wdDefaultCol   :: !Int             -- GEOMETRY
  , wdDefaultRow   :: !Int             -- GEOMETRY
  , wdInteractive  :: !Bool            -- GEOMETRY
  , wdWidgetId     :: !Int             -- GEOMETRY (== fromEnum)
  , wdPriority     :: !Int             -- GEOMETRY (== fromEnum)
  , wdHoldTicks    :: !Int             -- MECHANICS (mechanicsFor)
  , wdLiftHaptic   :: !Haptic          -- MECHANICS
  , wdTickEvery    :: !Int             -- MECHANICS
  , wdPulse        :: !PulseSpec       -- MECHANICS (period, lo, hi)
  , wdRenderMode   :: !RenderMode      -- ORTHOGONAL (not in placedRegion)
  , wdPaletteScope :: !PaletteScope    -- ORTHOGONAL
  } deriving (Eq, Show)

-- | Geometry+mechanics FOLDED from the owners; the two orthogonal columns supplied here.
descriptorFor :: ColorIdentity -> WidgetDescriptor
descriptorFor i =
  let m = mechanicsFor i
  in WidgetDescriptor
       { wdIdentity = i
       , wdFootprint = cwFootprint i, wdDefaultCol = cwDefaultCol i
       , wdDefaultRow = cwDefaultRow i, wdInteractive = cwInteractive i
       , wdWidgetId = cwWidgetId i, wdPriority = cwPriority i
       , wdHoldTicks = mcHoldTicks m, wdLiftHaptic = mcLiftHaptic m
       , wdTickEvery = mcTickEvery m, wdPulse = mcPulse m
       , wdRenderMode = renderModeFor i, wdPaletteScope = paletteScopeFor i }
  where
    renderModeFor Field64       = Colorized
    renderModeFor Palette16     = PaletteSwatches
    renderModeFor DiversityRing = DiversityGauge
    paletteScopeFor Field64       = PerFrame
    paletteScopeFor Palette16     = Global
    paletteScopeFor DiversityRing = PerFrame

-- | Every descriptor in ColorIdentity Enum order (drives the emitter + the store).
allDescriptors :: [WidgetDescriptor]
allDescriptors = map descriptorFor allIdentities
```

**Sample NEW-widget row** — a `.gifc16` global-palette 16×16 colorised cell. Its
row is fully DERIVED (no literal table to append to):

```haskell
WidgetDescriptor
  { wdIdentity=GifC16, wdFootprint=(16,16), wdDefaultCol=60, wdDefaultRow=145
  , wdInteractive=False, wdWidgetId=3, wdPriority=3
  , wdHoldTicks=6, wdLiftHaptic=LiftPop, wdTickEvery=1
  , wdPulse=PulseSpec 30 (q16One `div` 5) (q16One * 5 `div` 8)
  , wdRenderMode=PaletteSwatches, wdPaletteScope=Global }
```

Because `wdWidgetId = wdPriority = fromEnum`, a new constructor auto-gets distinct
id/priority — `lawDescriptorIdsDistinct` holds by construction.

### Why move / goldenAfter stay byte-identical

- `move`, `clampInBounds`, `placementScene`, `goldenAfter` (`MovableLayout.hs:
  159-212`) and their Swift mirror are **untouched**. The descriptor only re-routes
  the *source* of footprint/defaultCol/defaultRow/interactive/widgetId/priority —
  values are folded straight from `cwFootprint`/`cwDefault*`/…, so they are
  numerically identical (`lawDescriptorMatchesClass` pins this value-for-value).
- `placementScene` orders via `Map.toList` keyed by `ColorIdentity` `Ord`
  (`MovableLayout.hs:151`); the Swift mirror iterates `ColorIdentity.allCases`.
  Neither is touched, and `renderMode`/`paletteScope` never enter
  `placedRegion`/`LRegion`. The record-field ORDER is irrelevant to the disjoint
  test. ⇒ `goldenAfter` literal `(36,22)/(42,145)/(50,170)` is byte-identical;
  `Surface.assertSpecParity` re-folds and matches.
- `dropVerdict` (`CellMechanics.hs:229`) is closed over `move`, so
  `lawDropColorMatchesMove` is unaffected. `wdPulse` carries the same `PulseSpec`
  ⇒ `goldenPulse` (`CellMechanics.hs:351`) byte-identical.

---

## 2. Codegen collapse — six emitters → one table

`spec/src/SixFour/Codegen/Swift.hs`: add `import qualified
SixFour.Spec.WidgetDescriptor as WD` and one new `emitWidgetDescriptorContract ::
Text`. Wire it in `app/Spec.hs` with one
`writeUtf8 (swiftOutDir </> "WidgetDescriptorContract.swift") emitWidgetDescriptorContract`.

**The collapse — both existing emitters lose their switch BODIES and delegate:**

- `emitMoveContract` (`Swift.hs:1324-1357`): the `footprint`/`defaultCol`/
  `defaultRow`/`interactive` switches DELETED; each getter becomes a one-line
  delegate. `widgetId`/`priority` stay one-liners (`i.rawValue`). The enum
  `ColorIdentity` declaration STAYS in `MoveContract` (it is imported by the
  descriptor file).
- `emitCellMechanicsContract` (`Swift.hs:1582-1607`): the FIVE switches
  `holdTicks`/`tickEvery`/`pulseBasePeriod`/`pulseBaseLo`/`pulseBaseHi` DELETED,
  replaced by delegates to `descriptor(for:).holdTicks`/`.tickEvery`/
  `.pulseSpec.period|lo|hi`. `selfCheck()` reads through the delegates unchanged.

```swift
// MoveContract.swift (generated, now delegating)
public static func footprint(_ i: ColorIdentity) -> (w: Int, h: Int) { WidgetDescriptorContract.descriptor(for: i).footprint }
public static func defaultCol(_ i: ColorIdentity) -> Int             { WidgetDescriptorContract.descriptor(for: i).defaultCol }
public static func defaultRow(_ i: ColorIdentity) -> Int             { WidgetDescriptorContract.descriptor(for: i).defaultRow }
public static func interactive(_ i: ColorIdentity) -> Bool           { WidgetDescriptorContract.descriptor(for: i).interactive }
```

**The single new emitter** maps `descriptorRow` over `WD.allDescriptors` — one
emitter replacing six. Each row literal comes from `descriptorRow ::
WD.WidgetDescriptor -> Text` reusing `WD.renderModeName`/`paletteScopeName`/
`hapticName` for string tokens and `WD.psPeriodTicks`/`psMinQ16`/`psMaxQ16` for
the pulse tuple — so the lo/hi numbers (10922, 32768, …) are emitted verbatim.

```swift
// Generated/WidgetDescriptorContract.swift
public struct WidgetDescriptor: Sendable {
  public let identity: ColorIdentity
  public let footprint: (w: Int, h: Int)
  public let defaultCol: Int
  public let defaultRow: Int
  public let interactive: Bool
  public let widgetId: Int
  public let priority: Int
  public let holdTicks: Int
  public let liftHaptic: String          // hapticName token
  public let tickEvery: Int
  public let pulseSpec: (period: Int, lo: Int, hi: Int)
  public let renderMode: String          // renderModeName token
  public let paletteScope: String        // paletteScopeName token
}

public enum WidgetDescriptorContract {
  public static let descriptors: [WidgetDescriptor] = [
    WidgetDescriptor(identity: .field64, footprint: (64,64), defaultCol: 18, defaultRow: 22,
      interactive: false, widgetId: 0, priority: 0, holdTicks: 6, liftHaptic: "liftPop",
      tickEvery: 2, pulseSpec: (40, 10922, 32768), renderMode: "colorized", paletteScope: "perFrame"),
    WidgetDescriptor(identity: .palette16, footprint: (16,16), defaultCol: 42, defaultRow: 145,
      interactive: true, widgetId: 1, priority: 1, holdTicks: 6, liftHaptic: "liftPop",
      tickEvery: 1, pulseSpec: (30, 13107, 40960), renderMode: "paletteSwatches", paletteScope: "global"),
    WidgetDescriptor(identity: .diversityRing, footprint: (20,20), defaultCol: 40, defaultRow: 170,
      interactive: false, widgetId: 2, priority: 2, holdTicks: 6, liftHaptic: "liftPop",
      tickEvery: 1, pulseSpec: (34, 13107, 36864), renderMode: "diversityGauge", paletteScope: "perFrame"),
  ]
  public static func descriptor(for i: ColorIdentity) -> WidgetDescriptor {
    descriptors.first { $0.identity == i } ?? descriptors[i.rawValue]
  }
  public static var defaultPlacement: [ColorIdentity: (col: Int, row: Int)] {
    var p: [ColorIdentity: (col: Int, row: Int)] = [:]
    for d in descriptors { p[d.identity] = (d.defaultCol, d.defaultRow) }
    return p
  }
  public static func selfCheck() -> Bool {       // re-asserts the FOLD didn't drift
    descriptors.count == ColorIdentity.allCases.count
      && Set(descriptors.map { $0.widgetId }).count == descriptors.count
      && Set(descriptors.map { $0.priority }).count == descriptors.count
  }
}
```

`descriptors[0].defaultCol == 18`, NOT `goldenAfter`'s `36` — the descriptor
table carries DEFAULTS; `goldenAfter` is the result of FOLDING `move` over
`goldenScript` and is unchanged. `WidgetDescriptorContract.selfCheck()` is called
beside `MoveContract.selfCheck()` / `SixFourCellMechanics.selfCheck()` in
`Surface.assertSpecParity` (DEBUG).

---

## 3. `AppSettings` `allCases` store + lossless migration

`SixFour/Settings/AppSettings.swift`.

**Keys (lines 41-44).** Replace the three `.field64Position.v1` /
`.palette16Position.v1` / `.diversityRingPosition.v1` with ONE unified key; keep
the three old strings as `legacy…` constants for the one-time read:

```swift
static let widgetPositions             = "sixfour.widgetPositions.v1"   // ONE unified key
static let legacyField64Position       = "sixfour.field64Position.v1"
static let legacyPalette16Position     = "sixfour.palette16Position.v1"
static let legacyDiversityRingPosition = "sixfour.diversityRingPosition.v1"
```

**Store (replaces lines 147-188).** Delete the three `GridPoint` stored props.
`widgetPlacement` becomes ONE `allCases`-keyed computed property over the unified
JSON key — `[String:[Int]]` keyed by `ColorIdentity.rawValue` (`== fromEnum`,
stable under append-only enum growth; human-legible; zero-dep via
`JSONSerialization`). `get` decodes, re-validates through
`MoveContract.placementScene` + `GridLayoutContract.isDisjoint` (same
defense-in-depth as today, lines 246-255), falls back to
`WidgetDescriptorContract.defaultPlacement` on absent/corrupt. `set` encodes and
writes. **`MovableColorWidget.commit()` (line 155) needs NO change** — the facade
is opaque.

```swift
var widgetPlacement: [ColorIdentity: (col: Int, row: Int)] {
  get {
    guard let data = defaults.data(forKey: Key.widgetPositions),
          let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: [Int]]
    else { return WidgetDescriptorContract.defaultPlacement }
    var p: [ColorIdentity: (col: Int, row: Int)] = [:]
    for (k, arr) in json where arr.count == 2 {
      if let raw = Int(k), let id = ColorIdentity(rawValue: raw) { p[id] = (arr[0], arr[1]) }
    }
    let s = MoveContract.placementScene(p)
    let inBounds = s.allSatisfy { $0.col >= 0 && $0.col + $0.w <= MoveContract.cols
                              && $0.row >= 0 && $0.row + $0.h <= MoveContract.rows }
    return (inBounds && GridLayoutContract.isDisjoint(s)) ? p : WidgetDescriptorContract.defaultPlacement
  }
  set {
    let dict = Dictionary(uniqueKeysWithValues:
      newValue.map { (String($0.key.rawValue), [$0.value.col, $0.value.row]) })
    if let data = try? JSONSerialization.data(withJSONObject: dict) {
      defaults.set(data, forKey: Key.widgetPositions)
    }
  }
}
```

**One-time migration (in `init`, before other props).** `migrateFromLegacyKeys()`
runs iff (any legacy key present) AND (unified key absent) — idempotent and
append-only-stable. It parses the three legacy `"col,row"` strings with the SAME
`parsePosition` fallback discipline (lines 193-200; absent/garbage →
`WidgetDescriptorContract` default), re-validates through
`placementScene + isDisjoint`, and writes the unified blob only if valid (else
writes nothing → next read falls to defaults). Legacy keys are left in place
(history). `AppSettings` is `MainActor`-isolated, so `UserDefaults.set` atomicity
holds.

**Why lossless + byte-stable:** both validation paths use the SAME
`placementScene + isDisjoint`; defaults are numerically identical (sourced from
descriptors); every live write is gated by `move`'s disjoint check. Corrupt data
can never enter the live map (SEAL-init / SEAL-read / SEAL-write).

---

## 4. The LAYERED detent (CellTick + EdgeStop)

**Spec (extend `CellMechanics.hs`, after `cellsCrossed` ~line 216).** "Is the
next step blocked?" is just `dropVerdict` of the candidate delta — `dropVerdict`
already folds BOTH the edge clamp (`clampInBounds` inside `move`) AND the disjoint
reject into one `Reject`. ONE pure fn + ONE law, no new geometry authority:

```haskell
-- | True iff a lifted step to candidate offset @to@ is BLOCKED (clamps at the
-- lattice edge OR overlaps another widget). Closed over the proven 'dropVerdict'
-- (hence over 'move'), so the rigid EdgeStop fires on the SAME predicate as the
-- red drop-frame: feel == sight == commit.
cellStepBlocked :: Placement -> ColorIdentity -> (Int, Int) -> Bool
cellStepBlocked p i to = dropVerdict p i to == Reject

-- | KEYSTONE (detent layer): EdgeStop and the red drop-frame fire on one predicate.
lawStepBlockedMatchesVerdict :: Placement -> ColorIdentity -> (Int, Int) -> Bool
lawStepBlockedMatchesVerdict p i to =
  cellStepBlocked p i to == (dropVerdict p i to == Reject)
```

Add `cellStepBlocked` to the detent export section and
`lawStepBlockedMatchesVerdict` to the laws block (`CellMechanics.hs:53,65-77`),
plus a QuickCheck case in `Properties/CellMechanics.hs`. The `edgeStop` token is
already at ordinal 2 in the haptic alphabet (`CellMechanics.hs:169,182`) — **no
alphabet edit**.

**Codegen (extend `emitCellMechanicsContract`, beside `dropAccepts`).** Derived,
no switch table:

```swift
/// True iff a lifted step to (dCol,dRow) is BLOCKED (clamps at edge OR overlaps).
/// Closed over MoveContract.move via dropAccepts — fires EdgeStop on the SAME
/// predicate as the red drop-frame (Spec.CellMechanics.lawStepBlockedMatchesVerdict).
@inline(__always)
public static func cellStepBlocked(_ placement: [ColorIdentity: (col: Int, row: Int)],
                                   _ identity: ColorIdentity, dCol: Int, dRow: Int) -> Bool {
  !dropAccepts(placement, identity, dCol: dCol, dRow: dRow)
}
```

**Swift wiring (`MovableColorWidget.swift`, `liftDrag` lines 119-138).** Add
`@State private var lastStepCell: (col: Int, row: Int) = (0, 0)` to
`MovableModifier`. In `.onChanged`, AFTER the existing `CellTick` block:

```swift
let cell = snapCells(d.translation)
// CellTick (existing): selection feedback per tickEvery boundary — unchanged.
let crossed = SixFourCellMechanics.cellsCrossed((col: 0, row: 0), cell)
let every   = max(1, SixFourCellMechanics.tickEvery(identity))
if crossed / every != lastTickCells / every { Haptics.play(1) }   // cellTick
lastTickCells = crossed
// EdgeStop (NEW): rigid impact on the transition INTO a blocked/clamped cell,
// once per cell (lastStepCell guards re-fire while held against the wall).
if lastStepCell != cell {
  if SixFourCellMechanics.cellStepBlocked(settings.widgetPlacement, identity,
                                          dCol: cell.col, dRow: cell.row) {
    Haptics.play(2)   // edgeStop — UIImpactFeedbackGenerator(.rigid)
  }
  lastStepCell = cell
}
```

Reset `lastStepCell = (0, 0)` beside `lastTickCells = 0` on lift (line 124) and in
`.onEnded` (line 135).

**Proof stability.** `cellStepBlocked` is DERIVED from `dropVerdict`/`dropAccepts`
(closed over `move`). `EdgeStop` fires on a CONTINUOUS drag sample, NOT an FSM
transition, so it never enters `hapticOnTransition` / `goldenHaptics` /
`goldenPhaseTrace` — `selfCheck()` (`Swift.hs:1618-1643`) is unaffected.
`lawStepBlockedMatchesVerdict` is definitionally green. `lawTickConservation`
(`cellsCrossed` untouched) and `lawDropColorMatchesMove` stay green.
`cabal test` 599 → 600. Add a Haptics rate-limit to avoid Taptic spam against a
wall (Risk R5).

---

## 5. `Spec.Boundary` — sections + stepped rounded-rect

NEW module `spec/src/SixFour/Spec/Boundary.hs`. **Two orthogonal owners:** (1) the
SECTION STACK that *partitions* the lattice height downward; (2) the stepped
rounded-rect outline cells. `renderMode`/`paletteScope` are NOT here.

> **Critic correction (Q4, blocking).** `Lattice.rows = 218` is SCREEN-derived
> (`Lattice.hs:128-133`) and is the in-bounds authority for `lawSceneInBounds`,
> `clampInBounds`, `lawSafeAreaClearance`, and `move`. Sections **cannot grow**
> `rows`. So sections are a DESCRIPTIVE partition over the fixed 218-row lattice:
> `Σ secHeight == Lattice.rows` (`lawSectionsTileRows`). "Append a story step"
> means carving cells from an existing section (sum conserved) OR — if the screen
> authority itself grows — changing `Lattice.rows` AND the stack together. The
> bottom rounded corners are at `Σ` = 218; appending a NAMED band re-partitions,
> it does not extend past the home-indicator inset.

```haskell
-- | One named user-story section, N cells tall, appended BELOW the prior. Top is
-- pinned at the safe area; appending re-partitions downward.
data Section = Section { secName :: !String, secHeight :: !Int } deriving (Eq, Show)

-- | The declared stack, top→bottom. SUM == Lattice.rows (lawSectionsTileRows).
-- The real bands MUST be derived from the as-built Spec.GridLayout captureScene,
-- not invented (Risk R3). Illustrative split shown:
sectionStack :: [Section]
sectionStack =
  [ Section "capture" 64, Section "palette" 90, Section "thumb" 64 ]  -- Σ = 218

boundaryRows :: Int
boundaryRows = sum (map secHeight sectionStack)            -- == Lattice.rows

sectionTop :: Int -> Int                                   -- prefix sum (dividers)
sectionTop k = sum (map secHeight (take k sectionStack))

-- | The stepped rounded-rect over (0,0)..(cols-1, rows-1); corners = quarter-discs
-- approximated in whole cells. @bCorner@ = iPhone screen corner snapped to lattice.
data Boundary = Boundary { bCols :: !Int, bRows :: !Int, bCorner :: !Int } deriving (Eq, Show)

theBoundary :: Boundary
theBoundary = Boundary cols boundaryRows 14   -- 14*4 = 56pt ≈ device corner (verify; Risk R8)

-- | A perimeter cell SURVIVES rounding iff inside the corner quarter-disc (or not
-- in a corner). Integer Euclidean disc, no floats; same disc mirrored 4-fold.
insideRounded :: Boundary -> Int -> Int -> Bool
insideRounded (Boundary w h rad) c r =
  let nx = if c < rad then rad - c else if c >= w - rad then c - (w - rad - 1) else 0
      ny = if r < rad then rad - r else if r >= h - rad then r - (h - rad - 1) else 0
  in nx*nx + ny*ny <= rad*rad

walkOutline :: Boundary -> [(Int, Int)]   -- closed CW walk: consecutive 4-adjacent, last↔first
outlineSet  :: Boundary -> Set Int        -- O(1) membership: r*w + c
```

**Laws (`Properties/Boundary.hs`):**
- `lawSectionsTileRows`: `boundaryRows == Σ secHeight && boundaryRows == Lattice.rows`.
- `lawSectionsMonotone`: all `secHeight > 0`; tops strictly increasing.
- `lawSectionsAppendOnly`: re-partitioning fixes every prior `sectionTop`.
- `lawBoundaryOutlineClosed`: `walkOutline` is a cycle (consecutive + last↔first 4-adjacent).
- `lawBoundarySymmetric`: outline invariant under both reflections (4-fold).
- `lawBoundaryCornerBound`: `bCorner * 2 <= min bCols bRows`.
- `lawBoundaryInBounds`: every outline cell in `[0,cols) × [0,rows)`.

**Codegen** — NEW `emitBoundaryContract` (mirror `emitMoveContract`). Emits
`BoundaryContract.swift`: `cols`/`rows`/`corner`, `sectionNames`/
`sectionHeights`/`sectionTops`, `outline: [(col,row)]`, `isOutline(_:_:)` (O(1)
Set lookup), and `selfCheck()` re-walking adjacency + mirrors. Reuses existing
`intListLiteral`/`strLit`/`tshow` helpers. Wire in `app/Spec.hs` beside
`MoveContract`.

**`BoundaryView.swift`** (CellSprite-based, drawn ATOP the field, BELOW the
movable widgets; placed via `View.place(GridRegion)` at the full-lattice region in
`Surface.swift`):

```swift
struct BoundaryView: View {
  var ink: SIMD3<UInt8> = SIMD3(120, 120, 130)
  var body: some View {
    CellSprite(cols: BoundaryContract.cols, rows: BoundaryContract.rows,
               cellPt: GlobalLattice.gifPx) { c, r in
      BoundaryContract.isOutline(c, r) ? ink : nil
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}
```

**Where the layers meet.** Keep boundary rejection ORTHOGONAL — checked AFTER the
disjoint test, on the boundary set only — so `goldenAfter` stays byte-identical
(Risk R7). When/if blocked cells later fold into `move` as a 4th reject reason,
`cellStepBlocked` returns `True` at the rounded wall automatically — `EdgeStop`
fires at the boundary edge for free.

---

## 6. Authoring API

**ADD A MOVABLE WIDGET** (the descriptor-collapse goal). *Honest scope (critic
Q3): this is ONE descriptor row — geometry + mechanics + render columns — and NO
scattered Swift switches and NO `AppSettings` edit. An ON-SCREEN widget also needs
a Swift `.movable(identity,…)` call site with a cell-drawing view in
Live/Review/Rendering phase fields; that render call site is not collapsed.*

1. `MovableLayout.hs`: add the constructor to `data ColorIdentity` (line 91) +
   four `ColorWidget` cases (`cwFootprint`/`cwDefaultCol`/`cwDefaultRow`;
   `cwInteractive` falls through; `cwWidgetId`/`cwPriority` = `fromEnum`).
2. `CellMechanics.hs`: one `mechanicsFor` case (line 319).
3. `WidgetDescriptor.hs`: one `renderModeFor` + one `paletteScopeFor` case.
4. `cd spec && cabal test && cabal run spec-codegen` — every per-identity getter
   regenerates from `allIdentities`; the new descriptor row appears.
   `lawDefaultsDisjoint` proves the new dock doesn't collide; a missing
   `mechanicsFor`/`renderModeFor` case is a compile/test failure, never a silent
   gap. No `AppSettings` edit (the `allCases` JSON store keys by `rawValue`; the
   new ordinal's default comes from `WidgetDescriptorContract.defaultPlacement`).

**APPEND A DOWNWARD SECTION** (re-partition the frame for a story step).
1. `Boundary.hs`: append one `Section "newband" N`; keep `Σ == Lattice.rows`
   (carve `N` from an existing band, OR grow `Lattice.rows` + the stack together
   if the screen authority changes).
2. `cabal test` (`lawSectionsTileRows`/`Monotone`/`AppendOnly` green) →
   `cabal run spec-codegen` (regenerates `sectionTops` + outline) →
   `xcodegen generate && xcodebuild`. `BoundaryView` re-partitions; top corners
   unmoved.

---

## 7. Phased spec-first plan (each phase gated by `scripts/s4.sh`)

Each new `Spec.*`/`Codegen.*` module honors the CLAUDE.md contract: `spec.cabal`
`exposed-modules`, a `{- | Module / Description -}` header, ONE line in
`SixFour.Spec.Map` §7, a `-- |` on every export, `cabal haddock` warning-clean.

1. **WidgetDescriptor spec. ✅ DONE 2026-06-08.** Added `WidgetDescriptor.hs` (record +
   `RenderMode`/`PaletteScope` enums + `descriptorFor`/`allDescriptors` + 4 laws:
   `lawDescriptorMatchesClass`/`MatchesMechanics`/`Total`/`ScopeCoherent`). Wired
   `spec.cabal`, `Map.hs` §7, `Properties/WidgetDescriptor.hs`. **`cabal test` green
   (603 total).** The descriptor is a proven faithful *view* of `ColorWidget` +
   `mechanicsFor`, so Phase 2's codegen delegation is byte-safe.
2. **Descriptor codegen + delegation.** Add `emitWidgetDescriptorContract`; collapse
   the six `emitMoveContract` + five `emitCellMechanicsContract` switch bodies to
   delegates; wire `app/Spec.hs`. Gate: `s4.sh gen` → `xcodebuild` → confirm
   `MoveContract.goldenAfter`/`CellMechanicsContract.goldenPulse` byte-identical;
   `WidgetDescriptorContract.selfCheck()` in `assertSpecParity`.
3. **Detent (CellTick + EdgeStop).** Add `cellStepBlocked` +
   `lawStepBlockedMatchesVerdict` + emitter fn; wire `MovableColorWidget` +
   `lastStepCell` + Haptics rate-limit. Gate: `cabal test` 599→600;
   `goldenHaptics` unchanged.
4. **AppSettings `allCases` store + migration.** Collapse to one key +
   `widgetPlacement` JSON facade + `migrateFromLegacyKeys()`. Gate: `xcodebuild`;
   manual first-launch-upgrade migration test; `selfCheck` count guard.
5. **Canvas/viewport split (FOUNDATIONAL — user decision 2026-06-08).** The user chose
   a **scrolling canvas taller than the screen**, so `rows` becomes TWO concepts:
   `canvasRows = Σ section heights` (the `move`/`clampInBounds` in-bounds authority —
   widgets may dock below the fold) vs `viewportRows = 218` (the visible screen, where the
   home-indicator safe-area inset applies). This reworks `Spec.Lattice` (`lawLattice` pins
   `rows == 218` today, `Lattice.hs:257`) + `Spec.GridLayout`'s in-bounds/safe-area laws to
   quantify over `canvasRows` for placement but `viewportRows` for the inset. The field
   scrolls; appending a section genuinely extends the canvas downward. Do this BEFORE the
   boundary, spec-first, as its own gated phase — it touches the authority `move` depends
   on. Gate: `cabal test` (re-prove the disjoint/in-bounds laws over `canvasRows`);
   confirm `goldenAfter` byte-identical (the seed docks are unchanged, only the bound grows).
6. **Spec.Boundary.** Add `Boundary.hs` (sections + the stepped rounded-rect outline over
   `canvasRows` + laws), `emitBoundaryContract`, a scrollable `BoundaryView`,
   `Properties/Boundary.hs`, `spec.cabal`/`Map.hs` §7. The top corners round at the
   viewport top; the bottom corners round at the canvas end (`Σ` sections) and scroll into
   view. Gate: `s4.sh all`; `goldenAfter` byte-identical (boundary orthogonal).

---

## 8. Risks / open questions

- **R1 (critic Q4 → USER DECISION 2026-06-08: scrolling canvas).** The critic
  correctly flagged that `Lattice.rows = 218` is screen-derived and `move`'s
  in-bounds authority, so sections cannot grow it *as written*. The user chose to
  resolve this by **splitting canvas from viewport** (Phase 5): `canvasRows = Σ
  sections` (growable, the placement authority) vs `viewportRows = 218` (visible,
  the safe-area authority). This is the deeper, deliberate rework — NOT the
  "partition the fixed screen" fallback. The canvas genuinely extends downward and
  the field scrolls. Must re-prove the `GridLayout` in-bounds/safe-area laws over
  the split before the boundary lands.
- **R2 (critic Q3 — resolved).** "Add a widget = one row" is true for the
  DESCRIPTOR (geometry+mechanics+render, no Swift switches, no AppSettings edit),
  NOT for an on-screen widget (still needs a `.movable` render call site).
  `DiversityRing` already renders nothing — the spec member is reserved, dock held.
- **R3.** `sectionStack` heights must be DERIVED from the as-built
  `Spec.GridLayout captureScene`, not the illustrative 64+90+64; cross-check
  before committing or the boundary won't align with where widgets dock.
- **R4.** Emit mechanics from `WD.*` accessors, never the prompt's sample
  literals (SOURCE: `holdTicks=6` all; `Field64 tickEvery=2`; pulses
  `q16/6,q16/2 / q16/5,q16*5/8 / q16/5,q16*9/16`) or `goldenPulse`/`selfCheck`
  fail.
- **R5.** `EdgeStop` against a wall can spam the Taptic engine; the `lastStepCell`
  guard fires only on transition INTO a new blocked cell — also rate-limit in
  `Haptics.swift`.
- **R6.** `PaletteScope` already exists in `PaletteTreeView.swift:75-76`
  (`perFrame`/`global`) and `AppSettings`. The generated token MUST emit the SAME
  rawValues and Swift consumers map the token THROUGH the existing enum's
  `init(rawValue:)` — do NOT add a third type. Likewise map `renderMode` via the
  generated `allRenderModes` name array, never bare `==`.
- **R7.** If boundary-blocked cells fold into `move`, that touches the accept set
  and could change `goldenAfter`. Keep boundary rejection orthogonal (after the
  disjoint test) and re-run `cabal test` to confirm byte-identity.
- **R8.** Corner radius (14 cells ≈ 56pt) is an estimate; verify the real iPhone
  17 Pro corner. `lawBoundaryCornerBound` holds regardless; only the visual match
  depends on the real value.
- **R9 (open).** `wdLiftHaptic` is constant `LiftPop` today; emitting per-row is
  harmless, but flag it now as a real per-widget knob so a future per-widget lift
  feel isn't a silent behavior change.
- **R10 (open).** A future `ColorIdentity` REORDER would mis-map the
  ordinal-keyed JSON blob; the `selfCheck` count guard catches missing rows but
  not a reorder — document the enum as APPEND-ONLY.
- **Maintenance (both new modules).** `spec.cabal` `exposed-modules`, header,
  ONE `Map.hs` §7 line, `-- |` on every export, `Properties.WidgetDescriptor` +
  `Properties.Boundary` in the test `other-modules` stanza, `cabal haddock`
  warning-clean — or the lint/Haddock gate fails.

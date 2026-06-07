# SixFour — Ownership-Grid Spec + Grid Tech-Debt Cleanup Plan

> **Date:** 2026-06-06
> **Status:** DESIGN (spec-first, not yet built)
> **Owner module to add:** `SixFour.Spec.Ownership`
> **Companion gate:** `scripts/s4.sh all` (codegen → verify → native → lint → gen → build)
>
> This doc has two halves that must land together:
> **PART A** — the new SIMD-ownership-grid spec (`SixFour.Spec.Ownership`).
> **PART B** — the prioritized grid tech-debt cleanup (several items are *preconditions* for Part A).

---

## 0. The model, stated crisply

The Swift screen is **one SIMD field of cells**. Each cell is `(col, row, color)`, and **COLOR IS IDENTITY**: a chrome cell's rendered colour decodes *which Owner controls it*.

- The field is the **100×218 atom lattice** (`Lattice.cols × Lattice.rows = 21800` cells, the 4 pt-atom v3.0 screen lattice — **not** the 64×64 GIF base).
- `owner :: OwnerScene -> Atom -> Owner` is **TOTAL** over the whole lattice and is a **DISJOINT COVER**:
  - **Totality** — every cell has exactly one owner; a `Field` owner absorbs the complement.
  - **Disjointness** — no cell is owned twice; foreground regions are pairwise non-overlapping. A doubly-claimed cell surfaces the loud `CellFiber.contestedSentinel` through the existing no-blend fiber — **never a blend**.
- There are **7 named owners**, each with a typed, law-bound **Responsibility**:
  - `Preview` governs the **64×64** GIF-frame field.
  - `Palette` governs that frame's **16×16** colour grid.
  - `Shutter`, `Gear`, `Field`, `Ring`, `Wordmark` are the rest.
- The **whole field re-evaluates as ONE pass per 1/20 s tick** (`Display.logicRateHz = 20`).

### The three soundness traps the model resolves
1. **Content vs Identity layer split.** Preview/Palette *interiors* paint `σ.palette` DATA (the CONTENT layer); the colour-decodes-owner theorem is scoped to the chrome owners + the debug overlay (the IDENTITY layer). So `lawColorDecodesOwner` never overreaches into "the GIF preview must be 7 flat colours."
2. **Shutter∩Palette fusion is a declared `EffectZone`**, not an unhandled overlap. On the live face the shutter is fused into the palette rectangle; `lawFusionIsEffectZoneNotBug` rules this a first-class sanctioned co-occupancy, so disjointness is not violated.
3. **Totality is paired with completeness.** `lawPreviewClaimsFullFootprint` proves each foreground owner claims *exactly* its Lattice-sized footprint, so `Field`-as-totaliser cannot silently swallow an under-claim bug.

The module **composes the existing substrate** — `Lattice` atoms, `GridLayout`'s disjointness algebra, `CellFiber`'s no-blend fiber, `Order`/`GridScript` within-region fill, the single `Display` clock — and concretises `GridLayout`'s opaque `lrWidget :: Int` into a closed, public, colour-decodable `Owner` enum.

---

## PART A — The Ownership-Grid Spec

### A.1 Module + core types

`module SixFour.Spec.Ownership` (GHC-boot-only deps: `base`/`containers` + `Spec.Lattice`/`.GridLayout`/`.CellFiber`/`.Order`/`.GridAxis`/`.Display`).

```haskell
-- | The closed, exhaustive owner set. Bounded/Enum ⇒ the cover is machine-checked total.
-- Concretises GridLayout's opaque lrWidget :: Int (GridLayout.hs:71).
data Owner = Preview | Palette | Shutter | Gear | Field | Ring | Wordmark
  deriving (Eq, Ord, Show, Enum, Bounded)

allOwners :: [Owner]
allOwners = [minBound .. maxBound]            -- the 7-element domain of every owner law

-- | A SCREEN-lattice atom (the user's 'Swift grid'), NOT the 64×64 GIF base.
-- Cols 0..99, rows 0..217. Pins the load-bearing base decision (Risk #1).
data Atom = Atom { atomCol :: !Int, atomRow :: !Int } deriving (Eq, Ord, Show)

allAtoms :: [Atom]                            -- cols*rows = 100*218 = 21800; the finite total domain
allAtoms = [ Atom c r | r <- [0 .. Lattice.rows - 1], c <- [0 .. Lattice.cols - 1] ]

-- | Each owner's reserved IDENTITY badge colour, drawn from CellFiber.Color (Q16 OKLab)
-- so the SIMD field carries ONE colour type. Image is disjoint from neutralColor and
-- contestedSentinel and pairwise injective (lawOwnerColorInjective).
newtype OwnerColor = OwnerColor { unOwnerColor :: CellFiber.Color } deriving (Eq, Ord, Show)
ownerColor    :: Owner -> OwnerColor          -- injective identity palette
ownerColorInv :: OwnerColor -> Maybe Owner    -- partial inverse (Just on the 7 badges)

-- | A law-bound duty over a sized region, discharged at a cadence.
data Governs
  = GovernsFrames !Int | GovernsPalette !Int | GovernsControl
  | GovernsGauge  !Int | GovernsGround        | GovernsTitle
  deriving (Eq, Show)
data Responsibility = Responsibility { reGoverns :: !Governs, reCadenceHz :: !Int } deriving (Eq, Show)
responsibility :: Owner -> Responsibility     -- total, exhaustive over allOwners

-- | A foreground owner's rectangular claim. Reuses GridLayout.LRegion fields but
-- replaces lrWidget :: Int with a typed orOwner :: Owner.
data OwnerRegion = OwnerRegion
  { orOwner :: !Owner, orCol :: !Int, orRow :: !Int, orW :: !Int, orH :: !Int
  , orInteractive :: !Bool } deriving (Eq, Show)

-- | The scene: foreground owners + declared EffectZone fusion pairs.
-- Field is implicit (absorbs every unclaimed atom → cover is TOTAL).
data OwnerScene = OwnerScene
  { osRegions :: [OwnerRegion]                -- Preview..Wordmark, NO Field
  , osFusion  :: [(Owner, Owner)] }           -- declared co-owner pairs, e.g. (Shutter,Palette)
captureScene :: OwnerScene                    -- extends GridLayout.captureScene 2 → 7

-- | THE ownership map: TOTAL (no Maybe — Field is the default).
ownerAt        :: OwnerScene -> Atom -> Owner
ownerContested :: OwnerScene -> [Atom]        -- empty iff well-formed (modulo fusion)

-- | The SIMD cell (col,row,color). Identity layer = decoded owner badge;
-- Content layer = σ.palette data for Preview/Palette interiors.
data FieldCell  = FieldCell { fcCol :: !Int, fcRow :: !Int, fcColor :: !CellFiber.Color }
data RenderLayer = Identity | Content
fieldCell :: RenderLayer -> OwnerScene -> Atom -> FieldCell
fieldOf   :: RenderLayer -> OwnerScene -> [FieldCell]   -- length == cols*rows when total

-- | One whole-field re-evaluation per 1/20 s tick. Pure total function of the
-- mounted scene (tick enters only via the Field heartbeat ground inversion on Content).
refreshHz    :: Int                           -- == Display.logicRateHz == 20
refreshField :: Int -> RenderLayer -> OwnerScene -> [FieldCell]
```

### A.2 The owner table

| Owner | Identity badge (OKLab-Q16) | Region (cells) | Responsibility (@20 fps) |
|---|---|---|---|
| **Preview** | deep cool-blue (high-L, low-chroma, b<0) | col 18 row 22, **64×64** — REUSED from `GridLayout.captureScene` "preview" (GridLayout.hs:90); `previewCells=64` | `GovernsFrames 64` — the 64×64 GIF-frame field; 1 GIF px / atom; 4096 atoms |
| **Palette** | warm teal (mid-L, mid-chroma) | col 42 row 145, **16×16**, interactive — REUSED from "palette" (GridLayout.hs:92); `shutterCells=16==GridAxis.gridSide` | `GovernsPalette 16` — that frame's 256-slot palette; fill = Order/GridScript slot→rank bijection |
| **Shutter** | warm-red (low-L) | live face: **FUSED** into Palette (osFusion `(Shutter,Palette)` ⇒ declared EffectZone). capture/resolve face: own disc+ring (`6·2+2·2=16=shutterCells`) | `GovernsControl` — interactive trigger; footprint ≥ `touchFloorCells=11` |
| **Gear** | slate grey-green (low chroma, cool) | `w=h=controlCells=12`, thumb-reach corner, interactive. **NEW golden coords** | `GovernsControl` — settings; `12 ≥ 11` |
| **Field** | fixed neutral-leaning anchor (≠ `neutralColor`=⊥) | THE TOTALISER: every atom not claimed by a foreground region. CONTENT render = camera-responsive TintedCheckerField (dynamic, content layer only) | `GovernsGround` — background checker; two inks invert each tick (heartbeat) |
| **Ring** | bright amber (high chroma) | `w=h=ringCells=20` (R10); `ringTicks=64` tick cells (CellShapes.ringTickEndpoints). **NEW golden coords** | `GovernsGauge 64` — diversity gauge; `ringTicks==previewCells==64` |
| **Wordmark** | off-white (very high L, ~0 chroma) | `w=wordmarkCols=60 h=wordmarkRows=11`, non-interactive. **NEW golden coords** | `GovernsTitle` — title band; `wordmarkCols ≤ previewCells (60 ≤ 64)` |

### A.3 Laws (precise statements)

1. **`lawOwnerColorInjective`** — `∀ o1 o2 ∈ allOwners. ownerColor o1 == ownerColor o2 ⇒ o1 == o2`, and `∀ o. unOwnerColor (ownerColor o) ∉ {neutralColor, contestedSentinel}`. Discharge: 7-element pairwise check + 2 disequalities. *(Stated over fixed IDENTITY badges; Field's dynamic content tint is exempt.)*
2. **`lawColorDecodesOwner`** — On the Identity layer, `∀ atom` with `ownerAt s atom ≠ contested`: `ownerColorInv (fcColor (fieldCell Identity s atom)) == Just (ownerAt s atom)`; and `ownerColorInv ∘ ownerColor == Just` on all owners. On the Content layer the theorem is stated as **region membership** decodes the owner even when the painted colour is `σ.palette` data. *(Explicit layer scope — never an overreach.)*
3. **`lawCoverTotal`** — `∀ atom ∈ allAtoms, ownerAt captureScene atom` is defined. Equivalently `length (fieldOf l captureScene) == cols*rows == 21800` with no gaps. Field absorbs the complement, so `∪ osRegions ∪ Field = allAtoms` by construction. *(Closes the gap GridLayout left: it proved disjointness but permitted unclaimed cells.)*
4. **`lawCoverDisjoint`** — OwnerRegions of distinct non-fused owners are pairwise non-overlapping ⇒ `ownerContested captureScene == []`. Discharge by REUSE of `GridLayout.lawSceneDisjoint`/`lawDisjointMatchesRects` over the Owner-keyed scene, with `osFusion` pairs excluded. Together with `lawCoverTotal` ⇒ the **DISJOINT COVER**.
5. **`lawDisjointMatchesRectsOwner`** — BRIDGE (generalises GridLayout's 2→7): `null (ownerContested s) == not (any (uncurry regionsOverlap) (nonFusedDistinctPairs (osRegions s)))`. Fiber proof ≡ rectangle test over the owner set.
6. **`lawContentionIsSentinelNotBlend`** — `∀ atom ∈ ownerContested s, fcColor (fieldCell Identity s atom) == contestedSentinel` (loud magenta, NEVER averaged). Discharge by REUSE of `CellFiber.lawNoSynthesis`.
7. **`lawFusionIsEffectZoneNotBug`** — `(Shutter,Palette) ∈ osFusion`: `∀ atom` in the fused intersection, `fcColor (fieldCell Content s atom) ≠ contestedSentinel` (renders host content / `CellFiber.shimmerAt`). Fusion is a first-class ruling — disjoint-cover thesis NOT violated on the live face.
8. **`lawResponsibilityTotal`** — total & exhaustive: `Preview→GovernsFrames 64, Palette→GovernsPalette 16, Shutter→GovernsControl, Gear→GovernsControl, Field→GovernsGround, Ring→GovernsGauge 64, Wordmark→GovernsTitle`; every `reCadenceHz == refreshHz == 20`. Closed enum ⇒ no owner dutiless, no duty owner-less.
9. **`lawPreviewGovernsFrames`** — `responsibility Preview == Responsibility (GovernsFrames previewCells) 20 ∧ previewCells == 64`; cell count `== 64² == 4096 == length CellGrid.allPlaces`.
10. **`lawPreviewClaimsFullFootprint`** — COMPLETENESS companion: `∀ named owner o, {atom | ownerAt s atom == o} == regionCells (regionOf o)` (e.g. `orW==orH==previewCells`). An under-claim FAILS this law rather than silently falling through to Field. *(Totality + completeness kept SEPARATE.)*
11. **`lawPaletteGovernsPalette`** — `responsibility Palette == Responsibility (GovernsPalette shutterCells) 20 ∧ shutterCells == 16 ∧ shutterCells == GridAxis.gridSide ∧ region cells == GridAxis.gridCells == 256`. Internal fill = `Order.lawPermBijection`.
12. **`lawRingAnswersToFrames`** — `responsibility Ring == Responsibility (GovernsGauge ringTicks) 20 ∧ ringTicks == previewCells == 64`. Couples Ring↔Preview by law.
13. **`lawColorIsQuotientLabel`** — Identity layer: `∀ non-contested p q. fcColor (fieldCell Identity s p) == fcColor (fieldCell Identity s q) ⇔ ownerAt s p == ownerAt s q`. The colour field is the quotient map of the ownership partition. *(Sharpest formalisation of "color encodes ownership".)*
14. **`lawRefreshIs20fps`** — `refreshHz == Display.logicRateHz == 20`. `refreshField` is a pure total function of the mounted scene (tick enters only via the Field heartbeat). The refresh set over the SCREEN base `== allAtoms (21800)` — the spatial companion of Display T5's `fullLattice`. **NOTE the base-change:** T5.fullLattice is the 64×64 GIF field (4096); this law is stated over `allAtoms` (screen base), NOT compared to `T5.fullLattice` directly. Reuses the single Display clock constant; no second clock constant.
15. **`lawCoverInBounds`** — every owned atom lies inside 100×218. Discharge by REUSE of `GridLayout.lawSceneInBounds`; Field is bounded by construction. With (3)+(4) ⇒ a total, disjoint, in-bounds partition.

### A.4 Reuse map (NOTHING re-declared)

| Substrate | What is reused | Owner-spec use |
|---|---|---|
| **`Spec.Lattice`** | atoms + per-widget cell counts: `gifPx=4` (:107), `cols=100/rows=218` (:129,133), `previewCells=64` (:170), `shutterCells=16` (:185), `ringCells=20`/`ringTicks=64` (:192,196), `controlCells=12` (:180), `touchFloorCells=11` (:175), `wordmarkRows=11`/`wordmarkCols=60` (:200,204), `shutterDiscRadiusCells=6`/`shutterRingThicknessCells=2` (:216,220) | Every `Responsibility` size and `OwnerRegion` footprint is a Lattice constant |
| **`Spec.GridLayout`** | `LRegion`/`lrWidget` (:66,71), `Scene`/`captureScene` (:77,88), `regionCells` (:97), `regionsOverlap` (:104), `sceneGrid` fold via `CellFiber.join` (:112), `sceneContested` (:120), `lawSceneDisjoint` (:133), `lawSceneInBounds` (:137), `lawInteractiveTouchFloor` (:143), `lawDisjointMatchesRects` (:166) | `lawCoverDisjoint`/`InBounds`/`TouchFloor`/`DisjointMatchesRectsOwner` are DISCHARGED by these, not re-proven |
| **`Spec.CellFiber`** | `Color` Q16 OKLab (:89), `join=Set.union` (:96), `isContested |c|>1` (:116), `neutralColor` ⊥ (:152), `contestedSentinel` magenta (:159), no-blend render (:165), `shimmerAt` (:177), `lawNoSynthesis` (:218) | `OwnerColor` wraps `Color`; sentinel IS the contention marker; no new contention machinery |
| **`Spec.Order`/GridScript** | slot→rank `FinitePerm` (:76), `rowMajor` (:98), `serpentine` (:107), `lawPermBijection` (:132) | UNCHANGED — how an owner paints its OWN cells; ownership does not touch placement order |
| **`Spec.GridAxis`** | `gridSide=16` (:98), `gridCells=256` (:101) | `lawPaletteGovernsPalette` cross-checks Palette footprint so the two cannot drift |
| **`Spec.Display`** | `logicRateHz=20` (:255), `fullLattice`/T5 support (:368,375) | `lawRefreshIs20fps` binds `refreshHz` to `logicRateHz`; stated over screen base, base-difference explicit; no new clock |
| **`Spec.CellShapes`** | `ringTickEndpoints` 64-tick table (:81), `inDisc`/`inAnnulus` | Ring per-tick cells + Shutter disc closure |

### A.5 Swift port plan (with corrections to the synthesis's overreaches)

1. **Generate `OwnershipContract.swift`** exposing: `enum SFOwner: UInt8, CaseIterable` (7 cases, rawValue == Haskell Enum ordinal); `ownerColor(_:) -> SFColor` (injective OKLab-Q16 badge palette, golden-pinned); `responsibility(_:) -> SFResponsibility`; `captureRegions: [SFOwnerRegion]` (gains `owner: SFOwner`, replacing the discarded `GridRegion.widget: Int`); `fusionPairs: [(SFOwner,SFOwner)]`; `ownerAt(col:row:) -> SFOwner` (total cover = foreground regions + Field fallback).
2. **`CellField` base is ALREADY correct (comment-sync only — CORRECTED).** `CellField.cols/rows` resolve through `GlobalLattice.cols → SixFourLattice.cols → 100/218` at runtime — the bake is on the right base. Only the inline comments (`// 201`, `67×145`) are stale (retired 2 pt/6 pt eras); fix them with the D15/D19 comment-sync. *(This corrects the synthesis's earlier "re-base first" overreach; verified 2026-06-06.)*
3. **WIRE the existing color=ownership engine.** `ContestedCellGridView` already has `cellAt:(row,col)->SFCell` (:33) + `effectZone:(row,col)->Bool` (:35) seams and `renderCell` surfaces the sentinel. Set:
   - `cellAt = { (r,c) in SFCell([ OwnershipContract.ownerColor(OwnershipContract.ownerAt(col:c,row:r)).value ]) }`
   - `effectZone = { (r,c) in OwnershipContract.isFused(col:c,row:r) }`
   so a cell's colour IS its owner identity and any non-fused double-claim renders the sentinel with NO new code.
4. **RENDER LAYERS.** Keep live PhaseFields painting `σ.palette` CONTENT on Preview/Palette interiors (the hero must show the GIF, not 7 flat colours). Owner-identity is the Content layer with chrome wearing badges; the IDENTITY layer is reserved for an ownership DEBUG overlay — this layer split makes `lawColorDecodesOwner` sound.
5. **Stop discarding the owner id.** `View.place(_:)` (ScreenLattice.swift:36) reads only col/row/w/h today; thread `SFOwner` through and assert the placed view's owner badge matches its region.
6. **CLOCK (correction).** `PlaybackClock` the TYPE is alive (`ContestedCellGridView.swift:31` is typed `let clock: PlaybackClock`; its `Timer` is gone but the value-type drives ~10 files). `lawRefreshIs20fps` binds to `logicRateHz=20` (the one CADisplayLink is `SurfaceClock`); claim a single **RATE** (`logicRateHz`) that both `SurfaceClock` and the `PlaybackClock` cursor honour — **do NOT** claim a single clock *object*.
7. **Determinism.** The OKLab-Q16→sRGB8 Zig kernel (`SurfaceColor.oklabQ16ToSrgb8` / `s4_palette_oklab_to_srgb8`) bakes owner badges so screen == GIF byte-for-byte.

**Changes:** `SFOwner` replaces the opaque widget Int; `ownerColor` adds a 7-entry reserved palette; `CellField` re-based to 100×218 and owner-keyed on the debug layer.
**Stays:** the atom, `place()`, the clock RATE, the no-blend cell algebra, `σ.palette` content render.

### A.6 Codegen + golden plan (corrections applied)

- Add `emitOwnershipContract :: Text` **INSIDE the existing `spec/src/SixFour/Codegen/Swift.hs`** (there is NO `Codegen/GridLayout.hs` or `Codegen/Ownership.hs` — `emitGridLayoutContract` lives at `Swift.hs:1053+`, exported from `module SixFour.Codegen.Swift` at :18-34; siblings `emitLatticeContract:111`, `emitCellContract:974`). Wire it into the same export list + driver that writes `SixFour/Generated/*Contract.swift`.
- Emits `SixFour/Generated/OwnershipContract.swift`: (a) `enum SFOwner: UInt8, CaseIterable`; (b) `ownerColor(_:) -> SFColor` as Q16 OKLab literals; (c) `responsibility(_:)`; (d) `captureRegions: [SFOwnerRegion]` (sizes drawn from LatticeContract — no number re-typed); (e) `fusionPairs` + `isFused(col:row:)`; (f) `ownerAt(col:row:)`; (g) `selfCheck()` re-asserting injectivity, totality (all cols×rows resolve), disjointness-modulo-fusion, completeness, and `refreshHz==logicRateHz==20` **at init only** (pattern from `CellShapesContract.selfCheck` — never per-tick, to respect the 20 fps budget).
- **GOLDEN VECTORS** pinned in the spec and ported verbatim:
  1. `ownerColorTable :: [(Owner, CellFiber.Color)]` — the 7 badges.
  2. `coverSample :: [(Atom, Owner)]` — ~16 representative atoms (Preview interior, Palette interior, a Ring tick, a Wordmark cell, a Gear cell, a bare Field cell, every region BORDER, the four corners) → expected owner.
  3. `fusionSample` — atoms in Shutter∩Palette asserting NOT contested.
  4. `contestedFixture` — a deliberately-overlapped non-fused pair asserting `fcColor==contestedSentinel`.
  5. `decodeRoundTrip :: [(CellFiber.Color, Maybe Owner)]` — proves `lawColorDecodesOwner`.
  6. `responsibilityTable`.
- **Test gate:** `cabal test` (`Properties.Ownership` QuickCheck) gates `lawOwnerColorInjective`/`lawCoverTotal`/`lawCoverDisjoint`/`lawPreviewClaimsFullFootprint`/`lawResponsibilityTotal`/`lawRefreshIs20fps` over `allAtoms`. `CellAlgebraTests` already gate the no-blend render path `cellAt` feeds.
- **Lint:** wire into `scripts/lint-grid.sh` LINT-GOLDEN (assert `Ownership` module + `OwnershipContract.swift` exist + cabal-exposed). **ADD** a disjoint/total-cover assertion to `scripts/verify-doc-claims.sh` (it currently has ZERO ownership assertions).
- **PRECONDITION ledger fix:** correct `STATUS.md:81/91` "Spec.Lattice [PLANNED]/unbuilt" in the SAME change (this module hard-depends on live LatticeContract), or the doc-gate misreports the substrate as absent.

---

## PART A.7 — Implementation plan (sequenced, spec-first, smallest viable first)

Each step is: **write the Haskell law → emit the codegen contract slice → port the Swift seam → pin the golden gate.** Land in order; `cabal test` + `s4 all` must be green after each.

> **Step 0 (PREREQUISITES — must precede any owner code).** Land the PART-B prereqs marked `[PREREQ]`: (D1) un-stale `STATUS.md` Spec.Lattice rows; (D2) repair the RED `verify-doc-claims.sh` deleted-path checks + add the path-exists meta-guard; (D9) add the **complement + totality law** to GridLayout (`coverComplement` / `lawCoverPartitions`) so the cover is provably total *without* grafting a ground rectangle into the disjoint claim set (per D30). Without these the substrate the cover sits on is mislabeled and the gate lies. *(D-rebase was investigated and DOWNGRADED — see Part B: CellField already bakes at 100×218; only its comments are stale, so it is not a cardinality blocker.)*
>
> **✅ Step 0 LANDED 2026-06-06:** D1 (STATUS reconciled), D2 (gate green + meta-guard, 33 PASS), D9 (`lawCoverPartitions` added, full spec suite green, `GridLayoutContract.swift` byte-unchanged).
>
> **✅ STEPS 0–4 VERIFIED END-TO-END 2026-06-06:** `scripts/s4.sh all` ALL GREEN — codegen → verify-doc-claims → native (Zig) → GRID lint → xcodegen → **xcodebuild iOS `BUILD SUCCEEDED`**. `OwnershipContract.swift` compiles into the app target (no symbol collision), lint clean, drift gate clean. The disjoint-cover keystone is real on the build path. Steps 5–7 remain.

1. **Owner alphabet + injective badges. ✅ LANDED 2026-06-06.** Added `spec/src/SixFour/Spec/Ownership.hs` — `Owner`/`allOwners`/`OwnerColor`/`ownerColor`/`ownerColorInv` + `lawOwnerColorInjective` + `lawOwnerColorRoundTrips` + `ownerColorTable` golden. Codegen: `emitOwnershipContract` → `Generated/OwnershipContract.swift` (`enum SFOwner: UInt8`, `ownerColor(_:)`, `ownerColorInv`, `ownerColorTable`, `selfCheck()`). Gate: `Properties.Ownership` (4 props) green — **full suite 557 tests**; generated Swift `-typecheck` clean; `xcodegen` wired; no other `Generated/` file drifted. *(Swift app-target build via `s4 all` xcodebuild not yet run this session.)*
2. **Responsibility binding. ✅ LANDED 2026-06-06.** Added `Governs`/`Responsibility`/`responsibility` + `lawResponsibilityTotal`/`lawPreviewGovernsFrames`/`lawPaletteGovernsPalette`/`lawRingAnswersToFrames` + `responsibilityTable` golden, with sizes pinned to `Lattice.{previewCells,shutterCells,ringTicks}` / `GridAxis.{gridSide,gridCells}` / `Display.logicRateHz` / `CellGrid.allPlaces` (no re-typed literals; `previewCells²==|allPlaces|==4096`, `shutterCells²==gridCells==256` proven). Codegen: `SFGoverns`/`SFResponsibility` + `responsibility(_:)` + `responsibilityTable`; `selfCheck()` extended (Preview→frames 64, Palette→palette 16, all @20fps). Gate: `Properties.Ownership` now 8 props — **full suite 561 tests**; contract `-typecheck` clean; no other `Generated/` drift.
3. **Foreground regions (2-owner seed). ✅ SPEC+CODEGEN LANDED 2026-06-06.** Added `Atom`/`allAtoms`/`OwnerRegion`/`OwnerScene`/`captureScene` (preview+palette coords REUSED verbatim from `GridLayout.captureScene`, sizes from `Lattice`) + `ownerAt` (foreground + Field fallback) + `ownerContested` (REUSES `GridLayout.sceneContested` — no re-derived overlap) + `lawCoverInBounds`/`lawCoverDisjoint`/`lawCoverSampleMatches` + `coverSample` golden. Codegen: `SFOwnerRegion` + `captureRegions` + `ownerAt(col:row:)` + `coverSample` + `selfCheck()` cover assertion. **Full suite 564 tests**; contract `-typecheck` clean; no other `Generated/` drift. **⏳ DEFERRED (needs app build):** the live `ContestedCellGridView.cellAt` debug overlay (D7) — the first app-target change; batch it with `s4.sh all` rather than wire it unverified.
4. **Totality + completeness. ✅ LANDED 2026-06-06.** Added `lawCoverTotal` (all 21800 atoms owned; `Field` owns the exact complement = `cols·rows − previewCells² − shutterCells² = 17448`) + `lawPreviewClaimsFullFootprint` (each foreground owner claims EXACTLY its footprint — Preview 4096, Palette 256 — so an under-claim fails *this* law even though totality still holds; kept SEPARATE from totality by design). Codegen: `selfCheck()` does one lattice pass tallying per-owner counts (`nPrev==4096, nPal==256, nField==17448`, numbers emitted from `Lattice` constants). **Full suite 566 tests**; contract `-typecheck` clean; no other `Generated/` drift. **→ With `lawCoverDisjoint` (step 3) this completes the DISJOINT COVER — the keystone the whole model rests on.**
5. **Fusion zone. ✅ LANDED 2026-06-06.** `osFusion=[(Shutter,Palette)]` + `isFused` + `ownerContested` made fusion-aware (excludes declared pairs) + `fusionFixture`/`contestedFixture` + `lawFusionIsEffectZoneNotBug` (fused overlap ≠ contention) + `lawContentionIsSentinelNotBlend` (non-fused overlap → `CellFiber.render` = `contestedSentinel`, REUSING `lawNoSynthesis`) + `lawDisjointMatchesRectsOwner` (bridge generalised 2→owner-set+fusion). Codegen: `fusionPairs`/`isFused` + selfCheck. **569 tests**.
6. **The remaining owners + full 7-owner scene. ✅ LANDED 2026-06-06.** `captureScene` now has Preview/Palette/Shutter(fused≡Palette)/Wordmark(60×11@88)/Ring(20²@104)/Gear(12²@190) + implicit Field — a **proven disjoint cover** (coords from `Lattice` constants). `lawCoverTotal` generalised to `Field == cols·rows − |Set.union of footprints|` (fusion counted once); `lawPreviewClaimsFullFootprint` generalised to "footprint owned by self-or-fused"; added `lawOwnerTouchFloor`. Codegen: full `captureRegions` (6) + exhaustive per-owner `selfCheck` tally `[4096,256,0,144,16244,400,660]` (=21800). **570 tests**; typecheck clean; no other `Generated/` drift.
7. **Refresh + decode round-trip. ✅ SPEC+CODEGEN LANDED 2026-06-06.** Added `FieldCell` + `fieldColorAt` (identity layer: owner badge, or `contestedSentinel` at a genuine non-fused contention) + `fieldOf` + `refreshHz` (=`Display.logicRateHz`=20) + `decodeRoundTrip` golden + `lawRefreshIs20fps` + `lawColorDecodesOwner` + **`lawColorIsQuotientLabel`** (same colour ⇔ same owner — the sharpest form of "colour encodes ownership", follows from injectivity). Codegen: `refreshHz` + `fieldColorAt(col:row:)` + selfCheck refresh/decode spot-check. **Full suite 573 tests; full `s4.sh all` GREEN (BUILD SUCCEEDED).** **✅ LIVE OVERLAY LANDED 2026-06-06 (`d461870`):** `CellOwnershipOverlay.swift` paints the whole 100×218 lattice via `fieldColorAt` (one bake → `paletteToSRGB8(k=21800)` → one bitmap, `CellField` pattern — not a Canvas), gated by `AppSettings.debugOwnershipOverlay` (default OFF → shipping UI byte-identical), mounted as `SurfaceView`'s outermost `.overlay`. `s4.sh lint`+`build` green. `View.place(_:)`/`SFOwner` threading DEFERRED (the overlay is the whole field, not a placed sub-widget) — the one remaining future-work item.
8. **Final wiring.** `verify-doc-claims.sh` total/disjoint-cover assertion; `lint-grid.sh` LINT-GOLDEN owner-module check; STATUS.md ownership row. Gate: `scripts/s4.sh all` fully green.

---

## PART B — Prioritized grid tech-debt cleanup

Each row carries the **ownership-model tie-in** and a **[PREREQ]** / **[INDEP]** flag (prerequisite for the Part-A overhaul vs independent cleanup that may land any time).

### B.1 High severity

| id | title | location | sev | flag | fix (ownership tie-in) |
|---|---|---|---|---|---|
| **D1** status-drift: Spec.Lattice marked `[PLANNED]`/unbuilt but is live, law-bearing, test-gated | `docs/STATUS.md:81,91` | high | **[PREREQ]** | Delete the MISSING bullet (:81); resolve the `spec-lattice-unbuilt` open-debt row (:91) — Lattice.hs is a 12.4 KB module exporting 10 laws, emitting `LatticeContract.swift`, gated by `Properties.Lattice` (11 props). Per-widget cell counts ARE the per-owner responsibility substrate; calling it unbuilt hides usable law machinery. Keep the genuinely-open `atom-pitch-violations` row (:99). |
| **D2** `verify-doc-claims.sh` is RED: greps a deleted path `…/Review/GIFReviewView.swift` | `scripts/verify-doc-claims.sh:75,89` | high | **[PREREQ]** | Line 75 hard-fails (missing file); line 89 false-greens (`! grep` on a missing file flips to pass). Rewrite both for the live review path; line 75 must assert today's truth (PaletteGridView is NOT wired). **ADD a meta-guard** that every file path named in the gate exists (`test -e`), with a distinct "GATE BUG" message, so a deleted-file false-green/hard-fail can never masquerade as a doc-claim result. *Ownership: the gate must hold the cover honest; a lying gate cannot catch an ownership regression.* |
| **D3** STATUS "Palette explorer …default review view" describes a Review screen that no longer exists | `docs/STATUS.md:41-43` vs `ReviewPhaseField.swift:36-76` | high | **[INDEP]** | Rewrite :41-43 to the as-built review: single `CubeSurface` voxel hero on one `SurfaceClock` + pose sliders + determinism badge + Share/Retake row; no `.grid2D` enum case exists. Move PaletteGridView/Tree/AddressPicker/Quad4/Cloud to a DESIGN-ONLY/orphaned bullet. *Ownership: STATUS implies the palette OWNER's 16×16 surface is shipped — it is NOT on screen. Flag as an owner-surface gap.* |
| **D4** GIFPlayer + GIFCanvas: whole unified-player file dead (0 live callers) | `SixFour/UI/Components/GIFPlayer.swift` | high | **[INDEP]** | Delete `GIFPlayer.swift` (169 LOC) + lint exemption (`lint-grid.sh:45`). **Cascade:** also delete `VoxelCubeView` struct's dead caller path and `PlayerTransport.swift` (PlayerMode), but FIRST migrate `AppSettings.playerMode` (PlayerMode→local enum/Int) so persisted `sixfour.playerMode.v1` survives. Keep `PlaybackClock`. *Ownership: collapses the retired multi-surface player to one-surface ReviewPhaseField→CubeSurface.* |
| **D5** VoxelCubeView struct + state: dead wrapper; only `CubeSurface`/`VoxelCubeData`/`VoxelCubeState` live | `VoxelCubeView.swift:203` | high | **[INDEP]** | Delete the `VoxelCubeView: View` wrapper (~203-446) + its `#Preview`; **KEEP `VoxelCubeState`** (live `CubeSurface:462` + `VoxelMetalView:472` use it) and `CubeSurface`/`VoxelCubeData`. *Ownership: PREVIEW owner's 3D render primitive is `CubeSurface`; drop the dead interactive/brush wrapper.* |
| **D6** PaletteCloudView (626 LOC): orphan, only its own `#Preview` constructs it | `PaletteCloudView.swift` | high | **[INDEP]** | Delete the file; remove lint exemption (`lint-grid.sh:48`) + `verify-doc-claims.sh:78-79` "shipped" assert; drop stale doc refs. *Ownership: PALETTE owner's 4D projection — currently unreachable; safest first removal of the dark explorer family.* |
| **D7** ContestedCellGridView (113 LOC): the contention-surfacing view has 0 live callers | `ContestedCellGridView.swift` | high | **[PREREQ]** | **WIRE** into the live `SurfaceView`/`LivePhaseField` as a DEBUG ownership overlay (the Swift counterpart to `lawCoverDisjoint`) — this is the exact seam Part-A step 3/5/7 wires `cellAt`/`effectZone` into. *(If wiring is truly out of scope, delete + remove `lint-grid.sh:44` exemption + fix `SIXFOUR-DISPLAY-FSM.md:189`.)* Prefer WIRE — it makes "contention is a bug made visible" real on device. |
| **D8** PaletteGridView + PaletteTreeView: fully orphaned, yet STATUS calls PaletteGridView "default review view" | `PaletteGridView.swift`, `PaletteTreeView.swift` | high | **[INDEP]** | (1) Correct STATUS:41-42 (live default review = CubeSurface). (2) Optionally delete both views; do NOT claim it transitively kills PixelGrid (PaletteTreeView never used PixelGrid; PixelGrid is referenced by GridScript/ContestedCellGridView). Drop the `palette-tree-unlabeled` debt row (:98). |
| **D9** Disjoint-cover proof covers 2 owners; real scene has ~7 — not a TOTAL map | `spec/src/SixFour/Spec/GridLayout.hs:88-94` | high | **[PREREQ]** | Add a lowest-priority `background` LRegion spanning 100×218 + regions for the real owners; add a **totality** law (`every cell owned by exactly one region after priority resolution`) separate from `lawSceneDisjoint`. *This is precisely what `Spec.Ownership` formalises — Part A IS the fix; this row tracks the GridLayout-side groundwork (background owner + totality law) the new module composes.* |
| **D10** Banners + build stamp placed off-grid via `.overlay`/`.padding`, escaping the cover + lint | `CapturingPhaseField.swift:40`, `RenderingPhaseField.swift:48-49`, `LivePhaseField.swift:55-60` | high | **[PREREQ]** | Give banner/stage-banner/build-stamp their own `GridRegion`s in `captureScene` and `.place(...)` them; extend LINT-PLACEMENT to flag `.overlay(alignment:`/`.background(` carrying cell content (with `// LINT-ALLOW-OVERLAY` escape). *Ownership: these are real cell-consuming owners; today they can silently overlap Preview/Palette with no contention check — the back door the cover forbids.* |
| **D11** Disjoint-cover proof only instantiated on a 2-owner scene; 7-owner model has no proven scene | `GridLayout.hs:88-94`, `Properties/GridLayout.hs:10-26` | high | **[PREREQ]** | Make `captureScene` the FULL ownership map; add `Arbitrary Scene` + `forAll` for `lawDisjointMatchesRects` (pure equivalence, fuzz it); add `lawTotalCover`. *Ownership: until then disjoint/total are dischargeable only for the 2-owner seed — Part A's `coverSample` golden + full-scene laws subsume this.* CAUTION: adding real owners may surface a genuine wordmark/gear band overlap — that FAILURE is the point. |
| **D12** Governed chrome placed by `.overlay`/`.padding` bypasses `.place()` and every region/disjointness gate | multiple `*PhaseField.swift` | high | **[PREREQ]** | Same fix family as D10: named `GridRegion` + `.place()`; extend LINT-PLACEMENT to `.overlay(alignment:` and require overlay-padded `CellText` carry a region name. *Ownership: overlay placement is the unguarded re-admission of exactly the contention the proof forbids.* |
| **D-rebase** ~~high [PREREQ]~~ **→ med [INDEP], CORRECTED 2026-06-06** CellField *comments* are stale (`// 201`, `67×145` from retired 2pt/6pt eras), but the **runtime value is already correct**: `CellField.cols → GlobalLattice.cols → SixFourLattice.cols → 100`. This is NOT a wrong-cardinality bake — it is a comment-drift item in the D15/D19 family. | `CellField.swift:6,28-29,119-120` | med | **[INDEP]** | Comment-sync the `// 201` / `67·6=402` lines to v3.0 `100×218`. **No code change** — the bake already runs at 100×218 (verified). |

### B.2 Medium severity

| id | title | location | sev | flag | fix (ownership tie-in) |
|---|---|---|---|---|---|
| **D13** lint-grid.sh whitelists dead views by FILENAME instead of catching orphans | `lint-grid.sh:44-48` | high→med | **[INDEP]** | Keep the draw-vocab exemption (correctly scoped), but add a SEPARATE **LINT-ORPHAN** check: each `UI/Components/*View.swift` must have a non-`#Preview`, reachable-from-`SurfaceView` constructor call or be on an explicit allow-list. Catches transitive dead (VoxelCubeView via dead GIFPlayer). *Ownership: operationalizes "exactly ONE live render path rooted at SurfaceView."* |
| **D14** SFTheme is a SECOND, lint-invisible owner of cell↔point math | `Theme.swift:34-38,91,96` | med | **[INDEP]** | Have SFTheme RE-EXPORT GlobalLattice (`gifCanvasPt { GlobalLattice.gif(previewCells) }`, etc.), leaving SFTheme colour/typography only; extend LINT-SINGLE-LATTICE to forbid a second derivation of `gifCellPt`/`gifCanvasPt`. *Ownership: `heroEdge` is the PREVIEW owner's 64×64 — size it by the SAME call the owner-map uses to claim those cells.* |
| **D15** GlobalLattice.swift (the SOLE-owner header) inline comments cite retired 6 pt / gifPx-3 / 67×145 / closure 5·2+1·2 | `GlobalLattice.swift:26,30,33,38` | med | **[INDEP]** | Comment-sync to v3.0: `gifPx=4 pt = 12 device-px`, `subPt=gifPx/2`, `100×218`, closure `6·2+2·2=16`, 44 pt floor. Header (3-28) already correct (drop the line:8 citation). Best: have codegen emit the doc strings, or drop literals entirely. *Ownership: stale comments on the Law-#5 facade are the highest-traffic 6-vs-4 pt confusion source.* |
| **D16** docs/SIXFOUR-DESIGN-LANGUAGE.md (cited for the `[PLANNED]` tag) is stale v2.0 | `SIXFOUR-DESIGN-LANGUAGE.md:3-12` | med | **[INDEP]** | Add a v3.0 amendment (4 pt, 100×218, 256 pt preview, subPt retained, drop blanket `[PLANNED]` on Spec.Lattice). Until fixed, STATUS:91 must NOT cite it as evidence (circular: a stale doc "proving" a false status). Reconcile ScreenLattice/GlobalLattice/GridLayout as the single lattice authority. |
| **D17** PixelGrid: transitively dead (sole caller is orphaned PaletteGridView) | `PixelGrid.swift:74` | med | **[INDEP]** | Delete ONLY `struct PixelGrid: View` (74-95). **KEEP** `Color(srgb8:)`, `PixelImage`, `PixelGridOrigin`, `pixelFrame()`, `fillCell`, `fillBorder`, `paletteSubdivide` — all load-bearing across live surfaces. Fix the canonical-fill-site comments. |
| **D18** HaarShutterView: retired 4×4 Haar shutter glyph orphaned | `HaarShutterView.swift:9` | med | **[INDEP]** | Delete (45 LOC). *Ownership: SHUTTER owner's footprint is the 16×16 palette-as-shutter, not a 4×4 Haar tile.* Do NOT delete `SixFourNative.haarLevelColors` (spec-pinned kernel) — record in the Zig-migration ledger. |
| **D19** GlobalLattice.swift + CellField: two contradictory truths about cell-ownership geometry (6 pt/201×437 vs 4 pt/100×218) | `GlobalLattice.swift:30,33,38`, `CellField.swift:6,28-29,119-120` | med | **[PREREQ]** | Rewrite both comment blocks to v3.0 facts (`100·4=400`, not `402`). Better: codegen-emit the facade doc strings. *Ownership: a reader trusting these mis-computes which cells an owner claims — same single-source violation the lattice claims to eliminate.* (Overlaps D-rebase + D15.) |
| **D20** GridLayoutContract.selfCheck() is dead — runtime disjointness re-assertion never runs | `GridLayoutContract.swift:57-72` | med | **[PREREQ]** | Add `assert(GridLayoutContract.selfCheck(), …)` to `Surface.swift`'s `assertSpecParity()` (alongside `SixFourDisplay.selfCheck()` :192). Optionally a `#expect(...)` test. *Ownership: the disjoint cover's runtime guard is silently absent; the new `OwnershipContract.selfCheck()` must follow the SAME wiring.* |
| **D21** Lint allows `.place("name")` for any name absent from the scene — name/region binding debug-only | `ScreenLattice.swift:36-44` | med | **[PREREQ]** | Add LINT-PLACEMENT-NAMES: derive the legal name set from `GridLayoutContract.swift` `name:` literals (NOT hand-listed) and fail the build on any `.place("…")` not in it. Optionally harden the release fallback (visible sentinel, not silent `AnyView(self)`). *Ownership: makes "placed only by claiming proven cells" a build gate; the new owner names must join this check.* |
| **D22** ContestedCellGridView exempt as a primitive but never required (no gate wires it in) | `ContestedCellGridView.swift`, `lint-grid.sh:49` | med | **[PREREQ]** | Same decision as D7: WIRE as DEBUG contention overlay + test that contested rendering is non-dead, OR delete. Prefer WIRE (it is the Part-A debug-overlay seam). |
| **D23** STATUS/design-language drift: Spec.Lattice `[PLANNED]` but v3.0 live + law-bearing + test-registered | `STATUS.md:81,91`, `DESIGN-LANGUAGE.md:5,9-12` | med | **[PREREQ]** | (Same family as D1/D16/D23 — consolidate.) Resolve `spec-lattice-unbuilt`; amend DESIGN-LANGUAGE to v3.0; add a `verify-doc-claims.sh` rule: fail if a doc says "not yet built"/`[PLANNED]` next to a `Spec.<X>` that is cabal-exposed AND exports `law*` AND is referenced by an `emit*`. |
| **D24** LINT-DRAW-VOCAB enforced ONLY on LivePhaseField, not sibling governed phase fields | `lint-grid.sh` (`HUD=…LivePhaseField.swift`) | med | **[INDEP]** | Loop the THREE universal bans (opacity-on-cell, dimText/hairline, raw `RoundedRectangle`/`Circle`/`stroke`/`Text`) over every `Surface/*PhaseField.swift`; keep the GLASS ban HUD-only (Review/Settings glass is sanctioned). *Ownership: every phase field is the one no-blend owner field; gating only the HUD lets the other owners re-introduce drift.* |

### B.3 Low severity

| id | title | location | sev | flag | fix |
|---|---|---|---|---|---|
| **D25** Pervasive "6 pt" Review-pitch comments assert a retired pitch | `PlayerTransport.swift:13,31`, `CellSprite.swift:39,46,128`, `CellGlyph.swift:16`, `CellChrome.swift:73`, `PaletteGridView.swift:99` | low | **[INDEP]** | Replace `// 6 pt` with the typed token (`gifCellPt` = the one 4 pt atom) or drop the literal. Also fix `CellSprite.swift:96` (`12·6=72`→`16·4=64`), `:282` (`20·6=120`→`20·4=80`), and "34×34-cell" → `shutterCells=16`. Rule: comments name the token, never the number. |
| **D26** `glassClusterSpacing` comment wrong (`// 12 = 2 cells`; actual 8) | `Theme.swift:96` | low | **[INDEP]** | `// 2·4 = 8 pt (2 cells)`. Value 8 pt is correct/intended; comment-only. |
| **D27** PaletteTreeView treemap line widths use raw off-atom literals (2.5, 0.9, 0.5) | `PaletteTreeView.swift:67`, `Theme.swift:65` | low | **[INDEP]** | Consolidate the three literals into one named, spec-mirrored token group + a comment sanctioning treemap planes as a sub-subPt render detail. (These are BELOW subPt=2 pt; exact lattice multiples would coarsen the hairline.) |
| **D28** PaletteCloudView/VoxelCubeView (lint-exempt primitives) hold bare `.padding(8)`/`.frame(minHeight:44)` at glass-chrome sites | `PaletteCloudView.swift:254,459`, `VoxelCubeView.swift:322` | low | **[INDEP]** | Route through `GlobalLattice.pt(4)`=8 / `GlobalLattice.gif(touchFloorCells)`=44; narrow the exemption (`// LINT-ALLOW-POSITION` on the genuine canvas lines). Largely mooted if D4/D5/D6 delete these files. |
| **D29** STATUS "517 tests pass" is unpinned AND already drifted (actual 552) | `STATUS.md:40` | low | **[INDEP]** | Update 517→552 now; pin the count at the Tier-0 `cabal test` layer (e.g. emit a `spec/TEST_COUNT` the suite writes + gate-cross-checks), keeping `verify-doc-claims.sh` grep-only. Or drop the integer ("spec suite green, gated by `cabal test`"). |
| **D30** GridLayout `lrPriority` proven distinct but consulted by NO resolver (dead reassurance) | `GridLayout.hs:108-121,156-160` | low | **[INDEP]** | The model is NO-BLEND DISJOINTNESS (collision = sentinel, never priority-wins). DELETE `lrPriority` + `lawPriorityDistinct` (regen contract, drop `priority` from `selfCheck`), OR — if a true background plane is wanted — model it as a separate ground layer OUTSIDE the disjoint claim set (as `TintedCheckerField` already is). Do NOT graft a priority resolver onto the disjoint algebra. |

### B.4 Prerequisite ordering for the overhaul

**Must land before Part-A step 1:** D1, D2, D9 (+ the consolidated D15/D16/D19/D23 doc/comment v3.0 sync; **D-rebase folds into this comment-sync family — it is NOT a cardinality blocker**). ✅ D1/D2/D9 landed 2026-06-06.
**Land during Part-A steps 3–7 (they ARE the Swift seams):** D7/D22 (debug overlay), D10/D12 (chrome → regions), D11 (full-scene proof + Arbitrary), D20 (selfCheck wiring), D21 (place-name lint).
**Independent (any time, reduce noise first):** D3, D4, D5, D6, D8, D13, D14, D15, D17, D18, D24, D25–D30.

---

## Verify gate

After each step and at the end, run the full pipeline (codegen → verify-doc-claims → native → lint → gen → build):

```sh
scripts/s4.sh all
```

This regenerates `SixFour/Generated/OwnershipContract.swift`, runs `cabal test` (incl. `Properties.Ownership`), re-asserts `verify-doc-claims.sh` (now with the ownership total/disjoint-cover assertion + the path-exists meta-guard from D2), enforces `lint-grid.sh` (LINT-GOLDEN owner-module + LINT-ORPHAN + extended LINT-PLACEMENT/LINT-DRAW-VOCAB), regenerates the xcodeproj, and builds for iOS. All must be green.

---

## Executive summary

1. **The model:** the screen is one 100×218 SIMD cell field where color decodes owner; a new `SixFour.Spec.Ownership` gives a TOTAL, DISJOINT-COVER `owner :: OwnerScene -> Atom -> Owner` over 7 named owners (Preview→64×64, Palette→16×16, +Shutter/Gear/Field/Ring/Wordmark), re-evaluated as one pass per 1/20 s tick.
2. **Soundness:** an Identity/Content layer split scopes "color decodes owner" correctly, Shutter∩Palette fusion is a declared EffectZone (not a bug), and totality is paired with a completeness law so the Field totaliser can't hide under-claims — all composing existing Lattice/GridLayout/CellFiber/Order/Display law machinery (nothing re-declared).
3. **Build path:** 8 spec-first steps (Haskell law → `emitOwnershipContract` in the existing `Codegen/Swift.hs` → Swift seam via the already-present `ContestedCellGridView.cellAt`/`effectZone` → golden gate), smallest-viable first, after a Step-0 prerequisite block.
4. **Debt:** 30 adversarially-verified items; the load-bearing prerequisites are un-staling STATUS's false "Spec.Lattice unbuilt" rows (D1/D23 — **✅ done**), repairing the RED `verify-doc-claims.sh` deleted-path checks + meta-guard (D2 — **✅ done**), making GridLayout's cover actually total (D9 — **✅ done**; D11 full-scene fuzz pending), and pulling off-grid `.overlay` chrome into proven regions (D10/D12). Dead-chrome deletions (GIFPlayer/VoxelCubeView-wrapper/PaletteCloud/PaletteGrid/HaarShutter) and v3.0 comment syncs (incl. the downgraded D-rebase) are independent noise-reduction.
5. **Gate:** every step ends green under `scripts/s4.sh all`, which now also asserts the disjoint/total ownership cover and guards against the deleted-file gate hole.

**Path:** `/Users/daniel/SixFour/docs/SIXFOUR-OWNERSHIP-GRID-DESIGN.md`

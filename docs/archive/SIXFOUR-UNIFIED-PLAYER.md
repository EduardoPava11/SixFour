# SixFour — Unified 2D/3D Player + Frame-Synced Palette Analyzer

> Status: **IMPLEMENTED 2026-06-04** — build green, 149 Swift + 462 Haskell tests pass.
> Source: `sixfour-unified-player-design` workflow (map → design → adversarial critique), 2026-06-04.
>
> As-built notes:
> - Steps 1–8 all landed. `PlaybackClock` (one timer) replaces the four drifting clocks.
> - `GIFPlayer` hero = FLAT (`GIFCanvas`, render-only) ⟷ CUBE (`VoxelCubeView` `.heroMinimal`)
>   on a 6 pt `PlayerTransport` (play/pause · 64-cell scrub rail · counter · 2D/3D toggle).
> - `CellSprite`/`CellDigits` gained a `cellPt` param (default 2 pt HUD) so the transport
>   renders at 6 pt — single Review pitch, no GRID Law #5 regression.
> - Analyzers synced: Grid/Tree/Cloud read live `clock.frame`; AddressPicker/Quad4 read
>   `clock.settledFrame` (rebuild on pause/scrub only). Their internal `TimelineView`/`Timer`
>   clocks were deleted.
> - The palette explorer's `.voxel3D` was KEPT as the full study cube (provenance/trail/
>   luma/isolate), now clock-synced via `chrome: .full`. The `frameIndex(at:)` helper was
>   removed (no callers).

## Problem

The Review screen runs **four uncoordinated frame clocks** that drift and never agree on
"the current frame":

| Clock | Owner | Site |
|---|---|---|
| 2D GIF `Timer` | `GIFCanvas` | `GIFReviewView.swift:281` (frame `@State:233`) |
| status-line `TimelineView` (from `Date`) | `GIFReviewView` | `:143-144` → `PixelGrid.swift:34` |
| cloud 60Hz `Timer.publish` | `CloudState` | `PaletteCloudView.swift:215` |
| voxel 60Hz `Timer.publish` | `VoxelCubeState` | `VoxelCubeView.swift:214` |

`PaletteGridView`/`PaletteTreeView` ride yet another `TimelineView.animation`.
`AddressPickerView` (`:92`) and `Quad4DrillView` (`:98`) are hard-wired to
`palettesForDisplay.first` → they only *look* frame-locked to frame 0.

## Data is already there (memory flag was stale)

`CaptureOutput.palettesForDisplay : [[SIMD3<UInt8>]]` (64×256, **non-optional**, always
populated — `CaptureViewModel.swift:19`) and `frameIndicesForVoxels : [[UInt8]]?` (64×4096,
populated in all 3 render paths `:383/461/551`) already carry per-frame data end-to-end.
**No new `CaptureOutput` field is needed.** The "CaptureOutput drops frameIndices" note
referred only to the *optional* voxel index map (3D toggle hidden when `nil`, `:74`), not
the palettes. Palette-sync is `.first` → `[clock.frame]` at each call site.

## Architecture

```
GIFReviewView  ──owns──▶  PlaybackClock (ObservableObject, the ONE 20fps advancer)
                              │  @Published frame:Int 0..<N   playing:Bool
                              │  reduceMotion ⇒ frame pinned 0, advance() no-op
        ┌─────────────────────┼───────────────────────────────────┐
        ▼                     ▼                                     ▼
   GIFPlayer            status line                         palette analyzers
   (unified tool)       statusLine(frame: clock.frame)      read palettesForDisplay[clock.frame]
   ├ FLAT  = GIFCanvas (render-only)
   ├ CUBE  = VoxelCubeView (render-only, front face z=63 == clock.frame)
   ├ toggle = CellSelector<FLAT|CUBE>   (6pt)
   └ transport = PlayPause · ScrubRail(64) · Counter NN/64   (6pt)
```

`GIFPlayer` is the "one tool set": 2D and 3D are two render modes of the same component on
the same clock. The kernel guarantees the flat-pose 3D front face is **byte-identical** to
the 2D GIF at `clock.frame` (`Shaders.metal:658`, guarded by `VoxelRestPoseIdentityTests`).

## Decisions (locked 2026-06-04)

1. **Transport pitch = 6pt Review, single-pitch.** Re-implement the transport + toggle
   primitives on the 6pt `gifCellPt` cell so the entire Review surface is ONE pitch.
   Resolves the critic's dual-pitch (GRID Law #5) regression: the existing `CellSelector`/
   `CellRing`/`CellDigits` are 2pt-`GlobalLattice` and MUST NOT be imported as-is.
   → New 6pt cell variants; touch floor pinned in **points (≥44pt)**, cell count derived.
2. **Analyzer sync cadence:** Grid/Tree/Cloud follow `clock.frame` continuously (cheap
   selector swap). Tree-rebuilding analyzers (`AddressPickerView`, `Quad4DrillView`)
   re-sync **on pause/scrub only** — no ~256-leaf median-cut rebuild at 20fps.
3. **Spec depth = full codegen pipeline** (matches StageA/Coverage rigor): `Spec.PlaybackClock`
   + Codegen emitter → `Generated/PlaybackClockContract.swift` + Swift parity test gate.

## Pixel/GRID conformance (must hold)

- Transport + toggle built ONLY from Cell* primitives **re-pitched to 6pt** — zero SwiftUI
  `Slider`/`Picker`/`Toggle`. (Note: a `Button` used purely as a cell hit-target with a cell
  label is sanctioned precedent — the "zero Button" lint is restated as "no styled SwiftUI
  control chrome".)
- One cell pitch per surface (6pt on Review); controls grow by MORE cells, never bigger cells.
- Flat indexed cells only (Law #2): pressed = inverted block, selected = 1-cell accent
  border, disabled = 2×2 checker. No opacity/glass/blur/rounding on data or transport cells.
- 2D render unchanged: `PixelImage .interpolation(.none)`, square edge multiple-of-64.
- Transport is **static on the lattice** (Pass-A re-bake on discrete input), never animated
  by the 20fps clock; only the render surface animates (Pass B).
- Reduce-motion: the single clock freezes auto-advance globally (frame 0); scrub still
  allowed (discrete input). Verify cloud's "static streak" still composes from frame 0.

## Haskell spec — `SixFour.Spec.PlaybackClock` (Layers 0–2 + goldens)

Reuses the existing `Cyclic.hs` `(t+1) mod nt` idiom (`:236/252/324`).

- `monotonicModN`: `frameAfter N f == (f+1) mod N`
- `wrapAtBoundary`: `frameAfter N (N-1) == 0`
- `scrubClamped`: `clamp N i == max 0 (min (N-1) i)`
- `freezeIsFrameZero`: `reduceMotion ⇒ ∀k. iterate (frameAfter N) 0 !! k == 0`
- `twoViewsAgree`: `twoDFrame i == threeDFrontFace i` (front face z=63 ⇒ `i`)
- `paletteAtFrameDeterminism`: `paletteAt palettes (clamp N i)` pure total fn of `(palettes,i)`
- `analyzersAgreeWithPlayer`: grid/tree/cloud all index the same `clamp N i`
- `totalDefinedOnEmpty`: `N==0 ⇒ frame 0, empty palette`

Golden vectors pinned for `N=64` via Codegen → `Generated/PlaybackClockContract.swift`.

## Build order (serial — all steps re-touch `GIFReviewView.swift`)

1. **Spec gate:** `Spec/PlaybackClock.hs` + `test/PlaybackClockSpec.hs` (8 laws) green;
   Codegen emitter → `Generated/PlaybackClockContract.swift` golden vectors. Ships nothing.
2. **`PlaybackClock.swift`** (ObservableObject) ported bit-faithful from spec + Swift parity
   test against the contract. No UI consumer yet.
3. **`PlayerTransport.swift`** from 6pt Cell* primitives (PlayPause, ScrubRail≈unrolled
   CellRing ticks, FrameCounter via CellDigits/DigitGlyph). Standalone previewable. GRID lint.
4. **Refactor `GIFCanvas`** → render-only FLAT view reading `clock.frame` (drop Timer/
   startTimer). Build **`GIFPlayer.swift`** = {FLAT, CellSelector 2D/3D toggle, transport};
   CUBE hidden when `frameIndicesForVoxels == nil`. Wire `AppSettings.playerMode`.
5. **Refactor `VoxelCubeView`** → read `clock.frame`, drop internal 60Hz clock/tick/advance.
   Slot as CUBE render. Confirm `VoxelRestPoseIdentityTests` green.
6. **Swap `GIFReviewView`**: own `@StateObject PlaybackClock`, replace `GIFCanvas(:38)` with
   `GIFPlayer`, replace status `TimelineView(140-148)` with `clock.frame`, delete dead
   `GIFCanvas` struct (229-287). Milestone: unified player + synced status.
7. **Sync analyzers** (each shippable): Grid → Tree → Cloud (continuous), then AddressPicker
   + Quad4 (`.first` → `[clock.frame]`, rebuild on pause/scrub).
8. **Cleanup:** remove dead `frameIndex(at:rate:count:)` callers + redundant per-view
   reduce-motion guards; GRID lint + single-owner accessibility audit.

## Open items (decided defaults; revisit if needed)

- Cloud/Voxel "detach" mode for independent deep exploration: default = clock-synced,
  optional per-view detach toggle (deferred — not in first build).
- `CADisplayLink` vs `Timer.publish` for the advancer: pin BEFORE writing the golden so the
  parity test models the right mechanism. Default `Timer.publish(every: 1/20)` (already
  decimated; matches existing code; no tick-divider to model).

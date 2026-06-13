> **Status/built-state:** see [docs/STATUS.md](../STATUS.md) (canonical, gated by `scripts/verify-doc-claims.sh`). This document is design rationale, not a status ledger.

# SixFour — Interactive Control Audit

> Generated 2026-06-02 by the `sixfour-button-audit` workflow (18 UI files inventoried in parallel, then synthesized). Re-run that workflow to refresh.

**62 interactive controls** across the app. This document tracks every button/toggle/picker/gesture, groups them by function, and records the `2⁸/4⁴/16²` palette-address divergence plus its unification plan.

## 1. Full inventory (per file)

| Screen | File | # | Controls (line — label → action) |
|---|---|---|---|
| Capture | `CaptureView.swift` | 3 | `:119` **Settings (gear icon)** (Button) → showSettings = true<br>`:86` **Camera preview tap** (Gesture) → vm.focus(at:) and set reticle<br>`:175` **Shutter button** (Button) → vm.capture() burst |
| State | `CaptureViewModel.swift` | 0 | _(no controls — CaptureViewModel is a pure state container and business logic layer with no inte)_ |
| Review | `GIFReviewView.swift` | 13 | `:71` **RepresentationSelector** (Menu) → Mutates vm.settings.paletteRepresentation to select palette view mode (.structure/.grid/.c<br>`:80` **ScopeSelector** (Segment) → Mutates vm.settings.paletteScope to toggle between .perFrame and .global palette views<br>`:87` **BranchingSelector** (Menu) → Mutates vm.settings.paletteBranching to select tree branching factor (16^2 / 4^4 / 2^8)<br>`:91` **AddressPickerView** (Picker) → Multi-wheel address picker; mutates brushedIndex via Binding; address space radix determin<br>`:98` **Quad4DrillView** (Other) → 4^4 branching palette drill-down editor; mutates brushedIndex via Binding<br>`:101` **GlobalPaletteEditorView** (Other) → 16^2 or 2^8 branching global palette editor; mutates brushedIndex indirectly via GlobalPal<br>`:106` **PaletteGridView** (Other) → Displays 256 colours on user-assigned coordinate axes; read-only display (brushedIndex is <br>`:110` **GridAxisSelector** (Menu) → Mutates vm.settings.gridAxisX and vm.settings.gridAxisY to choose grid coordinate axes<br>`:118` **PaletteCloudView** (Other) → OKLab temporal cloud 3D projection view; mutates brushedIndex via Binding<br>`:128` **VoxelCubeView** (Other) → 64^3 (x,y,t) voxel cube view; mutates brushedIndex via Binding<br>`:203` **Share** (Button) → ShareLink(item: primary.gifURL) — exports/shares the rendered GIF<br>`:209` **Share contact sheet** (Button) → ShareLink(item: contact) — exports/shares contact sheet (conditional, only if primary.cont<br>`:216` **Retake** (Button) → Calls vm.reset() to restart capture |
| Settings | `SettingsView.swift` | 10 | `:35` **Done** (Button) → dismiss() — closes the Settings sheet<br>`:44` **Sampler** (Picker) → mutates $settings.defaultDitherMethod — selects between DitherMethod.allCases (determines <br>`:59` **Kernel** (Picker) → mutates $settings.ditherKernel — selects which kernel to use for error diffusion (shown on<br>`:63` **Serpentine scan** (Toggle) → mutates $settings.ditherSerpentine — enables/disables serpentine scan direction for error <br>`:76` **Temporal** (Picker) → mutates $settings.blueNoiseTemporal — selects temporal residual spectrum mode (shown only <br>`:92` **Deterministic core** (Toggle) → mutates $settings.useDeterministicCore — toggles between fixed-point integer pipeline vs G<br>`:107` **Palette structure** (Toggle) → mutates $settings.showPaletteTree — enables/disables display of median-cut SplitTree treem<br>`:109` **Branching** (Picker) → mutates $settings.paletteBranching — selects branching factor for viewing the palette tree<br>`:125` **Open in 64×64 preview** (Toggle) → mutates $settings.openInPixelatedPreview — toggles whether captures open in the pixelated <br>`:126` **Auto-save to Photos** (Toggle) → mutates $settings.autoSaveToPhotos — toggles automatic saving of captures to the Photos li |
| State | `StateScreens.swift` | 2 | `:21` **Open Settings** (Button) → openSettings() — opens iOS Settings via UIApplication.openSettingsURLString<br>`:61` **Try again** (Button) → onRetry closure — re-runs bootstrap after failure |
| Capture | `AddressPickerView.swift` | 1 | `:150` **Digit wheel (0..N-1)** (Picker) → updateDigit(index:value:) mutates selectedDigits[index], calls rebuildWheels(), sets brush |
| Capture | `Quad4DrillView.swift` | 2 | `:82` **quad cell** (Gesture) → onTapGesture calls descend(_:), which either appends to path (navigate deeper) or sets bru<br>`:114` **up** (Button) → path.removeLast(), navigates up one level in Quad4 tree |
| Capture | `PaletteGridView.swift` | 4 | `:110` **Representation selector buttons (structure/grid/cloud/cube)** (Segment) → updates @Binding var selection: PaletteRepresentation with snappy animation<br>`:137` **X axis menu** (Menu) → calls assign(_:toX:true) to update @Binding var xAxis: GridAxis, swaps with yAxis if colli<br>`:138` **Y axis menu** (Menu) → calls assign(_:toX:false) to update @Binding var yAxis: GridAxis, swaps with xAxis if coll<br>`:146` **Axis options in menu (grid axes)** (Button) → selects GridAxis value and calls onPick closure with snappy animation |
| Capture | `PaletteTreeView.swift` | 5 | `:97` **per-frame** (Button) → withAnimation { selection = .perFrame } — mutates @Binding PaletteScope<br>`:97` **global** (Button) → withAnimation { selection = .global } — mutates @Binding PaletteScope<br>`:125` **16²** (Button) → withAnimation { selection = .hex } — mutates @Binding PaletteBranching (sets to 16² branch<br>`:125` **4⁴** (Button) → withAnimation { selection = .quat } — mutates @Binding PaletteBranching (sets to 4⁴ branch<br>`:125` **2⁸** (Button) → withAnimation { selection = .bin } — mutates @Binding PaletteBranching (sets to 2⁸ branchi |
| Capture | `PaletteCloudView.swift` | 11 | `:249` **Snap to orthographic rest** (Button) → Sets yaw=0, pitch=0, projection=.orthographic with animation<br>`:447` **ortho** (Button) → Sets cloud.projection = .orthographic (inside ForEach loop over CloudProjection.allCases)<br>`:447` **explore** (Button) → Sets cloud.projection = .perspective (inside ForEach loop over CloudProjection.allCases)<br>`:474` **a×b** (Button) → Sets cloud.yaw=0, cloud.pitch=-.pi/2, cloud.projection=.orthographic (plane snap, inside F<br>`:474` **L×a** (Button) → Sets cloud.yaw=0, cloud.pitch=0, cloud.projection=.orthographic (plane snap, inside ForEac<br>`:474` **L×b** (Button) → Sets cloud.yaw=.pi/2, cloud.pitch=0, cloud.projection=.orthographic (plane snap, inside Fo<br>`:508` **Pause time or Play time** (Button) → Toggles cloud.playing boolean<br>`:513` **Trail length** (Button) → Cycles cloud.trail through off→short→long via cloud.trail.next extension<br>`:524` **Frame slider** (Slider) → Mutates cloud.frame via Binding (Int($0.rounded())) and sets cloud.playing=false on drag e<br>`:549` **Cloud canvas (orbit drag)** (Gesture) → DragGesture onChanged: mutates cloud.yaw and cloud.pitch based on translation with gain=0.<br>`:561` **Cloud canvas (dot tap brush)** (Gesture) → SpatialTapGesture onEnded: calls pickNearest(at:) to find front-most dot, mutates cloud.br |
| Capture | `GlobalPaletteEditorView.swift` | 8 | `:33` **BranchingSelector** (Picker) → mutates $branching binding (2^8, 4^4, or 16^2)<br>`:47` **Canvas tap gesture (palette treemap)** (Gesture) → calls path(at:size:) to compute selectedPath from tap location; highlights selected subtre<br>`:77` **grain** (Stepper) → mutates $grain state (0 to branching.depth); controls edit depth from root to leaf<br>`:89` **Lighter** (Button) → calls applyDelta(+0.05, 0, 0) to increase L channel of selected subtree<br>`:90` **Darker** (Button) → calls applyDelta(-0.05, 0, 0) to decrease L channel of selected subtree<br>`:91` **Warmer** (Button) → calls applyDelta(0, 0, +0.04) to increase b channel of selected subtree<br>`:92` **Cooler** (Button) → calls applyDelta(0, 0, -0.04) to decrease b channel of selected subtree<br>`:93` **Reset** (Button) → mutates current = baseline to undo all edits |
| Review | `VoxelCubeView.swift` | 11 | `:199` **Reset to flat 2D view** (Button) → Sets cube.yaw and cube.pitch to 0 with animation<br>`:221` **Play / Pause** (Button) → Toggles cube.playing boolean (controls 20fps frame advancement)<br>`:225` **Auto-rotate** (Button) → Toggles cube.autoRotate boolean (slow persistent yaw rotation)<br>`:263` **All** (Button) → Sets cube.provMode = 0 (shows all palette slots)<br>`:263` **Real** (Button) → Sets cube.provMode = 1 (shows extracted slots only)<br>`:263` **Split** (Button) → Sets cube.provMode = 2 (shows split slots only)<br>`:237` **Frame 1/64 slider** (Slider) → Mutates cube.frame (0-63), sets cube.playing = false when scrubbed<br>`:241` **Trail depth slider** (Slider) → Mutates cube.tLo (depth band start, 0-63), bounds to cube.tHi<br>`:245` **Air below luma slider** (Slider) → Mutates cube.lumaFloor (luminance threshold, 0-255)<br>`:184` **Voxel cube render surface (tap-to-pick)** (Gesture) → SpatialTapGesture: when cube.isFlat, reads voxel at tap location and sets brushedIndex (to<br>`:296` **Voxel cube render surface (orbit drag)** (Gesture) → DragGesture: mutates cube.yaw and cube.pitch (orbit rotation with 0.006 gain), clamps pitc |
| Shared/Component | `GlassControls.swift` | 1 | `:37` **systemImage (SF Symbol icon)** (Button) → calls action closure passed by caller |
| Capture | `PixelGrid.swift` | 0 | _(no controls — Pure rendering infrastructure for flat-cell indexed bitmap display and 256-colou)_ |
| Capture | `StatsFooterView.swift` | 0 | _(no controls — Read-only metrics display pill showing GIF extraction statistics (extractor, fil)_ |
| Capture | `CameraPreview.swift` | 1 | `:21` **tap gesture (camera focus tap)** (Gesture) → calls PreviewView.handleTap(_:) which invokes onTap callback with devicePoint and localPoi |
| Capture | `CellField.swift` | 0 | _(no controls — CellFieldView displays a full-screen tiled cell background using a Bayer-dithere)_ |
| Settings | `Theme.swift` | 0 | _(no controls — Design tokens and styling constants for SixFour UI—spacing, typography, colours,)_ |

## 2. Functional categories

### Capture actions
_Acquire imagery and fire the 64-frame burst on the live HUD._

- CaptureView.swift:175 — Shutter button (vm.capture() burst)
- CaptureView.swift:86 — Camera preview tap (vm.focus + reticle)
- CameraPreview.swift:21 — tap gesture (camera focus tap)

### Navigation / sheet entry
_Open and dismiss the secondary surfaces (settings, system fallbacks)._

- CaptureView.swift:119 — Settings gear (showSettings = true)
- SettingsView.swift:35 — Done (dismiss)
- StateScreens.swift:21 — Open Settings (UIApplication settings URL)
- StateScreens.swift:61 — Try again (onRetry bootstrap)
- GlassControls.swift:37 — systemImage glass button primitive (caller action)

### Palette representation mode switch
_Pick WHICH of the four 256-colour views renders (structure/grid/cloud/voxel3D) and whether the palette is per-frame or global — meta-selectors above the address widgets._

- GIFReviewView.swift:71 — RepresentationSelector
- PaletteGridView.swift:110 — Representation selector buttons (structure/grid/cloud/cube)
- GIFReviewView.swift:80 — ScopeSelector (perFrame/global)
- PaletteTreeView.swift:97 — per-frame / global scope buttons

### Palette-address navigation (the radix family)
_Address one of the 256 leaves of the SAME median-cut SplitTree and brush it across views (shared brushedIndex). Each control hardwires a different radix factorization of the 256-leaf address._

- GIFReviewView.swift:87 — BranchingSelector (sets radix 16²/4⁴/2⁸)
- PaletteTreeView.swift:125 — 16²/4⁴/2⁸ branching buttons
- SettingsView.swift:109 — Branching picker (PaletteBranching.allCases)
- GlobalPaletteEditorView.swift:33 — in-editor BranchingSelector
- AddressPickerView.swift:150 — Digit wheel 0..N-1 (N=branching.depth radix digits → leafIndexForAddress)
- GIFReviewView.swift:91 — AddressPickerView mount
- Quad4DrillView.swift:82 — quad cell tap (descend, 4⁴ opponent quadrants → leaf)
- Quad4DrillView.swift:114 — up (path.removeLast)
- GIFReviewView.swift:98 — Quad4DrillView mount (only when branching==.b4)
- GIFReviewView.swift:101 — GlobalPaletteEditorView mount (16²/2⁸ fallback)
- GlobalPaletteEditorView.swift:47 — treemap tap (path(at:size:) selects subtree)
- GlobalPaletteEditorView.swift:77 — grain stepper (edit depth 0..branching.depth)
- PaletteGridView.swift:137 — X axis menu (16² axis assign)
- PaletteGridView.swift:138 — Y axis menu (16² axis assign)
- PaletteGridView.swift:146 — axis option buttons
- GIFReviewView.swift:110 — GridAxisSelector mount
- AddressPickerView.swift:150 — (radix-N digit wheels, see above)

### Palette colour editing (nudge)
_Mutate the OKLab values of the selected subtree in the global editor._

- GlobalPaletteEditorView.swift:89 — Lighter (+L)
- GlobalPaletteEditorView.swift:90 — Darker (−L)
- GlobalPaletteEditorView.swift:91 — Warmer (+b)
- GlobalPaletteEditorView.swift:92 — Cooler (−b)
- GlobalPaletteEditorView.swift:93 — Reset (current = baseline)

### Cloud 3D view controls
_Orbit/scrub/style the OKLab temporal cloud projection and brush dots._

- PaletteCloudView.swift:249 — Snap to orthographic rest
- PaletteCloudView.swift:447 — ortho
- PaletteCloudView.swift:447 — explore (perspective)
- PaletteCloudView.swift:474 — a×b plane snap
- PaletteCloudView.swift:474 — L×a plane snap
- PaletteCloudView.swift:474 — L×b plane snap
- PaletteCloudView.swift:508 — Pause/Play time
- PaletteCloudView.swift:513 — Trail length cycle
- PaletteCloudView.swift:524 — Frame slider
- PaletteCloudView.swift:549 — Cloud canvas orbit drag
- PaletteCloudView.swift:561 — Cloud canvas dot tap brush (sets brushedIndex)

### Voxel-cube 3D view controls
_Orbit/scrub/filter the 64³ (x,y,t) voxel cube and tap-pick a slot._

- VoxelCubeView.swift:199 — Reset to flat 2D view
- VoxelCubeView.swift:221 — Play / Pause
- VoxelCubeView.swift:225 — Auto-rotate
- VoxelCubeView.swift:263 — All (provMode 0)
- VoxelCubeView.swift:263 — Real (provMode 1)
- VoxelCubeView.swift:263 — Split (provMode 2)
- VoxelCubeView.swift:237 — Frame slider
- VoxelCubeView.swift:241 — Trail depth slider
- VoxelCubeView.swift:245 — Air below luma slider
- VoxelCubeView.swift:184 — render surface tap-to-pick (sets brushedIndex)
- VoxelCubeView.swift:296 — render surface orbit drag

### Sampler / dither settings
_Configure the residual-shaping sampler (error diffusion vs blue noise) and render engine._

- SettingsView.swift:44 — Sampler picker (DitherMethod)
- SettingsView.swift:59 — Kernel picker (error-diffusion only)
- SettingsView.swift:63 — Serpentine scan toggle
- SettingsView.swift:76 — Temporal picker (blue-noise only)
- SettingsView.swift:92 — Deterministic core toggle
- SettingsView.swift:107 — Palette structure toggle (showPaletteTree)

### Capture preferences
_Post-capture behaviour toggles._

- SettingsView.swift:125 — Open in 64×64 preview toggle
- SettingsView.swift:126 — Auto-save to Photos toggle

### Export / share / lifecycle
_Emit the rendered GIF/contact sheet or restart capture._

- GIFReviewView.swift:203 — Share (ShareLink gifURL)
- GIFReviewView.swift:209 — Share contact sheet (ShareLink contact)
- GIFReviewView.swift:216 — Retake (vm.reset)

## 3. The 2⁸ / 4⁴ / 16² divergence

**Shared concept.** There is ONE object: the 256-leaf median-cut SplitTree (built once per frame, `PaletteTreeView.tree(for:)`), whose leaves are exactly the 256 palette slots, addressed by IndexedColor.index and brushed app-wide via a single `brushedIndex: Int?` binding. PaletteBranching (.b16/.b4/.b2 → 16²/4⁴/2⁸) is purely a RADIX/grouping choice over that same address: 256 = 16² = 4⁴ = 2⁸, so depth=branching.depth digits in base=branching.factor index the identical leaf set (AddressPickerView's `leafIndexForAddress(selectedDigits, tree:)`, GlobalPaletteEditorView grain 0..branching.depth). The radix changes only how the address is chunked, never what is addressed.

**One concept, four widgets:**

- **All radices (the meta-selector that SHOULD drive one widget but instead fans out)** — `PaletteTreeView.swift:125 BranchingSelector / duplicated at GIFReviewView.swift:87, SettingsView.swift:109, GlobalPaletteEditorView.swift:33`
  - Same PaletteBranching binding exposed four times. In GIFReviewView.swift:84-102 its value is used as a DISPATCH SWITCH that routes each radix to a DIFFERENT child widget instead of parameterizing one widget — this dispatch IS the divergence engine.
- **2⁸ (.b2)** — `AddressPickerView.swift:150 (N-wheel digit picker), mounted GIFReviewView.swift:91`
  - Models the address as N=depth ordered radix digits on horizontal wheels, each wheel labelled with the real (SplitAxis,pos) split read from the tree (AddressPickerView.swift:7-9). It is the ONLY widget that is genuinely radix-parameterized (N = branching.depth: 2/4/8 wheels), so it already generalizes across all three radices — yet it is mounted only in the per-frame structure branch, alongside the others rather than replacing them.
- **4⁴ (.b4)** — `Quad4DrillView.swift:82 quad-cell tap + :114 up button, mounted GIFReviewView.swift:97-99 (ONLY when branching==.b4)`
  - A bespoke 2×2 opponent-quadrant DRILL: descends one level per tap through `parent ± δ₁ ± δ₂` Hering quadrants in fixed (++),(+−),(−+),(−−) order with a breadcrumb/up-stack. It hardwires factor=4 into the UI geometry (2×2 grid) and builds its OWN tree (`Quad4.analyze`, Quad4DrillView.swift:36), a SEPARATE structure from the canonical SplitTree the other widgets share — the deepest divergence.
- **16² (.b16)** — `PaletteGridView.swift:137-146 X/Y axis menus + GridAxisSelector, mounted GIFReviewView.swift:106-112; AND GlobalPaletteEditorView.swift:47 treemap tap (16²/2⁸ fallback, GIFReviewView.swift:101)`
  - 16² is exposed TWO incompatible ways: (a) as a 16×16 coordinate GRID on user-assigned axes (read-only brush, addresses by (x,y) cell), and (b) when scope=global, as a treemap-tap subtree selector in GlobalPaletteEditorView with a grain stepper. Neither uses the wheel/digit address model; the grid even treats brushedIndex as read-only (PaletteGridView mount, GIFReviewView.swift:109).

**Why they diverged.** Each radix was given a widget that flatters its FACTOR rather than the shared tree: 4⁴ got an opponent-quadrant story (2×2 Hering), 16² got a square 16×16 coordinate grid, 2⁸ got the binary wheel address — three different mental models bolted onto one address space. Compounding it, GIFReviewView.swift:84-102 ALSO splits on scope (perFrame vs global), and the global branch hardcodes `if branching==.b4 { Quad4 } else { GlobalPaletteEditor }`, so the radix selector became a routing switch across heterogeneous widgets. They drifted because no single control consumed `branching` as a parameter; AddressPickerView (which already does, N=depth wheels) was added LATER and placed beside the legacy widgets instead of subsuming them, and Quad4DrillView even builds its own non-canonical tree.

## 4. Unification proposal (ranked)

### Step 1. Adopt AddressPickerView as the single canonical radix-parameterized address control and make it the ONLY palette-address navigator in the per-frame structure branch. It already takes `branching: PaletteBranching` and renders N=branching.depth wheels over the canonical SplitTree, brushing via leafIndexForAddress → brushedIndex (AddressPickerView.swift:18,150). Delete the Quad4 and grid-as-address mounts from the dispatch.
_Rationale:_ One widget that consumes the radix as a parameter is exactly the target; AddressPickerView is the only existing control that is already radix-general and tree-canonical, so unification means promoting it, not writing new code. Eliminates the GIFReviewView.swift:97-101 `if branching==.b4 … else …` dispatch fork.

_Files:_ `GIFReviewView.swift`, `AddressPickerView.swift`

### Step 2. Fold the Quad4 opponent-quadrant story into AddressPickerView as a per-wheel RENDER STYLE (when factor==4, draw each wheel/level as a 2×2 ±δ₁±δ₂ pad) instead of a separate widget that builds its own Quad4.analyze tree. Drive it off the canonical SplitTree so 4⁴ addresses the same 256 leaves as the others.
_Rationale:_ Removes the only widget that forks the underlying data model (Quad4DrillView.swift:36 builds a parallel tree), which is the deepest source of drift; the Hering-quadrant affordance survives as presentation, not a second address space.

_Files:_ `Quad4DrillView.swift`, `AddressPickerView.swift`, `GIFReviewView.swift`

### Step 3. Demote the 16×16 grid to a pure VISUALIZATION (PaletteGridView already takes brushedIndex read-only, GIFReviewView.swift:106-109) under the .grid representation only, and stop treating GridAxisSelector / X-Y menus as a radix-address control. The .b16 case in the structure branch is then served by the unified AddressPickerView like every other radix.
_Rationale:_ 16² is currently exposed as BOTH a coordinate grid and a treemap editor; keeping the grid strictly as a 256-view (the StructuredOutput 'other-256-view' tag it already carries) removes its overlap with addressing and leaves one address path.

_Files:_ `PaletteGridView.swift`, `GIFReviewView.swift`

### Step 4. Collapse the four BranchingSelector mounts to ONE source of truth. Keep the selector in the Review structure chrome bound to vm.settings.paletteBranching; remove the in-editor copy (GlobalPaletteEditorView.swift:33) and the Settings copy (SettingsView.swift:109), or make Settings merely a default that the live selector overrides.
_Rationale:_ Three live mutators of the same PaletteBranching binding (PaletteTreeView.swift:125, GIFReviewView.swift:87, GlobalPaletteEditorView.swift:33) plus a Settings default invite inconsistent state; one selector feeding the unified address widget is the whole point.

_Files:_ `PaletteTreeView.swift`, `GlobalPaletteEditorView.swift`, `SettingsView.swift`, `GIFReviewView.swift`

### Step 5. Separate ADDRESSING from EDITING: keep GlobalPaletteEditorView's nudge buttons (Lighter/Darker/Warmer/Cooler/Reset, :89-93) but have them act on whatever subtree the unified AddressPickerView selected (brushedIndex + grain depth), rather than the editor owning its own treemap-tap selection (:47) and its own BranchingSelector. Editing becomes a verb applied to the one selection, not a parallel navigator.
_Rationale:_ The editor currently re-implements address selection (treemap tap + grain + branching) just to host four nudge buttons; routing the nudges through the shared brushedIndex/grain decouples the (valuable) edit verbs from the (duplicated) navigation.

_Files:_ `GlobalPaletteEditorView.swift`, `AddressPickerView.swift`, `GIFReviewView.swift`

## 5. Other duplications worth collapsing

- BranchingSelector is instantiated FOUR times for the same PaletteBranching binding: PaletteTreeView.swift:125, GIFReviewView.swift:87, GlobalPaletteEditorView.swift:33, and SettingsView.swift:109. Collapse to one live control plus an optional Settings default.
- RepresentationSelector is duplicated: defined/mounted in GIFReviewView.swift:71 and again as 'Representation selector buttons' in PaletteGridView.swift:110 — two controls mutating the same PaletteRepresentation. Keep one.
- ScopeSelector exists twice for the same PaletteScope: GIFReviewView.swift:80 and PaletteTreeView.swift:97 (per-frame/global buttons). Unify.
- The three 3D/2D view controllers (PaletteCloudView, VoxelCubeView, and to a lesser extent Quad4DrillView) each re-implement near-identical orbit/scrub chrome: orbit DragGesture with pitch clamp ±1.5 (PaletteCloudView.swift:549 gain 0.007 vs VoxelCubeView.swift:296 gain 0.006), a rest/flatten button (PaletteCloudView.swift:249 vs VoxelCubeView.swift:199), play/pause (PaletteCloudView.swift:508 vs VoxelCubeView.swift:221), and a Frame slider (PaletteCloudView.swift:524 vs VoxelCubeView.swift:237). Extract a shared OrbitScrubChrome/gesture modifier.
- Tap-to-brush is reimplemented per view: PaletteCloudView.swift:561 pickNearest, VoxelCubeView.swift:184 voxel pick, AddressPickerView digit→leaf, Quad4DrillView descend-to-leaf, GlobalPaletteEditorView treemap path — all ultimately set the same brushedIndex. A single 'BrushTarget'/hit-test protocol would unify them.
- Plane-snap presets in PaletteCloudView (a×b, L×a, L×b at :474) carry paletteAddressRadix tags (4^4/16^2) yet are pure camera presets, not addressing — mislabeled overlap with the radix family that should be untangled when unifying.

# SixFour — Unified GIF Representation Design

> Generated 2026-06-02 by the `sixfour-representation-unify` workflow (7 parallel subsystem readers → synthesis). DESIGN ONLY — no code changed. Re-run the workflow to refresh.

## 0. The one-line model

> **The GIF is ONE (x,y,t) cube of palette indices, projected honestly to 2D; the palette is a separate factor with two knobs (scope, radix). The two factors meet only at the reconstruction law.**

## 0.1 Decision — FULL COLLAPSE TO ONE SURFACE (2026-06-02)

**Chosen architecture.** The Review screen has exactly **one primary surface: the index cube**, whose **rest pose IS the 2D GIF**. There is no separate "GIF hero bitmap" and no separate "voxel3D mode" — they are the same surface at two orbit states:

```
        rest pose (yaw=pitch=0)            orbit (drag)
        ┌───────────────┐                  ┌───────────────┐
        │  2D GIF        │   ── drag ──▶    │   ╱cube╱       │  prior frames
        │  (front face,  │   ◀─ release ─   │  ╱  t  ╱       │  extrude back
        │   z=63=cursor) │                  │ ╱_____╱        │  as depth = time
        └───────────────┘                  └───────────────┘
   default; pixel-identical to            same surface, depth cues on
   the encoded GIF (RULE-CUBE-2D-IDENTITY)
```

What this commits us to (and therefore what the rest of this doc must serve):
- **Retire the ImageIO bitmap hero.** The displayed 2D is the cube front-projection driven by the *live* index map + palette via the reconstruction law — not a re-decoded `.gif`. (Closes conflation #5 / blocking gap #4.)
- **`voxel3D` is no longer a `RepresentationSelector` peer.** Orbit *is* the 3D view; the selector that remains is the **palette panel** (scope + radix), which is the *other* factor. The index surface has no "modes" — only an orbit pose.
- **The index map becomes load-bearing, so it cannot be optional.** With no bitmap fallback, `frameIndicesForVoxels` must be populated on every real path and persisted (blocking gaps #1–2 are now *hard prerequisites*, not nice-to-haves).
- **One clock.** A single cursor drives both which `t` is the front slice and the palette playhead (blocking gap #6).

**Status: DESIGN — refining before any spec/Swift code.** Open sub-decisions this collapse raises are tracked in §9.

## 1. Canonical model

A SixFour GIF is ONE object: a 64x64x64 (x,y,t) voxel cube of palette INDICES — the index map (frameIndicesForVoxels: [[UInt8]], 64 frames x 4096 px, row-major y*64+x, CaptureViewModel.swift:46-52; spec IndexTensor in Indices.hs:38-42). That cube is the source of truth. It is shown HONESTLY by FRONT-PROJECTING it down the t axis onto the 2D screen (the looping GIF hero / VoxelCubeView rest pose, VoxelCubeView.swift:11-23). The PALETTE is a SEPARATE orthogonal factor — palettesForDisplay: [[SIMD3<UInt8>]] 64x256 (CaptureViewModel.swift:17-19) — running one continuous SCOPE axis (per-frame -> global, PaletteTreeView.swift:83-86, Collapse.hs:22-114). The radix factorizations 2^8/4^4/16^2 are VIEWS of that palette factor only (one canonical SplitTree, SplitTree.swift:37-61, SplitTree.hs:52-77), never of the index map. The two factors meet ONLY at the reconstruction law; everything else is an orthogonal projection of one factor or the other.

### Orthogonal factors

**INDEX MAP (x,y,t cube of slot ids)**
- _truth:_ frameIndicesForVoxels: [[UInt8]] 64x4096 row-major y*64+x, top-left origin; spec IndexTensor t h w k as flat U.Vector Int in [0,K-1] (Indices.hs:38-57); validated per-frame surjective by CompleteVoxelVolume (Indices.hs:59-99, StageContract.swift:44-66)
- _views:_ 2D GIF hero = front projection (GIFReviewView.swift:38 GIFCanvas -> PixelImage interpolation .none, PixelGrid.swift:39-57); VoxelCubeView 64^3 Metal raymarch: rest pose = front projection, orbit reveals t-as-depth (VoxelCubeView.swift:1-50,402-431; Shaders.metal:548-651)

**PALETTE (slot id -> colour) along the per-frame->global SCOPE axis** _(see §9.1 correction: scope swaps a whole render, not just colours)_
- _truth:_ palettesForDisplay: [[SIMD3<UInt8>]] 64x256 sRGB (CaptureViewModel.swift:17-19, GIFRenderer.swift:162-164); per-frame is NN input, global is one 256-table via farthestPointCollapse maximin (Collapse.hs:22-114, PaletteCollapse.swift:13-112) — **and carries its OWN index map** (`g.frameIndices`, CaptureViewModel.swift:528-551; whole-GIF significance rescue, DeterministicRenderer.swift:320-339), so per-frame↔global is a render swap. Scope is PaletteScope {perFrame|global} (PaletteTreeView.swift:83-86, AppSettings.swift:34,117-119)
- _views:_ PaletteTreeView median-cut treemap (SplitTree.swift:63-123); PaletteGridView 16x16 axis layout — PALETTE-coordinate plane, NOT the index plane (GridAxis.hs:1-37, PaletteGridView.swift:15-78); PaletteCloudView OKLab 3D cloud (CloudProjection.hs:1-200); AddressPickerView 2^8 / Quad4DrillView 4^4 / treemap 16^2 radix views (AddressPickerView.swift:4-48, Quad4DrillView.swift:4-93, PaletteBranching SplitTree.swift:37-61); GlobalPaletteEditorView global-scope editor (GlobalPaletteEditorView.swift:1-176)

**VIEW / PROJECTION (3D->2D geometry + orbit pose)**
- _truth:_ orthographic isometry pinned in CloudProjection.hs:20-46 (lawWorldIsometry, lawRotationIsometry, lawOrthographicInPlaneExact, lawPerspectiveDistorts); VoxelCube orbit (yaw,pitch) fixed halfSpan=32 (VoxelCubeView.swift:93-109, Shaders.metal:548-587). NO data — pure geometry over the index cube and the OKLab cloud
- _views:_ VoxelCubeView orbit pose; PaletteCloudView orbit / plane-snap / playhead

### Reconstruction law (the only place the factors meet)

```
pixel(x,y,t) = palettesForDisplay[t][ frameIndicesForVoxels[t][y*64 + x] ] — the single law joining the two orthogonal factors, already canonical at CaptureViewModel.swift:48 and VoxelCubeView.swift:48. The INDEX MAP supplies the slot id; the PALETTE (at whatever scope) supplies the colour for that slot. No view may bypass this law: every surface either projects the index cube (factors INDEX MAP + VIEW) or recolours/relays the palette (factor PALETTE).
```

## 2. Projection contract (2D = front of 3D)

2D PRIMARY SURFACE = the honest FRONT PROJECTION of the 3D index cube down the t axis. Definition of FRONT (rest pose): at yaw=pitch=0 the cube renders ORTHOGRAPHICALLY (no foreshortening) with fixed halfSpan=32 so one voxel = one GIF cell = gifCellPt (VoxelCubeView.swift:20-28). The front slice is z=63 (nearest camera), mapped to the current frame by f(z)=(cursor-63+z) mod 64 so z=63 -> frame=cursor (VoxelCubeView.swift:18-19, Shaders.metal:622). At rest the near face is pixel-identical to the 2D GIF hero (RULE-CUBE-2D-IDENTITY, VoxelCubeView.swift:11-23, VoxelRestPoseIdentityTests.swift:6-100). 'Collapsed' means SELECTED-SLICE not summed: the front projection shows frame t=cursor, and the playhead scrubs which t is front (the loop animates cursor). All depth cues (air cull, provenance filter, split darkening, face shading, brush dimming) are FLAT-GATED off at rest (isFlat = orbitMagnitude<0.001, Shaders.metal:606-651) so rest pose is provably the bare 2D GIF. ORBIT reveals 3D: nonzero (yaw,pitch) rotates the camera basis (voxelOrbit, Shaders.metal:548-587), prior frames extrude backward as depth=time, gated depth cues switch on. 2D IS the rest pose of the single 3D surface — not a separate widget; today the GIF hero is a separate ImageIO bitmap (GIFReviewView.swift:38,229-287) and the cube is an optional RepresentationSelector mode (GIFReviewView.swift:123-130); consolidation collapses these into ONE surface whose rest pose is the 2D GIF.

## 3. Palette unification (per-frame→global + 2⁸/4⁴/16²)

> ⚠️ **Superseded in part by §9.1.** The "scope never moves a pixel / 1:1 slot bijection" claim below is **false** against the renderer: per-frame and global are two complete renders with *different* index maps. Read §9.1 "MODEL CORRECTION" first; the radix-views half of this section stands.

Per-frame -> global becomes ONE continuous SCOPE axis, today the discrete PaletteScope enum {perFrame|global} (PaletteTreeView.swift:83-86, persisted AppSettings.swift:34,117-119). Truth: per-frame = 64 independent 256-tables (NN input); global = ONE 256-table from farthestPointCollapse maximin OKLab floor (Q16 byte-exact globalCollapseQ16, Collapse.hs:84-114, PaletteCollapse.swift:33-112). Scope is a slider/selector on the PALETTE factor alone; it never touches the index map (slot ids invariant — only the colour each slot resolves to changes; global reindexing maps slots 1:1, DeterministicRenderer.swift:336-339). The radix selector 2^8/4^4/16^2 is a SECOND, orthogonal control on the SAME palette factor: all three are VIEWS of the ONE canonical binary SplitTree obtained by collapsing k binary levels into one factor^depth=256 level (PaletteBranching b16/b4/b2, SplitTree.swift:37-61, SplitTree.hs:52-77; AddressPicker radix digit<->leaf round-trip, AddressPicker.hs:20-41). The exponent in 2^8 is TREE DEPTH, not data dimensionality (SplitTree.swift:49-59). Radix views attach to leaves of the palette tree (IndexedColor.index = palette slot), NEVER to pixels. Scope (per-frame<->global) and radix (2^8/4^4/16^2) are two independent knobs on the palette factor; the index map has neither.

## 4. Conflations the unified model MUST keep apart

- INDEX-MAP 2D plane vs PALETTE-LAYOUT 2D plane: the (x,y) front projection places PIXELS (each cell addresses a slot via frameIndices[t][y*64+x]); GridAxis places 256 COLOURS by user-assigned OKLab axes (GridAxis.hs:1-37, PaletteGridView.swift:15-78). Both look like 16x16-ish grids but mean utterly different things — image-space vs palette-coordinate-space. The unification must keep these as projections of DIFFERENT factors.
- RADIX (2^8/4^4/16^2) as data dimensionality vs as palette tree-depth VIEW: 2^8 is 8 binary tree levels over 256 leaves, not 8 data axes (SplitTree.swift:49-59, SIXFOUR-HIGHDIM-UIUX.md:9-19). Radix attaches to palette leaves only, never to the index map.
- SplitTree (renderer median-cut, 256 leaves, lo/hi half-sets) vs PairTree/Quad4 (NN sigma-genome, 128 mirror parent+/-delta pairs, 768/384 DOF): distinct objects; SplitTree has no parent+/-delta mirror semantics and mean-of-leaves != root (SplitTree.hs:1-30, palette-explorer doc). Quad4 is a LOSSY 513-DOF opponent-quadrant VIEW of PairTree (Quad4.hs:1-60), never drawn as lossless on SplitTree.
- SCOPE (per-frame->global colour ownership) vs PROJECTION (front-vs-orbit geometry): both are loosely called 'collapse'. Scope collapses 64 palettes -> 1 table (Collapse.hs); projection collapses the t-axis to a front slice (VoxelCubeView f(z)). Orthogonal — keep distinct names.
- DISPLAYED GIF bitmap (ImageIO CGImageSource decode, GIFReviewView.swift:229-287) vs the index cube it was encoded from (frameIndicesForVoxels). The hero is currently a re-decoded bitmap, NOT a projection of the live index map — a seam the unified surface must close so the hero IS the cube's rest pose.

## 5. Blocking gaps (close before the unified surface can exist)

- frameIndicesForVoxels is OPTIONAL and nil on legacy/synthetic outputs, so voxel3D is hidden (CaptureViewModel.swift:52 default nil; guard GIFReviewView.swift:74-76; VoxelCubeData init? returns nil VoxelCubeView.swift:62-64). A surface whose rest pose IS the projection cannot tolerate a nil index map — retire the bitmap fallback or make the index map non-optional on all real paths.
- frameIndicesForVoxels is NOT persisted in CaptureBundle (only tiles + perFrameStatistics saved); reloading a bundle requires re-dithering to regenerate indices (data-spine tracer gap). The cube cannot be reconstructed offline without re-render — blocks a re-openable unified surface.
- No per-pixel index buffer is bridged to the PALETTE views: brushing a palette slot cannot yet highlight the GIF PIXELS that use it because frameIndicesForVoxels reaches ONLY VoxelCube, not PaletteGridView/Cloud (highdim audit gap). The index-map<->palette link (the reconstruction law made interactive) is unplumbed.
- The 2D GIF hero is a re-decoded ImageIO bitmap (GIFReviewView.swift:229-287) DISCONNECTED from the live index cube; it is not the front projection of frameIndicesForVoxels. Until the hero is driven by the cube, '2D = rest pose of 3D' is aspirational, not actual.
- No codegen/golden contract unifies the projections: CloudProjection pins 3D->2D for the cloud (CloudProjection.hs) but GridAxis and the branching views are law-checked only, not golden-tested, and there is NO module declaring the index cube's front-projection contract (spec-contract analyst gap). VoxelRestPoseIdentity is a Swift-only test (VoxelRestPoseIdentityTests.swift) with no Haskell golden behind it.
- ONE-clock not unified: GIFCanvas + PaletteTreeView + PaletteGridView + VoxelCubeView + PaletteCloudView each subscribe to the per-frame clock independently (grid-is-the-render-surface.md:97); the front cursor (which t is projected) is not a single shared driver, so hero and cube can phase-drift.

## 6. Spec-first plan (Haskell source-of-truth, golden-gated — per CLAUDE.md)

### S1. Add Spec/FrontProjection.hs pinning the index-cube front-projection law frontSlice(cube,cursor)(x,y)=cube[cursor][y*64+x] with f(z)=(cursor-63+z) mod 64, plus the rest-pose identity theorem (orthographic, halfSpan=32, one voxel=one cell). State lawFrontIsCurrentFrame and lawRestPoseEqualsGifFrame so 2D=front-projection-of-3D is PROVED, not just a Swift test.
- **module:** `SixFour.Spec.FrontProjection (new; consumes Indices.IndexTensor)`
- **golden:** T=2,H=W=2,K=4 IndexTensor + cursor asserting frontSlice equals frame[cursor] byte-for-byte; pinned via Codegen.Golden into a Swift parity test replacing ad-hoc VoxelRestPoseIdentity assertions.
- **why:** The keystone claim '2D is the honest front projection of the 3D index cube' has NO Haskell source of truth today — only VoxelRestPoseIdentityTests.swift. CLAUDE.md demands spec-first with golden gating before Swift.

### S2. Extend Spec/Indices.hs with the explicit (x,y,t)->slot accessor and a ProjectionAxis tag {FrontT,SliceY,SliceX} so the cube's three orthogonal slicings are named and the t-axis front projection is distinguished from y/x slices. Keep CompleteVoxelVolume as the gate.
- **module:** `SixFour.Spec.Indices (extend)`
- **golden:** idx(f,y,x) round-trip for (f*h+y)*w+x against a hand-computed table; extend the existing Indices golden.
- **why:** Indices.hs owns the cube (Indices.hs:38-57) only as a flat tensor; projection axes must be first-class so the unified surface's orbit/slice ops have a verified vocabulary.

### S3. Add Spec/PaletteScope.hs (or extend Collapse.hs) declaring scope as a continuous axis with the law that the index map is INVARIANT under scope change — only the colour resolved per slot changes, and global reindexing is a slot bijection.
- **module:** `SixFour.Spec.PaletteScope (new; wraps Collapse.farthestPointCollapse)`
- **golden:** A per-frame index map + two scopes asserting frameIndices identical and only the palette table differs (global table = farthestPointCollapse of the 64).
- **why:** Scope-vs-projection conflate as 'collapse'; the spec must prove scope touches only the palette factor. Collapse.hs:22-114 has the maximin; the missing law is index-map invariance under scope.

### S4. Add Spec/RadixView.hs unifying GridAxis + SplitTree branching + AddressPicker + Quad4 as VIEWS OF THE PALETTE FACTOR, with lawRadixNeverTouchesIndexMap (radix digits address leaves=palette slots, never pixels) and lawBranchingArithmetic factor^depth=256. Cross-reference that GridAxis is palette-coordinate space, distinct from the index plane.
- **module:** `SixFour.Spec.RadixView (new; consumes SplitTree, GridAxis, AddressPicker, Quad4)`
- **golden:** An AddressPicker radix address round-trips to a leaf index (reuse AddressPicker.hs:20-41) PLUS a typed-distinctness golden asserting the address space carries no pixel coordinate.
- **why:** The spec-contract analyst flagged the views are proven internally but DISCONNECTED; this module is the missing seam declaring all radix/grid views attach to palette leaves only — separating the index-map plane from the palette-layout plane (the user's CRITICAL distinction).

### S5. Extend Spec/CloudProjection.hs to cover the index-cube orbit (not just the OKLab cloud): reuse rotateYawPitch + orthographic for the voxel cube so ONE projection geometry serves both the index cube and the OKLab cloud orbits, with halfSpan=32 fixed-scale as the rest-pose pin.
- **module:** `SixFour.Spec.CloudProjection (extend)`
- **golden:** Yaw/pitch rotation of a unit cube corner matches the Metal voxelOrbit basis to fixed precision; pin via Codegen.Golden as a cross-check vector for Shaders.metal:548-587.
- **why:** CloudProjection.hs:20-46 already pins isometry+orthographic+perspective-distorts; the voxel cube re-implements orbit in Metal with no Haskell behind it. Sharing the proven geometry unifies the VIEW factor.

## 7. Swift consolidation (follows the spec)

### C1. Make the GIF hero the FRONT PROJECTION of the live index cube: drive GIFCanvas from frameIndicesForVoxels + palettesForDisplay via the reconstruction law (CaptureViewModel.swift:48) at cursor=front-frame, instead of re-decoding the ImageIO bitmap. The hero becomes VoxelCubeView at rest pose (isFlat) — one surface, 2D by default.
- **files:** `GIFReviewView.swift:38,229-287`, `VoxelCubeView.swift:11-50`, `PixelGrid.swift:39-57`
- **why:** Closes the seam where the hero bitmap is disconnected from the index cube; makes '2D = rest pose of 3D' actual. Gated by Spec.FrontProjection golden.

### C2. Make frameIndicesForVoxels non-optional on the unified surface: populate it on every real render (already done GPU+deterministic, CaptureViewModel.swift:383,461,551) and retire the nil-guard that hides voxel mode (GIFReviewView.swift:74-76). Persist it in CaptureBundle so reload reconstructs the cube without re-dithering.
- **files:** `CaptureViewModel.swift:46-52,383,461,551`, `GIFReviewView.swift:74-76`, `VoxelCubeView.swift:62-64`
- **why:** A rest-pose-is-projection surface cannot fall back to a bitmap when the index map is nil; persistence makes the cube re-openable (blocking gaps 1-2).

### C3. Collapse RepresentationSelector so voxel3D is NOT a peer mode but the orbit-state of the primary surface: rest=2D GIF, orbit=3D cube. Keep .structure/.grid/.cloud as PALETTE-factor views in a SEPARATE selector. This enforces factor orthogonality in the UI (index surface vs palette surface are different panels).
- **files:** `GIFReviewView.swift:71-132`
- **why:** Today voxel3D sits beside palette views in one RepresentationSelector, conflating the index-cube surface with palette-layout surfaces. Splitting them realizes the canonical model's two-factor split.

### C4. Bridge the index map to palette views for brushing-through-the-law: when brushedIndex (a palette slot) is set, highlight the GIF PIXELS using it by reading frameIndicesForVoxels in PaletteGridView/Cloud/hero — the interactive reconstruction law. Drive scope (per-frame/global) and radix (2^8/4^4/16^2) as two orthogonal palette-factor knobs only.
- **files:** `GIFReviewView.swift:15-17,84-122`, `PaletteGridView.swift:20-23,68-77`, `PaletteTreeView.swift:83-112`
- **why:** brushedIndex is shared (P1) but the index map reaches only VoxelCube; bridging it makes slot<->pixel a live link without conflating the two 2D planes. Gated by Spec.RadixView + Spec.PaletteScope goldens.

### C5. Unify to ONE clock/cursor driver: a single parent TimelineView feeds the front-frame cursor to the hero/cube AND the playhead to the palette views, so the projected t-slice and the palette-frame are phase-locked.
- **files:** `GIFReviewView.swift:30-57`, `VoxelCubeView.swift:90-130`
- **why:** Five independent clock subscriptions (grid-is-the-render-surface.md:97) let hero and cube drift; one cursor = one t projected everywhere.

## 8. Unified surface — what the user sees & does

The Review screen presents ONE primary surface (the GIF) plus ONE orthogonal palette panel. PRIMARY SURFACE: by default it is the 2D looping GIF — the honest FRONT PROJECTION of the (x,y,t) index cube down the t axis, one voxel = one cell, pixel-identical to the encoded GIF (rest pose, VoxelRestPoseIdentity). The user ORBITS it (drag) to rotate into 3D: prior frames extrude backward as depth=time, depth cues switch on (air cull, provenance, split-darken, face shading); releasing returns toward the 2D rest pose. A single cursor/playhead scrubs which frame t is the front slice and drives the loop — the SAME clock for hero and palette. PALETTE PANEL (separate, orthogonal): a SCOPE control slides per-frame <-> global (64 independent 256-tables for the NN-input view, or one collapsed maximin table for the global view) — this recolours slots but never moves a pixel. A RADIX selector chooses the palette VIEW: 16^2 treemap, 4^4 opponent-quadrant drill, or 2^8 address wheels — three faithful views of the ONE SplitTree, each addressing the 256 COLOUR slots (never pixels). Grid mode lays the 256 colours on two user-chosen OKLab axes (palette-coordinate plane — explicitly NOT the image (x,y) plane). BRUSHING ties them via the reconstruction law: tapping a palette slot lights that colour across all palette views AND highlights the GIF pixels that use it on the primary surface; the index map and the palette stay visibly distinct but linked by pixel = palette[scope][t][ index[t][y*64+x] ]. The user reads the 2D GIF as the rest pose, orbits to see time-as-depth, slides scope to trade local fidelity for global coherence, and picks a radix to inspect/edit the palette — two knobs on colour, one orbit on geometry, never crossing the two 2D planes.

## 9. Open sub-decisions raised by FULL COLLAPSE (resolve during refinement, before spec)

The §0.1 decision turns several "nice properties" into hard requirements and surfaces real tensions. These are the questions to settle while the design is still on paper:

### Q1 — Always-cube, or swap-at-orbit? (perf/battery)
The primary surface is conceptually always the cube. Implementation has two honest readings:
- **Always-cube:** the Metal raymarch runs even at rest. At rest only the near face (z=63) is visible, so early-ray-exit makes it ~one texture-lookup per pixel — likely cheap, but it keeps the GPU/`MTKView` live for a *looping* hero (battery during a long review).
- **Swap-at-orbit:** render the cheap `PixelGrid`/`PixelImage` path at rest (`isFlat`), switch to the raymarch on first nonzero orbit. Conceptually still one surface; the rest path is just a fast equivalent, *guaranteed* equal by `RULE-CUBE-2D-IDENTITY`.
> **Leaning:** swap-at-orbit, because the rest pose is the 99% case and the identity rule already proves the cheap path is pixel-equal. But this must be **verified on real iPhone 17 Pro** (per CLAUDE.md, GPU/CPU latency decided by benchmark, not assumption). Decide before C1.

### Q2 — "What you see is what you share": cube-rest == *exported* GIF, not just in-memory frames
`RULE-CUBE-2D-IDENTITY` today proves the cube rest pose equals the *in-memory* `frameIndices` (`VoxelRestPoseIdentityTests`). But the shared artifact is the **encoded `.gif`**, which passes through `GIFEncoder` (LZW + colour-table quantization, `GIFRenderer.swift:162-164`). If the encoder re-quantizes `palettesForDisplay` (sRGB8 rounding, ≤256-entry table packing), the exported GIF can differ from the displayed cube.
> **Requirement:** extend the parity contract to **cube rest pose == decoded(exported .gif), byte-for-byte**, or the unified surface silently lies about the export. Add this as a golden in `Spec.FrontProjection` (S1) and confirm where, if anywhere, the encoder mutates the palette vs. consuming it as-is.

### Q3 — Brushing-at-rest collides with the current identity rule ⚠️
The collapse wants brushing to highlight *pixels* on the primary surface (C4). At rest that is a pixel mask on the 2D front face. **But today brush dimming is `isFlat`-gated OFF at rest** (`Shaders.metal:606-651`) precisely so rest pose = *bare* 2D GIF. So full collapse forces a choice:
- **Restate the identity rule:** rest pose = 2D GIF **when no brush is active**; with a brush, rest pose = GIF **+ pixel-highlight overlay**. The "bareness" guarantee becomes conditional on `brushedIndex == nil`.
- This is a genuine amendment to `RULE-CUBE-2D-IDENTITY`, not just a Swift tweak — so the `Spec.FrontProjection` law (S1) must encode the *conditional* identity (`brushedIndex == nil ⟹ rest == bare GIF`). Flagging because it's the one place the user's two goals (honest 2D rest **and** interactive slot↔pixel) are in tension.

### Q4 — Live scope/radix while the hero loops
Scope (per-frame↔global) leaves the index map invariant and only re-resolves colours (`DeterministicRenderer.swift:336`). So sliding scope should re-tint the looping cube **without** re-dithering or touching `frameIndices`. Confirm the surface re-reads `palettesForDisplay[scope]` per frame and that global reindexing stays a pure slot bijection — otherwise the "scope never moves a pixel" promise (§3) leaks into the index factor.

### Q5 — Orbit return + reduce-motion
Spring back to rest on release (rest is the "home" pose), or hold the dragged angle? Under reduce-motion the loop already freezes on frame 0 (`PaletteGridView.swift:13`); the collapsed surface must inherit that — rest pose frozen, no auto-orbit. UX-only, but pins the default that C1/C5 implement.

> These five are the refinement agenda. None require code; Q1–Q3 in particular should be answered before `Spec.FrontProjection` (S1) is written, because they change *what law it proves*.

## 9.1 Resolutions (grounded in code, 2026-06-02)

### ⚠️ MODEL CORRECTION — scope is NOT a pure palette knob
The §1/§3 claim *"scope recolours slots but never moves a pixel; global reindexing is a 1:1 slot bijection"* is **false** against the renderer. Evidence:
- The global render path emits its **own index map** and a single palette repeated across all frames: `palettesForDisplay = Array(repeating: g.globalPalette, count: 64)` and `frameIndicesForVoxels: g.frameIndices` (`CaptureViewModel.swift:528,542,551`).
- That global index map is **freshly assigned**, not relabeled: `DeterministicRenderer.swift:320-339` runs a whole-GIF significance rescue (`SixFourNative.significanceFill` over the pooled 262 144 pixels) and *splits the rescued flat assignment back into per-frame index maps* — a new nearest-global-slot assignment, lossy where frame-local colours merge.

**Corrected model:** per-frame (GIFA) and global (GIFB) are **two complete renders**, each a valid `(index cube, palette)` pair obeying the *same* reconstruction law. The INDEX × PALETTE orthogonality holds **within a scope**; **switching scope swaps both factors at once.** So "scope" is a *render selector*, not a re-tint. The two factors still meet only at the law — but the law is instantiated twice, once per scope.
> Consequence for the unified surface: sliding scope **does** change the displayed cube (different pixels *and* different colours), and it requires the global render to have run (`g.frameIndices` populated). It is NOT a cheap per-frame re-sample. Update §3 and the canonical PALETTE factor accordingly.

#### Reachability trace (settles the "is GIFB dead?" question)
GIFB **is wired and reachable** — the stale "GIFB never produced / collapse has 0 callers" memory is **retired**. The live dispatch (`CaptureViewModel.renderOnce`):
```
renderOnce:321   if settings.useDeterministicCore
  └─ renderDeterministic:401   if settings.paletteScope == .global
        ├─ .global  → renderDeterministicGlobal:476 → DeterministicRenderer.renderGlobalPalette(branching:)   ← GIFB
        └─ else     → DeterministicRenderer per-frame :409                                                     ← GIFA
  else
     └─ GIFRenderer (GPU) :342   — per-frame ONLY, no global branch
```
Three facts this nails down for the unified surface:
1. **GIFB exists**, via `renderGlobalPalette` (not the retired `collapse`); gated on `useDeterministicCore == true` **AND** `paletteScope == .global` (`CaptureViewModel.swift:321,401,476,490`).
2. **Scope is a capture-time EXCLUSIVE, not a live Review knob.** `renderOnce` is `if/else` → exactly **one** of GIFA/GIFB is baked into `CaptureOutput` per capture. The other render does not exist at Review time, so a live scope slider has nothing to cross-fade to yet.
3. **The GPU path ignores scope entirely** (`:342`, per-frame only). Scope=global is a no-op unless the deterministic core is on.

### Q1 — Always-cube vs swap-at-orbit → **lean swap, pending device numbers**
The raymarch (`Shaders.metal:611-651`) marches front-to-back and the near face (z=63) is hit on the first inside step at rest, so a rest frame is ≈1 texture-lookup/pixel — cheap, but it is a full-screen compute dispatch per loop frame at 20 fps. Decision deferred to an on-device measurement per CLAUDE.md; the identity rule guarantees the cheap `PixelImage` rest path is pixel-equal, so swap-at-orbit carries no correctness risk.

### Q2 — Export parity → **already structurally true; just pin it**
`GIFEncoder.colorTable` copies the `[SIMD3<UInt8>]` palette **verbatim** into the 768-byte table (`GIFEncoder.swift:120-130`) and `lzwEncode(minCodeSize: 8)` is lossless — the encoder performs **no** re-quantization or index remap. The sole quantization is `ColorScience.okLabToSRGB8` *upstream* (`GIFRenderer.swift:162-164`), producing `srgbPalettes`, and `palettesForDisplay` is assigned from those same sRGB8 palettes (`CaptureViewModel.swift:374,452`). The Metal `paletteTex` is built from `palettesForDisplay`, so the cube **already** samples the encoder's exact palette, and `frameIndicesForVoxels == volume.frames`. ⇒ cube-rest == decode(exported .gif) holds today by construction. **Action:** make S1's golden assert `decode(encode(volume, srgbPalettes))[t] == reconstruct(volume.frames[t], srgbPalettes[t])` so a future edit can't silently break it. No new code needed beyond the golden.

### Q3 — Brushing-at-rest → **confirmed tension; resolve with a non-destructive rest overlay**
The shader gates the cross-view brush `!flat` and documents it: *"Gated !flat so the 2D rest pose is exact"* (`Shaders.metal:638-651`). It also already encodes the per-radix brush set (`BrushSet.kernelHit`: 16²=single, 4⁴=quad `k&~3`, 2⁸=σ-pair `k^1`). So brushing-at-rest needs an explicit amendment. **Resolution:** keep the *dimming* style orbit-only (dimming the flat GIF would violate "what you see is what you share"); at rest, draw a **non-destructive highlight** (outline / marching-ants on the matched pixels) that leaves every pixel's colour byte-exact. The amended law for `Spec.FrontProjection` (S1): `brushedIndex == nil ⟹ rest == bare GIF`, **and** `brushedIndex ≠ nil ⟹ rest-colours == bare GIF` (overlay is an additive layer, never a colour mutation). Bareness becomes conditional; byte-exactness of the *pixels* stays unconditional.

### Q4 — Live scope re-tint → **moot, superseded by the model correction; AND scope is currently capture-time, not live**
Since scope swaps a whole render (above), there is no "re-tint without re-dither" to design — sliding to global *is* selecting the global render's `(g.frameIndices, g.globalPalette)`. The honest UX is a render **swap** (cross-fade between two complete looping cubes), not a recolour. The reachability trace shows the deeper issue: **today only ONE render exists per capture** (GIFA *or* GIFB, fixed at `renderOnce`), so a live Review slider currently has nothing to swap to. To make scope a live unified-surface knob, choose one:
- **(a) Precompute both at capture** — render GIFA and GIFB every time; slider is instant but capture pays ~2× render. Cleanest UX.
- **(b) Lazy global on first slide** — keep `tiles` in the bundle, run `renderGlobalPalette` on demand; cheap capture, one-time hitch on first slide. Requires persisting `tiles` (ties into blocking gap #2).
- **(c) Restrict scope to deterministic-core captures** — the GPU path has no global branch (`:342`), so either add one or grey-out the scope slider when `useDeterministicCore == false`. Lowest effort, but the slider's availability then depends on an unrelated Settings toggle — poor.
> **Leaning:** (b) lazy, because it matches "capture is cheap, Review is where you explore," and it composes with persisting the index map (gap #2) that full-collapse already requires. Revisit after the GPU-path question: does global belong under the GPU engine too, or is global inherently a deterministic-core feature?

### Q5 — Orbit return + reduce-motion → **spring-to-rest; freeze on frame 0 under reduce-motion** (UX default, no blockers)

**Net effect on the spec plan:** S3 (`Spec/PaletteScope.hs`) must be **rewritten** — its premise (index map invariant under scope) is false. Replace with: *scope selects one of N complete `(IndexTensor, Palette)` renders, each independently satisfying the reconstruction law*; the law to prove is per-render well-formedness + that GIFB's global table is the `farthestPointCollapse`/significance-rescued assignment, not a bijection of GIFA. S1, S2, S4, S5 are unaffected.

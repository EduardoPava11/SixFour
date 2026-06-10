> **Status/built-state:** see [docs/STATUS.md](STATUS.md) (canonical, gated by `scripts/verify-doc-claims.sh`). This document is design rationale, not a status ledger.
>
> **⚠️ SUPERSEDED ARCHITECTURE (2026-06-07).** This doc predates the `Surface` phase-field
> refactor. It names `CaptureView.swift` / `GIFReviewView` / `GIFAResolveView` /
> `fullScreenCover` as if current — **they no longer exist.** The as-built UI is the ONE-surface
> FSM in `SixFour/UI/Surface/` (`SurfaceView.swift` + `*PhaseField.swift`, `Surface.swift`
> `lawPhaseIsCellGrid`). Read this for the *design intent* (form-follows-function, the
> capture→loading→GIFA morph, the no-freeze/no-transparency/export contracts), but map every
> `CaptureView`/`GIFReviewView` reference onto the `Surface`/`PhaseField` code. The live
> review hero is the 64³ voxel cube (`VoxelCubeView.swift`), driven by discrete X/Y projection
> sliders. (`PixelGrid.swift` *is* still live — only the named *views* are retired.)

# SixFour: Capture → GIFA flow redesign (form-follows-function)

> Source: verified multi-agent design workflow (2026-06-06). 5 grounded design
> fragments, each adversarially verified against its riskiest claim, then
> synthesized. Two fragments' riskiest claims were REFUTED and the corrections
> are folded in below (see "CORRECTION" callouts). Every nontrivial claim cites a
> `file_path:line` or shows arithmetic.

**Brief (fixed product intent).** Form follows function: the GRID look is the FORM,
the calling SCRIPT is the function. Capture scene = live preview + a 16×16 palette
grid that IS the shutter (nothing else; other widgets deferred). No freeze on
capture — continuous live frames. A designed on-grid loading state while GIFA
builds. The transition capture→loading→GIFA must feel continuous at the cell level.
GIFA review = the 64³ space-time cube, rotatable to the isometric 8-bit look via
slider X / slider Y, + share + retake (nothing else). Export upscales 64×64→256×256
by 1→4×4 nearest replication. Every 64×64 cell carries a real color — no transparency.

---

## The model

**ONE grid FORM, parameterized by a SCRIPT (the function).** The form is a single
cell-render contract — flat indexed cells, integer scale, no AA, no opacity, one
indexed sRGB8 color per cell (the locked LOOK at `PixelGrid.swift:9-16`). The function
is a `GridScript` value the scene supplies. Capture and Review drive the *same* form
differently.

A `GridScript` is the Swift composition of three already-verified functions:
- **ORDER** — the rank permutation `slot → linear rank`, reusing the golden-pinned
  bijection `GridLayout.layoutN` (`GridLayout.swift:64`), proven hole-free/collision-free
  by `Spec.GridAxis lawLayoutIsBijection` (`GridAxis.hs:112-127`).
- **COLOR** — a *total* function `rank → SIMD3<UInt8>` (no `Optional`; the no-transparency
  law, see §Export). Sourced from `palettesForDisplay` via an enum
  `ColorSource { .zigDeterministic, .swiftFloat }` (the two existing producers,
  `CaptureViewModel.swift:444-462`). The form only ever sees final sRGB8 bytes via
  `Color(srgb8:)` (`PixelGrid.swift:24-26`), preserving on-screen == GIF byte identity.
- **EMBEDDING** — `rank → cell rect` on the locked lattice; the pitch is a *script knob*
  (capture = `CaptureGrid` 4pt pitch, `CaptureGrid.swift:18`; review = `GlobalLattice`/
  `LatticeContract` 6pt atom, `LatticeContract.swift:21-31`).

Plus an INTERACTION enum (`.shutter`, `.rotate(yaw,pitch)`, `.none`) — gestures live in
the script, not the form.

**CORRECTION (verifier refuted the "one renderer behind a `renderMode` switch" claim).**
The two real renderers are physically different machines and the split is a deliberate,
comment-locked perf contract (`PixelGrid.swift:14-15`, `CellField.swift:12-13`):
- **BITMAP backend** (uniform 64×64 = 4096 GIF/preview): materialize `Color(rank)` into a
  `side×side` RGBA8 buffer once, draw via `PixelImage`/`CGImage` `shouldInterpolate:false`
  (`PixelGrid.swift:43-61`). No per-cell closure. At 20fps a Canvas path would be
  4096×20 = 81,920 fills/sec — exactly the cost the contract forbids.
- **CANVAS backend** (≤256-cell palette + non-uniform treemap): `fillCell` per-rect with
  `colorAt → SIMD3<UInt8>?` and `PixelGridOrigin` flips (`PixelGrid.swift:74-95`).

So "ONE FORM" is met at the **contract+input layer** (one `CellSurface` type, one `order`,
one lattice embedding, one golden-checked LOOK), dispatching to two backends by
cell-count/uniformity — *not* by pretending CGImage and Canvas are the same code. The
unification is **proven**, not asserted: add an optional `Spec.GridScript` whose
load-bearing golden is a **render-equivalence law** — for a uniform embedding the bitmap
and Canvas backends produce byte-identical cell colors for every rank (analogous to
`RULE-CUBE-2D-IDENTITY`, `GIFPlayer.swift:126`). No mandatory new spec module: ORDER is
`Spec.GridAxis` (done), cell-as-function-of-Place + `Source` provenance is `Spec.CellGrid`
(`CellGrid.hs:30-56`, done).

This extends the centralized-ORDER plan: `Spec.Order → OrderContract.swift` is exactly the
ORDER slot; `GridScript` just names *which* order each scene binds (capture =
identity-by-index, no per-frame re-sort jitter; review = `GridLayout.layout(x:y:)`).

```
                       ┌──────────────── GridScript (the FUNCTION) ───────────────┐
                       │  order: [IndexedColor]->[Int]   (Spec.GridAxis / OrderContract)
   palettesForDisplay  │  color: ColorSource{.zig,.swift}  (rank->SIMD3<UInt8>, total)
   [[SIMD3<UInt8>]] ───┤  embed: Embedding{4pt | 6pt | dimetricCube}
                       │  inter: {.shutter | .rotate(yaw,pitch) | .none}
                       └────────────────────────────┬─────────────────────────────┘
                                                     v
                              CellSurface  (the FORM = one colorAt(rank) + lattice)
                            proven byte-equiv  ┌──────┴───────┐
                                               v              v
                                      BITMAP backend     CANVAS backend
                                      4096-cell GIF/      ≤256-cell palette
                                      preview (CGImage)   + treemap (fillCell)

  captureGIF  capturePalette  reviewCube  reviewPalette  =  four `static let` GridScripts
```

## Capture scene

**Only two elements** (brief): the live PREVIEW grid (bitmap backend, `captureGIF`, `.none`)
and the 16×16 PALETTE grid that IS the shutter (canvas backend, `capturePalette`, `.shutter`).
The palette is conditionally a `Button` (idle) or an inert grid (busy) — one widget,
color+position are the affordance (`CaptureView.swift:142-176`).

**NO-FREEZE — already architected correctly (verifier confirmed `holds=true`):**
- The burst runs entirely off the MainActor: `AVCaptureVideoDataOutput` delivers
  `CMSampleBuffer`s on a private serial `delegateQueue` (qos `.userInitiated`,
  `CaptureSession.swift:29,231`); each is `pipeline.submitAsync` (non-blocking), appended in
  the GPU completion handler; the burst future is a `CheckedContinuation`
  (`CaptureSession.swift:562-583`, resumed `:671-689`) awaited by `capture()` on the
  MainActor (`CaptureViewModel.swift:304-374`).
- Continuity = re-feed burst frames into the **same `previewTile` binding** the idle feed
  uses. Idle writes `previewTile` at `CaptureViewModel.swift:240`; the burst writes the SAME
  binding at `:325` via `burstFrameCallback` (declared `CaptureSession.swift:74`, fired `:803`,
  set `CaptureViewModel.swift:317-328`). The preview *shows the frames being recorded* —
  literal continuity, no frozen frame.
- Progress is **on-grid only**: `phase = .capturing(progress:)` (`CaptureViewModel.swift:326`)
  fills the captured fraction of the palette-shutter's 256 cells (a cell transform, not a fade).

**CORRECTION (verifier: the dominant failure mode is dropped RECORDED frames, not preview
stutter).** `makeQuantizedPreviewImage` (`CaptureViewModel.swift:753-783`) runs the full
deterministic quantize chain synchronously on the same serial `delegateQueue` that intakes
camera frames; with `alwaysDiscardsLateVideoFrames = true` (`:230`), queue back-pressure
becomes kernel-side **dropped burst frames** (counted `:828`), damaging the 20fps recorded
cadence. **Fix:** move `makeQuantizedPreviewImage` OFF `delegateQueue` onto a dedicated
preview-render queue with a coalescing latch (drop stale tiles); keep `delegateQueue` doing
only `collected.append` + finish-gating; add an on-device benchmark to replace the unverified
"~3-4ms" with a measured budget against the ~33-50ms ISP interval. Fall back to raw
`makePreviewImage` (~0.5ms) during the burst if it still lags.

**GAP (brief compliance):** the Settings gear (`CaptureView.swift:62-66,98-103`;
`CaptureGrid.swift:33,49-50`) is a third element. Remove it from the capture scene
(brief: "Nothing else"). UI-removal, not a pipeline change.

## Continuous transition + loading

The capture preview and final GIFA already render through the same byte-identical cell builder
— `CaptureViewModel.image(fromRGBA:side:)` (`:787`) ≡ `GIFCanvas.pixelImage(fromRGBA:side:)`
(`GIFPlayer.swift:160`), both feeding `PixelImage` `.interpolation(.none)`, opaque alpha. A
*cell* is already continuous. Three discontinuities remain: (1) the hard `fullScreenCover` swap
(`CaptureView.swift:21-26`); (2) a pitch jump (capture 4pt/256pt vs Review 6pt/384pt — both
integer multiples of 64, both ≤402pt); (3) loading is a TEXT banner (`CaptureView.swift:179-210`).

**Design:** keep ONE persistent 64×64 surface (the cube front face) mounted across
capture→loading→GIFA, never unmounting it. The LOADING state is an **on-grid "resolve sweep"**
over that surface, driven by the 5 real deterministic stages (`DeterministicRenderer.swift:22-27`,
surfaced one-at-a-time via `deterministicStage`, `CaptureViewModel.swift:491,572` — honest, tied
to real kernel completion):

| stage | on-grid effect |
|---|---|
| quantize | live cells snap to fewer colors |
| dither | serpentine Bayer-band resolves row-by-row (reuse `CellField.bayer:33`) |
| significance | any flat/degenerate cell fills with a real color (no-transparency law) |
| palette | cells re-tint preview-sRGB → final OKLab→sRGB8 bytes |
| encode | grid "locks", border hardens, GIFA frame 0 revealed |

`loadingProgress: Double` (0…5) drives a serpentine wipe; intra-stage fraction rides the
existing `GridHeartbeatClock` 20fps tick (`CaptureView.swift:7,58`) — zero extra clock. Animate
`PixelImage.edge` 256→384pt so the pitch jump becomes a continuous "cube coming forward" zoom
(both crisp; integer multiples of 64). The sweep lands on **GIFA frame 0 = the flat
front-projection rest face** (`GIFCanvas.frontProjectedFrames`, `GIFPlayer.swift:126-156`),
byte-identical to the live-quantized cell semantics. Capture→GIFA **never shows a cube**; the
isometric reveal is an opt-in Review gesture.

**CORRECTION (verifier refuted "host `GIFReviewView(vm:)` in-place").** `GIFReviewView` owns
full-screen layout (`Color.black.ignoresSafeArea()` `:35`, `ScrollView` `:49`, bottom-pinned
actionRow `:90`), its own `@State PlaybackClock` started/stopped by `GIFPlayer.onAppear/onDisappear`
(`GIFPlayer.swift:36-41`), explorer/status/badge chrome that contradicts the brief — and **no X/Y
rotation sliders at all**. So do NOT embed it. Instead:
1. Extract `GIFPlayer.renderSurface` into a standalone view taking `output + clock` as inputs,
   **not** owning clock lifecycle.
2. Replace `fullScreenCover` with an in-lattice `ZStack` branch keyed on `vm.primaryOutput`,
   mounting the extracted surface at the SAME `.position`/edge as `previewBlock`.
3. Build the brief's actual Review scene (cube + slider X + slider Y + SHARE + RETAKE) as a NEW
   lightweight view; leave `GIFReviewView`'s legacy chrome out of the morph path.
4. While embedded, drive the cube from a single shared clock (reuse the capture heartbeat).

Tune: clamp each stage band to ≥120ms min dwell (read real `stageMillis`, `CaptureOutput.swift:64`)
so a <150ms render is still readable, without faking progress. GPU fallback path exposes only 2
phases — add a graceful 2-band degradation.

## GIFA review: the isometric cube

Resurrect the already-built `VoxelCubeView` (`VoxelCubeView.swift` + `voxel_raymarch` in
`Shaders.metal`) as the Review hero. A 64³ (x,y,t) index volume drawn **orthographically**: at
yaw=pitch=0 the near face (z=63) is byte-1:1 with the flat 2D GIF (`RULE-CUBE-2D-IDENTITY`,
`VoxelCubeView.swift:136-153`). Slider X → yaw, slider Y → pitch (bind `VoxelCubeState.yaw/pitch`,
`:171-172,596-597`), replacing the orbit `DragGesture`. Chrome `.heroMinimal`. Plus SHARE + RETAKE.
**Nothing else.**

**VERIFIED screen-fit arithmetic (verifier confirmed `holds=true`, math redone to the digit):**
- The render surface is a FIXED `e×e` square: `e = canvasEdge(min(geo.w,geo.h), 64)` snaps DOWN
  to a multiple of 64 (`Theme.swift:70-73`), resolving to **384pt = 64×6pt** under the Review
  column (`VoxelCubeView.swift:270-276`). `384 ≤ 402` screen width, leaving **18pt (9pt/side)
  margin** (`LatticeContract.swift:70-71`; `Theme.swift:38` `gifCanvasPt=384`).
- The kernel maps the WHOLE `e`-px square to voxel-space `[-halfSpan,+halfSpan]`:
  `plane = (uv-0.5)*2*halfSpan`, `center = float3(32.0)`, `o = center + plane.x·Xb + plane.y·Yb +
  200·Zb`, `d = -Zb` (`Shaders.metal:591-615`). `halfSpan` multiplies **only `plane`** — never
  translates the center or basis.
- `VoxelIso.fitHalfSpan` (`VoxelCubeView.swift:139-153`) takes `max` over the 8 corners `{±32}³`
  of `max(|c·Xb|,|c·Yb|)`, +1 pad when orbited. Because the corner set is closed under negation,
  the silhouette on each screen axis is **symmetric** `[-m,+m]` about the fixed center → silhouette
  ⊆ window, **no clip/overflow at any (yaw,pitch).**
- **Exact `halfSpan`:** 32.0 flat → **51.34** at the 45°/30° hero → **global max 56.43** at
  (225°,−55°). Gesture clamps pitch to ±1.5rad (≈85.9°), so 56.43 is the true ceiling. Worst-case
  voxel = `384/(2·56.43) = 3.40pt` (0.57 gifPx) vs 6pt flat. The box NEVER grows on screen —
  **voxels shrink**; the silhouette is always a centered ≤384pt square < 402pt.

**Cube edge that fits 402pt at all rotations:** on-screen edge `e = 384pt = 64 cells @ 6pt`, fixed;
content `halfSpan` grows 32→56.43 absorbed into that fixed square. Margin 18pt.

**Gaps to close:** (1) the projection/fit math is hand-written and **NOT spec-pinned** — add
`Spec.VoxelFit` porting `voxelOrbit` + `fitHalfSpan`, proving `∀(yaw,pitch): fitHalfSpan ∈ [32,
32√3+1]` and on-screen silhouette = 384pt ≤ 402pt; goldens for 32.0 / 51.34 / 56.43. (2) Confirm
`CaptureOutput.frameIndicesForVoxels` is populated at Review time (`VoxelCubeData.init?(output:)`,
`VoxelCubeView.swift:73-74`) or the cube falls back to placeholder. (3) `ART_RES=128` drops to
~1.13 art-px at global-max halfSpan — consider restricting the pitch slider so the hero band
dominates, keeping the 8-bit stairstep readable.

## Export + opacity contract

**64→256 upscale = pure INDEX-domain 4× replication, BEFORE encode.** Each `UInt8` source index →
a 4×4 block of the SAME index: `out[(4·sy+dy)·256 + (4·sx+dx)] = src[sy·64+sx]`, producing 65536
indices/frame. The encoder takes `width=height=256`.

**Why byte-exact-safe (verifier confirmed `holds=true`):**
- Palette untouched: replicating indices (not colors) keeps the per-frame LCT byte-identical
  (`GIFEncoder.swift:120-130`); `okLabToSRGB8` / `s4_palette_oklab_to_srgb8` output unchanged.
- Timing untouched: the GCE delay is a fixed per-frame field independent of pixel count
  (`GIFEncoder.swift:159-170`, `kernels.zig:1212-1213`).
- LZW is length-agnostic: dictionary reset gates on `next_code ≤ 4095` (`GIFEncoder.swift:250-258`,
  `kernels.zig:1133/1141`), NOT pixel count; `256 < 65535` fits the u16 dimension fields. SHA-256
  hashes the produced bytes with no length assumption (`DeterministicRenderer.swift:214,402`).
- **CORRECTION (precision):** the Zig `SIDE/FRAME_COUNT/K` constants (`kernels.zig:53-55`) appear
  ONLY in test code; `s4_gif_assemble` is fully side-parametrized. **Do NOT route the upscale
  through `s4_gif_encode_burst`** — it would re-quantize/re-dither the upscaled pixels and change
  the bytes. Keep replication a pure index post-step, then call `s4_gif_assemble`(side=256) or
  `GIFEncoder(width:256,height:256)`. The ONLY required edit is the `frame.count != width*height`
  guard (`GIFEncoder.swift:66-69`), which auto-retargets at 256².

**No-transparency / every-cell-opaque (verifier: ALREADY structurally airtight — pin, don't build):**
- Encoder hardcodes transparent-color flag = 0 (packed `0x04`), no GCT (LSD `0x70`), disposal-1
  (`GIFEncoder.swift:159-170,82`; Zig `kernels.zig:1212-1215,1184`). No alpha channel anywhere.
- `SignificantVoxelVolume` brand forces every one of the 4096 source pixels to a real palette
  index, every slot ≥ `minPopulation` (`Significance.hs:449-454 lawSigAllSignificant`); the
  constructor REJECTS any frame with a sub-`minPopulation` cell (`Significance.hs:388-396`), so a
  `.degenerate` count-0 cell (`SignificantSplitFill.swift:96-112`) can never reach the encoder.
- `okLabToSRGB8` clamps to [0,1] and always returns 3 opaque bytes (`ColorScience.swift`).
- **Gate on the 64×64 SOURCE volume** (where P=4096=16·K makes "cannot fail" true); replication is
  a population-preserving 16× scale, so re-proving at 256² is unnecessary.

## Phased implementation plan

Each phase: **spec (Haskell) → codegen → golden test → Swift adoption → build/verify**
(`cd spec && cabal build && cabal test && cabal run spec-codegen` → `xcodegen generate` →
`xcodebuild -scheme SixFour -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`).
Tags: **[NEW]**, **[RESURRECT]**, **[UNTOUCHED]**, **[FIX]**.

**Phase 0 — No-freeze hardening [FIX, pipeline].** No spec change. Move `makeQuantizedPreviewImage`
off `delegateQueue` onto a coalescing preview-render queue; add on-device benchmark; verify hero
animates burst with `droppedFrameCount == 0`. *(Closes the verified dropped-frame risk before any
UI change.)*

**Phase 1 — Centralized ORDER / GridScript [NEW, optional spec].** Add `Spec.GridScript` pinning
the two named `embedding∘order` compositions (capture identity@4pt, review axis-sort@6pt) + the
**render-equivalence golden** (bitmap ≡ canvas byte-identical for uniform embedding). Reuses
`Spec.Order → OrderContract.swift`. Codegen `GridScriptContract.swift`; golden-pin in `Properties/`.
Swift: define `ColorSource`/`GridEmbedding`/`GridInteraction` enums + `GridScript` struct + 4
`static let`s; refactor `PixelGrid`+`PixelImage` into `CellSurface` dispatching to the two backends
behind one `colorAt(rank)` input contract.

**Phase 2 — Capture scene to two elements [FIX + NEW].** Remove gear; re-run CaptureGrid self-check.
Rebuild capture with exactly two `CellSurface`s (preview=`captureGIF` bitmap `.none`;
palette=`capturePalette` canvas `.shutter`). Add palette-shutter progress-fill from
`phase.capturing(progress:)`. **[UNTOUCHED]:** the burst pipeline itself.

**Phase 3 — Continuous loading sweep [NEW].** Spec: `Spec.GIFAResolve` (or extend `Spec.Display`) —
pure `(stageIndex, fraction, side) → resolved cell set`, serpentine order, golden-pinned. Codegen
`GIFAResolveContract.swift`. Swift: add `loadingStage`/`loadingProgress` to VM; build
`GIFAResolveView` over the persistent `PixelImage`, animate edge 256→384; replace `phaseBanner`
text. Add ≥120ms min-dwell + GPU 2-band degradation.

**Phase 4 — Persistent surface + Review scene [NEW + FIX].** Extract `GIFPlayer.renderSurface` to a
clock-injected standalone view (do NOT embed `GIFReviewView`). Replace `fullScreenCover` with
in-lattice `ZStack` keyed on `vm.primaryOutput`, surface at the same position/edge as `previewBlock`;
reconcile to one shared clock. Build the NEW lightweight Review scene (cube + 2 sliders + SHARE +
RETAKE).

**Phase 5 — Isometric cube [RESURRECT + NEW spec].** Spec: `Spec.VoxelFit` (port `voxelOrbit` +
`fitHalfSpan`; prove fit bound; goldens 32.0/51.34/56.43). Codegen `VoxelFitContract.swift`. Swift:
wire slider X→yaw, slider Y→pitch into `VoxelCubeState`; reference the contract from `VoxelIso` (no
free literals). Verify `frameIndicesForVoxels` populated, rest-pose byte-1:1, 64³ interactive on
iPhone 17 Pro. **[UNTOUCHED]:** `voxel_raymarch` kernel.

**Phase 6 — Export 4× upscale [NEW spec + Swift/Zig].** Spec: `Spec.Export` — `upscaleFactor=4`,
`outputSide=256`, `replicateIndices`, laws `lawReplicateLength`(f²·P) /
`lawReplicatePreservesUsedSet` / `lawReplicateCountsScale`; golden 2×2→8×8. Codegen the constants.
Swift: pure `replicate4x` (verified vs golden), called between the significance gate
(`GIFRenderer.swift:176`) and `encoder.encode` (`:202`); construct encoder at 256². Zig:
`s4_replicate_indices` + replicate then `s4_gif_assemble(side:256)` (NOT `s4_gif_encode_burst`). Pin
`lawNoTransparentIndex` + an encoder GCE/LSD byte test (`0x04`/`0x70` flags clear).

## Open questions / decisions for the user

1. **True 64³ voxel raymarch vs flat-quad isometric.** Recommended default: **keep true 64³
   raymarch** — built, verified screen-fit, and the brief wants the genuine "(x,y,t) cube in a game"
   look a flat quad cannot give.
2. **Loading-stage granularity.** Recommended default: **honest 5-stage sweep on the deterministic
   core**, graceful 2-band degradation when the GPU path runs, ≥120ms min-dwell. Never fake progress.
3. **Palette-shutter color freeze on press?** Recommended default: **freeze the palette colors at
   press** so the user sees the palette they "shot"; progress-fill animates over the frozen colors.
4. **Where does Settings go (removed from capture)?** Recommended default: **fully deferred** (no
   entry point now); palette long-press is the cheapest future home.
5. **Pitch reconciliation during the morph (256pt vs 384pt).** Recommended default: **drive the morph
   at capture's 4pt/256pt, then animate edge to 6pt/384pt during the loading sweep** so the handoff to
   the Review hero is positionally seamless.
6. **`Spec.GridScript` golden scope.** Recommended default: pin **both** the two `(order,embedding)`
   compositions **and** the render-equivalence law (bitmap≡canvas), plus per-surface `Source`
   provenance, so scene wiring is fully codegen-checked.

# SixFour — Swipe-to-LOOK + R3D `.cube` LUT extraction

> **One sentence:** a *look* is one data-driven OKLab palette→palette transform with two
> projections — the live capture screen recolours it on a **swipe**, and Review exports the
> **same** transform as a 65³ `.cube` LUT for grading R3D footage in DaVinci Resolve.

Status: BUILT (2026-06-10). Spec 750 tests + Zig 28 tests green; drift gate 24 symbols;
iOS BUILD SUCCEEDED (compile-only — on-device swipe/look legibility and the Resolve LUT
result are the user's verification step, per the camera-app rule).

## Origin

Ported from `~/lut-generator/src/python/gif_palette_lut.py` (and `lut_generator.py`): analyse a
palette across luminance zones, then for each input colour keep its lightness and bend its
chrominance toward the zone's mean a/b at that lightness ("chrominance-only transfer"), with a
filmic tonemap and Log3G10/RWGRGB→Rec.709 front-end for RED footage. The python works in CIELAB;
SixFour ports it to **OKLab** so it reuses the existing byte-exact Q16 colour core.

## The unifying idea (two projections of one transform)

```
        swipe ──▶  LookVariant (strength / polarity)
                          │  + live-derived ZoneProfile (the captured palette's own chroma)
                          ▼
                  transferOklabQ16   ← the ONE shared core (preview ≡ cube, a LAW)
          ┌───────────────┴────────────────┐
          ▼                                 ▼
  PREVIEW (cheap)                    EXPORT (R3D .cube)
  256-colour palette                 65³ grid in Log3G10/RWGRGB
  → recolour hero + shutter          → Rec.709 sRGB-gamma, 6-decimal
```

A `LookVariant` only picks **strength + polarity**; the **profile is always live-derived** from
the current palette, so the look is "your scene, graded by itself", not a canned recipe. `.off`
is the honest identity.

## Layers (Haskell → Zig → Swift → UI), all golden-gated

### Haskell spec (source of truth) — `spec/src/SixFour/Spec/`
- `ColorFixed` — added `isqrtFloor` (exact Q16 sqrt) + factored `oklabToLinearSRGBQ16` out of
  `oklabToSrgb8Q16` (pure refactor; existing colour golden re-verifies it).
- `ZoneProfile` — `analyzeZoneProfileQ16` (8 luminance zones, sum-then-divide ⇒ permutation-
  invariant; empty zones → global mean), `sampleZoneTargetQ16` (piecewise-linear, end-clamp),
  `chromaQ16`.
- `LookTransfer` — `transferOklabQ16`: keep L, blend a/b toward the (polarity-applied) zone
  target by strength, scale chroma (clamped), neutral-colour epsilon branch. `transferPaletteQ16`
  = the preview map. **★ Law: luminance preservation.**
- `RedFrontEnd` — `log3g10DecodeLut` / `filmicTonemapLut` generators (the ONLY place log/exp run;
  emitted as `.bin`), `rwgToRec709Q16` (composed-then-rounded matrix), `redDecodeToLinearQ16`
  (decode → matrix → clip → tonemap), `gamutCompressQ16` (in-gamut = exact fixed point),
  `applyBlackLiftQ16`.
- `CubeLut` — `cubeGridCoordQ16` (**★ .cube R-fastest ordering law**), `cubeVoxelQ16` (full
  per-voxel pipeline, **★ preview≡cube law**), `buildCubeQ16`; `srgbEncodeLutQ16` (Q16 sRGB
  output gamma for 6-decimal precision).
- `Fixtures.hs` emits `{log3g10_decode,filmic_tonemap,srgb_encode}_lut.bin` → `Native/src/` and
  `lut_golden.json` (synthetic palette + expected profile + adversarial transfer cases + a full
  5³ cube) → `trainer/out/`.

### Zig core — `Native/src/kernels.zig`
`@embedFile`s the three `.bin` LUTs (comptime length guards), `RWG_TO_REC709_Q16` literals, and
mirrors every Haskell function byte-for-byte. Exports `s4_zone_profile_q16`, `s4_look_transfer_q16`,
`s4_build_cube_q16`. `lut_fixture_test.zig` byte-checks the profile, every transfer case, and the
whole 125-entry cube against the Haskell golden. Header `sixfour_native.h` declares all 24 symbols
(drift gate `verify-doc-claims.sh`).

### Swift bridge — `SixFour/Native/SixFourNative.swift`
`srgb8ToOklab`, `lookZoneProfile`, `lookTransfer`, `extractLUT` (mirror the `quantizeFrame`
buffer-pointer pattern).

### UI
- `LookVariant` (`SixFour/Palette/LookVariant.swift`) — closed alphabet `off / soft / medium /
  strong / inverted`; `.params` → `LookParams`; `.apply(to:)` does the cheap 256-colour round-trip.
- `AppSettings.captureLook` — persisted (`sixfour.captureLook.v1`), default `.off`.
- `LivePhaseField.lookSwipe` — a clear background `DragGesture` (6-cell min, horizontal-dominant,
  `.onEnded`) cycles the look + haptic; a transient `CellText` shows the look name (only when a
  grade is active). The hero is `allowsHitTesting(false)`, so swipes reach the layer without
  fighting the palette's tap/lift.
- `SurfaceView` — re-grades `surface.palette` (shutter) and `surface.previewPalette` (hero)
  through `captureLook.apply(to:)`; the index tile is untouched, so **nothing moves** — the cell
  grid is structurally intact.
- `ReviewPhaseField` — **Export LUT** button (shown when a look is active) → `LUTFile.makeShareItem`
  builds the 65³ cube from the clip-wide pooled palette and shares the `.cube` via an
  `ActivityView` sheet.
- `LUTFile` (`SixFour/Encoder/LUTFile.swift`) — pure-Swift `.cube` writer (header +
  `value/65536` to 6 decimals, in .cube order).

## Why these choices
- **OKLab not CIELAB:** reuses the byte-exact Q16 core; sRGB ≡ Rec.709 primaries ⇒ OKLab→linear
  is exactly linear Rec.709 (only gamma differs, applied separately). The one hazard — OKLab L ∈
  [0,1] vs CIELAB L\* ∈ [0,100] — is pinned by the luminance-preservation law.
- **Transcendentals as embedded 1-D LUTs:** keeps the whole path deterministic integer Q16, the
  `gamma_lut.bin` precedent. No floating point on the core path → cross-device byte-exact.
- **Q16 6-decimal `.cube`:** banding-free for real R3D grading; the golden stays exact (Q16 ints).

## Verify end-to-end
```bash
cd spec && cabal build && cabal test                      # 750 laws + goldens
cabal run spec-fixtures                                    # emit .bin + lut_golden.json
cd ../Native && zig build test                             # 28 Zig tests (byte-exact to spec)
cd .. && bash scripts/verify-doc-claims.sh                 # drift gate (24 symbols)
xcodegen generate && xcodebuild -scheme SixFour \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build   # BUILD SUCCEEDED
```
On device (user): swipe on capture cycles distinguishable looks (hero + palette recolour, name +
haptic); Review → Export LUT shares a `.cube`; load it on a RED/R3D clip in Resolve and confirm
the grade matches the on-screen look.

## Notes / open
- Compile-only on iOS (sim has no camera): gesture arbitration and look legibility are device-
  verified by the user.
- OKLab≠CIELAB ⇒ the *method* is ported, not the python's byte-for-byte output.
- If 8-bit-ish banding ever shows on R3D, bump `numZones` (cheap) before reaching for cubic-spline
  zone interpolation (the python's `CubicSpline`; we use exactly-reproducible piecewise-linear).

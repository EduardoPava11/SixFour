# Session Notes — 2026-07-06 — Color-Time Theory, Multiscale Render, Optical EV

A large session that (1) built the "color-time" theory as a verified Haskell spec arc, (2) landed
the always-on multiscale render foundation on device, and (3) added real optical-EV bracketing and
the inverted-pyramid three-view. Everything device-side is **additive and flag-gated**; the default
(all flags off) path is byte-identical to before, and the byte-exact core is preserved throughout.

## Haskell spec (source of truth) — 9 new verified modules

All `cabal test` green, Haddock 100%, wired in `spec.cabal` + `Spec.Map` + `test/Spec.hs`.

| Module | What it proves | Laws |
|---|---|---|
| `RadiometricRealize` | inverse-EOTF realization (linear16 sums → sRGB8), BT.2020→sRGB gamut hop; keystone `lawEncodeInvertsEotf` | 7 |
| `ColorTime` | τ_c = temporal support of a chromatic measurement; SNR ∝ √τ_c; Jensen (pool in linear light); τ_c(k)=4^k·Δ₀ | 10 |
| `GaussianLadder` | the 2×2×2 ladder = ℤ[i] ramified prime (1+i); ideal norm = color-time; Morton = SIMT thread index | 9 |
| `EventEncoding` | capture = temporal dither; Hermite identity = entropy-up-signal-captured; rate–distortion | 5 |
| `Gif89aDecode` | the 3 rungs → palette (16²) + index map (64²) + per-frame dither (32²); 14-bit colour from 8-bit GIF | 8 |
| `GeneDensity` | a gene = a mass-preserving-up-to-warp pushforward on the colour density | 9 |
| `GeneDensity3D` | joint (R,G,B) hyperoctahedral B₃ hue warp; hue rotation is NOT a product of per-channel marginals | 12 |
| `HaltDepth` | certified kinematic order → render depth (motion→64³, stillness→16³); the multiscale allocator | 11 |
| `LabTransition` | the OKLab valve: pool on RGB, look on LAB; only the linear hue (S₃/C₄) crosses scale-equivariantly | 6 |

**The unifying number:** one integer `k` is spatial coarsening, temporal-pool depth (2^k), optical
stops (+k), ideal-norm √ (4^k), color-time (4^k·Δ₀), dither bit-gain (k bits), and the palette↔index
split (K=16², S=64²=16·K).

## Device (iOS, byte-exact, additive)

- **Inverted-pyramid three-view** (`InvertedPyramidField`) — the launch capture face: 64²/32²/16²
  as an inverted pyramid, the 16² vertex is the shutter; wired into `LivePhaseField`.
- **Optical EV** — `ExposureBracketDriver` (real single-cam time-multiplexed bracket via
  `setExposureModeCustom`, light ladder 64²=0 / 32²=+1 / 16²=+2 stops) + `CaptureExposureProbe`
  (device capability probe). Behind `Feature.opticalEV`.
- **Live ladder** — `Feature.liveLadder`: the real device 32²/16² rungs realized to sRGB8 via the
  new inverse-EOTF kernel (`s4_sums_bt2020_to_srgb8`, `palette16.zig`).
- **ColorHead** — the x420 path now realizes `latestGCT` (BT.2020 kernel); balance-audit fix to
  `realizeSingleFrame` (divisor derived from the actual crop, not the instance `cropSide`).
- **Multiscale render (Stage 0)** — `HaltDepthBridge` (byte-exact mirror of `Spec.HaltDepth` +
  golden-parity test) turns the live certified halt orders into the per-region depth field;
  `MultiScaleRender` fuses V16/V32/V64 via `s4_render_select` and routes back through the SAME five
  `DeterministicRenderer` kernels to a GIF. Behind `Feature.multiScaleRender`; the `all-fine ==
  current renderer, bit-for-bit` safety is guaranteed by construction (bitcast + pure-copy select).

## Feature flags (all default OFF; default path byte-identical)

`opticalEV`, `liveLadder`, `multiScaleRender`.

## Verification

- spec: `cabal build` + `cabal test` (all new modules green) + `cabal haddock` 100%.
- Zig: `zig build test` — 122 tests.
- iOS: BUILD / TEST BUILD SUCCEEDED (arm64 simulator, compile-check only — camera app runs on
  device); GRID lint PASS. Swift tests compile but were not executed headless (no simulator/camera).

## Next (planned, not built)

- **Stage A — the sculpt surface** on the `.deciding` seam: swipe→hue (writing into the
  `LabTransition` valve), coarseness dial (halt→depth threshold, live), background θ_up learning.
- **The true density-warp MLX seam** — the 21-word `θ_up → colour-index` model behind
  `GeneDensity3D.hueRotate`, so the hue dial drives a real density warp, not just the palette.

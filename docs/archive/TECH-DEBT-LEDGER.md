> **ARCHIVED 2026-06-05 — superseded by [docs/STATUS.md](STATUS.md).**
> Retained for history only. Do NOT use for current status: the live open-debt table now lives
> in docs/STATUS.md, and §A1 items #5–#8 audit NOTES.md phrases that were already annotated
> CLOSED inline (self-referential drift). For current truth, read docs/STATUS.md and run
> scripts/verify-doc-claims.sh.

# SixFour — Tech-Debt Ledger

> Generated synthesis pass. Every claim below was read from source and adversarially
> verified. Cite `file:line` evidence; do not guess.

## The architecture lens (the "core" this repo should embody)

Borrowed from TigerBeetle: **state = fold(apply, init, log)**, with four properties.

1. **DETERMINISTIC** — integer-exact, byte-exact cross-device. Float is the "lying layer".
2. **RECOMPUTED** — correctness via multi-impl parity (Zig ≡ Swift ≡ Haskell golden) and
   re-running the pure fold, NOT runtime replication.
3. **LOG-FOLDED** — the 64 per-frame palettes are the "log"; `s4_global_collapse` folds them
   (pooled maximin) into ONE global palette. state = fold over candidates.
4. **CONSERVATION-TYPED** — leaves are SELECTED from real input colors (never synthesized) ⇒
   no color created; significance (every slot ≥ `minPopulation`) ⇒ nothing unbooked.

The NN is **OFF** the deterministic path: it is a CLIENT that MINTS a float σ-pair genome
(384-DOF), QUANTIZED at a commit boundary into a fixed-size integer gene blob; from there only
the deterministic Zig fold APPLIES it. **Mint ≠ Apply.**

**Tech debt here = anything that violates, obscures, or fails to wire this core.**

Repo root: `/Users/daniel/SixFour`. Key spots: `Native/src/kernels.zig` (`s4_*` kernels),
`SixFour/` (Swift), `spec/` (Haskell source of truth + golden), `trainer/`,
`docs/SIXFOUR-ARCHITECTURE-MAP.md`, `CLAUDE.md`, `NOTES.md`.

## Build-sequence ordering (docs/SIXFOUR-ARCHITECTURE-MAP.md §4)

Items are ordered by where they sit on the spine, high-severity first within each band:

1. **Wire the GIFA→GIFB collapse fold into the render path** (the keystone)
2. **Wire the mint/apply gene-quantize boundary + `loadLookNet`**
3. **Lock the 384-DOF contract / purge 768**
4. **Parity & conservation gaps**
5. **Determinism / float-drift removal**
6. **Hygiene**

---

## Status update — keystone fold implemented (Zig core)

> Applied after the audit, verified by `zig build test` → **26/27 pass, 1 skip
> (the not-yet-existent Haskell `golden.gif`), 0 fail**. Footprint: `Native/src/kernels.zig` only.

- **#1 `stub-gif-encode-burst` → DONE.** `s4_gif_encode_burst` is no longer a
  `RC_NOT_IMPLEMENTED` stub. It is now the single-call deterministic fold —
  `widen → linear→OKLab → quantise → dither → palette → assemble` — composing the
  already-golden-gated sub-kernels per frame, then one `s4_gif_assemble`. Significance
  is intentionally out of scope (the signature carries no `min_population`); this is
  the pure core `apply` primitive, a pure function of the input halfs (the "recompute
  to verify" entrypoint a gene exchange needs). Gated by a new
  **composition-equals-its-gated-parts** test (transitively rides the color/quant/
  dither/assemble Haskell goldens) + determinism + GIF89a + guards. The Haskell
  `gif_fixture_test.zig` end-to-end golden still skips until `golden.gif` lands.
- **#4 `s4-widen-half-stub` → DONE.** `s4_widen_half_to_q16` implemented as the exact
  I/O edge: `round(half · 2^16)`, round-half-away-from-zero, non-finite→0, saturated
  to ±2^30. Pinned by an anchor test (1.0→65536, 0.5→32768, 2.0→131072, ±inf/NaN→0).
- **`s4_burst_scratch_bytes`** rewritten to size the burst carving EXACTLY (~0.5 MB
  for 64³, down from the old ~2.6 MB dead-histogram over-allocation).
- **STALE-CLAIM CORRECTION (was Band 1 premise).** The audit/arch-map claim that the
  GIFA→GIFB **collapse has "zero callers" / GIFB is never produced is FALSE.**
  `s4_global_collapse` → `SixFourNative.globalCollapse` → `DeterministicRenderer.renderGlobalPalette`
  → `CaptureViewModel.renderDeterministicGlobal` (`:490`), reached from `renderOnce`
  when `settings.useDeterministicCore && settings.paletteScope == .global`, gated by
  the whole-GIF `GlobalCompleteVolume` + `GlobalSignificantVolume` brands. The collapse
  fold is ALREADY on the app path; `docs/SIXFOUR-ARCHITECTURE-MAP.md` §2(c)/§4-item-1
  should be updated to retire the "zero callers" wording.

---

## Findings table

| # | id | title | file | class | sev | fixKind |
|---|----|-------|------|-------|-----|---------|
| 1 | stub-gif-encode-burst | `s4_gif_encode_burst` unimplemented (Stage-0 stub, keystone entrypoint) | `Native/src/kernels.zig:112` | unwired-core | high | feature |
| 2 | empty-training-data | Training-data dirs empty; trainer `SystemExit`s | `trainer/data/` | conservation-gap | high | feature |
| 3 | looknet-load-unused | `loadLookNet` / `s4_load_look_net` declared, zero production callers | `SixFour/Native/SixFourNative.swift:82` | unwired-core | high/med | feature |
| 4 | s4-widen-half-stub | `s4_widen_half_to_q16` unimplemented + uncalled (gene-quantize input edge) | `Native/src/kernels.zig:141` | unwired-core | med→low | feature |
| 5 | decoder-768-vs-384 | NOTES #5/#7 claim 768-DOF; generated emits 384-DOF | `NOTES.md:239-251` | doc-drift | high | mechanical |
| 6 | mlx-never-exercised-stale | NOTES #8 claims MLX never in `smoke_test.py`; Step 3b exists | `NOTES.md:254` | doc-drift | high | mechanical |
| 7 | nonfinite-guard-stale | NOTES #10 claims no NaN guard; guards exist | `NOTES.md:260` | doc-drift | high | mechanical |
| 8 | halting-loss-stale | NOTES #11 claims halting λ never trained; it is | `NOTES.md:262` | doc-drift | high | mechanical |
| 9 | gifencoder-lzw-parity | `s4_gif_assemble` ≡ `GIFEncoder.swift` LZW: no direct parity gate | `Native/src/kernels.zig:985` | parity-gap | med | feature |
| 10 | missing-dither-golden | `s4_dither_frame` no Swift golden gate (Zig+spec have one) | `SixFourTests/GlobalRenderTests.swift:49` | parity-gap | med | feature |
| 11 | missing-palette-srgb8-golden | `s4_palette_oklab_to_srgb8` no Swift golden gate | `SixFourTests/GlobalRenderTests.swift:49` | parity-gap | low | feature |
| 12 | missing-srgb8-oklab-golden | `s4_srgb8_to_oklab_q16` no dedicated golden (any tier) | `Native/src/kernels.zig:1086` | parity-gap | low | feature |
| 13 | log-callback-no-test | `s4_set_log_callback` untested from Swift (telemetry, off-path) | `Native/src/kernels.zig:26` | hygiene | low | feature |
| 14 | doc-drift-lloyd-iters | Lloyd iter count divergence (GPU 15 / spec 3 / shipped 0) undocumented in Zig | `Native/src/kernels.zig:213` | doc-drift | med | mechanical |
| 15 | doc-drift-stbn3d | STBN3D determinism/no-regenerate contract undocumented in Zig | `Native/src/kernels.zig:519` | doc-drift | low | mechanical |
| 16 | spec-lattice-unbuilt | `Spec.Lattice` Cardinal-Law enforcement is `[PLANNED]` only | `docs/SIXFOUR-DESIGN-LANGUAGE.md:5,95` | unwired-core | high | feature |
| 17 | palette-search-design-only | `PaletteSearch` MCTS spec-complete, zero iOS consumer | `spec/src/SixFour/Spec/PaletteSearch.hs` | unwired-core | low | feature |
| 18 | palette-tree-unlabeled | `PaletteTreeView` split planes drawn but axis/threshold unlabelled | `SixFour/UI/Components/PaletteTreeView.swift:72` | hygiene | low | feature |
| 19 | unwired-probe | `s4_probe` toolchain link smoke test, zero production callers | `Native/src/root.zig:26` | hygiene | low | feature |
| 20 | cube-doc-superseded | ✅ RESOLVED 2026-06-05 — banner-marked + moved to `docs/archive/cube-generated-uiux-system.md` | `docs/archive/cube-generated-uiux-system.md:1` | doc-drift | med | done |
| 21 | cell-lattice-36-cells | ✅ RESOLVED 2026-06-05 — doc archived (`docs/archive/cell-lattice-widget-spec.md`); the 36-cell digression no longer lives in any active doc. (Still pin shutter = 34 cells in `Spec.Lattice`.) | `docs/archive/cell-lattice-widget-spec.md` | doc-drift | low | done |

---

## Band 1 — Wire the collapse fold into the render path (keystone)

### 1. `s4_gif_encode_burst` is unimplemented (Stage-0 stub) — `stub-gif-encode-burst`
- **File:** `Native/src/kernels.zig:112` · class: unwired-core · sev: high · fixKind: **feature**
- **Evidence:** The whole-burst entrypoint ("linear-sRGB halfs → deterministic GIF89a bytes",
  `kernels.zig:111`) discards all params and returns `RC_NOT_IMPLEMENTED` (`:131-137`).
  `kernels.zig:13-15` notes every kernel returns `S4_RC_NOT_IMPLEMENTED` until its spec-first
  stage. The Swift seam `SixFourNative.encodeBurst` (`SixFourNative.swift:139`) wraps it and
  returns nil until the body lands; a repo-wide grep for callers of `encodeBurst` found ZERO.
  Tests (`kernels.zig:1454`, `gif_fixture_test.zig`) only assert it returns NOT_IMPLEMENTED.
- **Why it's core:** this is the `state = fold(apply)` spine; the deterministic quantized-core
  entrypoint does not yet exist on the app path.
- **Fix:** implement as the end-to-end entrypoint — Metal halfs → Q16 `linearToOklab` →
  `quantize` → `dither` → `palette_oklab_to_srgb8` → `gif_assemble`, byte-exact against Haskell
  goldens across spec-first stages. Note the live device path is the per-stage
  `DeterministicRenderer` chain; this monolithic path is a separate, dormant rollout.

---

## Band 2 — Mint/apply gene-quantize boundary + loadLookNet

### 2. Training-data directories are empty — `empty-training-data`
- **File:** `trainer/data/` · class: conservation-gap · sev: high · fixKind: **feature**
- **Evidence:** `ls trainer/data/captured_frames/` and `…/reference_gifs/` are both 0 files.
  The metric trainer hard-fails: `train_metric.py:131`
  `raise SystemExit(f"No GIFs in {data_dir}…")` (default `--data-dir data/reference_gifs`,
  `:168`). `NOTES.md:234` corroborates. `SETUP.md:30` instructs dropping reference GIFs there.
  Without data the float σ-pair genome can never be minted.
- **Scope note:** only `train_metric.py` (the 9-param OKLab metric trainer) hard-depends on
  these dirs. `train_look_net_mlx.py` does NOT — it imports `zig_native` (`zn.gif_to_tokens`)
  as a synthetic data engine and never reads `data/{captured_frames,reference_gifs}`.
  `captured_frames` has no code reader at all today.
- **Fix:** populate `trainer/data/reference_gifs` via a documented acquisition path — real
  on-device session captures, or the Zig synthetic-GIF engine (`s4_synth_burst`,
  `Native/src/synth.zig:130`, wired via `trainer/zig_native.py:108`) writing `.gif` files —
  and add a smoke test that `train_metric.py` runs to completion. Define or document/remove
  `captured_frames`.

### 3. `loadLookNet` / `s4_load_look_net` has zero production callers — `looknet-load-unused`
- **File:** `SixFour/Native/SixFourNative.swift:82` · class: unwired-core · sev: high · fixKind: **feature**
- **Evidence:** `loadLookNet` (`:82-110`) wraps Zig `s4_load_look_net`. Repo-wide grep: the
  only callers of `s4_load_look_net` are tests (`Native/src/fixture_test.zig`,
  `Native/src/root.zig:209+`); no production Swift call site. The returned `LookNetWeights`
  fields (phi/w1/w2/heads) are never read; there is no `forwardLookNet`/inference path in
  `SixFour/`. `SIXFOUR-ARCHITECTURE-MAP.md:44`: "`loadLookNet` (`:82`) is **load-only with
  zero callers**." Deferral matches deployment state (no trained blob, empty data dirs).
- **Stale-comment caveat:** `SixFourNative.swift:79-81` calls the Zig kernel a "declared
  contract… real parse may land beyond the `s4_probe` spike" — but `root.zig:72-145` is a
  complete, bounds-checked, tested parser. Minor doc inaccuracy, not blocking.
- **Fix:** build-order step 5 (`ARCHITECTURE-MAP.md:72`): once colour weights exist, hand-write
  the Swift/Accelerate (or Metal) forward pass that calls `loadLookNet`, computes the Haar
  decode via `s4_haar_reconstruct`, and expands σ-pair coefficients → 256-leaf palette. Gate
  vs golden vectors. **Correctly deferred** behind Phase-2 trainer completion.

### 4. `s4_widen_half_to_q16` unimplemented + uncalled — `s4-widen-half-stub`
- **File:** `Native/src/kernels.zig:141` · class: unwired-core · sev: med→**low** · fixKind: **feature**
- **Evidence:** discards all params and returns `RC_NOT_IMPLEMENTED` (`:141-144`); declared
  `sixfour_native.h:124`; asserted-stub test `kernels.zig:1453`. No Swift wrapper exists.
  Its only intended consumer is the monolithic `s4_gif_encode_burst` (itself a stub), whose
  Swift wrapper `encodeBurst` has zero callers. The live device path reads Metal Float16 halfs
  back as `[UInt16]` bit patterns, never needing a Zig half-widening step.
- **Severity:** downgrade to **low** — nothing live depends on it; it sits entirely on a
  dormant, deferred path.
- **Fix (either, both code):** (A) implement as a real IEEE-half→Q16 kernel with the pinned
  rounding rule + a Haskell-golden fixture test, keeping the composable-sub-kernel ABI
  complete; or (B) if the Swift-reads-halfs path has truly settled, remove the decl
  (`sixfour_native.h:124`), the stub (`kernels.zig:141-144`), AND the assertion test
  (`kernels.zig:1453`). There is no `SixFourNative.swift` reference to remove. Do not implement
  in isolation today (would add unexercisable dead code); revive or retire the whole burst path
  as a spec-first stage with a real caller.

---

## Band 3 — Lock the 384-DOF contract / purge 768 (doc-drift, all mechanical)

> A single codegen change (commit `7c55d56`, "Group C: MLX verification gaps + PonderNet
> halting loss") landed the 384-DOF pivot, MLX verification arms, and halting loss, but
> NOTES.md §§B/C were never reconciled. Items 5–8 are all stale prose in NOTES.md and should
> be closed in one edit pass.

### 5. NOTES #5/#7 claim 768-DOF and missing SIGMA_PAIR pins — `decoder-768-vs-384`
- **File:** `NOTES.md:239-251` · class: doc-drift · sev: high · fixKind: **mechanical**
- **Evidence:** NOTES.md:240 says `look_net_mlx.py:32 DECODER_OUT_DIM=768`. Actual
  `look_net_mlx.py:33` (and `look_net_torch.py:33`) read `DECODER_OUT_DIM = 384 # = SIGMA_PAIR_DOF`,
  emit `(B,384)` SigmaPairTree coeffs, reconstruct the 256-leaf palette. NOTES #7 claims "Zero
  hits for `SIGMA_PAIR`" — but `SIGMA_PAIR_DOF=384/DEPTH=7/LEAVES=256` are now codegen-emitted:
  `look_net_mlx.py:40-42`, `look_net_torch.py:40-42`, `net_shape.py:37`,
  `NetContract.swift:48` (LEAVES), `contract.rs:23-25`. Spec derives it:
  `LookNetD.hs:117 decoderOutputDim = sigmaPairDegreesOfFreedom`, `SigmaPairHead.hs:104`,
  assertion `LookNetD.hs:315 decoderOutputDim == 384`.
- **Fix:** mark NOTES #5 (`:239-244`) AND #7 (`:248-251`) CLOSED — generated MLX/torch/net_shape
  emit `DECODER_OUT_DIM=384` and pin the SIGMA_PAIR constants; sources are
  `Burn.hs:58-61→contract.rs:23-25`, `Shapes.hs→net_shape.py:37`,
  `CoreML.hs:89-98→look_net_torch.py:40-42`, `MLX.hs→look_net_mlx.py:40-42`,
  `Swift.hs:319→NetContract.swift:48`. (Note: `Swift.hs` emits only the `SIGMA_PAIR_LEAVES`
  aux-dim, not the DOF/DEPTH constants.)

### 6. NOTES #8 claims MLX never exercised in smoke_test — `mlx-never-exercised-stale`
- **File:** `NOTES.md:254` · class: doc-drift · sev: high · fixKind: **mechanical**
- **Evidence:** NOTES.md:254 says "MLX is never exercised in `smoke_test.py`". But
  `trainer/smoke_test.py:73-106` is "Step 3b: MLX σ-equivariance numerical check (bit-exact)":
  `import mlx.core as mx` (`:78`), `import look_net_mlx as mlxm` (`:79`), transfers torch
  state_dict into MLX (`:83-92`), asserts `mlx_delta != 0.0` fails (`:104-105`). Same additions
  also stale #9 (Step 3c MLX↔torch allclose, `:108-123`).
- **Fix:** see Mechanical Fixes appendix.

### 7. NOTES #10 claims no NaN/non-finite guard — `nonfinite-guard-stale`
- **File:** `NOTES.md:260` · class: doc-drift · sev: high · fixKind: **mechanical**
- **Evidence:** NOTES.md:260 says "No NaN / non-finite guard in `check_golden.py`". But
  `check_golden.py:101-103` (`run_torch`) and `:132-134` (`run_mlx`) both contain
  `if not np.all(np.isfinite(out)): diffs.append((c["name"]+":nonfinite", float("inf"))); continue`.
- **Fix:** see Mechanical Fixes appendix.

### 8. NOTES #11 implies halting loss never trained — `halting-loss-stale`
- **File:** `NOTES.md:262` · class: doc-drift · sev: high · fixKind: **mechanical**
- **Evidence:** NOTES.md:262 says "PonderNet halting λ_ℓ is computed but never trained". But
  `Spec.Loss` defines `haltingDistribution` (`Loss.hs:314`), `geometricPrior` (`:325`),
  `haltingLoss` (`:343-346`) with laws (`:454-478`); `look_net_loss_mlx.py:173/201` mirror them;
  `train_look_net_mlx.py:103` defines `halting_loss_mx` and ACTIVELY TRAINS it
  (`total = … + args.lam_halt * halt`, gradients via `nn.value_and_grad`).
- **Fix:** see Mechanical Fixes appendix.

---

## Band 4 — Parity & conservation gaps

### 9. `s4_gif_assemble` ≡ `GIFEncoder.swift` LZW: no direct parity gate — `gifencoder-lzw-parity`
- **File:** `Native/src/kernels.zig:985` · class: parity-gap · sev: med · fixKind: **feature**
- **Evidence:** `s4_gif_assemble` claims to "Mirror GIFEncoder.swift / SixFour.Gen.GifWire
  byte-for-byte" (`kernels.zig:982-983`). A spec GIF golden IS generated (`Fixtures.hs:58-62` →
  `gif_golden.gif`/`gif_golden_indices.bin`/`gif_golden_palettes.bin`). But grep for
  `gif_golden`/`gifAssemble`/`s4_gif_assemble` across `SixFourTests/` returns ZERO hits.
  `GlobalRenderTests.swift` only asserts the `GIF89a` magic prefix (`:45`) + sha256
  self-determinism (`:138`), never byte-equality vs golden or vs Swift. `GIFEncoderTests.swift`
  tests Swift LZW in isolation (`:89`) and never touches the Zig kernel. The RECOMPUTED parity
  the Zig comment asserts is UNVERIFIED — the precedent (`ZigCollapseGoldenTests`) exists for
  collapse but not assemble.
- **Fix:** add a Zig/Swift GIF-assemble golden parity test mirroring `ZigCollapseGoldenTests`.
  No codegen emits a Swift-consumable GIF golden (it lands only as raw `.gif`/`.bin` in
  `trainer/out/`, not in the test bundle), so this needs NEW wiring: either (a) a
  `Codegen/GifGolden.hs` emitting a Swift enum (indices + sRGB8 palettes + expected GIF bytes)
  like `Collapse.hs`, or (b) wire `gif_golden.gif`/`.bin` into `SixFourTests` as resources.
  Then `ZigGifAssembleGoldenTests.swift` asserting `SixFourNative.gifAssemble(...)` bytes ==
  golden, and cross-check `GIFEncoder.swift` byte-matches Zig.

### 10. `s4_dither_frame` has no Swift golden gate — `missing-dither-golden`
- **File:** `SixFourTests/GlobalRenderTests.swift:49` · class: parity-gap · sev: med · fixKind: **feature**
- **Evidence:** `s4_dither_frame` (`kernels.zig:519`) is invoked from Swift only via the full
  render path (`DeterministicRenderer.swift:130,316` → `SixFourNative.ditherFrame:238`).
  `GlobalRenderTests` exercises it indirectly; grep of `SixFourTests` shows NO test loading
  `dither_golden.json` or asserting per-pixel `ditherFrame` indices per mode. The dedicated
  golden gate exists ONLY on the Zig side (`dither_fixture_test.zig:34`, consuming
  `trainer/out/dither_golden.json` from `Fixtures.hs:68`). The Swift third-home parity gate is
  genuinely missing. (Cross-device determinism is already Haskell↔Zig-proven, so this is a
  coverage gap, not a live determinism break.)
- **Fix:** add a Haskell `Codegen/Dither.hs` (mirroring `Codegen/Collapse.hs`) emitting
  `SixFour/Generated/DitherGolden.swift` (side, k, centroids Q16, pixels, thresholds, per-(mode,
  serpentine) expected indices) from `Spec.SpatialDither.ditherFrameQ16`; wire into the codegen
  driver (`spec/app/Gen.hs`) + drift gate (`project.yml`). Then `ZigDitherGoldenTests.swift`
  for the 4 cases (FS raster, FS serpentine, Atkinson, blue-noise) + a pure-Swift `Dither` path
  parity check. New codegen + test wiring, not a mechanical edit.

### 11. `s4_palette_oklab_to_srgb8` has no Swift golden gate — `missing-palette-srgb8-golden`
- **File:** `SixFourTests/GlobalRenderTests.swift:49` · class: parity-gap · sev: low · fixKind: **feature**
- **Evidence:** `s4_palette_oklab_to_srgb8` (`kernels.zig:809`) reachable from Swift only via
  `SixFourNative.paletteToSRGB8:365`. The sole Swift test, `GlobalRenderTests.swift:48-51`,
  compares the kernel output against the SAME kernel call — a tautology. No
  `ColorGolden`/`PaletteColorGolden` exists in `SixFour/Generated/`; no `Codegen/Color.hs`.
  `ColorScienceTests.swift` gates the Swift float `ColorScience.okLabToSRGB8`, NOT the Zig
  kernel. Cross-language determinism IS already gated from Zig (`color_fixture_test.zig:69-83`),
  so this is defense-in-depth, hence low.
- **Fix:** create `spec/src/SixFour/Codegen/Color.hs` emitting
  `SixFour/Generated/ColorGolden.swift` ({Q16 OKLab → sRGB8} cases from `Spec.ColorFixed`),
  register in spec-codegen, regenerate. Add `ZigPaletteColorGoldenTests.swift` asserting
  `SixFourNative.paletteToSRGB8(...)` == golden bytes.

### 12. `s4_srgb8_to_oklab_q16` has no dedicated golden (any tier) — `missing-srgb8-oklab-golden`
- **File:** `Native/src/kernels.zig:1086` · class: parity-gap · sev: low · fixKind: **feature**
- **Evidence:** No dedicated golden in any tier: zero Swift callers (only
  `trainer/zig_native.py:91-92,198` via ctypes); no Zig `test` block names it (Zig color goldens
  cover only `linear_to_oklab_q16` @1379 and `palette_oklab_to_srgb8` @1398);
  `spec/test/Properties/ColorFixed.hs` covers forward linear→OKLab and inverse OKLab→sRGB8 but
  never sRGB8→linear→OKLab. The finding's claim that `GIFEncoderTests` covers it via
  `gifDecodeRoundTrip` is FALSE — that test uses a private Swift LZW decoder, never this kernel.
- **Fix:** add the test where the kernel lives, NOT in Swift (zero Swift callers). Option A
  (preferred): a Zig test asserting `s4_srgb8_to_oklab_q16(known triples)` == precomputed OKLab
  Q16 anchors matching the Haskell oracle (`srgbLinLut` ∘ `linearToOklabQ16` from
  `Spec.ColorFixed`). Option B: a Haskell property in `ColorFixed.hs` round-tripping
  sRGB8→linear→OKLab vs the Double oracle.

### 13. `s4_set_log_callback` untested from Swift — `log-callback-no-test`
- **File:** `Native/src/kernels.zig:26` · class: hygiene · sev: low · fixKind: **feature**
- **Evidence:** Swift installs the callback at startup (`SixFourNative.swift:33-43`). No Swift
  test exercises it. The mechanism IS already tested in Zig (`kernels.zig:1424-1439`: registers
  `testLogSink`, asserts `test_log_count>=1` + the `palette` tag + silent-when-unset).
  `debtClass` corrected from "determinism-violation" → **hygiene**: `kernels.zig:21-22` states
  logging is "telemetry, outside the deterministic contract… Logs never affect the returned
  bytes" — off the deterministic path, cannot violate determinism.
- **Fix:** optional, low priority. If desired, a Swift test calling
  `SixFourNative.installLogging()` then a kernel, capturing `os.Logger` via a test sink (needs a
  capturable Logger sink = net-new infra). Deterministic guarantee already covered in Zig.

---

## Band 5 — Determinism / float-drift documentation

### 14. Lloyd iteration-count divergence undocumented in Zig — `doc-drift-lloyd-iters`
- **File:** `Native/src/kernels.zig:213` · class: doc-drift · sev: med · fixKind: **mechanical**
- **Evidence:** `s4_quantize_frame` takes `lloyd_iters` as a required param (`:217`). Counts
  differ across impls: spec `StageA.hs:88` uses `lloyd 3`; Metal `Shaders.metal:285` says "full
  15-iteration k-means"; Swift `SixFourNative.swift:121` defaults `lloydIters=15`;
  `gif_fixture_test.zig:64` pins 15. The SHIPPED deterministic capture path passes **0**
  (`CaptureViewModel.swift:672`, `DeterministicRenderer.swift:73`), and `s4_global_collapse`
  passes 0 (`kernels.zig:359`). It is an UNRESOLVED open question (`NOTES.md:146`, `:187` §6 Q4).
  The Zig doc (`kernels.zig:207-212`) explains maximin+optional Lloyd but never the count
  divergence or cross-impl parity requirement. Byte-exactness requires the same count across
  Zig/Swift/Metal for a given path. (The spec's "3" is the Wu variance-cut lineage, a DIFFERENT
  seeder; the maximin mirror is `QuantFixed.hs`, whose `:98` already says "0 = pure maximin".)
- **Fix:** see Mechanical Fixes appendix.

### 15. STBN3D determinism contract undocumented in Zig — `doc-drift-stbn3d`
- **File:** `Native/src/kernels.zig:519` · class: doc-drift · sev: low · fixKind: **mechanical**
- **Evidence:** `s4_dither_frame` takes `stbn_slice` and uses it only as a lookup table
  (`:563`), with no comment on its canonical origin/size/no-regenerate contract. Supporting
  facts: `Spec/STBN3D.hs:76` is the void-and-cluster mask doc; `Resources/stbn3d-8.bin` is
  exactly 512 bytes; `NOTES.md:85-87/122/153` say "never regenerate" + warn "Euclidean ≠
  toroidal mask"; Swift `STBN3DMaskLoader.loadTiled()` (`DeterministicRenderer.swift:100`,
  `PaletteGenerator.swift:92`) does the 8×8→64³ tiling + per-frame slice. The kernel is the
  silent consumer of an unvalidated, semantically-loaded table.
- **Fix:** see Mechanical Fixes appendix. (Producer is `spec/app/Spec.hs:89`, NOT `Fixtures.hs`.)

---

## Band 6 — Hygiene & UI honesty

### 16. `Spec.Lattice` Cardinal-Law enforcement is `[PLANNED]` only — `spec-lattice-unbuilt`
- **File:** `docs/SIXFOUR-DESIGN-LANGUAGE.md:5,95` · class: unwired-core · sev: high · fixKind: **feature**
- **Evidence:** `grep -rln Lattice --include=*.hs` returns ZERO; no `Codegen/Lattice.hs`. The
  doc self-marks the gap: `:5` (enforcement machinery unbuilt), `:95` (SFTheme interim authority
  until Spec.Lattice ships), `:151/:170/:171` closure-law `[PLANNED]` (25 tags total). §10.2
  (`:663-665`) places it as phase 2 after GATE-DECISIONS; Cardinal Law #8 (golden gate) is
  itself `[PLANNED]` (`:30`), §9.2 (`:616`) calls it "a tracked TODO, not a present guarantee."
  The Swift `GlobalLattice` owner exists (`SixFour/UI/GlobalLattice.swift`), so cell-math
  ownership is partially shipped, but the Haskell golden that pins/verifies those numbers is
  absent — the Cardinal Laws are doc-true but not machine-checked.
- **Fix:** build `Spec.Lattice` (§10.2 phase 2): band map, golden split (LAW-GOLDEN), token
  tiering, single-pitch predicate, closure laws (§3.3), θ→cell tick table,
  luminance/contrast functions. Emit golden vectors; wire cabal test gate for Swift mirrors.

### 17. `PaletteSearch` MCTS spec-complete, zero iOS consumer — `palette-search-design-only`
- **File:** `spec/src/SixFour/Spec/PaletteSearch.hs` · class: unwired-core · sev: low · fixKind: **feature**
- **Evidence:** The only non-Haskell reference is a doc comment at
  `SixFour/Palette/PaletteValue.swift:18` ("UNWIRED… no runtime caller until the deferred
  PaletteSearch feature lands"). Zero Swift imports, Rust bindings, or trainer consumers. Spec
  (336 lines, not the 234 in arch-map — minor stale count) + property tests
  (`spec/test/Properties/PaletteSearch.hs`). `ARCHITECTURE-MAP.md:74` explicitly defers it:
  "spec-complete, no iOS consumer; wire only after steps 1–5 give it a real collapsed palette to
  search over." **Correctly deferred** (depends on the working global-collapse render path).
- **Fix:** Phase-3 — once `s4_global_collapse` is wired and produces a byte-identical GIFB
  candidate, port `PaletteSearch` to Swift/Rust (or keep calling from the MLX trainer) and wire
  as an optional post-render refinement step.

### 18. `PaletteTreeView` split planes unlabelled by axis/threshold — `palette-tree-unlabeled`
- **File:** `SixFour/UI/Components/PaletteTreeView.swift:72` · class: hygiene · sev: low · fixKind: **feature**
- **Evidence:** (Cited path corrected — actual is `UI/Components/`, not `Palette/Views/`.)
  `draw` renders split planes via `ctx.fillBorder(rect, width: lw, color: SFTheme.treemapPlane)`
  with `lw` scaling by `(maxDepth-depth)` — borders carry depth but NO axis/threshold text. The
  drawn `NaryNode` (`SplitTree.swift:126-128`) has only `.leaf`/`.branch([NaryNode])` and
  discards the axis+pos that the source `SplitTree.branch(axis:pos:…)` holds; `collapse`
  (`:105-108`) drops them. `ARCHITECTURE-MAP.md:55` flags it as the smallest first truth-win.
- **Fix:** thread axis+pos through `NaryNode` and add text rendering in `draw()`. Code change.

### 19. `s4_probe` toolchain link smoke test, zero callers — `unwired-probe`
- **File:** `Native/src/root.zig:26` (NOT `kernels.zig:26` — finding mislocated) · class: hygiene · sev: low · fixKind: **feature**
- **Evidence:** `export fn s4_probe(x: u32) u32 { return x +% 1; }` at `root.zig:26`; header
  decl `sixfour_native.h:18` ("Used by the build/link smoke test only"); Swift wrapper
  `SixFourNative.swift:24-26` ("Toolchain/link smoke test… remove once a real kernel ships").
  Repo-wide grep for `.probe(` across `SixFour/`+`SixFourTests/` shows ZERO callers of the
  wrapper (other `probe` hits are unrelated: format-probing, centroid probes, shape-probe).
- **Fix (feature, not mechanical):** if removed, delete from `root.zig:26-28`,
  `sixfour_native.h:17-18`, `SixFourNative.swift:22-26`, the doc-line `SixFourNative.swift:80-81`,
  and `APP-MAP.md:99`, THEN re-point the build/link smoke test onto a real always-present kernel
  (e.g. `s4_burst_scratch_bytes`). Multi-file ABI rewiring. Safer alternative: keep a minimal
  dedicated probe for CI link verification and only fix the mislocated cite.

### 20. `cube-generated-uiux-system.md` not banner-marked SUPERSEDED — `cube-doc-superseded` — ✅ RESOLVED 2026-06-05
- **Resolution:** ARCHIVED banner applied and moved to `docs/archive/cube-generated-uiux-system.md` in the docs-consolidation pass. No longer regenerates 6 pt tokens from an unmarked "source of truth."
- **File:** `docs/archive/cube-generated-uiux-system.md:1` · class: doc-drift · sev: med · fixKind: **done**
- **Evidence:** `:3` reads "**Status:** spec (source of truth → Haskell golden → SwiftUI/Metal)"
  with no superseded banner. `SIXFOUR-DESIGN-LANGUAGE.md:658` dispositions it "**SUPERSEDED for
  sizing (pending migration).** Add an in-file header banner" + warns "Left un-marked, it keeps
  regenerating 6 pt tokens — the exact failure the user is angry about."
- **Fix:** see Mechanical Fixes appendix.

### 21. Stray "36 cells" digression must be deleted — `cell-lattice-36-cells` — ✅ RESOLVED 2026-06-05
- **Resolution:** `cell-lattice-widget-spec.md` ARCHIVED (`docs/archive/`) — the 36-cell digression no longer lives in any active doc; DESIGN-LANGUAGE is sole sizing canon. Residual action: pin shutter = 34 cells in `Spec.Lattice` (code, tracked separately).
- **File:** `docs/archive/cell-lattice-widget-spec.md` · class: doc-drift · sev: low · fixKind: **done**
- **Evidence:** `:30` reads "Shutter = `shutterSidePt = gifCellPt×12 = 72pt`. At 2pt that is
  **36 cells** (prior pitches said 34 — wrong, critique 2/3)." `SIXFOUR-DESIGN-LANGUAGE.md:657`
  mandates: "delete its stray '36 cells' digression so a future author cannot re-derive 36; pin
  shutter = 34 cells in `Spec.Lattice`." Note: 72pt at cellPt=2 genuinely IS 36 cells — the
  intent (`:152`, `:166`) is to DELETE the stale 72pt→36 derivation, NOT to re-label 72pt as 34
  cells (that would plant a new arithmetic error). `Spec.Lattice` does not exist yet, so do not
  cite it.
- **Fix:** see Mechanical Fixes appendix.

---

## Appendix A — Mechanical fixes (safe to apply now)

Pure doc/string/dead-comment edits, no code change, no wiring. Apply today.

### A1. `NOTES.md` §§B/C — close stale items 5, 7, 8, 9, 10, 11
One reconciliation pass (all landed in commit `7c55d56`, never folded back):
- **Item #5** (`:239-244`): replace "Decoder still emits 768-DOF Haar…" → CLOSED; generated
  `look_net_mlx.py:33`/`look_net_torch.py:33` read `DECODER_OUT_DIM = 384` and reconstruct the
  256-leaf σ-pair palette.
- **Item #7** (`:248-251`): replace "No `SIGMA_PAIR_*` codegen pins emitted anywhere…" → CLOSED;
  `SIGMA_PAIR_DOF=384/DEPTH=7/LEAVES=256` emitted at `look_net_mlx.py:40-42`,
  `look_net_torch.py:40-42`, `net_shape.py:37`, `NetContract.swift:48`, `contract.rs:23-25`
  (sources `Burn.hs:58-61`, `Shapes.hs`, `CoreML.hs:89-98`, `MLX.hs`, `Swift.hs:319`).
- **Item #8** (`:254`): replace "**MLX is never exercised in `smoke_test.py`**" →
  "**MLX σ-equivariance is verified in `smoke_test.py` Step 3b**" (`smoke_test.py:73-106`).
- **Item #9** (`:257`): mark closed — `smoke_test.py` Step 3c (`:108-123`) is a same-weights
  MLX↔torch `allclose` at rtol 1e-5.
- **Item #10** (`:260`): replace "**No NaN / non-finite guard in `check_golden.py`**" →
  "**NaN / non-finite guard implemented in `run_torch` and `run_mlx`**" (`check_golden.py:101-103`,
  `:132-134`).
- **Item #11** (`:262-264`): replace "**PonderNet halting λ_ℓ is computed but never trained**" →
  "**PonderNet halting loss trained via KL(halting-dist ‖ geometric-prior)** in
  `Spec.Loss.haltingLoss` (`Loss.hs:343`), mirrored in `look_net_loss_mlx.py` and actively
  trained in `train_look_net_mlx.py:103` (`total += lam_halt·halt`)."

### A2. `Native/src/kernels.zig` ~`:518` — STBN3D contract comment (add to `s4_dither_frame`)
> `stbn_slice` MUST be one frame (p bytes) of the canonical STBN3D mask: the 8³ void-and-cluster
> scalar mask (`stbn3d-8.bin`, 512 bytes, toroidal Euclidean distance) tiled 8×8→64³ pixels by
> the Swift caller (`STBN3DMaskLoader.loadTiled`). Pre-computed off-device, pinned by
> `Spec/STBN3D.hs` + `Generated/STBN3DContract.swift`; canonical bytes emitted by
> `spec/app/Spec.hs` (`writeBinary stbn3d-8.bin`). Never regenerate — Euclidean ≠ toroidal mask
> would break cross-device determinism (NOTES.md §STBN3D).

### A3. `Native/src/kernels.zig` ~after `:212` — Lloyd iteration-count comment (`s4_quantize_frame`)
> `lloyd_iters`: caller chooses; 0 = pure maximin (the diversity/coverage objective). The shipped
> deterministic capture path and `s4_global_collapse` pass 0; the GPU/full-pipeline Swift path
> and gif fixtures use 15. Standardizing the device count (15 GPU-parity vs 3 spec variance-cut)
> is an OPEN question (NOTES.md §4, §6 Q4). Byte-exactness requires the same count across
> Zig/Swift/Metal for a given path.

### A4. `docs/cube-generated-uiux-system.md` — SUPERSEDED banner — ✅ DONE 2026-06-05
Banner applied and the doc moved to `docs/archive/cube-generated-uiux-system.md` (carries an
ARCHIVED banner). No further action.

### A5. `docs/cell-lattice-widget-spec.md:30` — delete the 36-cell digression — ✅ MOOT 2026-06-05
The doc was ARCHIVED (`docs/archive/cell-lattice-widget-spec.md`), so the 36-cell digression no
longer lives in an active doc. Canonical value: **shutter = 34 cells = 68 pt**. Residual code
action: pin it in `Spec.Lattice` once that module lands (tracked separately).

---

## Appendix B — Feature backlog (ordered by build sequence)

Each requires code / wiring / design (NOT a doc edit). Top of the spine first.

1. **`stub-gif-encode-burst`** — implement the keystone whole-burst deterministic entrypoint
   (linearToOklab→quantize→dither→palette→gif_assemble), byte-exact vs Haskell goldens. [high]
2. **`empty-training-data`** — populate `trainer/data/reference_gifs` (synthetic via
   `s4_synth_burst` or real captures) + smoke test `train_metric.py` to completion. [high]
3. **`looknet-load-unused`** — hand-write the on-device Swift/Accelerate(Metal) forward pass
   that calls `loadLookNet` + `s4_haar_reconstruct`, expanding σ-pair coeffs → 256-leaf palette;
   gate vs golden. (Blocked on trained colour weights.) [high]
4. **`s4-widen-half-stub`** — implement (with Haskell-golden fixture) OR retire the kernel +
   its stub test; only as part of reviving/retiring the burst path. [low]
5. **`spec-lattice-unbuilt`** — build `Spec.Lattice` Haskell golden enforcing the Cardinal Laws
   (band map, golden split, single-pitch predicate, closure laws); wire the cabal gate. [high]
6. **`gifencoder-lzw-parity`** — Codegen `GifGolden.swift` (or bundle `gif_golden.*`) +
   `ZigGifAssembleGoldenTests` asserting Zig ≡ Swift ≡ golden bytes. [med]
7. **`missing-dither-golden`** — `Codegen/Dither.hs` → `DitherGolden.swift` +
   `ZigDitherGoldenTests` (4 dither cases) + pure-Swift parity. [med]
8. **`missing-palette-srgb8-golden`** — `Codegen/Color.hs` → `ColorGolden.swift` +
   `ZigPaletteColorGoldenTests`. [low]
9. **`missing-srgb8-oklab-golden`** — Zig (or Haskell) golden for `s4_srgb8_to_oklab_q16`;
   NOT a Swift test. [low]
10. **`palette-search-design-only`** — Phase-3: port `PaletteSearch` to Swift/Rust + wire as
    optional post-render refinement (after global-collapse path works). [low]
11. **`palette-tree-unlabeled`** — thread axis+pos through `NaryNode` + render axis/threshold
    labels in `PaletteTreeView.draw()`. [low]
12. **`log-callback-no-test`** — optional Swift log-sink coverage test (needs capturable Logger
    sink). [low]
13. **`unwired-probe`** — optionally remove `s4_probe` across the ABI + re-point CI link check to
    a real kernel; or keep + fix the mislocated cite. [low]

**Feature backlog count: 13.**

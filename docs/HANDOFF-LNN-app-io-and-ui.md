> **Status/built-state:** see [docs/STATUS.md](STATUS.md) (canonical, gated by `scripts/verify-doc-claims.sh`). This document is design rationale, not a status ledger.

# Handoff — wiring the L-NN into the app (I/O + UI surfacing)

**Purpose of next session:** take the trained L-NN nucleus and (1) wire it into the app's
GIF **input → output** path, and (2) **surface it in the UI** so the user understands the NN
as a *tool to refine their looks*. This doc is the map: current state, the exact seams to
touch (file:line), and the UI design.

Sister docs: training regimen → `trainer/TRAINING.md`; full design + history →
`~/.claude/plans/smooth-roaming-flamingo.md` and memory `sixfour-look-nn-lab-training-workflow`.

---

## 0. Where we are (current state)

- **The L-NN nucleus is designed, trained-on-M1-by-you, and deploy-ready.** It maps a 64³
  **colour** per-frame-palette GIF → a single **global grayscale** 256-level palette → a global
  GIF. It beats the 256-level Wasserstein-barycenter baseline on held-out captures (5/6, often ~3×).
- **Weights ship as a blob:** `trainer/out/look_net_trained.s4ln` (133,923 B), loadable by the
  Zig `s4_load_look_net` (verified). Produced by the regimen (`trainer/regimen.py`).
- **What EXISTS on device:** the blob **loader** only — `SixFourNative.loadLookNet(_:) -> LookNetWeights`
  (`SixFour/Native/SixFourNative.swift:82`), plus the per-frame kernels (`quantizeFrame`,
  `ditherFrame`, `paletteToSRGB8`, `gifAssemble`).
- **What does NOT exist yet (the work):** (a) the on-device **forward pass** (token → palette);
  (b) the **global re-index** (all frames → one palette); (c) any **UI** for the NN. The app
  today only makes **per-frame-local-palette** GIFs (`GIFRenderer`/`DeterministicRenderer`).

---

## 1. App I/O — wiring the NN (input GIF → forward → output GIF)

The pipeline to build, end to end:

```
colour per-frame-palette GIF (or live capture's per-frame palettes)
   │  ① tokenize: decode → μ=srgb8→oklab, Σ=0, w=population, pooled  (gif_to_tokens twin)
   ▼
② L-NN forward pass (load blob → weighted-pool encoder → halting recursion → depth-8 L head → σ)
   ▼  global grayscale palette: 256 distinct L
③ global re-index: assign every frame's pixels to the ONE palette (nearest L)
   ▼
④ assemble single global-LCT grayscale GIF  (s4_gif_assemble, same palette on every frame)
```

### ① Tokenize (the NN input) — mirror `trainer/zig_native.gif_to_tokens`
The input tensor is a **pure function of the GIF** (train==deploy):
- decode the GIF → per-frame indices + sRGB8 LCTs (Zig `s4_gif_decode` — already built),
- per slot: `μ = s4_srgb8_to_oklab_q16(slot)` (built), `Σ = 0` (a GIF has no covariance),
  `w = pixel population`; pool 64×256 → 16384 tokens, normalise `Σw=1`.
- For a **live capture** (not a GIF), the app already has `ClusterStatistics` with real `μ,Σ,count`
  (`ClusterStatistics.swift:50`) → richer tokens (Σ≠0). Decide which input the in-app NN consumes
  (GIF-decoded vs capture-stats) — see Open Questions.

### ② Forward pass (the missing kernel) — mirror `trainer/train_look_net_mlx.generate_palette`
**Critical: the L-NN forward is NOT the generic σ-pair decoder — it's the depth-8 L head.** Mirror
exactly (hand-written Swift/Accelerate or a new Zig kernel, per CLAUDE.md zero-deps):
1. `loadLookNet(blob)` → weights (phi, w1, w2, halt_w/b, heads[8]).
2. **Encoder:** apply σ-block-diagonal mask to `phi`; **weighted** sum-pool tokens by `w` (the
   token_mask) → 64-d context. *(weighted pool, not raw sum — tames the 16384-token magnitude.)*
3. **Recursion:** one shared block (w1,w2, tanh, σ-masked) reused 8× → 9 contexts; σ-invariant
   halt head per context → halting distribution (the *complexity* signal, see UI).
4. **Decoder:** 8 σ-masked heads → 384 coeffs.
5. **L head (the key step):** take `coeffs[:256]` → **depth-8 inverse Haar** (`haar_l_depth8`,
   scalar) → `sigmoid(·)` → **256 distinct L values in (0,1)**. This is the global grayscale palette.
   (The σ-pair `reconstruct_sigma_pair` is for chroma/A,B — do NOT use it for L; it caps L at 128.)
- Reference impl to port verbatim: `trainer/train_look_net_mlx.py` `haar_l_depth8`, `generate_palette`,
  `palette_of`. σ masks: `trainer/generated/look_net_mlx.py` (`_PHI_MASK`, `_SIGMA_MASK`, `_HEAD_MASKS`).
- **Verify against a golden:** emit a forward golden for the L head (extend `Codegen.Golden` /
  `axisnet_golden.json`) so the device forward is bit-checked, like every other tier.

### ③ Global re-index — new render stage (mirror `trainer/global_palette.global_reindex`)
- For each frame, assign each pixel to the nearest global-palette L (`argmin |Lpix − Lpal|`).
- Slot in **between extraction and GIF encode**. Today `PaletteGenerator.generate()` only emits
  per-frame palettes (`GIFRenderer.swift:98`, `DeterministicRenderer.swift:75`); add a
  `useGlobalPalette` branch that produces 64 frames of global indices + 1 LCT.
- Spec reference: `L7 remapFrame` / `globalIndexTensor` (Haskell, spec-only) — port to Swift.

### ④ Assemble — reuse existing
- `SixFourNative.gifAssemble(indices:, palettesRGB:, …)` with the **same** global palette repeated
  for all frames → a global-LCT GIF (valid; or add a true GCT variant later). Palette to sRGB8 via
  `s4_palette_oklab_to_srgb8` on the 256 grayscale OKLab leaves.

### Integration checklist (file:line)
- [ ] `Native/src/` — implement the L-NN forward kernel (or do it in Swift/Accelerate). Add C ABI
      `s4_look_net_forward_l(weights, tokens, …, out_palette_q16)` to `Native/include/sixfour_native.h`.
- [ ] `SixFour/Native/SixFourNative.swift:82` — add `lookNetForwardL(...) -> [SIMD3<Float>]` (256 grey OKLab).
- [ ] New render stage (global re-index) in `SixFour/Encoder/` (GIFRenderer or a new GlobalPaletteRenderer).
- [ ] `Codegen.Golden` — L-head forward golden; cross-check device == MLX == Haskell.

---

## 2. UI surfacing — "the NN is a tool to refine your looks"

**Framing:** the per-frame palette is the *raw capture*; the NN's global palette is a **look** — one
coherent grade across the whole burst. The UI's job: make the NN's look **legible** (what it did and
how well) and **steerable** (let the user influence it). Surface in the **Review** screen primarily
(`SixFour/UI/Screens/Review/GIFReviewView.swift:26`), reusing existing components.

### 2a. Make it LEGIBLE (what the NN did)
- **Before/after toggle** — per-frame-local GIF (today's output) vs the NN global-palette GIF.
  Reuse `GIFCanvas`; add a segmented control. This is the core "what the look does" comparison.
- **The look itself** — render the global palette with `PaletteStripView` (`UI/Components/PaletteStripView.swift`)
  in **static mode** (`palettes.count == 1`) below the GIF; show the per-frame palettes in
  **animated mode** beside it. "One look vs 64 frames" — the collapse made visible.
- **Look complexity (halting)** — surface `E[d]` (expected halting depth) as a "look complexity"
  readout: how many lightness levels this look actually uses (the NN sized it to the scene). This is
  the halting signal made meaningful to the user.
- **Faithfulness** — show the NN-vs-baseline / NN-vs-per-frame L-MSE as a "how faithfully one look
  captures the burst" bar (mirrors the existing per-frame `sig/cov/MSE` line, `GIFReviewView.swift:71`).
- **Dynamic range / grey anchor** — show the look's L span `[Lmin,Lmax]` and grey midpoint
  (`Spec.AxisNet.dynamicRangeOf`/`greyOf`) — "the tonal range of this look."

### 2b. Make it STEERABLE (refine the look)
- **Complexity budget** — a slider that truncates the halting depth at inference (`2^d` levels):
  fewer levels = simpler/posterized look, more = richer. Maps directly to the halting truncation
  already in the trainer. Thread as a new `LookConfig` (mirror `DitherConfig`/`AppSettings`,
  `Settings/AppSettings.swift:62`).
- **Look on/off** — `useLookNetPalette: Bool` in `AppSettings` (persisted), gating the global path.
- **(Future) look variants** — the MAP-Elites / per-user-variance archive (design only) becomes a
  *gallery of looks* the user swipes through; their pick is the refinement signal. This is the
  long-term "refine your look" loop (RLHF-style); note it, don't build it yet.

### UI checklist (file:line)
- [ ] `GIFReviewView.swift:26` — before/after segmented control (per-frame vs global GIF).
- [ ] `GIFReviewView.swift` — add a "Look" panel: `PaletteStripView` (static global) + complexity
      readout (E[d]) + faithfulness bar + dynamic-range/grey-anchor chips.
- [ ] `Settings/AppSettings.swift:62` — add `LookConfig { useLookNetPalette, complexityBudget }`,
      persist + thread through render like `ditherConfig`.
- [ ] `SettingsView.swift:40` — a "Look" section (enable + complexity slider).
- [ ] (Optional) `CaptureView.swift` — a "suggested look" chip from the live NN complexity estimate.

---

## 3. Open questions for next session
1. **In-app NN input = GIF-decoded tokens (Σ=0) or live capture-stats tokens (Σ≠0)?** The model was
   trained on GIF-decoded (Σ=0) — for train==deploy fidelity, feed it the same. But the app has
   richer capture-stats. Decide (and if using capture-stats, consider a Σ≠0 retrain).
2. **Where does the forward pass run** — Swift/Accelerate or a new Zig kernel? (CLAUDE.md: hand-written,
   zero-deps; ~115K params → either is cheap. Benchmark on device.)
3. **Global-LCT vs true GCT GIF** — repeating one LCT works; a real Global Color Table is smaller.
4. **A/B chroma** — this whole doc is the L (grayscale) nucleus. The color look needs M-A/M-B/M-unify
   (the chroma nets keep the σ-pair). UI should be built so adding chroma later is a palette swap, not
   a redesign.

---

## 4. Quick-start commands (next session)
```bash
# train the L-NN (you'll have done this) → out/look_net_trained.s4ln
cd ~/SixFour/trainer && uv run python regimen.py          # gates → train → quality gate → blob
# inspect the look the NN produced on a held-out capture:
uv run python eval_l_quality.py                            # per-seed beats-baseline table
# app build:
cd ~/SixFour && xcodegen generate && xcodebuild -scheme SixFour \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

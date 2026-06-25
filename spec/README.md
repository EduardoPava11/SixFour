# sixfour-spec

Haskell source-of-truth for the SixFour palette pipeline + NN slot signatures.

Layout:

- `src/SixFour/Spec/Shape.hs` — type-level `(T=64, H=64, W=64, K=256)`.
- `src/SixFour/Spec/Color.hs` — sRGB ↔ OKLab (mirrors `SixFour/Color/ColorScience.swift`).
- `src/SixFour/Spec/Palette.hs` — `Palette K OKLab` + `S_K` gauge action.
- `src/SixFour/Spec/Indices.hs` — `IndexTensor T H W K` + `CompleteVoxelVolume` brand (strict per-frame surjectivity).
- `src/SixFour/Spec/Gauge.hs` — Symmetric-group action on `(palette, indices)`.
- `src/SixFour/Spec/StageA.hs` — per-frame quantizer (pinned). Each frame keeps its own 256-colour palette; there is no cross-frame merge.
- `src/SixFour/Spec/Cyclic.hs` — cyclic palette-stack descriptor (deferred-NN feature seam; owns `SinkhornParams` for its entropic-OT transition cost).
- `src/SixFour/Spec/Net.hs` — NN op signatures (slot-agnostic, deferred).
- `src/SixFour/Spec/Laws.hs` — Algebraic laws collected for the test suite.
- `src/SixFour/Codegen/Swift.hs` — Emits Swift contracts to `SixFour/Generated/` (the shipped, zero-dependency iOS app).
- `src/SixFour/Codegen/Shapes.hs` — Emits NumPy shape + significance constants (`stages.py`, `net_shape.py`) to `trainer/generated/`.
- `src/SixFour/Codegen/CoreML.hs` — Emits the look-NN as a PyTorch module + coremltools driver. **Dormant ANE-distillation fallback**, not the shipped path (see repo-root `CLAUDE.md`).
- `src/SixFour/Codegen/Burn.hs` — Emits the dimensional contract + golden cross-check vectors to the Rust `burn` baseline.

## Build

```bash
cd ~/SixFour/spec
cabal build
cabal test
cabal run spec-codegen
```

`cabal run spec-codegen` writes 28 Swift/golden files + the Python trainer contracts + 1 resource:

- `SixFour/Generated/*.swift` — the Swift contracts and byte-exact goldens the hand-written
  Swift/Metal port is verified against (StageContract, NetContract, STBN3DContract,
  SignificanceContract, CollapseGolden, PairTreeGolden, PaletteValueGolden, MaskedBandGolden, …)
- `SixFour/Resources/stbn3d-8.bin` — 8³ STBN3D scalar mask, tiled to 64³ at runtime
- `trainer/generated/stages.py` — NumPy shape/significance constants
- `trainer/generated/{jepa_data,jepa_head,temporal_data}_golden.json` — the H-JEPA data-engine,
  head-trajectory, and inter-frame `(t,t+1)` goldens the `trainer/mlx/` loaders reproduce byte-exact
- `trainer/generated/__init__.py` — empty package marker
- `studio/look-nn-baseline/src/generated/contract.rs` — Rust `burn` dimensional contract + golden vectors

Each contains constants and assertions the iOS app and the Mac-side trainer
import. The Haskell spec is the only source allowed to change those
constants; if they drift, `cabal test` fails and the codegen targets
won't rebuild cleanly.

## How the trainer is gated

The Mac-side H-JEPA trainer lives hand-written in `trainer/mlx/`. The spec is its
**authority**: the goldens above (`jepa_data`, `jepa_head`, `temporal_data`) are emitted from
the spec, and the trainer's Python loaders must reproduce them byte-exact, so a one-byte drift
between the spec and the trainer is a gate failure. The shipped iOS app stays zero-dependency
(hand-written Swift + Metal, verified against the Haskell golden vectors). All emitted files are
kept intentionally (not dead code) so the contracts stay drift-checked. Do not hand-edit them;
change `src/SixFour/Codegen/` and regenerate.

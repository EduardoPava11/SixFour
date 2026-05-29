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

`cabal run spec-codegen` writes 8 files + 1 resource:

- `SixFour/Generated/StageContract.swift`
- `SixFour/Generated/NetContract.swift`
- `SixFour/Generated/STBN3DContract.swift`
- `SixFour/Generated/SignificanceContract.swift`
- `SixFour/Resources/stbn3d-8.bin` — 8³ STBN3D scalar mask, tiled to 64³ at runtime
- `trainer/generated/stages.py`
- `trainer/generated/net_shape.py`
- `trainer/generated/look_net_torch.py` — PyTorch look-NN (CoreML/ANE fallback only; not shipped)
- `trainer/generated/build_mlpackage.py` — coremltools driver (CoreML/ANE fallback only)
- `trainer/generated/__init__.py` — empty package marker
- `studio/look-nn-baseline/src/generated/contract.rs` — Rust `burn` dimensional contract + golden vectors

Each contains constants and assertions the iOS app and the Mac-side trainer
import. The Haskell spec is the only source allowed to change those
constants; if they drift, `cabal test` fails and the codegen targets
won't rebuild cleanly.

## Generated but not yet wired

`NetContract.swift` and `STBN3DContract.swift` are emitted for the planned NN /
STBN3D temporal pipeline; `StageContract.swift` and `SignificanceContract.swift`
are actively consumed by the iOS palette code. The PyTorch/coremltools outputs
(`look_net_torch.py`, `build_mlpackage.py`) are a **dormant ANE-distillation
fallback** — the primary training target is MLX on the M1 and the shipped iOS
app stays zero-dependency (hand-written Swift + Metal, verified against the
Haskell golden vectors). All emitted files are kept intentionally (not dead
code) so the contracts stay drift-checked against the spec. Do not hand-edit
them; change `src/SixFour/Codegen/` and regenerate.

# sixfour-spec

Haskell source-of-truth for the SixFour palette pipeline + NN slot signatures.

Layout:

- `src/SixFour/Spec/Shape.hs` — type-level `(T=64, H=64, W=64, K=256)`.
- `src/SixFour/Spec/Color.hs` — sRGB ↔ OKLab (mirrors `SixFour/Color/ColorScience.swift`).
- `src/SixFour/Spec/Palette.hs` — `Palette K OKLab` + `S_K` gauge action.
- `src/SixFour/Spec/Indices.hs` — `IndexTensor T H W K` + `Surjective256` witness.
- `src/SixFour/Spec/Gauge.hs` — Symmetric-group action on `(palette, indices)`.
- `src/SixFour/Spec/StageA.hs` — Wu per-frame quantizer (pinned).
- `src/SixFour/Spec/StageB.hs` — Sinkhorn-balanced global merger (pinned, witnessed).
- `src/SixFour/Spec/Pipeline.hs` — GADT composing Stage A ; Stage B.
- `src/SixFour/Spec/Net.hs` — NN op signatures (slot-agnostic, deferred).
- `src/SixFour/Spec/Laws.hs` — Algebraic laws collected for the test suite.
- `src/SixFour/Codegen/Swift.hs` — Emits Swift contracts to `SixFour/Generated/`.
- `src/SixFour/Codegen/MLX.hs` — Emits Python contracts to `trainer/generated/`.

## Build

```bash
cd ~/SixFour/spec
cabal build
cabal test
cabal run spec-codegen
```

`cabal run spec-codegen` writes:

- `SixFour/Generated/StageContract.swift`
- `SixFour/Generated/NetContract.swift`
- `trainer/generated/stages.py`
- `trainer/generated/net_shape.py`

Each contains constants and assertions the iOS app and MLX trainer
import. The Haskell spec is the only source allowed to change those
constants; if they drift, `cabal test` fails and the codegen targets
won't rebuild cleanly.

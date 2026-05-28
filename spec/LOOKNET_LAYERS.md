# The look-NN's layers — input, output, and everything between

> **Updated by the 2026-05-27 pivot.** L1–L2 changed: the substrate is the continuous
> OKLab **Gaussian mixture** (`Spec.GMM`), per-component token width **10**, *not* the
> `11·8 = 88` category code. So `L2 Categorize → 88` below is now `L2 GMM token → 10`,
> the encoder is `10 → dM` (set-pooled), and the core `dM → dM` amortizes the
> Wasserstein-2/Bures barycenter (`Spec.Bures`). L5–L9 (the Haar decoder, reconstruct,
> remap, global index, dither) are **unchanged**. The authoritative table is
> `SixFour.Spec.LookNet.lookNetLayers`; the burn crate reads it via the generated
> `studio/look-nn/src/generated/contract.rs` (`Codegen.Burn`).

Working notes (2026-05-26). Companion to `NN_SPACE_NOTES.md` (the palette's
shape) — this fixes the **end-to-end dataflow**: the ordered layers that turn a
capture into the global palette AND the `T×H×W = 64×64×64` index mapping (the whole
GIF). Mirrored by `SixFour.Spec.LookNet`.

## The dimensional table

`dM` = `modelDim` (width, default 64), `N` = `maxPonderDepth` (8). These are the
**only free structural dims**; everything else is pinned by `T=64, H=64, W=64,
K=256` and the Haar tree (`768 = 3·256`).

| # | Layer | in | out | kind |
|---|---|---|---|---|
| L1 | Pool | `CyclicStack T K` = `T·K·4` = 65536 | candidates `65536` | det |
| L2 | Categorize (IB code) | `65536` | `11·8 = 88` | det |
| L3 | Encoder `E` | `88` | `11·dM = 704` | learn |
| L4 | Core `R` | `704` | `dM = 64` (depth ≤ N) | learn |
| L5 | Decoder `D` | `64` | `768` (root + 255 offsets) | learn |
| L6 | Reconstruct | `768` | `256·3 = 768` (balanced) | det |
| L7 | Remap (join +global) | `T·K·3` | `T·K = 16384` | det |
| L8 | GlobalIndex (join +remap) | `T·H·W = 262144` | `262144 ∈ [0,256)` | det |
| L9 | Dither (+STBN3D) | `262144` | `262144` (the GIF) | learn/det |

The **NN proper is L3–L5** (and L9 if the p-field is learned); L1–L2, L6–L8 are the
fixed scaffold. The palette path L1→L6 is a linear chain; the index path L8→L9 is a
linear chain over the voxel tensor; L7 is a fan-in join (palette + local palettes).

## Input — what the NN consumes (and what we can synthesize)

`LookInput`:
- `liStack :: CyclicStack T K` — the 64 per-frame palettes (256 OKLab) + weights.
  **This is synthesizable** today via `analysis-core::synth_stack(p, 64, 256)`.
- `liLocalIndices :: IndexTensor T H W K` — each frame's Stage-A local assignment
  (which local palette slot each of the 4096 pixels took). Synthesizable as a field
  for tests; on device it is `ClusterStatistics.assignments`.

Real on-device input is *richer* (per-frame 3×3 covariances, raw OKLab tiles), but
the learnable palette path needs only the synthesizable palette+weights → categories.

## Output — the whole GIF

`LookOutput`:
- `loPalette :: HaarPalette` — the global 256 = 128 σ-balanced pairs (by construction).
- `loIndices :: IndexTensor T H W K` — the global index mapping (the GIF pixels).
- `loGlobalComplete :: Maybe GlobalSurjective` — the completeness witness.

**L7 replaced (was per-frame completeness).** The contract is now **global
surjectivity** (`⋃ₜ usedₜ = 256`); a single frame uses a *subset*. This is the
deliberate opposite of Stage-A's `CompleteVoxelVolume` (which stays for the local
per-frame palettes). A `Nothing` witness forces a documented fallback, exactly like
the Hybrid pipeline's witnesses.

## The key finding: synthetic data is palette-level

`synth` produces **palette-level** data only (`CyclicStack`: T frames × K
palette+weights). There is **no per-pixel synthesis**. Consequences:

1. **Palette path (L1–L6) trains on existing synthetic data.** The learnable
   E/R/D map the synthesizable category code → the Haar palette. Fully exercisable
   on the Mac mini today.
2. **Index path (L7–L8) is deterministic** — a nearest-global remap of the
   Stage-A local indices — so it needs no training; it is tested in Haskell with a
   synthetic `IndexTensor`.
3. **L9 dither / moving p-field, *if learned*, needs per-pixel data.** Training or
   evaluating it end-to-end requires a **pixel-volume extension to `synth`**
   (weights → spatial field + STBN3D). Flagged as a Phase-C / Rust dependency; not
   built in this Haskell pass. The *shape* (`T×H×W`) is identical whether L9 is
   learned or deterministic, so the dimensional contract types both.

## Mirrors

- `SixFour.Spec.LookNet` — the table, the typed I/O, the deterministic reference
  layers, the learnable shape contracts (`encoderIO/coreIO/decoderIO`), `runLookNet`,
  `baselinePalette`.
- `SixFour.Spec.Indices.GlobalSurjective` — the global completeness brand.
- `Properties.LookNet` — chain-composition, the 88/768 dimensional facts, and the
  end-to-end worked example (global-surjective yet per-frame-incomplete).

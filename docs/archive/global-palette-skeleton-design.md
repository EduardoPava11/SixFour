> **Status/built-state:** see [docs/STATUS.md](../STATUS.md) (canonical, gated by `scripts/verify-doc-claims.sh`). This document is design rationale, not a status ledger.

# SixFour: Per-Frame → Global Palette Collapse

**Audience:** the engineer building the deterministic NN-emulator collapse and its Review UI.
**Status:** implementable skeleton. The trained look-NN drops in later behind one Swift protocol;
this ships the deterministic conformer that computes the real coverage-maximin floor.

Two corrections are baked in throughout and are non-negotiable:

1. **The shipped emulator is the diversity / coverage MAXIMIN baseline, not "the Wasserstein-2
   barycenter."** `Spec/Collapse.hs` calls `farthestPointCollapse` a *"diversity-preserving
   classical baseline"* that *"RETAINS the most gamut coverage."* `Spec/Bures.hs` Thm 9 defines the
   free-support W2 barycenter as **population-weighted k-means** — a different object that the
   *trained NN* targets. Do not label the maximin output "the barycenter," and do not claim
   `s·tanh(residual)=0 ⇒ exact barycenter`. The honesty of the NN slot is a **type-contract** claim
   (`[[SIMD3<Float>]] → CollapsedPalette`), not a numeric-equivalence claim.

2. **The per-frame `CompleteVoxelVolume` / `SignificantVoxelVolume` brands are incompatible with one
   global palette** and must be **restated as whole-GIF brands in the spec + codegen BEFORE any
   renderer is wired.** This is a correctness blocker, not an open question (see §1, Phase 1).

---

## 0. Branch-parameterized input AND output (DECISION, 2026-05-30)

The branching the user selects in the UI (`16² / 4⁴ / 2⁸`) is **the NN's structural
genome** — it parameterizes the per-frame *input* representation **and** the global
*output* representation, end to end. This is not a view toggle; it is the model's
input/output shape. The three options are exactly three genomes the spec already defines:

| Branching | Spec genome (output type) | DOF | Inductive bias | Forward transform (256 leaves → genome) |
|---|---|---|---|---|
| **16²** | `FlatPalette` (direct 256 OKLab) | 768 | none (raw) | identity |
| **4⁴** | `Spec.Quad4.Quad4Palette` | **513** | opponent-quadrant (Hering a/b) | **`quad4Analyze` — TO ADD** (Quad4 has `reconstruct`/`toVector` but no forward `analyze`) |
| **2⁸** | `Spec.PairTree.HaarPalette` | 768 (σ-variant 384) | binary mirror-pairs | `PairTree.analyze` (exists) |

Consequences that ripple through the design below:

- **The collapse protocol takes a `branching` parameter** and returns a genome of the
  matching type. `CollapsedPalette` becomes a sum over the three genomes (a
  `BranchedPalette`), all sharing the 256 reconstructed sRGB leaves (the GIF GCT is
  always the 256 flat leaves — GIF cannot encode a tree; the genome is the *generative*
  / NN representation, the GCT is its `reconstruct`).
- **The deterministic emulator's maximin core is structure-free** (it picks 256 leaves),
  then **analyzes** those leaves into the selected genome (identity / `quad4Analyze` /
  `PairTree.analyze`), and the GCT is `genome.leaves` (= `reconstruct`). Crucially:
  **16² and 2⁸ are lossless 768-DOF genomes, so their colours equal the maximin leaves;
  4⁴ is a 513-DOF subspace, so `quad4Analyze` is a lossy PROJECTION and the rendered
  colours SHIFT toward the opponent-quadrant subspace** — branching already changes the
  output palette in the emulator, before any NN (the inductive bias is visible). The
  trained NN makes all three branch-dependent; the type contract holds across the swap,
  the numeric values do not (and need not).
- **The per-frame input is structured at the same `branching`** (each of the 64 palettes
  analyzed into the genome), so the pooled token set the NN ingests has the user's shape.
  The emulator pools leaves regardless; the structuring is the NN-faithful representation
  + the visualization.
- **DOF differs by branching** (768 / 513 / 768; σ-PairTree 384). This is a real
  parameter-budget + inductive-bias choice the user is now making at runtime.

**New spec work this adds to Phase 0/1** (folded into the build order):
- `quad4Analyze :: [OKLab] -> Quad4Palette` in `Spec.Quad4` (the forward 4-ary transform:
  per 2×2 quad, parent = mean, `(δ₁, δ₂)` = the 2-D Haar of the four children) + its
  round-trip law `reconstruct ∘ quad4Analyze = id`.
- A `FlatPalette` genome (trivial: the 256 leaves) for the `16²` case, for a uniform
  `BranchedPalette` interface.
- A unifying `BranchedPalette` (Swift + a spec mirror) = `flat | quad4 | haar`, with
  `branching`, the 256 sRGB leaves, and the genome. The collapse, the GIF re-index, and
  the Review view all key off it.

The rest of this document describes the `2⁸`/Haar path concretely; `4⁴`/Quad4 and
`16²`/flat follow the same shape via their genome's `analyze`/`reconstruct`.

---

## 1. The NN contract

**Input.** A capture = 64 per-frame palettes. The live carrier is
`PaletteGenerator.Output.perFramePalettes : [[SIMD3<Float>]]` (T×K = 64×256 OKLab centroids) on the
GPU path, and `DeterministicRenderer` `centroidsPerFrame : [[Int32]]` (Q16) on the default path.
Each slot optionally carries a population (`SixFourSignificantCell.count`, from
`PaletteGenerator.Output.perFrameCells : [[SixFourSignificantCell]]` — **non-optional**).
Mathematically this is a permutation-invariant **set** of 64 measures; the NN-facing view is the
pooled GMM token set (point-mass, Σ=0 from palette entries; `Spec/GMM.hs`, `gmmTokenDim=10`, up to
T·K=16384 tokens).

**Output.** ONE global 256-colour palette for the whole 64³ GIF. Native math form = a `HaarPalette`
(`Spec/PairTree.hs`): a root OKLab + 8 levels of offsets, `2^i` offsets at level `i`,
`degreesOfFreedom = 3·256 = 768`. The GIF-facing form = a single `[SIMD3<UInt8>]` of 256 sRGB
entries (one Global Color Table) + 64 re-indexed index maps.

**Pooling.** Permutation-invariant sum/union. Classical face (what the emulator runs):
`Spec.Collapse.pooledCandidates` = `concat` of all 64 frames' OKLab entries (order-invariant
multiset). NN face: `Spec.GMM.poolGMM = normalizeGMM . concat`, then
`Spec.LookNetE.encoderReference` = sum of `placeToken` over the set.

**Math target.** The NN amortizes the **population-weighted W2 barycenter** (`Spec/Bures.hs` Thm 9;
Agueh–Carlier 2011). The deterministic emulator computes the **coverage maximin set**
(`Spec/Collapse.hs farthestPointCollapse`), the gamut-coverage floor — *related to but distinct
from* the weighted barycenter. As `Σ→0` the Bures barycenter degenerates to **weighted** Euclidean
k-means (still weighted), **not** to unweighted maximin; do not conflate the two reductions.

**Equivariances the emulator must hold structurally** (`Spec/PairTree.hs`, `Spec/LookNetCompose.hs`):
- frame/token permutation-invariance (sum/union pooling),
- σ-reflect equivariance σ(L,a,b)=(L,−a,−b) (exact Euclidean isometry; `lawSigmaInvolution`,
  `lawSigmaEuclideanIsometry`),
- gauge / palette-order invariance and idempotence (`Properties.Collapse`),
- gamut closure (maximin picks actual input colours; never invents colour),
- Haar round-trip `analyze∘reconstruct = id` on the 768-DOF tree (`lawReconstructAnalyzeRoundTrip`).

**What the emulator omits (no-stub-honest, no deterministic ground truth):** the learned residual
(`s·tanh(residual)=0` ⇒ exact floor); the L4 core's Mixture-of-Recursions / PonderNet halting
(affects *how* the net reaches a target, never the I/O contract); the Bures covariance refinement
(optional; Σ=0 from palette/GIF tokens makes it degenerate); the L9 learned dither (use the existing
STBN3D path).

---

## 2. Architecture — the collapse protocol and the NN slot

```
64 per-frame palettes ([[SIMD3<Float>]]  or  [[Int32]] Q16)
        │
        ▼
  PaletteCollapse.collapse(...)   ◄── the NN slot (one protocol)
        │                              today: FarthestPointCollapse (deterministic maximin)
        │                              later: LookNetCollapse (weight-blob forward pass)
        ▼
  CollapsedPalette { oklab[256], srgb[256], haar:HaarPalette(768) }
        │
        ▼
  re-index all 64 frames against collapsed.oklab  (CentroidSet + Probe.nearest, lowest-index ties)
        │
        ▼
  GlobalCompleteVolume + GlobalSignificantVolume  (NEW whole-GIF brands, §1 / Phase 1)
        │
        ▼
  GIFEncoder.encode(globalVolume:globalPalette:...)  (NEW single-GCT mode)
```

Both renderers hold `let collapser: PaletteCollapse = FarthestPointCollapse()`. Swapping in
`LookNetCollapse` is a one-line default change with zero downstream edits.

**Numeric-parity decision (resolves the major golden blocker).** The Haskell `farthestPointCollapse`
computes in `Double`; `okLabDistanceSquared` in Swift returns `Float`. A greedy maximin argmax over
≤16384 near-tied points **will diverge** between Double and Float, and an index sequence has no
tolerance band. Therefore:

> **The shipped collapse + its golden run in the Q16 integer domain** on both the default and
> (eventually) GPU paths. Port `farthestPointCollapse` to integer OKLab-Q16 (matching
> `DeterministicRenderer`'s existing Q16 substrate and `SixFourNative`), and emit the golden from an
> integer reference. The index sequence is then genuinely reproducible bit-for-bit. The float
> `[SIMD3<Float>]` overload exists only as a non-golden-gated convenience for the GPU path during
> rollout; it is **not** the deterministic artifact.

This makes the deterministic path (the default, `useDeterministicCore=true`) the byte-exact home
from day one and avoids asserting an unattainable Double↔Float index parity.

---

## 3. File layout

| Path | Kind | Responsibility |
|---|---|---|
| `SixFour/Palette/PaletteCollapse.swift` | swift-new | `protocol PaletteCollapse` (the NN slot) + `struct FarthestPointCollapse` (deterministic Q16 maximin) + `struct CollapsedPalette`. |
| `SixFour/Palette/PaletteHaarTree.swift` | swift-new | Swift port of `Spec.PairTree`: `HaarPalette`, `analyze([OKLab])→HaarPalette`, `reconstruct`, `degreesOfFreedom=768`. Gated against the PairTree golden (round-trip). |
| `spec/src/SixFour/Codegen/Collapse.hs` | haskell-new | Emit `collapse_golden.json` from the **integer** reference (pooled cloud, first-seed index, full chosen-index sequence, K leaves) + the `analyze` HaarPalette. Wire into `spec/app/Spec.hs`. |
| `spec/src/SixFour/Spec/Collapse.hs` | haskell-modify | Add an integer-Q16 reference `farthestPointCollapseQ16` (or parameterise the metric) so the golden matches the Swift Q16 port exactly. Keep the Double `farthestPointCollapse` as the math reference. |
| `spec/src/SixFour/Spec/GlobalVolume.hs` (+ `Properties.GlobalVolume`) | haskell-new | Whole-GIF surjectivity + significance contract (§1). Source of truth for the regenerated Swift brands. |
| `spec/src/SixFour/Codegen/Swift.hs` | haskell-modify | Add `emitGlobalVolumeContract` emitting `GlobalVolumeContract.swift`; register in `spec/app/Spec.hs`. |
| `SixFour/Generated/GlobalVolumeContract.swift` | generated | `GlobalCompleteVolume` + `GlobalSignificantVolume` brands (do not hand-edit). |
| `SixFour/Encoder/GIFEncoder.swift` | swift-modify | ADD `encode(globalVolume:globalPalette:to:comment:)` — GCT mode. Per-frame LCT `encode(volume:perFramePalettes:...)` unchanged. |
| `SixFour/Encoder/GIFRenderer.swift` | swift-modify | Insert collapse + re-index + GCT encode behind a `globalPalette` setting (GPU path). |
| `SixFour/Encoder/DeterministicRenderer.swift` | swift-modify | Insert Q16 collapse + re-index + GCT encode after Stage 4 (default path); Zig GCT kernel is the later byte-exact home. |
| `SixFour/Settings/AppSettings.swift` | swift-modify | Add `paletteScope: PaletteScope` and `globalPalette: Bool`. |
| `SixFour/UI/Components/ScopeSelector.swift` | swift-new | Glass chrome twin of `BranchingSelector`, bound to `PaletteScope`. |
| `SixFour/UI/Components/PaletteTreeView.swift` | swift-modify | Add `enum PaletteScope`. `PaletteTreeView` itself **unchanged** (a 1-element `palettes` array freezes its animation via the existing `palettes.count > 1` guard). |
| `SixFour/UI/Screens/Review/GIFReviewView.swift` | swift-modify | Scope-driven `paletteStructure(_:)`; whole-GIF status line under `.global`. |
| `SixFour/UI/Screens/Capture/CaptureViewModel.swift` | swift-modify | Add `globalPaletteForDisplay: [SIMD3<UInt8>]` to `CaptureOutput`; fill it from the collapser on both paths. |
| `spec/docs/COLLAPSE-EMULATOR.md` | doc | Records: protocol = NN I/O boundary; maximin = coverage floor (NOT the barycenter); Q16-golden gate; whole-GIF brand restatement; 768-vs-384 DOF; why Bures/PonderNet are omitted. |

---

## 4. Core types & signatures

### 4a. The collapse protocol + deterministic impl (`PaletteCollapse.swift`)

```swift
import simd

/// The look-NN I/O slot. Input = the 64×256 per-frame OKLab palettes (flowing as
/// PaletteGenerator.Output.perFramePalettes) + the per-frame significance cells
/// (NON-optional; carries .count populations for a future weighted barycenter).
/// Output = ONE global palette. The trained LookNetCollapse conforms to this exact signature.
protocol PaletteCollapse: Sendable {
    /// `branching` is the user's selected genome (§0): it shapes the per-frame input
    /// tokenization AND the output genome. The trained LookNetCollapse conforms to the
    /// same signature.
    func collapse(perFramePalettes: [[SIMD3<Float>]],
                  perFrameCells: [[SixFourSignificantCell]],
                  branching: PaletteBranching) -> CollapsedPalette
}

/// The branch-parameterized collapse output. The 256 sRGB leaves are the GIF Global
/// Color Table (always flat — GIF cannot encode a tree); `genome` is the structural
/// representation the user selected, which is what the NN emits/ingests.
struct CollapsedPalette: Sendable {
    let branching: PaletteBranching
    let oklab: [OKLab]            // 256 reconstructed leaves (re-indexing quantizes against these)
    let srgb:  [SIMD3<UInt8>]     // 256 sRGB8 GCT = oklab.map(ColorScience.okLabToSRGB8)
    let genome: BranchedPalette   // .flat([OKLab]) | .quad4(Quad4Palette) | .haar(HaarPalette)
}

/// The three structural genomes (§0). DOF: flat 768 / quad4 513 / haar 768.
enum BranchedPalette: Sendable {
    case flat([OKLab])            // 16²: the 256 leaves directly
    case quad4(Quad4Palette)      // 4⁴: 513-DOF opponent-quadrant (Spec.Quad4)
    case haar(HaarPalette)        // 2⁸: 768-DOF binary Haar (Spec.PairTree)

    /// Forward: 256 leaves → genome for `branching` (identity / quad4Analyze / analyze).
    static func analyze(_ leaves: [OKLab], _ b: PaletteBranching) -> BranchedPalette
    /// Inverse: genome → 256 leaves (the GCT). `reconstruct ∘ analyze = id` per genome.
    var leaves: [OKLab] { /* flat: self; quad4: Quad4.reconstruct; haar: PaletteHaarTree.reconstruct */ }
}

/// Deterministic conformer = the coverage/diversity MAXIMIN floor (NOT the W2 barycenter;
/// weights ignored, matching Spec.Collapse). Numeric work in Q16 integer OKLab so it
/// reproduces the integer golden bit-for-bit.
struct FarthestPointCollapse: PaletteCollapse {
    func collapse(perFramePalettes: [[SIMD3<Float>]],
                  perFrameCells: [[SixFourSignificantCell]]) -> CollapsedPalette {
        // 1. POOL: union of all 64×256 OKLab entries → ≤16384 candidates, quantized to Q16.
        // 2. MAXIMIN (Q16, K=256):
        //    m   = cloud mean in Q16
        //    first = argmax_i d2Q16(cand_i, m)     // ties: lowest index
        //    minD[i] = d2Q16(cand_first, i)
        //    repeat K-1×: pick = argmax_i minD[i]  // ties: lowest index
        //                 minD[i] = min(minD[i], d2Q16(cand_pick, i))
        //    → 256 chosen Q16 colours (actual input colours ⇒ gamut-closed).
        // 3. dequantize → [OKLab]; srgb via okLabToSRGB8; haar via analyze.
    }
}
```

Corrected facts vs the reviewed designs:
- `CollapsedPalette.oklab` is `[OKLab]` (the struct in `ColorScience.swift`), **not** `[SIMD3<Float>]`.
  `okLabToSRGB8`/`okLabDistanceSquared`/`analyze` all take `OKLab`; wrap at the seam (`OKLab($0)`),
  exactly as `GIFRenderer.swift:160` does.
- `perFrameCells` is **non-optional** `[[SixFourSignificantCell]]`.
- **Tie-break:** maximin first-seed and `argmax(minD)` use lowest-index-wins (Haskell `V.maxIndex`;
  Swift `KMeansPalettePipeline.farthestPointSeedCentroids` keeps earliest via strict `>`). The
  *re-index* step (`Probe.nearest`) is the strict-`<` lowest-index nearest rule. Pin both in the golden.
- `FarthestPointCollapse` cannot reuse `KMeansPalettePipeline.farthestPointSeedCentroids` bit-for-bit
  (that lives in `Metal/`, takes a frame's pixels, returns `[SIMD4<Float>]`). Only the loop shape
  ports — this is a fresh pure-Swift Q16 routine.

### 4b. Haar tree (`PaletteHaarTree.swift`)

```swift
struct HaarPalette: Sendable, Equatable {
    let root: OKLab
    let levels: [[OKLab]]   // level i has 2^i offsets, 8 levels → 768 DOF
}
enum PaletteHaarTree {
    static func analyze(_ leaves: [OKLab]) -> HaarPalette        // (x+y)/2, (x-y)/2 reduce
    static func reconstruct(_ hp: HaarPalette) -> [OKLab]        // node → [n+d, n-d]
    static let degreesOfFreedom = 768
}
```
Gated against a PairTree golden (`analyze∘reconstruct = id`).

### 4c. The whole-GIF brands (`Spec/GlobalVolume.hs` → `GlobalVolumeContract.swift`)

Replaces the per-frame brands at the global encode gate. Restated, not weakened:

```
GlobalCompleteVolume(checkingFrames: [[UInt8]]):
   - exactly T frames, each pixelsPerFrame long
   - surjectivity over the UNION of all 64 frames onto the 256 GCT:
     (⋃ₜ seenₜ).count == K        -- NOT per-frame; a flat frame need not touch all 256
GlobalSignificantVolume(complete, pooledCells):
   - per global slot j: Σ over frames count_j ≥ minPopulation   -- pooled mass
   - total mass == T · pixelsPerFrame
```
The "no empty slot ships" guarantee survives: every one of the 256 global colours is exercised
somewhere in the GIF and backed by ≥ minPopulation pooled pixels. **Do not call
`CompleteVoxelVolume(checkingFrames:)` on global indices — it requires per-frame `seen.count == K`
(StageContract.swift:62-64) and returns nil for typical frames, aborting the render at the fail-loud
guard.**

### 4d. The UI scope toggle

```swift
enum PaletteScope: String, CaseIterable, Codable, Sendable {
    case perFrame, global
    var label: String { self == .perFrame ? "per-frame" : "global" }
}
// AppSettings: var paletteScope (Key "sixfour.paletteScope.v1", default .perFrame)
//              var globalPalette (Key "sixfour.globalPalette.v1", default false)
struct ScopeSelector: View { @Binding var selection: PaletteScope }  // glass twin of BranchingSelector
```

### 4e. The optional global-table GIF export (`GIFEncoder.swift`)

```swift
func encode(globalVolume: GlobalCompleteVolume,
            globalPalette: [SIMD3<UInt8>],   // 256
            to url: URL, comment: String? = nil) throws
```
All block builders already exist and are reused unchanged:
- LSD packed byte `0x70 → 0xF7` (bit7 GCT=1, bits0-2 size=7). *(LSD packed at GIFEncoder.swift:82.)*
- Write ONE `colorTable(globalPalette)` after the LSD (the 768-byte builder at line 120 is shared).
- Per frame use `imageDescriptor(width:height:packed: 0x07)` (LCT bit OFF) and **skip** the per-frame
  `localColorTable`.
- NETSCAPE loop, comment extension, graphicsControl disposal=1, `lzwEncode(minCodeSize:8)` carry over.
  Frames must be pre-re-indexed against the global palette by the caller.

---

## 5. Data flow

```
capture (64 OKLabTile)
  │  GPU path: GIFRenderer.render → KMeansExtractor.extractBatch → PaletteGenerator.generate
  │     → Output.perFramePalettes [[SIMD3<Float>]] 64×256, perFrameCells
  │  Default path: DeterministicRenderer.render → Stage 1 quantize → centroidsPerFrame [[Int32]] Q16
  ▼
COLLAPSE (only when settings.globalPalette == true)
  collapser.collapse(perFramePalettes:perFrameCells:) → CollapsedPalette
  ▼
RE-INDEX 64 frames against collapsed.oklab
  CentroidSet(collapsed.oklab.map(\.simd)) + Probe.nearest  (strict-<, lowest-index)
  → 64 global index maps [[UInt8]]
  ▼
GATE: GlobalCompleteVolume(checkingFrames:) + GlobalSignificantVolume(pooledCells:)
  ▼
ENCODE: GIFEncoder.encode(globalVolume:globalPalette: collapsed.srgb:...)
  ▼
CaptureOutput.globalPaletteForDisplay = collapsed.srgb   (always computed once per capture)
  ▼
REVIEW (GIFReviewView.paletteStructure, scope-driven):
  .perFrame → PaletteTreeView(palettes: o.palettesForDisplay, branching:)            // 64-tree animation
  .global   → PaletteTreeView(palettes: [o.globalPaletteForDisplay], branching:)     // 1-element ⇒ static
```

**UI reuse, accurately.** `PaletteTreeView` is reused **unchanged**: under `.global` pass a 1-element
`palettes` array, and its `palettes.count > 1` guard (line 32) freezes to a single static treemap.
`SplitTree` unchanged. Under `.global`, `perFrameStatus` switches to a whole-GIF line — its
`256/256 ✓` per-frame assertion (GIFReviewView.swift:92) does not apply to a single global palette
and must be replaced with the whole-GIF surjectivity readout.

**`globalPaletteForDisplay` converter consistency:** pick ONE converter. Since collapse runs in Q16
on the default path, route the global palette through the **same Zig
`SixFourNative.paletteToSRGB8(centroidsQ16:k:)`** the per-frame palettes use (DeterministicRenderer.swift:159),
so `globalPaletteForDisplay` is byte-identical to the encoder's GCT. Do **not** mix Zig
`paletteToSRGB8` with Swift `ColorScience.okLabToSRGB8` for the same field.

---

## 6. Build order

**Phase 0 — Haskell collapse + genomes + golden (gate before any Swift).**
Files: `Spec/Collapse.hs` (`farthestPointCollapseQ16` integer reference), `Spec/Quad4.hs`
(**add `quad4Analyze :: [OKLab] -> Quad4Palette`** + `lawQuad4AnalyzeRoundTrip`), a `FlatPalette`
genome + a `BranchedPalette` (`flat | quad4 | haar`) with `analyze`/`leaves` over all three (+ the
per-genome round-trip laws), `Codegen/Collapse.hs` (emit `collapse_golden.json` with the chosen-index
sequence **and** the genome coefficients for each branching), wire into `spec/app/Spec.hs`,
`Properties.Collapse` round-trip/idempotence/gauge laws if absent.
DoD: `cabal build && cabal test && cabal run spec-codegen` green; integer-exact index sequence;
`reconstruct ∘ analyze = id` for all three genomes (flat/quad4/haar); golden carries all three.

**Phase 1 — Whole-GIF brands (the blocker fix; before any renderer).**
Files: `Spec/GlobalVolume.hs` + `Properties.GlobalVolume`, `Codegen/Swift.hs emitGlobalVolumeContract`,
regenerate `Generated/GlobalVolumeContract.swift`.
DoD: union-surjectivity + pooled-significance laws restate (not weaken) the guarantee; `cabal test` green.

**Phase 2 — Swift collapse + Haar, golden-gated.**
Files: `PaletteHaarTree.swift`, `PaletteCollapse.swift` (`FarthestPointCollapse` Q16).
DoD: unit test loads `collapse_golden.json`, reproduces cloud mean, first-seed, full index sequence,
leaves bit-for-bit; `analyze∘reconstruct` round-trip passes.

**Phase 3 — GCT encoder mode.**
Files: `GIFEncoder.swift` (`encode(globalVolume:globalPalette:...)`).
DoD: GCT GIF decodes in Preview/`exiftool`; per-frame LCT mode untouched; golden byte check on a fixture.

**Phase 4 — Renderer seams (default path first).**
Files: `DeterministicRenderer.swift` (collapse Q16 after Stage 4, re-index, GCT encode behind
`globalPalette` setting), then `GIFRenderer.swift`, `AppSettings.swift`, `CaptureViewModel.swift`.
DoD: `globalPalette` on → one GCT GIF passing the whole-GIF brands; off → byte-identical to today;
both fill `globalPaletteForDisplay` via the same Zig converter.

**Phase 5 — Review UI.**
Files: `PaletteTreeView.swift` (`PaletteScope`), `AppSettings.swift` (`paletteScope`),
`GIFReviewView.swift` (scope-driven structure + whole-GIF status), `ScopeSelector.swift`.
DoD: scope toggle flips per-frame ↔ global tree (global static); whole-GIF surjectivity readout;
glass stays chrome-only.

---

## 7. Open questions (residual decisions)

1. **Output DOF (768 vs 384).** Emulator emits a free 768-DOF `HaarPalette` matching
   `Spec.PairTree`/CLAUDE.md. The trained decoder commits to the 384-DOF σ-symmetric `SigmaPairTree`
   (128 mirror pairs; `sigmaPairDegreesOfFreedom = 384`), but NOTES.md flags that pivot un-wired.
   Ship 768 now; σ-projecting an arbitrary maximin palette to 384 is lossy, so swapping in
   `LookNetCollapse` *may shift rendered leaves* — the slot is a *type* drop-in, not yet a *numeric*
   one. Decide whether to pre-emptively σ-pair-symmetrize the emulator output.
2. **Weights.** `farthestPointCollapse` ignores `perFrameCells.count` (pure coverage; per
   `sixfour-lnn-research-lloydmax-ceiling`, coverage not MSE is the metric). The weighted W2
   barycenter would use the counts. Confirm the shipped collapse stays unweighted maximin vs. adds a
   weighted-k-means refinement.
3. **Swift vs Zig for the deterministic GCT encode.** Phase 4 routes the default path through Swift
   `GIFEncoder` GCT mode (Zig `s4_gif_*` are LCT-only). For full cross-device byte-exactness the
   long-term home is a Zig GCT kernel + Q16 collapse kernel. Decide when to integerize.
4. **Bures path.** Optional, currently degenerate (Σ=0 from point-mass tokens). Only load-bearing if
   live `ClusterStatistics` Σ≠0 is fed in. Decide whether the emulator ever enables covariance-aware
   refinement or leaves it to the NN.
5. **`globalPaletteForDisplay` array shape.** Single-element (recommended) vs 64-repeated.
   `PaletteTreeView`'s `count > 1` guard already gives the static behaviour.

# SixFour — Browsable, Updatable Spec Workflow (Haskell toolchain; NN at the core)

> Status: workflow (2026-06-08). Turns the 83-module Haskell spec into a *browsable* and *updatable*
> reference using the Haskell toolchain, organised so the **NN design is the centre**. Landing module:
> `SixFour.Spec.Map`. SixFour owns all code (spec = Tier-0, not shipped).

---

## 0. Why
The spec has grown to **83 modules** (72 `Spec.*` + 11 `Codegen.*`), each already carrying a rich
doc-comment. The Haskell-native move is to *use those comments*: **Haddock** renders them as a browsable,
hyperlinked HTML reference; **Hoogle** makes it searchable by name and type; **ghcid** gives live feedback
while you edit; and the existing **`cabal test` + golden vectors** keep it honest as the app changes. No new
language, no doc rot — the doc IS the source.

---

## 1. The categorisation (sections)
Encoded in `SixFour.Spec.Map` (the Haddock landing page) and mirrored here. Keep both in sync on add.

| # | Category | Role | Key modules |
|---|---|---|---|
| ★ | **NN DESIGN — the core** | learns the global palette as a gated residual | `Net`, `LookNet`, `LookNetE/R/D`, `LookNetCompose`, `LookNetEval`, `LookCore`, `Layer`, `Loss`, `PaletteOracle`, `PaletteSearch` |
| 1 | Numeric & colour core | OKLab, fixed-point, tensors | `Color`, `ColorFixed`, `Shape`, `LinAlg`, `Tensor`, `Gauge` |
| 2 | Per-frame palette (NN **input**) | StageA extraction + stats | `StageA`, `Palette`, `QuantFixed`, `GMM`, `Bures`, `Diversity`, `Coverage`, `Significance*` |
| 3 | Collapse → global palette | sliced-W₂ barycenter | `Collapse`, `GlobalVolume`, `Cyclic` |
| 4 | Genome / radix (NN **output** space) | 16²/4⁴/2⁸ trees | `SplitTree`, `PairTree*`, `SigmaPair*`, `SigmaDecomp`, `Quad4*`, `Bottleneck16`, `AddressPicker` |
| 5 | **Authoring story (Acts I–IV)** | the user pipeline the NN lives in | `StageA`(I), `QuartetDelta`(II), `HaarRibbon`(III), `Export`(IV) |
| 6 | Dither & index encoding | residual-shaping sampler | `Dither`, `SpatialDither`, `STBN3D`, `Indices`, `FrontProjection`, `VoxelFit` |
| 7 | UI: cell-field / display / grid | the I/O appliance | `Display`, `PlaybackClock`, `Lattice`, `Cell*`, `Grid*`, `MovableLayout`, `Ownership`, … |
| 8 | Cross-cutting | shared law combinators | `Laws` |
| 9 | Codegen → app | Swift/Zig/Python emitters | `Codegen.Swift/.Shapes/.Golden/.Genome*/.MLX/.CoreML/…` |

**The spine through the centre:** cat. 2 (input) → cat. 3 (collapse) → cat. ★ (NN learns the barycenter) →
cat. 4 (emits a genome) → cat. 9 (codegen to the app), all *within* cat. 5 (the authoring story). The
verdict pins the NN's role: **no JEPA core; a gated, gap-only residual head on a deterministic base**
(`docs/SIXFOUR-256-SUPERRES-WORKFLOW.md`).

---

## 2. The toolchain (what's installed, what it gives)
| Tool | Gives | Command |
|---|---|---|
| **Haddock** | browsable HTML, hyperlinked to source, in-page fuzzy search (quickjump) | `cabal haddock sixfour-spec --haddock-hyperlink-source --haddock-quickjump` |
| **Hoogle** | search by name *and type signature* | `cabal haddock … --haddock-hoogle` → `hoogle generate --local=<dir> --database=spec.hoo` → `hoogle server` |
| **ghcid** | live re-typecheck on save (sub-second loop while editing) | `ghcid -c 'cabal repl sixfour-spec'` |
| **fourmolu** | consistent formatting | `fourmolu -i src/SixFour/Spec/*.hs` |

One script drives the browsable build: **`spec/scripts/spec-docs.sh`** (`--serve` to also start Hoogle on
:8080). Start browsing at module **`SixFour.Spec.Map`**.

> Not installed: `graphmod`/`graphviz` (module-import graph). Optional add-on; Haddock's module tree +
> Hoogle already cover navigation. If wanted: `cabal install graphmod` + `brew install graphviz`, then
> `graphmod -p $(find src -name '*.hs') | dot -Tsvg > spec/spec-graph.svg`.

---

## 3. The iterate loop (updatable as the app changes)
Every spec change runs the same gate; the browsable docs and the app contracts regenerate from it, so
nothing drifts:

```
edit Spec.*        →  ghcid (live typecheck, sub-second)
                   →  cabal test           # laws + golden vectors (the correctness gate)
                   →  cabal run spec-codegen # regen Swift/Zig/Python contracts (app stays in sync)
                   →  spec/scripts/spec-docs.sh   # regen Haddock + Hoogle (browsable spec stays in sync)
```

- **Add a module:** wire it into `spec.cabal` `exposed-modules`, add a `{- | … -}` header, and add ONE line
  to `SixFour.Spec.Map` under its category. The Haddock landing updates on next `spec-docs.sh`.
- **Change a contract:** edit the `Spec`, let `cabal test` catch broken laws, `spec-codegen` re-emits the
  Swift/Zig/Python — the app *cannot* drift (golden-pinned, `cabal test` is the gate).
- **Section markers:** use Haddock `== Heading` blocks inside long modules so they're sub-navigable.

---

## 4. Iterating the NN core (the centre)
The NN is the part most in flux, so it gets a focused loop. North star (do not relitigate): **statistical
base, no JEPA core, the look-NN is a gated gap-only residual** that snaps to the nearest 256-leaf index at
write time (`docs/SIXFOUR-256-SUPERRES-WORKFLOW.md`, `docs/SIXFOUR-PALETTE-STORY-WORKFLOW.md` §5).

1. **Shape first** — `Net.slotLookDims` pins io dims / depth → `NetContract`. Change shapes here only.
2. **Forward path** — `LookNetE` (encoder, σ-equivariant) → `LookNetR` (MoR core) → `LookNetD` (384-DOF
   σ-pair decoder); the composition theorem is `LookNetCompose`. Iterate with `LookNetEval` + ghcid.
3. **What it consumes / emits** — input = per-frame palettes (cat. 2); output space = the genome (cat. 4);
   it learns the cat. 3 barycenter. Wire to the story: the residual fills Act-II/III gaps the deterministic
   base leaves (disocclusion, HF/MF chroma).
4. **Value + search** — `PaletteOracle` (deterministic beauty/entropy) + `PaletteSearch` (MCTS).
5. **Gate every change** — `cabal test` (σ-equivariance metamorphic law + goldens) before regen.
6. **Trainer/deploy** — MLX on M1 (Tier-1), verified vs goldens, hand-written Swift+Metal on device
   (Tier-2, zero deps). `Codegen.MLX` is the primary emitter; `Codegen.CoreML` dormant.

---

## 5. Maintenance contract
- `SixFour.Spec.Map` is the **single index** — every new module gets one line there, under its category.
- This doc's category table and `Map` must agree (they are the same taxonomy in two renders).
- `spec-docs.sh` is the only way to regen the browsable spec; never hand-edit generated HTML.
- The browsable spec is a *view* of the source; correctness still lives in `cabal test` + golden vectors.

---

## 6. Next
- Run `spec/scripts/spec-docs.sh` to publish the first browsable build; sanity-check `Map` renders as the
  landing page with all categories clickable.
- (Optional) add the `graphmod` import-graph as `spec/spec-graph.svg` for a visual map.
- Backfill any thin module headers (Haddock surfaces them as blanks) — the doc-comment IS the spec page.

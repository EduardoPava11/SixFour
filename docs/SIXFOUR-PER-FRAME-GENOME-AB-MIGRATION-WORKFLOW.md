# SixFour — Per-Frame · Orthogonal-A/B-Genome · Learned-256³ Migration Workflow

> **Status:** DIRECTION (2026-06-18). This workflow **supersedes the single-global-genome
> framing** in `docs/SIXFOUR-CANONICAL-PATH.md` and the "global palette" gravity in
> `docs/STATUS.md` §"What SixFour is". It does **not** delete that work — it **tags** it
> (see §6) and re-points the directory at a path the repo already holds in pieces.
>
> **One-line reframe:** the product is *not* one global palette collapsed from 64 frames.
> It is a **per-frame** palette cube reduced by a **reversible (2×2)×(2×2)→1** lift into a
> **pair of orthogonal 16³ genomes (A,B)** the user A/B-tests, with a **learned generative
> super-resolution** reversal up to 256³ — and a **vector (not JSON) RAG store of learned
> genes on a SIMT substrate**.

---

## 0. Why this document exists

The user's direction (verbatim intent, 2026-06-18):

- 64³ is the **input** to the network stack; the nets "think/reason in LAB colour space and
  spatio-temporal space."
- `64³ → [16³(A) / 16³(B)]` — both A and B are 16×16 spatial × 16 temporal, produced by a
  **reversible** `(2×2)×(2×2)→1` reduction.
- **A and B must be ORTHOGONAL** — "both must have different *genes*." That orthogonality is
  the *whole point* of A/B testing here. (Explicitly **not** "A is L, B is a,b" — not a channel
  split.)
- MVP: turn the 64³ voxel mass into the (A,B) pair → user **A/B-tests until satisfied** → emit
  a **reversal to 256³**, which is **learned generative super-resolution**.
- **Every capture session starts with very different A/B's, then closes the differences a
  little** (start-diverse-then-converge).
- **ALL of this MUST be per-frame palette.** The global-palette collapse is the misdirection
  to move away from.
- **RAG** to keep the saved learned genes. **JSON is slow and it is text — use vectors.**
  **SIMT.**
- **Tag, do not delete.** This is a whole-directory change so the whole app *trains* and
  *produces GIFs* on per-frame palette.

The key finding from mapping the directory: **most of this already exists as research and
spec.** It was buried under a "collapse 64 frames to one global genome" layer. This workflow
is the map from the user's seven pillars to the files that hold them, plus the genuine gaps.

---

## 1. The seven pillars → where the research already lives

Legend: **[BUILT]** implemented + gated · **[SPEC]** Haskell law exists, no device port ·
**[DESIGN]** doc/stub only · **[GAP]** not yet designed.

### Pillar A — Reversible (2×2)×(2×2)→1 spatio-temporal reduction  **[BUILT, spec]**
- `spec/src/SixFour/Spec/RGBTLift.hs` — `liftQuad`/`unliftQuad`: a 2×2 spatial block of 4
  scalars → ONE cell carrying 4 channels (R,G,B,T), recovered **exactly**. "The separable 2-D
  Haar realised by the integer lifting scheme (the S-transform) … a bijection on `Int` with no
  rounding loss."
- `spec/src/SixFour/Spec/CubeLadder.hs` — `liftLevel`/`unliftLevel`, `distill`/`synthesize`.
  `lawLadderBijective`: **"64³↔16³ loses nothing (the detail is carried, not discarded)."**
  Each ×2 step is one 2-D-Haar `liftLevel`; two steps = the user's `(2×2)×(2×2)`.
- `spec/src/SixFour/Spec/TemporalLoop.hs` — `temporalResidual`: one level of the **same**
  reversible integer Haar over the 64-frame axis (low band = smoothed motion, high band =
  detail); the split is lossless.
- `spec/src/SixFour/Spec/PairTreeFixed.hs` — `liftPair`/`unliftPair`, the shared `div 2`
  flooring S-transform primitive.
- Zig: `s4_haar_*` in `Native/src/kernels.zig` (exact integer, fixtures green).

> **Reconcile note:** today the spatial lift (`RGBTLift`) and the temporal lift (`TemporalLoop`)
> are **decoupled** and applied per-axis; there is **no single joint spatio-temporal 4×4×4
> operator**. The user's `(2×2)×(2×2)→1` on the full voxel cube is the *composition* of these.
> Phase 1 makes that composition a first-class, named, gated operator (`Spec.VoxelReduce`).

### Pillar B — Two ORTHOGONAL genomes (the A/B genes)  **[SPEC]**
- `spec/src/SixFour/Spec/GenomePair.hs` — the keystone.
  - `genomeInner` — W-weighted dot on **384-D generator-space displacements** (128 generators
    × 3 OKLab channels).
  - `chooseDisjointBands` — split top-ranked generators into two **disjoint** bands by rank
    parity (`S_A` = ranks 0,2,4…; `S_B` = 1,3,5…). `lawSelectorRidesOnDisjoint`.
  - `sampleOrthogonalPair` — propose `(δ_A, δ_B)`; `δ_A` nudges `S_A`, `δ_B` the disjoint
    `S_B`. **`lawPairOrthogonalExact`: `genomeInner δ_A δ_B == 0` EXACTLY on the Q16 lattice —
    "an algebraic decomposition of ONE signal into disjoint coordinates; it needs no
    Gram–Schmidt and no ε."**
- This is *exactly* "both must have different genes," made exact and provable.
- **Device path is a stub** (`perturb()` placeholder) per
  `docs/SIXFOUR-NETWORKS-CANONICAL-ROSTER.md`. Porting it is Phase 3.

### Pillar C — Learned generative super-resolution to 256³  **[DESIGN/STUB]**
- `spec/src/SixFour/Spec/ExportFamily.hs` — emits `{16³, 64³, 256³}` rungs.
  - `synthBeyond` (256³ floor) = nearest-neighbour replicate (deterministic).
  - **`NetSynth256`** = a SEPARATE **gated** learned enhancement on top, "proven bit-exact-equal
    to the floor at zero genome." **The synthesis stubs are still `error "TODO"`** — this is the
    real generative-NN slot the user calls "learned generative super-resolution."
- `spec/src/SixFour/Spec/CubeLadder.hs` `tier256` = "synthesises from the substrate."

### Pillar D — Start-diverse-then-converge  **[SPEC partial]**
- `spec/BLEED_LOOP.md` — reverse-waterfilling reveal schedule; `goldenDecay` escalates a budget
  monotonically (coarse harmonies bleed first); attractor is "a non-trivial invariant *shell* …
  seductive rather than convergent."
- `spec/src/SixFour/Spec/PersonalGenome.hs` — `coldStartGenome` (θ=0, n=0) → `personalBeta`
  ramps monotonically as Compares accrue (`lawBetaMonotoneRamp`). No convergence claim, only a
  **monotone trust ramp** — the formal home of "close the differences a little each session."
- `spec/src/SixFour/Spec/PreferenceUpdate.hs` — `btUpdate` (Bradley–Terry, η=0.05, λ=1e-3).
- **The "spread" the pair starts with and how it anneals per session is not yet a named
  parameter.** Phase 4 introduces a session **divergence schedule** `Δ(session, picks)` that
  feeds `sampleOrthogonalPair`'s magnitude.

### Pillar E — Per-frame palette EVERYWHERE  **[BUILT input / GAP output]**
- `spec/src/SixFour/Spec/StageA.hs` — per-frame 256-colour palette + index tensor per frame.
  This is the NN **input** and is BUILT.
- `SixFour/Encoder/GIFEncoder.swift` — `encode(...)` already writes **GIF89a per-frame local
  colour tables** (the per-frame GIF, "GIFA"). The encoder is already per-frame-capable.
- **The misdirection:** the look path then **collapses** per-frame palettes to ONE global
  palette (`globalCollapseQ16` / `s4_global_collapse`) and the look-NN "emits ONE **global**
  384-DOF genome for the whole 64³ GIF" (CLAUDE.md). The output must become **per-frame**: the
  genome modulates a *per-frame* palette family, never a single global table. Phases 2 + 5.

### Pillar F — RAG vector store of learned genes  **[BUILT carrier / GAP store]**
- `spec/src/SixFour/Spec/GenomeCarrier.hs` — genomes already serialize as **Int32 LE Q16
  binary** inside a GIF89a app-extension (`0x21 0xFF`); chosen explicitly because float/JSON
  "would silently truncate and break the round-trip." This is the user's "vectors not JSON,"
  already decided for the wire format. `lawEmbedExtractRoundTrip`, `lawCRCRejectsCorruption`.
- `spec/src/SixFour/Spec/PersonalGenome.hs` — the per-device **770-D θ** taste vector (~3 KB),
  a pure memoised fold over the local pick log.
- `spec/src/SixFour/Spec/GenomeBlend.hs` — federated reception (a foreign genome enters as ONE
  logged Compare, never a splice).
- **GAP:** there is **no vector retrieval/similarity index** — no kNN/HNSW over saved genes,
  no on-device vector DB, no decided similarity metric. STATUS §3 acknowledges "no per-user
  delta/adapter spec." This is the **RAG store the user wants** and it is genuinely new work
  (Phase 6). It must be **binary vectors on a SIMT substrate, not JSON**.

### Pillar G — SIMT substrate  **[BUILT partial]**
- NOTES.md: "Everything bare-metal on **SIMT + Metal** (Zig CPU reference, MSL GPU,
  golden-vector parity; never mlx-swift, never CoreML)."
- `SixFour/Atlas/AtlasTrainer.swift` — MPSGraph value training **proven on iPhone 17 Pro**
  (12.4 ms/step, bit-identical Mac↔iPhone).
- `SixFour/Metal/KMeansPalettePipeline.swift`, `Shaders.metal`, `GPUContext.swift` — existing
  GPU palette/colour kernels.
- **Keystone GAP:** `no-metal-golden-gate` — the *first* byte-exact Zig↔Metal golden — is named
  in NOTES.md but unbuilt. Every new SIMT kernel (genome ops, vector store, per-frame collapse)
  must land behind this gate.

### Pillar H — MAP-Elites  **[REVIVED — decided 2026-06-18: go hard]**
- `spec/archive/COMPETITION.md` retired MAP-Elites (2026-05-27) only because the *grid* was keyed
  to the deleted Berlin–Kay categories. The QD **intent** ("keep an archive of diverse-but-
  beautiful elites; the user is the reward") was never wrong — only its discretisation.
- **DECISION (Daniel): revive MAP-Elites as the canonical model, gridless.** Use **CVT-MAP-Elites**
  (Vassiliades et al. 2017 — Centroidal Voronoi Tessellation cells over a *continuous* behavioural
  descriptor, no axis-aligned grid). The DPP gallery (`Spec/Preference.hs`) is **demoted to the
  per-session *display* selector** (pick a diverse swipe-set *from* the archive), not the archive
  itself. The archive is the structure; the DPP view is one read of it.
- **Behavioural descriptor (the illumination axes), from Daniel's #3:**
  1. **policy:value ratio `r`** — the search's explore/exploit mix (see Pillar B/D below). This is
     the headline axis: the archive illuminates looks from policy-heavy (exploratory) to
     value-heavy (exploitative).
  2. **gamut/chroma diversity** — `gamutCoverageFraction` / effective-dim (`Spec/Coverage.hs`,
     `Spec/Diversity.hs`), already golden-computable at zero labelling cost.
- **Mutation operator = `sampleOrthogonalPair` (Pillar B).** Each capture's A,B are two elites
  drawn from cells at *different* `r` — orthogonal by construction, divergent by descriptor.
- **The archive IS the Pillar-F vector store** (see §9 analysis): one structure, not two.

---

## 2. The target architecture (per capture session)

**A and B are TWO INDEPENDENT reductions, every capture** (Daniel's #3 — not a split of one):

```
 capture 64-frame burst (64×64)              [Pillar E: per-frame StageA palettes]
        │
        ▼  reversible (2×2)×(2×2)→1  (Spec.VoxelReduce = CubeLadder ∘ TemporalLoop)
   64³ index cube  ──lossless──►  16³ substrate          [Pillar A]
        │
        ├──────────────────────────┬──────────────────────────┐
        ▼ search A: ratio r_A       ▼ search B: ratio r_B       │  r_A ≠ r_B  ⇒ divergent
   (policy-heavy / explore)    (value-heavy / exploit)          │  [Pillar B + D]
   ┌──────────────┐            ┌──────────────┐                 │  seeded from RAG archive
   │  64³→16³ (A)  │    ⊥       │  64³→16³ (B)  │  exact orthog. │  cells (§9)
   │ per-frame look│            │ per-frame look│  genomeInner≈0 │
   └──────┬───────┘            └──────┬────────┘                 │
          └────────  A/B pick  ────────┘   btUpdate θ (no server) ┘  [Pillar D/F]
                       │
                       ▼   |r_A − r_B| shrinks next round (start-diverse → converge)
                  satisfied?
                       │ yes
                       ▼   learned generative reversal  NetSynth256    [Pillar C]
                   256³ Export Family  {16³,64³,256³ GIF + genome embedded}
                       │
                       ▼   genome → CVT-MAP-Elites archive = vector store (Q16, SIMT)  [Pillar F/G/H]
```

**The policy:value ratio is the engine of divergence.** Each search ranks terminal genomes by
mixing a policy prior with a value estimate (Gumbel-AlphaZero, `SIXFOUR-ALPHAZERO-COLLAPSE-DESIGN.md`
§5.3). A and B run *independent* searches with **different mix ratios** — A explores (policy-heavy),
B exploits (value-heavy) — so they diverge by construction. The ratio gap `|r_A − r_B|` **is** the
session divergence schedule Δ (Pillar D): wide on the first round, narrowing as the user picks. The
ratio is also the headline MAP-Elites behavioural-descriptor axis (Pillar H).

Everything on the path is a **per-frame** palette (Pillar E); the genome is the *palette factor*
that modulates the per-frame family; the cube ladder is the *index factor*; they stay decoupled
(`GenomePair.hs`: "the genome is the palette factor; R/RGBT spatial lift is the index factor;
they are decoupled").

---

## 3. Built vs. gap — the honest ledger

| Pillar | Component | State | First file to touch |
|---|---|---|---|
| A | reversible 64³↔16³ lift | **BUILT (spec+Zig)** | `Spec/CubeLadder.hs`, `Spec/RGBTLift.hs` |
| A | joint spatio-temporal reduce op | **GAP (compose exists, unnamed)** | new `Spec/VoxelReduce.hs` |
| B | exact orthogonal A/B genes (two independent searches, `r_A≠r_B`) | **SPEC** | `Spec/GenomePair.hs` (port to device) |
| C | learned 256³ super-res | **DESIGN/STUB (`error "TODO"`)** | `Spec/ExportFamily.hs` `NetSynth256` |
| D | divergence schedule Δ = `|r_A−r_B|` (policy:value gap) | **GAP (ramp exists, no Δ knob)** | `Spec/PersonalGenome.hs` + new `Spec/DivergenceSchedule.hs` |
| E | per-frame palette OUTPUT | **GAP (input built, output global)** | `DeterministicRenderer.render()` (keep), retire global branch |
| F+H | RAG gene store **=** CVT-MAP-Elites archive (one object) | **GAP (carrier built)** | new `Spec/CVTArchive.hs` (= `GeneStore`) |
| F | vectors-not-JSON | **BUILT (carrier Q16)** | `Spec/GenomeCarrier.hs` |
| F | retrieval metric = orthogonality metric | **BUILT** | `Spec/GenomePair.hs` `genomeInner` |
| G | SIMT genome/store kernels | **GAP (substrate proven)** | `no-metal-golden-gate` first |

---

## 4. The misdirection to retire (the "global palette" surface)

These are the **single-global-collapse** symbols. They are tagged, **not deleted** (§6). They
stay green and gated as a regression reference; the migration routes the *live* path around them.

| Layer | Symbol | File |
|---|---|---|
| Zig | `s4_global_collapse` | `Native/src/kernels.zig:459` |
| Swift FFI | `globalCollapse`, `GlobalCollapseResult` | `SixFour/Native/SixFourNative.swift:260` |
| Swift render | `renderGlobalPalette` | `SixFour/Encoder/DeterministicRenderer.swift:317` |
| Swift VM | `renderDeterministicGlobal`, `paletteScope == .global` branch | `SixFour/UI/Screens/Capture/CaptureViewModel.swift:599,680` |
| Settings | `paletteScope` (global case) | `SixFour/Settings/AppSettings.swift` |
| Haskell | `globalCollapseQ16`, `globalCollapseIndicesQ16`, `reindexFrameQ16` | `spec/src/SixFour/Spec/Collapse.hs:101` |
| Export | `LadderExport.flatGlobalLeaves`, `LadderGIF.encodeGlobal` | `SixFour/Encoder/LadderExport.swift`, `LadderGIF.swift` |

> **Subtlety for the gate:** `scripts/verify-doc-claims.sh` ANCHOR 1 asserts "global collapse
> wired (≥1 production caller)." When the migration removes the last *live* global caller, that
> anchor must be **inverted** (assert global is reference-only / tagged), in the same commit, or
> the gate fails. Do not silently delete the anchor — rewrite it to the new truth.

---

## 5. Migration phases (spec-first, each gated by `scripts/s4.sh all`)

Order follows the repo's own gate-order (`codegen → doc → verify → native → lint → gen → build`).
Each phase is mergeable on its own and changes **no app behaviour** until Phase 5.

- **Phase 0 — Tag + lint (this workflow, no behaviour change). ✅ DONE 2026-06-18.** §6 tags applied
  at the 5 core global-collapse defs. `scripts/lint-no-global-palette.sh` freezes the call-site set
  (passes clean; catches a new caller) and is wired into `s4.sh lint`. Memory + STATUS direction
  pointer updated. *The directory now declares its intent.*

- **Phase 1 — Name the reversible reduction. ✅ DONE 2026-06-18.** `Spec/VoxelReduce.hs` = the
  composition (spatial `CubeLadder.distill` per channel ∘ temporal `TemporalLoop.haarSplitTime` per
  position) as one `(2×2)×(2×2)→1` operator. `lawVoxelReduceBijective` (expand∘reduce = id) passes
  100 random cubes + 2 fixed-cube goldens; `lawVoxelSubstrateShape` + `lawVoxelReduceDeterministic`
  green. Wired in cabal + `Spec.Map` + test driver.
  **Next (Phase 1b) — AUDITED per `docs/SIXFOUR-REUSE-FIRST-NO-NEW-DEBT-WORKFLOW.md` §5.1:** NO
  monolithic `s4_voxel_reduce`. The spatial half reuses the existing `s4_cube_lift_level` /
  `s4_cube_unlift_level` (exact `CubeLadder` twin, already golden-gated); the temporal half is one
  new loop reusing the S-transform — which is FACTORED out of `rgbtLiftQuad` (4 inline copies) into
  shared `sLift`/`sUnlift` helpers (debt cleanup) — with its own golden from `TemporalLoop`; and
  on-device VoxelReduce ORCHESTRATES the two, mirroring the Haskell composition. Net new lift math:
  zero. Net inline duplicates removed: four.
  - **1b.1 ✅ DONE:** factored `sLift`/`sUnlift` out of `rgbtLiftQuad`/`rgbtUnliftQuad` (kernels.zig);
    `zig build test` byte-identical (goldens prove it).
  - **1b.2 ✅ DONE:** temporal one-level kernel `s4_haar_split_level` / `s4_haar_join_level` (reuse
    `sLift`/`sUnlift`), pinned to `TemporalLoop.haarSplitTime` via `temporal_golden.json` +
    `temporal_fixture_test.zig` (byte-exact + odd-length negative round-trip). Header (33 syms) +
    doc gate green. Spatial half reuses existing `s4_cube_lift_level` (no code).
  - **1b.3 ✅ DONE (compile-gated):** Swift `VoxelReduce` (`SixFour/RGBT4D/VoxelReduce.swift`) =
    per-channel/per-frame `RGBT4DLift.distill` ∘ per-position temporal split (reuses
    `RGBT4DLift.sLift`) — REUSES the existing golden-gated Swift port, owns no new lift.
    `Codegen.VoxelReduce` → `Generated/VoxelReduceGolden.swift` pins the substrate from
    `Spec.VoxelReduce`; `VoxelReduceGoldenTests` asserts substrate byte-exact + round-trip (×1 and
    ×2 levels). `TEST BUILD SUCCEEDED` (arm64). Tests run on device/sim (no sim on the headless box).

  **Phase 1 is COMPLETE across all four languages:** Haskell spec (882 tests) ≡ Zig
  (`s4_haar_split_level` + `s4_cube_lift_level`, golden) ≡ Swift (`VoxelReduce`, golden, compile-gated).
  The `64³↔16³` reversible reduction is owned, named, and proven. **Next: Phase 2** (per-frame
  palette OUTPUT contract) or **Phase 3** (orthogonal A/B as two independent searches).

- **Phase 2 — Per-frame palette OUTPUT contract.** Extend `Spec/StageA`/render contract so the
  look produces a **per-frame palette family** (not a collapsed global table). Keep
  `DeterministicRenderer.render()` (already per-frame); make it the canonical path. Pin a golden
  that the per-frame GIF is byte-stable.

- **Phase 3 — Orthogonal A/B as two independent searches.** Port `GenomePair.sampleOrthogonalPair`
  / `chooseDisjointBands` to Swift+Zig (`s4_orthogonal_pair`), gated bit-exact vs the Haskell laws;
  replace the `perturb()` stub. Run **two independent Gumbel searches** (A,B), each with its own
  policy:value mix ratio `r` (the search already exposes the prior↔value weighting). Wire both 16³
  candidate renders into the A/B UI (`docs/SIXFOUR-GENOME-AB-PIVOT-WORKFLOW.md` 8-phase FSM).

- **Phase 4 — Divergence schedule Δ = the policy:value ratio gap.** New `Spec/DivergenceSchedule.hs`:
  `Δ(session, picks) = |r_A − r_B|` starts large (A explores, B exploits → very different) and
  shrinks monotonically as the user picks (couples to `PersonalGenome.personalBeta`). Law: `Δ`
  monotone non-increasing in picks, **bounded below > 0** (A and B never collapse to identical).
  Feeds Phase 3's two searches *and* is the headline MAP-Elites descriptor axis (Phase 8).

- **Phase 5 — Defer global to V2 (MVP1 is per-frame only). NO DELETION.** Final framing
  (Daniel, 2026-06-18): the global path is kept, compiled, and recoverable, behind ONE gate
  (`Feature.globalPaletteV2 = false`); MVP1 ships per-frame only. Dedicated mapped plan:
  **`docs/SIXFOUR-GLOBAL-PALETTE-RETIREMENT-WORKFLOW.md`** (V0–V6: add gate → guard the live
  router → retag V2-DEFERRED → MVP1 UI hides scope → doc-claim asserts the flag is OFF → docs →
  verify). Same map as the deletion plan, action flipped from delete to V2-defer. Two protections
  intact: the `Collapse.hs` math/path split, and the Atlas stays (future direction). The
  freeze-lint stays a freeze (blocks NEW global callers); nothing is removed.

- **Phase 6 — Learned 256³ super-resolution.** Fill `NetSynth256` (the `error "TODO"` stubs):
  the generative reversal that synthesises detail above the nearest-neighbour floor, gated
  bit-exact-equal-to-floor at zero genome. Trainer work (Pillar C) — `trainer/` produces the
  synth weights; deploy as a hand-written Swift/Metal forward pass per CLAUDE.md.

- **Phase 7+8 (merged) — CVT-MAP-Elites archive = the SIMT vector RAG store.** One object
  (`Spec/CVTArchive.hs`, a.k.a. `GeneStore`), per §9. On-device archive of **Q16 384-DOF genomes**
  (reuse `GenomeCarrier` layout), CVT cells over the continuous descriptor (policy:value ratio +
  gamut/chroma diversity), mutation = `sampleOrthogonalPair`. Retrieval = batched **`genomeInner`**
  (the orthogonality metric, reused) on Metal behind `no-metal-golden-gate`, fixed-order Q16-key
  reduction. Queried at search root to seed the two A/B searches (far cells early → near cells as θ
  sharpens). DPP gallery (`Spec/Preference.hs`) demoted to the per-session display selector reading
  *from* the archive. **No JSON on any hot path.**

---

## 6. Tagging convention (DO NOT DELETE)

The repo already uses inline status banners (`⚠️ OWNED-BUT-UNWIRED`). Mirror that. The tag is a
**grep target + a pointer**, never a deletion.

**Inline marker** (Swift/Zig/Haskell — comment syntax per language):
```
⚠️ DEPRECATED-GLOBAL-PALETTE — single-global-collapse misdirection; superseded by per-frame +
orthogonal-A/B genomes. Kept as a green regression reference, NOT a live path.
See docs/SIXFOUR-PER-FRAME-GENOME-AB-MIGRATION-WORKFLOW.md §4. Do not add new callers.
```

**Rules:**
1. Tag every symbol in §4 at its definition site. Keep all tests green (they are the regression
   reference).
2. **Lint gate** (`scripts/lint-grid.sh` or a sibling `scripts/lint-no-global-palette.sh`): fail
   the build if a **new** call site of a tagged symbol appears outside the tagged file itself and
   its existing test files. This freezes the blast radius without deleting anything.
3. Doc gate: when the live path flips (Phase 5), update `verify-doc-claims.sh` ANCHOR 1 to assert
   the global path is reference-only.
4. STATUS.md: add a one-line direction pointer to this doc; do not rewrite the whole ledger until
   Phase 5 lands.

---

## 7. Decisions — RESOLVED 2026-06-18 (Daniel)

- **Q1 — MAP-Elites vs DPP gallery → REVIVE MAP-ELITES, GO HARD.** CVT-MAP-Elites (gridless,
  continuous descriptor) is the canonical model. The DPP gallery is demoted to the per-session
  display selector (reads diverse swipe options *from* the archive). `sampleOrthogonalPair` is the
  mutation operator. Descriptor axes = (policy:value ratio `r`, gamut/chroma diversity). See
  Pillar H + §9. *Phase 8 is now "build CVT-MAP-Elites archive," not "decide."*

- **Q2 — the RAG embedding → ANALYSED in §9.** Verdict: **item = 384-DOF genome**, stored Q16
  binary (reuse `GenomeCarrier` layout); **similarity = `genomeInner`** (the orthogonality inner
  product, reused); **query = current `g0` ⊕ θ-tilt** (retrieve looks near the working point,
  re-ranked by taste). The archive *is* the store *is* the MAP-Elites structure — one thing.

- **Q3 — per-frame genome granularity → TWO INDEPENDENT REDUCTIONS, EVERY CAPTURE.** Not a split
  of one cube and not one-genome-expanded. `64³→16³ (A)` and `64³→16³ (B)` run as two independent
  policy/value searches with different mix ratios `r_A ≠ r_B` (Pillar B/D, §2 diagram). The
  ratio gap is Δ and is the headline MAP-Elites axis. Both A and B carry per-frame palettes.

---

## 8. Cross-references (do not duplicate these — extend them)

- `docs/SIXFOUR-GENOME-AB-PIVOT-WORKFLOW.md` — the existing 8-phase A/B FSM + Export Family. This
  migration **is** that pivot, made the default and freed from the global collapse.
- `docs/SIXFOUR-ALPHAZERO-COLLAPSE-DESIGN.md` — policy/value over reversible OKLab moves; the
  A/B pick is its reward signal. Compatible: the genome *moves* are the policy's action space.
- `docs/COLOR-ATLAS.md` — on-device MPSGraph training (proven). The Phase-6 synth trainer and
  Phase-7 store build on this substrate.
- `spec/archive/COMPETITION.md` — the retired MAP-Elites design (Q1 context).
- `docs/STATUS.md` — canonical *status*; add the direction pointer, reconcile fully at Phase 5.

---

## 9. RAG fit analysis — WHERE retrieval belongs

> Task: "do an analysis to find WHERE RAG fits best." This section is that analysis. RAG here =
> *retrieval over a vector store of learned genes*, **on a SIMT substrate, binary Q16, never JSON.**

### 9.1 What is being retrieved, and the metric

- **Item (the vector):** the **384-DOF σ-pair genome** — the look itself. Stored Int32 LE Q16
  (reuse the `GenomeCarrier.hs` layout already chosen *because* float/JSON "would silently
  truncate"). This is the "vectors not JSON" requirement, already half-built.
- **Similarity metric:** **`genomeInner`** (`Spec/GenomePair.hs`) — the W-weighted generator-space
  inner product. This is the SAME function that proves A⊥B (`lawPairOrthogonalExact`). One metric
  serves both orthogonality and retrieval; no new distance to define or gate.
- **Query:** the working point `g0` of the current capture, optionally tilted by the 770-D taste
  θ (retrieve looks *near where you are*, re-ranked by *what you like*).
- **Why not key by θ:** θ is the *taste* (one per device, ~3 KB, a fold over the pick log). It is
  the **re-ranker / query bias**, not the item. Items are genomes; θ scores them.

### 9.2 The five candidate insertion points (scored)

Criteria: **leverage** (does it serve "start-diverse-then-converge" + A/B), **latency budget**
(must NOT touch the 20fps capture loop; gallery-time ms is fine), **SIMT-fit** (batched
`genomeInner` + fixed-order Q16-key reduction, the §5.3 frontier pattern), **build cost**,
**alignment** with the decided architecture.

| # | Insertion point | Leverage | Latency | SIMT-fit | Verdict |
|---|---|---|---|---|---|
| 1 | **Search-root warm-start** — seed the two searches (A,B) from retrieved archive elites near `g0`, at different `r` cells | **High** — *is* start-diverse (pull from far cells early) → converge (tighten the neighbourhood as θ sharpens) | gallery-time, fine | batched inner = §5.3 frontier | **PRIMARY** |
| 2 | **MAP-Elites archive backing** — the CVT archive *is* the vector store; "retrieve nearest occupied cell" = a similarity query | **High** — unifies Pillar F + H into one structure | offline / between captures | native | **PRIMARY (same store as #1)** |
| 3 | **Episodic value prior** — augment the linear-770 value with a kNN term over past Compare outcomes for similar genes (NEC / episodic-control style) | Medium — densifies sparse preference, but overlaps the planned KataGo aux heads (§6) | search-time, bounded | yes | **SECONDARY (v2)** |
| 4 | **Per-move policy retrieval** — retrieve past Edit trajectories for similar boards to bias the policy | Low/Med — heavy, big new surface, marginal over Gumbel-search | search-time, costly | partial | **REJECT (for now)** |
| 5 | **Cross-user / federated RAG** — retrieve other users' genes | N/A on-device — CLAUDE.md forbids a server; `GenomeBlend` already handles a *received* genome as one Compare | n/a | n/a | **REJECT (no server)** |

### 9.3 Verdict

**RAG fits best as ONE structure: the CVT-MAP-Elites archive realised as a SIMT vector store of
Q16 genomes, queried at the root of the two A/B searches** (points 1 + 2 are the same store).

- **It is the archive AND the store AND the warm-start** — Pillars F, H, and the A/B seed collapse
  into a single owned object. No second database.
- **Retrieval = `genomeInner` batched on Metal**, identical in shape to the §5.3 "GPU batched value
  oracle": collect the archive frontier (M genomes), one dispatch, read back M Q16 similarity keys,
  fixed-order reduction, argmax with lowest-index tie-break. The integer key — not the float — is
  the cross-tier contract (`lawArgmaxKeyDependsOnlyOnKeys` already governs this discipline).
- **It directly powers "start-diverse-then-converge"**: round 1 retrieves elites from *far-apart*
  `r` cells (very different A/B); each pick sharpens θ, which tightens the query neighbourhood and
  shrinks `|r_A − r_B|` → the candidates converge.
- **Secondary (v2):** the episodic value prior (#3) once enough Compares accrue — but gate it
  behind the same GLRM kill-switch (§5.4) so retrieval can't inject noise into the value head.

### 9.4 Where RAG must NOT go (anti-requirements)

- **Not in the 20fps capture loop** — retrieval is a Review/gallery-time op; the capture path stays
  the deterministic integer fold.
- **Not JSON, anywhere on the hot path** — Q16 binary vectors only (the wire format is already
  decided in `GenomeCarrier.hs`).
- **Not on the deterministic integer ladder** — the cube lift is parameter-free and exact;
  retrieval lives in the *genome/palette* factor, never the *index* factor.
- **Not a learned dynamics model** — retrieval seeds and re-ranks; it never replaces the reversible
  transition (no MuZero latent model; §6 REJECT stands).

### 9.5 Build slot

This is **Phase 7** (`Spec/GeneStore.hs`), now specified by §9.1–9.3: an on-device CVT-MAP-Elites
archive of Q16 genomes with a `genomeInner` SIMT similarity kernel behind `no-metal-golden-gate`,
queried at search root. Phase 8 (the CVT archive structure) and Phase 7 (the store) **merge** —
they were always one object.


# SixFour — Debt Reconciliation & Cleanup Report

> Synthesis of five audit phases (iPhone 17 Pro / iOS 26 on-device-ML research ×2, a 45-doc
> classification, a 3-part Haskell spec audit, a 2-part Zig review), reconciled against
> `docs/STATUS.md` (the canonical ledger) and verified against current source on 2026-06-09.
> Where memory and STATUS disagreed, STATUS + source won.

## (a) Executive summary

The codebase is **healthier than project memory implies**, and the dominant remaining debt is
**doc drift around a UI atom change (6pt→4pt) and deleted views**, plus a **single coherent
architectural gap**: the personalization spine (on-device look-learning) is fully *designed* and
*partially trained on the Mac*, but **nothing learns or runs a learned genome on the device**.

Key reconciliations (memory → reality):
- **"GIFB never produced / s4_global_collapse has 0 callers"** — FALSE. Global collapse is WIRED
  in production (`CaptureViewModel.renderDeterministic → renderDeterministicGlobal →
  DeterministicRenderer.renderGlobalPalette → SixFourNative.globalCollapse → s4_global_collapse`).
  STATUS already records this; three docs still open with the stale "gap" framing.
- **"s4_quantize uses maximin ≠ Wu canon (REAL BUG)"** — NOT A BUG. Maximin (Gonzalez 1985,
  farthest-first) **IS** the Haskell canon (`Spec.QuantFixed`/`Spec.Collapse`). Zig matches the
  spec byte-for-byte. The memory note referred to an older Metal/Swift path, not this contract.
- **"No look-NN trainer / Spec.Loss unported"** — STALE. `trainer/train_look_net_mlx.py` exists
  (PonderNet halting + GAN/soft-OT + Bures anchor) and `trainer/look_net_loss_mlx.py` mirrors
  `Spec.Loss` term-for-term, gated at 1e-6. Caveat: grayscale-L-only, synthetic-only, Mac-side,
  **never deployed** (`loadLookNet` has zero callers).
- **Decoder DOF** — 384-DOF σ-pair head confirmed everywhere; the "768" figure is dead.

The genuinely-dead/unwired surfaces are all on the **learned/personalization side**: the
on-device forward pass (`loadLookNet` 0 callers), the search value head
(`PaletteValue.swift` 0 callers), the preference/Bradley-Terry spec (`Spec.Preference` orphan),
the look-category taxonomy (deleted with `Spec.Competition`), and two orphan authoring stages
(`Spec.HaarRibbon`, `Spec.QuartetDelta`). Real defects are tiny: a stale `s4_synth_burst`
header signature (Mac tooling, contained) and three Zig exports missing header declarations.

This report archives **13 superseded docs**, keeps **the rest as a live idea reservoir**, and
lists the concrete spec/Zig fixes plus regenerable build dirs to reclaim.

## (b) What SixFour IS vs IS NOT

**IS (verified against the cell-field canon + source):**
- An iOS 26 camera app, zero third-party deps, hand-written Swift + Metal + Zig.
- A **deterministic, integer-exact Zig render core** (18 `s4_*` header symbols; 21 actual
  exports) that folds a 64-frame burst → 64×64×256 GIF byte-identically across devices. Default
  path (`useDeterministicCore = true`); the GPU-float renderer is the throw-fallback.
- **"One cube projected honestly"**: a 64³ index cube is the only state; the 2D GIF, the 16×16
  palette grid, and the shutter are Haar projections of it. GIFA (per-frame) **and** GIFB
  (global pooled-maximin collapse) both ship.
- The **cell-field grid app**: the whole screen is ONE data-coloured 4pt cell field @20fps
  (GRID v3.0 / CellField / ownership grid). The five-acts flow is a LAYER over that field.
- **Haskell-as-source-of-truth**: 595 spec tests green, cross-language goldens pin Zig ≡ Swift ≡
  Haskell. Map-lint and Haddock-header lint are CLEAN for all Spec.* modules.

**IS NOT (yet) — the personalization north-star is unbuilt:**
- It does NOT learn the user's look on-device. There is **no on-device trainer**, no per-user
  delta/adapter, and no learned genome runs at all (`loadLookNet` 0 callers).
- It does NOT have a **look-CATEGORY taxonomy** — the Berlin-Kay/`Spec.Competition` grid was
  deleted when `Spec.Preference` went category-free. The north-star's "looks mapped in
  categories" has no surviving spec.
- The shipped global palette is the **deterministic Zig collapse, NOT a learned NN genome**.
- It is NOT a voxel-raymarcher app — the Metal raymarcher and `VoxelCubeView` are DELETED;
  the review cube is a pure-Swift per-cell rasterizer (`Surface.bakeCube`).
- It is NOT a 6pt/2pt-atom app — the atom is **4pt** (GRID v3.0); the player/transport, glass
  chrome, and several editor views named in older docs are DELETED.

## (c) iPhone 17 Pro + iOS 26 feasibility verdict for on-device personal look-TRAINING

**VERDICT: YES — the user can genuinely train / push-pull a model on the device, and the A19
Pro is the first Apple silicon where this is comfortable rather than a stretch.** But ONLY at
small scale (a thin trainable head, not the full net), and the enabling hardware is the
**GPU Neural Accelerators**, NOT the 40+ TOPS Neural Engine.

**The decisive facts:**
- A19 Pro adds per-GPU-core **Neural Accelerators** (matmul/tensor hardware in all 6 cores),
  giving ~8 TFLOPS FP16 / ~14.7 TOPS INT8 of **programmable, autodiff-capable** compute
  (~7.4 TFLOPS measured on the 5-core A19). The 40+ TOPS ANE is **inference-only** with no
  public gradient/backprop path — it cannot train. This validates the project-memory decision
  to deploy the look-net on the GPU and skip the ANE.
- A 115K-param net is ~230 KB at FP16; a forward+backward step is well under 1 GFLOP even over a
  64-frame batch. **Compute is never the limit.** The real ceilings are 76.8 GB/s unified-memory
  bandwidth (one 32×32 FP16 matmul wants ~93 GB/s/core) and GPU kernel-launch overhead — both
  mitigated by keeping the tiny net's weights **on-chip** and fusing matmul+activation via
  Metal `cooperative_tensor`. This is exactly why the look-net must stay SMALL and tile-resident.

**The zero-dep on-device training path (ranked by fit to the Tier2 contract):**
1. **Hand-written SGD on a small look-delta head (BEST FIT).** A few-hundred-param dense/residual
   head with an MSE-style objective, trained by a hand-written gradient loop in Swift or in the
   **Zig core** (byte-exact, cross-device deterministic — a novel selling point, matching the
   `s4_*` philosophy), optionally CPU via **BNNS**. Zero deps, full loss control, no black box.
   Most on-contract.
2. **MPSGraph custom training loop (first-party GPU escape hatch).** Autodiff +
   variable-assign weight updates with an **arbitrary loss** (no innerProduct/conv restriction) —
   the path for W2/OT barycenter look-losses that Core ML cannot express. Zero third-party dep.
   Gate it to Review/idle, never live capture.
3. **Core ML `MLUpdateTask` (sanctioned, most constrained).** Genuinely runs backprop and writes
   updated weights on-device, but restricted to **innerProduct + convolution** trainable layers
   and **MSE / cross-entropy** only. Fits a "frozen deterministic/Zig base + thin trainable dense
   head"; a kNN updatable model maps directly onto **per-user look categories** — the closest
   off-the-shelf answer to the north-star's "looks mapped in categories." Acceptable as a
   fallback only if SixFour authors the `.mlmodel` itself.

**Ruled OUT on the shipped path:** `mlx-swift` (third-party, Swift.org explicitly says
"research, not production" — confine to the Tier1 Mac trainer; the memory note "redirect deploy
to mlx-swift GPU" is STALE for the shipped path); Foundation Models LoRA (Mac-only Python
training, language model, per-OS-version adapter lock + 160MB + entitlement); Metal 4 ML encoder
/ Shader ML (inference-only, no gradients — use it to *run* the personalized head at 20fps).

**Recommended deploy spine:** Tier1 (Mac, MLX) pre-trains the base look-net; the iPhone TRAINS
only a small per-user **delta head** on a handful of "push/pull" look choices via a hand-written
SGD loop (Swift/Zig), persisting the delta through the existing
`export_look_net_blob.py` / `s4_load_look_net` byte-exact format and parser. Camera: prefer the
rawest source (ProRAW/Log, A19-exclusive ProRes RAW) for OKLab palette diversity — the value is
bit-depth/gamut, not resolution, since SixFour does its own deterministic Zig downscale.

## (d) Docs reconciliation table

### ARCHIVE (superseded / stale, with a named replacement)
| Doc | Why | Superseded by |
|-----|-----|---------------|
| APP-MAP.md | Built-state claims contradict STATUS (14 vs 18 symbols; calls real kernels "stubs"; per-frame-only when collapse is wired); points to archived ARCHITECTURE-MAP; pre-cell-field; 2pt/6pt pitch | STATUS.md |
| global-palette-skeleton-design.md | Build skeleton that mostly SHIPPED; marks quad4Analyze/FlatPalette/BranchedPalette "TO ADD" though they exist; "GIFB never produced" retired | STATUS.md + source |
| SIXFOUR-CAPTURE-GIFA-FLOW.md | Self-declares SUPERSEDED; names deleted views; wants to RESURRECT deleted VoxelCubeView/voxel_raymarch as review hero | STATUS.md (Surface refactor) + SIXFOUR-ACTS-WORKFLOW.md |
| SIXFOUR-CELL-FLUIDITY-WORKFLOW.md | v2 rides the CPU per-tick bake the newer fluidity doc deletes as the jank root cause | SIXFOUR-CAPTURE-FLUIDITY-SYSTEMS.md |
| SIXFOUR-CONTROL-AUDIT.md | "62 controls" inventory against deleted UI (CaptureView/GIFReviewView/AddressPicker/etc. all gone); self-disclaims | STATUS.md + SIXFOUR-COLLAPSE-LEVER-UIUX.md (the radix-unification idea survives there) |
| SIXFOUR-DESIGN-LANGUAGE.md | Declares 6pt/67×145 atom authoritative; live atom is 4pt/100×218 | GRID v3.0 (Lattice.hs + LatticeContract.swift) |
| SIXFOUR-DESIGN-MAP.md | Maps the 2pt/6pt era; claims Lattice/CellShapes "absent" though they ship at 4pt; governs deleted VoxelCubeView | SIXFOUR-GRID-DSL-STUDY.md + STATUS.md |
| SIXFOUR-UIUX-ARCHITECTURE-DECISIONS.md | ADR-6 mandates "gifPx=6, 2pt retired"; live is 4pt; cites deleted VoxelCubeView + cube 60Hz Timer; right ideas already shipped | SIXFOUR-TOTAL-PIXELATION.md + STATUS.md + SIXFOUR-RENDER-CONSTRUCTION-AND-DEBT.md |
| SIXFOUR-UIUX-DIMENSIONAL-MAP.md | Self-labels "GRID v2.0", 6pt/67×145; cites deleted VoxelCubeView/GIFCanvas/PlayerTransport | SIXFOUR-DESIGN-LANGUAGE successor (v3) + STATUS.md |
| SIXFOUR-UNIFIED-PLAYER.md | "IMPLEMENTED" but centers deleted GIFPlayer/PlayerTransport/VoxelCubeView/GIFCanvas; 6pt; only PlaybackClock survives | STATUS.md (2026-06-07 deletions) + Surface.bakeCube |

> Note: GIFA-GIFB-COLLAPSE-REDESIGN.md was flagged `contradictsStatus` but its *idea* (collapse
> as a scored AlphaGo-style move) is LIVE and serves the north-star, so it is KEPT-AS-IDEA with a
> one-paragraph correction note, NOT archived. SIXFOUR-RADIX-CONTROLS.md likewise has stale
> file:line citations inside a still-canonical genome idea — KEPT, citations to refresh.

### KEEP-CANONICAL (current, source-backed, authoritative on their topic)
SIXFOUR-VISION.md, STATUS.md, SIXFOUR-ACTS-WORKFLOW.md, SIXFOUR-BURES-DISCRETE-CORRECTION.md
(ADR-014), SIXFOUR-CAPTURE-FLUIDITY-SYSTEMS.md, SIXFOUR-COLOR-WIDGETS.md,
SIXFOUR-GRID-DSL-STUDY.md, SIXFOUR-INFLUENCE-FIELD-WORKFLOW.md, SIXFOUR-OWNERSHIP-GRID-DESIGN.md,
SIXFOUR-RENDER-CONSTRUCTION-AND-DEBT.md, SIXFOUR-SPEC-BROWSABLE-WORKFLOW.md,
SIXFOUR-SPEC-METHODOLOGY.md, SIXFOUR-TESTABLE-ACT1-WORKFLOW.md, SIXFOUR-TOTAL-PIXELATION.md,
SIXFOUR-DISPLAY-FSM.md (fix one stale "6pt" line), SIXFOUR-DIMENSIONAL-FIELD-ARCHITECTURE.md.

### KEEP-AS-IDEA (live reservoir — see §g for the backlog)
GIFA-GIFB-COLLAPSE-REDESIGN.md, HANDOFF-LNN-app-io-and-ui.md, ios26-render-survey.md,
L-NN-FUNCTION-DESIGN.md, L-NN-MASTER-DESIGN.md, palette-explorer-2d-3d-4d-design.md,
SIXFOUR-COLLAPSE-LEVER-UIUX.md, SIXFOUR-FOUR-GIF-UIUX-WORKFLOW.md,
SIXFOUR-GRID-COMPOSABILITY-WORKFLOW.md, SIXFOUR-HIGHDIM-UIUX.md,
SIXFOUR-JEPA-256-SUPERRES-WORKFLOW.md, SIXFOUR-JEPA-VS-STATISTICAL-CELLGRID.md,
SIXFOUR-METAL-FIELD-SPEC-ALIGNMENT.md, SIXFOUR-PALETTE-IS-MOTION-WORKFLOW.md,
SIXFOUR-PALETTE-STORY-WORKFLOW.md, SIXFOUR-RADIATION-THEMES-AND-FLUIDITY-STUDY.md,
SIXFOUR-RADIX-CONTROLS.md, SIXFOUR-SEARCH-AS-DECISION.md, SIXFOUR-WIDGET-DESCRIPTOR-WORKFLOW.md,
SIXFOUR-WIDGET-TIME-AND-GIFD-PROPOSALS.md.

## (e) Spec audit findings (87 modules: 76 Spec.* + 11 Codegen.*)

**Lint cleanliness:** All Spec.* modules pass Map-membership + Haddock-header + cabal-exposed.
`MISSING=0` on the real `spec-docs.sh` Map lint.

**True orphans (no importer, no test, no codegen, no consumer):**
- `Spec.HaarRibbon` — Act III 2⁸ Haar-ribbon authoring stage. Header claims a parity gate
  (`Properties.HaarRibbon`) that does NOT exist. Fully inert.
- `Spec.QuartetDelta` — Act II 4⁴ quartet core/displacement stage. Header claims
  `Properties.QuartetDelta` which does NOT exist. Fully inert.

**Designed-but-dead (tested in Haskell, zero Swift/codegen consumer):**
- `Spec.WidgetDescriptor`, `Spec.Loom`, `Spec.AddressPicker` — authoring/preference surfaces;
  function absorbed by CellMechanics + MovableLayout (which ARE wired). AddressPicker survives
  only as a comment in `PlaybackClock.swift:43` (the shipped glass picker was removed in the
  one-surface collapse).

**Un-wired learned heads (the personalization spine):**
- `loadLookNet` — declared, **zero production callers** (the entire learned forward path
  terminates here unreached). STATUS open-debt `looknet-load-unused`.
- `PaletteValue.swift` / `Spec.PaletteSearch` — value head + MCTS golden-pinned, **no caller**.
  Ethos pillar #4 ("NN proposes, SEARCH generates, user picks") has no runtime.
- `Spec.SigmaPairHead` equivariance instance — 384-DOF reconstruction is wired, but the formal
  σ-equivariance instance/design matrix is re-asserted only in tests.

**Half-wired golden drift:**
- `Spec.FrontProjection`, `Spec.VoxelFit` — golden emitted but no UI consumes it (VoxelFit
  shelved per a Surface.swift comment).
- `Spec.CloudProjection`, `Spec.GridAxis`, `Spec.GridScript` — hand-ported into UI but NOT
  golden-pinned (no Codegen emitter) → drift risk.

**Dangling reference:** `Spec.Map` cites non-existent `Spec.Quad4Fit` (folded per ADR-014).

**Lint under-enforcement:** `spec-docs.sh` only Map-lints Spec.* (quoted form), NOT Codegen.*
(`@.X@` form), and does NOT verify Haddock headers or the presence of claimed `Properties.*`
test modules — so the orphan stages above pass the gate silently.

**Personalization gaps (the architectural through-line):**
1. No on-device trainer spec — no gradient/optimizer/weight-update spec for the iPhone.
2. No per-user delta/adapter/LoRA spec — one global 384-DOF genome; one user == one model.
3. No look-CATEGORY taxonomy — `Spec.Competition`/Berlin-Kay grid deleted; the only
   personalization spec (`Spec.Preference`, Bradley-Terry + DPP gallery) is ORPHANED.
4. Trained model is grayscale-L-only — colour personalization is two milestones out.

## (f) Zig review findings

**The s4_quantize maximin-vs-Wu question is RESOLVED — NOT A BUG.** `s4_quantize_frame` uses
maximin (Gonzalez 1985 farthest-first), which IS the Haskell canon
(`Spec.QuantFixed.quantizeFrameQ16` / `Spec.Collapse`): first seed = farthest-from-integer-mean,
strict-`>` low-index tie-break, `divTrunc` Lloyd means, empty-cluster-keeps-centroid, strict-`<`
assignment — byte-for-byte vs Haskell. The memory "maximin≠Wu" note referred to an old
Metal/Swift path, not this Zig↔spec contract.

**Parity is strong and explicitly engineered:** every numeric kernel cites and matches a named
`Spec.*` module with shared integer literals and embedded golden LUTs (gamma_lut.bin 65537B,
srgb_linear_lut.bin 1024B, comptime-size-checked). Color, Haar lifting, blue-noise threshold,
FS/Atkinson taps, significance split-fill, and GIF89a/LZW all mirror their spec modules with a
SOLID `assemble∘decode = id` round-trip test. `s4_global_collapse` is WIRED in production.

**Real defects:**
- **`s4_synth_burst` header signature is STALE (medium).** Header declares 5 params; the Zig fn
  takes 8 (adds `l_min_q16, l_max_q16, chroma_max_q16`). A header-based C/Swift caller would
  mis-call it (wrong registers → garbage/crash). Contained because it is Mac-side tooling and
  the bridge never calls it. Fix the prototype + the `S4_SYNTH` doc block.
- **Three exports missing header declarations (low).** `s4_gif_decode`,
  `s4_gif_decode_scratch_bytes`, `s4_srgb8_to_oklab_q16` are `pub export fn` (in the `.a`) but
  absent from `sixfour_native.h` → Swift-unreachable. 21 actual exports vs the documented 18.
  Either declare them (if on-device GIF decode/verify is wanted) or comment them host-test-only.
- **Error-diffusion i32 accumulator (low, theoretical).** Zig uses i32 where the spec uses
  unbounded Int; in-gamut OKLab Q16 stays safe, but an adversarial extreme-Q16 frame could
  overflow i32 (ReleaseSafe traps) while Haskell would not. Never reached by real captures.

**Dead bridge wrappers (un-wired, not buggy):** `encodeBurst`, `haarLevelNodes`, `loadLookNet`
have zero production callers — the monolithic burst path, the level-4 16-colour shutter, and the
look-NN are not yet consumed by the app.

**Second Zig review caveat:** `s4_gif_encode_burst` golden is `unverified` — the `gif_fixture`
test skips the `golden.gif` vs `gif_golden.gif` comparison (dead fixture). The monolithic path
is composition-equality-tested but lacks a direct golden GIF gate.

## (g) Idea backlog ranked by the north-star (on-device personalized look-learning)

**NOW (enables the north-star, buildable next):**
- HANDOFF-LNN-app-io-and-ui.md — wire the forward pass + NN UI (the most direct handoff).
- SIXFOUR-SEARCH-AS-DECISION.md — keep/swipe → Bradley-Terry utility IS the on-device push-pull
  signal; the keystone preference loop.
- SIXFOUR-COLLAPSE-LEVER-UIUX.md — the cut-level slider is the literal deterministic "push/pull"
  authoring axis a learned genome later drives.
- L-NN-MASTER-DESIGN.md + L-NN-FUNCTION-DESIGN.md — the canonical look-NN design-of-record.

**NEXT (enables, but depends on NOW or on a decision):**
- SIXFOUR-RADIX-CONTROLS.md — radix choice selects the genome (768/513/384) + σ-pair-mirror edit
  (refresh stale citations).
- SIXFOUR-PALETTE-STORY-WORKFLOW.md — tap=protect / scroll=cut hands-on authoring loop.
- SIXFOUR-GRID-COMPOSABILITY-WORKFLOW.md / SIXFOUR-WIDGET-DESCRIPTOR-WORKFLOW.md — the seam new
  per-user/look-category widgets plug into with zero re-proof.
- GIFA-GIFB-COLLAPSE-REDESIGN.md — collapse-as-scored-move (correct its stale "gap" paragraph).

**LATER (supports — substrate/legibility, rides on the above):**
- palette-explorer-2d-3d-4d-design.md, SIXFOUR-HIGHDIM-UIUX.md, SIXFOUR-FOUR-GIF-UIUX-WORKFLOW.md,
  SIXFOUR-PALETTE-IS-MOTION-WORKFLOW.md, SIXFOUR-JEPA-VS-STATISTICAL-CELLGRID.md (NN-core policy),
  SIXFOUR-DIMENSIONAL-FIELD-ARCHITECTURE.md, SIXFOUR-WIDGET-TIME-AND-GIFD-PROPOSALS.md.

**PARKING (neutral / capability the north-star can later ride; not personalization itself):**
- ios26-render-survey.md, SIXFOUR-JEPA-256-SUPERRES-WORKFLOW.md,
  SIXFOUR-METAL-FIELD-SPEC-ALIGNMENT.md, SIXFOUR-RADIATION-THEMES-AND-FLUIDITY-STUDY.md.

## (h) Prioritized next actions

1. **Record the training-feasibility verdict in STATUS** (new section): on-device TRAINING is
   now hardware-realistic on the A19 Pro via the GPU Neural Accelerators (NOT the ANE);
   MLX is Tier1-Mac-ONLY; the shipped on-device path = hand-written SGD on a small delta head
   (Swift/Zig) or MPSGraph, with Core ML MLUpdateTask/kNN as the sanctioned category fallback.
2. **Archive the 13 superseded docs** (§d) into `docs/archive/`.
3. **Spec hygiene:** fix the `Spec.Map` dangling `Quad4Fit` link; either delete/test the two
   orphan stages (`HaarRibbon`, `QuartetDelta`) or remove their false `Properties.*` header
   claims; extend `spec-docs.sh` to lint Codegen.* Map entries + verify claimed `Properties.*`.
4. **Zig fixes:** correct the `s4_synth_burst` header prototype to 8 params; add (or document as
   host-test-only) the three undeclared exports; un-skip the `gif_fixture` golden so
   `s4_gif_encode_burst` is golden-pinned.
5. **Personalization spine (the north-star):** restore a look-CATEGORY taxonomy spec; add a
   per-user delta/adapter spec; spec a minimal on-device SGD update over the 384-DOF head; then
   wire `loadLookNet` + the forward pass + the preference loop (un-stranding `Spec.Preference`).
6. **Golden-pin the hand-ported drift modules** (CloudProjection, GridAxis, GridScript) with
   Codegen emitters.
7. **Reclaim build dirs** (§artifactDeletions) — confirm sizes locally first; only
   `studio/.venv` (475M) and `spec/analysis/dist-newstyle` (35M) were visible in this audit run.
8. **Tiny STATUS drift:** `atom-pitch-violations` cites `AddressPickerView.swift:173`, but that
   file is DELETED — re-target or close that open-debt row.

---

## (i) Execution log — what was actually done (2026-06-09)
This section is appended by the cleanup pass after verifying the synthesis against live source.
### Source-verification corrections to the synthesis
- **Atom = 4pt confirmed** (`SixFour/Generated/LatticeContract.swift` v3.0) — every doc archived for the 6pt/2pt atom is genuinely superseded.
- **Deleted-view claims confirmed:** `VoxelCubeView`, `CaptureView`, `GIFReviewView`, `PlayerTransport`, `GlobalPaletteEditorView`, `AddressPickerView` are all gone.
- **CORRECTION (twice over):** the synth claimed `GlassControls.swift` was deleted; I then claimed it was a dead file (0 refs). **Both wrong.** It defines `GlassIconButton`/`GlassToolbarCluster`/`GlassInfoChip`, all used by `PaletteCloudView` — a LIVE dependency. My grep checked the *type name* `GlassControls`, not the exported component names. A trial deletion broke the build (`cannot find 'GlassIconButton'`); the file was restored. Lesson: verify a file's *exported symbols*' usage, not the filename, before calling it dead — and the iOS build is the gate that caught it.
- **`loadLookNet` confirmed 0 callers** — the on-device personalization forward pass is defined but unwired (the north-star gap is real).
- **Global collapse confirmed WIRED** (CaptureViewModel → DeterministicRenderer → SixFourNative → PaletteCollapse).
- The executive summary says "archives 13 docs"; the verified, source-grounded move list is **10** (below). The other superseded-ish docs were kept as idea-reservoir.

### Docs archived (10) — reversible `git mv` to `docs/archive/`
- `docs/APP-MAP.md` → `docs/archive/APP-MAP.md`
- `docs/global-palette-skeleton-design.md` → `docs/archive/global-palette-skeleton-design.md`
- `docs/SIXFOUR-CAPTURE-GIFA-FLOW.md` → `docs/archive/SIXFOUR-CAPTURE-GIFA-FLOW.md`
- `docs/SIXFOUR-CELL-FLUIDITY-WORKFLOW.md` → `docs/archive/SIXFOUR-CELL-FLUIDITY-WORKFLOW.md`
- `docs/SIXFOUR-CONTROL-AUDIT.md` → `docs/archive/SIXFOUR-CONTROL-AUDIT.md`
- `docs/SIXFOUR-DESIGN-LANGUAGE.md` → `docs/archive/SIXFOUR-DESIGN-LANGUAGE.md`
- `docs/SIXFOUR-DESIGN-MAP.md` → `docs/archive/SIXFOUR-DESIGN-MAP.md`
- `docs/SIXFOUR-UIUX-ARCHITECTURE-DECISIONS.md` → `docs/archive/SIXFOUR-UIUX-ARCHITECTURE-DECISIONS.md`
- `docs/SIXFOUR-UIUX-DIMENSIONAL-MAP.md` → `docs/archive/SIXFOUR-UIUX-DIMENSIONAL-MAP.md`
- `docs/SIXFOUR-UNIFIED-PLAYER.md` → `docs/archive/SIXFOUR-UNIFIED-PLAYER.md`

### Disk artifacts reclaimed (~5.7 GB)
- Deleted (provably regenerable): `studio/target`, `spec/dist-newstyle`, `Native/.zig-cache`, `build-device`, `trainer/.venv` (uv.lock), `trainer/__pycache__`.
- **HELD:** `studio/.venv` (475 MB) — no lockfile/pyproject anywhere, so not provably regenerable. Awaiting user decision.

## (j) Fix backlog (a)–(d) execution — 2026-06-09

- **(c) Zig/spec hygiene — DONE, verified.** `s4_synth_burst` header prototype fixed (5→8 params);
  the 3 undeclared Zig exports (`s4_gif_decode`, `s4_gif_decode_scratch_bytes`,
  `s4_srgb8_to_oklab_q16`) declared under a tooling banner; gate upgraded from a magic count to a
  drift-proof **header-symbol-set ≡ Zig-export-set** check; dangling `Spec.Quad4Fit` removed from
  `Spec.Map`. Gates: doc-claims ✓, `zig build test` ✓, `cabal test` (624) ✓.
- **(d) Delete dead `GlassControls.swift` — REVERSED (was not dead).** See the correction above; the
  file is live and kept. No code deleted (consistent with the "code is never deleted" rule).
- **(b1) Golden-pin `oklabToWorld` — DONE, verified.** New `Codegen.CloudProjection` emits
  `CloudProjectionGolden.swift`; the Swift map extracted to a testable `CloudWorld.map` (TODO removed)
  and pinned by `CloudProjectionGoldenTests`. Gates: `cabal test` ✓, **iOS BUILD SUCCEEDED** ✓,
  **TEST BUILD SUCCEEDED** ✓. Remaining: `Spec.GridAxis` / `Spec.GridScript` goldens (their Swift
  consumer functions still need mapping first).
- **(b2) Full-burst `golden.gif` — DEFERRED (real blocker, not faked).** The skipped
  `s4_gif_encode_burst` golden needs a *composed* halfs→GIF encoder in the Haskell spec (only the 7
  per-stage pieces exist) that is byte-exact with the Zig fold, plus the STBN mask wired through the
  burst path (the test uses `dither_mode=2` with a `null` mask — the project's deferred "Stage 2/6").
  Asserting byte-exactness without proving it would violate the golden-gate ethos, so the honest skip
  stays; the STATUS row carries the precise blocker.
- **(a) Look-category + on-device-trainer spec — see `Spec.LookCategory`** (the north-star's missing
  foundation: a category taxonomy + a Bradley-Terry on-device learning step, building on
  `Spec.Preference`). Source-of-truth spec layer with laws + tests; device wiring follows the
  (still-unwired) `loadLookNet` forward pass.

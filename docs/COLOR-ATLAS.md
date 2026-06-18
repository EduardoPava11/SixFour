# SixFour Color Atlas — Canonical Design (AlphaGo-framed curation → 256³)

> **ABANDONED-PATH NOTE (2026-06-18):** the supervised MLX look-net training this doc assumes was
> ABANDONED 2026-06-17 and its trained artifacts (`look_net_trained.s4ln`, `atlas_net_trained.npz`,
> `synth_looknet_grayscale.gif`) were DELETED. Wherever this doc references those blobs, read them
> as design/regenerable references, NOT reachable files. `Spec.GLRM` is described as needing to be
> built — it now EXISTS (`spec/src/SixFour/Spec/GLRM.hs`); only wiring is outstanding. Current NN
> direction + honest as-built status: `docs/SIXFOUR-NN-DESIGN-CANON.md`, the per-net roster
> `docs/SIXFOUR-NETWORKS-CANONICAL-ROSTER.md`, and canon `docs/STATUS.md`.

**Status of record: 2026-06-10. This is the canonical design for the Color Atlas system** — the
16³ curation board, the unified Move ADT, the policy/value/search loop over σ-pair genomes, and
the two-cube → 256³ cascade upscale. It synthesizes three adversarially-judged proposals
(search-first, tensor-first, flywheel-first) and **resolves every judge critique explicitly**
(call-outs marked `RESOLUTION` inline). The forward direction it extends:
`docs/SIXFOUR-SEARCH-AS-DECISION.md` (the search-is-the-decision frame) and
`docs/L-NN-MASTER-DESIGN.md` (the Look-NN backbone). Where older docs disagree, this doc is the
record for the Atlas subsystem.

**Design principle (the flywheel rule):** the product works on day 1 with **zero trained
weights** — deterministic policy (`referencePolicy` ∩ codebook), deterministic value
(`paletteReward` + shaped curation terms) — and every user decision is a logged, replayable
training example. The NN is an *upgrade path behind failable hooks*, never a dependency.

**House constraints honored throughout:** contract-first (Haskell spec is truth; Swift mirrors
with golden parity); zero third-party iOS deps; Q16 integer-exact on the render path;
σ-equivariance architectural (gates are belt-and-suspenders, never substitutes); no stubs on the
production path; everything behind an `AppSettings` gate, default path byte-identical.
**Do not commit; leave changes in the working tree.**

---

## 1. Vision & the AlphaGo mapping

The user curates a global 256-colour palette by playing moves on a 16³ OKLab board. Algorithms
surface options (the policy), the user's accumulated taste scores them (the value), MCTS searches
the genome space between user plies, and the endgame is a recomputed — never interpolated —
256×256×256 GIF built from two 64³ cubes plus carried cascade state.

| AlphaGo | Color Atlas | Where |
|---|---|---|
| Board state `s` | `Board16` — 16³ OKLab bin grid, 6 channels (§2), built by exact `Coverage.okLabBin` arithmetic | new `AtlasBoard.hs`; bins from `spec/src/SixFour/Spec/Coverage.hs` |
| Move `a` | Two-level algebra: **curation moves** (ToggleBin / WeightRegion / PinAnchor / Compare, user plies between searches) + **genome moves** (existing `Move {mvLevel, mvIndex, mvDelta}`, MCTS plies inside a search) | new `AtlasMove.hs`; `PaletteSearch.hs:120` |
| Policy π(a\|s) | `mkAtlasOracle` — day 1 a board-modulated `referencePolicy`; later Look-NN-backboned heads over a finite 127×12 move vocabulary | new `AtlasOracle.hs`; `PaletteOracle.hs:67` |
| Value V(s) | β-blend: pinned deterministic `paletteReward` (wrapped for σ-pair states, §4) ⊕ Bradley-Terry utility `linearUtility θ` learned on-device from Compare moves | `PaletteOracle.hs:57`; `Preference.hs:59,64`; new `PreferenceUpdate.hs` |
| Search | `mctsStep`/`runSearch`/`extractGallery` **verbatim** (PUCT, persistent rose tree, LCG seed, DPP gallery) + a golden-parity Swift port for the device | `PaletteSearch.hs:200,244,277`; new `AtlasSearch.swift` |
| Self-play | Every session emits (board, move, root visit distribution, outcome) → SF64 replay file → Mac MLX trainer; Mac-side expert iteration against the pinned reward needs no humans | new `DecisionLog.hs`; trainer §5 |
| Endgame | Two-cube → 256³ re-render: cascadeInit-style carry/reset, slot-aligned Q16 palette blending, prior-weighted-nearest quantization consuming the carried state | new `AtlasCascade.hs`, `Upscale256.hs`; patterns from `/Users/daniel/QUAD-Codec/src/cascade.zig`, `/Users/daniel/QUAD-Spec/src/Quad/NN/PriorWeightedNearest.hs` |

**Where the analogy breaks (stated, not smoothed):** there is one user, not two players;
"win" = keep/Compare-pick, captured via the Bradley-Terry link, not a game outcome; the search
returns a DPP-diverse **gallery**, not a single move (the KataGo/AlphaGo lesson: surface an
option *set*); and exploration noise (Dirichlet, visit temperature) lives **only in the Mac
trainer harness**, never in the pure spec search — `lawDeterministic` purity is load-bearing for
replayability.

---

## 2. Tensor table (single source of truth for every shape)

| Name | Shape | dtype | Domain | Producer | Consumer |
|---|---|---|---|---|---|
| `palettesPerFrame` | [64,256,3] | int32 | OKLab Q16 (sRGB8 twin for display) | Zig `s4_quantize_frame` per frame | board builder, cube-B render, upscaler |
| `indexCubeB` (per-frame, GIFA) | [64,64,64] | uint8 | slot into `palettesPerFrame[t]` | existing GIFA path (`Surface.indexCube`) | board mass, upscaler |
| `indexCubeA` (global, GIFB) | [64,64,64] | uint8 | slot into `globalLeavesQ16` | `renderGlobalPalette` dither (`DeterministicRenderer.swift:352+`) | upscaler arbitration, Review |
| `globalLeavesQ16` | [256,3] | int32 | OKLab Q16 | `s4_global_collapse` → **curated/searched replacement** (§8 seam) | `BranchedPalette.projectQ16`, palette map |
| `board` s | [16,16,16,6] | float32 | normalized / signed | `AtlasBoard.boardTensor` fold over decision log | oracle featurizer, replay buffer, UI |
| — ch0 `binMassPalettes` | [16³] | float32 | count/16384 (64×256 slots; normalisedMass analog) | `okLabBin` over `palettesPerFrame` | π, V |
| — ch1 `binMassPixels` | [16³] | float32 | count/262144 | `okLabBin` over `indexCubeB` through palettes | π, V, exit state |
| — ch2 `globalCoverage` | [16³] | float32 | count/256 of current candidate leaves per bin | `reconstructPaired` of candidate genome, binned | V, coverage badge |
| — ch3 `weightField` | [16³] | float32 | signed, default 0 | WeightRegion moves | π prior reweight |
| — ch4 `killMask` | [16³] | float32 | {0,1} | ToggleBin moves | π prior zeroing |
| — ch5 `anchorMask` | [16³] | float32 | {0,1} | PinAnchor moves | π forced moves; upscaler verbatim passthrough |
| `anchorColors` | [≤256,3] | int32 | OKLab Q16 | PinAnchor moves | genome projection, Upscale256 |
| `tokens` | [≤4096,13] | float32 | OKLab float + 3 σ-invariant curation scalars | occupied bins → extended GMM tokens | L3 encoder φ′ |
| `genome` g | [384] | float32 net / int32 Q16 render | SigmaPairTree flat layout (`SigmaPairHead.hs`: root triple + per-level offsets, levels 2⁰…2⁶) | L5 / `analyzePaired` / MCTS node | `reconstructPaired` → 256 leaves; genome encoder |
| `ctx` (fused) | [128] | float32 | hidden (64 board ‖ 64 genome; each split 22 achro / 21 rg / 21 by) | board pool + σ-masked genome encoder | heads |
| `nodeLogits` | [127] | float32 | logits over addressable Haar slots | node head (σ-invariant input) | π |
| `deltaLogits` | [12] | float32 | logits over codebook | delta head (σ-pair row-swap mask) | π |
| `moveVocab` | 127×12 = **1,524** | const | (level,index,delta) | `DeltaCodebook.hs` | oracle, replay encoding |
| `deltaCodebook` | [12,3] | const | OKLab; rows 2i/2i+1 swap under σ; magnitude halves per level | spec constant | move construction |
| `valueScalar` | [1] | float64 | ℝ | σ-invariant value head ⊕ BT blend | `oValue`, gallery ranking |
| `atlasEmbedding` | [768+2] | float64 | 256 leaves ×3 via `reconstructPaired` ++ [coverage, beauty] | new `AtlasState.atlasEmbedding` | `linearUtility θ`, `greedyGallery` DPP |
| `θ` (BT utility) | [770] | float32 | float | on-device `btUpdate` | `oValue` blend |
| `visitDist` | [≤8] | float32 | Σ=1 | root `stChildren` visit counts | policy distillation target |
| `replayTuple` | board + move u32 + visitDist + outcome | mixed | SF64 records | device session | Mac MLX trainer |
| `paletteMap` M | [64,256] | uint8 | per-frame slot → global slot | `nearestQ16` per frame | slot alignment σ_f, upscaler prior |
| `ExitState` E | 256 slots × **16 B** = 4,096 B | mixed LE | mass u32 \| dL,da,db i16 (mean×128 truncated div — QUAD "Q15" convention, `bias.zig:248`, copied verbatim) \| dx,dy i16 Q8.8 \| dt i16 Q8.8 | 64³ render fold (`deriveExit`) | `exitInit` → 256³ prior |
| `outPalettes` | [256,256,3] | int32→uint8 | Q16 internally, sRGB8 LCTs | temporal slot-aligned blend | 256³ GIF |
| `Cube256` | [256,256,256] | uint8 | slot into `outPalettes[f′]` | prior-weighted nearest quantizer | GIF assembly |
| `.s4ln` v2 | 13 LookNet + 7 atlas tensors | float32 LE | raw **pre-σ-mask** | `export_look_net_blob.py` extension | `s4_load_look_net` v2, Swift forward |

> **Note (2026-06-17 AlphaZero reframe):** the `.s4ln` v2 FORMAT, `export_look_net_blob.py`,
> and the `s4_load_look_net` loader are DESIGN/CODE kept as ideas. The supervised MLX trained
> instance `atlas_net_trained.npz` (and `look_net_trained.s4ln`) were DELETED and are
> regenerable; nothing on disk is a trained artifact except the regenerable GOLDEN loader
> fixture `look_net.s4ln`. This doc's policy/value net is what the sanctioned MPSGraph trainer
> now produces.

> **RESOLUTION (judge: P0's ExitState fields summed to 16 B, not the claimed 12).** The layout
> is now 16 B/slot by construction: 4+6+4+2 = 16, no pad. Compile-time sum check
> `256 × 16 = 4096` in `AtlasCascade.hs`, mirrored byte-for-byte in Swift.

> **RESOLUTION (judge: P1's 8-channel board vs P2's 6).** Six channels. P1's ch3 (min-ΔE to
> nearest leaf) and ch7 (centroid residual) are derivable features the featurizer may compute,
> not board state; keeping the board minimal keeps the replay-determinism law cheap.

---

## 3. The Move ADT and the replay wire format

### 3.1 Curation moves (user plies — edit the board, condition the oracle)

```haskell
-- SixFour.Spec.AtlasMove
data CurationMove
  = ToggleBin    BinIdx                 -- keep/kill a 16³ bin (involutive)
  | WeightRegion BinIdx Q88             -- i16 Q8.8 signed delta, additive/commutative
  | PinAnchor    BinIdx OKLabQ16        -- palette MUST contain this colour (idempotent)
  | Compare      GenomeHash GenomeHash  -- winner, loser — state-identity; emits a BT pair
```

`applyCuration :: CurationMove -> Board16 -> Board16` is total (out-of-range = identity).
`Compare` mutates nothing — it is pure training signal. Board channels ch0–ch2 are recomputed
from σ's `palettesPerFrame`/`indexCube`/candidate genome and are **never** edited by moves
(law: curation edits touch ch3–ch5 only).

### 3.2 Genome moves (machine plies — edit the genome inside a search)

Exactly the existing `Move { mvLevel, mvIndex, mvDelta }` (`PaletteSearch.hs:120`) — lossless,
`invertMove`-reversible (`:132`), `wellFormed`-preserving — with `mvDelta` drawn from the
12-entry `deltaCodebook` (±L, ±a, ±b × 2 magnitudes {0.04, 0.01}, magnitude scaled 2^−level,
σ-paired rows). All existing move laws hold unchanged because the codebook has the same shape
as `stubOracle`'s 12 fixed perturbations (`PaletteSearch.hs:303`).

> **RESOLUTION (judge: move-space count).** The vocabulary is **127 × 12 = 1,524**, not 1,536.
> A depth-7 `HaarPalette` has 1+2+…+64 = 127 addressable level slots; `applyMove`
> (`PaletteSearch.hs:127–129`) only modifies the levels list — **the root is unaddressable**.
> P1's 128×12 counted a phantom node; pinned by a law in `DeltaCodebook.hs`.

### 3.3 SF64 replay container

TLV container ported from QUAD's `Container.hs` discipline: magic `"SF64"`, 16 B header
(magic u32 | version u32=1 | flags u16, bit0 = hasUserDecisions | entryCount u16 | reserved u32).
Chunks:

- **DECN** — fixed **32 B LE** entries: tag u8 | bin x,y,z 3×u8 | wDelta i16 Q8.8 | flags u16 |
  anchor 3×i32 Q16 (Compare reuses first 8 B as winHash u32 + loseHash u32, third i32 = 0) |
  winHash u32 | loseHash u32 | **pad u32 = 0**. Explicit compile-time sum:
  1+3+2+2+12+4+4+4 = 32.
  > **RESOLUTION (judge: P2's 32 B entry summed to 28 with padding unstated).** Pad is now an
  > explicit named field, pinned in the sum check and asserted zero on read.
- **GNOM** — u32 hash + 384×f32 genome (the candidates referenced by Compare hashes).
- **VDST** — u32 genome hash + u8 count ≤8 + count×(u32 move-vocab index + f32 visit fraction):
  root visit distributions for policy distillation.
- **BORD** — one [16,16,16,6] float32 snapshot per session open (sanity/golden only; the board
  is *re-derivable* by folding DECN — the replay-determinism law).

Laws: round-trip; TLV order-insensitive; unknown-tag forward-compat skip; **replay determinism**
(same log ⇒ bit-identical board); entry-size sum checks. Data syncs Mac↔iPhone only (QUAD
NN-PATH federated split) — it never leaves the device pair.

---

## 4. Policy, value, and how PaletteSearch consumes them

### 4.0 Rooting the search at the σ-pair genome (the depth-7/depth-8 schism)

> **RESOLUTION (judge, all three lenses — the most-flagged defect).** `paletteEmbedding`
> (`PaletteSearch.hs:267–268`) calls `PairTree.reconstruct`, which on a **depth-7** tree yields
> 128 leaves = **384** floats, not the documented 768. P0's claim that it "still yields 768" is
> false as written. **And the same bug bites the value:** `paletteReward`
> (`PaletteOracle.hs:57–62`) *also* calls `reconstruct`, so on a depth-7-rooted state it would
> score the 128 *generators*, not the 256 σ-paired leaves — σ-reflection structurally doubles
> chroma diversity, so beauty/entropy over generators is a *different objective*. No proposal
> caught the reward half; this doc fixes both at once.

Fix, in new module `SixFour.Spec.AtlasState`:

```haskell
newtype SigmaSearchState = SigmaSearchState SigmaPairTree   -- depth-7 root, 384 DOF

atlasLeaves    :: SigmaSearchState -> [OKLab]    -- = reconstructPaired, 256 leaves ALWAYS
atlasEmbedding :: SigmaSearchState -> Embedding  -- 768 = 256×3, ++ [coverage, beauty] → 770
shapedReward   :: RewardWeights -> Board16 -> SigmaSearchState -> Double
-- shapedReward routes through atlasLeaves (NOT reconstruct):
--   wb·(−beautyLossLeaves leaves) + wd·gaussianColorEntropy leaves
--   + λa·anchorHit(board, leaves) + λw·⟨ch3, binned leaves⟩ − λt·⟨ch4, binned leaves⟩
```

`PaletteSearch.hs` itself stays **byte-identical**: the search still operates on `HaarPalette`
(the depth-7 tree inside the newtype); only the Oracle we *supply* uses `atlasEmbedding` /
`shapedReward`. Laws: `length (atlasEmbedding s) == 770` for all well-formed states (closes the
unenforced-768 risk); `atlasLeaves` = leaves of `reconstructPaired`; **extend the PaletteSearch
property generators to depth 7** (today they only generate depths 1–4, so the old 768 claim was
never even exercised).

### 4.1 The Oracle (day 1, zero weights)

```haskell
mkAtlasOracle :: AtlasWeights -> Board16 -> Oracle   -- AtlasWeights zero = reference
```

`oPolicy`: start from `referencePolicy` (`PaletteOracle.hs:67`) restricted to the codebook, then
(a) **zero** priors on moves whose resulting leaf lands in a killed bin (ch4); (b) **multiply**
priors by `exp(weightField[bin])` (ch3); (c) **inject** forced anchor-satisfaction moves when
ch5 anchors are unmet; (d) **top-k = 8 + renormalize** before returning.

> **RESOLUTION (judge: expansion blow-up / unnormalized priors — `childrenFromPolicy` at
> `PaletteSearch.hs:194–195` expands every proposed move).** Adopted P0's discipline over P1's:
> top-k and renormalization are **laws on `mkAtlasOracle`** (priors sum to 1; length ≤ 8;
> killed-bin moves never proposed; empty board ⇒ `referencePolicy` ∩ codebook exactly), so
> `mctsStep`/`childrenFromPolicy` and every existing PaletteSearch law stay verbatim. The fix
> lives at the oracle seam, never as a search patch. P1's `SearchControl` module (modifying
> `Hyperparams`/`childrenFromPolicy`) is **rejected** — more invasive for no gain; its one good
> law ("k ≥ branching ⇒ identical behavior") is kept as a law on `topKRenorm`.

`oValue s = (1−β)·shapedReward s + β·btProbability (linearUtility θ (atlasEmbedding s))`, with
**β = n/(n+50)** ramping on accumulated Compare count n. β=0 today is golden-testable; the
deterministic reward dominates at tiny n (BT-overfit guard).

### 4.2 The networks (later — behind failable hooks)

Backbone reuse: the frozen LookNet (33,411 params, `trainer/generated/look_net_mlx.py`) remains
the *generator* (tokens → genome g₀ = search root / first gallery). New atlas heads:

| Component | Dims | Stored | Free (post-mask) | σ story |
|---|---|---|---|---|
| φ′ token-column extension | 64×3 new cols (10→13) | 192 | 192 | new cols are σ-invariant curation scalars; `GMM_TOKEN_SIGMA_MASK` extends with 3 fixed entries — `lookNetSigmaTheorem` composition preserved |
| Genome encoder | 384→64, σ-masked (transposed `SIGMA_DECODER_MASK` structure) | 24,576 | 13,568 | σ-equivariant by mask algebra; context splits 22 achro / 21 rg / 21 by |
| Node head | 24→127 (reads σ-invariant projection: 22 achro dims ++ ‖rg‖² ++ ‖by‖²) | 3,048 | 3,048 | node logits σ-invariant by construction |
| Delta head | 128→12, σ-pair row-swap constraint (rows 2i/2i+1 tied via chroma-negation) | 1,536 | 768 | π(σs) = σ-permuted π(s) — equivariance algebraic |
| Value head | 24→32→1 on the σ-invariant projection | 832 | 832 | V(σs) = V(s) by construction |
| BT θ | [770] linear | 770 | 770 | utility over leaves embedding |
| **Totals (new)** | | **30,954** | **19,178** | + frozen LookNet 33,411 ⇒ ≈64K stored on device |

> **RESOLUTION (judge: P0's board-only policy emits IDENTICAL priors at every tree node —
> "policy degenerates to a learned static prior").** Adopted P1's genome conditioning: the
> genome encoder reads the **node's own genome** (which changes per `applyMove`), fused with the
> board context (frozen during an episode). Priors genuinely vary across the tree.

> **RESOLUTION (judge: P1's Conv3d trunk violates the σ-equivariance hard constraint).** There
> is **no conv trunk**. Board features enter as extended GMM tokens through the existing masked
> L3/L4 pathway; every new head is mask-algebraic (the house pattern: raw stored weights,
> call-time masks). P1's export gates |V(s)−V(σs)| < 1e-4 and KL(π(s)‖σπ(σs)) < 1e-3 are kept
> as **belt-and-suspenders trainer gates**, never as a substitute for architecture.

> **σ-mirror boundary caveat (judge, shared blind spot).** The board σ-mirror law (a-bin
> i→15−i, b-bin j→15−j under chroma negation) holds only **off bin boundaries** given
> `okLabBin`'s floor-and-clamp arithmetic. The spec law is stated with that caveat and the
> QuickCheck generators avoid exact lattice points.

### 4.3 How the search consumes them — and where it runs

Mac/spec: `runSearch (mkAtlasOracle w board) (Hyperparams 1.4) (HaltOnVisits 512) seed root`
with `mctsStep` (`PaletteSearch.hs:200`) **verbatim** — pure, persistent, LCG-seeded
(s·1103515245+12345 mod 2³¹), replayable. Output `extractGallery 4 α ℓ` (`:277`) → four
DPP-diverse candidates via `greedyGallery` → the Compare UI. Root = `analyzePaired` of the
current curated palette, or the `farthestPointCollapse` baseline genome on first run (the
fidelity floor, `LookNet.hs baselinePalette`).

> **RESOLUTION (judge: "where does MCTS run on the phone?" — the Haskell spec does not ship in
> a zero-dependency iOS app; P0 was silent).** Adopted P2's plan: **`AtlasSearch.swift`** — a
> ~100-line Swift port of `mctsStep`/`runSearch`/`extractGallery` with the identical LCG,
> identical PUCT, identical ties→argmax-with-seed break, array-backed children (the spec's
> `!!`/`setAt` lists are too slow for interactive budgets — verified). Pinned by a **golden
> trace parity test**: same oracle tables + seed ⇒ identical visit counts and gallery on a fixed
> fixture, Haskell vs Swift. This is the proven Collapse/Q16 mirroring discipline. Budget:
> 512 visits × width ≤8 ⇒ trees ~10³–10⁴ nodes, interactive.

> **RESOLUTION (judge: Dirichlet noise / visit temperature).** Kept **out of the spec and out of
> the device**. Exploration noise is applied by the Mac trainer harness, which drives the same
> pure `mctsStep` with perturbed priors. `lawDeterministic` survives untouched.

Tiered degradation chain (QUAD `PalettePredictor` failable-hook pattern): `.s4ln` v2 atlas
tensors present ⇒ NN heads; absent/nil ⇒ linear θ; n=0 ⇒ pure `shapedReward`. Every tier is
deterministic and the fallthrough is silent and total.

---

## 5. Curriculum & cold start

**Phase 0 — today, no weights, no Mac.** Oracle = board-modulated `referencePolicy` + codebook;
value = `shapedReward`, β=0. All four move types have immediate deterministic UX effect: kills
zero priors, weights tilt them, anchors force moves, Compares update θ. Gate: searched palette
beats `farthestPointCollapse` on `gamutCoverageFraction` + beauty over the 7 synth classes —
the ES baseline (`studio/look-nn-baseline`) is the honest floor, per `regimen.py` discipline.

**On-device, per Compare (immediately).** New spec module `PreferenceUpdate.hs` supplies the
update rule `Preference.hs` deliberately omits:

```
θ ← θ + η·(1 − σ(θ·(w−l)))·(w−l) − η·λ·θ        η = 0.05, λ = 1e-3, dims = 770
```

~3 KB of state; the flywheel turns from move #1 with no Mac round-trip. Laws: gradient matches
finite difference (1e-6); one small-η step strictly decreases pair loss; loss antisymmetric
under (w,l) swap; ‖θ‖ bounded under λ>0; fold order-independence **not** claimed (documented).

**Mac-side staged curriculum** (QUAD Easy/Medium/Hard + chapter discipline; chapter tag packed
in the record header high byte, deterministic prime seeds):

1. **T1 — value cold start (LLN analog, no humans).** Genomes sampled Easy (stub perturbations
   of `baselinePalette`) → Medium (random codebook walks) → Hard (random σ-pair trees); labels =
   `shapedReward` — free, pinned, golden-testable. MSE regression on the value head; σ-augmented
   batches; export gate |V−V∘σ| < 1e-4.
2. **T2 — policy bootstrap (expert iteration, no humans).** Run `mctsStep` with the
   pinned-reward oracle, 256 sims/root, Dirichlet noise in the harness; train π by KL to root
   visit distributions, value by backed-up means. AlphaZero self-play where the referee is the
   golden reward.
3. **GLRM gate — before any human-preference NN training.** Port QUAD's `GLRM.hs` `fitOLS`
   (Gauss-Jordan, 1e-12 pivot): regress logged BT outcomes on [coverage, beauty, ‖chroma‖²].
   Require stable β̂ and R² signal. **If this fails, the preference data is noise; stop** — the
   single cheapest kill-switch in the plan.
   > **RESOLUTION (judge: BT overfit at tiny n; "rare epistemic hygiene").** β-ramp + L2 + this
   > gate, in that order. The NN value head never trains on pairs the linear model can't see.
4. **T3 — human loop (federated).** SF64 replay → Mac: (a) θ via SGD on
   −log `btProbability(u(w)−u(l))`; (b) value head: BT loss + 0.3·MSE-to-`shapedReward` anchor;
   (c) policy fine-tune on device visit distributions + behavior cloning of accepted moves
   (weight 0.3). Palette-space regression losses use ΔE_OkLab (port QUAD `Loss.hs` Ottosson-exact
   matrices, round-trip ≤1e-4).

**Deploy.** `.s4ln` v2: same record format, tensor_count 13→20 (φ′ cols, genome encoder, node
head, delta head, value 2×, θ). Extend `s4_load_look_net` (`Native/src/root.zig:72`) + Swift
`loadLookNet` — **this is the first caller of the existing dead-end seam** flagged in
`SixFourNative.swift`. Weights raw pre-mask; the hand-written Swift forward applies masks.
Ship gates: bit-exact blob round-trip + `.spot.json` cross-language asserts; held-out BT
log-loss < linear θ's; per-class coverage ≥ maximin baseline (≥75% per EVERY class).

---

## 6. Two-cube → 256³ cascade upscale (deterministic endgame)

Inputs: **cube A** (`GlobalResult.frameIndices` + curated `globalLeavesQ16`), **cube B**
(`CompleteVoxelVolume` indexCube + 64 per-frame Q16 palettes), **paletteMap M** [64,256]
(per-frame `nearestQ16` of each frame slot into the curated global palette, ties→lowest),
**ExitState E** from the 64³ pass.

**Carry/reset rule (`exitInit`, cascadeInit-literal — `/Users/daniel/QUAD-Spec/src/Quad/Cascade.hs`).**
Per global slot: zero the **mass** plane (scale-dependent, ∝N²); carry the dimensionless rates
`dL,da,db` (mean OKLab residual of assigned cube-B pixels vs the leaf, ×128 truncated div — the
QUAD convention at `bias.zig:248` copied **verbatim**, never "fixed"), `dx,dy` (Q8.8 spatial
drift) and `dt` (Q8.8 temporal occupancy drift); session counter +1. One memset, in-place safe,
byte-pinned Haskell↔Swift (the `prop_CASCADE_haskell_zig_agree` pattern).

**Temporal 4× (64→256 frames), slot-aligned.** Output frame f′ = 4t+k, k∈{0..3}:

- **Slot alignment σ_t** (P1's `alignSlots`): slots j of P_t and j′ of P_{t+1} sharing
  M[t][j] = M[t+1][j′] are matched (ties lowest); unmatched slots fall back to direct
  `nearestQ16`. *Never* blend raw index k across independently-quantized frame palettes.
- **Output palette**: `P′[j] = ((4−k)·P_t[j] + k·P_{t+1}[σ_t(j)]) >> 2` in Q16 — exact integer
  (int64 intermediate, exact shift); t=63 clamps. **k=0 reproduces P_t byte-identically** (law).
- **Anchors verbatim**: after blending, `anchorColors` are substituted exactly into every output
  palette — the user contract that pins survive to 256³.

> **RESOLUTION (judge: P2's "φ=0 ⇒ cube-A frame byte-identical" golden law is unsatisfiable —
> cube A's indices reference the *global* palette while the output palette is per-frame-blended;
> and P2 blended raw index k across frames).** Both fixed: the upscaler is **cube-B-relative**
> (P0's "source colour from the richer per-frame cube"), slot alignment is explicit (P1), and
> the golden laws are the *satisfiable* ones below — no law claims cube-A byte-identity.

**Per-pixel rule (recompute, never interpolate).** Output pixel (f′, 4y+v, 4x+u):

- Target colour `x` = Q16 temporal blend `((4−k)·c_t + k·c_{t+1}) >> 2` of cube-B
  palette-reconstructed colours at source pixel (t, y, x) and (t+1, y, x).
- Candidate slots = slot of the source pixel ∪ slots of its 3×3 source neighborhood mapped
  through σ_t (≤10 candidates) — spatial 4× refines edges instead of replicating blocks.
- Quantize by **prior-weighted nearest** (port of
  `/Users/daniel/QUAD-Spec/src/Quad/NN/PriorWeightedNearest.hs`):
  `score(j) = d²_Q16(x, P′[j]) − λ·prior(j)`, λ=1, ties→lowest index, where `prior(j)` is the
  carried drift agreement of E's slot M-image (sign agreement of (x − P′[j]) with the carried
  dL,da,db rates — the *consumption* side QUAD left latent; here it is load-bearing).
- Killed-bin arbitration: where the curated palette and cube B disagree (pixel colour falls in a
  ch4-killed bin), cube A wins: x snaps to `globalLeavesQ16[indexCubeA[t,y,x]]` first.

Output: 256 frames × 256², per-frame LCTs from `P′` → existing GIF assembly with `upscale=1`.
The existing `upscale=4` index replication remains the byte-identical fallback when the gate is
off. Learned refinement (a residual head on x before quantization) is a later swap behind the
same quantizer interface.

**Laws (`Upscale256.hs`):** k=0 ⇒ output palette ≡ P_t; λ=0 ⇒ quantizer ≡ `nearestQ16`
(ties lowest); **λ=1 vs λ=0 outputs differ on a pinned fixture** (the anti-latent-carry proof —
the consumer ships in the SAME milestone as the producer, per all three judges); anchors appear
verbatim in every output palette; all arithmetic int32/int64-closed, golden SHA-256 on a fixed
synthetic cube pair; every index < palette size (total).

---

## 7. New spec modules + properties (the contract for Implement)

All under `/Users/daniel/SixFour/spec/src/SixFour/Spec/`, tests as
`test/Properties/<Module>.hs` exporting `tests :: TestTree`, registered in `test/Spec.hs` and
`spec.cabal` (house convention; deps stay base/vector/containers/text/transformers).

| Module | Key exports | Property names |
|---|---|---|
| `AtlasBoard.hs` | `Board16`, `BinIdx`, `boardTensor`, `boardTokens`, `boardSigma` | `lawMassNormalized` (ch0 Σ=1), `lawBinAgreesWithCoverage` (pointwise = `Coverage.okLabBin`), `lawSigmaMirrorOffBoundary` (i→15−i, generators avoid lattice points), `lawTokensSigmaInvariantCols`, `lawTotalOnEmpty` |
| `AtlasMove.hs` | `CurationMove(..)`, `applyCuration`, `boardFromLog` | `lawToggleInvolutive`, `lawWeightAdditiveCommutative`, `lawPinIdempotent`, `lawCompareIdentity`, `lawReplayDeterminism`, `lawBaseChannelsUntouched` (ch0–ch2 never edited) |
| `AtlasState.hs` | `SigmaSearchState`, `atlasLeaves`, `atlasEmbedding`, `shapedReward` | `lawEmbedding770`, `lawLeavesViaReconstructPaired`, `lawRewardOverLeavesNotGenerators` (≠ `paletteReward∘reconstruct` on a pinned σ-asymmetric fixture), `lawSearchPreservesDepth`; **plus depth-7 generators added to PaletteSearch's suite** |
| `DeltaCodebook.hs` | `deltaCodebook`, `moveVocab` | `lawTwelvePerLevel`, `lawSigmaClosed` (rows 2i/2i+1 swap), `lawMagnitudeHalvesPerLevel`, `lawVocab1524` (root unaddressable), `lawWellFormedPreserving` |
| `AtlasOracle.hs` | `AtlasWeights`, `mkAtlasOracle`, `topKRenorm` | `lawPriorsSumOne`, `lawWidthLeqEight`, `lawKilledNeverProposed`, `lawAnchorForcedMove`, `lawZeroWeightsIsReference`, `lawTopKIdentityWhenWide` (k ≥ branching ⇒ unchanged), `lawOracleDeterministic` |
| `PreferenceUpdate.hs` | `btUpdate`, `btLogLoss`, `btFit` | `lawGradientFiniteDiff`, `lawStepDecreasesLoss`, `lawSwapAntisymmetry`, `lawThetaBounded`, (documented non-law: fold order-independence) |
| `DecisionLog.hs` | SF64 types, `encodeLog`, `decodeLog`, layout constants | `lawRoundTrip`, `lawTLVOrderInsensitive`, `lawEntrySize32` (compile-time sum incl. pad), `lawUnknownTagSkip`, `lawReplayMonotone` |
| `AtlasCascade.hs` | `ExitState`, `deriveExit`, `exitInit`, layout constants | `lawLayoutSum4096` (256×16), `lawInitZeroesMassOnly`, `lawCarriedBytesIdentical`, `lawInitIdempotentOnCarry`, `lawQ15TruncDivMatchesQuad` (golden vs `bias.zig` semantics), `lawCounterMonotone` |
| `Upscale256.hs` | `alignSlots`, `blendPalettesQ16`, `quantizePrior`, `upscale256` | `lawK0PaletteExact`, `lawLambda0IsNearestQ16`, `lawLambdaConsumptionDiffers` (λ=1 ≠ λ=0 on fixture), `lawAnchorsVerbatim`, `lawIntegerClosed` + golden SHA, `lawIndicesInRange` |

Existing modules touched: `PaletteSearch.hs` — **no semantic change**; property suite gains
depth-7 generators and a per-depth embedding-length pin. `spec-codegen` gains emitters for the
atlas net shapes and the move-vocab table (mirroring `generated/net_shape.py` discipline).

---

## 8. Implementation phases & seams

**Phase A — spec (modules §7), then Swift mirrors.** `cabal build && cabal test && cabal run
spec-codegen`; commit nothing (house rule for this effort: leave in working tree).

**Phase B — device flywheel (zero weights).**
- `AtlasBoard.swift`, `AtlasMove.swift`, `DecisionLog.swift` — golden parity vs spec.
- `AtlasSearch.swift` — the mctsStep port, golden trace parity fixture.
- `AtlasOracle.swift` — board-modulated reference policy + `shapedReward` (mirrors
  `PaletteValue.swift` precedent).
- `PreferenceUpdate.swift` — on-device θ, persisted alongside the SF64 log.

**Phase C — UI (additive, gated, no FSM change).** Curation is an **out-of-band sub-state
inside `.review`** (like `liftedWidget`/`paletteScope`) — *not* a new FSM phase, so
`Display.hs`/`DisplayContract.swift` and the golden happy-path trace are untouched. No new
movable widget identity (avoids a `MoveContract` regen): the board view is VStack-pinned chrome
in the review field, built from `CellSprite`/`CellText` at `GlobalLattice` pitches —
16 scrubbable 16×16 slices of the 16³ board, template = `ReviewPhaseField.swift` paletteStrip.
Gate: `AppSettings.colorAtlasEnabled`, key `"sixfour.colorAtlas.v1"`, default **false** —
default path byte-identical.

**Phase D — render injection (WYSIWYG).** The curated/searched palette (Q16, one pinned
`okLabToQ16` rounding function with golden vectors) replaces `collapse.leaves` between
`SixFourNative.globalCollapse` (`DeterministicRenderer.swift:356`) and
`BranchedPalette.projectQ16` (`:363`) — the **render path**, not merely the `PaletteCollapse`
protocol (the protocol remains the display/editor seam and gains an `AtlasCollapse`
implementation for previews). Dither, pooled-significance rescue, sRGB, gifAssemble, SHA-256 all
run downstream unchanged. Test: SHA badge asserts curated-view bytes == export bytes. Brand-gate
preflight (surjectivity + minPopulation) runs live in the curation UI; export is not offered
while red.

**Phase E — endgame.** `AtlasCascade.swift` + `AtlasUpscale.swift` (deterministic 256³),
shipping the prior-weighted-nearest consumer **in the same milestone** as the exit-state
producer, with the λ=1≠λ=0 golden fixture. Native ABI additions (Zig kernels for the hot
quantize loop) come later behind the same Swift interfaces — Swift-first keeps the milestone
honest.

**Phase F — trainer.** `trainer/atlas_*.py` files (§ summary list), `.s4ln` v2 in
`export_look_net_blob.py` + `Native/src/root.zig` parser extension + `SixFourNative.swift`
loader extension (first caller of the dead-end seam). Regimen-style gates before any blob ships.

---

## 9. Risks

1. **WYSIWYG break** — palette injected into the protocol but not the render path. *Mitigation:*
   Phase D's single seam at `DeterministicRenderer.swift:356–363`; SHA badge parity test is the
   product-level regression.
2. **Brand-gate rejection** — curated palettes with dead/duplicate slots fail
   `GlobalCompleteVolume` surjectivity or `minPopulation` at export. *Mitigation:* live preflight
   in the UI; `oValue` penalty for zero-ch0-support leaves so search avoids gate-violating
   palettes; pooled-significance rescue downstream; `AtlasOracle` law that proposed genomes keep
   256 distinct leaves.
3. **Depth-7/768 schism + generator-scored reward** — the two `reconstruct`-vs-`reconstructPaired`
   bugs (§4.0). *Mitigation:* `AtlasState` wraps both embedding and reward; per-depth length
   pins; depth-7 property generators; `lawRewardOverLeavesNotGenerators` on a σ-asymmetric
   fixture.
4. **BT overfit / noisy preference data at tiny n.** *Mitigation:* β = n/(n+50) ramp; L2; DPP
   gallery diversity keeps pairs non-degenerate; the GLRM gate stops NN training cold if linear
   recoverability fails.
5. **Spec-MCTS performance on device.** *Mitigation:* `AtlasSearch.swift` arrays + identical
   LCG, golden trace parity (proven Collapse/Q16 pattern); 512 visits × width 8 ⇒ ~10³–10⁴
   nodes.
6. **Latent carry (QUAD's documented trap)** — ExitState produced but never consumed.
   *Mitigation:* producer and prior-weighted-nearest consumer ship in one milestone with the
   λ-differing golden fixture; `dt`-driven behavior is observable in the temporal switch
   behavior of slot priors.
7. **Q-format drift breaking byte-reproducibility** — float genome → Q16 leaves; the QUAD
   "Q15-that's-really-×128" truncated-div convention. *Mitigation:* one pinned `okLabToQ16`
   rounding function with golden vectors; copy QUAD's semantics verbatim with byte-agreement
   properties; SHA-256 end-to-end.
8. **σ-equivariance regression as heads evolve.** *Mitigation:* equivariance is mask-algebraic
   in every new layer; trainer export gates (|ΔV| < 1e-4, KL < 1e-3) are a tripwire, not the
   guarantee.

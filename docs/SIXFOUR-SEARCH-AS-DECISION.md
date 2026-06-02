# SixFour — The Search IS the User-Elevated Decision (AlphaGo → SixFour)

**Status:** understanding doc to ground the search build. Date: 2026-06-01. Sources: the four lens reports + cited spec files. The forward path and search ADT are spec'd and golden-verified; the on-device search runner, the learned value head, and the preference loop are NOT built — flagged inline.

This doc draws an architectural analogy to AlphaGo. The analogy is load-bearing only where stated; **every place it breaks is called out explicitly** rather than smoothed over.

---

## 1. How the Go nets work (policy + value + compute-bounded MCTS)

AlphaGo/AlphaZero use one network with **two heads**: a **policy head** emitting a distribution over moves `P(a|s)`, and a **value head** emitting a scalar `V(s) ∈ [−1, 1]` — the expected game outcome (−1 loss, 0 draw, +1 win). The value head is trained by MSE regression against actual self-play outcomes `z`: `loss = (v_θ(s) − z)²`; the policy head is trained by cross-entropy against the **MCTS-improved** visit distribution `π`, so the search teaches the net, which then steers the search more sharply — a virtuous loop (Silver et al., Nature 2016; AlphaGo Zero, Nature 2017).

The **two heads exist to truncate an astronomical tree**. Go has ≈250 legal moves per ply; a depth-`d` enumeration is ≈250^d (≈10²³ at d=10) — impossible. MCTS samples instead of enumerating, and the two heads cut both dimensions:
- **Policy biases breadth** — the prior focuses expansion on moves the net likes, shrinking the effective branching factor.
- **Value truncates depth** — a single forward pass replaces a full rollout to terminal (≈15,000× faster per the Hui exposition), so a leaf can be scored without playing the game out.

Selection uses **PUCT**, balancing exploitation (mean value `Q`) against exploration (policy prior × visit scaling):
`PUCT(child) = Q(child) + c · P(child) · √N(parent) / (1 + N(child))`.
Unvisited high-prior moves get boosted; the bonus decays as a child accrues visits. After ≈1600 simulations per move, the **root visit counts** — not the raw net — pick the move.

The **compute bound is explicit and roughly monotone**: more simulations ⇒ stronger play, and simulations are capped by wall-clock / hardware. AlphaGo runs ≈1600 sims/move (≈5s); Pachi needs ≈100,000 to reach pro-dan with no nets. The net's quality sets the effective branching factor — better priors mean fewer wasted sims. KataGo (Wu, arXiv 1902.10565) tightens this for small budgets: an **uncertainty-weighted** value head (resimulate only where the net is unsure) and **auxiliary heads** (score, ownership) for sample efficiency — both directly relevant to an on-device budget.

Sources: AlphaGo Nature 2016; AlphaGo Zero Nature 2017; AlphaZero (Silver et al., Science 2018); KataGo (Wu 2019, arXiv 1902.10565); Hui, "AlphaGo How It Works Technically"; Lc0 AlphaZero primer.

---

## 2. The mapping onto SixFour (what's already spec'd)

The search ADT is a faithful, golden-verified Go transcription. The correspondence, with file:line:

| Go | SixFour | File:line |
|---|---|---|
| State (board) | `SearchState` = one complete `HaarPalette` (256 reconstructed leaves) | `PaletteSearch.hs:113` |
| Move | reversible OKLab delta to one Haar coefficient `(mvLevel, mvIndex, mvDelta)`, lossless, structure-preserving | `PaletteSearch.hs:118–127` |
| Move invertibility | `applyMove (invertMove m) ∘ applyMove m ≡ id` | `PaletteSearch.hs:128–130` |
| Policy `P(a\|s)` | `referencePolicy` — coarse-to-fine Haar perturbations, level-decayed priors normalised to 1 (a heuristic stand-in for the untrained look-NN policy head) | `PaletteOracle.hs:64–74` |
| Value `V(s)` | `paletteReward` = `wb·(−beautyLossLeaves) + wd·gaussianColorEntropy` (Ou-Luo pair harmony + OKLab differential entropy) | `PaletteOracle.hs:52–61`; Swift `PaletteValue.swift:75–80` |
| PUCT | `Q + c·P·√N/(1+n)` | `PaletteSearch.hs:178–183` |
| Backup | persistent rose tree; parent visits = Σ child visits | `PaletteSearch.hs:191–218` |
| Final move selection | `extractGallery` + greedy DPP (k diverse, high-value) | `PaletteSearch.hs:267–273` |

**Where the mapping HOLDS:** the PUCT formula is identical (`PaletteSearch.hs:181–183`); the tree is persistent/immutable and **deterministic by seed** via an explicit LCG (`PaletteSearch.hs:276–282`); the compute bound is expressed by explicit **halting modes** — `HaltOnVisits n` (playout budget) and `HaltOnValue thr` (quality threshold, safety-capped at 100k iters) (`PaletteSearch.hs:229–244`).

**Where it BREAKS — and this is the load-bearing difference:** Go has **one true reward = win**, learned by MSE against the realized outcome. SixFour's `paletteReward` is **not a win/loss outcome** — it is a *deterministic aesthetic oracle* (Ou-Luo pair beauty + OKLab entropy), pinned as "the value head's TARGET … pure + total; golden-pinnable," i.e. golden-testable today, before any training (`PaletteOracle.hs:52–61`, `PaletteValue.swift`). It is the **training target** for the value head, not a learned prediction of an external truth. Two further breaks: (1) the value here is **two observable terms** (beauty + diversity), not one black-box scalar; (2) the search emits a **gallery of k≈3–5**, not a single move. Crucially, **the actual user reward — keep/swipe — is NOT yet wired into either the search value or the gallery weighting** (§3).

---

## 3. The user as the value function (the elevated decision)

This is the keystone reframe: **the human keep/swipe IS the win signal.** In Go the value head approximates the game outcome; here the only ground-truth "outcome" is whether the user keeps the GIF. The machinery to turn that into a utility is spec'd:

- **Bradley-Terry link** (`Preference.hs:62–69`): `btProbability(g) = σ(g)`, `g = u(A) − u(B)`, so `P(A ≻ B) ≈ σ(utility(A) − utility(B))`. A **keep** raises `u`, a **swipe** lowers it; pairwise comparisons across galleries fit the utility.
- **Utility form** (`Preference.hs:59`): `Utility = Embedding → ℝ`; reference inhabitant `linearUtility θ·x`.
- **Quality-weighted DPP** (`Preference.hs:125–129`): `qᵢ = exp(α·uᵢ)` weights the diversity ensemble by utility.

The keep is literally **the move**: AlphaGo plays a move and that board becomes the new root; here the kept palette becomes the anchor / warm-start for the next search.

**The two bounds align by intent.** AlphaGo truncates because compute is exponential. SixFour truncates for **two reasons that push the same direction**: the on-device sim budget (battery/latency) *and* the human-attention budget. The gallery size `k≈3–5` is not a compute ceiling — it is a UX parameter; SIXFOUR-VISION.md §4 lists "gallery size k (3 vs 10 — measure engagement)" as an open decision, so the *exact* k is an open empirical question, not a fixed claim. The intuition is: that is roughly the number of options a human can judge in one glance, and "the NN proposes, a search generates the options, the user picks" (`SIXFOUR-VISION.md`). The internal node count is set by the halting condition (`HaltOnVisits` / `HaltOnValue`), which is itself an open tuning choice — any "~hundreds of nodes" figure is **illustrative, not a spec bound**: the actual count depends on the (untrained) policy prior and the chosen halt.

**Not built:** the NN value head does not exist (LookNet untrained); the keep/swipe signal is captured by the app but not fed back; no on-device Bradley-Terry update; no persistent utility θ between searches; `paletteReward` is still the deterministic metric, not learned from keeps. The integration path is open. SIXFOUR-VISION.md §4 frames the open decision as "value head (auxiliary vs read-from-core)" and "beauty metric (deterministic vs learned)"; the two concrete wirings below are **this author's synthesis of those open decisions, not a verbatim Option A/B from the vision doc**:
- **(synthesis) Re-parametrize** the search value by the user's utility `u` — harder, needs re-architecture of the Oracle.
- **(synthesis) Reweight the gallery** by the learned `u` at `extractGallery` — simpler, since `extractGallery` already passes `meanValue` as the quality scalar (`PaletteSearch.hs:270`), so swapping in `u(embedding)` is the minimal change.

Cold-start (population-warm θ vs uniform θ=0) is also unsettled (`SIXFOUR-VISION.md` §4, "preference cold-start").

---

## 4. The three radices are one object (alignment)

**16² / 4⁴ / 2⁸ are not three trees — they are three views of one median-cut `SplitTree`.** The tree is built once: binary median-cut on the widest of L/a/b at each level, tie-broken on `(coord, index)` for reproducibility, producing exactly **256 leaves in a fixed in-order** (`SplitTree.swift:64–84`, `widestAxis` at `:108–116`). The three radices collapse `collapseK` binary levels per displayed level, and `factor^depth = 256` for all three (`SplitTree.swift:104–112`, `SIXFOUR-RADIX-CONTROLS.md:9–43`):
- **16²** — `collapseK=4` → factor 16, depth 2 (two 16-ary decisions)
- **4⁴** — `collapseK=2` → factor 4, depth 4 (four 4-ary decisions)
- **2⁸** — `collapseK=1` → factor 2, depth 8 (eight binary decisions)

The **radix = the resolution of the decision**: deeper radix = more, finer binary choices over the *same* 8 underlying levels. The exponent in 2⁸ is **tree depth (8 binary splits over the widest of 3 OKLab axes), NOT 8 independent dimensions** (`SplitTree.swift:51–58` blurb).

**What ALIGNS:** the **same 256 leaves, same leaf order, same in-order adjacency** (golden: four greyscale points → identical leaf order `[0,2,3,1]`, `SplitTree.swift:10–12`). Operationally the views share one `@State brushedIndex: Int?` (`GIFReviewView.swift:17`), threaded to grid (`PaletteGridView.swift`), picker (`AddressPickerView.swift`), and cloud — so a brushed colour lights identically across views because all read the same leaf index. **Note the precise meaning:** `brushedIndex` is an index into the **stable flat 256-leaf SplitTree order** (i.e. into the 768-real flat leaf *space*), NOT a genome coordinate. When 4⁴ or 2⁸ views are shown they collapse the same leaves, but the brushed index still names a SplitTree leaf, never a Quad4 node or a σ-pair generator.

**What does NOT align — and this is precise:**
1. **The three genomes are different parameterizations**, not copies of the tree (`SIXFOUR-RADIX-CONTROLS.md:36–43`, `[SPEC-ONLY]`): Flat **768** (256 independent OKLab leaves — *the flat leaf space, explicitly NOT a genome*, `NetContract.swift:42–44`); Quad4 **513** (3 root + 6×85 non-leaf `parent ± δ` nodes — **lossy**, an injective lower-dim subspace of the 768 leaf space, exact only for Quad4-reconstructible palettes, `Quad4.hs:107–109`); SigmaPair **384** (the *shipped* output, `NetContract.swift:29–32,42–44`; 3×128 σ-pair generators — **lossy**, exact only on σ-symmetric palettes, `SigmaPairHead.hs:98–116`). So **4⁴ is a lossy subspace that shifts colours** relative to the flat leaves; the radices share leaves only at the display layer.
2. **The control choice does not yet reach the genome or the collapse** (`SIXFOUR-RADIX-CONTROLS.md:36–43` `[SPEC-ONLY]`, and the §3/§4 build steps): the deterministic collapse takes only a branching `collapseK` and returns flat leaves; branching reaches **display only**. Nothing in the collapse path produces the genome types yet.
3. **σ-pair: the OUTPUT structure is spec'd; the EDITOR constraint is TO BUILD.** `reconstructPaired` algebraically interleaves the 256 leaves as `[c₀, σ(c₀), c₁, σ(c₁), …]` (`SigmaPairHead.hs:114–116`) — that is the decoder's output form. The spec does **not** define a σ-mirror constraint on the search moves, on the collapse, or on the user-facing editor. So brushing leaf 2i lighting its σ-partner 2i+1, and `GlobalPaletteEditorView` edits being mirror-locked, are **TO BUILD**, not derivable from the spec alone. The cube is also unbrushed (`VoxelCubeView.swift` has no `brushedIndex`), and 4⁴ renders via the generic treemap, never a Quad4-specific view.

**Critical disanalogy with Go:** the radix choice is **NOT a node in the search tree.** AlphaGo's MCTS nodes are board positions; SixFour's search nodes are palette variants under reversible **Haar moves** `(mvLevel, mvIndex, mvDelta)` (`PaletteSearch.hs:118–127`) — perturbations to Haar coefficients, not radix-level operations. Branching is a property of the `SplitTree` renderer, not the search state. The radix is an orthogonal, **zero-cost display/granularity choice** over a result; search depth (how many Haar moves to explore) is orthogonal to radix depth (how to render). The intended binding (**aspirational**, `SIXFOUR-RADIX-CONTROLS.md:36–43` and build steps) is that choosing a radix *selects which genome the NN occupies* (16²→768, 4⁴→513, 2⁸→384) — but that wiring does not exist.

---

## 5. What this implies for the build

Concrete consequences, with the built/aspirational line drawn explicitly:

1. **The value head must include human preference, not just `paletteReward`.** Today the value is a fixed aesthetic oracle (beauty + diversity, `PaletteOracle.hs:52–61`); that is the *cold-start prior*, not the destination. Wire keep/swipe → Bradley-Terry update on `u` (`Preference.hs:62–69`), then either re-parametrize the search value by `u` or reweight the gallery's DPP quality term by `u` — `extractGallery` currently passes `meanValue` as the quality scalar (`PaletteSearch.hs:270`), so swapping in `u(embedding)` is the minimal change. (These two wirings are the author's synthesis of SIXFOUR-VISION §4's open "value head" / "beauty metric" decisions, not a fixed plan in the doc.) **Not built.**

2. **The search must be compute-bounded and emit a tiny aligned gallery.** Keep the explicit halting (`HaltOnVisits` / `HaltOnValue`, `PaletteSearch.hs:229–244`) sized to the *human-attention* bound (k≈3–5, where the exact k is "measure engagement", SIXFOUR-VISION §4), not just compute; the two bounds push the same direction. KataGo's uncertainty-weighted playouts and auxiliary heads (predict diversity directly) are the right efficiency moves for an on-device budget. The **on-device MCTS runner does not exist** — the ADT, PUCT, `runSearch`, and reference oracle are spec'd in Haskell; the runner would be hand-written Swift/Metal loading the trained net.

3. **The radix controls ARE the decision granularity.** Treat 16²/4⁴/2⁸ as the user's declaration of decision resolution (and, intended, of which NN genome to occupy). The honest build step is to make the collapse **branching-aware so the choice reaches the genome and the cube, not just display**. **Not built** — branching is display-only today (`SIXFOUR-RADIX-CONTROLS.md` `[SPEC-ONLY]` / `[BUILT, display path only]`).

4. **Alignment must be enforced, not assumed.** The shared `brushedIndex` is the alignment primitive — and it indexes the **flat SplitTree leaf order**, not a genome coordinate; keep it that way. Extend it consistently: thread it into `VoxelCubeView`; **build** the σ-pair editor behaviour (light σ-pairs together in 2⁸, mirror-lock edits) — that behaviour is TO BUILD, since the spec only fixes the σ-interleaved *output* (`SigmaPairHead.hs:114–116`), not the editor constraint; and give 4⁴ a Quad4-honest view. Keep the genome honesty explicit — **768 = flat leaf space, 384 = shipped genome** (`NetContract.swift:42–44`); never let the picker conflate "display SplitTree" with "σ-locked genome."

5. **Hold the deterministic grammar and laws.** The search is pure and seed-reproducible *given a fixed oracle* (`PaletteSearch.hs:276–282`); the `SplitTree` is golden-verified once. Once a value head is learned, training is non-deterministic and the produced trees will differ — so what to preserve is the **deterministic grammar and the algebraic laws** (PUCT, persistent backup, move invertibility, seed-reproducibility of a run), not literal determinism of future outputs. Hold that grammar as the learned value head and preference loop land, so every projection the user touches stays provable against the spec.

**Bottom line:** the Go architecture maps cleanly onto a *compute-bounded, option-generating* search whose **value function is meant to become the human**, and the three radices are one honest projection of one 256-leaf tree. The blueprint and contracts exist (Haskell specs + Swift goldens); the value head, the on-device search runner, the keep/swipe → Bradley-Terry loop, the σ-pair editor constraint, and the radix→genome wiring are the unbuilt keystone.

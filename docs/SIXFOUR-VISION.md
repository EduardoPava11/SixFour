# SixFour — Unifying Vision

**Status:** Vision / architecture (design-only; the look-NN is designed, not trained). The doc the others hang off.
**Date:** 2026-06-01.

> **Canonical orientation (2026-06-05).** This doc owns the **narrative** (what SixFour is and
> why); `SIXFOUR-ARCHITECTURE-MAP.md` owns the **built / design / missing ledger** (current
> state, test counts, what's wired). README / CLAUDE.md / SETUP.md / APP-MAP.md describe stable
> structure and **defer here for status** — they must not restate a drifting "current status"
> line. If status disagrees across docs, this pair wins.

---

## 0. The vision in one line

> **One cube, projected honestly onto touchable surfaces. The NN proposes, a search generates the options, the user picks — and the spec proves every projection.**

SixFour produces exactly one object: the **64×64×64 GIF cube** of 256-colour frames. Everything else is a *projection* of that cube onto a surface a phone can show and a finger can touch (2D / 3D), and the controls **are** the act of projecting.

- **Atom:** the cell (one GIF pixel = one unit — GRID).
- **Verb:** projection (3D→2D cloud/cube; tree→plane treemap/grid; 256-index→N wheels address-picker).
- **Law:** honesty, *proven by the spec* — no view shows a dimension the data lacks, fakes distance, or relabels an address bit as a feature; no embedding (t-SNE/UMAP/SOM); distance-true only orthographic; goldens pin the math.

---

## 1. The pipeline (GIF → GIF)

```
capture ─▶ per-frame palettes ─▶  NN collapse  ─▶   SEARCH      ─▶  DPP gallery ─▶ user swipe ─▶ preference
(64×64×64) (256/frame, max-LAB   (→ ONE global    (generate a       (pick k         (choose one)   (keep/swipe →
 DONE       diversity) DONE        palette) SPEC'D  diverse set)      diverse)                       Bradley-Terry)
                                   (untrained)      ◀── KEYSTONE      SPEC'D
                                                        GAP
```

- **Capture (DONE):** 64-frame × 64×64 → per-frame 256-colour palettes (max-LAB-diversity, population-significant). The well-built input.
- **NN = subject-matter expert (SPEC'D, untrained):** collapses the 64 per-frame palettes (permutation-invariant sum-pool of OKLab Gaussian tokens) into ONE global ~384-DOF σ-pair Haar palette for the 64³ GIF. `Spec.LookNet*` / `Spec.Collapse` / `Spec.Bures` (barycenter = the *training* target, not an on-device invariant).
- **Search (THE KEYSTONE GAP — see §2):** turns the NN's proposal into a *candidate set* by balancing exploitation (the NN's pick) ↔ exploration (diversify), AlphaGo/KataGo-style. **This does not exist yet.**
- **DPP gallery (SPEC'D):** `Preference.greedyGallery` selects k≈3–5 *diverse* options (quality-weighted RBF/Bures kernel over OKLab/Haar embeddings) from the candidate set.
- **User swipe → preference (partly spec'd):** keep/swipe feeds a Bradley-Terry utility; keep = refinement anchor, swipe = novelty signal.

---

## 2. Have it vs. build it (honest, from the adversarial review)

**Have it (spec'd + landed):**
- NN substrate L3–L6 (Encoder→Core→Decoder→σ-pair reconstruct), 384-DOF Haar palette — *designed, contract-pinned*.
- `Preference.greedyGallery` — the diverse-option **selection** (real quality-diversity: DPP log-det).
- Beauty `B(G)` (Ou-Luo pair harmony) + diversity `Cov(G)` (DPP log-det) metrics.
- `PairTree` lossless Haar folds (round-trip golden) — the reversible "move" grammar.
- 16²/4⁴/2⁸ ↔ OKLab honest mapping (`AddressPicker`, `CloudProjection`, `GridAxis`).
- Zero-dep / spec-first contract.

**Build it (the keystone gaps — these are the real work):**
1. **THE SEARCH.** `Collapse` + `Preference` are *selection*, not *search*: there is **no** MCTS tree, playout grammar, value backup, exploration schedule, or halting. Without it the gallery has no candidate set to diversify. **This is the keystone** — spec + golden-gate a search (root = farthest-point collapse; playout = sample the policy; balance exploit↔explore; leaves → gallery).
2. **A value / policy head.** The decoder emits a *point estimate*, not a distribution or policy log-probs, and beauty/diversity are post-hoc functions, not neural predictions. Spec the value head (outputs, training path, σ-equivariance, goldens).
3. **The candidate-generation grammar.** Decide search space: continuous 384-DOF Haar (NN-native, differentiable) vs. discrete fold sequences (user-faithful). Convert via `PairTree.analyze` on a leaf.
4. **Train + deploy.** MLX trainer (self-play) → hand-written Swift forward pass (L3–L6, zero-dep) verified byte-for-bit vs. Haskell goldens. The search is a Mac-side / off-device personalization feature, not necessarily shipped inference.
5. **Preference loop.** On-device Bradley-Terry update from keep/swipe; cold-start (warm-start from population vs. uniform); margin stability for index re-mapping (`γ_pix`).

> Every "hyperparameter" in the raw synthesis (temperatures, playout counts, reward weights) was **invented** — none are spec'd. They are tuning decisions for *after* the search exists, not facts.

---

## 3. The dimensional views ARE the search space + the option UI

The 16²/4⁴/2⁸ branchings are radix views of **one** median-cut `SplitTree` (factor^depth = 256), each split = the *widest of L/a/b* at a position. This single structure plays **two roles**:
- **Search coordinate system:** a search "state" is a subtree node (binary path / n-ary address); an "action" is a digit pick / fold that refines an `axis@pos` region of OKLab. The branchings give the search a *navigable, honest* state space.
- **Option-navigation UI:** the user browses the surfaced options through the same projections — the 2⁸ spine (AddressPicker breadcrumb), the 4⁴ drill zones, the 16² grid snapshot, the OKLab cloud. Distance-true (orthographic) or rank-based (grid); **addressing ≠ features** (the exponent is tree depth, not dimensionality).

This is the vision made literal: the thing the search walks and the thing the user navigates are the *same honest projection* of the one cube.

---

## 4. Phased plan (spec-first) & open decisions

**Phases:** (1) spec the value/policy head on `LookNet` (+ goldens); (2) **spec the search** — tree, playout grammar (lossless Haar folds), exploit↔explore, halting, leaves→gallery (+ golden traces); (3) integrate `Preference` utility (Bradley-Terry + DPP) end-to-end; (4) MLX train + hand-written Swift forward pass (golden-verified); (5) on-device preference loop + measure on iPhone 17 Pro.

**Open decisions (yours to make):** search space (Haar-continuous vs fold-discrete); value head (auxiliary vs read-from-core); beauty metric (deterministic vs learned); gallery size k (3 vs 10 — measure engagement); barycenter as training-target-only (recommended) vs constraint; preference cold-start (warm vs uniform) and cross-user transfer.

---

## 5. What this means for "pushing the UI/UX"
The UX surfaces (cloud, address-picker, treemap, grid, voxel-cube) are the **option-navigation layer** of this vision — they're how the user *sees and picks* among the search's options. So UX work and the NN/search work converge: every new projection or cross-view link (e.g. shared `brushedIndex` across all views) is also a richer way to browse the eventual gallery. Build the projections now; they pay off the moment the search exists to fill them.

---

## References
- UI/UX map (dimensions-first, 20 fps) `docs/SIXFOUR-UIUX-DIMENSIONAL-MAP.md` · GRID `docs/SIXFOUR-DESIGN-LANGUAGE.md` · pixelation `docs/SIXFOUR-TOTAL-PIXELATION.md` (glass retired; `docs/archive/SIXFOUR-GLASS-LANGUAGE.md`) · high-D `docs/SIXFOUR-HIGHDIM-UIUX.md` · palette/volume `docs/palette-explorer-2d-3d-4d-design.md` (umbrella; cube shelved → `docs/archive/SIXFOUR-VOXEL-CUBE.md`).
- Look-NN: `docs/GIFA-GIFB-COLLAPSE-REDESIGN.md` (forward brief), `docs/L-NN-MASTER-DESIGN.md`, `docs/L-NN-FUNCTION-DESIGN.md` (research lineage in `docs/archive/`); `spec/src/SixFour/Spec/{LookNet*,Collapse,Bures,Preference,Diversity,PairTree,SplitTree,AddressPicker,CloudProjection,GridAxis}.hs`.
- Precedent: AlphaGo/AlphaZero (policy+value+MCTS), KataGo (uncertainty-weighted playouts, optimistic policy), MAP-Elites / DPP quality-diversity.

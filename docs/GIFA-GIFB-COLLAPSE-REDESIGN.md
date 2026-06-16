> **Status/built-state:** see [docs/STATUS.md](STATUS.md) (canonical, gated by `scripts/verify-doc-claims.sh`). This document is design rationale, not a status ledger.

# GIFA → GIFB collapse — redesign brief (the per-frame → global palette move)

> **Status: OPEN DESIGN BRIEF (2026-06-05).** This is the forward design surface for the
> look-NN. It **frames the problem**; it does not yet fix the mechanic. The decision method
> is research-driven (survey the literature → map to a program → let the math dictate), not
> menu-of-options. The prior L-NN prose lineage (`archive/L-NN-ATOM-DESIGN`,
> `archive/L-NN-PRODUCT-ABSTRACTION`, `archive/L-NN-RESEARCH-AND-WORKFLOW`,
> `archive/PALETTE-LOOM-INTERACTION`) is **input** to this brief, not authority.
> Living references: `L-NN-MASTER-DESIGN.md` (math design-of-record),
> `L-NN-FUNCTION-DESIGN.md` (user-function view), `spec/LOOK_NN.md` / `spec/LOOKNET_LAYERS.md`
> / `spec/NN_SPACE_NOTES.md` (the typed contract), and `Spec.*.hs` (the only executable truth).

## 1. The gap this brief exists to close

The app extracts a **per-frame** 256-colour palette per frame (`Spec/StageA.hs`) — call the
result **GIFA**. The product promise is a single **global** 256-colour palette over the whole
64³ cube — **GIFB**. Today **GIFB is never produced**: `s4_global_collapse` exists in Zig and is
wrapped in Swift (`SixFourNative.globalCollapse`) but has **zero callers**; `DeterministicRenderer`
ships per-frame palettes only (see `docs/STATUS.md` for built/design/missing; lineage `docs/archive/SIXFOUR-ARCHITECTURE-MAP.md` §4, build-order step 1).

The collapse — *how 64 per-frame palettes become one global palette* — is the unbuilt keystone.
Everything else (the σ-pair genome, the Haar tree, the dither) is downstream of it.

## 2. The framing: collapse as an AlphaGo-style move + value

The redesign reframes the collapse the way AlphaGo reframed Go: **enumerate the moves, let an NN
score the winning probability, search over the scored moves, let the human pick.** Mapping:

| AlphaGo | SixFour collapse |
|---|---|
| Board position | The current set of per-frame palettes (GIFA) + any partial global palette |
| Legal moves | The ways per-frame palette mass can be **merged / pruned / migrated** into the global 256 |
| Policy (move priors) | The look-NN proposing which merges are worth trying (`E/R/D` core) |
| Value (win probability) | `PaletteValue` scoring a candidate global palette's **quality** (beauty + fidelity + coverage) |
| Tree search (MCTS) | `Spec.PaletteSearch` — generate candidate global palettes, score, expand the good ones |
| The move played | `s4_global_collapse` applied to realise the chosen global palette → GIFB |
| Human review | The Review UI: the user picks among scored candidates |

This is **not new architecture** — it is connecting parts the repo already has but left
disconnected:

- **Move operator** — `s4_global_collapse` (Zig, owned, byte-exact) and its Swift wrapper.
- **Search keystone** — `Spec.PaletteSearch` (GHCi-validated; `SIXFOUR-VISION.md`:
  "SEARCH generates options, NN proposes, value-head scores, user picks").
- **Value head** — `PaletteValue` (float scorer).
- **Genome** — the 384-DOF σ-pair decoder (`Spec/SigmaPairHead.hs`) the chosen move reconstructs to.

## 3. The open questions (to be answered by research, then spec)

These are deliberately **unanswered** here — each is a research+spec task, not a pick:

1. **Move set.** What is the legal-move alphabet of the collapse? (pairwise merge, mass-transport
   reassignment, σ-balanced subtree fusion, prune-and-resplit?) Survey OT barycenter / k-means
   merge / palette-quantization-under-motion literature before fixing it.

   > **Update 2026-06-15 — first candidate move spec'd.** The OT-barycenter survey is underway
   > (verified 2024–2026 literature sweep; deep-research review this session). The first executable
   > candidate now lives in the spec:
   > **`Spec.Barycenter.freeSupportBarycenter`** — a free-support Wasserstein barycenter
   > (Cuturi–Doucet 2014; the 2025 particle-flow framing) built on the new **`Spec.Sinkhorn`**
   > entropic-OT kernel. It is a *mass-transport reassignment* move: seeded from the maximin pick,
   > the global atoms flow to the OT-average of the 64 per-frame palettes. Proven gamut-closed (stays
   > in the inputs' convex hull), support-size-preserving, and translation-equivariant
   > (`Properties.Barycenter`). This does NOT fix the alphabet — it adds ONE transport-based move to
   > score against maximin via `PaletteOracle` / `PaletteSearch`. The byte-exact shipped collapse
   > remains `Collapse.globalCollapseQ16` until a move is settled.
2. **Value target.** What does the value head actually score? In self-supervised palette land there
   is **no label `y`** (open Q flagged in the GRAM mapping note). Candidate signals: Bures fidelity,
   coverage (the spec metric, *not* MSE — see `sixfour-diversity-spec`), Ou-Luo pair beauty,
   flicker variance. Which combination, and is it learned or fixed?

   > **Update 2026-06-15.** A tighter fidelity signal is now available: **`Loss.fidelityLossSinkhorn`**
   > (debiased Sinkhorn divergence, `Spec.Sinkhorn`) keeps the palette + capture as discrete measures
   > instead of collapsing them to one moment-matched Gaussian (the Bures baseline), so it penalises a
   > palette that matches mean+spread yet misses a colour mode — a candidate value-target component.
3. **Search ↔ UI coupling.** How does the user experience the search? GIFB is the product, but the
   candidates are the *choice*. The UI/UX redesign and the collapse mechanic must be co-designed
   (this brief's reason for existing) — see `SIXFOUR-VISION.md` and the GRID design language.
4. **Where it runs.** Collapse + search on-device vs Mac-trained priors only; the integer-floor
   Zig core is the cross-device byte-exact substrate (`sixfour-zig-quantized-core`).

## 4. What "done" looks like

- `s4_global_collapse` has a caller on the render path; the app **emits GIFB**.
- The value head and search are spec'd (Haskell laws + golden vectors) before any Swift/Metal port.
- The UI exposes scored global-palette candidates for the user to pick.
- This brief is superseded by a concrete `L-NN-MASTER-DESIGN.md` revision once the move set and
  value target are settled by research.

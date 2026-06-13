# SixFour — LAB-space CHOICES → algorithms → gestures

The menu of perceptual color choices a user makes over the 16 RGBT frame-groups to build
the global 256-colour palette, each grounded in a cited algorithm and bound to ONE gesture
on the pixelated cell grid. Distilled from the deep-research report + an adversarial
elucidate→critique→architecture workflow (2026-06-13). Companion to
[`SIXFOUR-GESTURE-GRID-TOOLS.md`](SIXFOUR-GESTURE-GRID-TOOLS.md) and
[`SIXFOUR-ACTS-WORKFLOW.md`](SIXFOUR-ACTS-WORKFLOW.md); cite, don't duplicate.

## The surviving menu (post-critique, ranked)

| # | Choice | What the user decides | Algorithm · space | Gesture | New spec |
|---|--------|----------------------|-------------------|---------|----------|
| 1 | **Group select** (8.5) | WHICH of the 16 RGBT groups seed the global collapse (+ see each group's 4 frames as R/G/B/T *motion*) | pool only the picked groups' colours → maximin · OKLab | **clean tap** on a rail column | `Spec.GroupRGBT` |
| 2 | **Coverage ↔ fidelity** (7.5) | palette spreads to cover the whole gamut (diverse) vs pulls in to minimise error (faithful) | interpolate maximin (Gonzalez coverage floor) ↔ k-means (MSE over pooled entries) · OKLab | **horizontal drag** on a dedicated strip | `Spec.CoverageFidelity` |
| 3 | **Lightness band** (7.5) | which L window the 256 slots are *spent* on (finer gradation there) | weighted maximin tilted to an L window · OKLab L handle | **two-finger vertical drag** on Palette16 | (part of `GroupRGBT` weight) |
| 4 | **Chroma push** (7.4) | how saturated — radial scale about the neutral axis, hue+L frozen | `C=√(a²+b²)` multiply (generator-space) · OKLab | **pinch** | `Spec.ChromaPush` |
| 5 | **Opponent quadrant** (6.5) | global warm/cool/teal-orange bias `q=(qa,qb)` | constant (a,b) bias on chrominance · OKLab; retires the 5-case `LookVariant` | **directional drag** | `Spec.OpponentBias` |
| 6 | **Split-tone hue** (6.5, conditional) | differential hue shift between shadows/highlights | PER-ZONE differential rotate only · OKLab | **two-finger rotate** | `Spec.SplitTone` |

**DROPPED:** *global uniform hue-rotate* — a chroma+L-locked isometry, zero coverage/diversity
DOF, an Instagram-tier filter (keep only the per-zone split-tone, #6). *group-merge-weight as
a standalone* — folded into #1 as its continuous generalization (`w ∈ 0..W`), since both hit
the identical pooled-candidate seam.

> **The honest correction the critique forced on "see the 4 as R/G/B/T":** mapping the 4
> frames of a group to literal R/G/B/T colour *channels* and "weighting the 4" is a CATEGORY
> ERROR — the 4⁴ R/G/B/T quadrants are leaf-space tree nodes, not the 4 captured frames. The
> real decision is **which groups** feed the collapse (#1); the "see as 4" is a **read-only
> QuartetDelta motion overlay**, not a slider. Your vision survives — made honest.

## Architecture (the 4 resolved gaps)

1. **MERGE — re-quantize the weighted pool with the existing maximin; NO Wasserstein
   barycenter.** Per-group weight = integer **replication count** in the concat pool (the one
   weighting a population-free pool can express). Barycenter rejected: Sinkhorn = 10–100× cost,
   iterative, needs a zero-dep hand-port that doesn't exist, and *invents out-of-gamut colour*
   — breaking gamut-closure and "the grid IS the feedback." Maximin keeps every leaf an actual
   captured colour, so a weight/coverage drag repopulates cells with colours the user *saw*.
   *(Fidelity endpoint stated honestly: MSE-minimal over the **pooled candidate set**, not the
   per-pixel Lloyd-Max scene ceiling — the pool dropped pixel populations at `concat`.)*
2. **TWO-SPACE — OKLab for ALL gesturable handles (L/a/b/C/h) AND `Spec.Coverage` occupancy.**
   *Correction to the earlier framing:* coverage occupancy is **metric-free** (counting distinct
   16³ voxels), so it stays OKLab — moving it to ΔE was a category error. **CIEDE2000 is a NEW
   verdict-layer readout only** (per-group "which covers better", 16 summary numbers), never in
   the collapse inner loop; build only when a "better" affordance ships.
3. **CELL LAYOUT — `GroupRail`: a 16-col × 4-row cell band below `Field64` in `.browsing`**
   (columns = the 16 groups, rows = the R/G/B/T frame roles) — the patent's time×group array
   (US 9,552,520), so a group reads as a *unit*. Horizontal swipe on `Field64` scrubs the burst
   as 16 groups; tap a rail column = pick that group.
4. **GESTURE PARTITION — needs `Spec.PaletteGesture` (provable, not asserted).** The critiques
   found real collisions (every single-finger verb on Palette16 is already taken; coverage-drag
   collides with cloud yaw; the 2-finger escapes are unproven on 64-pt cells). The partition is
   `(region × recognizer-class × axis × latch)` with `lawPartition` (exhaustive ⟹ ≤1 gesture per
   event), `lawDragDecodeRoundTrip` (2-D drag → 3-D OKLab δ), and `lawSigmaLocked` (chroma-push /
   hue / bias are generator-space ops, NOT the additive `LeafOverride` slot).

## The load-bearing truth

**The meaningful half is currently UNWIRED: `LadderExport.flatGlobalLeaves` pools all 64
frames — the picks change nothing.** So `Spec.GroupRGBT` (group → weighted pool → collapse) is
the FOUNDATION; until it lands, every choice above is cosmetic. It is also the one new spec that
unblocks both #1 (group select) and #3 (lightness band, as a weight).

## Build plan (spec-first; into Act III `.browsing`)

1. **`Spec.GroupRGBT`** — `64 frames → 16 RGBT quads (frames[4g..4g+3]) → integer-replication-
   weighted pool → globalCollapseQ16`; thread into `flatGlobalLeaves(palettesPerFrame:weights:)`.
   Law: **weight-1-everywhere ≡ today's `globalCollapseQ16`** (backward-compat golden) + monotone
   weight→survival. *Makes the picks real.*
2. **`Spec.PaletteGesture`** — the partition + the three laws above (golden-gated).
3. **`GroupRail` 16×4 placement** in `.browsing` + **Swift `QuartetDelta` port** (Haskell golden
   exists, no twin) for the per-group motion-heat read.
4. Then the choice ops, each spec-first + gated: `CoverageFidelity`, `ChromaPush` (generator-space
   multiply, σ mirrors free), `OpponentBias` (retire `LookVariant`), `SplitTone`.

## Open decisions

- **Scope:** ship #1 + #2 first (the load-bearing pair — *which colours* + *coverage↔fidelity*),
  defer #3–#6? Or the full menu?
- **Gesture channels:** the 2-finger / pinch / rotate escapes need an on-device feel test (no
  camera in sim) — accept prototype-then-tune.
- **CIEDE2000 verdict layer:** build the "which group covers better" readout now, or defer until
  the choices exist?

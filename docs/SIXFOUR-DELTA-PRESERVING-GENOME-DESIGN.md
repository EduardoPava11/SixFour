# SixFour — Delta-Preserving Genome + Merkle Gene Tree

**Status:** design (2026-06-18), from a 6-agent research+critic workflow. Branch
`feat/delta-preserving-genome`. Answers the user ask: make the A/B genome
preserve relative color deltas (intra-frame + inter-frame) toward beauty, and
link the 16²/4⁴/2⁸ widgets to the genes "like a merkle tree." **Is it possible?
YES** — ~80% of the substrate is already proven in `spec/`; the corrections
below bound what is real vs net-new.

## The problem (verified)
The picked GIF degraded into noise by ~round 16. **Root cause (critic-confirmed):**
the A/B pair was re-centered each round on `chosenLookPalettes` — the *lossy*
sRGB8-round-tripped + re-quantized chosen look — so lossy round-trips compounded.
Reverted in `614c773` (propose from the fixed original capture). NOT the cause:
`PersonalTaste.leafTint` (it is hard-clamped ±8192 Q16 = ±0.125 OKLab) and
`GenomePair` fixed-step (applied once, doesn't self-accumulate). The "A/B barely
changes per round" is a *separate* symptom: the fixed ±1024 step (~JND) never
annealed + `DivergenceSchedule` never wired.

## The architecture: one store, three views, one annealed move, two ascent channels
- **STORE = the reversible integer Haar (`PairTreeFixed`, 768-DOF / 256 leaves).**
  Every parent = exact invertible fold of its children (`liftPair`: parent =
  y + floorHalf(x−y), detail d = x−y; `reconstruct∘analyze = id` EXACT,
  `lawReconstructAnalyzeRoundTripExact`). This IS the color-merkle: parent gene =
  deterministic *invertible* function of children (proves integrity AND
  reconstructs — better than a SHA fold).
- **THREE VIEWS = three cut-levels of that one tree** (`SplitTree.lawCollapsePreservesLeaves`
  + `lawBranchingArithmetic` prove 16²=4⁴=2⁸=256): 16² SEE = leaf-genes by rank;
  4⁴ CONTROL = the 16 Quad4 opponent nodes (mean, ΔR/G, ΔB/T — the RGBT brush);
  2⁸ LEARN = the 128 σ-pair generators. Each widget LINKS to the node-genes at its
  level (`lawWidgetGeneIsNodeGene`, new). Edits propagate delta-preservingly: an
  edit re-folds UP (parents re-derive) and DOWN, scoped (`LeafOverride.lawSigmaOverrideScopedToGenerator`:
  generator i touches only leaves 2i, 2i+1) and additive (`lawSigmaOverrideAdditive`,
  no compounding) — which is exactly what kills cumulative drift.
- **ONE ANNEALED MOVE** replaces both degraders. Magnitude annealed by a schedule
  (wide early → floored late), cumulative displacement hard-capped (project back
  into the ball each round).
- **TWO ASCENT CHANNELS (the AlphaGo split):** canonical Ou-Luo two-color harmony
  as the warm prior (move *shape*) + learned θ (Bradley-Terry, `AtlasTrainer`) as
  the harmony-vs-diversity *weight*. A and B = two moves both ascending the beauty
  objective, separated by the divergence schedule (A explore, B exploit).

## CRITIC CORRECTIONS (do not skip)
1. **No "exact rotation."** A 3-shear integer rotation is reversible but NOT
   distance-preserving (drifts ~1 LSB/shear). The truly-exact integer-lattice
   isometries are the *discrete subgroup*: signed-axis permutations/sign-flips of
   (a,b[,L]) + integer translation t (σ is the proven instance,
   `lawSigmaEuclideanIsometry` PairTree.hs:280). So either v1 move = that exact
   discrete set + bounded translation (no-tolerance, repo-clean), OR a continuous
   rotation that is explicitly ε-tolerance-gated. **Open decision below.**
2. **Beauty coefficients are net-new research.** The ratio objective B = U/V
   (Birkhoff, `BEAUTY_FINDINGS.md` proves ratio ≠ additive on ~20% of scenes) +
   the unity-preservation penalty (maximin drops complements in ~1/3 of scenes)
   ARE in-repo. The specific Ou-Luo HC/HL/HH closed-form coefficients are NOT
   (and are CIELAB-calibrated; repo is OKLab). Land the ratio + unity first;
   defer the coefficient port behind a cited-source gate + CIELAB↔OKLab decision.
3. **Gene-store migration is real work.** Shipped widgets read BranchedPalette /
   median-cut `SplitTree`, NOT the dyadic `PairTreeFixed`. Stable dyadic addresses
   are exactly what we want, but swapping the render tree moves which colors land
   in which cell — a migration phase, not "almost no new math."
4. **Schedule naming:** `DivergenceSchedule.divergence(n)` already means the
   policy:value mix-ratio gap — add a sibling `Spec.MoveRadiusSchedule` (same decay
   shape, reuse `lawDivergenceMonotone`/`lawDivergenceBoundedBelow`) for the
   geometric radius; don't overload it.

## Build plan (spec-first; cabal test gates each)
- **P0 — stop the bleeding (done / no spec):** revert the lossy re-center (`614c773`);
  next: thread `abPickCount` as n + scale the move by a schedule; cap cumulative
  displacement.
- **P1 — `Spec.IsometryMove`:** the delta-preserving move over the EXACT discrete
  subgroup (decision-gated) + bounded translation; `lawMovePreservesPairwiseDelta`
  (EXACT only on the discrete subgroup), `lawIsometryReversible`.
- **P2 — `Spec.MoveRadiusSchedule` + wire it:** geometric radius + cumulative cap;
  retire `GenomePair.stepFor` fixed-1024; wire `DivergenceSchedule` to the A/B gap.
- **P3 — `Spec.GeneMerkle`:** name `Gene = (mean, detail)` per node = the
  `analyzeFixed` fold; `viewGenes` per branching; scoped additive `editAt`; map the
  three cuts to the three widgets. Includes the BranchedPalette→dyadic migration +
  cross-radix authority decision.
- **P4 — exact beauty:** ratio U/V + unity-preservation first (in-repo); Ou-Luo
  coefficients deferred behind a source gate.
- **P5 — retire `leafTint`; θ selects the move DIRECTION** (once/round via
  `applySigmaOverride`, σ-locked, annealed); A/B = two moves descending B, separated
  by the schedule; pick = Bradley-Terry reward.

## Open decisions (genuinely the owner's — gate P1/P3/P4)
1. **Move group v1:** exact discrete subgroup (sign-flips/swaps + integer t —
   no-tolerance, repo-clean, smaller set) **vs** continuous rotation (more
   expressive, ε-tolerance-gated). *Recommend exact discrete for v1.*
2. **Canon (BLOCKING):** are shipped candidates the 128-generator σ-pair genome
   (all the cited laws bind) **or** the 256-free-leaf maximin (`PersonalTaste.swift:13-18`
   says maximin)? The merkle/delta story assumes σ-pair. *Recommend migrate to σ-pair.*
3. **Beauty objective:** adopt ratio U/V (re-derive `lawRewardLinear`) **vs** keep
   the linear sum (accept ~20% ranking disagreement).
4. Cross-radix edit authority (which view is authoritative; others read-only),
   color space for Ou-Luo (CIELAB eval vs OKLab re-fit), beauty hard-constraint vs
   soft-floor — resolvable as P3/P4 land.

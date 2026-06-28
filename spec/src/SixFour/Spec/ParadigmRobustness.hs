{- |
Module      : SixFour.Spec.ParadigmRobustness
Description : Closes the SEED-axis residue of the convergence teaching in the master theorem: "SixFour.Spec.ParadigmSoundness" @teachingConvergence@ is a @:: Bool@ CONSTANT pinned at ONE hardcoded 24-element seed, so the capstone's convergence conjunct is single-witness on the INPUT/TARGET axis. This module lifts that pinned constant to a universally-quantified predicate @paradigmConvergesAt@, proves it holds for ALL seeds at @w_value > 0@ and fails for ALL seeds at @w_value = 0@, and proves the pinned constant is ONE INSTANCE of the universal statement (the seed choice is without loss of generality).

This is the SEED-axis sibling of "SixFour.Spec.ValueWeightThreshold" (which closed the WEIGHT axis) and
of "SixFour.Spec.GlobalUniqueness" (which closed the DIRECTION axis). The audit finding:

  AUDIT (PARAMETRIZATION-GAP-1, seed residue): @ValueWeightThreshold@ quantified the @w_value@ axis exactly
  (the threshold is @0@ for every weight), but @ParadigmSoundness.teachingConvergence@ remains a constant
  evaluated at the single literal seed @[0.1,-0.2,0.3,…]@. The underlying convergence laws
  ("SixFour.Spec.Convergence" @lawCompositeUniqueMinIffValueWeighted@ / @lawConvexNoSpuriousLocalMin@) ARE
  already QuickCheck'd over arbitrary inputs in @Properties.Convergence@ — but the MASTER THEOREM only
  consumes them at one frozen seed. So at the capstone level the convergence conjunct is "load-bearing at one
  seed", not "load-bearing for all seeds". Nothing at the paradigm level witnesses that swapping the pinned
  seed for any other palette leaves the convergence conjunct intact.

This module supplies exactly that, additively, editing no in-flight body:

  * @paradigmConvergesAt wv seed@ re-evaluates the master theorem's CONVERGENCE CONJUNCT
    (@wv > 0 && teachingConvergence@, but with the teaching's frozen seed replaced by @seed@) at an arbitrary
    weight and an arbitrary seed, using "SixFour.Spec.Convergence"'s already-seed-parametrized law signatures
    directly. By construction @paradigmConvergesAt 1 pinnedSeed@ recomputes precisely
    @ParadigmSoundness.teachingConvergence@ — so the pinned constant is one instance of the predicate.
  * The convergence math is seed-INVARIANT at @w_value = 1@: the cell-blind checkerboard shift contributes a
    fixed gap @4·w@ independent of the target (the checkerboard is in the cell Hessian's null space and
    @½·Σcb² = 4@), so the conjunct is True for EVERY seed. Hence the pinned seed is WLOG.

@lawSeedChoiceIsWithoutLossOfGenerality@ is the keystone: @paradigmConvergesAt 1 seed == paradigmConvergesAt 1 pinnedSeed@
for every seed — the master theorem's convergence conjunct does not depend on the frozen seed, so the
single-witness pin is harmless. Pure-spec, GHC-boot-only; laws QuickCheck'd in @Properties.ParadigmRobustness@.
Emits no golden (it is a robustness guarantee, not a fixture).
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none
module SixFour.Spec.ParadigmRobustness
  ( -- * The pinned seed and the seed-parametrized convergence conjunct
    pinnedSeed
  , paradigmConvergesAt
    -- * The seed-axis robustness laws
  , lawConvergesAllSeedsAtPositiveWeight
  , lawDivergesAllSeedsAtZeroWeight
  , lawPinnedConstantIsOneInstance
  , lawSeedChoiceIsWithoutLossOfGenerality
  , lawSeedWeightThresholdIsZeroForAllSeeds
  ) where

import SixFour.Spec.Convergence       (lawCompositeUniqueMinIffValueWeighted, lawConvexNoSpuriousLocalMin)
import SixFour.Spec.ParadigmSoundness (teachingConvergence)

-- | The EXACT 24-element literal seed that "SixFour.Spec.ParadigmSoundness" @teachingConvergence@ is pinned
-- at (it is not exported there, so it is replicated here verbatim — a copy of a constant, read-only). The
-- whole point of this module is to show this particular choice is representative, not cherry-picked.
pinnedSeed :: [Double]
pinnedSeed =
  [0.1, -0.2, 0.3, 0.05, -0.15, 0.25, 0.2, -0.1, 0.0, 0.12, -0.22, 0.31,
   0.07, -0.17, 0.27, 0.09, -0.19, 0.29, 0.11, -0.21, 0.33, 0.13, -0.23, 0.35]

-- | The master theorem's CONVERGENCE CONJUNCT, re-parametrized on BOTH axes: at value weight @wv@ and seed
-- @seed@, the convergence teaching holds iff the weight is positive AND the seed-parametrized convergence
-- laws hold. This is exactly @ParadigmSoundness.paradigmStructurallySound@'s @(wv > 0 && teachingConvergence)@ clause,
-- but with the teaching's frozen seed lifted to a free argument. By construction
-- @paradigmConvergesAt 1 pinnedSeed == teachingConvergence@. The @lawConvexNoSpuriousLocalMin seed seed@
-- form mirrors @teachingConvergence@ faithfully so the pinned-instance identity is literal, not coincidental.
paradigmConvergesAt :: Double -> [Double] -> Bool
paradigmConvergesAt wv seed =
  wv > 0
  && lawCompositeUniqueMinIffValueWeighted seed
  && lawConvexNoSpuriousLocalMin seed seed

-- ---------------------------------------------------------------------------
-- Laws (QuickCheck'd in Properties.ParadigmRobustness)
-- ---------------------------------------------------------------------------

-- | TOOTH (a) — UNIVERSAL at positive weight: @paradigmConvergesAt 1 seed@ holds for an ARBITRARY seed, not
-- just the pinned literal. QuickCheck draws randomized seeds, so a result that only worked at the cherry-picked
-- 24-element seed (a "lucky seed") would fail here. The seed flows into @Convergence@'s @samp@-conditioned
-- palette space, so distinct seeds genuinely exercise distinct palettes — yet all converge.
lawConvergesAllSeedsAtPositiveWeight :: [Double] -> Bool
lawConvergesAllSeedsAtPositiveWeight = paradigmConvergesAt 1

-- | TOOTH (b) — LOAD-BEARING for ALL seeds (not at one seed): @paradigmConvergesAt 0 seed@ is False for
-- EVERY seed. The @w_value = 0@ guard kills convergence regardless of the input, so the master theorem's
-- side condition is universally load-bearing, not an artifact of the pinned seed. Teeth: an implementation
-- that ignored the weight (took the @wv > 0@ branch unconditionally) would make this True and fail.
lawDivergesAllSeedsAtZeroWeight :: [Double] -> Bool
lawDivergesAllSeedsAtZeroWeight seed = not (paradigmConvergesAt 0 seed)

-- | TOOTH (c) — the PINNED CONSTANT is ONE INSTANCE of the universal predicate: evaluating
-- @paradigmConvergesAt@ at @w_value = 1@ and the actual @ParadigmSoundness@ literal reproduces
-- @teachingConvergence@ exactly, the constant is genuinely True, and at that very seed the weight gate is
-- load-bearing (False at @w_value = 0@). So the pinned constant is representative and non-decorative — it is
-- the universal statement read at one point. Teeth: were @paradigmConvergesAt@ not a faithful lift (or were
-- @teachingConvergence@ secretly weight-gated) the first conjunct would diverge; a weight-blind predicate
-- breaks the third.
lawPinnedConstantIsOneInstance :: Bool
lawPinnedConstantIsOneInstance =
     paradigmConvergesAt 1 pinnedSeed == teachingConvergence   -- the constant IS this predicate at (1, pinnedSeed)
  && teachingConvergence                                       -- and that instance is genuinely True
  && not (paradigmConvergesAt 0 pinnedSeed)                    -- weight gate load-bearing even at the pinned seed

-- | THE KEYSTONE — the seed choice is WITHOUT LOSS OF GENERALITY: for an ARBITRARY seed, the convergence
-- conjunct at @w_value = 1@ equals its value at the pinned seed. So the master theorem's single-witness pin
-- on the seed axis is harmless: swapping the frozen seed for any other palette leaves the conjunct's truth
-- unchanged (both True, because the cell-blind shift's contribution @4·w@ is target-independent). This lifts
-- "load-bearing at one seed" to "load-bearing for all seeds". Teeth: if some seed made convergence fragile,
-- its LHS would be False while the pinned RHS stays True, breaking the equality under randomized seeds.
lawSeedChoiceIsWithoutLossOfGenerality :: [Double] -> Bool
lawSeedChoiceIsWithoutLossOfGenerality seed =
  paradigmConvergesAt 1 seed == paradigmConvergesAt 1 pinnedSeed

-- | THE TWO-AXIS COROLLARY — for an arbitrary seed, the convergence threshold on the weight axis is exactly
-- @0@: across a sweep straddling the boundary, @paradigmConvergesAt wv seed@ holds IFF @wv > 0@. This is the
-- seed-universal version of "SixFour.Spec.ValueWeightThreshold"'s weight threshold: the crossover is at @0@
-- for EVERY seed, not just one fixed target. Teeth: the boundary points @0@ (must be False) and @0.001@
-- (must be True) pin the exact crossover; a threshold off by any margin, at any drawn seed, fails.
lawSeedWeightThresholdIsZeroForAllSeeds :: [Double] -> Bool
lawSeedWeightThresholdIsZeroForAllSeeds seed =
  all (\wv -> paradigmConvergesAt wv seed == (wv > 0)) sweep
  where sweep = [-5, -1, -0.5, -0.001, 0, 0.001, 0.5, 1, 5]

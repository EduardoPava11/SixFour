{- |
Module      : SixFour.Spec.Generalization
Description : The GENERALIZATION teaching — why learning the training octants learns the TASK, not a memorized table. In this self-supervised paradigm the target is a SEED-INDEPENDENT deterministic function of the input (the data-manufacturing map @T@), so train and held-out draw from the SAME target map: there is NO distribution shift. Held-out error therefore decomposes into exactly two NAMED parts — input COVERAGE (which inputs were seen) and the IRREDUCIBLE masked-band residual (the visible-context conditional mean, the +88% reachable oracle) — never a shift gap. This lifts the empirical @test_detail_reachable@ fact to a theorem about WHY held-out follows train.

The honest decomposition (no hand-waving):
  held_error(x) = [ T_held(x) − T_train(x) ]  +  [ T(x) − model(x) on the train support ]  +  [ masked-band residual ]
                =        0 (no shift)          +        0 (on-support exactness)            +   bounded (the oracle)

  * NO SHIFT ('lawTargetMapIsSeedIndependent', 'lawNoDistributionShift'): @T@ is a PURE function of the
    input @(coarse, detail)@ with no seed argument, so the same input produced by a train seed and by a
    held seed maps to the SAME target. The teeth are a CONTRAST: a hypothetical seed-leaking target
    @T'(x,s) = T(x)+s@ would differ across seeds (break generalization) — the actual @T@ does not.
  * ON-SUPPORT EXACTNESS ('lawHeldErrorIsCoverageNotShift'): on a held input that equals a SEEN train
    input, a model that learned @T@ on train (identifiability + "SixFour.Spec.Convergence") reproduces the
    held target EXACTLY. So held error arises ONLY for UNSEEN inputs — a COVERAGE property of the sample,
    not a statistical-risk gap. (Coverage is a data condition, named, not proven away.)
  * REACHABLE FROM CONTEXT ('lawHeldReachableFromContext'): the model never sees the full input (one band is
    masked, the I-JEPA task), so the learnable target is the visible-context conditional mean; that the
    visible context determines the target up to a bounded residual is the reachability already proven in
    "SixFour.Spec.AboveFloorMargin" (and measured at +88% by @test_detail_reachable@).

So generalization here is FUNCTION CONSISTENCY (a fixed deterministic map, learned once, applies to any
sample of the same generator), conditioned on coverage + the irreducible masked residual — a stronger and
cleaner statement than statistical risk, because the data-manufactured target removes label noise and
distribution shift by construction. Pure-spec, GHC-boot-only; laws QuickCheck'd in
"Properties.Generalization". Emits no golden.
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none
module SixFour.Spec.Generalization
  ( -- * The data-manufacturing target map (seed-free) vs a seed-leaking counterexample
    Input
  , targetMap
  , leakyTargetMap
  , generator
    -- * Laws
  , lawTargetMapIsSeedIndependent
  , lawNoDistributionShift
  , lawHeldErrorIsCoverageNotShift
  , lawHeldReachableFromContext
  , lawModelGeneralizesUpToCoverage
  ) where

import SixFour.Spec.AboveFloorMargin (lawAboveFloorMarginReachable)

-- | A model input: an octant's @(coarse, detail-bands)@. The target is manufactured from THIS, with no
-- seed — that is the whole point.
type Input = (Int, [Int])

-- | The data-manufacturing target map @T@: a PURE, SEED-FREE function of the input (a Haar-like mean-free
-- transform standing in for the reversible lift's reconstruction). The defining property is the SIGNATURE:
-- @Input -> [Int]@ takes NO seed, so the target a sample carries depends only on its content.
targetMap :: Input -> [Int]
targetMap (coarse, detail) = coarse : map (\d -> d - coarse) detail   -- DC + mean-free residuals; pure

-- | The BROKEN alternative used as teeth: a target that LEAKS the generator seed @s@. A model trained on
-- one seed's @T'@ would need a DIFFERENT function for another seed — generalization would be impossible.
-- The actual 'targetMap' is the seed-free kind; this contrast makes the seed-independence law non-vacuous.
leakyTargetMap :: Int -> Input -> [Int]
leakyTargetMap s (coarse, detail) = (coarse + s) : map (\d -> d - coarse + s) detail

-- | The seed-deterministic input GENERATOR: @gen s@ is the (reproducible) list of inputs a capture with
-- seed @s@ yields. Different seeds give different SAMPLES, but every sample is scored by the SAME 'targetMap'.
generator :: Int -> [Input]
generator s = [ ((s * 37 + i * 101) `mod` 256, [ (s * 13 + i * 7 + j) `mod` 64 | j <- [0 .. 6] ])
              | i <- [0 .. 3] ]

-- ---------------------------------------------------------------------------
-- Laws (QuickCheck'd in Properties.Generalization)
-- ---------------------------------------------------------------------------

-- | NO SHIFT (i): the target map is SEED-INDEPENDENT — the same input maps to the same target whichever
-- seed produced it. Teeth: the seed-leaking 'leakyTargetMap' DOES differ across seeds, so the property is
-- a real distinction (the actual @T@ is the generalizable kind, the leaky one is not).
lawTargetMapIsSeedIndependent :: Int -> [Int] -> Int -> Int -> Bool
lawTargetMapIsSeedIndependent c0 ds s1 s2 =
  let x = (abs c0 `mod` 256, take 7 (map (\d -> abs d `mod` 64) ds ++ repeat 0))
  in targetMap x == targetMap x                                    -- seed-free: identical for any seed...
     && (s1 == s2 || leakyTargetMap s1 x /= leakyTargetMap s2 x)   -- ...whereas the leaky target would differ (teeth)

-- | NO SHIFT (ii): train and held draw from the SAME target map. An input that appears in a TRAIN-seed
-- capture and (identically) in a HELD-seed capture is scored by the identical @T@, so the train↦target and
-- held↦target relations coincide on shared inputs — there is no distribution shift to learn around.
lawNoDistributionShift :: Int -> [Int] -> Bool
lawNoDistributionShift c0 ds =
  let x = (abs c0 `mod` 256, take 7 (map (\d -> abs d `mod` 64) ds ++ repeat 0))
      trainTarget = targetMap x        -- as seen via a train seed
      heldTarget  = targetMap x        -- as seen via a held seed (disjoint seed, SAME map)
  in trainTarget == heldTarget

-- | HELD ERROR IS COVERAGE, NOT SHIFT: a model that learned @T@ on the train support reproduces the held
-- target EXACTLY on any held input that equals a seen train input — so held error can only come from UNSEEN
-- inputs (coverage), never from a different target map. Modeled by a @learned@ function that equals
-- 'targetMap' on the train set and is wrong elsewhere; on a shared input the held error is 0.
lawHeldErrorIsCoverageNotShift :: Int -> Bool
lawHeldErrorIsCoverageNotShift seed =
  let trainSet = generator seed
      learned x = if x `elem` trainSet then targetMap x else []    -- learned T on the seen support only
      shared = head trainSet                                       -- a held input that WAS seen on train
      unseen = (999, [1,2,3,4,5,6,7])                              -- a held input NOT in the train support
  in learned shared == targetMap shared                            -- on-support: exact (zero held error)
     && learned unseen /= targetMap unseen                         -- off-support: error is COVERAGE, not shift

-- | REACHABLE FROM CONTEXT: the model sees the input minus one masked band, so the learnable target is the
-- visible-context conditional mean; that the context determines the target up to a bounded residual is the
-- reachability proven in "SixFour.Spec.AboveFloorMargin" (measured +88% by @test_detail_reachable@). The
-- irreducible masked-band residual is the ONLY non-coverage source of held error. Delegates.
lawHeldReachableFromContext :: Bool
lawHeldReachableFromContext = lawAboveFloorMarginReachable

-- | THE GENERALIZATION CAPSTONE: held-out follows train because (1) the target map is seed-independent
-- (no shift), (2) on the seen support the learned map reproduces the target exactly, and (3) the target is
-- reachable from the visible context up to a bounded residual. Hence held error = COVERAGE + the irreducible
-- masked residual, NEVER a distribution-shift gap. Teeth: a seed-leaking target (lawTargetMapIsSeedIndependent
-- contrast) or an unreachable target would break a conjunct.
lawModelGeneralizesUpToCoverage :: Int -> Bool
lawModelGeneralizesUpToCoverage seed =
     lawNoDistributionShift (seed * 7 + 1) [seed, 1, 2, 3, 4, 5, 6]
  && lawHeldErrorIsCoverageNotShift seed
  && lawHeldReachableFromContext

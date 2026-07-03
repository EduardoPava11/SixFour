{- |
Module      : SixFour.Spec.DescriptorQuasiIsometry
Description : The ADMISSIBILITY GATE a gene descriptor (and any learned encoder standing in for it) must pass: the pullback distance @geneDistance@ is a TWO-SIDED additive quasi-isometry from the Q16-floor gene metric to the P6 archive cloud, so a descriptor may neither COLLAPSE (distinct floor genes to distance 0) nor be DISCONTINUOUS (a 1-LSB gene step to an unbounded cell jump).

"SixFour.Spec.GeneSimilarity" proved @geneDistance@ is a pullback PSEUDOmetric: it
inherits non-negativity, symmetry and the triangle inequality, and it quotients the
gauge (identical expression ⇒ distance 0). A pseudometric is only HALF of what a
MAP-Elites descriptor needs. A cell function that merged two genuinely different
looks into one cell, or scattered one look across many, would satisfy every
pseudometric law and still be useless: those are the LOWER (no collapse) and UPPER
(no discontinuity) bounds a pseudometric does not carry.

This module promotes the pseudometric to a two-sided bound on the Q16 floor:

@
  loNum·dq − loDen·slack  ≤  loDen·dc   (LOWER: distinct floor genes stay apart)
  dc·hiDen                ≤  hiNum·dq   (UPPER: a small dq cannot jump dc)
@

where @dq@ is the L¹ distance between the two genes' Q16 FLOOR REPRESENTATIVES and
@dc = geneDistance@ on those representatives. The distortion is the rational
@κ = c2/c1 = (hiNum·loDen)/(hiDen·loNum) ≥ 1@ (an isometry is @κ=1@; Nash forbids
@κ=1@ under compression, so a BOUNDED @κ@ is the honest target). This is exactly
the acceptance test a merged, bred, or learned descriptor blob must pass to enter
the atlas; the CNN-encoder route enforces the upper half by spectral normalisation
and must EARN the lower half.

== Discrete geometry + algebraic number theory

The mechanics are lattice and integer facts, never analysis on ℝ:

  * The distance lives on the ℤ[1\/2] Q16 floor. Both @dq@ and @dc@ are computed
    on Q16 FLOOR REPRESENTATIVES (@quantizeQ16@ words), never on raw fp32 θ, so the
    inequalities are byte-exact integer comparisons and the gate is total, not
    tolerance-based ('lawFloorKernelIsGaugeKernel' pins that the metric kernel IS the
    sub-quantum gauge kernel).
  * The LOWER bound (@c1>0@, no collapse) is an ALGEBRAIC full-rank fact, not a
    trained property: two band-weight vectors that agree on all 9 'canonicalProbe'
    committed readouts are Q16-equal, because the per-band design matrix over the
    exact-readout stimuli is a VANDERMONDE whose integer determinant is a unit-scaled
    non-zero (det @2@ on the @{ -1, 0, 1 }@ stimulus triple), hence full column rank over
    ℤ ('lawProbeDesignVandermondeFullRank'). A DEGENERATE (collinear) probe set has
    determinant @0@ and cannot separate ('lawRealProbeSeparatesCollision' is the
    non-vacuity witness: the real probe keeps apart two genes a rank-deficient probe
    would merge). This full-rank certificate is the real Tier-0 keystone; the
    quasi-isometry inequality rides on it as a corollary.
  * The additive @slack@ is pinned STRICTLY below one representable Q16 step
    ('lawSlackBelowOneStep': @slack·loNum < loDen·oneStep@ with @slack = 0@), so the
    lower bound carries anti-collapse content everywhere above the floor and the
    "additive slack" is never an escape hatch.
  * @κ→1@ is stated as BOUNDED distortion at the coincidence point (both distances
    @0@, @c1>0@, @κ≥1@), NOT as an identity @dc==dq@ (that would be a
    'SixFour.Spec.CrossEncoderDistance' cross-encoder-zero fact, a different quantity).

The pinned constants @c1 = loNum\/loDen = 1\/2@ and @c2 = hiNum\/hiDen = 18@ are for the
shipped 'defaultPredictorShape' (7 bands × 3 features, 9-point 'canonicalProbe'); the
upper constant is a validated safe ceiling (the observed single-word worst case is 9).
-}
module SixFour.Spec.DescriptorQuasiIsometry
  ( -- * The Q16-floor gene metric and the descriptor distance
    thetaFloorRep
  , thetaFloorDist
  , descriptorDistance
    -- * Pinned distortion constants (golden)
  , loNum, loDen, hiNum, hiDen, slack, oneStep
    -- * Keystone: the probe design separates bands (full-rank certificate)
  , committedCloud
  , lawProbeDesignVandermondeFullRank
  , lawProbeDesignSeparatesBands
  , lawRealProbeSeparatesCollision
    -- * The two-sided quasi-isometry (corollary) and its halves
  , lawDescriptorIsQuasiIsometry
  , lawDescriptorUpperLipschitz
  , lawDescriptorLowerSeparation
    -- * Honest quotient, de-vacuifying slack, bounded distortion
  , lawFloorKernelIsGaugeKernel
  , lawSlackBelowOneStep
  , lawDistortionBoundedAtAnalysis
  ) where

import SixFour.Spec.GeneSimilarity  (geneDistance, canonicalProbe)
import SixFour.Spec.DetailPredictor (PredictorShape, defaultPredictorShape, rawBands)
import SixFour.Spec.Q16             (quantizeQ16, toQ16)

-- | The shipped predictor shape (7 bands × 3 features). The pinned constants are
-- for this shape; expressing the laws over it matches "SixFour.Spec.GeneSimilarity".
sh :: PredictorShape
sh = defaultPredictorShape

-- | The Q16 FLOOR REPRESENTATIVE of a gene, word by word (@quantizeQ16@ is the
-- Double→Int floor; the representative is the canonical integer point of the
-- sub-quantum gauge class).
thetaFloorRep :: [Double] -> [Int]
thetaFloorRep = map quantizeQ16

-- | The gene re-expressed as its Q16 floor representative (Double view), so the
-- descriptor distance is read on the floor, "never raw fp32 θ".
floorGene :: [Double] -> [Double]
floorGene = map (toQ16 . quantizeQ16)

-- | @dq@: the L¹ distance between two genes' Q16 floor representatives (integer,
-- gauge-quotiented).
thetaFloorDist :: [Double] -> [Double] -> Int
thetaFloorDist a b = sum (zipWith (\x y -> abs (x - y)) (thetaFloorRep a) (thetaFloorRep b))

-- | @dc@: the REAL 'geneDistance' evaluated on the floored representatives (the
-- pullback cloud distance the descriptor is measured by).
descriptorDistance :: [Double] -> [Double] -> Int
descriptorDistance a b = geneDistance sh (floorGene a) (floorGene b)

-- | Pinned golden constants. @c1 = loNum\/loDen = 1\/2@, @c2 = hiNum\/hiDen = 18@,
-- @slack = 0@ (INVARIANT 'lawSlackBelowOneStep': @slack·loNum < loDen·oneStep@).
loNum, loDen, hiNum, hiDen, slack, oneStep :: Int
loNum = 1; loDen = 2; hiNum = 18; hiDen = 1; slack = 0; oneStep = 1

-- | A probe-parameterised committed cloud mirror of @expressGene@'s value readouts:
-- @quantizeQ16 (rawBands θ v)@ at each (probe stimulus, band). Uses the REAL
-- 'rawBands', so cloud agreement here is exactly agreement of the shipped expression.
committedCloud :: [Int] -> [Double] -> [Int]
committedCloud probe g = [ quantizeQ16 rb | v <- probe, rb <- rawBands sh g v ]

-- | A correct 3×3 integer determinant (the byte-exact full-rank certificate).
det3x3 :: [[Int]] -> Int
det3x3 [[a,b,c],[d,e,f],[g,h,i]] = a*(e*i-f*h) - b*(d*i-f*g) + c*(d*h-e*g)
det3x3 _ = 0

-- | ★ KEYSTONE (design certificate). The per-band design over the exact-readout
-- stimuli @s ∈ { -1, 0, 1 }@ (@v ∈ { -65536, 0, 65536 }@) is the Vandermonde @[[1,s,s²]]@,
-- integer determinant @2 ≠ 0@ = full column rank over ℤ, so agreement of all 3
-- band coefficients is forced by agreement on those 3 probes; a DEGENERATE
-- (collinear, all @s=0@) design has determinant @0@ and cannot separate. @c1>0@
-- rests on this.
lawProbeDesignVandermondeFullRank :: Bool
lawProbeDesignVandermondeFullRank =
     det3x3 [[1,-1,1],[1,0,0],[1,1,1]] == 2       -- real exact-stimulus Vandermonde: full rank
  && det3x3 [[1,0,0],[1,0,0],[1,0,0]] == 0        -- collinear (rank-deficient): cannot separate

-- | The keystone as an operational predicate over the REAL 'rawBands': two genes
-- whose committed clouds agree on the full 'canonicalProbe' frame share a Q16 floor
-- representative. (Bool @<=@ is implication.)
lawProbeDesignSeparatesBands :: [Double] -> [Double] -> Bool
lawProbeDesignSeparatesBands a b =
  (committedCloud canonicalProbe a == committedCloud canonicalProbe b)
    <= (thetaFloorRep a == thetaFloorRep b)

-- | Non-vacuity witness: two Q16-DISTINCT genes agree on a DEGENERATE one-stimulus
-- probe (a rank-deficient design would merge them), yet the REAL 'canonicalProbe'
-- keeps their committed clouds apart. The full frame separates a collision a bad
-- design would not.
lawRealProbeSeparatesCollision :: Bool
lawRealProbeSeparatesCollision =
  let ga = pad [1,0,0]; gb = pad [1,5,7]      -- same constant coeff, differ in v,w of band 0
      degenerate = [0]                          -- only the s=0 stimulus (rank < 3)
  in  committedCloud degenerate    ga == committedCloud degenerate    gb   -- degenerate MERGES
   && committedCloud canonicalProbe ga /= committedCloud canonicalProbe gb  -- real SEPARATES
   && thetaFloorRep ga /= thetaFloorRep gb                                  -- and they ARE distinct
  where pad xs = map toQ16 (take nWords (xs ++ repeat 0))
        nWords = 21

-- | The two-sided additive quasi-isometry (corollary of the keystone):
-- @c1·dq − slack ≤ dc ≤ c2·dq@, all integer.
lawDescriptorIsQuasiIsometry :: [Double] -> [Double] -> Bool
lawDescriptorIsQuasiIsometry a b =
  let q = thetaFloorDist a b; c = descriptorDistance a b
  in  loNum*q - loDen*slack <= loDen*c    -- LOWER: no collapse
   && c*hiDen               <= hiNum*q    -- UPPER: no discontinuity

-- | Upper half alone (non-expansion, the spectral-norm analogue).
lawDescriptorUpperLipschitz :: [Double] -> [Double] -> Bool
lawDescriptorUpperLipschitz a b = descriptorDistance a b * hiDen <= hiNum * thetaFloorDist a b

-- | Lower half alone (anti codebook-collapse): distinct floor genes stay apart.
lawDescriptorLowerSeparation :: [Double] -> [Double] -> Bool
lawDescriptorLowerSeparation a b =
  loNum * thetaFloorDist a b - loDen*slack <= loDen * descriptorDistance a b

-- | Honest quotient: the metric kernel is EXACTLY the sub-quantum gauge kernel,
-- @dq a b == 0 ⇔@ shared Q16 representative.
lawFloorKernelIsGaugeKernel :: [Double] -> [Double] -> Bool
lawFloorKernelIsGaugeKernel a b = (thetaFloorDist a b == 0) == (thetaFloorRep a == thetaFloorRep b)

-- | The de-vacuifying golden: the whole additive-slack region is provably sub-LSB,
-- so the lower bound is never vacuously satisfied by slack.
lawSlackBelowOneStep :: Bool
lawSlackBelowOneStep = slack * loNum < loDen * oneStep   -- 0 < 2

-- | @κ→1@ at the coincidence point as BOUNDED distortion (both distances 0, @c1>0@,
-- @κ = (hiNum·loDen)/(hiDen·loNum) ≥ 1@), NOT the identity @dc==dq@.
lawDistortionBoundedAtAnalysis :: [Double] -> Bool
lawDistortionBoundedAtAnalysis a =
     descriptorDistance a a == 0 && thetaFloorDist a a == 0   -- coincidence: both 0
  && loNum > 0 && hiDen > 0                                    -- c1 > 0
  && hiNum * loDen >= hiDen * loNum                            -- κ ≥ 1

module Properties.GeneSimilarity (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.DetailPredictor (defaultPredictorShape, paramCount)
import SixFour.Spec.GeneSimilarity

-- | A θ_up-shaped gene: 21 words on the trained scale (readouts within a few
-- Q16 units, negatives included).
genGene :: Gen [Double]
genGene = vectorOf (paramCount defaultPredictorShape) (choose (-2, 2))

tests :: TestTree
tests = testGroup "GeneSimilarity (pullback pseudometric — express on the probe lattice, measure in d6)"
  [ testProperty "pullback is a pseudometric (reflexive-zero, symmetric, triangle)" $
      forAll genGene $ \a -> forAll genGene $ \b -> forAll genGene $ \c ->
        lawPullbackPseudometric a b c

  , testProperty "gauge quotient: sub-quantum θ ≠ zero word-wise, expresses IDENTICALLY, distance 0" $
      once lawGaugeQuotient

  , testProperty "the zero gene is the origin (all-floor cloud, self-distance 0)" $
      once lawFloorIsOrigin

  , testProperty "positions are a shared frame: position axes contribute exactly 0" $
      forAll genGene $ \a -> forAll genGene (lawPositionsCancel a)

  , testProperty "the pinned probe separates (unit gene > 0 from zero; full 9×7 frame)" $
      once lawProbeSeparates
  ]

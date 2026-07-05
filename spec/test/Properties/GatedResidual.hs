module Properties.GatedResidual (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.DetailPredictor (defaultPredictorShape, paramCount)
import SixFour.Spec.GatedResidual

-- Coarse Q16 values in a realistic range.
genV :: Gen Int
genV = choose (-8000, 8000)

-- A param vector sized to the deployed shape (small magnitude keeps the gated
-- readout well-scaled).
genParams :: Gen [Double]
genParams = vectorOf (paramCount defaultPredictorShape) (choose (-0.5, 0.5))

-- Gate strengths spanning both signs and out to the near-saturated tail.
genAlpha :: Gen Double
genAlpha = choose (-6, 6)

genAlphaNonneg :: Gen Double
genAlphaNonneg = choose (0, 6)

tests :: TestTree
tests = testGroup "GatedResidual (tanh-gated learned residual; alpha=0 == floor, contractive toward it)"
  [ testProperty "KEYSTONE: alpha=0 == the byte-exact floor (dial the gene to lossless, no weight change)" $
      forAll genParams $ \ps -> forAll genV $ \v -> lawZeroGateIsFloor defaultPredictorShape ps v

  , testProperty "contractive: |gated| <= |ungated| for any alpha (only pulls TOWARD the floor)" $
      forAll genParams $ \ps -> forAll genV $ \v -> forAll genAlpha $ \a ->
        lawGateContractive defaultPredictorShape ps v a

  , testProperty "monotone-earn: |gated| grows with alpha on [0, .) toward the ungated head" $
      forAll genParams $ \ps -> forAll genV $ \v ->
        forAll genAlphaNonneg $ \a1 -> forAll genAlphaNonneg $ \a2 ->
          lawGateMonotoneOnNonneg defaultPredictorShape ps v a1 a2

  , testProperty "approaches ungated: large alpha => gate -> 1 => gated -> raw" $
      forAll genParams $ \ps -> forAll genV $ \v -> lawGateApproachesUngated defaultPredictorShape ps v

  , testProperty "sign preserving: a positive gate never flips a band's sign" $
      forAll genParams $ \ps -> forAll genV $ \v -> forAll genAlpha $ \a ->
        lawGateSignPreserving defaultPredictorShape ps v a
  ]

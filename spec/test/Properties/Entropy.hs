module Properties.Entropy (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.Color   (OKLab(..))
import SixFour.Spec.Entropy

genOKLab :: Gen OKLab
genOKLab = OKLab <$> choose (0, 1) <*> choose (-0.4, 0.4) <*> choose (-0.4, 0.4)

-- A small capture: 1–5 frames, each a 1–5 colour palette.
genFrames :: Gen [[OKLab]]
genFrames = do
  nf <- choose (1, 5)
  let frame = choose (1, 5) >>= \k -> vectorOf k genOKLab
  vectorOf nf frame

-- A small global palette (1–5 colours).
genGlobal :: Gen [OKLab]
genGlobal = choose (1, 5) >>= \k -> vectorOf k genOKLab

tests :: TestTree
tests = testGroup "Entropy (capture information analysis — RGBT weights + scope cost)"
  [ testProperty "RGBT weights are non-negative" $
      forAll genFrames lawWeightsNonNegative

  , testProperty "RGBT weights sum to 1" $
      forAll genFrames lawWeightsSumToOne

  , testProperty "scope cost is non-negative" $
      forAll genGlobal $ \g ->
        forAll genFrames (lawScopeCostNonNegative g)

  , testProperty "scope cost is EXACTLY zero when all frames equal the global palette" $
      forAll genGlobal $ \g ->
        forAll (choose (1, 6)) (lawScopeCostZeroOnIdenticalFrames g)

  , testProperty "scope verdict respects its threshold (Global ⟺ cost ≤ τ)" $
      forAll (choose (0, 1e-3)) $ \tau ->
        forAll (choose (0, 1e-3)) (lawScopeVerdictThreshold tau)
  ]

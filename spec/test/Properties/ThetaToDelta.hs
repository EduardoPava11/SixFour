{- |
Module      : Properties.ThetaToDelta
Description : Property tests for 'SixFour.Spec.ThetaToDelta' — the θ → δ taste map.

Closes the maintenance-contract false-green: the module header claimed these laws
were "QuickCheck'd in Properties.ThetaToDelta" before this file existed.
-}
module Properties.ThetaToDelta (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.ThetaToDelta

-- A θ of length @6g + 2@ for a small generator count (the real θ is 770 = 6·128 + 2).
genTheta :: Gen [Double]
genTheta = do
  g <- choose (0, 24) :: Gen Int
  vectorOf (6 * g + 2) (choose (-5, 5))

-- A non-negative gain (the laws hold for any gain ≥ 0; defaultGain is the shipped one).
genGain :: Gen Double
genGain = choose (0, 1e6)

-- A generator list (float OKLab-ish) for the finite-difference gradient law.
genGens :: Gen [(Double, Double, Double)]
genGens = do
  n <- choose (0, 24) :: Gen Int
  vectorOf n ((,,) <$> choose (-1, 1) <*> choose (-1, 1) <*> choose (-1, 1))

tests :: TestTree
tests = testGroup "ThetaToDelta (θ → δ taste-ascent gradient — n=0 map)"
  [ testProperty "zero θ ⇒ zero δ (no taste, no tint)" $
      forAll (choose (0, 256)) lawZeroThetaZeroDelta

  , testProperty "δ is clamped to ±deltaMaxQ16 for any θ and gain" $
      forAll genGain $ \gain -> forAll genTheta (lawDeltaBoundedQ16 gain)

  , testProperty "raw map IS the leaf-linear taste gradient (finite-diff, ε)" $
      forAll genTheta $ \t -> forAll genGens (lawRawIsTasteGradient t)

  , testProperty "raw map is linear in θ" $
      forAll genTheta $ \t1 ->
        forAll (vectorOf (length t1) (choose (-5, 5))) $ \t2 ->
          lawRawLinearInTheta t1 t2

  , testProperty "the [coverage, beauty] tail does not affect δ" $
      forAll genTheta $ \t ->
        forAll (choose (-9, 9)) $ \c -> forAll (choose (-9, 9)) (lawCoverageBeautyIgnored t c)
  ]

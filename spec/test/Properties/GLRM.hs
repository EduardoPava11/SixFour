{-# LANGUAGE ScopedTypeVariables #-}

module Properties.GLRM (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Test.QuickCheck

import SixFour.Spec.GLRM

-- The preference-training kill-switch (M4): OLS over [coverage, beauty, ‖chroma‖²]; train only on
-- a stable fit, drop degenerate gallery pairs. These laws pin the solver's correctness and the
-- two refusal behaviours (no signal -> STOP; too-close pair -> zero weight).

genFeatures :: Gen Features
genFeatures = (,,) <$> choose (0, 2) <*> choose (0, 2) <*> choose (0, 1)

genSamples :: Gen [(Features, Double)]
genSamples = do
  n <- choose (0, 30)
  vectorOf n ((,) <$> genFeatures <*> choose (-2, 2))

genFeatsList :: Gen [Features]
genFeatsList = do
  n <- choose (4, 10)
  vectorOf n genFeatures

genBeta :: Gen (Double, Double, Double, Double)
genBeta = (,,,) <$> c <*> c <*> c <*> c where c = choose (-2, 2)

genEmb :: Gen [Double]
genEmb = do n <- choose (1, 8); vectorOf n (choose (-2, 2))

genEmbPair :: Gen ([Double], [Double])
genEmbPair = do
  n <- choose (1, 8)
  (,) <$> vectorOf n (choose (-2, 2)) <*> vectorOf n (choose (-2, 2))

genYs :: Gen [Double]
genYs = do n <- choose (4, 8); vectorOf n (choose (-2, 2))

tests :: TestTree
tests = testGroup "GLRM (the preference-training kill-switch)"

  [ testProperty "a fit's R² is in [0,1] (lawR2InUnitInterval)" $
      forAll genSamples lawR2InUnitInterval

  , testProperty "OLS recovers an exactly-linear signal, R² ≈ 1 (lawOLSRecoversLinear)" $
      forAll genFeatsList $ \fs -> forAll genBeta $ \bs -> lawOLSRecoversLinear fs bs

  , testProperty "no signal (identical rows) BLOCKS training (lawNoSignalBlocks)" $
      forAll genFeatures $ \f -> forAll genYs $ \ys -> lawNoSignalBlocks f ys

  , testProperty "shouldTrain == stable-fit-clears-floor (lawKillSwitchConsistent)" $
      forAll genSamples lawKillSwitchConsistent

  , testProperty "a degenerate pair carries zero weight (lawDegeneratePairZeroWeight)" $
      forAll genEmb lawDegeneratePairZeroWeight

  , testProperty "positive weight iff informative pair (lawGalleryPairInformative)" $
      forAll genEmbPair $ \(a, b) -> lawGalleryPairInformative a b

  , testProperty "GOLDEN: an exactly-linear preference signal PASSES the kill-switch" $
      once $
        let feats   = [(0,0,0),(1,0,0),(0,1,0),(0,0,1),(1,1,1)]
            samples = [ (f, 2 + 3 * c) | f@(c,_,_) <- feats ]   -- y = 2 + 3·coverage, exact
        in shouldTrain samples

  , testProperty "GOLDEN: a constant-feature (no-information) log BLOCKS the kill-switch" $
      once $ not (shouldTrain [ ((1,1,1), y) | y <- [1,2,3,4,5] ])
  ]

module Properties.DetailMaskedPrediction (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.OctreeCell             (Detail)
import SixFour.Spec.DetailMaskedPrediction

-- Coarse context values in the stable training range (toQ16 keeps ||phi||^2 ~ 1 so
-- eta=0.25 SGD converges, as pinned for DetailPredictor).
genV :: Gen Int
genV = choose (-8000, 8000)

-- Targets whose bands reach off-floor (|coef| > 4096) so the constant-predictor loss
-- is genuinely positive.
genDetail :: Gen Detail
genDetail =
  let g = choose (-20000, 20000)
  in (,,,,,,) <$> g <*> g <*> g <*> g <*> g <*> g <*> g

tests :: TestTree
tests = testGroup "DetailMaskedPrediction (the real JEPA objective: constant predictor incurs positive loss)"
  [ testProperty "OBJECTIVE: off-floor masked target => constant predictor loss > 0 AND one step reduces it" $
      forAll genV $ \v -> forAll genDetail $ \t -> lawConstantPredictorIncursLoss v t

  , testProperty "the mask is recoverable: training drives loss to a tiny fraction of the constant loss" $
      forAll genV $ \v -> forAll genDetail $ \t -> lawTrainingDrivesLossDown v t

  , testProperty "the masked band carries info beyond context: fitting one answer misses another" $
      forAll genV $ \v -> forAll genDetail $ \t -> lawFittingOneTargetMissesAnother v t
  ]

module Properties.Barycenter (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.Color      (OKLab(..))
import SixFour.Spec.Sinkhorn   (Measure)
import SixFour.Spec.Barycenter

genOKLab :: Gen OKLab
genOKLab = OKLab <$> choose (0, 1) <*> choose (-0.4, 0.4) <*> choose (-0.4, 0.4)

genMeasure :: Gen Measure
genMeasure = do
  k <- choose (1, 4)
  vectorOf k ((,) <$> genOKLab <*> choose (0.1, 2.0))

-- A few input measures + a small seed support.
genInputs :: Gen ([Measure], [OKLab])
genInputs = do
  s    <- choose (1, 3)
  ms   <- vectorOf s genMeasure
  kSeed <- choose (1, 4)
  seed <- vectorOf kSeed genOKLab
  pure (ms, seed)

tests :: TestTree
tests = testGroup "Barycenter (free-support Wasserstein / particle-flow collapse move)"
  [ testProperty "preserves support size (K-palette stays a K-palette)" $
      forAll genInputs $ \(ms, seed) ->
        lawBarycenterPreservesSupportSize ms seed

  , testProperty "gamut-closed: output stays within the input atoms' bounding box" $
      forAll genInputs $ \(ms, seed) ->
        lawBarycenterStaysInInputHull ms seed

  , testProperty "translation-equivariant: shift inputs + seed by v ⇒ barycenter shifts by v" $
      forAll genInputs $ \(ms, seed) ->
        forAll ((,,) <$> choose (-0.3, 0.3) <*> choose (-0.3, 0.3) <*> choose (-0.3, 0.3)) $ \v ->
          lawBarycenterTranslationEquivariant ms seed v
  ]

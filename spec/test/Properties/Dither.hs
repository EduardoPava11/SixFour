module Properties.Dither (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Test.QuickCheck
import Text.Printf (printf)

import SixFour.Spec.Color  (OKLab(..))
import SixFour.Spec.Dither

genOKLab :: Gen OKLab
genOKLab = OKLab <$> choose (0, 1) <*> choose (-0.4, 0.4) <*> choose (-0.4, 0.4)

genP :: Gen Double
genP = choose (0, 1)

tests :: TestTree
tests = testGroup "Dither (binary distribution realising a pair)"
  [ testProperty "dithered colour is convex: each channel between anchor & partner" $
      forAll genP $ \p ->
        forAll genOKLab $ \a ->
          forAll genOKLab $ \b -> lawDitheredColorConvex p a b

  , testProperty "endpoints: p=0 ⇒ anchor, p=1 ⇒ partner" $
      forAll genOKLab $ \a ->
        forAll genOKLab $ \b ->
          ditheredColor 0 a b == a && ditheredColor 1 a b == b

  , -- The binary distribution reproduces the colour: golden-ordered draws average
    -- to p. T = 64 frames (SixFour's loop length); golden low-discrepancy ⇒ tight.
    testProperty "golden-ordered binary mean recovers p (T=64)" $
      forAll genP (lawDitherMeanRecoversP 0.05 64)

  , testProperty "flicker (binomial variance) is maximal at p = 0.5" $
      forAll (choose (1, 64)) $ \t ->
        forAll genP $ \p -> lawVarianceMaxAtHalf t p

  , -- Knowledge: a φ-positioned tone (0.382/0.618) flickers less than a 50/50 blend.
    testProperty "φ split (0.382/0.618) has lower flicker than 0.5" $
      once $
        let vHalf = binomialVariance 64 0.5
            vPhi  = binomialVariance 64 0.382
        in label (printf "var@0.5=%.2f  var@0.382=%.2f" vHalf vPhi) (vPhi < vHalf)
  ]

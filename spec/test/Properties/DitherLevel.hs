module Properties.DitherLevel (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.DitherLevel

tests :: TestTree
tests = testGroup "DitherLevel (dither = the per-pixel latent z, realized by a decoder)"
  [ testProperty "realization is UNBIASED: loop mean recovers p" $
      once lawRealizationUnbiased
  , testProperty "realization is NOT reversible: distinct p, same finite-T stream" $
      once lawRealizationIsNotReversible
  , testProperty "flicker (latent variance) peaks at p=0.5" $
      once lawDitherFlickerPeaksAtHalf
  , testProperty "continuous p reduces to the discrete corner at p in {0,1}" $
      once lawContinuousReducesToDiscrete
  , testProperty "the golden ordering tames the latent; a constant ordering does not" $
      once lawGoldenOrderingTamesLatent
  ]

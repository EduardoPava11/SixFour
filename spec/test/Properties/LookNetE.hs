{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}

module Properties.LookNetE (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Test.QuickCheck

import qualified Data.Vector.Unboxed as U

import SixFour.Spec.Tensor   (Tensor1(..))
import SixFour.Spec.LookNetE

-- A single 10-D GMM token with unit-bounded entries.
genToken :: Gen [Double]
genToken = vectorOf 10 (choose (-1, 1))

-- A token set with 0..6 tokens (small enough that the FP reassociation noise
-- stays well within the 1e-12 tolerance).
genTokenSet :: Gen GmmTokenSet
genTokenSet = do
  n   <- choose (0, 6)
  rs  <- vectorOf n genToken
  case mkGmmTokenSet rs of
    Just s  -> pure s
    Nothing -> error "genTokenSet: shape mismatch (impossible)"

-- A non-empty token set (for permutation invariance — empty trivially passes).
genTokenSetNonEmpty :: Gen GmmTokenSet
genTokenSetNonEmpty = do
  n  <- choose (1, 6)
  rs <- vectorOf n genToken
  case mkGmmTokenSet rs of
    Just s  -> pure s
    Nothing -> error "genTokenSetNonEmpty: shape mismatch (impossible)"

-- A permutation of [0..n-1] for the size of the supplied token set.
genPermOf :: GmmTokenSet -> Gen [Int]
genPermOf s = shuffle [0 .. gmmTokenSetSize s - 1]

tests :: TestTree
tests = testGroup "LookNetE (L3 encoder — typed Stage with σ-equivariance + perm-invariance)"

  [ testProperty "placement map honours σ-classes (compile-time-meaningful, runtime-checked)" $
      once lawPlacementMapHonoursSigma

  , testProperty "reference baseline σ-equivariance: E(σx) ≈ σ(Ex) (tol 1e-12)" $
      forAll genTokenSet (lawEncoderRefSigmaEquivariance 1e-12)

  , testProperty "reference baseline permutation-invariance: E(perm s) ≈ E(s) (tol 1e-12)" $
      forAll genTokenSetNonEmpty $ \s ->
        forAll (genPermOf s) $ \perm ->
          lawEncoderRefPermutationInvariance 1e-12 perm s

  , testProperty "dimensional contract: input 10-D tokens → output 64-D context" $
      once lawEncoderRefDimensionalContract

  , testProperty "empty token set maps to the zero context" $
      once $
        let HiddenContext (Tensor1 v) = encoderReference (GmmTokenSet [])
        in U.length v == 64 && U.all (== 0.0) v

  , testProperty "channel-slot accounting: 22 achromatic + 21 red-green + 21 blue-yellow = 64" $
      once $
        let a = length achromaticChannelSlots
            r = length redGreenChannelSlots
            b = length blueYellowChannelSlots
        in a == 22 && r == 21 && b == 21 && a + r + b == 64
           && minimum achromaticChannelSlots == 0
           && maximum achromaticChannelSlots == 21
           && minimum redGreenChannelSlots   == 22
           && maximum redGreenChannelSlots   == 42
           && minimum blueYellowChannelSlots == 43
           && maximum blueYellowChannelSlots == 63
  ]

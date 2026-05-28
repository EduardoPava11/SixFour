{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}

module Properties.LookNetCompose (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Test.QuickCheck

import qualified Data.Vector.Unboxed as U

import SixFour.Spec.Tensor        (Tensor1(..))
import SixFour.Spec.LookNetE      (GmmTokenSet(..), mkGmmTokenSet)
import SixFour.Spec.LookNetCompose

genToken :: Gen [Double]
genToken = vectorOf 10 (choose (-1, 1))

genTokenSet :: Gen GmmTokenSet
genTokenSet = do
  n   <- choose (0, 5)
  rs  <- vectorOf n genToken
  case mkGmmTokenSet rs of
    Just s  -> pure s
    Nothing -> error "genTokenSet: shape mismatch (impossible)"

tests :: TestTree
tests = testGroup "LookNetCompose (E :> R :> D — end-to-end σ-equivariance theorem)"

  [ testProperty "the pipeline typechecks: lookNetSigmaTheorem produces a SigmaEquivariantDict" $
      once lawPipelineComposes

  , testProperty "the reference pipeline (E_ref :> R_ref :> D_ref) is the zero map" $
      forAll genTokenSet lawLookNetReferenceIsZero

  ]

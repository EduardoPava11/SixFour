{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}

module Properties.LookNetR (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Test.QuickCheck

import qualified Data.Vector.Unboxed as U

import SixFour.Spec.Tensor   (Tensor1(..))
import SixFour.Spec.LookNetE (HiddenContext(..))
import SixFour.Spec.LookNetR

genHiddenContext :: Gen HiddenContext
genHiddenContext = do
  xs <- vectorOf 64 (choose (-1, 1) :: Gen Double)
  pure (HiddenContext (Tensor1 (U.fromList xs)))

tests :: TestTree
tests = testGroup "LookNetR (L4 shared-block recursion — Mixture-of-Recursions over Haar levels, σ-invariant halting)"

  [ testProperty "structural constants: depth=8, halting=1 per step" $
      once (coreDepth == 8 && haltingWeightSlot == 1)

  , testProperty "exactly ONE shared block reused coreDepth=8 times (Mixture-of-Recursions)" $
      forAll genHiddenContext lawSharedBlockReuse

  , testProperty "reference core IS the identity (the spec is a contract, not a computation)" $
      forAll genHiddenContext lawCoreRefIsIdentity

  , testProperty "reference core σ-equivariance: id ∘ σ = σ ∘ id (trivial base case)" $
      forAll genHiddenContext lawCoreRefSigmaEquivariance

  , testProperty "recursion is σ-equivariant inductively ∀ n≤coreDepth (id refine, tol 1e-12)" $
      forAll genHiddenContext (lawRecursionSigmaEquivariance 1e-12)

  , testProperty "halting head is σ-INVARIANT (squares kill chroma sign — EXACT, ==)" $
      forAll genHiddenContext lawHaltingSigmaInvariance

  , testProperty "σ-block-diagonal mask: weight free iff input/output dims share σ-class" $
      once lawBlockDiagonalMaskRespectsSigma

  , testProperty "symmetry pruning arithmetic: 22² + 42² = 2248 / 4096 free, ratio ≈ 0.549" $
      once lawSymmetryPruningRatio

  , testProperty "free parameter count is 2248 per 64×64 weight (45% pruned by symmetry)" $
      once (freeParameterCount == 2248 && naiveParameterCount == 4096)
  ]

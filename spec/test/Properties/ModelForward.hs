module Properties.ModelForward (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.ModelForward

-- | Exactly the octant shape: 8 coarse children. Under the previous bare-@[Int]@
-- generator the laws' @length \/= 8 ||@ totality guard short-circuited on almost
-- every case, so the two behavioural keystones passed near-vacuously (audit
-- 2026-07-03, finding G1). The @cover@\/@checkCoverage@ pair below turns any
-- regression back to a vacuous generator into a test FAILURE, not a silent pass.
genCoarse8 :: Gen [Int]
genCoarse8 = vectorOf 8 arbitrary

tests :: TestTree
tests = testGroup "ModelForward (the nudge-conditioned forward contract)"
  [ testProperty "unpainted input is the byte-exact floor (any head, either gauge; octant shape always driven)"
      (checkCoverage $ forAll genCoarse8 $ \coarse ->
         cover 99 (length coarse == 8) "octant-shaped coarse (8 children)" $
         lawZeroNudgeForwardIsFloor coarse)
  , testProperty "a painted cell moves the output off the floor (any pair 0..8, any positive budget, either gauge)"
      (checkCoverage $ forAll genCoarse8 $ \coarse ->
         forAll (choose (0, 8)) $ \p ->
         forAll (choose (1, 1048576)) $ \v ->
         forAll arbitrary $ \g ->
           cover 99 (length coarse == 8) "octant-shaped coarse (8 children)" $
           lawNudgeMovesOutput p v g coarse)
  , testProperty "the ModelIO input boundary is honest end-to-end (forwardFromInput consumes paint + gauge)"
      (checkCoverage $ forAll genCoarse8 $ \coarse ->
         forAll (choose (0, 8)) $ \p ->
         forAll (choose (1, 1048576)) $ \v ->
         forAll arbitrary $ \g ->
           cover 99 (length coarse == 8) "octant-shaped coarse (8 children)" $
           lawForwardFromInputConsumesPaint p v g coarse)
  , testProperty "REFUSAL: a missing budget row degrades to the byte-exact floor (contract, not accident)"
      (forAll genCoarse8 $ \coarse -> forAll arbitrary $ \g ->
         lawMissingBudgetRowIsFloor g coarse)
  , testProperty "the head's codomain is A_7 (every output reconstructs mean-free)"
      lawResidualStaysInA7
  , testProperty "the commit is byte-exact Q16 (invented coords re-enter the grid with no drift)"
      lawForwardCommitIsQ16
  ]

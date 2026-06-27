module Properties.ModelForward (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.ModelForward

tests :: TestTree
tests = testGroup "ModelForward (the nudge-conditioned forward contract)"
  [ testProperty "unpainted input is the byte-exact floor (any head, either gauge)"
      lawZeroNudgeForwardIsFloor
  , testProperty "a painted cell moves the output off the floor"
      lawNudgeMovesOutput
  , testProperty "the head's codomain is A_7 (every output reconstructs mean-free)"
      lawResidualStaysInA7
  , testProperty "the commit is byte-exact Q16 (invented coords re-enter the grid with no drift)"
      lawForwardCommitIsQ16
  ]

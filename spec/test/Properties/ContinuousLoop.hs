module Properties.ContinuousLoop (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.ContinuousLoop

tests :: TestTree
tests = testGroup "ContinuousLoop (the live steering loop: steer the latent, preview cheaply, commit on demand)"
  [ testProperty "a tick NEVER commits (latent stays continuous, not the Q16 bytes)" $
      once lawStepNeverCommits
  , testProperty "the identity gesture is a fixpoint (latent and commit invariant)" $
      once lawIdentityGestureIsFixpoint
  , testProperty "the loop closes over T (a full period of no-gesture ticks returns the latent)" $
      once lawLoopClosesOverT
  , testProperty "KEYSTONE: commit invariant under the display decoder (end-to-end quarantine)" $
      once lawCommitInvariantUnderDisplayDecoder
  ]

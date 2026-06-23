module Properties.Sided (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.Sided

-- The real teeth of this module are at COMPILE time (commitS of a DisplaySide value does not
-- type-check). These laws document the legal commit-side path; the quarantine itself is a free
-- theorem of the phantom tag + hidden constructor.
tests :: TestTree
tests = testGroup "Sided (type-enforced quarantine: a display-side float cannot reach the commit)"
  [ testProperty "the commit is a function of the latent alone (a display value cannot appear)" $
      once lawSidedDisplayCannotCommit
  , testProperty "the commit side round-trips (latent -> floor)" $
      once lawSidedCommitRoundTrips
  ]

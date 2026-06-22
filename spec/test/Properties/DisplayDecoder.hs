module Properties.DisplayDecoder (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.DisplayDecoder

tests :: TestTree
tests = testGroup "DisplayDecoder (the L-16³ is a learned, lossy, QUARANTINED view — not the architecture)"
  [ testProperty "KEYSTONE: the commit is quarantined from the display (float preview can't touch the Q16 bytes)" $
      once lawCommitQuarantinedFromDisplay
  , testProperty "the display is a learned decoder-dependent float view (not a canonical projection)" $
      once lawDisplayIsLossyFloat
  , testProperty "steering acts on the latent, so the approximate preview drives a real deterministic commit" $
      once lawSteeringActsOnLatent
  ]

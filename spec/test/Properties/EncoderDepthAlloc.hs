module Properties.EncoderDepthAlloc (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.EncoderDepthAlloc

tests :: TestTree
tests = testGroup "EncoderDepthAlloc (the earned encoder depth — the octant rate-distortion ladder)"
  [ testProperty "the depth ceiling is the octant ladder (64³→4³ = 4 levels = 8⁴ volume), not L=6" $
      once lawDepthCeilingIsOctantLadder
  , testProperty "depth tracks the drained remainder (shallow if detail flattens, capped at 4)" $
      once lawDepthIsDrainedRemainder
  , testProperty "TEETH: a premature cut drops [3584,448,56,7] non-recoverable detail dims" $
      once lawPrematureCutDropsDetail
  ]

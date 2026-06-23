module Properties.Q16 (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.Q16

tests :: TestTree
tests = testGroup "Q16 (the foundational fixed-point quantiser)"
  [ testProperty "quantisation is idempotent on the grid (quantizeQ16 . toQ16 == id)" $
      lawTerminalQuantizationIdempotent
  ]

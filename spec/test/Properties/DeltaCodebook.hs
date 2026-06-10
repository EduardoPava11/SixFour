{- |
Module      : Properties.DeltaCodebook
Description : Property tests for 'SixFour.Spec.DeltaCodebook' — the finite
              127 × 12 = 1524 genome-move vocabulary (root unaddressable).
-}
module Properties.DeltaCodebook (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Test.QuickCheck

import SixFour.Spec.Color         (OKLab(..))
import SixFour.Spec.DeltaCodebook
import SixFour.Spec.PairTree      (HaarPalette(..))
import SixFour.Spec.SigmaPairHead (sigmaPairDepth)

genOKLab :: Gen OKLab
genOKLab = OKLab <$> choose (0, 1) <*> choose (-0.4, 0.4) <*> choose (-0.4, 0.4)

-- | A well-formed DEPTH-7 tree (the vocabulary's home).
genHaar7 :: Gen HaarPalette
genHaar7 = do
  rt   <- genOKLab
  lvls <- mapM (\i -> vectorOf (2 ^ i) genOKLab) [0 .. sigmaPairDepth - 1]
  pure (HaarPalette rt lvls)

tests :: TestTree
tests = testGroup "DeltaCodebook (127 slots x 12 sigma-paired deltas = 1524)"
  [ testProperty "exactly 12 rows, 12 moves per addressable slot" $
      property lawTwelvePerLevel
  , testProperty "adjacent row pairs are sigma-closed (the row-swap mask)" $
      property lawSigmaClosed
  , testProperty "delta magnitude halves per level (exact powers of two)" $
      property lawMagnitudeHalvesPerLevel
  , testProperty "PINNED count: 127 slots (root unaddressable), 1524 moves" $
      property lawVocab1524
  , testProperty "every vocab move preserves well-formedness on depth-7 trees" $
      forAll genHaar7 lawWellFormedPreserving
  , testProperty "out-of-range codebook rows are the zero delta (total)" $
      forAll (choose (0, 6)) $ \lv ->
        deltaAt lv (-1) == OKLab 0 0 0 && deltaAt lv codebookSize == OKLab 0 0 0
  ]

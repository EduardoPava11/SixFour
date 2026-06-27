module Properties.BlindComplementGeometry (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.BlindComplementGeometry

tests :: TestTree
tests = testGroup "BlindComplementGeometry (the precise S^⊥ vs A_7 geometry: distinct, overlap is mean-free blind)"
  [ testProperty "CORE: the checkerboard is in BOTH S^⊥ and A_7 (the overlap)"
      (once lawCheckerboardInBlindAndA7)
  , testProperty "CORRECTION i: S^⊥ ⊄ A_7 (e_0 is blind but Σ=1, refused by A_7)"
      (once lawBlindDirectionOutsideA7)
  , testProperty "CORRECTION ii: A_7 ⊄ S^⊥ (x−y is a legal A_7 residual cellLoss SEES)"
      (once lawA7DirectionSeenByCell)
  , testProperty "CORRECTION iii: dims differ — blind 15, A_7 21, overlap 12"
      (once lawBlindAndA7DimsDiffer)
  , testProperty "CAPSTONE: S^⊥ and A_7 are distinct; overlap is the mean-free blind subspace"
      (once lawBlindMeetsA7InMeanFreeBlind)
  ]

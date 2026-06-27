module Properties.BlindComplementIsA7 (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.BlindComplementIsA7

tests :: TestTree
tests = testGroup "BlindComplementIsA7 (the cell-blind complement IS the mean-free A_7 lattice)"
  [ testProperty "the checkerboard blind direction is mean-free (A_7)"        (once lawCheckerboardIsMeanFree)
  , testProperty "the blind direction is admitted by the MeanFree constructor" (once lawBlindDirectionIsLatticeVector)
  , testProperty "TEETH: a non-lattice (Sigma!=0) direction is refused"       (once lawNonLatticeDirectionRefused)
  , testProperty "CAPSTONE: cellLoss is blind to it AND it is an A_7 residual" (once lawCellBlindComplementIsA7)
  ]

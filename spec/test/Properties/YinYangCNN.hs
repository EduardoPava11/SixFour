module Properties.YinYangCNN (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.YinYangCNN

genVolume :: Gen [Integer]
genVolume = vectorOf 512 (choose (-1000, 1000))

genBlock :: Gen [Integer]
genBlock = vectorOf 8 (choose (-1000, 1000))

genCoefs :: Gen [Integer]
genCoefs = vectorOf 64 (choose (-9, 9))

tests :: TestTree
tests = testGroup "YinYangCNN (yin frozen exact; yang = S only; widths and tying are theorems)"
  [ testGroup "The yin path is frozen exact (zero parameters)"
      [ testProperty "the stride-2 all-ones conv IS the sums carrier (byte-for-byte)" $
          forAll genVolume lawEncoderIsAllOnesConv
      ]

  , testGroup "The yang heads are forced by the algebra"
      [ testProperty "staged detail counts are {1,2,4} summing to 7 = rank A_7, every axis order" $
          once lawStagedExpansionCountsSumToSeven
      , testProperty "x<->y tying by INTEGER symmetrization commutes exactly (any linear head)" $
          forAll genCoefs $ \cs -> forAll genBlock (lawSwapTyingBySymmetrization cs)
      ]
  ]

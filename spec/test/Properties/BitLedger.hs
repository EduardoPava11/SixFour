module Properties.BitLedger (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.BitLedger

tests :: TestTree
tests = testGroup "BitLedger (10-bit signal -> 8-bit GIF: decode-widen, integrate, realize once)"
  [ testGroup "Nothing is lost before the realization"
      [ testProperty "a strictly monotone decode LUT is injective (10->16 widening is lossless)" $
          forAll (resize 64 (listOf1 arbitrary)) lawStrictMonotoneDecodeIsLossless
      , testProperty "pool width is exact: 2^k samples of b bits sum in exactly b+k bits" $
          \k b -> lawPoolSumWidthExact k b
      , testProperty "the u64 carrier holds the worst crop (38 of 63 bits)" $
          once lawU64CarriesTheWorstCrop
      ]

  , testGroup "Pooling GAINS depth; realization spends it once"
      [ testProperty "pooled means have n*(2^b-1)+1 levels — always deeper than one sample" $
          lawPoolingGainsDepth
      , testProperty "shipped ledger pinned: 4096-sample bin of 10-bit = 22 bits; realize drops 14" $
          once lawShippedLedgerPinned
      , testProperty "every 8-bit code is reachable through round-half-up realization" $
          \n v -> lawByteCodesAllReachable n v
      ]
  ]

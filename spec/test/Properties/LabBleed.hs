module Properties.LabBleed (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.LabBleed

genBytes :: Int -> Gen [Integer]
genBytes n = vectorOf n (choose (0, 255))

tests :: TestTree
tests = testGroup "LabBleed (generated Lab equations; scale-dilated distance; bleed -> compression + entropy)"
  [ testGroup "The equations are generated, not asserted"
      [ testProperty "coefficient rows == the opponent function; rendered strings pinned" $
          forAll (genBytes 3) lawOpponentEquationsMatchFunction
      , testProperty "det = 6 = 2*3 (the non-unit 3 boundary, made numeric)" $
          once lawOpponentDetIsSix
      ]

  , testGroup "Variable distance per scale is forced by the carrier"
      [ testProperty "L1 opponent metric dilates by exactly 8 per rung (pool = x8, linear)" $
          forAll (genBytes 6) lawMetricDilatesWithCarrier
      ]

  , testGroup "Bleed generates compression and entropy, exactly"
      [ testProperty "bleeds nest: coarser radius only merges cells, never re-shuffles" $
          forAll arbitrary $ \r -> forAll arbitrary $ \m ->
            forAll (genBytes 6) (lawBleedNestsAcrossScales r m)
      , testProperty "compression: coarser bleed never increases index transitions" $
          forAll arbitrary $ \r -> forAll arbitrary $ \m ->
            forAll (genBytes 48) (lawBleedGeneratesCompression r m)
      , testProperty "entropy ledger: W factorizes exactly across one bleed step" $
          forAll arbitrary $ \r -> forAll arbitrary $ \m ->
            forAll (genBytes 24) (lawBleedGeneratesEntropyLedger r m)
      ]
  ]

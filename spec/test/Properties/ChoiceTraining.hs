module Properties.ChoiceTraining (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.ChoiceTraining

genDepths :: Gen [Int]
genDepths = vectorOf 8 (choose (0, 2))

genVolume :: Gen [Integer]
genVolume = vectorOf (8 * 8 * 8) (choose (0, 255))

tests :: TestTree
tests = testGroup "ChoiceTraining (three GIFs, mixed; the user's choice is the signal)"
  [ testGroup "Arms are free to generate"
      [ testProperty "every mix is a regionwise splice of the three pure GIFs" $
          forAll genDepths $ \ds -> forAll genVolume (lawMixIsRegionwiseSplice ds)
      ]

  , testGroup "Choice is crisp; paint is ambiguous (exactly)"
      [ testProperty "a single-region pair renders byte-identical outside that region" $
          forAll (choose (0, 7)) $ \r -> forAll genDepths $ \ds ->
            forAll (choose (0, 2)) $ \dA -> forAll (choose (0, 2)) $ \dB ->
              forAll genVolume (lawSingleRegionChoiceIsUnambiguous r ds dA dB)
      , testProperty "paint underdetermines depth: 3^8 fields -> 2^8 masks (witness + pigeonhole)" $
          once lawPaintUnderdeterminesDepth
      ]

  , testGroup "Choices identify the field"
      [ testProperty "two comparisons per region recover ANY target field exactly" $
          forAll genDepths lawTournamentIdentifiesField
      ]
  ]

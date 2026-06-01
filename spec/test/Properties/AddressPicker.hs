{- |
Module      : Properties.AddressPicker
Description : Property tests for 'SixFour.Spec.AddressPicker'.

Exercises the EXPORTED laws of the address↔leaf mapping behind the
multi-component @AddressPickerView@. Trees are FULL 256-leaf median-cut trees
(256 = 2^8 → balanced depth-8) — the real palette case the module is specified
for. (Imports the module under test; does not re-implement it.)
-}
module Properties.AddressPicker (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Test.QuickCheck

import SixFour.Spec.Color     (OKLab(..))
import SixFour.Spec.SplitTree
import SixFour.Spec.AddressPicker

-- | 256 distinct-index colours → a full depth-8 median-cut tree (the palette case).
gen256 :: Gen [IndexedColor]
gen256 = do
  cols <- vectorOf 256 genOKLab
  pure (zipWith IndexedColor [0 ..] cols)
  where
    genOKLab = OKLab <$> choose (0, 1) <*> choose (-0.4, 0.4) <*> choose (-0.4, 0.4)

genTree :: Gen SplitTree
genTree = buildSplitTree <$> gen256

genBranching :: Gen Branching
genBranching = elements [B16, B4, B2]

tests :: TestTree
tests = testGroup "AddressPicker (multi-component picker address↔leaf mapping)"
  [ testProperty "address round-trips to its leaf index (full 256-leaf tree)" $
      withMaxSuccess 20 $ forAll genBranching $ \b -> forAll genTree $ \t ->
        lawPickerAddressRoundTrip b t
  , testProperty "addresses are injective (one distinct address per leaf)" $
      withMaxSuccess 20 $ forAll genBranching $ \b -> forAll genTree $ \t ->
        lawAddressInjectivity b t
  , testProperty "every leaf's address has exactly branchDepth digits" $
      withMaxSuccess 20 $ forAll genBranching $ \b -> forAll genTree $ \t ->
        all (\i -> maybe False ((== digitCount b) . length) (addressOfLeafIndex b i t))
            [0 .. length (leaves t) - 1]
  , testProperty "each digit reads a real (axis,pos) split from the tree path" $
      withMaxSuccess 20 $ forAll genBranching $ \b -> forAll genTree $ \t ->
        all (\d -> maybe False (const True) (axisAndPosAtDigit b d t))
            [0 .. digitCount b - 1]
  , testProperty "factor^depth = 256 for every branching (16²/4⁴/2⁸)" $
      once (property lawAddressArithmeticInvariant)
  ]

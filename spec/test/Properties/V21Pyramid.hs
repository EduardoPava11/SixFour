module Properties.V21Pyramid (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.V21Pyramid

-- Raw scalar seeds (the laws clamp them to small level counts / factors / coarse sides) and a raw int
-- list coerced into a legal count field inside each law, exactly as the device fills box*w-mass bins.
genSeed :: Gen Int
genSeed = choose (0, 32)

genField :: Gen [Int]
genField = do
  n <- choose (0, 60)
  vectorOf n (choose (0, 6))

tests :: TestTree
tests = testGroup "V21Pyramid (two-scale spatial field pyramid: 64×64 sub-bins pool to 16×16 bins)"
  [ testProperty "a coarse bin is the block-sum of its sub-bins (defining equation)" $
      forAll genSeed $ \l -> forAll genSeed $ \s -> forAll genSeed $ \f -> forAll genField $
        lawCoarseIsBlockSumOfFine l s f
  , testProperty "KEYSTONE: pooling is transitive (bins == pooled sub-bins, 64->16 == 64->32->16)" $
      forAll genSeed $ \l -> forAll genSeed $ \s -> forAll genField $
        lawPyramidTransitive l s
  , testProperty "mass is conserved (the coarse level adds no observation)" $
      forAll genSeed $ \l -> forAll genSeed $ \s -> forAll genSeed $ \f -> forAll genField $
        lawMassConserved l s f
  , testProperty "local conservation: coarse bin-channel mass == its block's sub-bin masses" $
      forAll genSeed $ \l -> forAll genSeed $ \s -> forAll genSeed $ \f -> forAll genField $
        lawCoarseBinMassIsBlockMass l s f
  , testProperty "the basis is realisable: a coarse mode occurs in some fine sub-bin (gamut-closed)" $
      forAll genSeed $ \l -> forAll genSeed $ \s -> forAll genSeed $ \f -> forAll genField $
        lawCoarseModeIsRealizable l s f
  , testProperty "the fine field is NOT recoverable from the coarse (real context, not redundant)"
      lawFineNotRecoverableFromCoarse
  , testProperty "the pyramid is the capture box one step coarser (matches accumulateHist)"
      lawPoolMatchesAccumulateBoxGrouping
  , testProperty "16×16 = 256 = nLevels: one coarse bin per palette slot"
      lawSixteenIsPaletteBasis
  ]

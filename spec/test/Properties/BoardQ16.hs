{-# LANGUAGE ScopedTypeVariables #-}

module Properties.BoardQ16 (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Test.QuickCheck

import qualified Data.Vector as V

import SixFour.Spec.AtlasBoard (BinIdx(..), OKLabQ16, binIndex)
import SixFour.Spec.BoardQ16

-- The deterministic integer board-mass derivation (M2): closes the float input gap so the
-- policy argmax is cross-device stable. The headline property is order-independence (integer
-- counts), which the float histogram fails; plus a concrete golden pin for the Zig/Swift ports.

genQ16 :: Gen OKLabQ16
genQ16 = (,,) <$> choose (0, q16One - 1)
              <*> choose (negate halfQ16, halfQ16 - 1)
              <*> choose (negate halfQ16, halfQ16 - 1)

genColours :: Gen [OKLabQ16]
genColours = do
  n <- choose (0, 50)
  vectorOf n genQ16

genBin :: Gen BinIdx
genBin = (\i j k -> BinIdx (i, j, k)) <$> choose (0, 15) <*> choose (0, 15) <*> choose (0, 15)

tests :: TestTree
tests = testGroup "BoardQ16 (deterministic integer board-mass derivation — the M2 golden)"

  [ testProperty "binOfQ16 is total: every Q16 colour lands on the board" $
      forAll genQ16 lawBinOfQ16InRange

  , testProperty "binOfQ16 recovers bin centres exactly (pins it to the okLabBin grid)" $
      forAll genBin lawBinQ16RoundTripsCenters

  , testProperty "counts sum to length (every colour counted once)" $
      forAll genColours lawCountsSumToLength

  , testProperty "counts are permutation-invariant vs reverse (lawCountsOrderIndependent)" $
      forAll genColours lawCountsOrderIndependent

  , testProperty "counts are permutation-invariant under ANY shuffle (the determinism property)" $
      forAll genColours $ \cs -> forAll (shuffle cs) $ \cs' ->
        countsQ16 cs' == countsQ16 cs

  , testProperty "Q16 mass is bounded and ~sums to 2^16 (lawMassQ16Bounded)" $
      forAll genColours lawMassQ16Bounded

  , testProperty "GOLDEN: binOfQ16 (40000,1000,-2000) == BinIdx (9,8,7)" $
      once $ binOfQ16 (40000, 1000, -2000) == BinIdx (9, 8, 7)

  , testProperty "GOLDEN: 5 copies of one colour concentrate (count=5, mass=2^16 at its bin)" $
      once $
        let c   = (40000, 1000, -2000) :: OKLabQ16
            ix  = binIndex (BinIdx (9, 8, 7))
            cnt = countsQ16 (replicate 5 c)
            m   = boardMassQ16 (replicate 5 c)
        in cnt V.! ix == 5 && V.sum cnt == 5
           && m V.! ix == q16One && V.sum m == q16One
  ]

module Properties.WeaveOrder (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.WeaveOrder

genRung :: Gen WeaveRung
genRung = elements [W64, W32, W16]

genWord :: Gen WeaveWord
genWord = choose (0, 16 :: Int) >>= \n -> vectorOf n genRung

-- | A pair of words of EQUAL units: pad the shorter with W64 singles.
genEqualUnitWords :: Gen (WeaveWord, WeaveWord)
genEqualUnitWords = do
  a <- genWord
  b <- genWord
  let ua = weaveUnits a
      ub = weaveUnits b
      pad w k = w ++ replicate k W64
  pure ( pad a (max 0 (ub - ua)), pad b (max 0 (ua - ub)) )

genD0 :: Gen Rational
genD0 = do
  p <- choose (1, 100 :: Integer)
  q <- choose (1, 100 :: Integer)
  pure (fromInteger p / fromInteger q)

tests :: TestTree
tests = testGroup "WeaveOrder (the temporal weave: order is the mechanic; the measure cannot see it)"
  [ testGroup "The block arithmetic and the floor bridge"
      [ testProperty "delays match the Zig floor law 320/side (64->5, 32->10, 16->20)" $
          once lawDelayMatchesFloorLaw
      , testProperty "every weave word is GIF89a-representable (per-frame GCE delay)" $
          forAll genWord lawWeaveIsGifRepresentable
      , testProperty "the composition recurrence counts the enumeration" $
          forAll (choose (0, 12)) lawCountMatchesEnumeration
      , testProperty "one 16-frame block has exactly SIX fill orders" $
          once lawBlockHasSixWeaves
      , testProperty "the window's decision space is pinned: 2,610,226,433,308,951 words" $
          once lawWindowWeaveCountPinned
      ]

  , testGroup "Color-time: the three paths are equal"
      [ testProperty "equal-span weaves integrate identical color-time (partition invariance)" $
          forAll genD0 $ \d0 -> forAll genEqualUnitWords $ \(a, b) ->
            lawWeaveColorTimeConserved d0 a b
      , testProperty "pooled-burst and long-shutter paths agree per frame" $
          forAll genD0 lawPartPathsEqualColorTime
      ]

  , testGroup "Order is invisible to the measure — and is therefore the record's job"
      [ testProperty "same multiset => same units, delays, color-time (2:1 vs 1:2 quantified)" $
          forAll genD0 $ \d0 -> forAll genWord $ \w ->
            forAll (shuffle w) $ \w' -> lawOrderIsInvisibleToTheMeasure d0 w w'
      , testProperty "yet distinct orders are real information (witness {32,64,64} has 3)" $
          once lawOrderCarriesInformation
      ]

  , testGroup "Energy: the 16 is palette-exact; the ladder balances"
      [ testProperty "16^2 = 256 = the GCT: dither pressure 1, nothing to invent" $
          once lawCoarsestIsPaletteExact
      , testProperty "dither pressure x color-time factor is rung-invariant (= 16)" $
          once lawDitherPressureBalancesColorTime
      ]

  , testGroup "S/K/I on the rungs (the weave reading of the combinators)"
      [ testProperty "S 16 32 64 -> 16 64 (32 64), verbatim" $
          once lawSExpandsToTheWeaveReading
      , testProperty "S duplicates the fine substrate (1 -> 2 references)" $
          once lawSDuplicatesTheSubstrate
      , testProperty "K keeps the coarse, forgets the fine" $
          once lawKForgetsTheFine
      , testProperty "I is free: passes through, duplicates nothing" $
          once lawIIsFree
      , testProperty "an n-layer S-tower costs exactly 2^n substrate references" $
          once lawSTowerCostsExponential
      ]
  ]

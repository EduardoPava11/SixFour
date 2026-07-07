module Properties.Gif89aDecode (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Data.List (nub, sort)
import Data.Ratio ((%))

import SixFour.Spec.Gif89aDecode

-- A small palette of DISTINCT exact colours.
genPalette :: Gen Palette
genPalette = do
  n  <- choose (1, 16)
  xs <- vectorOf n (choose (0, 255) :: Gen Integer)
  pure (map fromInteger (nub (sort xs)))

genColor :: Gen Color
genColor = do
  n <- choose (0, 4096) :: Gen Integer
  d <- choose (1, 16)   :: Gen Integer
  pure (n % d)

genFine :: Gen [Color]
genFine = choose (0, 32) >>= \n -> vectorOf n genColor

-- Signal in palette-spacing units (interior — no top clamp needed for the recovery laws).
genSig :: Gen Rational
genSig = do
  n <- choose (1, 4096) :: Gen Integer
  d <- choose (1, 256)  :: Gen Integer
  pure (n % d)

genT :: Gen Int
genT = choose (1, 64)

tests :: TestTree
tests = testGroup "Gif89aDecode (3 color-time rungs → index map + per-frame palettes)"
  [ testProperty "PALETTE ← 16² = 256 entries" $ once lawPaletteIsCoarse
  , testProperty "INDEX MAP ← finest: total over the field" $
      forAll genFine $ \fine -> forAll genPalette $ \p -> lawIndexMapIsFine fine p
  , testProperty "NEAREST: chosen index minimises reconstruction error" $
      forAll genPalette $ \p -> forAll genColor $ \c -> lawIndexIsNearest p c
  , testProperty "RANGE: indices are legal palette slots" $
      forAll genPalette $ \p -> forAll genColor $ \c -> lawIndexInRange p c
  , testProperty "PLAYBACK recovers colour beyond 8 bits (Hermite temporal integral)" $
      forAll genSig $ \s -> forAll genT $ \t -> lawGifPlaybackRecovers s t
  , testProperty "EFFECTIVE BITS: playback on 1/T grid ⇒ 8 + log₂T bits" $
      forAll genSig $ \s -> forAll genT $ \t -> lawEffectiveBitsGrid s t
  , testProperty "MIDDLE rung is the dither: 32² = 4·16² (2 bits)" $ once lawMidRungRefines
  , testProperty "CONSERVATION: 64²/16² = 16 = 4² (S = 16·K)" $ once lawSKConservation
  ]

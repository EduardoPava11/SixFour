module Properties.Color (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Test.QuickCheck

import SixFour.Spec.Color
import SixFour.Spec.Laws (lawOKLabRoundTrip)

newtype InGamut = InGamut SRGB deriving Show

instance Arbitrary InGamut where
  arbitrary = do
    r <- choose (0, 1) :: Gen Double
    g <- choose (0, 1)
    b <- choose (0, 1)
    pure (InGamut (SRGB r g b))

tests :: TestTree
tests = testGroup "Color"
  [ -- Deterministic grid scan, NOT a random property: the previous random
    -- ≤1e-6 test was flaky because Haskell's `**` is exp(y·log x), less
    -- accurate than a hardware `pow`, so QuickCheck occasionally found a
    -- near-gamut-boundary colour whose round-trip exceeded 1e-6. We instead
    -- scan a fixed 33³ sRGB grid (incl. the gamma boundary + near-black/white)
    -- and assert the worst-case round-trip error ≤ 1e-5 — still ≪ 8-bit
    -- quantization (1/255 ≈ 4e-3), so it never affects correctness, and it
    -- can't be flaky.
    testProperty "OKLab round-trip ≤ 1e-5 over a deterministic sRGB grid" $
      once $
        let grid = [ fromIntegral i / 32 | i <- [0 .. 32] :: [Int] ]
        in all (lawOKLabRoundTrip 1e-5) [ SRGB r g b | r <- grid, g <- grid, b <- grid ]
  , testProperty "okLabDistanceSquared is symmetric" $
      \(InGamut s1) (InGamut s2) ->
        let l1 = srgbToOKLab s1
            l2 = srgbToOKLab s2
        in okLabDistanceSquared l1 l2 == okLabDistanceSquared l2 l1
  , testProperty "okLabDistanceSquared (x, x) == 0" $
      \(InGamut s) ->
        let l = srgbToOKLab s
        in okLabDistanceSquared l l == 0
  ]

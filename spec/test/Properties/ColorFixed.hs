module Properties.ColorFixed (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.Color      (OKLab(..), SRGB(..), linearSRGBToOKLab, okLabToSRGB)
import SixFour.Spec.ColorFixed (linearToOklabQ16, oklabToSrgb8Q16, q16One, icbrtQ16, isqrtFloor)

toQ :: Double -> Int
toQ x = round (x * fromIntegral q16One)

fromQ :: Int -> Double
fromQ v = fromIntegral v / fromIntegral q16One

tests :: TestTree
tests = testGroup "ColorFixed"
  [ -- The Q16 integer pipeline must track the Double OKLab oracle closely
    -- enough that the difference is perceptually irrelevant (≪ the 1/255 ≈ 4e-3
    -- 8-bit step). Deterministic grid scan (per Properties.Color, random scans
    -- are flaky near the gamut/gamma boundary). The residual is fixed-point
    -- truncation + per-coefficient Q16 rounding + the floor cube root.
    testProperty "Q16 linear→OKLab matches the Double oracle ≤ 5e-3 over a grid" $
      once $
        let grid = [ fromIntegral i / 16 | i <- [0 .. 16] :: [Int] ]
            err (r, g, b) =
              let (lq, aq, bq) = linearToOklabQ16 (toQ r, toQ g, toQ b)
                  OKLab l a bb = linearSRGBToOKLab (r, g, b)
              in maximum [ abs (fromQ lq - l), abs (fromQ aq - a), abs (fromQ bq - bb) ]
        in maximum [ err (r, g, b) | r <- grid, g <- grid, b <- grid ] <= 5e-3

  , -- icbrtQ16 is EXACTLY the integer floor cube root in Q16: with n = x·2^32,
    -- Y = icbrtQ16 x satisfies Y³ ≤ n < (Y+1)³. This is the property the Zig
    -- binary search must reproduce bit-for-bit (no float, no tolerance).
    testProperty "icbrtQ16 is the exact floor cube root (Y³ ≤ x·2^32 < (Y+1)³)" $
      \(NonNegative x') ->
        let x = x' `mod` 131073        -- the clamped input domain [0, 131072]
            y = icbrtQ16 x
            n = x * 4294967296          -- x << 32
        in y * y * y <= n && (y + 1) * (y + 1) * (y + 1) > n

  , -- isqrtFloor is EXACTLY the integer floor square root: Y² ≤ n < (Y+1)².
    -- This is the property the Zig chroma-magnitude helper must reproduce
    -- bit-for-bit. Domain bounded under 2^40 (OKLab Q16 sum-of-squares).
    testProperty "isqrtFloor is the exact floor sqrt (Y² ≤ n < (Y+1)²)" $
      \(NonNegative n') ->
        let n = n' `mod` (1099511627776 :: Int)   -- [0, 2^40)
            y = isqrtFloor n
        in y * y <= n && (y + 1) * (y + 1) > n

  , -- Black → 0, white → ~1.0 in L with ~0 chroma (sign/scale sanity anchors).
    testProperty "black→0, white→L≈1 a≈b≈0" $ once $
      let (lb, ab, bb) = linearToOklabQ16 (0, 0, 0)
          (lw, aw, bw) = linearToOklabQ16 (q16One, q16One, q16One)
      in lb == 0 && ab == 0 && bb == 0
         && abs (lw - q16One) <= 64       -- within ~1e-3 of 1.0
         && abs aw <= 64 && abs bw <= 64

  , -- The inverse (OKLab Q16 → sRGB8 via the gamma LUT) tracks the Double
    -- okLabToSRGB·255 reference to ≤ 2 codes over the grid: fixed-point matmul
    -- truncation + the single LUT round. ≤2/255 is imperceptible and bounded.
    testProperty "Q16 OKLab→sRGB8 matches the Double oracle ≤ 2 codes over a grid" $
      once $
        let grid = [ fromIntegral i / 12 | i <- [0 .. 12] :: [Int] ]
            toByte x = max 0 (min 255 (round (x * 255))) :: Int
            err (r, g, b) =
              let oklab@(lq, aq, bq) = linearToOklabQ16 (toQ r, toQ g, toQ b)
                  (r8, g8, b8) = oklabToSrgb8Q16 oklab
                  SRGB dr dg db = okLabToSRGB (uncurry3 OKLab (fromQ lq, fromQ aq, fromQ bq))
              in maximum [ abs (r8 - toByte dr), abs (g8 - toByte dg), abs (b8 - toByte db) ]
        in maximum [ err (r, g, b) | r <- grid, g <- grid, b <- grid ] <= 2
  ]

uncurry3 :: (a -> b -> c -> d) -> (a, b, c) -> d
uncurry3 f (a, b, c) = f a b c

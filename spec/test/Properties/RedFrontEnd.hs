module Properties.RedFrontEnd (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import qualified Data.Vector.Unboxed as U

import SixFour.Spec.ColorFixed (q16One)
import SixFour.Spec.RedFrontEnd

fromQ :: Int -> Double
fromQ v = fromIntegral v / fromIntegral q16One

tests :: TestTree
tests = testGroup "RedFrontEnd"
  [ -- The decode LUT tracks the Double oracle: entries ARE round(oracle·2^16), so
    -- over a grid the reconstructed value matches to ≤ 1 Q16 (the rounding).
    testProperty "log3g10DecodeLut matches the Double oracle (≤ 1 Q16)" $ once $
      let idxs = [ (i * lutN) `div` 32 | i <- [0 .. 32] ]
          err i = abs (log3g10DecodeLut U.! i - round (log3g10DecodeD (fromIntegral i / fromIntegral lutN) * fromIntegral q16One))
      in maximum (map err idxs) <= 1

  , -- Decode is monotone increasing (more exposure → more light).
    testProperty "log3g10DecodeLut is monotone increasing" $ once $
      and [ log3g10DecodeLut U.! i <= log3g10DecodeLut U.! (i+1) | i <- [0 .. lutN - 1] ]

  , -- 18% mid-gray anchor: encoded ~0.333 decodes to ~0.18 linear.
    testProperty "decode(0.333) ≈ 0.18 (18% gray anchor)" $ once $
      let v = round (0.333 * fromIntegral q16One :: Double) :: Int
      in abs (fromQ (log3g10DecodeSampleQ16 v) - 0.18) <= 0.01

  , -- Filmic LUT: anchors and monotonicity. x=0 → 0; top → ≈ 1.0.
    testProperty "filmic LUT: entry0 == 0, top ≈ q16One, monotone" $ once $
      let mono = and [ filmicTonemapLut U.! i <= filmicTonemapLut U.! (i+1) | i <- [0 .. lutN - 1] ]
      in filmicTonemapLut U.! 0 == 0
         && abs (filmicTonemapLut U.! lutN - q16One) <= 2     -- 1−exp(−32) ≈ 1
         && mono

  , -- filmic LUT vs the Double oracle over a grid (≤ 2 Q16).
    testProperty "filmic LUT matches the Double oracle (≤ 2 Q16)" $ once $
      let xmax = fromIntegral filmicXMaxQ16 / fromIntegral q16One :: Double
          err i = let x = (fromIntegral i / fromIntegral lutN) * xmax
                  in abs (filmicTonemapLut U.! i - round (filmicTonemapD 2.0 x * fromIntegral q16One))
      in maximum [ err ((i * lutN) `div` 48) | i <- [0 .. 48] ] <= 2

  , -- RWG→Rec.709 preserves the neutral axis: each row of the matrix sums to ≈ 1
    -- (D65 white → D65 white). Tolerance a few hundred Q16 (rounding + the small
    -- white-point mismatch in the published constants).
    testProperty "rwgToRec709Q16 rows sum to ≈ q16One (white preserved)" $ once $
      let (a,b,c,d,e,f,g,h,i) = rwgToRec709Q16
          rowsum x y z = abs ((x + y + z) - q16One) <= 400
      in rowsum a b c && rowsum d e f && rowsum g h i

  , -- redDecodeToLinearQ16 anchors: grid black → 0 (decode→neg→clip→tonemap 0);
    -- grid white → ≈ white (decode→huge→tonemap→≈1).
    testProperty "redDecode: (0,0,0)→(0,0,0), (1,1,1)→≈(1,1,1)" $ once $
      let (rb,gb,bb) = redDecodeToLinearQ16 (0, 0, 0)
          (rw,gw,bw) = redDecodeToLinearQ16 (q16One, q16One, q16One)
      in rb == 0 && gb == 0 && bb == 0
         && abs (rw - q16One) <= 2 && abs (gw - q16One) <= 2 && abs (bw - q16One) <= 2

  , -- ★ In-gamut colours are an EXACT fixed point of gamut compression (the
    -- integer reconstruction Y + dev·1 = channel is exact).
    testProperty "gamutCompressQ16 fixes in-gamut colours exactly" $
      forAll genInGamut $ \(r, g, b) ->
        gamutCompressQ16 (r, g, b) == (r, g, b)

  , -- Gamut compression is idempotent and lands in gamut.
    testProperty "gamutCompressQ16 is idempotent and in-gamut" $
      forAll genAnyLinear $ \(r, g, b) ->
        let o1@(r1,g1,b1) = gamutCompressQ16 (r, g, b)
            o2 = gamutCompressQ16 o1
            inGamut v = v >= 0 && v <= q16One
        in o2 == o1 && inGamut r1 && inGamut g1 && inGamut b1

  , -- Black lift raises the floor: lift(0) == blackLiftQ16, lift(white) == white.
    testProperty "applyBlackLiftQ16 raises black, fixes white" $ once $
      applyBlackLiftQ16 (0,0,0) == (blackLiftQ16, blackLiftQ16, blackLiftQ16)
      && applyBlackLiftQ16 (q16One,q16One,q16One) == (q16One,q16One,q16One)
  ]
  where
    genInGamut = do
      r <- choose (0, q16One); g <- choose (0, q16One); b <- choose (0, q16One)
      pure (r, g, b)
    genAnyLinear = do
      r <- choose (negate q16One, 2 * q16One)
      g <- choose (negate q16One, 2 * q16One)
      b <- choose (negate q16One, 2 * q16One)
      pure (r, g, b)

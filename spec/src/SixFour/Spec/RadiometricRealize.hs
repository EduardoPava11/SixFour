{- |
Module      : SixFour.Spec.RadiometricRealize
Description : THE INVERSE-EOTF REALIZATION — closing the linear16 measurement path back to sRGB8 bytes. The measurement pooling kernels ("SixFour.Spec.V21Pyramid" carriers, @s4_pool_sums_linear_srgb8@ / @s4_pool_sums_linear_hlg10@) leave bin sums in LINEAR light on the 65535=1.0 scale; @s4_sums_to_srgb8@ is byte-sum-only and refuses them (ColorHead.swift:160). This module is the missing REALIZATION: area-MEAN each linear16 bin sum (round-half-up over @count@ pixels), then inverse-EOTF ENCODE the linear mean to sRGB8. It is the measurement-path twin of the gamma-byte realization @s4_sums_to_srgb8@ ("SixFour.Spec.FidelityLadder") — same round-half-up mean, differing only by the encode step.

THE ENCODE IS ONE TRANSFER, TWO QUANTIZATIONS. The sRGB transfer 'SixFour.Spec.Color.linearToSRGB' / 'SixFour.Spec.Color.srgbToLinear' is the SINGLE source of truth — 'SixFour.Spec.CubeLut.srgbEncodeLutQ16' quantizes it to Q16 (65536-scale, the .cube output gamma); this module quantizes the SAME function to 8-bit palette codes on the 65535-scale that @palette16.zig@'s decode golden @srgb_to_linear16@ lives on. They are not two encoders — they are two output granularities of one function. The 8-bit realization is pinned by the STRONGEST possible golden: 'lawEncodeInvertsEotf' — encode is the EXACT quantizer-inverse of the decode (@encode (decode v) == v@ for every code), the round-in-ENCODED-space quantizer boundary table (@srgbEncodeThresh16@). This is deliberately NOT round(encode·255) and NOT a binary search of @srgb_to_linear16@ (round-in-linear); the boundary table is the perceptually-correct sRGB quantizer and it round-trips the decode exactly. Zig mirrors @srgbEncodeThresh16@ as a literal golden with spot-check + the round-trip law, the same convention as @srgb_to_linear16@/@hlg_to_linear16@.

PRIMARIES — THE x420 FEED IS BT.2020, NOT sRGB. The live measurement feed (x420, HLG BT.2100) carries linear-light in BT.2020 primaries: ColorHead does the BT.2020 Y'CbCr→R'G'B' conversion and @hlg_to_linear16@ inverts only the HLG TRANSFER, never the gamut. Applying the sRGB OETF to BT.2020 linear and labelling it sRGB8 would mis-hue and over-saturate every non-neutral colour (a BT.2020 primary red would collapse to sRGB 255,0,0). So the x420 realization FIRST applies the exact BT.2020→sRGB(Rec.709) linear 3×3 matrix ('bt2020ToSrgbLinear16', golden Q15 integers), with a deterministic clamp to @[0,65535]@ (in-gamut BT.2020 maps out-of-sRGB-gamut, so the clamp is mandatory, not optional), THEN the sRGB OETF. The matrix rows sum to EXACTLY 32768 in Q15, so the neutral axis is preserved bit-exactly ('lawGrayAxisPreserved') — grey stays grey through the gamut hop. The sRGB-primary feed (@s4_pool_sums_linear_srgb8@) needs no matrix and uses 'realizeSrgbLinearSums' directly.

HONEST BOUNDARY (mirroring "SixFour.Spec.FidelityLadder"): the RATIONAL structure is the law; the byte path rounds once at the end (mean → matrix → clamp → encode). Encoding is NON-LINEAR, so realize does NOT compose across the 64/32/16 rungs — mean-then-encode ≠ encode-then-mean ('lawRealizeIsMeanThenEncode', the measurement-path teeth analogue of @s4_sums_to_srgb8@'s teeth). A reviewer must not "optimize" it to pool-in-encoded-space. And a TONE note: HLG is scene-referred; this realization treats the peak-normalized HLG linear directly as sRGB display-linear (no HLG inverse-OOTF / system-gamma / reference-white(0.75) step). That is a deterministic display-referred TONE-MAP CHOICE, documented like the sRGB-feed 'tone-mapped, accepted' note in @palette16.zig@ — not a claim of colorimetrically-exact HDR→SDR. The primaries and transfer are exact; the HDR luminance mapping is a chosen peak normalization.
-}
-- COMPARTMENT: ZIG-FLOOR | tag:DeviceTag
module SixFour.Spec.RadiometricRealize
  ( -- * The sRGB transfer, quantized to 8-bit palette codes
    srgbDecode16
  , srgbEncodeThresh16
  , linear16ToSrgb8
    -- * Realization of linear16 bin sums
  , meanRoundHalfUp
  , realizeSrgbLinearSums
    -- * BT.2020 → sRGB gamut hop (the x420 primaries fix)
  , bt2020ToSrgbQ15
  , bt2020ToSrgbLinear16
  , realizeBt2020LinearSums
    -- * Laws
  , lawEncodeInvertsEotf
  , lawBlackWhiteEndpoints
  , lawRealizeMonotone
  , lawRealizeIsMeanThenEncode
  , lawGrayAxisPreserved
  , lawBt2020Endpoints
  , lawBt2020InGamut
  ) where

import SixFour.Spec.Color (srgbToLinear)

-- | Full linear16, the top of the 65535=1.0 scale (both inverse EOTFs land here:
-- sRGB code 255 and HLG code 1023 both decode to @linear16Max@).
linear16Max :: Int
linear16Max = 65535

-- | The palette EOTF DECODE (sRGB 8-bit code → scene-linear16), the oracle the
-- Zig literal @srgb_to_linear16@ pins: @round(srgbToLinear(v/255) * 65535)@.
srgbDecode16 :: Int -> Int
srgbDecode16 v = round (srgbToLinear (fromIntegral v / 255) * fromIntegral linear16Max)

-- | The sRGB ENCODE quantizer boundary table: @srgbEncodeThresh16 v@ is the
-- lowest linear16 value that encodes to code @v@ (@thresh 0 = 0@; for @v>=1@,
-- @round(srgbToLinear((v-0.5)/255) * 65535)@ — the round-in-ENCODED-space
-- midpoint). Monotone nondecreasing; Zig mirrors it as a 256-entry literal.
srgbEncodeThresh16 :: Int -> Int
srgbEncodeThresh16 v
  | v <= 0    = 0
  | otherwise = round (srgbToLinear ((fromIntegral v - 0.5) / 255) * fromIntegral linear16Max)

-- | Inverse-EOTF ENCODE: linear16 (clamped to @[0,65535]@) → sRGB 8-bit code =
-- the largest @v@ with @srgbEncodeThresh16 v <= lin@. Round-to-nearest in
-- ENCODED space; the exact quantizer-inverse of 'srgbDecode16'.
linear16ToSrgb8 :: Int -> Int
linear16ToSrgb8 lin =
  let c = max 0 (min linear16Max lin)
  in length (takeWhile (\v -> srgbEncodeThresh16 v <= c) [0 .. 255]) - 1

-- | Round-half-up integer mean of a bin @sum@ over @count@ pixels
-- (@(sum + count`div`2) `div` count@); the same mean @s4_sums_to_srgb8@ uses.
meanRoundHalfUp :: Int -> Int -> Int
meanRoundHalfUp count s = (s + count `div` 2) `div` count

-- | REALIZE a run of sRGB-PRIMARY linear16 bin sums (R,G,B interleaved) to sRGB8
-- bytes: area-mean each channel over @count@ pixels, then 'linear16ToSrgb8'.
-- For feeds whose primaries are already sRGB (@s4_pool_sums_linear_srgb8@); the
-- x420 (BT.2020) feed must use 'realizeBt2020LinearSums'.
realizeSrgbLinearSums :: Int -> [Int] -> [Int]
realizeSrgbLinearSums count = map (linear16ToSrgb8 . meanRoundHalfUp count)

-- | The BT.2020→sRGB(Rec.709) linear 3×3 matrix in Q15 (row-major), derived from
-- the D65 primaries. Each row sums to EXACTLY 32768 (⇒ the neutral axis is a
-- fixed point). Golden: Zig mirrors these nine integers verbatim.
bt2020ToSrgbQ15 :: [Int]
bt2020ToSrgbQ15 =
  [  54411, -19256,  -2387
  ,  -4081,  37123,   -274
  ,   -595,  -3296,  36659 ]

-- | One BT.2020 linear16 triple → sRGB linear16 triple: the Q15 matrix with
-- round-half (floor of @(dot + 16384)`div`32768@) and a deterministic clamp to
-- @[0,65535]@ (in-gamut BT.2020 maps out of the sRGB gamut, so the clamp is
-- mandatory). Grey (@r==g==b@) is preserved bit-exactly by the 32768 row sums.
bt2020ToSrgbLinear16 :: (Int, Int, Int) -> (Int, Int, Int)
bt2020ToSrgbLinear16 (r, g, b) =
  let m = bt2020ToSrgbQ15
      row i = let j = 3 * i
              in max 0 (min linear16Max
                   (((m !! j) * r + (m !! (j + 1)) * g + (m !! (j + 2)) * b + 16384) `div` 32768))
  in (row 0, row 1, row 2)

-- | REALIZE a run of BT.2020 linear16 bin sums (R,G,B interleaved) to sRGB8: per
-- bin, area-mean the three channels over @count@, apply 'bt2020ToSrgbLinear16'
-- (gamut hop + clamp), then 'linear16ToSrgb8' each. The x420 realization.
realizeBt2020LinearSums :: Int -> [Int] -> [Int]
realizeBt2020LinearSums count = go
  where
    go (sr : sg : sb : rest) =
      let (lr, lg, lb) = bt2020ToSrgbLinear16
            (meanRoundHalfUp count sr, meanRoundHalfUp count sg, meanRoundHalfUp count sb)
      in linear16ToSrgb8 lr : linear16ToSrgb8 lg : linear16ToSrgb8 lb : go rest
    go _ = []

-- | KEYSTONE: the encode is the EXACT quantizer-inverse of the decode —
-- @linear16ToSrgb8 (srgbDecode16 v) == v@ for every 8-bit code @v@. This pins
-- the Zig encode table to the SAME transfer as the decode golden (the strongest
-- golden a realization can carry) and is the single-source-of-truth gate.
lawEncodeInvertsEotf :: Int -> Bool
lawEncodeInvertsEotf v0 =
  let v = v0 `mod` 256
  in linear16ToSrgb8 (srgbDecode16 v) == v

-- | Endpoints: black linear16 → code 0, full linear16 → code 255.
lawBlackWhiteEndpoints :: Bool
lawBlackWhiteEndpoints =
  linear16ToSrgb8 0 == 0 && linear16ToSrgb8 linear16Max == 255

-- | The encode is monotone nondecreasing in linear16 (a valid quantizer): the
-- smaller of two linear values never encodes to a larger code.
lawRealizeMonotone :: Int -> Int -> Bool
lawRealizeMonotone a0 b0 =
  let clampL x = max 0 (min linear16Max (abs x))
      lo = min (clampL a0) (clampL b0)
      hi = max (clampL a0) (clampL b0)
  in linear16ToSrgb8 lo <= linear16ToSrgb8 hi

-- | TEETH: realize (mean-then-encode) does NOT compose across rungs — encoding
-- is non-linear, so the linear-mean of a mid-gray bin @{0,65535}@ encodes to 188
-- (@linear16ToSrgb8 32768@), NOT the 128 you get by encoding endpoints then
-- averaging. A reviewer must not pool in encoded space.
lawRealizeIsMeanThenEncode :: Bool
lawRealizeIsMeanThenEncode =
  let meanThenEncode = linear16ToSrgb8 (meanRoundHalfUp 2 (0 + linear16Max))
      encodeThenMean = (linear16ToSrgb8 0 + linear16ToSrgb8 linear16Max) `div` 2
  in meanThenEncode == 188 && encodeThenMean == 127 && meanThenEncode /= encodeThenMean

-- | The neutral axis survives the gamut hop bit-exactly: a grey BT.2020 triple
-- @(L,L,L)@ maps to sRGB @(L,L,L)@ (the Q15 rows sum to 32768).
lawGrayAxisPreserved :: Int -> Bool
lawGrayAxisPreserved l0 =
  let l = max 0 (min linear16Max (abs l0))
  in bt2020ToSrgbLinear16 (l, l, l) == (l, l, l)

-- | BT.2020 gamut-hop endpoints: black→black, full-white→full-white.
lawBt2020Endpoints :: Bool
lawBt2020Endpoints =
  bt2020ToSrgbLinear16 (0, 0, 0) == (0, 0, 0)
    && bt2020ToSrgbLinear16 (linear16Max, linear16Max, linear16Max)
         == (linear16Max, linear16Max, linear16Max)

-- | The gamut hop is TOTAL: every output channel is clamped into @[0,65535]@,
-- so no out-of-sRGB-gamut BT.2020 colour wraps or escapes the range.
lawBt2020InGamut :: Int -> Int -> Int -> Bool
lawBt2020InGamut r0 g0 b0 =
  let c x = max 0 (min linear16Max (abs x))
      (lr, lg, lb) = bt2020ToSrgbLinear16 (c r0, c g0, c b0)
  in all (\x -> x >= 0 && x <= linear16Max) [lr, lg, lb]

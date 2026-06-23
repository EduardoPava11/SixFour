{- |
Module      : SixFour.Spec.RedFrontEnd
Description : The RED-camera front-end of the LUT: REDWideGamutRGB / Log3G10 →
              tonemapped linear Rec.709, in deterministic Q16.

This is the .cube /input/ side. A 3D LUT for grading R3D footage takes coordinates
in RED's Log3G10 / RWGRGB encoding; this module decodes one such Q16 grid
coordinate to tonemapped linear Rec.709 ready for 'SixFour.Spec.ColorFixed.linearToOklabQ16'.
Ported from @~/lut-generator/src/python/{lut_generator,gif_palette_lut}.py@:

  1. per-channel Log3G10 decode  (LUT — the ONLY place @log/10^x@ is evaluated)
  2. RWG → Rec.709 linear matrix  ('rwgToRec709Q16', 9 Q16 constants)
  3. clip negatives to 0          (post-matrix out-of-gamut)
  4. per-channel filmic tonemap   (LUT — the ONLY place @exp@ is evaluated)

== No floats on the runtime path
The two transcendentals are realised as 1-D LUTs ('log3g10DecodeLut',
'filmicTonemapLut') GENERATED here from @Double@ oracles and embedded in the Zig
core as @.bin@ blobs (the @gamma_lut.bin@ pattern). At runtime everything is Q16
integer — byte-exact across devices. 'gamutCompressQ16' and 'applyBlackLiftQ16'
(used by "SixFour.Spec.CubeLut" on the /output/ side) are pure Q16 arithmetic.

== Ordering is load-bearing
Tonemap runs BEFORE OKLab (so values land in [0,1) and the OKLab clamp never
crushes highlights); black-lift runs BEFORE gamut-compress. Both are pinned as
laws. The filmic LUT's 'filmicXMaxQ16' domain constant MUST equal the Zig const.
-}
-- COMPARTMENT: SWIFT-COREAI | tag:DisplaySide
module SixFour.Spec.RedFrontEnd
  ( -- * Double oracles (reference; not on the runtime path)
    log3g10DecodeD
  , filmicTonemapD
  , rwgToRec709D
    -- * Constants
  , lutN
  , filmicExposureQ16
  , filmicXMaxQ16
  , blackLiftQ16
  , rwgToRec709Q16
    -- * Generated Q16 LUTs (emitted as .bin, embedded in Zig)
  , log3g10DecodeLut
  , filmicTonemapLut
    -- * Q16 runtime helpers
  , log3g10DecodeSampleQ16
  , filmicTonemapSampleQ16
  , redDecodeToLinearQ16
  , gamutCompressQ16
  , applyBlackLiftQ16
  ) where

import qualified Data.Vector.Unboxed as U

import SixFour.Spec.ColorFixed (q16One)

-- ===========================================================================
-- Double oracles (reference only — used to GENERATE the LUTs + matrix constants)
-- ===========================================================================

log3g10A, log3g10B, log3g10C, log3g10LinSlope, log3g10LinOffset :: Double
log3g10A         = 0.224282       -- logSideSlope
log3g10B         = 155.975327     -- linSideSlope
log3g10C         = 0.01           -- linSideOffset seed
log3g10LinSlope  = 15.1927        -- linear-extension slope
log3g10LinOffset = log3g10B * log3g10C + 1.0   -- = 2.5597…

-- | Log3G10 DECODE (encoded → linear), RED White Paper Rev-B. For our @[0,1]@
-- grid the @V ≥ 0@ log branch dominates; the @V < 0@ linear extension is kept
-- for completeness.
log3g10DecodeD :: Double -> Double
log3g10DecodeD v
  | v < 0     = v / log3g10LinSlope - log3g10C
  | otherwise = (10 ** (v / log3g10A) - log3g10LinOffset) / log3g10B

-- | Filmic tonemap @1 − exp(−exposure·x)@ for @x > 0@, else @0@ (python
-- @np.where(x>0, …, 0)@). @exposure@ is a real (e.g. 2.0).
filmicTonemapD :: Double -> Double -> Double
filmicTonemapD exposure x
  | x > 0     = 1 - exp (negate exposure * x)
  | otherwise = 0

-- REDWideGamutRGB → CIE XYZ (D65) and XYZ → Rec.709 (D65), from the RED white
-- paper / OCIO. The shipped matrix is their COMPOSITION at full precision.
rwgToXyzD :: [[Double]]
rwgToXyzD =
  [ [  0.735275,  0.068609,  0.146571 ]
  , [  0.286694,  0.842979, -0.129673 ]
  , [ -0.079681, -0.347343,  1.516082 ] ]

xyzToRec709D :: [[Double]]
xyzToRec709D =
  [ [  3.2404542, -1.5371385, -0.4985314 ]
  , [ -0.9692660,  1.8760108,  0.0415560 ]
  , [  0.0556434, -0.2040259,  1.0572252 ] ]

-- | RWG → Rec.709 linear, composed at full @Double@ precision (NOT two separate
-- Q16 roundings — that would double-round). Row-major 3×3.
rwgToRec709D :: [[Double]]
rwgToRec709D = matMul xyzToRec709D rwgToXyzD
  where
    matMul a b = [ [ sum [ a !! i !! k * b !! k !! j | k <- [0..2] ] | j <- [0..2] ] | i <- [0..2] ]

-- ===========================================================================
-- Constants
-- ===========================================================================

-- | LUT length−1. The decode LUT is indexed DIRECTLY by the Q16 encoded value
-- (so @lutN == q16One@); both LUTs have @lutN + 1@ entries (the @gamma_lut@
-- convention).
lutN :: Int
lutN = q16One

-- | Filmic exposure in Q16 (python @FILMIC_EXPOSURE = 2.0@). The @Double@
-- generator uses @2.0@ directly; this is exported for the contract.
filmicExposureQ16 :: Int
filmicExposureQ16 = 2 * q16One

-- | Filmic LUT input-domain cap (linear light), Q16. At @x = 16@, @1−exp(−32) ≈ 1@,
-- so any larger input clamps to the top entry. The Zig sampler MUST divide by the
-- byte-identical constant.
filmicXMaxQ16 :: Int
filmicXMaxQ16 = 16 * q16One

-- | Black lift (python @BLACK_LIFT = 0.008@) in Q16: @out = lift + v·(1−lift)@.
blackLiftQ16 :: Int
blackLiftQ16 = round (0.008 * fromIntegral q16One :: Double)

-- Rec.709 luminance weights, Q16.
lumaR, lumaG, lumaB :: Int
lumaR = round (0.2126 * fromIntegral q16One :: Double)
lumaG = round (0.7152 * fromIntegral q16One :: Double)
lumaB = round (0.0722 * fromIntegral q16One :: Double)

-- | RWG → Rec.709 as nine Q16 constants (row-major), rounded from the COMPOSED
-- @Double@ matrix 'rwgToRec709D'. The SAME nine literals are hard-coded in
-- @Native/src/kernels.zig@.
rwgToRec709Q16 :: (Int, Int, Int, Int, Int, Int, Int, Int, Int)
rwgToRec709Q16 =
  let m = rwgToRec709D
      e i j = round ((m !! i !! j) * fromIntegral q16One :: Double)
  in ( e 0 0, e 0 1, e 0 2
     , e 1 0, e 1 1, e 1 2
     , e 2 0, e 2 1, e 2 2 )

-- ===========================================================================
-- Generated Q16 LUTs (the .bin blobs)
-- ===========================================================================

-- | Log3G10 decode LUT: entry @i@ is @round(log3g10DecodeD (i/lutN) · 2^16)@,
-- @i ∈ [0, lutN]@. SIGNED (slightly negative near 0; large positive near 1).
log3g10DecodeLut :: U.Vector Int
log3g10DecodeLut = U.generate (lutN + 1) $ \i ->
  let v = fromIntegral i / fromIntegral lutN :: Double
  in round (log3g10DecodeD v * fromIntegral q16One)

-- | Filmic tonemap LUT: entry @i@ is @round(filmicTonemapD 2.0 (x) · 2^16)@ where
-- @x = (i/lutN)·filmicXMax@, @i ∈ [0, lutN]@. Monotone in @[0, q16One)@.
filmicTonemapLut :: U.Vector Int
filmicTonemapLut = U.generate (lutN + 1) $ \i ->
  let x = (fromIntegral i / fromIntegral lutN) * (fromIntegral filmicXMaxQ16 / fromIntegral q16One) :: Double
  in round (filmicTonemapD 2.0 x * fromIntegral q16One)

-- ===========================================================================
-- Q16 runtime helpers
-- ===========================================================================

-- | Sample the decode LUT at a Q16 encoded value @v ∈ [0, q16One]@ (index =
-- @clamp 0 lutN v@, since @lutN == q16One@).
log3g10DecodeSampleQ16 :: Int -> Int
log3g10DecodeSampleQ16 v = log3g10DecodeLut U.! max 0 (min lutN v)

-- | Sample the filmic LUT at a Q16 linear value @x ≥ 0@. Index =
-- @clamp 0 lutN ((x·lutN) `quot` filmicXMaxQ16)@ (needs i64 in Zig). @x ≤ 0 → 0@.
filmicTonemapSampleQ16 :: Int -> Int
filmicTonemapSampleQ16 x
  | x <= 0    = 0
  | otherwise = filmicTonemapLut U.! max 0 (min lutN ((x * lutN) `quot` filmicXMaxQ16))

-- | Decode one Q16 RWG/Log3G10 grid coordinate to tonemapped linear Rec.709 Q16
-- (in @[0, q16One)@): Log3G10 decode → RWG→Rec.709 matrix → clip negatives →
-- filmic tonemap. Matrix intermediates are i64.
redDecodeToLinearQ16 :: (Int, Int, Int) -> (Int, Int, Int)
redDecodeToLinearQ16 (vr, vg, vb) =
  let lr = log3g10DecodeSampleQ16 vr
      lg = log3g10DecodeSampleQ16 vg
      lb = log3g10DecodeSampleQ16 vb
      (m00, m01, m02, m10, m11, m12, m20, m21, m22) = rwgToRec709Q16
      r0 = (m00 * lr + m01 * lg + m02 * lb) `quot` q16One
      g0 = (m10 * lr + m11 * lg + m12 * lb) `quot` q16One
      b0 = (m20 * lr + m21 * lg + m22 * lb) `quot` q16One
      rc = max 0 r0
      gc = max 0 g0
      bc = max 0 b0
  in (filmicTonemapSampleQ16 rc, filmicTonemapSampleQ16 gc, filmicTonemapSampleQ16 bc)

-- | Luminance-preserving gamut compression (python @gamut_compress@) on linear
-- Rec.709 Q16. In-gamut input is an EXACT fixed point.
gamutCompressQ16 :: (Int, Int, Int) -> (Int, Int, Int)
gamutCompressQ16 (r, g, b) =
  let yRaw = (lumaR * r + lumaG * g + lumaB * b) `quot` q16One
      y    = max 1 yRaw
      devR = r - y
      devG = g - y
      devB = b - y
      scaleFor dev
        | dev > 0   = ((q16One - y) * q16One) `quot` dev
        | dev < 0   = (y * q16One) `quot` negate dev
        | otherwise = q16One
      sc0 = minimum [q16One, scaleFor devR, scaleFor devG, scaleFor devB]
      sc  = max 0 (min q16One sc0)
      out dev = clamp01 (y + (dev * sc) `quot` q16One)
  in (out devR, out devG, out devB)
  where clamp01 v = max 0 (min q16One v)

-- | Black lift on linear Rec.709 Q16: @out = lift + v·(1 − lift)@ (raises the
-- floor for a faded-film feel). Applied BEFORE 'gamutCompressQ16'.
applyBlackLiftQ16 :: (Int, Int, Int) -> (Int, Int, Int)
applyBlackLiftQ16 (r, g, b) = (lift r, lift g, lift b)
  where lift v = blackLiftQ16 + (v * (q16One - blackLiftQ16)) `quot` q16One

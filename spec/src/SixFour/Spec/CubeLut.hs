{- |
Module      : SixFour.Spec.CubeLut
Description : The N³ .cube grid builder — the EXPORT projection of a look.

Samples the shared look transform on an N³ grid in RED Log3G10 / RWGRGB space and
emits palette-styled Rec.709 (sRGB-gamma) values — the @.cube@ LUT a colourist
loads onto an R3D clip. The per-voxel pipeline (python @gif_palette_lut.build_lut@,
ported to OKLab + Q16):

  Log3G10/RWG grid coord ('cubeGridCoordQ16')
    → tonemapped linear Rec.709  ('SixFour.Spec.RedFrontEnd.redDecodeToLinearQ16')
    → OKLab                      ('SixFour.Spec.ColorFixed.linearToOklabQ16')
    → LOOK transfer              ('SixFour.Spec.LookTransfer.transferOklabQ16')  ← same as preview
    → linear sRGB                ('SixFour.Spec.ColorFixed.oklabToLinearSRGBQ16')
    → black lift                 ('SixFour.Spec.RedFrontEnd.applyBlackLiftQ16')
    → gamut compress             ('SixFour.Spec.RedFrontEnd.gamutCompressQ16')
    → sRGB gamma encode (Q16)    ('srgbEncodeSampleQ16')

== Ordering (load-bearing)
Tonemap precedes OKLab; black-lift precedes gamut-compress. The @.cube@ scan
order is R-fastest, then G, then B (the index @bi·n² + gi·n + ri@) — pinned as a
law so the LUT never ships R/B-swapped.

== Output precision
Voxels are Q16 sRGB-encoded (via 'srgbEncodeLutQ16', a 16-bit sibling of
@gamma_lut@), formatted to 6 decimals in the @.cube@ — banding-free, unlike an
8-bit table.
-}
-- COMPARTMENT: SWIFT-COREAI | tag:DisplaySide
module SixFour.Spec.CubeLut
  ( cubeSizeDefault
  , cubeSizeGolden
  , srgbEncodeLutQ16
  , srgbEncodeSampleQ16
  , cubeGridCoordQ16
  , cubeVoxelQ16
  , buildCubeQ16
  ) where

import qualified Data.Vector.Unboxed as U

import SixFour.Spec.Color       (linearToSRGB)
import SixFour.Spec.ColorFixed  (q16One, linearToOklabQ16, oklabToLinearSRGBQ16)
import SixFour.Spec.ZoneProfile (ZoneProfileQ16)
import SixFour.Spec.LookTransfer (TransferParamsQ16, transferOklabQ16)
import SixFour.Spec.RedFrontEnd  (redDecodeToLinearQ16, gamutCompressQ16, applyBlackLiftQ16)

-- | Shipped cube size (python @LUT_SIZE = 65@).
cubeSizeDefault :: Int
cubeSizeDefault = 65

-- | Golden cube size — small enough to byte-check the WHOLE grid (5³ = 125).
cubeSizeGolden :: Int
cubeSizeGolden = 5

-- | sRGB ENCODE LUT (linear Q16 → sRGB-encoded Q16). The cube's output gamma; a
-- 16-bit sibling of @gamma_lut@ for 6-decimal precision. Embedded in Zig.
srgbEncodeLutQ16 :: U.Vector Int
srgbEncodeLutQ16 = U.generate (q16One + 1) $ \i ->
  let lin = fromIntegral i / fromIntegral q16One :: Double
      e   = linearToSRGB lin
  in max 0 (min q16One (round (e * fromIntegral q16One)))

-- | Sample the sRGB-encode LUT at a linear Q16 value (index clamped to @[0, q16One]@).
srgbEncodeSampleQ16 :: Int -> Int
srgbEncodeSampleQ16 lin = srgbEncodeLutQ16 U.! max 0 (min q16One lin)

-- | The Q16 RWG/Log3G10 grid coordinate of cube index @(ri, gi, bi)@ in an N³
-- cube: each channel is @i/(n-1)@ in Q16 (so 0 at index 0, @q16One@ at @n-1@).
cubeGridCoordQ16 :: Int -> (Int, Int, Int) -> (Int, Int, Int)
cubeGridCoordQ16 n (ri, gi, bi)
  | n <= 1    = (0, 0, 0)
  | otherwise = (coord ri, coord gi, coord bi)
  where coord i = (i * q16One) `quot` (n - 1)

-- | One voxel: the full per-voxel pipeline. Output is a Q16 sRGB-encoded triple
-- in @[0, q16One]@.
cubeVoxelQ16 :: TransferParamsQ16 -> ZoneProfileQ16 -> Int -> (Int, Int, Int) -> (Int, Int, Int)
cubeVoxelQ16 params zp n idx =
  let coord      = cubeGridCoordQ16 n idx
      lin        = redDecodeToLinearQ16 coord
      oklab      = linearToOklabQ16 lin
      graded     = transferOklabQ16 params zp oklab     -- ← the SAME transform the preview uses
      linOut     = oklabToLinearSRGBQ16 graded
      lifted     = applyBlackLiftQ16 linOut
      (cr, cg, cb) = gamutCompressQ16 lifted
  in (srgbEncodeSampleQ16 cr, srgbEncodeSampleQ16 cg, srgbEncodeSampleQ16 cb)

-- | The whole cube as Q16 sRGB-encoded triples in @.cube@ order (R fastest, then
-- G, then B — element at index @bi·n² + gi·n + ri@).
buildCubeQ16 :: TransferParamsQ16 -> ZoneProfileQ16 -> Int -> [(Int, Int, Int)]
buildCubeQ16 params zp n =
  [ cubeVoxelQ16 params zp n (ri, gi, bi)
  | bi <- [0 .. n - 1], gi <- [0 .. n - 1], ri <- [0 .. n - 1] ]

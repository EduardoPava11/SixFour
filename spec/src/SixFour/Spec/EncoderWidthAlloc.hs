{- |
Module      : SixFour.Spec.EncoderWidthAlloc
Description : The EARNED encoder channel widths — the fixed 512-channel waist PARTITIONED across the three modalities by their entropy-share ("SixFour.Spec.EncoderModalityLoad"), via the Hamilton largest-remainder method so the split sums to EXACTLY 512 (so @lawFuseIsMidpoint@ survives). No channel count chosen; each is the integer entropy share.

The widths are not hyperparameters — they are a deterministic function of the three commensurable
loads. `largestRemainder` floors the ideal real-valued counts and hands the leftover units to the
modalities with the largest fractional parts, so:

  * 'lawWidthsSumToDModel' — the widths sum to EXACTLY @vitDModel = 512@ for ANY loads, so the
    partition preserves the @lawFuseIsMidpoint@ waist (@64·512 = 32768 = 32³@). TEETH: naive
    per-modality @round@ on a @(⅓,⅓,⅓)@ tie sums to **513** — off by one, breaking the waist.
  * 'lawEncoderWidthIsEntropyShare' — the widths follow the load order (a bigger entropy load earns
    a bigger width); a uniform split does not.
  * 'lawUniformWidthWastesOnGreyscale' — a clip whose palette load is small (greyscale, low colour
    rank) earns a palette width BELOW the uniform @512/3@; the freed channels go to index/perceptual.
  * 'lawColourfulPaletteEarnsMoreWidthThanGreyscale' — ties to "SixFour.Spec.EncoderModalityLoad":
    with the index/perceptual bands held fixed, a full-gamut palette earns strictly more palette
    channels than a greyscale one — the encoder capacity literally follows the colour.

GHC-boot-only; re-pins nothing. Laws QuickCheck'd in "Properties.EncoderWidthAlloc".
-}
-- COMPARTMENT: MLX-MODEL | tag:MacTag
module SixFour.Spec.EncoderWidthAlloc
  ( -- * The earned allocation
    largestRemainder
  , encoderWidths
    -- * Laws (QuickCheck'd in @Properties.EncoderWidthAlloc@)
  , lawWidthsSumToDModel
  , lawEncoderWidthIsEntropyShare
  , lawUniformWidthWastesOnGreyscale
  , lawColourfulPaletteEarnsMoreWidthThanGreyscale
  ) where

import Data.List (sortBy)
import Data.Ord  (comparing, Down(..))

import SixFour.Spec.Color             (OKLab(..))
import SixFour.Spec.HalfwayLatent     (vitDModel)
import SixFour.Spec.EncoderModalityLoad (modalityLoads)

-- | Hamilton largest-remainder apportionment: split @total@ units across the modalities in
-- proportion to non-negative weights @ws@, summing to EXACTLY @total@. Floor the ideal counts,
-- then give the @total − Σfloor@ leftover units (always @0 ≤ … < length ws@) to the largest
-- fractional parts.
largestRemainder :: Int -> [Double] -> [Int]
largestRemainder total ws
  | n == 0    = []
  | otherwise =
      let s       = sum ws
          shares  = if s <= 0 then replicate n (1 / fromIntegral n) else map (/ s) ws
          exact   = map (* fromIntegral total) shares
          floors  = map (floor :: Double -> Int) exact
          deficit = max 0 (total - sum floors)
          fracs   = zipWith (\e f -> e - fromIntegral f) exact floors
          winners = take deficit (map snd (sortBy (comparing (Down . fst)) (zip fracs [0 :: Int ..])))
      in [ (floors !! i) + (if i `elem` winners then 1 else 0) | i <- [0 .. n - 1] ]
  where n = length ws

-- | The earned @(index, palette, perceptual)@ channel widths: the three loads apportioned over
-- the fixed @vitDModel = 512@ waist.
encoderWidths :: (Double, Double, Double) -> (Int, Int, Int)
encoderWidths (i, p, c) =
  case largestRemainder vitDModel [i, p, c] of
    [wi, wp, wc] -> (wi, wp, wc)
    _            -> (0, 0, 0)

-- =============================================================================
-- Laws
-- =============================================================================

-- | The widths sum to EXACTLY @vitDModel@ for any loads — the partition preserves the waist.
-- TEETH: naive per-modality @round@ on a @(⅓,⅓,⅓)@ tie sums to 513, breaking @lawFuseIsMidpoint@.
lawWidthsSumToDModel :: Bool
lawWidthsSumToDModel =
     all (\ws -> sum (largestRemainder vitDModel ws) == vitDModel)
         [ [1,1,1], [3,2,1], [10,0,0], [0.1,0.2,0.7], [5,5,5,5,5], [0,0,0] ]
  && sum [ round (w * fromIntegral vitDModel) :: Int | w <- [1/3, 1/3, 1/3 :: Double] ] /= vitDModel
  -- ^ the naive method gives 171+171+171 = 513 ≠ 512

-- | The widths follow the entropy-load order: a bigger load earns a bigger width.
lawEncoderWidthIsEntropyShare :: Bool
lawEncoderWidthIsEntropyShare =
  let (wi, wp, wc) = encoderWidths (10, 100, 50)   -- palette > perceptual > index by load
  in wp > wc && wc > wi && wp - wi >= 100          -- thick margin: no near-uniform allocator passes

-- | A small palette load (greyscale / low colour rank) earns a palette width BELOW the uniform
-- @512/3@ — the entropy allocation refuses to waste channels on a rank-deficient colour set.
lawUniformWidthWastesOnGreyscale :: Bool
lawUniformWidthWastesOnGreyscale =
  let (_, wp, _) = encoderWidths (100, 5, 100)   -- index & perceptual rich, palette tiny
  in wp < vitDModel `div` 3

-- | TIE TO THE LOADS: with the index/perceptual bands held fixed, a full-gamut palette earns
-- strictly more palette-encoder channels than a greyscale one — capacity follows the colour.
lawColourfulPaletteEarnsMoreWidthThanGreyscale :: Bool
lawColourfulPaletteEarnsMoreWidthThanGreyscale =
  let band    = [0,1,1,2,0,1,3,0]
      grey    = [(OKLab 0 0 0, 1), (OKLab 80 0 0, 1)]
      colour  = [(OKLab 0 0 0, 1), (OKLab 80 60 40, 1), (OKLab 30 70 20, 1)]
      (_, wpGrey,   _) = encoderWidths (modalityLoads band grey   band)
      (_, wpColour, _) = encoderWidths (modalityLoads band colour band)
  in wpColour > wpGrey

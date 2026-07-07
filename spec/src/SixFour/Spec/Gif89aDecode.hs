{- |
Module      : SixFour.Spec.Gif89aDecode
Description : DECODING THE THREE COLOR-TIME RUNGS INTO GIF89a PRIMITIVES — the ladder's three resolutions are ingredients with different color-time, and they factor EXACTLY into the two things a GIF89a frame is made of: a per-frame PALETTE (a Local Color Table, ≤256 colours) and an INDEX MAP (one 8-bit code per pixel). The color-time-RICHEST rung is the palette (colour needs fidelity, not resolution); the FINEST rung is the index map (spatial detail, not colour); the MIDDLE rung is the per-frame palette DITHER (the sub-palette refinement spread across frames, "SixFour.Spec.EventEncoding"). Playing the GIF back is the temporal integral — the color-time decode ("SixFour.Spec.ColorTime") — and it recovers colour BEYOND the 8-bit palette.

THE FACTORIZATION (space × space × time → palette + indices).
  * PALETTE ← 16² (256 cells, MAX color-time). The coarse rung has exactly 256 cells = a palette, and at that scale the construction and perceptual encoders coincide ("SixFour.Spec.CoarseIsPalette"). Highest τ_c ⇒ lowest chromatic noise ⇒ the codebook is where fidelity must live.
  * INDEX MAP ← 64² (4096 cells, MIN color-time, MAX spatial). Each finest pixel is quantised to its NEAREST palette entry ('lawIndexIsNearest') — an 8-bit code, no colour of its own. Spatial detail lives here.
  * PER-FRAME DITHER ← 32² (1024 cells = 4×256, MID). The middle rung carries @32²/16² = 4 = 2@ bits of sub-palette colour ('lawMidRungRefines'); spread over the frames it becomes the per-frame palette variation. GIF89a's Local Color Tables ARE a temporal-dither codebook.

PLAYBACK IS THE COLOR-TIME DECODE. Encode a fine colour @s@ (in palette-spacing units) across @T@ frames by ordered dither — the per-frame index is @⌊s + i/T⌋@ — and the GIF PLAYBACK (the temporal mean the eye/integration performs) is @decodeMean@, which by Hermite's identity recovers @s@ to @1/T@ of the palette spacing ('lawGifPlaybackRecovers'). The decode lands on the @1/T@-refined grid ('lawEffectiveBitsGrid'): the 256-entry palette (8 bits) plus @T@-frame temporal dither yields @8 + log₂T@ effective bits — for the shipped @T=64@ burst, FOURTEEN-bit colour out of GIF89a's 8-bit primitives. The 8 bits are the palette; the extra @log₂T@ are color-time.

CONSERVATION. @64² / 16² = 16 = 4²@ ('lawSKConservation'): the space-per-colour ratio is the SQUARE of the finest→palette pooling factor — the same ideal-norm arithmetic as "SixFour.Spec.GaussianLadder" (the index grid is @4²@ finer than the palette). Pixels (S) and palette (K) split as @S = 16·K@. Pure-spec; exact @Rational@ / @Integer@, reusing "SixFour.Spec.EventEncoding".
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none
module SixFour.Spec.Gif89aDecode
  ( -- * GIF89a primitives
    Color
  , Palette
  , IndexMap
  , paletteCells
  , indexCells
  , midCells
    -- * The decode
  , nearestIndex
  , quantizeToPalette
  , reconstruct
  , gifIndexStack
  , gifPlayback
    -- * Laws
  , lawPaletteIsCoarse
  , lawIndexMapIsFine
  , lawIndexIsNearest
  , lawIndexInRange
  , lawGifPlaybackRecovers
  , lawEffectiveBitsGrid
  , lawMidRungRefines
  , lawSKConservation
  ) where

import Data.Ratio (denominator)

import SixFour.Spec.EventEncoding (encodeEvent, decodeMean)

-- | A colour as an exact scalar intensity in palette-spacing units (the per-channel
-- generalisation is a trivial product of three of these).
type Color = Rational

-- | A GIF89a colour table: an ordered list of ≤256 colours (a Local Color Table per frame).
type Palette = [Color]

-- | A GIF89a index map: one palette index per pixel.
type IndexMap = [Int]

-- | Palette entries = @16² = 256@ (the coarse rung; the codebook, MAX color-time).
paletteCells :: Int
paletteCells = 16 * 16

-- | Index-map cells = @64² = 4096@ (the finest rung; spatial detail, MIN color-time).
indexCells :: Int
indexCells = 64 * 64

-- | Middle-rung cells = @32² = 1024 = 4·256@ (the per-frame dither budget, 2 bits).
midCells :: Int
midCells = 32 * 32

-- | The nearest palette entry to a colour (argmin @|c − pⱼ|@; ties to the lower index).
nearestIndex :: Palette -> Color -> Int
nearestIndex pal c = snd (minimum [ (abs (c - p), i) | (p, i) <- zip pal [0 ..] ])

-- | Quantise a field of fine colours to palette indices — the INDEX MAP of one frame.
quantizeToPalette :: Palette -> [Color] -> IndexMap
quantizeToPalette pal = map (nearestIndex pal)

-- | Reconstruct colours from a palette + index map (the per-pixel table lookup a decoder does).
reconstruct :: Palette -> IndexMap -> [Color]
reconstruct pal = map (pal !!)

-- | The per-frame index STACK for one fine colour @s@ over @T@ frames: ordered dither
-- @[⌊s + i/T⌋]@ — the temporal-dither codebook realised as GIF frames ("SixFour.Spec.EventEncoding").
gifIndexStack :: Color -> Int -> [Integer]
gifIndexStack = encodeEvent

-- | GIF PLAYBACK = the temporal mean of the index stack = the color-time integral / decode.
gifPlayback :: [Integer] -> Int -> Rational
gifPlayback = decodeMean

-- ─────────────────────────────────────────────────────────────────────────────
-- Laws
-- ─────────────────────────────────────────────────────────────────────────────

-- | PALETTE ← 16²: the palette has exactly @16² = 256@ entries (the coarse rung is the codebook,
-- delegated to "SixFour.Spec.CoarseIsPalette").
lawPaletteIsCoarse :: Bool
lawPaletteIsCoarse = paletteCells == 256 && paletteCells == 16 * 16

-- | INDEX MAP ← finest: one index per finest pixel — the map is total over the 64² field.
lawIndexMapIsFine :: [Color] -> Palette -> Bool
lawIndexMapIsFine fine pal =
  null pal || length (quantizeToPalette pal fine) == length fine

-- | NEAREST: the chosen index minimises the reconstruction error over all palette entries.
lawIndexIsNearest :: Palette -> Color -> Bool
lawIndexIsNearest pal c =
  null pal || let i = nearestIndex pal c
              in all (\p -> abs (c - pal !! i) <= abs (c - p)) pal

-- | RANGE: every index is a legal palette slot @[0, |palette|)@.
lawIndexInRange :: Palette -> Color -> Bool
lawIndexInRange pal c =
  null pal || let i = nearestIndex pal c in i >= 0 && i < length pal

-- | PLAYBACK RECOVERS BEYOND 8 BITS: the per-frame dithered index stack, played back (temporal
-- mean = color-time), recovers @s@ to @1/T@ of the PALETTE spacing — colour finer than the
-- 256-entry codebook can hold. (Hermite, via "SixFour.Spec.EventEncoding".)
lawGifPlaybackRecovers :: Color -> Int -> Bool
lawGifPlaybackRecovers s t
  | t <= 0    = True
  | otherwise = let d = s - gifPlayback (gifIndexStack s t) t
                in d >= 0 && d * fromIntegral t < 1

-- | EFFECTIVE BITS: playback lands on the @1/T@-refined grid, so 256 palette entries + @T@
-- dither frames give @256·T@ levels = @8 + log₂T@ bits (T=64 ⇒ 14-bit colour from 8-bit GIF).
lawEffectiveBitsGrid :: Color -> Int -> Bool
lawEffectiveBitsGrid s t =
  t <= 0 || (fromIntegral t `mod` denominator (gifPlayback (gifIndexStack s t) t) == (0 :: Integer))

-- | MIDDLE RUNG IS THE DITHER: @32² = 4·16²@ — the mid rung carries exactly 2 bits of
-- sub-palette colour, the per-frame palette refinement budget.
lawMidRungRefines :: Bool
lawMidRungRefines = midCells == 4 * paletteCells

-- | CONSERVATION: @64²/16² = 16 = 4²@ — the space-per-colour ratio is the SQUARE of the
-- finest→palette pooling factor (the "SixFour.Spec.GaussianLadder" ideal norm). @S = 16·K@.
lawSKConservation :: Bool
lawSKConservation = indexCells `div` paletteCells == 16 && indexCells == 16 * paletteCells

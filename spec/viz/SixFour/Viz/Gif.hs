{-# LANGUAGE ScopedTypeVariables #-}
{- |
Module      : SixFour.Viz.Gif
Description : Bridge the look-NN spec types to animated, palettized GIFs (JuicyPixels).

The medium is the proof. A 'LookInput' is /already/ a list of frames each with its own
256-colour palette and its own index map — exactly the shape of JuicyPixels'
@encodeGifImages :: GifLooping -> [(Palette, GifDelay, Image Pixel8)] -> ...@. So the
"before" GIF (per-frame palettes) and the "after" GIF (one shared global palette) come
straight off the spec types via 'SixFour.Spec.Color.okLabToSRGB'.

This module is exercised only by the @spec-gif@ executable; JuicyPixels never enters the
@sixfour-spec@ library (the dependency-isolation discipline of @spec/analysis/@).
-}
module SixFour.Viz.Gif
  ( -- * OKLab → pixels
    oklabToRGB8
  , oklabPalette
    -- * Frames
  , indexImage
  , frameToRGB
  , swatchRGB
    -- * Compositing (RGB)
  , upscaleNN
  , upscalePix8
  , hcatRGB
  , diffRGB
    -- * Encoders
  , gifPerFramePalette
  , gifGlobalPalette
  , gifFromRGBFrames
  , writeGif
  ) where

import qualified Data.Vector          as V
import qualified Data.Vector.Unboxed  as U
import qualified Data.ByteString.Lazy as BL
import           Data.Word            (Word8)

import Codec.Picture            (Image(..), PixelRGB8(..), Pixel8, generateImage, pixelAt)
import Codec.Picture.Types      (Palette)
import Codec.Picture.Gif        (GifLooping(..), GifDelay, encodeGifImages)
import Codec.Picture.ColorQuant (palettize, PaletteOptions(..), defaultPaletteOptions)

import SixFour.Spec.Color (OKLab(..), SRGB(..), okLabToSRGB)

-- ---------------------------------------------------------------------------
-- OKLab → pixels
-- ---------------------------------------------------------------------------

-- | OKLab → an 8-bit sRGB pixel (gamma-encoded by 'okLabToSRGB', then clamped/rounded).
oklabToRGB8 :: OKLab -> PixelRGB8
oklabToRGB8 lab =
  let SRGB r g b = okLabToSRGB lab
  in PixelRGB8 (q r) (q g) (q b)
  where q x = fromIntegral (max 0 (min 255 (round (x * 255) :: Int))) :: Word8

-- | A list of OKLab colours as a GIF 'Palette' (a 1×N RGB image). Length must be 1..256.
oklabPalette :: [OKLab] -> Palette
oklabPalette cs =
  let v = V.fromList (map oklabToRGB8 cs)
      n = max 1 (V.length v)
  in generateImage (\x _ -> v V.! x) n 1

-- ---------------------------------------------------------------------------
-- Frames
-- ---------------------------------------------------------------------------

-- | A frame's row-major index list (@length = w*h@, each @< 256@) as an 'Image Pixel8'.
indexImage :: Int -> Int -> [Int] -> Image Pixel8
indexImage w h idx =
  let v = U.fromList (map fromIntegral idx) :: U.Vector Word8
  in generateImage (\x y -> v U.! (y * w + x)) w h

-- | Paint a frame: each pixel becomes the RGB of @palette !! index@.
frameToRGB :: [OKLab] -> Int -> Int -> [Int] -> Image PixelRGB8
frameToRGB pal w h idx =
  let pv = V.fromList (map oklabToRGB8 pal)
      iv = U.fromList idx :: U.Vector Int
  in generateImage (\x y -> pv V.! (iv U.! (y * w + x))) w h

-- | Render a palette as a @cols@-wide grid of @cell@×@cell@ swatches (unused cells dark).
swatchRGB :: Int -> Int -> [OKLab] -> Image PixelRGB8
swatchRGB cols cell cs =
  let pv   = V.fromList (map oklabToRGB8 cs)
      n    = V.length pv
      rows = (n + cols - 1) `div` cols
  in generateImage
       (\x y -> let i = (y `div` cell) * cols + (x `div` cell)
                in if i < n then pv V.! i else PixelRGB8 16 16 16)
       (cols * cell) (max 1 (rows * cell))

-- ---------------------------------------------------------------------------
-- Compositing
-- ---------------------------------------------------------------------------

-- | Nearest-neighbour ×@s@ upscale (RGB) — 64px is tiny on screen; display only.
upscaleNN :: Int -> Image PixelRGB8 -> Image PixelRGB8
upscaleNN s img =
  generateImage (\x y -> pixelAt img (x `div` s) (y `div` s))
                (imageWidth img * s) (imageHeight img * s)

-- | Nearest-neighbour ×@s@ upscale of a palettized (index) image — indices replicate.
upscalePix8 :: Int -> Image Pixel8 -> Image Pixel8
upscalePix8 s img =
  generateImage (\x y -> pixelAt img (x `div` s) (y `div` s))
                (imageWidth img * s) (imageHeight img * s)

-- | Place two RGB images side by side with a @gapW@-wide separator of colour @gapC@.
hcatRGB :: Int -> PixelRGB8 -> Image PixelRGB8 -> Image PixelRGB8 -> Image PixelRGB8
hcatRGB gapW gapC a b =
  let wa = imageWidth a
      h  = max (imageHeight a) (imageHeight b)
      w  = wa + gapW + imageWidth b
      at img xx yy
        | xx < imageWidth img && yy < imageHeight img = pixelAt img xx yy
        | otherwise = gapC
  in generateImage
       (\x y -> if x < wa then at a x y
                else if x < wa + gapW then gapC
                else at b (x - wa - gapW) y)
       w h

-- | Per-channel absolute difference, amplified ×8 — a zero diff renders pure black
-- (the visual form of "these two are identical").
diffRGB :: Image PixelRGB8 -> Image PixelRGB8 -> Image PixelRGB8
diffRGB a b =
  generateImage
    (\x y -> let PixelRGB8 r1 g1 b1 = pixelAt a x y
                 PixelRGB8 r2 g2 b2 = pixelAt b x y
                 d u v = fromIntegral (min 255 (8 * abs (fromIntegral u - fromIntegral v :: Int))) :: Word8
             in PixelRGB8 (d r1 r2) (d g1 g2) (d b1 b2))
    (imageWidth a) (imageHeight a)

-- ---------------------------------------------------------------------------
-- Encoders
-- ---------------------------------------------------------------------------

-- | THE PROBLEM (input): one frame per @(palette, indices)@ pair, each frame carrying its
-- OWN local palette — the per-frame-palette GIF. @scale@ upscales the index image.
gifPerFramePalette :: Int -> Int -> Int -> GifDelay -> [([OKLab], [Int])] -> Either String BL.ByteString
gifPerFramePalette scale w h d frames =
  encodeGifImages LoopingForever
    [ (oklabPalette pal, d, upscalePix8 scale (indexImage w h idx)) | (pal, idx) <- frames ]

-- | THE SOLUTION (output): every frame shares ONE global palette — JuicyPixels emits a
-- single global colour table when the palettes are identical.
gifGlobalPalette :: Int -> Int -> Int -> GifDelay -> [OKLab] -> [[Int]] -> Either String BL.ByteString
gifGlobalPalette scale w h d global frames =
  encodeGifImages LoopingForever
    [ (oklabPalette global, d, upscalePix8 scale (indexImage w h idx)) | idx <- frames ]

-- | Encode arbitrary RGB frames (composites, diffs, swatches) by median-cut palettizing
-- each frame to ≤256 colours.
gifFromRGBFrames :: GifDelay -> [Image PixelRGB8] -> Either String BL.ByteString
gifFromRGBFrames d frames =
  encodeGifImages LoopingForever
    [ let (i8, pal) = palettize opts im in (pal, d, i8) | im <- frames ]
  where opts = defaultPaletteOptions { enableImageDithering = False }

-- | Write an encoder result to a file, failing loudly on an encode error.
writeGif :: FilePath -> Either String BL.ByteString -> IO ()
writeGif fp = either (\e -> error ("GIF encode failed for " ++ fp ++ ": " ++ e)) (BL.writeFile fp)

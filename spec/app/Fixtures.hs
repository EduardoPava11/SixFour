{- |
spec-fixtures — emits the cross-language GOLDEN fixtures the Zig native core
verifies against (Native/src/*_fixture_test.zig), plus the shared binary
resources the core @\@embedFile@s.

Each golden is computed by the fixed-point Haskell spec (the bit-exact source of
truth), so the Zig kernel must reproduce it exactly. Integers only (Q16 i32 /
u8), so plain JSON decimal transport is exact — no IEEE-754 hex needed.

Run from @spec/@:  @cabal run spec-fixtures@
  → ../trainer/out/color_golden.json   (Zig color fixture test)
  → ../Native/src/gamma_lut.bin        (the inverse-gamma LUT the core embeds)
Override dirs with @--out DIR@ (goldens) and @--native DIR@ (embedded resources).
Kept OUT of spec-codegen so the iOS drift gate never writes into the real tree.
-}
module Main (main) where

import qualified Data.ByteString      as BS
import qualified Data.ByteString.Lazy as BL
import           Data.Bits            (shiftR, (.&.))
import           Data.List            (intercalate)
import           Data.Maybe           (fromMaybe)
import qualified Data.Text            as T
import qualified Data.Vector.Unboxed  as U
import           Data.Word            (Word8)
import           System.Directory     (createDirectoryIfMissing)
import           System.Environment   (getArgs)
import           System.FilePath      ((</>))

import SixFour.Spec.Color           (srgbToLinear)
import SixFour.Spec.ColorFixed
  ( linearToOklabQ16, oklabToSrgb8Q16, gammaLut, q16One, goldenLinearInputsQ16 )
import SixFour.Spec.Significance      (minPopulation)
import SixFour.Spec.SignificanceFixed (rescueQ16, cellsQ16)
import SixFour.Spec.SpatialDither     (DitherMode(..), ditherFrameQ16)
import SixFour.Spec.QuantFixed        (quantizeFrameQ16)
import SixFour.Spec.Collapse
  ( globalCollapseQ16, reindexFrameQ16, pooledCandidatesQ16 )
import SixFour.Spec.PairTreeFixed
  ( HaarPaletteI(..), analyzeFixed, reconstructFixed )
import SixFour.Gen.GifWire            (assembleGifRGB8)

main :: IO ()
main = do
  args <- getArgs
  let opts      = parseArgs args
      outDir    = fromMaybe "../trainer/out" (lookup "--out" opts)
      nativeDir = fromMaybe "../Native/src"  (lookup "--native" opts)
  createDirectoryIfMissing True outDir
  createDirectoryIfMissing True nativeDir

  writeFile (outDir </> "color_golden.json") emitColorGolden
  BS.writeFile (nativeDir </> "gamma_lut.bin") (BS.pack (U.toList gammaLut))
  -- sRGB8→linear Q16 LUT (the INVERSE-decode table s4_srgb8_to_oklab_q16 embeds):
  -- byte-identical to this Haskell, computed from the SAME srgbToLinear.
  BS.writeFile (nativeDir </> "srgb_linear_lut.bin") srgbLinearLutBin

  -- GIF89a/LZW golden for s4_gif_assemble.
  writeFile  (outDir </> "gif_golden.json")          gifMeta
  BS.writeFile (outDir </> "gif_golden_indices.bin")  gifIndicesBin
  BS.writeFile (outDir </> "gif_golden_palettes.bin") gifPalettesBin
  BL.writeFile (outDir </> "gif_golden.gif")          gifBytes

  -- Significance split-fill golden for s4_significance_fill.
  writeFile (outDir </> "significance_golden.json") emitSignificanceGolden

  -- Spatial dither golden for s4_dither_frame.
  writeFile (outDir </> "dither_golden.json") emitDitherGolden

  -- Quantize golden for s4_quantize_frame.
  writeFile (outDir </> "quant_golden.json") emitQuantGolden

  -- Global-collapse golden for s4_global_collapse (GIFA → GIFB). Same fixture as
  -- SixFour/Generated/CollapseGolden.swift, so spec ≡ Swift ≡ Zig on one cloud.
  writeFile (outDir </> "collapse_golden.json") emitCollapseGolden

  -- Owned integer Haar golden for s4_haar_analyze / s4_haar_reconstruct.
  writeFile (outDir </> "haar_golden.json") emitHaarGolden

  putStrLn $ "spec-fixtures: wrote color_golden.json to " <> outDir
  putStrLn $ "  linear_to_oklab cases: " <> show (length goldenLinearInputsQ16)
  putStrLn $ "  oklab_to_srgb8 cases:  " <> show (length goldenLinearInputsQ16)
  putStrLn $ "spec-fixtures: wrote gamma_lut.bin (" <> show (U.length gammaLut) <> " bytes) to " <> nativeDir
  putStrLn $ "spec-fixtures: wrote srgb_linear_lut.bin (" <> show (BS.length srgbLinearLutBin) <> " bytes) to " <> nativeDir
  putStrLn $ "spec-fixtures: wrote gif_golden.gif (" <> show (BL.length gifBytes) <> " bytes), "
             <> show gifFrameCount <> " frames @ " <> show gifSide <> "²×" <> show gifK <> " to " <> outDir

-- | sRGB8→linear Q16 decode LUT: 256 little-endian int32 of
-- @round(srgbToLinear(i/255) · 65536)@, clamped ≥ 0. The inverse-direction
-- companion to gamma_lut.bin; s4_srgb8_to_oklab_q16 @\@embedFile@s it. Computed
-- from the SAME 'SixFour.Spec.Color.srgbToLinear' so Zig and Haskell agree byte-for-byte.
srgbLinearLutBin :: BS.ByteString
srgbLinearLutBin = BS.pack (concatMap (le32 . entry) [0 .. 255])
  where
    entry :: Int -> Int
    entry i = max 0 (round (srgbToLinear (fromIntegral i / 255) * fromIntegral q16One))
    le32 :: Int -> [Word8]
    le32 v = [ fromIntegral (v `shiftR` s) .&. 0xFF | s <- [0, 8, 16, 24] ]

-- | { q16_one, linear_to_oklab: [...], oklab_to_srgb8: [...] }
emitColorGolden :: String
emitColorGolden =
  unlines
    [ "{"
    , "  \"_comment\": \"GENERATED by sixfour-spec / spec-fixtures — do not edit. Regenerate: cabal run spec-fixtures.\","
    , "  \"q16_one\": " <> show q16One <> ","
    , "  \"linear_to_oklab\": ["
    , intercalate ",\n" (map fwdLine goldenLinearInputsQ16)
    , "  ],"
    , "  \"oklab_to_srgb8\": ["
    , intercalate ",\n" (map invLine goldenLinearInputsQ16)
    , "  ]"
    , "}"
    ]
  where
    fwdLine lin@(r, g, b) =
      let (l, a, bb) = linearToOklabQ16 lin
      in "    { \"lin\": " <> triple r g b
         <> ", \"oklab\": " <> triple l a bb <> " }"
    -- Inverse cases are seeded from the forward OKLab outputs (round-trip
    -- coverage over the same structured set of colours).
    invLine lin =
      let (l, a, bb)  = linearToOklabQ16 lin
          (r8, g8, b8) = oklabToSrgb8Q16 (l, a, bb)
      in "    { \"oklab\": " <> triple l a bb
         <> ", \"rgb\": " <> triple r8 g8 b8 <> " }"
    triple x y z = "[" <> intercalate ", " (map show [x, y, z]) <> "]"

-- ---------------------------------------------------------------------------
-- GIF89a / LZW golden for s4_gif_assemble
-- ---------------------------------------------------------------------------

gifFrameCount, gifSide, gifK, gifDelayCs :: Int
gifFrameCount = 3
gifSide       = 64           -- 4096 px/frame — enough to exercise dict growth/reset
gifK          = 256
gifDelayCs    = 5            -- 20 fps

gifComment :: T.Text
gifComment = T.pack "SixFour deterministic GIF golden v1"

-- | Three deterministic frames spanning the LZW state machine: a 0..255 ramp
-- (fills the dictionary), a constant run, and a pseudo-random spread.
gifFrames :: [(U.Vector Int, [(Word8, Word8, Word8)])]
gifFrames = [ (frameIndices f, palette f) | f <- [0 .. gifFrameCount - 1] ]
  where
    p = gifSide * gifSide
    frameIndices f = U.generate p (idx f)
    idx 0 i = i `mod` 256                       -- ramp
    idx 1 _ = 7                                 -- constant
    idx _ i = (i * 1103515245 + 12345) `mod` 256  -- LCG spread
    palette f =
      [ ( fromIntegral ((k + f * 40) `mod` 256)
        , fromIntegral ((255 - k) `mod` 256)
        , fromIntegral ((k * 7 + f * 11) `mod` 256) )
      | k <- [0 .. gifK - 1] ]

gifBytes :: BL.ByteString
gifBytes = assembleGifRGB8 gifSide gifSide 20 (Just gifComment) gifFrames

gifIndicesBin :: BS.ByteString
gifIndicesBin =
  BS.pack [ fromIntegral v | (idx, _) <- gifFrames, v <- U.toList idx ]

gifPalettesBin :: BS.ByteString
gifPalettesBin =
  BS.pack [ ch | (_, pal) <- gifFrames, (r, g, b) <- pal, ch <- [r, g, b] ]

gifMeta :: String
gifMeta =
  unlines
    [ "{"
    , "  \"_comment\": \"GENERATED by sixfour-spec / spec-fixtures — do not edit.\","
    , "  \"frame_count\": " <> show gifFrameCount <> ","
    , "  \"side\": " <> show gifSide <> ","
    , "  \"k\": " <> show gifK <> ","
    , "  \"delay_cs\": " <> show gifDelayCs <> ","
    , "  \"comment\": \"" <> T.unpack gifComment <> "\""
    , "}"
    ]

-- ---------------------------------------------------------------------------
-- Significance split-fill golden for s4_significance_fill
-- ---------------------------------------------------------------------------

sigK, sigP :: Int
sigK = 16
sigP = 64

-- Deterministic Q16 pixels/centroids + an imbalanced initial labelling (only
-- slots 0..2 used ⇒ 13 deficient slots), so the rescue must pull donors.
sigPixels :: [(Int, Int, Int)]
sigPixels = [ pix i | i <- [0 .. sigP - 1] ]
  where pix i = ( (i * 2654435761 + 17) `mod` 65536
                , (i * 40503     + 17) `mod` 65536
                , (i * 1000003   + 17) `mod` 65536 )

sigCentroids :: [(Int, Int, Int)]
sigCentroids = [ pix (i * 7 + 1) | i <- [0 .. sigK - 1] ]
  where pix i = ( (i * 2654435761 + 17) `mod` 65536
                , (i * 40503     + 17) `mod` 65536
                , (i * 1000003   + 17) `mod` 65536 )

sigIndicesIn :: [Int]
sigIndicesIn = [ i `mod` 3 | i <- [0 .. sigP - 1] ]

sigIndicesOut :: [Int]
sigIndicesOut = rescueQ16 sigK sigCentroids sigIndicesIn sigPixels

sigCells :: [(Int, Int, Int, Int, Int, Int, Int)]
sigCells = cellsQ16 sigK sigCentroids sigIndicesOut sigPixels

emitSignificanceGolden :: String
emitSignificanceGolden =
  unlines
    [ "{"
    , "  \"_comment\": \"GENERATED by sixfour-spec / spec-fixtures — do not edit.\","
    , "  \"k\": " <> show sigK <> ","
    , "  \"p\": " <> show sigP <> ","
    , "  \"min_population\": " <> show minPopulation <> ","
    , "  \"centroids\": " <> triples sigCentroids <> ","
    , "  \"pixels\": " <> triples sigPixels <> ","
    , "  \"indices_in\": " <> ints sigIndicesIn <> ","
    , "  \"indices_out\": " <> ints sigIndicesOut <> ","
    , "  \"cells\": " <> cellsArr sigCells
    , "}"
    ]
  where
    ints xs    = "[" <> intercalate ", " (map show xs) <> "]"
    triples ts = "[" <> intercalate ", " [ "[" <> intercalate "," (map show [l,a,b]) <> "]" | (l,a,b) <- ts ] <> "]"
    cellsArr cs = "[" <> intercalate ", "
      [ "[" <> intercalate "," (map show [ml,ma,mb,sl,sa,sb,n]) <> "]" | (ml,ma,mb,sl,sa,sb,n) <- cs ] <> "]"

-- ---------------------------------------------------------------------------
-- Spatial dither golden for s4_dither_frame
-- ---------------------------------------------------------------------------

ditSide, ditK :: Int
ditSide = 8
ditK    = 8

ditPixels :: [(Int, Int, Int)]
ditPixels = [ px i | i <- [0 .. ditSide * ditSide - 1] ]
  where px i = ( (i * 1009 + 31) `mod` 65536
               , (i * 2003 + 31) `mod` 65536
               , (i * 3001 + 31) `mod` 65536 )

ditCentroids :: [(Int, Int, Int)]
ditCentroids = [ px (i * 13 + 1) | i <- [0 .. ditK - 1] ]
  where px i = ( (i * 1009 + 31) `mod` 65536
               , (i * 2003 + 31) `mod` 65536
               , (i * 3001 + 31) `mod` 65536 )

ditThresholds :: [Int]
ditThresholds = [ (i * 97 + 5) `mod` 256 | i <- [0 .. ditSide * ditSide - 1] ]

-- (mode, serpentine) → kernel-level dither_mode int for the Zig ABI.
ditCases :: [(Int, Bool, DitherMode)]
ditCases =
  [ (0, False, FloydSteinberg)
  , (0, True,  FloydSteinberg)
  , (1, False, Atkinson)
  , (2, False, BlueNoise) ]

emitDitherGolden :: String
emitDitherGolden =
  unlines
    [ "{"
    , "  \"_comment\": \"GENERATED by sixfour-spec / spec-fixtures — do not edit.\","
    , "  \"side\": " <> show ditSide <> ","
    , "  \"k\": " <> show ditK <> ","
    , "  \"centroids\": " <> triples ditCentroids <> ","
    , "  \"pixels\": " <> triples ditPixels <> ","
    , "  \"thresholds\": " <> ints ditThresholds <> ","
    , "  \"cases\": [ " <> intercalate ", " (map caseObj ditCases) <> " ]"
    , "}"
    ]
  where
    caseObj (m, serp, mode) =
      let out = ditherFrameQ16 mode ditSide serp ditCentroids ditThresholds ditPixels
      in "{ \"mode\": " <> show m
         <> ", \"serpentine\": " <> (if serp then "1" else "0")
         <> ", \"indices\": " <> ints out <> " }"
    ints xs    = "[" <> intercalate ", " (map show xs) <> "]"
    triples ts = "[" <> intercalate ", " [ "[" <> intercalate "," (map show [l,a,b]) <> "]" | (l,a,b) <- ts ] <> "]"

-- ---------------------------------------------------------------------------
-- Quantize golden for s4_quantize_frame
-- ---------------------------------------------------------------------------

quSide, quK :: Int
quSide = 8
quK    = 8

quPixels :: [(Int, Int, Int)]
quPixels = [ px i | i <- [0 .. quSide * quSide - 1] ]
  where px i = ( (i * 2741 + 13) `mod` 65536
               , (i * 5009 + 13) `mod` 65536
               , (i * 7919 + 13) `mod` 65536 )

-- Two cases: pure maximin (iters 0, max diversity) and a Lloyd-refined run.
quCases :: [Int]
quCases = [0, 4]

emitQuantGolden :: String
emitQuantGolden =
  unlines
    [ "{"
    , "  \"_comment\": \"GENERATED by sixfour-spec / spec-fixtures — do not edit.\","
    , "  \"side\": " <> show quSide <> ","
    , "  \"k\": " <> show quK <> ","
    , "  \"pixels\": " <> triples quPixels <> ","
    , "  \"cases\": [ " <> intercalate ", " (map caseObj quCases) <> " ]"
    , "}"
    ]
  where
    caseObj iters =
      let (cs, asn) = quantizeFrameQ16 quK iters quPixels
      in "{ \"lloyd_iters\": " <> show iters
         <> ", \"centroids\": " <> triples cs
         <> ", \"indices\": " <> ints asn <> " }"
    ints xs    = "[" <> intercalate ", " (map show xs) <> "]"
    triples ts = "[" <> intercalate ", " [ "[" <> intercalate "," (map show [l,a,b]) <> "]" | (l,a,b) <- ts ] <> "]"

-- ---------------------------------------------------------------------------
-- Global-collapse golden for s4_global_collapse (GIFA → GIFB)
-- ---------------------------------------------------------------------------

-- The SAME fixture as Codegen.Collapse / CollapseGolden.swift: the 64 cross-
-- language Q16 OKLab inputs in 8 frames of 8, collapsed to k_out = 16 leaves.
colKOut :: Int
colKOut = 16

colFrames :: [[(Int, Int, Int)]]
colFrames = chunk 8 (map linearToOklabQ16 goldenLinearInputsQ16)
  where
    chunk _ [] = []
    chunk n xs = take n xs : chunk n (drop n xs)

emitCollapseGolden :: String
emitCollapseGolden =
  unlines
    [ "{"
    , "  \"_comment\": \"GENERATED by sixfour-spec / spec-fixtures — do not edit. Same fixture as CollapseGolden.swift.\","
    , "  \"t\": " <> show (length colFrames) <> ","
    , "  \"k_in\": " <> show (length (head colFrames)) <> ","
    , "  \"k_out\": " <> show colKOut <> ","
    , "  \"palettes\": " <> triples pooled <> ","
    , "  \"leaves\": " <> triples leaves <> ","
    , "  \"indices\": " <> ints indices
    , "}"
    ]
  where
    pooled  = pooledCandidatesQ16 colFrames
    leaves  = globalCollapseQ16 colKOut colFrames
    indices = concatMap (reindexFrameQ16 leaves) colFrames
    ints xs    = "[" <> intercalate ", " (map show xs) <> "]"
    triples ts = "[" <> intercalate ", " [ "[" <> intercalate "," (map show [l,a,b]) <> "]" | (l,a,b) <- ts ] <> "]"

-- ---------------------------------------------------------------------------
-- Owned integer Haar golden for s4_haar_analyze / s4_haar_reconstruct
-- ---------------------------------------------------------------------------

-- A deterministic 16-leaf Q16 OKLab fixture (depth 4), in gamut.
haarLeaves :: [(Int, Int, Int)]
haarLeaves = [ px i | i <- [0 .. 15] ]
  where px i = ( (i * 2741 + 13) `mod` 65536 - 4096
               , (i * 5009 + 13) `mod` 52428 - 26214
               , (i * 7919 + 13) `mod` 52428 - 26214 )

emitHaarGolden :: String
emitHaarGolden =
  unlines
    [ "{"
    , "  \"_comment\": \"GENERATED by sixfour-spec / spec-fixtures — do not edit. SixFour.Spec.PairTreeFixed.\","
    , "  \"n\": " <> show (length haarLeaves) <> ","
    , "  \"leaves\": " <> triples haarLeaves <> ","
    , "  \"root\": " <> triple (rootI hp) <> ","
    , "  \"offsets\": " <> triples (concat (levelsI hp))
    , "}"
    ]
  where
    hp = analyzeFixed haarLeaves
    triple (l, a, b) = "[" <> intercalate "," (map show [l, a, b]) <> "]"
    triples ts = "[" <> intercalate ", " (map triple ts) <> "]"

-- | @--key value@ / @--key=value@ parser (mirrors app/Spec.hs).
parseArgs :: [String] -> [(String, String)]
parseArgs [] = []
parseArgs (kv : rest)
  | take 2 kv == "--", '=' `elem` kv =
      let (k, v) = break (== '=') kv in (k, drop 1 v) : parseArgs rest
parseArgs (k : v : rest)
  | take 2 k == "--" = (k, v) : parseArgs rest
parseArgs (_ : rest) = parseArgs rest

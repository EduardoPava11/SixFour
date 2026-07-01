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
import qualified Data.Vector          as V
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
import SixFour.Spec.GlobalCollapseQ16
  ( globalCollapseQ16, reindexFrameQ16, pooledCandidatesQ16 )
import SixFour.Spec.V21Field         (collapseQ16, BinQ16(..), labDeltaAt, liftOctList, countsToEnergy, modeOfCounts, accumulateHist, accumulateHistSoft, centeredEnergy, modeRelative, anchorAt, paletteDelta, paletteW1)
import SixFour.Spec.PairTreeFixed
  ( HaarPaletteI(..), analyzeFixed, reconstructFixed, levelNodesFixed, treeDepthI )
import SixFour.Spec.RGBTLift          (liftQuad)
import SixFour.Spec.CubeLadder        (liftLevel)
import SixFour.Spec.TemporalLoop      (haarSplitTime)
import SixFour.Spec.ZoneProfile
  ( ZoneProfileQ16(..), analyzeZoneProfileQ16 )
import SixFour.Spec.LookTransfer
  ( TransferParamsQ16(..), defaultTransferParamsQ16, transferOklabQ16 )
import SixFour.Spec.RedFrontEnd       (log3g10DecodeLut, filmicTonemapLut, filmicXMaxQ16)
import SixFour.Spec.CubeLut           (srgbEncodeLutQ16, buildCubeQ16, cubeSizeGolden)
import SixFour.Gen.GifWire            (assembleGifRGB8)
import SixFour.Spec.Upscale256
  ( UpscaleInput(..), UpscaleOutput(..), upscale256, PxQ16
  , driftPrior, quantizePrior
  , consumptionFixturePalette, consumptionFixtureExit, consumptionFixtureTarget )
import SixFour.Spec.AtlasCascade      (ExitState(..), SlotExit(..), zeroSlot, exitSlotCount)

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

  -- Full-burst golden for s4_gif_encode_burst (the COMPOSED fold:
  -- widen→oklab→quantize→dither(FS)→palette→assemble). golden_input.halfs is the
  -- matching binary16 burst; golden.gif is the byte-exact output the Zig monolithic
  -- entrypoint must reproduce. Small dims (2×8²×4) — the fold is size-independent.
  BS.writeFile (outDir </> "golden_input.halfs") burstInputHalfsBin
  BL.writeFile (outDir </> "golden.gif")          burstGifBytes

  -- Significance split-fill golden for s4_significance_fill.
  writeFile (outDir </> "significance_golden.json") emitSignificanceGolden

  -- Spatial dither golden for s4_dither_frame.
  writeFile (outDir </> "dither_golden.json") emitDitherGolden

  -- Quantize golden for s4_quantize_frame.
  writeFile (outDir </> "quant_golden.json") emitQuantGolden

  -- Global-collapse golden for s4_global_collapse (GIFA → GIFB). Same fixture as
  -- SixFour/Generated/CollapseGolden.swift, so spec ≡ Swift ≡ Zig on one cloud.
  writeFile (outDir </> "collapse_golden.json") emitCollapseGolden

  -- V2.1 collapse golden for s4_v21_collapse: per channel-curve argmin energy = the GIF89a byte
  -- (SixFour.Spec.V21Field.collapseQ16, lowest-index tie-break). Spec ≡ Zig on one fixture.
  writeFile (outDir </> "v21_collapse_golden.json") emitV21CollapseGolden

  -- V2.1 per-level octant lift driver golden for s4_v21_octant_lift_curve (drives the gated
  -- s4_octant_lift per level; SixFour.Spec.V21Field.liftOctList over the OctreeCell edge).
  writeFile (outDir </> "v21_octant_golden.json") emitV21OctantLiftGolden

  -- V2.1 opponent-delta golden for s4_v21_opponent_delta: per-level neighbour delta + integer
  -- opponent (SixFour.Spec.V21Field.labDeltaAt; the encode target, lawOpponentCommutesWithDelta).
  writeFile (outDir </> "v21_opponent_golden.json") emitV21OpponentDeltaGolden

  -- V2.1 captured-bin energy golden for s4_v21_counts_to_energy (make_bins core): empirical
  -- histogram counts -> energy = total - count (SixFour.Spec.V21Field.countsToEnergy); collapse of
  -- the energy = the mode. Also carries the modes so the Zig fixture can cross-check collapse and
  -- the order-duality with s4_board_counts_to_mass_q16.
  writeFile (outDir </> "v21_counts_golden.json") emitV21CountsEnergyGolden

  -- V2.1 histogram accumulation golden for s4_v21_accumulate_hist (the other half of make_bins):
  -- box-decimate a fine grid into coarse voxels, per-channel value histograms
  -- (SixFour.Spec.V21Field.accumulateHist).
  writeFile (outDir </> "v21_hist_golden.json") emitV21HistGolden

  -- The canonical ENCODER-INPUT presentation: ground-state centering, mode-relative reindexing, and
  -- the anchor that reconstructs the centered curve from the mode-relative curve + the GIF byte
  -- (SixFour.Spec.V21Field.centeredEnergy / modeRelative / anchorAt). Spec == Zig on one fixture.
  writeFile (outDir </> "v21_mode_relative_golden.json") emitV21ModeRelativeGolden

  -- The per-frame PALETTE DELTA (the temporal metric weight axisWeight T = pd): the L1 between two
  -- palettes' per-channel value histograms (SixFour.Spec.V21Field.paletteDelta). Spec == Zig on one
  -- fixture; also pins gauge invariance is respected by construction (histogram, not slot order).
  writeFile (outDir </> "v21_palette_delta_golden.json") emitV21PaletteDeltaGolden

  -- The 1-D WASSERSTEIN-1 palette metric (SixFour.Spec.V21Field.paletteW1): L1 of the per-channel
  -- value CDFs, the ground-distance-aware upgrade of the total-variation paletteDelta. Same fixture
  -- palettes; the Zig kernel s4_v21_wdist1d reproduces the scalar and the drift<jump discrimination.
  writeFile (outDir </> "v21_wdist1d_golden.json") emitV21WDist1DGolden

  -- The SUB-LSB SOFT-SPLAT construction (SixFour.Spec.V21Field.accumulateHistSoft): each fine sample
  -- is a high-precision position and deposits an integer mass w split across the two adjacent value
  -- levels, so the 10-bit sensor bits round() discards survive as the histogram's first moment.
  writeFile (outDir </> "v21_soft_hist_golden.json") emitV21SoftHistGolden

  -- Owned integer Haar golden for s4_haar_analyze / s4_haar_reconstruct.
  writeFile (outDir </> "haar_golden.json") emitHaarGolden

  -- Temporal one-level Haar split golden for s4_haar_split_level / s4_haar_join_level
  -- (the temporal half of SixFour.Spec.VoxelReduce; mirrors TemporalLoop.haarSplitTime).
  writeFile (outDir </> "temporal_golden.json") emitTemporalGolden

  -- rgbt4d_golden.json: the RGBT-4D lift + cube-ladder level (Zig rgbt4d fixture test).
  writeFile (outDir </> "rgbt4d_golden.json") emitRGBT4DGolden

  -- Look / LUT extraction. The two transcendental 1-D LUTs the cube embeds
  -- (Log3G10 decode, filmic tonemap) + the Q16 sRGB-encode output LUT, all as LE
  -- i32; plus lut_golden.json for s4_zone_profile_q16 / s4_look_transfer_q16 /
  -- s4_build_cube_q16 (a small 5³ cube, byte-checked whole).
  BS.writeFile (nativeDir </> "log3g10_decode_lut.bin") (le32Vec log3g10DecodeLut)
  BS.writeFile (nativeDir </> "filmic_tonemap_lut.bin")  (le32Vec filmicTonemapLut)
  BS.writeFile (nativeDir </> "srgb_encode_lut.bin")     (le32Vec srgbEncodeLutQ16)
  writeFile (outDir </> "lut_golden.json") emitLutGolden

  -- upscale256_golden.json: the deterministic 64³→256³ FLOOR (Spec.Upscale256.upscale256 =
  -- Spec.ModelIO.buildFloor at zero nudge). The Python trainer port (trainer/mlx/upscale256.py)
  -- must reproduce this byte-exact, so "above-floor" margin is measured against the REAL floor.
  writeFile (outDir </> "upscale256_golden.json") emitUpscaleGolden

  putStrLn $ "spec-fixtures: wrote color_golden.json to " <> outDir
  putStrLn $ "  linear_to_oklab cases: " <> show (length goldenLinearInputsQ16)
  putStrLn $ "  oklab_to_srgb8 cases:  " <> show (length goldenLinearInputsQ16)
  putStrLn $ "spec-fixtures: wrote gamma_lut.bin (" <> show (U.length gammaLut) <> " bytes) to " <> nativeDir
  putStrLn $ "spec-fixtures: wrote srgb_linear_lut.bin (" <> show (BS.length srgbLinearLutBin) <> " bytes) to " <> nativeDir
  putStrLn $ "spec-fixtures: wrote gif_golden.gif (" <> show (BL.length gifBytes) <> " bytes), "
             <> show gifFrameCount <> " frames @ " <> show gifSide <> "²×" <> show gifK <> " to " <> outDir
  putStrLn $ "spec-fixtures: wrote golden.gif (" <> show (BL.length burstGifBytes) <> " bytes) + golden_input.halfs ("
             <> show (BS.length burstInputHalfsBin) <> " bytes), burst "
             <> show burstFrames <> "×" <> show burstSide <> "²×" <> show burstK <> " to " <> outDir
  putStrLn $ "spec-fixtures: wrote log3g10_decode_lut.bin (" <> show (U.length log3g10DecodeLut * 4)
             <> " bytes), filmic_tonemap_lut.bin (" <> show (U.length filmicTonemapLut * 4)
             <> " bytes), srgb_encode_lut.bin (" <> show (U.length srgbEncodeLutQ16 * 4) <> " bytes) to " <> nativeDir
  putStrLn $ "spec-fixtures: wrote lut_golden.json (cube " <> show cubeSizeGolden <> "³ = "
             <> show (cubeSizeGolden ^ (3 :: Int)) <> " entries) to " <> outDir

-- ---------------------------------------------------------------------------
-- Full-burst golden for s4_gif_encode_burst — the COMPOSED fold
-- ---------------------------------------------------------------------------

burstFrames, burstSide, burstK, burstLloyd :: Int
burstFrames = 2
burstSide   = 32                -- 1024 px/frame: p > k so quantize loses info ⇒ real dither
burstK      = 256               -- the app shape GifWire/GIFEncoder.swift support (K=256)
burstLloyd  = 15                -- Lloyd refinements (matches the test call)

-- Exact binary16 halfs and their linear-sRGB Q16 widening, for the 9 eighths
-- {0, ⅛, ¼, ⅜, ½, ⅝, ¾, ⅞, 1}. Each is exactly representable in binary16 AND
-- ×2^16 is an exact integer, so s4_widen_half_to_q16 (half→f32→×65536→round) is
-- EXACT — the golden cannot diverge on the I/O edge by float precision. 9³ = 729
-- distinct colours > K, so the 256-centroid quantize is non-degenerate. (bits, q16).
burstHalfTable :: [(Int, Int)]
burstHalfTable =
  [ (0x0000, 0),     (0x3000, 8192),  (0x3400, 16384)
  , (0x3600, 24576), (0x3800, 32768), (0x3900, 40960)
  , (0x3A00, 49152), (0x3B00, 57344), (0x3C00, 65536) ]

-- Deterministic value index in [0,8] for (frame, pixel, channel) — spatial variation
-- so quantize forms real clusters and FS dither has error to diffuse.
burstPick :: Int -> Int -> Int -> Int
burstPick f i c = (i * 3 + c * 7 + f * 13 + i * i) `mod` 9

-- A pixel's linear-sRGB Q16 triple (= the exact widen of its halfs).
burstPixelQ16 :: Int -> Int -> (Int, Int, Int)
burstPixelQ16 f i = (q 0, q 1, q 2)
  where q c = snd (burstHalfTable !! burstPick f i c)

-- The burst input as binary16 LE bytes: frame-major, pixel, channel (T·H·W·3).
burstInputHalfsBin :: BS.ByteString
burstInputHalfsBin = BS.pack
  [ byte
  | f <- [0 .. burstFrames - 1]
  , i <- [0 .. burstSide * burstSide - 1]
  , c <- [0 .. 2]
  , let bits = fst (burstHalfTable !! burstPick f i c)
  , byte <- [ fromIntegral (bits .&. 0xFF), fromIntegral ((bits `shiftR` 8) .&. 0xFF) ]
  ]

-- One frame through the fold: oklab → quantize → FS dither → palette(sRGB8).
burstFrameOut :: Int -> (U.Vector Int, [(Word8, Word8, Word8)])
burstFrameOut f =
  let p           = burstSide * burstSide
      oklab       = [ linearToOklabQ16 (burstPixelQ16 f i) | i <- [0 .. p - 1] ]
      (cents, _)  = quantizeFrameQ16 burstK burstLloyd oklab
      indices     = ditherFrameQ16 FloydSteinberg burstSide False cents [] oklab
      paletteRGB  = [ let (r, g, b) = oklabToSrgb8Q16 c
                      in (fromIntegral r, fromIntegral g, fromIntegral b) | c <- cents ]
  in (U.fromList indices, paletteRGB)

-- The whole composed GIF (no comment, 20 fps ⇒ 5 cs/frame) the Zig entrypoint mirrors.
burstGifBytes :: BL.ByteString
burstGifBytes =
  assembleGifRGB8 burstSide burstSide 20 Nothing [ burstFrameOut f | f <- [0 .. burstFrames - 1] ]

-- | sRGB8→linear Q16 decode LUT: 256 little-endian int32 of
-- @round(srgbToLinear(i/255) · 65536)@, clamped ≥ 0. The inverse-direction
-- companion to gamma_lut.bin; s4_srgb8_to_oklab_q16 @\@embedFile@s it. Computed
-- from the SAME 'SixFour.Spec.Color.srgbToLinear' so Zig and Haskell agree byte-for-byte.
srgbLinearLutBin :: BS.ByteString
srgbLinearLutBin = BS.pack (concatMap (le32 . entry) [0 .. 255])
  where
    entry :: Int -> Int
    entry i = max 0 (round (srgbToLinear (fromIntegral i / 255) * fromIntegral q16One))

-- | One Q16 'Int' as four little-endian bytes.
le32 :: Int -> [Word8]
le32 v = [ fromIntegral (v `shiftR` s) .&. 0xFF | s <- [0, 8, 16, 24] ]

-- | A Q16 'Int' vector as a little-endian i32 byte string (the @.bin@ embed format).
le32Vec :: U.Vector Int -> BS.ByteString
le32Vec = BS.pack . concatMap le32 . U.toList

-- ---------------------------------------------------------------------------
-- Look / LUT extraction golden for s4_zone_profile_q16 / s4_look_transfer_q16 /
-- s4_build_cube_q16
-- ---------------------------------------------------------------------------

-- A deterministic OKLab Q16 palette (the same structured colour set as collapse).
lutPaletteOklab :: [(Int, Int, Int)]
lutPaletteOklab = map linearToOklabQ16 goldenLinearInputsQ16

lutProfile :: ZoneProfileQ16
lutProfile = analyzeZoneProfileQ16 lutPaletteOklab

lutParams :: TransferParamsQ16
lutParams = defaultTransferParamsQ16

-- Transfer probe inputs incl. adversarial cases (zero-chroma neutrals → the
-- epsilon-snap branch; L at the extremes → end-zone clamp).
lutTransferInputs :: [(Int, Int, Int)]
lutTransferInputs =
  [ (q16One `div` 2, q16One `div` 8, negate (q16One `div` 8))   -- mid, coloured
  , (q16One `div` 4, 0, 0)                                       -- neutral shadow (eps branch)
  , (0,              q16One `div` 10, q16One `div` 10)           -- L = 0
  , (q16One,         negate (q16One `div` 6), q16One `div` 12)   -- highlight
  , ((3 * q16One) `div` 4, 0, 0) ]                               -- neutral highlight

emitLutGolden :: String
emitLutGolden =
  unlines
    [ "{"
    , "  \"_comment\": \"GENERATED by sixfour-spec / spec-fixtures — do not edit. Regenerate: cabal run spec-fixtures.\","
    , "  \"q16_one\": " <> show q16One <> ","
    , "  \"num_zones\": " <> show (zpNumZones lutProfile) <> ","
    , "  \"filmic_xmax_q16\": " <> show filmicXMaxQ16 <> ","
    , "  \"transfer_params\": { \"strength\": " <> show (tpStrength lutParams)
        <> ", \"chroma_min\": " <> show (tpChromaMin lutParams)
        <> ", \"chroma_max\": " <> show (tpChromaMax lutParams)
        <> ", \"polarity\": " <> show (tpPolarity lutParams)
        <> ", \"chroma_eps\": " <> show (tpChromaEps lutParams) <> " },"
    , "  \"palette_oklab\": " <> triples lutPaletteOklab <> ","
    , "  \"zone_profile\": { \"mean_a\": " <> ints (U.toList (zpMeanA lutProfile))
        <> ", \"mean_b\": " <> ints (U.toList (zpMeanB lutProfile))
        <> ", \"mean_c\": " <> ints (U.toList (zpMeanC lutProfile))
        <> ", \"global\": " <> triple (zpGlobalA lutProfile, zpGlobalB lutProfile, zpGlobalC lutProfile)
        <> " },"
    , "  \"transfer_cases\": [ " <> intercalate ", " (map transferCase lutTransferInputs) <> " ],"
    , "  \"cube_size\": " <> show cubeSizeGolden <> ","
    , "  \"cube\": " <> triples (buildCubeQ16 lutParams lutProfile cubeSizeGolden)
    , "}"
    ]
  where
    transferCase inp =
      "{ \"in\": " <> triple inp <> ", \"out\": " <> triple (transferOklabQ16 lutParams lutProfile inp) <> " }"
    triple (x, y, z) = "[" <> intercalate ", " (map show [x, y, z]) <> "]"
    triples ts = "[" <> intercalate ", " (map triple ts) <> "]"
    ints xs = "[" <> intercalate ", " (map show xs) <> "]"

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
-- V2.1 collapse golden for s4_v21_collapse (SixFour.Spec.V21Field.collapseQ16)
-- ---------------------------------------------------------------------------

-- | The number of value levels per curve in the V2.1 collapse fixture (kept small to exercise the
--   argmin logic; the kernel is n_levels-agnostic up to 256).
v21CollapseNLevels :: Int
v21CollapseNLevels = 6

-- | Twelve Q16 energy curves (p = 4 pixels x 3 channels), length 'v21CollapseNLevels', chosen to
--   exercise ties (lowest index wins), negatives, and monotone runs.
v21CollapseCurves :: [[Int]]
v21CollapseCurves =
  [ [9, 5, 7, 2, 8, 2]
  , [0, 0, 0, 0, 0, 0]
  , [3, 1, 4, 1, 5, 9]
  , [10, 9, 8, 7, 6, 5]
  , [-1, -2, -3, -2, -1, 0]
  , [5, 5, 5, 5, 5, 4]
  , [100, -100, 100, -100, 0, 0]
  , [2, 2, 1, 2, 2, 2]
  , [0, 1, 2, 3, 4, 5]
  , [5, 4, 3, 2, 1, 0]
  , [7, 7, 7, 6, 7, 7]
  , [1, 0, 0, 1, 1, 1]
  ]

-- | The V2.1 collapse golden: the curves plus their collapsed levels, computed by the spec
--   ('collapseQ16') so the golden cannot drift from the source of truth.
emitV21CollapseGolden :: String
emitV21CollapseGolden =
  unlines
    [ "{"
    , "  \"_comment\": \"GENERATED by sixfour-spec / spec-fixtures; do not edit.\","
    , "  \"p\": " <> show (length v21CollapseCurves `div` 3) <> ","
    , "  \"n_levels\": " <> show v21CollapseNLevels <> ","
    , "  \"curves\": " <> arr2 v21CollapseCurves <> ","
    , "  \"collapsed\": " <> ints (map collapseQ16 v21CollapseCurves)
    , "}"
    ]
  where
    ints xs  = "[" <> intercalate ", " (map show xs) <> "]"
    arr2 xss = "[" <> intercalate ", " (map ints xss) <> "]"

-- ---------------------------------------------------------------------------
-- V2.1 mode-relative ENCODER-INPUT golden for s4_v21_centered_energy /
-- s4_v21_mode_relative / s4_v21_anchor_at
-- (SixFour.Spec.V21Field.centeredEnergy / modeRelative / anchorAt)
-- ---------------------------------------------------------------------------

-- | The number of value levels in the V2.1 mode-relative fixture.
v21RelNLevels :: Int
v21RelNLevels = 6

-- | Twelve energy curves (p = 4 pixels x 3 channels), length 'v21RelNLevels', chosen to exercise a
--   clear mode, ties (lowest index wins), a flat curve (mode 0), and negatives, so centering +
--   mode rotation + the anchor round-trip is non-trivial.
v21RelCurves :: [[Int]]
v21RelCurves =
  [ [9, 5, 7, 2, 8, 2]
  , [0, 0, 0, 0, 0, 0]
  , [3, 1, 4, 1, 5, 9]
  , [10, 9, 8, 7, 6, 5]
  , [-1, -2, -3, -2, -1, 0]
  , [5, 5, 5, 5, 5, 4]
  , [100, -100, 100, -100, 0, 0]
  , [2, 2, 1, 2, 2, 2]
  , [0, 1, 2, 3, 4, 5]
  , [5, 4, 3, 2, 1, 0]
  , [7, 7, 7, 6, 7, 7]
  , [1, 0, 0, 1, 1, 1]
  ]

-- | The mode-relative golden: each curve's centered energy, mode-relative presentation, GIF mode
--   ('collapseQ16'), and the anchored reconstruction ('anchorAt' of the mode-relative curve at the
--   mode), all from the spec so the golden cannot drift. The Zig test asserts every kernel matches
--   AND that the anchor reproduces the centered curve (field + GIF reconstruct the field).
emitV21ModeRelativeGolden :: String
emitV21ModeRelativeGolden =
  unlines
    [ "{"
    , "  \"_comment\": \"GENERATED by sixfour-spec / spec-fixtures; do not edit.\","
    , "  \"p\": " <> show (length v21RelCurves `div` 3) <> ","
    , "  \"n_levels\": " <> show v21RelNLevels <> ","
    , "  \"curves\": " <> arr2 v21RelCurves <> ","
    , "  \"centered\": " <> arr2 (map centeredEnergy v21RelCurves) <> ","
    , "  \"mode_relative\": " <> arr2 (map modeRelative v21RelCurves) <> ","
    , "  \"modes\": " <> ints (map collapseQ16 v21RelCurves) <> ","
    , "  \"anchored\": " <> arr2 [ anchorAt (collapseQ16 c) (modeRelative c) | c <- v21RelCurves ]
    , "}"
    ]
  where
    ints xs  = "[" <> intercalate ", " (map show xs) <> "]"
    arr2 xss = "[" <> intercalate ", " (map ints xss) <> "]"

-- ---------------------------------------------------------------------------
-- V2.1 histogram accumulation golden for s4_v21_accumulate_hist (make_bins half 1)
-- ---------------------------------------------------------------------------

-- | The fine grid for the accumulation fixture: fx=4, fy=2, ft=2, 3 channels = 48 samples, values
--   0..3 (n_levels=4); decimation 2x2x2 -> 2 coarse voxels. Layout (((ft*fy+y)*fx+x)*3+ch).
v21HistFine :: [Int]
v21HistFine = [ i `mod` 4 | i <- [0 .. 47] ]

-- | The histogram-accumulation golden: the fine grid + dims + decimation, and the per-voxel
--   per-channel value counts the spec's 'accumulateHist' produces.
emitV21HistGolden :: String
emitV21HistGolden =
  unlines
    [ "{"
    , "  \"_comment\": \"GENERATED by sixfour-spec / spec-fixtures; do not edit.\","
    , "  \"fx\": 4, \"fy\": 2, \"ft\": 2,"
    , "  \"dx\": 2, \"dy\": 2, \"dt\": 2,"
    , "  \"n_levels\": 4,"
    , "  \"fine\": " <> ints v21HistFine <> ","
    , "  \"counts\": " <> ints (accumulateHist (4, 2, 2) (2, 2, 2) 4 v21HistFine)
    , "}"
    ]
  where
    ints xs = "[" <> intercalate ", " (map show xs) <> "]"

-- ---------------------------------------------------------------------------
-- V2.1 SOFT-SPLAT histogram golden for s4_v21_accumulate_hist_soft (the sub-LSB construction)
-- ---------------------------------------------------------------------------

-- | The sub-level weight budget for the soft-splat fixture (2 extra bits below the value LSB).
v21SoftBudget :: Int
v21SoftBudget = 4

-- | The high-precision fine grid: fx=4, fy=2, ft=2, 3 channels = 48 samples, positions hi in
--   0 .. (n_levels-1)*w = 12 (n_levels=4, w=4). Chosen so many samples fall BETWEEN levels (nonzero
--   sub-fraction), exercising the two-level split, plus exact multiples (hi=0,4,8,12) that land whole.
v21SoftFine :: [Int]
v21SoftFine = [ i `mod` 13 | i <- [0 .. 47] ]

-- | The soft-splat golden: the fine grid + dims + decimation + budget, and the per-voxel per-channel
--   SOFT counts the spec's 'accumulateHistSoft' produces (mass w per sample, split across two levels).
emitV21SoftHistGolden :: String
emitV21SoftHistGolden =
  unlines
    [ "{"
    , "  \"_comment\": \"GENERATED by sixfour-spec / spec-fixtures; do not edit.\","
    , "  \"fx\": 4, \"fy\": 2, \"ft\": 2,"
    , "  \"dx\": 2, \"dy\": 2, \"dt\": 2,"
    , "  \"n_levels\": 4,"
    , "  \"w\": " <> show v21SoftBudget <> ","
    , "  \"fine\": " <> ints v21SoftFine <> ","
    , "  \"counts\": " <> ints (accumulateHistSoft v21SoftBudget (4, 2, 2) (2, 2, 2) 4 v21SoftFine)
    , "}"
    ]
  where
    ints xs = "[" <> intercalate ", " (map show xs) <> "]"

-- ---------------------------------------------------------------------------
-- V2.1 captured-bin energy golden for s4_v21_counts_to_energy (make_bins core)
-- ---------------------------------------------------------------------------

-- | The number of value levels in the V2.1 captured-bin fixture.
v21CountsNLevels :: Int
v21CountsNLevels = 6

-- | Twelve count histograms (p = 4 pixels x 3 channels), each 'v21CountsNLevels' levels, chosen to
--   exercise a clear mode, ties (lowest index wins), a uniform histogram, and bimodal shapes.
v21CountsHist :: [[Int]]
v21CountsHist =
  [ [0, 1, 0, 5, 0, 2]   -- mode 3
  , [3, 3, 3, 3, 3, 3]   -- uniform -> mode 0
  , [1, 4, 0, 4, 0, 0]   -- bimodal tie 1/3 -> mode 1
  , [0, 0, 0, 0, 0, 7]   -- mode 5
  , [2, 9, 0, 9, 0, 1]   -- bimodal tie 1/3 -> mode 1
  , [5, 0, 0, 0, 0, 0]   -- mode 0
  , [0, 0, 0, 0, 8, 8]   -- tie 4/5 -> mode 4
  , [1, 1, 6, 1, 1, 1]   -- mode 2
  , [9, 0, 0, 0, 0, 0]   -- mode 0
  , [0, 0, 0, 0, 0, 3]   -- mode 5
  , [0, 0, 0, 7, 0, 0]   -- mode 3
  , [4, 5, 5, 4, 4, 4]   -- tie 1/2 -> mode 1
  ]

-- | The captured-bin golden: the count histograms, their energy curves (countsToEnergy = total -
--   count), and their modes (collapse of the energy), all from the spec so the golden cannot drift.
emitV21CountsEnergyGolden :: String
emitV21CountsEnergyGolden =
  unlines
    [ "{"
    , "  \"_comment\": \"GENERATED by sixfour-spec / spec-fixtures; do not edit.\","
    , "  \"p\": " <> show (length v21CountsHist `div` 3) <> ","
    , "  \"n_levels\": " <> show v21CountsNLevels <> ","
    , "  \"counts\": " <> arr2 v21CountsHist <> ","
    , "  \"energy\": " <> arr2 (map countsToEnergy v21CountsHist) <> ","
    , "  \"modes\": " <> ints (map modeOfCounts v21CountsHist)
    , "}"
    ]
  where
    ints xs  = "[" <> intercalate ", " (map show xs) <> "]"
    arr2 xss = "[" <> intercalate ", " (map ints xss) <> "]"

-- ---------------------------------------------------------------------------
-- V2.1 per-level octant lift driver golden for s4_v21_octant_lift_curve
-- ---------------------------------------------------------------------------

-- | The number of value levels in the V2.1 octant-driver fixture.
v21OctNLevels :: Int
v21OctNLevels = 5

-- | Eight octant cells, each a Q16 curve of 'v21OctNLevels' levels (cell-major).
v21OctCells :: [[Int]]
v21OctCells =
  [ [10, 20, 30, 40, 50]
  , [12, 18, 33, 38, 55]
  , [ 9, 21, 29, 42, 48]
  , [11, 19, 31, 41, 51]
  , [13, 17, 34, 37, 56]
  , [ 8, 22, 28, 43, 47]
  , [14, 16, 35, 36, 57]
  , [ 7, 23, 27, 44, 46]
  ]

-- | The octant-driver golden: for each level, lift the eight cells' values through the spec's
--   'liftOctList' (the OctreeCell edge), giving the coarse curve + the 7 residual curves.
emitV21OctantLiftGolden :: String
emitV21OctantLiftGolden =
  unlines
    [ "{"
    , "  \"_comment\": \"GENERATED by sixfour-spec / spec-fixtures; do not edit.\","
    , "  \"n_levels\": " <> show v21OctNLevels <> ","
    , "  \"cells\": " <> arr2 v21OctCells <> ","
    , "  \"coarse\": " <> ints coarse <> ","
    , "  \"residuals\": " <> arr2 resCurves
    , "}"
    ]
  where
    perLevel = [ liftOctList [ v21OctCells !! w !! l | w <- [0 .. 7] ] | l <- [0 .. v21OctNLevels - 1] ]
    coarse   = [ co | (co, _)  <- perLevel ]
    resByLvl = [ rs | (_, rs)  <- perLevel ]                                  -- each length 7
    resCurves = [ [ resByLvl !! l !! r | l <- [0 .. v21OctNLevels - 1] ] | r <- [0 .. 6] ]
    ints xs  = "[" <> intercalate ", " (map show xs) <> "]"
    arr2 xss = "[" <> intercalate ", " (map ints xss) <> "]"

-- ---------------------------------------------------------------------------
-- V2.1 opponent-delta golden for s4_v21_opponent_delta
-- ---------------------------------------------------------------------------

-- | The number of value levels in the V2.1 opponent-delta fixture.
v21OppNLevels :: Int
v21OppNLevels = 5

-- | Two bins (each three Q16 curves of 'v21OppNLevels'); the per-level neighbour pair.
v21OppBin1, v21OppBin2 :: BinQ16
v21OppBin1 = BinQ16 [10, 20, 30, 40, 50] [5, 5, 5, 5, 5] [0, 10, 20, 30, 40]
v21OppBin2 = BinQ16 [ 1,  2,  3,  4,  5] [5, 4, 3, 2, 1] [0,  0,  0,  0,  0]

-- | The opponent-delta golden: for each level, the spec's 'labDeltaAt' gives the (L,a,b) delta;
--   reshaped to three output curves (L, a, b).
emitV21OpponentDeltaGolden :: String
emitV21OpponentDeltaGolden =
  unlines
    [ "{"
    , "  \"_comment\": \"GENERATED by sixfour-spec / spec-fixtures; do not edit.\","
    , "  \"n_levels\": " <> show v21OppNLevels <> ","
    , "  \"bin1\": " <> binArr v21OppBin1 <> ","
    , "  \"bin2\": " <> binArr v21OppBin2 <> ","
    , "  \"out_lab\": " <> arr2 [ ls, as, bs ]
    , "}"
    ]
  where
    labs = [ labDeltaAt v21OppBin1 v21OppBin2 l | l <- [0 .. v21OppNLevels - 1] ]
    ls = [ l | (l, _, _) <- labs ]
    as = [ a | (_, a, _) <- labs ]
    bs = [ b | (_, _, b) <- labs ]
    binArr (BinQ16 r g bch) = arr2 [r, g, bch]
    ints xs  = "[" <> intercalate ", " (map show xs) <> "]"
    arr2 xss = "[" <> intercalate ", " (map ints xss) <> "]"

-- ---------------------------------------------------------------------------
-- V2.1 palette-delta golden for s4_v21_palette_delta
-- ---------------------------------------------------------------------------

-- | The value alphabet in the V2.1 palette-delta fixture.
v21PalNLevels :: Int
v21PalNLevels = 6

-- | Two 4-slot palettes, flat SLOT-MAJOR (slot*3 + channel). @palB@'s first two slots are @palA@'s
--   first two REORDERED, so the fixture also exercises the gauge (a slot swap that does not, on its
--   own, change the delta); the remaining slots differ genuinely.
v21PalA, v21PalB :: [Int]
v21PalA = [0, 1, 2,  3, 4, 5,  1, 1, 1,  5, 0, 3]
v21PalB = [3, 4, 5,  0, 1, 2,  1, 1, 1,  2, 2, 2]

-- | The palette-delta golden: the L1 between the two palettes' per-channel value histograms
--   (SixFour.Spec.V21Field.paletteDelta), the temporal metric weight the Zig kernel reproduces.
emitV21PaletteDeltaGolden :: String
emitV21PaletteDeltaGolden =
  unlines
    [ "{"
    , "  \"_comment\": \"GENERATED by sixfour-spec / spec-fixtures; do not edit.\","
    , "  \"n_levels\": " <> show v21PalNLevels <> ","
    , "  \"k\": " <> show (length v21PalA `div` 3) <> ","
    , "  \"pal1\": " <> ints v21PalA <> ","
    , "  \"pal2\": " <> ints v21PalB <> ","
    , "  \"palette_delta\": " <> show (paletteDelta v21PalNLevels v21PalA v21PalB)
    , "}"
    ]
  where ints xs = "[" <> intercalate ", " (map show xs) <> "]"

-- | The 1-D Wasserstein-1 golden: the same two fixture palettes and their W1 (L1 of the per-channel
--   CDFs) from the spec 'paletteW1', plus the drift-vs-jump discriminator vectors (single-slot palettes
--   at level 0, level 1, and the top level) proving the Zig kernel charges the ground distance.
emitV21WDist1DGolden :: String
emitV21WDist1DGolden =
  unlines
    [ "{"
    , "  \"_comment\": \"GENERATED by sixfour-spec / spec-fixtures; do not edit.\","
    , "  \"n_levels\": " <> show v21PalNLevels <> ","
    , "  \"k\": " <> show (length v21PalA `div` 3) <> ","
    , "  \"pal1\": " <> ints v21PalA <> ","
    , "  \"pal2\": " <> ints v21PalB <> ","
    , "  \"w1\": " <> show (paletteW1 v21PalNLevels v21PalA v21PalB) <> ","
    , "  \"drift_w1\": " <> show (paletteW1 v21PalNLevels [0,0,0] [1,0,0]) <> ","
    , "  \"jump_w1\": " <> show (paletteW1 v21PalNLevels [0,0,0] [v21PalNLevels - 1,0,0])
    , "}"
    ]
  where ints xs = "[" <> intercalate ", " (map show xs) <> "]"

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
    , "  \"offsets\": " <> triples (concat (levelsI hp)) <> ","
    , "  \"level_nodes\": " <> nested
    , "}"
    ]
  where
    hp = analyzeFixed haarLeaves
    -- level_nodes[l] = the 2^l node colours at pairing level l (l = 0..depth);
    -- level depth == leaves. The Zig s4_haar_level_nodes must match each byte-exact.
    nested = "[" <> intercalate ", "
               [ triples (levelNodesFixed l hp) | l <- [0 .. treeDepthI hp] ] <> "]"
    triple (l, a, b) = "[" <> intercalate "," (map show [l, a, b]) <> "]"
    triples ts = "[" <> intercalate ", " (map triple ts) <> "]"

-- | The temporal one-level Haar split golden — the cross-language fixture the Zig
-- @temporal_fixture_test.zig@ verifies @s4_haar_split_level@ / @s4_haar_join_level@ against.
-- A fixed, NEGATIVE-heavy 8-frame OKLab sequence (the floor-div sign trap), split into
-- @(low, high)@ by 'SixFour.Spec.TemporalLoop.haarSplitTime' — the temporal half of
-- 'SixFour.Spec.VoxelReduce'.
emitTemporalGolden :: String
emitTemporalGolden =
  unlines
    [ "{"
    , "  \"_comment\": \"GENERATED by sixfour-spec / spec-fixtures — do not edit. SixFour.Spec.TemporalLoop.haarSplitTime.\","
    , "  \"n\": " <> show (length frames) <> ","
    , "  \"frames\": " <> triples frames <> ","
    , "  \"low\": "  <> triples lo <> ","
    , "  \"high\": " <> triples hi
    , "}"
    ]
  where
    frames = [ ( (i * 53 + 7) `mod` 240 - 120
               , (i * 29 + 3) `mod` 240 - 120
               , (i * 71 + 5) `mod` 240 - 120 )
             | i <- [0 .. 7 :: Int] ]
    (lo, hi)         = haarSplitTime frames
    triple (a, b, c) = "[" <> intercalate "," (map show [a, b, c]) <> "]"
    triples ts       = "[" <> intercalate ", " (map triple ts) <> "]"

-- | The RGBT-4D lift + cube-ladder level golden — the cross-language alignment fixture
-- the Zig @rgbt4d_fixture_test.zig@ verifies the @s4_rgbt_lift_quad@ / @s4_cube_lift_level@
-- kernels against (and the same numbers the Swift @RGBT4DGolden@ pins).
emitRGBT4DGolden :: String
emitRGBT4DGolden =
  unlines
    [ "{"
    , "  \"_comment\": \"GENERATED by sixfour-spec / spec-fixtures — do not edit. SixFour.Spec.RGBTLift + CubeLadder.\","
    , "  \"side\": 8,"
    , "  \"grid\": " <> ints grid <> ","
    , "  \"lift_in\": " <> ints [10, 20, 30, 44] <> ","
    , "  \"lift_out\": " <> ints [lr, lg, lb, lt] <> ","
    , "  \"level_coarse\": " <> ints coarse <> ","
    , "  \"level_details\": " <> triples dets
    , "}"
    ]
  where
    grid           = [ ((i * 37 + 11) `mod` 251) - 125 | i <- [0 .. 63] ]
    (lr, lg, lb, lt) = liftQuad (10, 20, 30, 44)
    (coarse, dets) = liftLevel 8 grid
    ints xs        = "[" <> intercalate "," (map show xs) <> "]"
    triple (a, b, c) = "[" <> intercalate "," (map show [a, b, c]) <> "]"
    triples ts     = "[" <> intercalate ", " (map triple ts) <> "]"

-- ---------------------------------------------------------------------------
-- upscale256 golden for trainer/mlx/upscale256.py (the byte-exact buildFloor)
-- ---------------------------------------------------------------------------

-- | The carried drift (slot, dL, da, db) the ExitState exposes — sparse; used BOTH to build
-- 'ugInput's exit state AND to serialize it, so the Python port reads exactly what Haskell ran.
ugDrift :: [(Int, Int, Int, Int)]
ugDrift = [ (3, -40, 5, -5), (7, 60, -3, 3) ]

-- | The killed-bin threshold: a colour is in a curation-killed region iff L > this (cube A wins).
ugKillThreshold :: Int
ugKillThreshold = 63000

-- | A fully-explicit, serializable upscale input. It exercises: the temporal blend (incl. NEGATIVE
-- chroma with a non-multiple-of-4 numerator, so the arithmetic shift @>>2@ differs from truncation),
-- NON-IDENTITY slot alignment (@upMap@ @[3,7]@ vs @[7,3]@ ⇒ σ = [1,0], the match branch is non-trivial),
-- MULTI-ANCHOR substitution (two anchors ⇒ the taken-set arbitration runs), killed-bin arbitration, and
-- the 3×3 candidate neighbourhood. The drift-PRIOR's DECISIVENESS (where the carried exit flips a quantize
-- choice) is gated separately by 'ugPriorCase' (the spec's consumption fixture), since on this cube the
-- gamut distances dwarf the prior.
ugInput :: UpscaleInput
ugInput = UpscaleInput
  { upFrames   = 2
  , upSide     = 2
  , upPalettes = [ [(0, 0, 0), (65535, 8193, -8191)]
                 , [(4097, 0, 0), (61440, 4096, -4096)] ]
  , upMap      = [ [3, 7], [7, 3] ]
  , upGlobal   = [ (0, 0, 0), (32768, 0, 0), (65536, 0, 0) ]
  , upCubeB    = [ V.fromList [0, 1, 1, 0], V.fromList [1, 1, 0, 0] ]
  , upCubeA    = [ V.fromList [0, 2, 2, 0], V.fromList [2, 2, 0, 0] ]
  , upKilled   = \(l, _, _) -> l > ugKillThreshold
  , upExit     = ExitState
      (V.replicate exitSlotCount zeroSlot V.//
         [ (s, SlotExit 0 (fromIntegral dl) (fromIntegral da) (fromIntegral db) 0 0 0)
         | (s, dl, da, db) <- ugDrift ])
      1
  , upAnchors  = [ (32768, 16384, 0), (20000, -6000, 8000) ]
  , upLambda   = 1
  }

-- | The drift-prior DECISIVE case = the spec's consumption fixture: @λ = 0@ picks the nearest slot (0),
-- @λ = 1@ flips to slot 1 because the carried exit drift agrees there. Gates the Python @drift_prior@ +
-- @quantize_prior_among@ byte-exact (the path the full-cube golden does not make decisive).
ugPriorPalette :: [PxQ16]
ugPriorPalette = consumptionFixturePalette

ugPriorMap :: [Int]
ugPriorMap = [0, 1]

ugPriorTarget :: PxQ16
ugPriorTarget = consumptionFixtureTarget

-- The consumption fixture carries a NEGATIVE dL on slot 1 (SlotExit 0 (-5) 0 …); serialise it sparsely.
ugPriorDrift :: [(Int, Int, Int, Int)]
ugPriorDrift = [ (1, -5, 0, 0) ]

ugPriorPick :: Int -> Int
ugPriorPick lam = quantizePrior lam ugPriorPalette prior ugPriorTarget
  where prior = driftPrior consumptionFixtureExit ugPriorMap ugPriorPalette ugPriorTarget

emitUpscaleGolden :: String
emitUpscaleGolden =
  let UpscaleOutput pals planes = upscale256 ugInput
  in unlines
    [ "{"
    , "  \"_comment\": \"GENERATED by sixfour-spec / spec-fixtures — do not edit. Spec.Upscale256.upscale256 = Spec.ModelIO.buildFloor. trainer/mlx/upscale256.py reproduces this byte-exact.\","
    , "  \"input\": {"
    , "    \"frames\": " <> show (upFrames ugInput) <> ","
    , "    \"side\": " <> show (upSide ugInput) <> ","
    , "    \"palettes\": " <> triples2 (upPalettes ugInput) <> ","
    , "    \"map\": " <> ints2 (upMap ugInput) <> ","
    , "    \"global\": " <> triples (upGlobal ugInput) <> ","
    , "    \"cubeB\": " <> ints2 (map V.toList (upCubeB ugInput)) <> ","
    , "    \"cubeA\": " <> ints2 (map V.toList (upCubeA ugInput)) <> ","
    , "    \"killThreshold\": " <> show ugKillThreshold <> ","
    , "    \"exitDrift\": [" <> intercalate ", " [ ints [s, dl, da, db] | (s, dl, da, db) <- ugDrift ] <> "],"
    , "    \"anchors\": " <> triples (upAnchors ugInput) <> ","
    , "    \"lambda\": " <> show (upLambda ugInput)
    , "  },"
    , "  \"output\": {"
    , "    \"palettes\": " <> triples2 pals <> ","
    , "    \"cube\": " <> ints2 (map V.toList planes)
    , "  },"
    , "  \"priorCase\": {"
    , "    \"_doc\": \"drift-prior DECISIVE (consumption fixture): lambda=0 picks slot 0 (nearest), lambda=1 flips to slot 1 (carried exit drift agrees). Gates drift_prior + quantize_prior byte-exact.\","
    , "    \"palette\": " <> triples ugPriorPalette <> ","
    , "    \"map\": " <> ints ugPriorMap <> ","
    , "    \"exitDrift\": [" <> intercalate ", " [ ints [s, dl, da, db] | (s, dl, da, db) <- ugPriorDrift ] <> "],"
    , "    \"target\": " <> triple ugPriorTarget <> ","
    , "    \"pick0\": " <> show (ugPriorPick 0) <> ","
    , "    \"pick1\": " <> show (ugPriorPick 1)
    , "  }"
    , "}"
    ]
  where
    triple (l, a, b) = "[" <> intercalate "," (map show [l, a, b]) <> "]"
    triples ts  = "[" <> intercalate ", " (map triple ts) <> "]"
    triples2 :: [[PxQ16]] -> String
    triples2 tss = "[" <> intercalate ", " (map triples tss) <> "]"
    ints xs     = "[" <> intercalate "," (map show xs) <> "]"
    ints2 xss   = "[" <> intercalate ", " (map ints xss) <> "]"

-- | @--key value@ / @--key=value@ parser (mirrors app/Spec.hs).
parseArgs :: [String] -> [(String, String)]
parseArgs [] = []
parseArgs (kv : rest)
  | take 2 kv == "--", '=' `elem` kv =
      let (k, v) = break (== '=') kv in (k, drop 1 v) : parseArgs rest
parseArgs (k : v : rest)
  | take 2 k == "--" = (k, v) : parseArgs rest
parseArgs (_ : rest) = parseArgs rest

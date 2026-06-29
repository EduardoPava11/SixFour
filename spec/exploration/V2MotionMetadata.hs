{- |
Module      : V2MotionMetadata
Description : EXPLORATION (NOT WIRED, base-only, runghc). Per-frame MOMENTUM stored as a GIF89a
              Application Extension ("S4MOTION1"), PROVABLY off the byte-exact reversible floor.

  Check:  runghc V2MotionMetadata.hs   (base-only, self-contained; no -i flag needed)

  THE OWNER DECISION (2026-06-29): momentum = "which direction is the pixel moving" = a coarse
  optical-flow field, computed DURING 64^3 construction (at capture resolution, BEFORE the 64x64
  decimation, so it carries genuine sub-pixel transport the voxel mass cannot represent). It is
  STORED as GIF89a metadata and used to give the model's encoder more context for the 64^3.

  THE SAFETY CONTRACT (why this does NOT change the floor):
    * GIF89a requires a decoder to SKIP application-extension blocks whose 11-byte identifier it
      does not recognize (the same mechanism NETSCAPE2.0 looping uses). So the reversible
      reconstruction path reads ONLY the image-data blocks and never parses "S4MOTION1".
    * 'decodeFloor' models that path: it extracts image data and ignores every extension. The
      keystone law 'lawMotionExtIsFloorInvariant' proves decodeFloor is byte-for-byte IDENTICAL
      with or without the motion extension, and 'lawMotionCorruptionFloorInvariant' proves even a
      CORRUPTED motion block leaves the reconstructed picture untouched. The floor cannot depend on
      momentum because the floor's decoder does not even read it.
    * CONSEQUENCE (store-for-the-model, strip-for-sharing): because stripping is pixel-lossless,
      the training/corpus GIF can carry the motion field while the shared art GIF can drop it, with
      the law guaranteeing the image is unchanged. The GIF-bloat cost applies only where you keep it.

  WHY IT IS WORTH STORING (not just a cached feature): 'lawMotionCarriesSubGridInfo' exhibits two
  GIFs with IDENTICAL image bytes but DIFFERENT momentum. decodeFloor cannot tell them apart; the
  metadata can. That is the pre-decimation sub-grid information the 64^3 physically discarded. The
  same law simultaneously witnesses floor-independence (same picture) and informativeness (different
  momentum), so the feature earns its complexity.

  SCOPE / HONESTY: this module models the STORAGE format + the floor-invariance contract + the
  encoder-conditioning SHAPE (upsample the coarse 8x8 field to the 64-grid as a derived input,
  never a stored latent axis). It does NOT model the optical-flow ESTIMATOR itself: the estimator
  is a deterministic but off-floor hint, out of scope for byte-exactness (it does not need to be
  cross-device bit-exact, only reproducible for golden-testing the encoder). The "ImageData" bytes
  here are a stand-in for the real LZW stream; what is faithful is the BLOCK STRUCTURE and which
  blocks the floor reads. Base-only, runghc, NOT in cabal/Map/gate. No em-dashes (owner directive).
-}
module V2MotionMetadata where

-- ===========================================================================
-- (1) The coarse per-frame flow field: an 8x8 grid of (dx,dy) per frame.
-- ===========================================================================

-- | The coarse grid is 8x8 per frame. Per-pixel flow would dwarf the image data and gives the model
--   nothing the 64^3 does not already carry; 8x8 is a conditioning hint, not a reconstruction.
gridN :: Int
gridN = 8

-- | A displacement (dx, dy), signed, in capture-resolution pixels.
type Vec = (Int, Int)

-- | One frame's flow: a gridN x gridN grid of displacement vectors.
type FrameFlow = [[Vec]]

-- | The whole motion field: one FrameFlow per frame (the t axis).
type Motion = [FrameFlow]

-- | Displacements are stored as signed bytes; clamp to the representable [-128, 127].
clampS :: Int -> Int
clampS = max (-128) . min 127

-- | Signed value -> unsigned byte (0..255).
toByte :: Int -> Int
toByte v = clampS v + 128

-- | Unsigned byte -> signed value (-128..127).
fromByte :: Int -> Int
fromByte b = b - 128

-- | Generic fixed-size chunker.
chunk :: Int -> [a] -> [[a]]
chunk _ [] = []
chunk n xs = take n xs : chunk n (drop n xs)

-- | Bytes per frame: gridN*gridN cells, 2 bytes each.
frameBytes :: Int
frameBytes = gridN * gridN * 2

-- | Serialize one frame, row-major (dx,dy) -> [dxByte, dyByte].
encodeFrame :: FrameFlow -> [Int]
encodeFrame ff = concat [ [toByte dx, toByte dy] | row <- ff, (dx, dy) <- row ]

-- | Inverse of 'encodeFrame' for a full frameBytes-length chunk.
decodeFrame :: [Int] -> FrameFlow
decodeFrame = chunk gridN . pairUp
  where
    pairUp (x:y:rest) = (fromByte x, fromByte y) : pairUp rest
    pairUp _          = []

-- | Serialize the whole motion payload: [nFrames] ++ per-frame bytes.
encodeMotion :: Motion -> [Int]
encodeMotion m = length m : concatMap encodeFrame m

-- | Inverse of 'encodeMotion'.
decodeMotion :: [Int] -> Motion
decodeMotion []       = []
decodeMotion (n:rest) = map decodeFrame (take n (chunk frameBytes rest))

-- ===========================================================================
-- (2) GIF89a sub-block chunking: a data stream is split into <=255-byte sub-blocks.
-- ===========================================================================

-- | GIF89a sub-blocks carry at most 255 bytes each.
maxSub :: Int
maxSub = 255

-- | Split a payload into GIF89a sub-blocks (each <= 255 bytes).
chunkSub :: [Int] -> [[Int]]
chunkSub = chunk maxSub

-- | Reassemble sub-blocks into the payload.
unchunkSub :: [[Int]] -> [Int]
unchunkSub = concat

-- ===========================================================================
-- (3) The block model: image data (the floor reads these) vs application extensions.
-- ===========================================================================

-- | Our application-extension identifier. (Real GIF89a uses an 11-byte field: 8 name + 3 auth.)
appId :: String
appId = "S4MOTION1"

-- | The subset of GIF89a structure that matters here. ImageData is a stand-in for the LZW stream;
--   AppExt carries an identifier plus its sub-blocks. The floor reads ONLY ImageData.
data Block
  = ImageData [Int]
  | AppExt String [[Int]]
  deriving (Eq, Show)

-- | A GIF is a sequence of blocks.
type Gif = [Block]

-- | Wrap a motion field as a "S4MOTION1" application-extension block.
motionExt :: Motion -> Block
motionExt m = AppExt appId (chunkSub (encodeMotion m))

-- | Read the first S4MOTION1 block, if present, and decode the motion field.
readMotionExt :: Gif -> Maybe Motion
readMotionExt []                              = Nothing
readMotionExt (AppExt idn subs : _) | idn == appId = Just (decodeMotion (unchunkSub subs))
readMotionExt (_ : rest)                      = readMotionExt rest

-- | Remove every S4MOTION1 block (the pixel-lossless "strip for sharing" operation).
stripMotionExt :: Gif -> Gif
stripMotionExt = filter (not . isMotion)
  where
    isMotion (AppExt idn _) = idn == appId
    isMotion _              = False

-- | THE REVERSIBLE FLOOR DECODER. It extracts only image data, IN ORDER, and ignores every
--   extension block. This is the model of "what reconstruction sees"; it never parses S4MOTION1.
decodeFloor :: Gif -> [[Int]]
decodeFloor g = [ bs | ImageData bs <- g ]

-- ===========================================================================
-- (4) Encoder conditioning shape: upsample the coarse 8x8 field to the model grid.
-- ===========================================================================

-- | Nearest-neighbour upsample of a coarse FrameFlow to an n x n conditioning grid (n a multiple of
--   gridN). This is the derived encoder INPUT aligned to the 64-grid, never a stored latent axis.
upsampleFlow :: Int -> FrameFlow -> [[Vec]]
upsampleFlow n ff =
  [ [ ff !! (i * gridN `div` n) !! (j * gridN `div` n) | j <- [0 .. n - 1] ]
  | i <- [0 .. n - 1] ]

-- | Recover the coarse grid from an upsampled field (picks each block's representative cell).
downsampleFlow :: [[Vec]] -> FrameFlow
downsampleFlow big =
  let n      = length big
      factor = n `div` gridN
  in [ [ big !! (i * factor) !! (j * factor) | j <- [0 .. gridN - 1] ]
     | i <- [0 .. gridN - 1] ]

-- ===========================================================================
-- (5) Deterministic, non-constant test fields.
-- ===========================================================================

-- | A non-constant 8x8 flow frame parameterized by a seed (values stay within [-30, 29]).
sampleFrame :: Int -> FrameFlow
sampleFrame seed =
  [ [ ((i + seed) `mod` 60 - 30, (j * 2 - seed) `mod` 60 - 30) | j <- [0 .. gridN - 1] ]
  | i <- [0 .. gridN - 1] ]

-- | A motion field of nf distinct frames.
sampleMotion :: Int -> Motion
sampleMotion nf = [ sampleFrame s | s <- [1 .. nf] ]

-- ===========================================================================
-- (6) Laws.
-- ===========================================================================

-- | The coarse field serializes and deserializes byte-exactly (including the empty field).
lawMotionRoundTrips :: Bool
lawMotionRoundTrips = all ok [0 .. 5]
  where ok nf = let m = sampleMotion nf in decodeMotion (encodeMotion m) == m

-- | Sub-block chunking round-trips and respects the 255-byte cap; non-vacuous (payload > 255 so it
--   genuinely splits into multiple sub-blocks).
lawSubBlockChunking :: Bool
lawSubBlockChunking =
  let p  = encodeMotion (sampleMotion 5)   -- 1 + 5*128 = 641 bytes
      cs = chunkSub p
  in unchunkSub cs == p
       && all (\c -> length c <= maxSub) cs
       && length cs >= 2

-- | A written motion block reads back exactly, even interleaved between image-data blocks.
lawWriteThenReadMotion :: Bool
lawWriteThenReadMotion = all ok [0 .. 5]
  where
    ok nf = let m = sampleMotion nf
                g = [ImageData [1, 2, 3], motionExt m, ImageData [4, 5, 6]]
            in readMotionExt g == Just m

-- | After stripping, no motion is readable.
lawStripThenReadIsNothing :: Bool
lawStripThenReadIsNothing =
  let m = sampleMotion 4
      g = [ImageData [1, 2, 3], motionExt m, ImageData [4, 5, 6]]
  in readMotionExt (stripMotionExt g) == Nothing

-- | KEYSTONE. The reversible floor decode is byte-for-byte identical with or without the motion
--   extension. The picture does not depend on momentum at all.
lawMotionExtIsFloorInvariant :: Bool
lawMotionExtIsFloorInvariant = all ok [0 .. 5]
  where
    ok nf =
      let m       = sampleMotion nf
          img     = [ImageData [10, 20], ImageData [30]]
          withExt = [ImageData [10, 20], motionExt m, ImageData [30]]
      in decodeFloor withExt == decodeFloor img
           && decodeFloor withExt == [[10, 20], [30]]

-- | Even a CORRUPTED motion block leaves the reconstructed picture untouched (and the corruption is
--   real: it changes the decoded motion).
lawMotionCorruptionFloorInvariant :: Bool
lawMotionCorruptionFloorInvariant =
  let m  = sampleMotion 3
      g  = [ImageData [7, 8], motionExt m, ImageData [9]]
      g' = map corrupt g
  in decodeFloor g' == decodeFloor g
       && readMotionExt g' /= readMotionExt g
  where
    corrupt (AppExt idn subs) | idn == appId =
      AppExt idn (map (map (\b -> (b + 13) `mod` 256)) subs)
    corrupt b = b

-- | Momentum carries information the image bytes do NOT: two GIFs with identical image data but
--   different motion are indistinguishable to the floor, distinct to the metadata reader. This is
--   the pre-decimation sub-grid signal, and it simultaneously witnesses floor-independence.
lawMotionCarriesSubGridInfo :: Bool
lawMotionCarriesSubGridInfo =
  let img = [100, 101, 102]
      g1  = [ImageData img, motionExt (sampleMotion 4)]
      g2  = [ImageData img, motionExt (sampleMotion 5)]
  in decodeFloor g1 == decodeFloor g2
       && readMotionExt g1 /= readMotionExt g2

-- | The coarse grid survives the upsample/downsample round trip to the model grid.
lawUpsampleDownsampleCoarse :: Bool
lawUpsampleDownsampleCoarse = all ok [1 .. 4]
  where ok seed = let f = sampleFrame seed in downsampleFlow (upsampleFlow 64 f) == f

-- | Upsampling is block-constant nearest-neighbour: each model-grid cell equals its coarse cell.
lawUpsampleBlockConstant :: Bool
lawUpsampleBlockConstant =
  let f      = sampleFrame 2
      big    = upsampleFlow 64 f
      factor = 64 `div` gridN
  in and [ big !! i !! j == f !! (i `div` factor) !! (j `div` factor)
         | i <- [0 .. 63], j <- [0 .. 63] ]

-- ===========================================================================
-- (7) Runner.
-- ===========================================================================

checks :: [(String, Bool)]
checks =
  [ ("lawMotionRoundTrips",               lawMotionRoundTrips)
  , ("lawSubBlockChunking",               lawSubBlockChunking)
  , ("lawWriteThenReadMotion",            lawWriteThenReadMotion)
  , ("lawStripThenReadIsNothing",         lawStripThenReadIsNothing)
  , ("lawMotionExtIsFloorInvariant",      lawMotionExtIsFloorInvariant)
  , ("lawMotionCorruptionFloorInvariant", lawMotionCorruptionFloorInvariant)
  , ("lawMotionCarriesSubGridInfo",       lawMotionCarriesSubGridInfo)
  , ("lawUpsampleDownsampleCoarse",       lawUpsampleDownsampleCoarse)
  , ("lawUpsampleBlockConstant",          lawUpsampleBlockConstant)
  ]

main :: IO ()
main = do
  let passed = length (filter snd checks)
      total  = length checks
  mapM_ (\(n, b) -> putStrLn ((if b then "PASS  " else "FAIL  ") ++ n)) checks
  putStrLn "------------------------------------------------------------"
  putStrLn ("SUMMARY: " ++ show passed ++ "/" ++ show total ++ " laws PASS")
  putStrLn ""
  let m       = sampleMotion 3
      art     = [ImageData [10, 20], motionExt m, ImageData [30]]
      shared  = stripMotionExt art
  putStrLn ("corpus GIF blocks   : " ++ show (length art) ++ " (image + S4MOTION1)")
  putStrLn ("shared GIF blocks   : " ++ show (length shared) ++ " (motion stripped)")
  putStrLn ("floor decode equal? : " ++ show (decodeFloor art == decodeFloor shared))
  putStrLn ("  corpus floor      : " ++ show (decodeFloor art))
  putStrLn ("  shared floor      : " ++ show (decodeFloor shared))
  putStrLn ("motion in corpus?   : " ++ show (readMotionExt art /= Nothing))
  putStrLn ("motion in shared?   : " ++ show (readMotionExt shared /= Nothing))
  if passed == total then return () else error "some laws FAILED"

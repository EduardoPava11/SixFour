{- |
Module      : SixFour.Gen.GifDecode
Description : Decode the app-family GIF89a bytes back to indices + palettes.

The inverse of "SixFour.Gen.GifWire", used to prove @decode ∘ encode = id@ on
the (indices, RGB-palette) pair and to re-validate the 'CompleteVoxelVolume'
brand from the bytes alone. It understands exactly the dialect the encoder
emits — per-frame Local Color Tables, no Global Color Table, NETSCAPE loop,
disposal-1 frames, a Comment Extension — but the LZW decoder itself is the
standard variable-width GIF algorithm, so a real viewer would read the same
pixels.

Because OKLab→sRGB rounding is lossy, the round-trip identity is at the
__byte__ level: decoded RGB tables equal 'oklabToRGB8' of the encoded palette,
and decoded indices equal the original 'IndexTensor'.
-}
module SixFour.Gen.GifDecode
  ( DecodedGif (..)
  , DecodedFrame (..)
  , decodeGif
  , decodedIndices
  ) where

import           Data.Word           (Word8)
import           Data.Bits           (shiftL, shiftR, (.|.), (.&.), testBit)
import qualified Data.ByteString     as BS
import qualified Data.ByteString.Lazy as BL
import qualified Data.IntMap.Strict  as IM
import qualified Data.Text           as T
import qualified Data.Text.Encoding  as TE

-- | A decoded GIF: canvas size, the frames, and any embedded comment.
data DecodedGif = DecodedGif
  { dgWidth   :: !Int
  , dgHeight  :: !Int
  , dgFrames  :: ![DecodedFrame]
  , dgComment :: !(Maybe T.Text)
  } deriving (Eq, Show)

-- | One frame: its Local Color Table (RGB triples) and its row-major indices.
data DecodedFrame = DecodedFrame
  { dfPalette :: ![(Word8, Word8, Word8)]  -- ^ length = LCT size (256 here)
  , dfIndices :: ![Int]                    -- ^ length = w*h
  } deriving (Eq, Show)

-- | All frames' indices concatenated in @T·H·W@ order — the flat shape an
-- 'SixFour.Spec.Indices.IndexTensor' expects.
decodedIndices :: DecodedGif -> [Int]
decodedIndices = concatMap dfIndices . dgFrames

-- ---------------------------------------------------------------------------
-- Top-level parse
-- ---------------------------------------------------------------------------

decodeGif :: BL.ByteString -> Either String DecodedGif
decodeGif lbs = do
  let bs = BL.toStrict lbs
  rest0 <- expect "GIF89a header" (BS.pack [0x47,0x49,0x46,0x38,0x39,0x61]) bs
  -- logical screen descriptor: w(2) h(2) packed(1) bg(1) aspect(1)
  (w, r1)      <- takeU16 rest0
  (h, r2)      <- takeU16 r1
  (packed, r3) <- takeByte r2
  (_bg, r4)    <- takeByte r3
  (_asp, r5)   <- takeByte r4
  -- skip a Global Color Table if present (the app never writes one)
  r6 <- if testBit packed 7
          then let gctSize = 3 * (1 `shiftL` ((fromIntegral packed .&. 0x07) + 1))
               in dropN gctSize r5
          else Right r5
  (frames, comment) <- blocks w h r6 [] Nothing
  Right (DecodedGif w h (reverse frames) comment)

-- step through extensions / image descriptors / trailer
blocks
  :: Int -> Int -> BS.ByteString
  -> [DecodedFrame] -> Maybe T.Text
  -> Either String ([DecodedFrame], Maybe T.Text)
blocks w h bs acc comment =
  case BS.uncons bs of
    Nothing                -> Left "unexpected EOF (no trailer)"
    Just (0x3B, _)         -> Right (acc, comment)       -- trailer
    Just (0x21, rest)      -> do                          -- extension
      (label, r1) <- takeByte rest
      case label of
        0xFE -> do (txt, r2) <- readSubBlocks r1          -- comment
                   blocks w h r2 acc (Just (TE.decodeUtf8 txt))
        _    -> do (_, r2)   <- readSubBlocks r1          -- skip others
                   blocks w h r2 acc comment
    Just (0x2C, rest)      -> do                          -- image descriptor
      (frame, r1) <- readImage w h rest
      blocks w h r1 (frame : acc) comment
    Just (b, _)            -> Left ("unknown block byte 0x" ++ show b)

-- image descriptor + (optional) LCT + LZW image data
readImage :: Int -> Int -> BS.ByteString -> Either String (DecodedFrame, BS.ByteString)
readImage w h bs = do
  (_l, r1)     <- takeU16 bs
  (_t, r2)     <- takeU16 r1
  (iw, r3)     <- takeU16 r2
  (ih, r4)     <- takeU16 r3
  (packed, r5) <- takeByte r4
  let hasLCT  = testBit packed 7
      lctSize = 1 `shiftL` ((fromIntegral packed .&. 0x07) + 1)
  (palette, r6) <-
    if hasLCT then readPalette lctSize r5
              else Right ([], r5)
  (minCodeSize, r7) <- takeByte r6
  (imgData, r8)     <- readSubBlocks r7
  let idx = lzwDecode (fromIntegral minCodeSize) imgData
      want = iw * ih
  if length idx /= want
    then Left ("frame pixel count " ++ show (length idx) ++ " ≠ " ++ show want)
    else Right (DecodedFrame palette (map fromIntegral idx), r8)

readPalette :: Int -> BS.ByteString -> Either String ([(Word8,Word8,Word8)], BS.ByteString)
readPalette n bs
  | BS.length bs < n * 3 = Left "truncated color table"
  | otherwise =
      let (tbl, rest) = BS.splitAt (n * 3) bs
          triples = [ (BS.index tbl (i*3), BS.index tbl (i*3+1), BS.index tbl (i*3+2))
                    | i <- [0 .. n - 1] ]
      in Right (triples, rest)

-- ---------------------------------------------------------------------------
-- Sub-block de-framing
-- ---------------------------------------------------------------------------

-- | Read length-prefixed sub-blocks until the @0x00@ terminator, returning the
-- concatenated payload and the remaining stream.
readSubBlocks :: BS.ByteString -> Either String (BS.ByteString, BS.ByteString)
readSubBlocks = go []
  where
    go chunks bs = case BS.uncons bs of
      Nothing          -> Left "EOF inside sub-blocks"
      Just (0x00, r)   -> Right (BS.concat (reverse chunks), r)
      Just (n, r)      ->
        let len = fromIntegral n
        in if BS.length r < len
             then Left "truncated sub-block"
             else let (chunk, r') = BS.splitAt len r
                  in go (chunk : chunks) r'

-- ---------------------------------------------------------------------------
-- LZW decode (standard variable-width GIF)
-- ---------------------------------------------------------------------------

-- | Decode one frame's image-data payload to a flat list of palette indices.
lzwDecode :: Int -> BS.ByteString -> [Int]
lzwDecode minCodeSize payload = run
  where
    clearCode = 1 `shiftL` minCodeSize
    endCode   = clearCode + 1

    initTable :: IM.IntMap [Word8]
    initTable = IM.fromList [ (i, [fromIntegral i]) | i <- [0 .. clearCode - 1] ]

    -- a bit cursor over the payload: (byteIndex, bitOffset)
    totalBits = 8 * BS.length payload

    readCode :: Int -> Int -> Maybe (Int, Int)
    readCode size pos
      | pos + size > totalBits = Nothing
      | otherwise =
          let bitAt i = let byte = BS.index payload (i `shiftR` 3)
                        in if testBit byte (i .&. 7) then 1 else 0 :: Int
              code = foldr (\b acc -> acc `shiftL` 1 .|. b)
                           0
                           [ bitAt (pos + j) | j <- [0 .. size - 1] ]
          in Just (code, pos + size)

    run :: [Int]
    run = case readCode (minCodeSize + 1) 0 of
            Nothing -> []
            Just (first, p1)
              | first == clearCode ->
                  -- standard: stream opens with a clear; start fresh
                  case readCode (minCodeSize + 1) p1 of
                    Nothing -> []
                    Just (c, p2) -> firstCode c p2
              | otherwise -> firstCode first p1

    -- the very first data code is always a literal already in the base table;
    -- emit it, then iterate with the base table (no entry added yet)
    firstCode :: Int -> Int -> [Int]
    firstCode c pos =
      let e = IM.findWithDefault [] c initTable
      in map fromIntegral e ++ goLoop initTable c e (minCodeSize + 1) (endCode + 1) pos

    goLoop :: IM.IntMap [Word8] -> Int -> [Word8] -> Int -> Int -> Int -> [Int]
    goLoop tbl prevCode prevEntry size next pos =
      case readCode size pos of
        Nothing -> []
        Just (code, pos')
          | code == endCode   -> []
          | code == clearCode ->
              -- reset to the base table and re-read a fresh literal
              case readCode (minCodeSize + 1) pos' of
                Nothing -> []
                Just (c, pos'') ->
                  let e = IM.findWithDefault [] c initTable
                  in map fromIntegral e
                     ++ goLoop initTable c e (minCodeSize + 1) (endCode + 1) pos''
          | otherwise ->
              let entry = case IM.lookup code tbl of
                            Just e  -> e
                            Nothing -> prevEntry ++ [head prevEntry]  -- KwKwK
                  newEntry = prevEntry ++ [head entry]
                  tbl'     = IM.insert next newEntry tbl
                  next'    = next + 1
                  -- grow when the table has filled the current width
                  size'    = if next' == (1 `shiftL` size) && size < 12
                               then size + 1 else size
              in map fromIntegral entry
                 ++ goLoop tbl' code entry size' next' pos'

-- ---------------------------------------------------------------------------
-- Byte-stream readers
-- ---------------------------------------------------------------------------

expect :: String -> BS.ByteString -> BS.ByteString -> Either String BS.ByteString
expect name prefix bs
  | prefix `BS.isPrefixOf` bs = Right (BS.drop (BS.length prefix) bs)
  | otherwise                 = Left ("expected " ++ name)

takeByte :: BS.ByteString -> Either String (Int, BS.ByteString)
takeByte bs = case BS.uncons bs of
  Just (b, r) -> Right (fromIntegral b, r)
  Nothing     -> Left "unexpected EOF reading byte"

takeU16 :: BS.ByteString -> Either String (Int, BS.ByteString)
takeU16 bs
  | BS.length bs < 2 = Left "unexpected EOF reading u16"
  | otherwise        =
      let lo = fromIntegral (BS.index bs 0)
          hi = fromIntegral (BS.index bs 1)
      in Right (lo .|. (hi `shiftL` 8), BS.drop 2 bs)

dropN :: Int -> BS.ByteString -> Either String BS.ByteString
dropN n bs
  | BS.length bs < n = Left "unexpected EOF skipping bytes"
  | otherwise        = Right (BS.drop n bs)

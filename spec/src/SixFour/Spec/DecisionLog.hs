{- |
Module      : SixFour.Spec.DecisionLog
Description : The SF64 replay container — every user decision is a logged,
              replayable training example (the flywheel's wire format).

Design §3.3 (@docs/COLOR-ATLAS.md@). A TLV container ported from QUAD's
@Container.hs@ discipline (@/Users/daniel/QUAD-Spec/src/Quad/Container.hs@):
magic @"SF64"@, a 16-byte header, then tagged chunks. The container is the
self-play record: it syncs Mac↔iPhone ONLY (the QUAD NN-PATH federated split)
and the board is RE-DERIVABLE by folding the DECN chunk — the BORD snapshot is
sanity/golden material, never the source of truth ('AtlasMove.boardFromLog' is
the replay-determinism seam).

Wire layout (all little-endian):

  * __Header (16 B)__ — magic u32 @"SF64"@ | version u32 = 1 |
    flags u16 (bit0 = hasUserDecisions) | entryCount u16 | reserved u32 = 0.
  * __DECN__ — fixed 32 B entries (judge resolution: the pad is an explicit
    NAMED field, pinned in the sum check and asserted zero on read):
    tag u8 | bin x,y,z 3×u8 | wDelta i16 Q8.8 | flags u16 |
    anchor 3×i32 Q16 (Compare mirrors winHash u32 + loseHash u32 into the
    first 8 B, third i32 = 0) | winHash u32 | loseHash u32 | pad u32 = 0.
    Explicit sum: @1+3+2+2+12+4+4+4 = 32@ ('lawEntrySize32').
  * __GNOM__ — per candidate: u32 hash + 384×f32 genome (the genomes the
    Compare hashes reference).
  * __VDST__ — per search root: u32 genome hash + u8 count ≤ 8 +
    count × (u32 move-vocab index + f32 visit fraction) — the policy
    distillation targets.
  * __BORD__ — one @[16,16,16,6]@ float32 board snapshot per session open
    (24576 floats, bin-major, channel-minor).

Floats are stored as IEEE-754 binary32 ('castFloatToWord32'), so the
in-memory log keeps 'Float' for those planes — encode∘decode is then EXACT
('lawRoundTrip' over 'normalizeLog'-canonical logs). Decoding is total
('Maybe'), skips unknown tags ('lawUnknownTagSkip'), and accepts the
chunks in any order ('lawTLVOrderInsensitive').
-}
module SixFour.Spec.DecisionLog
  ( -- * Layout constants (compile-time sums)
    sf64Magic
  , sf64Version
  , headerSize
  , decnEntrySize
  , decnFieldSizes
  , genomeFloats
  , boardFloats
  , visitCap
  , embeddingFloats
    -- * The log
  , SF64Log(..)
  , emptyLog
  , wellFormedLog
  , normalizeLog
  , boardSnapshot
    -- * Encode / decode
  , encodeEntry
  , decodeEntry
  , encodeChunks
  , assembleContainer
  , encodeLog
  , decodeLog
    -- * Laws (predicates; QuickCheck'd in Properties.DecisionLog)
  , lawRoundTrip
  , lawTLVOrderInsensitive
  , lawEntrySize32
  , lawUnknownTagSkip
  , lawReplayMonotone
  , lawCompareEmbeddingRoundTrip
  , lawBackwardCompatNoCMPE
  ) where

import           Data.Bits   (shiftL, shiftR, (.&.), (.|.))
import           Data.Int    (Int16, Int32)
import           Data.Word   (Word8, Word16, Word32)
import           GHC.Float   (castFloatToWord32, castWord32ToFloat)
import qualified Data.Vector as V

import SixFour.Spec.AtlasBoard (BinIdx(..), Board16(..), boardBins, boardChannels)
import SixFour.Spec.AtlasMove  (CurationMove(..), GenomeHash(..), Q88(..),
                                boardFromLog)

-- ---------------------------------------------------------------------------
-- Layout constants
-- ---------------------------------------------------------------------------

-- | The magic bytes @"SF64"@, as they appear on the wire.
sf64Magic :: [Word8]
sf64Magic = [0x53, 0x46, 0x36, 0x34]  -- 'S' 'F' '6' '4'

-- | Container version.
sf64Version :: Word32
sf64Version = 1

-- | Header bytes: magic 4 + version 4 + flags 2 + entryCount 2 + reserved 4.
headerSize :: Int
headerSize = 16

-- | The named DECN field sizes, IN ORDER (the explicit sum the judge asked
-- for): tag, bin×3, wDelta, flags, anchor (3×i32), winHash, loseHash, pad.
decnFieldSizes :: [Int]
decnFieldSizes = [1, 3, 2, 2, 12, 4, 4, 4]

-- | @1+3+2+2+12+4+4+4 = 32@.
decnEntrySize :: Int
decnEntrySize = sum decnFieldSizes

-- | A GNOM genome is exactly 384 floats (the σ-pair genome's flat layout).
genomeFloats :: Int
genomeFloats = 384

-- | A BORD snapshot is @16³ × 6 = 24576@ floats.
boardFloats :: Int
boardFloats = boardBins * boardChannels

-- | A VDST root stores at most 8 visit fractions (the oracle's top-k width).
visitCap :: Int
visitCap = 8

-- | A CMPE Compare embedding is exactly 770 floats: the 'PreferenceUpdate'
-- @atlasEmbedding@ (256 leaves × 3 ++ [coverage, beauty]) — the BT-update input
-- frozen at pick time so replay is self-contained (no GNOM dependency).
embeddingFloats :: Int
embeddingFloats = 770

-- ---------------------------------------------------------------------------
-- The log
-- ---------------------------------------------------------------------------

-- | One session's replay record. Float planes are 'Float' (binary32 on the
-- wire — keeping them 'Float' in memory makes the round trip exact).
data SF64Log = SF64Log
  { logDecisions :: [CurationMove]                      -- ^ DECN, decision order
  , logGenomes   :: [(GenomeHash, [Float])]             -- ^ GNOM, 384 floats each
  , logVisits    :: [(GenomeHash, [(Word32, Float)])]   -- ^ VDST, ≤ 8 per root
  , logBoards    :: [V.Vector Float]                    -- ^ BORD, 24576 floats each
  , logCompareEmbeddings
      :: [(GenomeHash, GenomeHash, [Float], [Float])]   -- ^ CMPE: per Compare,
        -- (winHash, loseHash, winner 770-f embedding, loser 770-f embedding) —
        -- the BT-update input frozen at pick time (additive chunk, version-stable).
  } deriving (Eq, Show)

-- | The empty session.
emptyLog :: SF64Log
emptyLog = SF64Log [] [] [] [] []

-- | The wire can only carry: in-range u8 bins, exactly-384-float genomes,
-- ≤ 8 visit rows, exactly-24576-float boards, ≤ 65535 decisions.
wellFormedLog :: SF64Log -> Bool
wellFormedLog (SF64Log ds gs vs bs es) =
  length ds <= 65535
    && all binOk ds
    && all ((== genomeFloats) . length . snd) gs
    && all ((<= visitCap) . length . snd) vs
    && all ((== boardFloats) . V.length) bs
    && all embOk es
  where
    embOk (_, _, w, l) = length w == embeddingFloats && length l == embeddingFloats
    binOk (ToggleBin bi)      = u8Bin bi
    binOk (WeightRegion bi _) = u8Bin bi
    binOk (PinAnchor bi c)    = u8Bin bi && i32Triple c
    binOk (Compare _ _)       = True
    u8Bin (BinIdx (x, y, z))  = all (\v -> v >= 0 && v < 256) [x, y, z]
    i32Triple (l, a, b)       = all fitsI32 [l, a, b]
    fitsI32 v = v >= fromIntegral (minBound :: Int32)
                  && v <= fromIntegral (maxBound :: Int32)

-- | Canonicalise an arbitrary log into its wire image (what encode∘decode
-- yields): bins masked to u8, anchors wrapped to i32, genomes padded/truncated
-- to 384, visits truncated to 8, boards padded/truncated to 24576, decisions
-- truncated to 65535. Identity on 'wellFormedLog' inputs.
normalizeLog :: SF64Log -> SF64Log
normalizeLog (SF64Log ds gs vs bs es) = SF64Log
  (map normMove (take 65535 ds))
  [ (h, pad 0 genomeFloats g) | (h, g) <- gs ]
  [ (h, take visitCap v) | (h, v) <- vs ]
  [ V.fromList (pad 0 boardFloats (V.toList b)) | b <- bs ]
  [ (wh, lh, pad 0 embeddingFloats w, pad 0 embeddingFloats l) | (wh, lh, w, l) <- es ]
  where
    pad z n xs = take n (xs ++ repeat z)
    normMove (ToggleBin bi)       = ToggleBin (normBin bi)
    normMove (WeightRegion bi d)  = WeightRegion (normBin bi) d
    normMove (PinAnchor bi (l, a, b)) =
      PinAnchor (normBin bi) (wrapI32 l, wrapI32 a, wrapI32 b)
    normMove m@(Compare _ _)      = m
    normBin (BinIdx (x, y, z))    = BinIdx (x .&. 255, y .&. 255, z .&. 255)
    wrapI32 v = fromIntegral (fromIntegral v :: Int32)

-- | The BORD plane of a board: 24576 floats, bin-major × channel-minor
-- (anchor COLOURS are not in the snapshot — the snapshot is sanity material;
-- the colours replay from the DECN PinAnchor entries).
boardSnapshot :: Board16 -> V.Vector Float
boardSnapshot b = V.fromList
  [ realToFrac (ch V.! ix)
  | ix <- [0 .. boardBins - 1]
  , ch <- [ bMassPalettes b, bMassPixels b, bCoverage b
          , bWeight b, bKill b, bAnchorMask b ] ]

-- ---------------------------------------------------------------------------
-- LE primitives
-- ---------------------------------------------------------------------------

u16le :: Word16 -> [Word8]
u16le v = [ fromIntegral (v `shiftR` s) | s <- [0, 8] ]

u32le :: Word32 -> [Word8]
u32le v = [ fromIntegral (v `shiftR` s) | s <- [0, 8, 16, 24] ]

i16le :: Int16 -> [Word8]
i16le = u16le . fromIntegral

i32le :: Int32 -> [Word8]
i32le = u32le . fromIntegral

f32le :: Float -> [Word8]
f32le = u32le . castFloatToWord32

takeU16 :: [Word8] -> Maybe (Word16, [Word8])
takeU16 (a : b : r) = Just (fromIntegral a .|. (fromIntegral b `shiftL` 8), r)
takeU16 _           = Nothing

takeU32 :: [Word8] -> Maybe (Word32, [Word8])
takeU32 (a : b : c : d : r) = Just
  ( fromIntegral a .|. (fromIntegral b `shiftL` 8)
      .|. (fromIntegral c `shiftL` 16) .|. (fromIntegral d `shiftL` 24)
  , r )
takeU32 _ = Nothing

takeI16 :: [Word8] -> Maybe (Int16, [Word8])
takeI16 bs = do (v, r) <- takeU16 bs; pure (fromIntegral v, r)

takeI32 :: [Word8] -> Maybe (Int32, [Word8])
takeI32 bs = do (v, r) <- takeU32 bs; pure (fromIntegral v, r)

takeF32 :: [Word8] -> Maybe (Float, [Word8])
takeF32 bs = do (v, r) <- takeU32 bs; pure (castWord32ToFloat v, r)

takeN :: Int -> [Word8] -> Maybe ([Word8], [Word8])
takeN n bs = let (h, t) = splitAt n bs
             in if length h == n then Just (h, t) else Nothing

times :: Int -> ([Word8] -> Maybe (a, [Word8])) -> [Word8] -> Maybe ([a], [Word8])
times 0 _ bs = Just ([], bs)
times n p bs = do (x, r) <- p bs; (xs, r') <- times (n - 1) p r; pure (x : xs, r')

-- ---------------------------------------------------------------------------
-- DECN entries
-- ---------------------------------------------------------------------------

moveTag :: CurationMove -> Word8
moveTag ToggleBin{}    = 0
moveTag WeightRegion{} = 1
moveTag PinAnchor{}    = 2
moveTag Compare{}      = 3

-- | One fixed-32-byte DECN entry (the wire image of a 'normalizeLog'-
-- canonical move).
encodeEntry :: CurationMove -> [Word8]
encodeEntry m =
  [moveTag m] ++ binB ++ i16le wDelta ++ u16le 0
    ++ concatMap i32le anchor ++ u32le winH ++ u32le loseH ++ u32le 0
  where
    (binB, wDelta, anchor, winH, loseH) = case m of
      ToggleBin (BinIdx (x, y, z)) ->
        (b3 x y z, 0, [0, 0, 0], 0, 0)
      WeightRegion (BinIdx (x, y, z)) (Q88 d) ->
        (b3 x y z, d, [0, 0, 0], 0, 0)
      PinAnchor (BinIdx (x, y, z)) (l, a, b) ->
        (b3 x y z, 0, [fromIntegral l, fromIntegral a, fromIntegral b], 0, 0)
      Compare (GenomeHash w) (GenomeHash l) ->
        -- mirrors the hashes into the anchor field's first 8 B (design §3.3)
        ([0, 0, 0], 0, [fromIntegral w, fromIntegral l, 0], w, l)
    b3 x y z = [fromIntegral x, fromIntegral y, fromIntegral z]

-- | Parse one entry; 'Nothing' on truncation, unknown tag, or non-zero pad
-- (the pad is ASSERTED zero on read — judge resolution §3.3).
decodeEntry :: [Word8] -> Maybe (CurationMove, [Word8])
decodeEntry bs0 = do
  ((tag, bx, by, bz), bs1) <- case bs0 of
    (t : x : y : z : r) -> Just ((t, x, y, z), r)
    _                   -> Nothing
  (wDelta, bs2) <- takeI16 bs1
  (_flags, bs3) <- takeU16 bs2
  (anchor, bs4) <- times 3 takeI32 bs3
  (winH,   bs5) <- takeU32 bs4
  (loseH,  bs6) <- takeU32 bs5
  (padW,   bs7) <- takeU32 bs6
  if padW /= 0 then Nothing else do
    let bi = BinIdx (fromIntegral bx, fromIntegral by, fromIntegral bz)
    mv <- case tag of
      0 -> Just (ToggleBin bi)
      1 -> Just (WeightRegion bi (Q88 wDelta))
      2 -> case anchor of
             [l, a, b] -> Just (PinAnchor bi ( fromIntegral l
                                             , fromIntegral a
                                             , fromIntegral b ))
             _         -> Nothing
      3 -> Just (Compare (GenomeHash winH) (GenomeHash loseH))
      _ -> Nothing
    pure (mv, bs7)

-- ---------------------------------------------------------------------------
-- Chunks
-- ---------------------------------------------------------------------------

tagDECN, tagGNOM, tagVDST, tagBORD, tagCMPE :: [Word8]
tagDECN = map (fromIntegral . fromEnum) "DECN"
tagGNOM = map (fromIntegral . fromEnum) "GNOM"
tagVDST = map (fromIntegral . fromEnum) "VDST"
tagBORD = map (fromIntegral . fromEnum) "BORD"
tagCMPE = map (fromIntegral . fromEnum) "CMPE"  -- Compare embeddings (additive, v1-skip-compatible)

-- | The four chunk payloads of a (canonical) log, in canonical order. Exposed
-- so 'lawTLVOrderInsensitive' can permute REAL chunks through
-- 'assembleContainer'.
encodeChunks :: SF64Log -> [([Word8], [Word8])]
encodeChunks lg0 =
  [ (tagDECN, concatMap encodeEntry (logDecisions lg))
  , (tagGNOM, concat [ u32le h ++ concatMap f32le g
                     | (GenomeHash h, g) <- logGenomes lg ])
  , (tagVDST, concat [ u32le h ++ [fromIntegral (length v)]
                         ++ concat [ u32le mi ++ f32le fr | (mi, fr) <- v ]
                     | (GenomeHash h, v) <- logVisits lg ])
  , (tagBORD, concat [ concatMap f32le (V.toList b) | b <- logBoards lg ])
  , (tagCMPE, concat [ u32le wh ++ u32le lh
                         ++ concatMap f32le w ++ concatMap f32le l
                     | (GenomeHash wh, GenomeHash lh, w, l) <- logCompareEmbeddings lg ])
  ]
  where lg = normalizeLog lg0

-- | Header + the given chunks, in the given order.
assembleContainer :: Word16 -> [([Word8], [Word8])] -> [Word8]
assembleContainer entryCount chunks =
  sf64Magic ++ u32le sf64Version
    ++ u16le (if entryCount > 0 then 1 else 0)   -- flags bit0 = hasUserDecisions
    ++ u16le entryCount
    ++ u32le 0                                    -- reserved
    ++ concat [ tag ++ u32le (fromIntegral (length pay)) ++ pay
              | (tag, pay) <- chunks ]

-- | The canonical encoding: header + DECN, GNOM, VDST, BORD.
encodeLog :: SF64Log -> [Word8]
encodeLog lg =
  assembleContainer (fromIntegral (length (logDecisions (normalizeLog lg))))
                    (encodeChunks lg)

-- | Total decode. Checks magic, version, reserved = 0, the per-entry pad,
-- payload shapes, and that entryCount matches the DECN entries. Unknown
-- chunk tags are SKIPPED (forward compatibility); recognised chunks may
-- arrive in any order and accumulate in arrival order.
decodeLog :: [Word8] -> Maybe SF64Log
decodeLog bs0 = do
  (magic, bs1) <- takeN 4 bs0
  if magic /= sf64Magic then Nothing else do
    (ver, bs2) <- takeU32 bs1
    if ver /= sf64Version then Nothing else do
      (_flags, bs3) <- takeU16 bs2
      (cnt,    bs4) <- takeU16 bs3
      (res,    bs5) <- takeU32 bs4
      if res /= 0 then Nothing else do
        lg <- goChunks emptyLog bs5
        if length (logDecisions lg) /= fromIntegral cnt
          then Nothing
          else Just lg
  where
    goChunks acc [] = Just acc
    goChunks acc bs = do
      (tag, r1) <- takeN 4 bs
      (len, r2) <- takeU32 r1
      (pay, r3) <- takeN (fromIntegral len) r2
      acc' <- dispatch acc tag pay
      goChunks acc' r3
    dispatch acc tag pay
      | tag == tagDECN = do
          ms <- parseMany decodeEntry pay
          pure acc { logDecisions = logDecisions acc ++ ms }
      | tag == tagGNOM = do
          gs <- parseMany parseGenome pay
          pure acc { logGenomes = logGenomes acc ++ gs }
      | tag == tagVDST = do
          vs <- parseMany parseVisit pay
          pure acc { logVisits = logVisits acc ++ vs }
      | tag == tagBORD = do
          bds <- parseMany parseBoard pay
          pure acc { logBoards = logBoards acc ++ bds }
      | tag == tagCMPE = do
          es <- parseMany parseCompareEmb pay
          pure acc { logCompareEmbeddings = logCompareEmbeddings acc ++ es }
      | otherwise = Just acc   -- unknown tag: skip (forward compatibility)

-- | Run a sub-parser to payload exhaustion ('Nothing' on trailing garbage).
parseMany :: ([Word8] -> Maybe (a, [Word8])) -> [Word8] -> Maybe [a]
parseMany _ [] = Just []
parseMany p bs = do
  (x, r) <- p bs
  xs <- parseMany p r
  pure (x : xs)

parseGenome :: [Word8] -> Maybe ((GenomeHash, [Float]), [Word8])
parseGenome bs = do
  (h, r1) <- takeU32 bs
  (g, r2) <- times genomeFloats takeF32 r1
  pure ((GenomeHash h, g), r2)

parseVisit :: [Word8] -> Maybe ((GenomeHash, [(Word32, Float)]), [Word8])
parseVisit bs = do
  (h, r1) <- takeU32 bs
  (n, r2) <- case r1 of { (c : r) -> Just (fromIntegral c :: Int, r); _ -> Nothing }
  if n > visitCap then Nothing else do
    (v, r3) <- times n (\b -> do (mi, b1) <- takeU32 b
                                 (fr, b2) <- takeF32 b1
                                 pure ((mi, fr), b2)) r2
    pure ((GenomeHash h, v), r3)

parseBoard :: [Word8] -> Maybe (V.Vector Float, [Word8])
parseBoard bs = do
  (fs, r) <- times boardFloats takeF32 bs
  pure (V.fromList fs, r)

parseCompareEmb :: [Word8]
                -> Maybe ((GenomeHash, GenomeHash, [Float], [Float]), [Word8])
parseCompareEmb bs = do
  (wh, r1) <- takeU32 bs
  (lh, r2) <- takeU32 r1
  (w,  r3) <- times embeddingFloats takeF32 r2
  (l,  r4) <- times embeddingFloats takeF32 r3
  pure ((GenomeHash wh, GenomeHash lh, w, l), r4)

-- ---------------------------------------------------------------------------
-- Laws
-- ---------------------------------------------------------------------------

-- | encode → decode recovers the canonical log (identity on well-formed logs).
lawRoundTrip :: SF64Log -> Bool
lawRoundTrip lg = decodeLog (encodeLog lg) == Just (normalizeLog lg)

-- | A permutation of the four chunks decodes to the SAME log (one chunk per
-- tag, so per-tag accumulation is order-free).
lawTLVOrderInsensitive :: SF64Log -> [Int] -> Bool
lawTLVOrderInsensitive lg perm =
  let chunks = encodeChunks lg
      n      = fromIntegral (length (logDecisions (normalizeLog lg)))
      order  = dedup [ p `mod` length chunks | p <- perm ]
      shuffd = [ chunks !! i | i <- order ]
                 ++ [ c | (i, c) <- zip [0 ..] chunks, i `notElem` order ]
  in decodeLog (assembleContainer n shuffd) == decodeLog (assembleContainer n chunks)
  where
    dedup []       = []
    dedup (x : xs) = x : dedup (filter (/= x) xs)

-- | The explicit field-size sum AND the encoded length: every entry is 32 B.
lawEntrySize32 :: CurationMove -> Bool
lawEntrySize32 m =
  decnEntrySize == 32
    && decnFieldSizes == [1, 3, 2, 2, 12, 4, 4, 4]
    && length (encodeEntry m) == decnEntrySize

-- | Splicing an UNKNOWN chunk anywhere among the four leaves the decode
-- unchanged (forward compatibility).
lawUnknownTagSkip :: SF64Log -> Int -> [Word8] -> Bool
lawUnknownTagSkip lg at junk =
  let chunks  = encodeChunks lg
      n       = fromIntegral (length (logDecisions (normalizeLog lg)))
      pos     = at `mod` (length chunks + 1)
      unknown = (map (fromIntegral . fromEnum) "ZZZZ", junk)
      spliced = take pos chunks ++ [unknown] ++ drop pos chunks
  in decodeLog (assembleContainer n spliced) == Just (normalizeLog lg)

-- | Replay is monotone: appending decisions never disturbs the replay of the
-- earlier prefix (left-fold associativity of 'boardFromLog' — the property
-- that lets the device extend the log incrementally).
lawReplayMonotone :: Board16 -> [CurationMove] -> [CurationMove] -> Bool
lawReplayMonotone b xs ys =
  boardFromLog b (xs ++ ys) == boardFromLog (boardFromLog b xs) ys

-- | The CMPE chunk round-trips: a log carrying Compare embeddings encodes and
-- decodes to the canonical log, embeddings intact (the BT-update input survives).
lawCompareEmbeddingRoundTrip
  :: [(GenomeHash, GenomeHash, [Float], [Float])] -> Bool
lawCompareEmbeddingRoundTrip es =
  let lg = emptyLog { logCompareEmbeddings = es }
  in fmap logCompareEmbeddings (decodeLog (encodeLog lg))
       == Just (logCompareEmbeddings (normalizeLog lg))

-- | Backward compatibility: a container assembled WITHOUT a CMPE chunk (a v1 log)
-- decodes to a log with NO Compare embeddings — old logs read cleanly, the new
-- field defaults empty. (The additive chunk is version-stable; no v1 reader breaks.)
lawBackwardCompatNoCMPE :: SF64Log -> Bool
lawBackwardCompatNoCMPE lg0 =
  let lg      = (normalizeLog lg0) { logCompareEmbeddings = [] }
      noCmpe  = filter (\(t, _) -> t /= tagCMPE) (encodeChunks lg)
      n       = fromIntegral (length (logDecisions lg))
  in decodeLog (assembleContainer n noCmpe)
       == Just (lg { logCompareEmbeddings = [] })

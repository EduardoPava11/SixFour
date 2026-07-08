{- |
Module      : SixFour.Spec.CaptureRecord
Description : THE SHUTTER'S LEDGER — one deterministic CBOR record per capture, written when the burst completes, carrying exactly the data the pooled sums CANNOT: the weave word (the temporal ORDER of rung frames, provably invisible to every conserved marginal — "SixFour.Spec.WeaveOrder" 'SixFour.Spec.WeaveOrder.lawOrderIsInvisibleToTheMeasure'), the measured per-frame timing, and the burst's bin sums + realized GCT. The encoding is the RFC 8949 CORE DETERMINISTIC subset (definite lengths only, minimal-length integer heads, map keys sorted bytewise on their encodings), so the SAME record always yields the SAME bytes — reproducibility is a property of the format, not a discipline. The Swift writer is a hand-port gated by the golden bytes pinned here ('lawGoldenRecordPinned'); any drift between what the app writes and what the study/training tooling reads is a broken law, not a debugging session.

== Why CBOR, why deterministic

The record is for STUDY and for TRAINING (the S/K/I system is learned from
these records): it must be readable by any off-device tool (CBOR is an IETF
standard with decoders everywhere), zero-dependency to write (the encoder
below is ~60 lines of pure byte arithmetic — well inside the Tier-2
hand-written rule), and canonical (two captures with equal content produce
byte-identical records, so records can be content-addressed, deduplicated,
and diffed). JSON (the existing @CaptureBundle@) keeps the human-readable
role; this record is the machine-exact sibling, additive not a replacement.

== The subset

Majors 0 (unsigned), 2 (bytes), 3 (text, ASCII-restricted for totality),
4 (array), 5 (map). No floats ever (the carrier is integer sums and
integer microseconds — floats would break bit-exactness), no indefinite
lengths, no tags. 'decode' is a total parser of exactly this subset;
'lawDecodeInvertsEncode' + 'lawEncodingIsCanonicallyStable' pin that encode
and decode are exact inverses on canonical values and that re-encoding a
decoded record is byte-identical.

== The record

'CaptureRecord' — version, window (320 cs), base delay (5 cs), the WEAVE
WORD as rung indices in capture order, measured per-frame intervals in
integer MICROSECONDS (exact; the Swift side rounds its float milliseconds
once, at the boundary), the 16×16×3 u64 bin sums (the transitive carrier —
the 32² and 16² views are exact derivations, never stored twice), and the
768-byte realized GCT. Keystone: 'lawWeaveSurvivesTheRecord' — the weave
word round-trips through the bytes IN ORDER, so the record carries exactly
the information "SixFour.Spec.WeaveOrder" proves the measure loses.
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none
module SixFour.Spec.CaptureRecord
  ( -- * The deterministic CBOR subset
    Cbor (..)
  , encodeHead
  , encode
  , canonical
  , decode
    -- * The capture record
  , CaptureRecord (..)
  , recordToCbor
  , encodeRecord
  , weaveFromCbor
  , goldenRecord
  , goldenRecordBytes
    -- * Laws
  , lawHeadsAreMinimal
  , lawMapKeysSortedBytewise
  , lawDecodeInvertsEncode
  , lawEncodingIsCanonicallyStable
  , lawWeaveSurvivesTheRecord
  , lawGoldenRecordPinned
  ) where

import Data.Bits (shiftR, (.&.))
import Data.Char (chr, ord)
import Data.List (sortOn)
import Data.Word (Word8)

import SixFour.Spec.WeaveOrder (WeaveRung (..), rungIndex)

-- ─────────────────────────────────────────────────────────────────────────────
-- The deterministic CBOR subset
-- ─────────────────────────────────────────────────────────────────────────────

-- | The value AST of the subset: unsigned integers, byte strings, ASCII
-- text, arrays, maps. Deliberately no floats, no tags, no negatives — the
-- capture carrier is unsigned-exact.
data Cbor
  = CUInt Integer
  | CBytes [Word8]
  | CText String
  | CArray [Cbor]
  | CMap [(Cbor, Cbor)]
  deriving (Eq, Show)

-- | A CBOR head with the MINIMAL-length argument encoding (RFC 8949
-- §4.2.1): the argument goes in the initial byte if < 24, else in the
-- shortest of 1/2/4/8 big-endian bytes. Negative arguments clamp to 0
-- (totality; the subset is unsigned).
encodeHead :: Int -> Integer -> [Word8]
encodeHead major nRaw
  | n < 24         = [ib n]
  | n < 0x100      = ib 24 : be 1 n
  | n < 0x10000    = ib 25 : be 2 n
  | n < 0x100000000 = ib 26 : be 4 n
  | otherwise      = ib 27 : be 8 n
  where
    n = max 0 nRaw
    ib info = fromIntegral (major * 32 + fromInteger info `mod` 32)
      -- info < 32 always: literal 24..27 or n < 24
    be :: Int -> Integer -> [Word8]
    be w v = [ fromIntegral (v `shiftR` (8 * i)) | i <- [w - 1, w - 2 .. 0] ]

-- | Deterministic encode. Maps are sorted bytewise on their ENCODED keys
-- (the core deterministic rule) with duplicate keys dropped; text is
-- ASCII-clamped (@?@ for anything above 127 — totality, and the record's
-- keys are ASCII by construction).
encode :: Cbor -> [Word8]
encode (CUInt n)   = encodeHead 0 n
encode (CBytes bs) = encodeHead 2 (toInteger (length bs)) ++ bs
encode (CText s)   = encodeHead 3 (toInteger (length s)) ++ map asciiByte s
encode (CArray xs) = encodeHead 4 (toInteger (length xs)) ++ concatMap encode xs
encode (CMap kvs)  =
  encodeHead 5 (toInteger (length kvs')) ++ concatMap pair kvs'
  where
    kvs' = dedupe (sortOn (encode . fst) kvs)
    dedupe (a : b : rest)
      | encode (fst a) == encode (fst b) = dedupe (a : rest)
      | otherwise                        = a : dedupe (b : rest)
    dedupe xs = xs
    pair (k, v) = encode k ++ encode v

-- | ASCII clamp: code points ≥ 128 become @?@ so text length == byte
-- length and the encoding never needs multi-byte UTF-8.
asciiByte :: Char -> Word8
asciiByte c = let o = ord c in if o < 128 then fromIntegral o else 63

-- | The canonical form 'encode' actually serializes: text ASCII-clamped,
-- maps recursively sorted and deduplicated. 'decode' returns values in this
-- form, which is what makes round-tripping exact.
canonical :: Cbor -> Cbor
canonical (CUInt n)   = CUInt (max 0 n)
canonical (CBytes bs) = CBytes bs
canonical (CText s)   = CText (map (chr . fromIntegral . asciiByte) s)
canonical (CArray xs) = CArray (map canonical xs)
canonical (CMap kvs)  =
  CMap (dedupe (sortOn (encode . fst) [ (canonical k, canonical v) | (k, v) <- kvs ]))
  where
    dedupe (a : b : rest)
      | encode (fst a) == encode (fst b) = dedupe (a : rest)
      | otherwise                        = a : dedupe (b : rest)
    dedupe xs = xs

-- | Total parser of exactly the subset: returns the value and the remaining
-- bytes, or 'Nothing' on anything outside the subset (indefinite lengths,
-- tags, floats, negatives, truncation).
decode :: [Word8] -> Maybe (Cbor, [Word8])
decode [] = Nothing
decode (b : rest) =
  case (major, info) of
    (0, _) -> do (n, r) <- arg
                 pure (CUInt n, r)
    (2, _) -> do (n, r) <- arg
                 (bs, r') <- takeN n r
                 pure (CBytes bs, r')
    (3, _) -> do (n, r) <- arg
                 (bs, r') <- takeN n r
                 pure (CText (map (chr . fromIntegral) bs), r')
    (4, _) -> do (n, r) <- arg
                 (xs, r') <- items n r
                 pure (CArray xs, r')
    (5, _) -> do (n, r) <- arg
                 (kvs, r') <- pairs n r
                 pure (CMap kvs, r')
    _      -> Nothing
  where
    major = fromIntegral b `div` 32 :: Int
    info  = fromIntegral b `mod` 32 :: Int
    arg | info < 24 = Just (toInteger info, rest)
        | info == 24 = beN 1
        | info == 25 = beN 2
        | info == 26 = beN 4
        | info == 27 = beN 8
        | otherwise = Nothing
    beN w = do (bs, r) <- takeN (toInteger (w :: Int)) rest
               pure (foldl (\acc x -> acc * 256 + toInteger x) 0 bs, r)
    takeN :: Integer -> [Word8] -> Maybe ([Word8], [Word8])
    takeN n xs =
      let k = fromInteger n
      in if n >= 0 && length xs >= k then Just (splitAt k xs) else Nothing
    items :: Integer -> [Word8] -> Maybe ([Cbor], [Word8])
    items 0 r = Just ([], r)
    items n r = do (x, r') <- decode r
                   (xs, r'') <- items (n - 1) r'
                   pure (x : xs, r'')
    pairs :: Integer -> [Word8] -> Maybe ([(Cbor, Cbor)], [Word8])
    pairs 0 r = Just ([], r)
    pairs n r = do (k, r') <- decode r
                   (v, r'') <- decode r'
                   (kvs, r''') <- pairs (n - 1) r''
                   pure ((k, v) : kvs, r''')

-- ─────────────────────────────────────────────────────────────────────────────
-- The capture record
-- ─────────────────────────────────────────────────────────────────────────────

-- | What the shutter writes. Empty lists are legal (a field the burst did
-- not produce is absent-as-empty, never invented).
data CaptureRecord = CaptureRecord
  { crVersion          :: Integer     -- ^ record format version (1)
  , crWindowCs         :: Integer     -- ^ the burst window, cs (320)
  , crBaseDelayCs      :: Integer     -- ^ the timeline quantum, cs (5)
  , crWeave            :: [WeaveRung] -- ^ THE ORDER — rung frames, capture order
  , crFrameIntervalsUs :: [Integer]   -- ^ measured per-frame intervals, µs
  , crSums16           :: [Integer]   -- ^ 16×16×3 u64 bin sums, row-major (or [])
  , crGct              :: [Word8]     -- ^ realized 768-byte GCT (or [])
  } deriving (Eq, Show)

-- | The record as a CBOR map. Keys are short ASCII text; the deterministic
-- encoder sorts them bytewise, so key order here is documentation only.
recordToCbor :: CaptureRecord -> Cbor
recordToCbor cr = CMap
  [ (CText "v",     CUInt (crVersion cr))
  , (CText "win",   CUInt (crWindowCs cr))
  , (CText "d0",    CUInt (crBaseDelayCs cr))
  , (CText "weave", CArray [ CUInt (toInteger (rungIndex p)) | p <- crWeave cr ])
  , (CText "dtus",  CArray (map CUInt (crFrameIntervalsUs cr)))
  , (CText "s16",   CArray (map CUInt (crSums16 cr)))
  , (CText "gct",   CBytes (crGct cr))
  ]

-- | The record's deterministic bytes — the whole point in one function.
encodeRecord :: CaptureRecord -> [Word8]
encodeRecord = encode . recordToCbor

-- | Read the weave word back out of a decoded record (rung indices 0/1/2 →
-- 'W64'/'W32'/'W16'; anything else refuses). The inverse the keystone law
-- exercises.
weaveFromCbor :: Cbor -> Maybe [WeaveRung]
weaveFromCbor (CMap kvs) =
  case [ v | (CText "weave", v) <- kvs ] of
    [CArray xs] -> traverse fromIdx xs
    _           -> Nothing
  where
    fromIdx (CUInt 0) = Just W64
    fromIdx (CUInt 1) = Just W32
    fromIdx (CUInt 2) = Just W16
    fromIdx _         = Nothing
weaveFromCbor _ = Nothing

-- | The golden sample: version 1, the shipped window, a two-block weave
-- @[16] ++ [32,64,64]@ (the 1-then-2:1 orders, 8 units), three measured
-- intervals, tiny sums, a 3-byte GCT stub. Small enough to eyeball, real
-- enough to pin every field's encoding.
goldenRecord :: CaptureRecord
goldenRecord = CaptureRecord
  { crVersion          = 1
  , crWindowCs         = 320
  , crBaseDelayCs      = 5
  , crWeave            = [W16, W32, W64, W64]
  , crFrameIntervalsUs = [50000, 50000, 50000]
  , crSums16           = [1, 2, 3]
  , crGct              = [0, 1, 2]
  }

-- | The pinned deterministic bytes of 'goldenRecord' — a LITERAL, never
-- recomputed: the Swift writer's parity gate and this encoder's own
-- regression pin ('lawGoldenRecordPinned').
goldenRecordBytes :: [Word8]
goldenRecordBytes =
  [ 0xA7                                            -- map(7)
  , 0x61, 0x76, 0x01                                -- "v": 1
  , 0x62, 0x64, 0x30, 0x05                          -- "d0": 5
  , 0x63, 0x67, 0x63, 0x74, 0x43, 0x00, 0x01, 0x02  -- "gct": h'000102'
  , 0x63, 0x73, 0x31, 0x36, 0x83, 0x01, 0x02, 0x03  -- "s16": [1,2,3]
  , 0x63, 0x77, 0x69, 0x6E, 0x19, 0x01, 0x40        -- "win": 320
  , 0x64, 0x64, 0x74, 0x75, 0x73                    -- "dtus":
  , 0x83, 0x19, 0xC3, 0x50, 0x19, 0xC3, 0x50, 0x19, 0xC3, 0x50 -- [50000 ×3]
  , 0x65, 0x77, 0x65, 0x61, 0x76, 0x65              -- "weave":
  , 0x84, 0x02, 0x01, 0x00, 0x00                    -- [2,1,0,0] = 16,32,64,64
  ]

-- ─────────────────────────────────────────────────────────────────────────────
-- Laws
-- ─────────────────────────────────────────────────────────────────────────────

-- | Minimal heads at every boundary: 23 is immediate, 24 takes one byte,
-- 256 two, 65536 four, 2^32 eight — and never longer.
lawHeadsAreMinimal :: Bool
lawHeadsAreMinimal =
  map (length . encodeHead 0)
      [0, 23, 24, 255, 256, 65535, 65536, 4294967295, 4294967296]
    == [1, 1, 2, 2, 3, 3, 5, 5, 9]

-- | Encoded map keys are strictly increasing bytewise — the core
-- deterministic ordering, checked on the record's own map.
lawMapKeysSortedBytewise :: CaptureRecord -> Bool
lawMapKeysSortedBytewise cr =
  case canonical (recordToCbor cr) of
    CMap kvs -> strictlyIncreasing [ encode k | (k, _) <- kvs ]
    _        -> False
  where
    strictlyIncreasing (a : b : rest) = a < b && strictlyIncreasing (b : rest)
    strictlyIncreasing _              = True

-- | Decode inverts encode on canonical values, consuming every byte.
lawDecodeInvertsEncode :: Cbor -> Bool
lawDecodeInvertsEncode v =
  decode (encode v) == Just (canonical v, [])

-- | Canonical stability: re-encoding a decoded encoding is byte-identical.
-- Two writers that both satisfy this law can never disagree on bytes.
lawEncodingIsCanonicallyStable :: Cbor -> Bool
lawEncodingIsCanonicallyStable v =
  case decode (encode v) of
    Just (v', []) -> encode v' == encode v
    _             -> False

-- | KEYSTONE: the weave word survives the record IN ORDER. The measure
-- cannot carry the order ("SixFour.Spec.WeaveOrder"); these bytes can, and
-- exactly.
lawWeaveSurvivesTheRecord :: [WeaveRung] -> Bool
lawWeaveSurvivesTheRecord w =
  case decode (encodeRecord goldenRecord { crWeave = w }) of
    Just (v, []) -> weaveFromCbor v == Just w
    _            -> False

-- | The golden bytes are pinned: the encoder reproduces them, byte for
-- byte. This is the Swift hand-port's parity gate.
lawGoldenRecordPinned :: Bool
lawGoldenRecordPinned = encodeRecord goldenRecord == goldenRecordBytes

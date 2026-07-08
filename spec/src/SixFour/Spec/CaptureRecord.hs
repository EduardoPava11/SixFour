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

== Version 2 — the independent rungs

When the multi-scale ladder captures the three rungs as SEPARATE exposures
("SixFour.Spec.MultiScaleCapture"), the derived-pyramid premise of @s16@
("stored once, derived exactly") breaks BY DESIGN: the 64\/32\/16 streams
are independent evidence, so storing all three is non-redundant. Version 2
adds five keys, version-gated so version-1 bytes never change
('lawGoldenRecordPinned' stays pinned):

* @c64@ \/ @c32@ \/ @c16@ — per-rung burst volumes as u64 sums arrays.
  Independent mode writes all three; derived mode writes @c16@ only and
  leaves the others absent-as-empty (the record convention).
* @ev@ — per-rung 'RungExposure' triples, fine→coarse: duration µs, ISO
  milli-units, EV offset in CENTISTOPS. The EV offset is SIGNED (the fine
  base may sit below the metered reference), and the subset has no major 1
  — signed values ride the 'zigzag' convention INSIDE major 0
  ('lawZigzagRoundTrips').
* @tel@ — the "SixFour.Spec.RungTelemetry" snapshot ('TelemetrySnapshot'):
  per-rung arrival counts, per-rung significance N, and the independence
  co-movement statistic, all unsigned.

'goldenRecordV2' \/ 'goldenRecordV2Bytes' pin the v2 encoding
('lawGoldenRecordV2Pinned'); 'lawV1DecodesUnderV2Reader' pins that a v2
reader is total over v1 records (missing keys read as absent-as-empty).
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none
module SixFour.Spec.CaptureRecord
  ( -- * The deterministic CBOR subset
    Cbor (..)
  , encodeHead
  , encode
  , canonical
  , decode
    -- * Signed values inside major 0
  , zigzag
  , unzigzag
    -- * The capture record
  , CaptureRecord (..)
  , RungExposure (..)
  , TelemetrySnapshot (..)
  , recordToCbor
  , encodeRecord
  , weaveFromCbor
  , versionFromCbor
  , cubeFromCbor
  , exposuresFromCbor
  , telemetryFromCbor
  , goldenRecord
  , goldenRecordBytes
  , goldenRecordV2
  , goldenRecordV2Bytes
    -- * Laws
  , lawHeadsAreMinimal
  , lawMapKeysSortedBytewise
  , lawZigzagRoundTrips
  , lawDecodeInvertsEncode
  , lawEncodingIsCanonicallyStable
  , lawWeaveSurvivesTheRecord
  , lawWeaveSurvivesTheRecordV2
  , lawRungFieldsSurviveTheRecord
  , lawV1DecodesUnderV2Reader
  , lawGoldenRecordPinned
  , lawGoldenRecordV2Pinned
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
-- Signed values inside major 0
-- ─────────────────────────────────────────────────────────────────────────────

-- | The subset has no major 1, so signed quantities (EV offsets below the
-- fine reference) ride major 0 under the zigzag convention: @n ↦ 2n@ for
-- @n ≥ 0@, @-n ↦ 2n-1@ for @n > 0@ (so 0,-1,1,-2,2 → 0,1,2,3,4). Always
-- non-negative, always minimal-head-encodable; 'unzigzag' inverts exactly
-- ('lawZigzagRoundTrips').
zigzag :: Integer -> Integer
zigzag n
  | n >= 0    = 2 * n
  | otherwise = negate (2 * n) - 1

-- | Inverse of 'zigzag': even words are non-negative halves, odd words are
-- negative.
unzigzag :: Integer -> Integer
unzigzag m
  | even m    = m `div` 2
  | otherwise = negate ((m + 1) `div` 2)

-- ─────────────────────────────────────────────────────────────────────────────
-- The capture record
-- ─────────────────────────────────────────────────────────────────────────────

-- | One rung's realized exposure — INTEGER micro-fields only (the
-- no-floats rule): what the ladder's @setExposureModeCustom@ actually set,
-- in units exact enough that no rounding ever happens twice.
data RungExposure = RungExposure
  { reDurationUs   :: Integer -- ^ exposure duration, µs (unsigned)
  , reIsoMilli     :: Integer -- ^ ISO in milli-units (ISO 100 = 100000; unsigned)
  , reEvCentistops :: Integer -- ^ EV offset vs the fine reference, CENTISTOPS —
                              --   SIGNED; rides 'zigzag' on the wire
  } deriving (Eq, Show)

-- | The "SixFour.Spec.RungTelemetry" snapshot the burst leaves behind, all
-- unsigned. Rung lists run fine→coarse (64, 32, 16).
data TelemetrySnapshot = TelemetrySnapshot
  { tsArrivals           :: [Integer] -- ^ per-rung arrival pulse counts
  , tsSampleVolume       :: [Integer] -- ^ per-rung significance N (sample volumes)
  , tsComovementPermille :: Integer   -- ^ independence co-movement statistic,
                                      --   permille (1000 = fully determined =
                                      --   the fell-back-to-derived warning)
  } deriving (Eq, Show)

-- | What the shutter writes. Empty lists are legal (a field the burst did
-- not produce is absent-as-empty, never invented). The version field GATES
-- THE WIRE SHAPE: version 1 emits exactly the seven original keys (bytes
-- pinned forever by 'lawGoldenRecordPinned'); version 2 adds the five
-- independent-rung keys.
data CaptureRecord = CaptureRecord
  { crVersion          :: Integer     -- ^ record format version (1 or 2)
  , crWindowCs         :: Integer     -- ^ the burst window, cs (320)
  , crBaseDelayCs      :: Integer     -- ^ the timeline quantum, cs (5)
  , crWeave            :: [WeaveRung] -- ^ THE ORDER — rung frames, capture order
  , crFrameIntervalsUs :: [Integer]   -- ^ measured per-frame intervals, µs
  , crSums16           :: [Integer]   -- ^ 16×16×3 u64 bin sums, row-major (or [])
  , crGct              :: [Word8]     -- ^ realized 768-byte GCT (or [])
  , crCube64           :: [Integer]   -- ^ v2: 64-rung independent volume u64 sums (or [])
  , crCube32           :: [Integer]   -- ^ v2: 32-rung independent volume u64 sums (or [])
  , crCube16           :: [Integer]   -- ^ v2: 16-rung volume u64 sums — derived
                                      --   mode writes ONLY this cube (or [])
  , crExposures        :: [RungExposure] -- ^ v2: per-rung exposure, fine→coarse (or [])
  , crTelemetry        :: Maybe TelemetrySnapshot -- ^ v2: telemetry snapshot
                                      --   ('Nothing' encodes as the empty array)
  } deriving (Eq, Show)

-- | The record as a CBOR map. Keys are short ASCII text; the deterministic
-- encoder sorts them bytewise, so key order here is documentation only.
-- The v2 keys appear only when @'crVersion' ≥ 2@ — a version-1 record's
-- bytes are exactly what they were before version 2 existed.
recordToCbor :: CaptureRecord -> Cbor
recordToCbor cr = CMap (v1Fields ++ v2Fields)
  where
    v1Fields =
      [ (CText "v",     CUInt (crVersion cr))
      , (CText "win",   CUInt (crWindowCs cr))
      , (CText "d0",    CUInt (crBaseDelayCs cr))
      , (CText "weave", CArray [ CUInt (toInteger (rungIndex p)) | p <- crWeave cr ])
      , (CText "dtus",  CArray (map CUInt (crFrameIntervalsUs cr)))
      , (CText "s16",   CArray (map CUInt (crSums16 cr)))
      , (CText "gct",   CBytes (crGct cr))
      ]
    v2Fields
      | crVersion cr >= 2 =
          [ (CText "c64", CArray (map CUInt (crCube64 cr)))
          , (CText "c32", CArray (map CUInt (crCube32 cr)))
          , (CText "c16", CArray (map CUInt (crCube16 cr)))
          , (CText "ev",  CArray (map exposureToCbor (crExposures cr)))
          , (CText "tel", telemetryToCbor (crTelemetry cr))
          ]
      | otherwise = []

-- | One rung's exposure as a fixed triple @[duration_us, iso_milli,
-- zigzag(ev_centistops)]@ — the one place a signed field enters the wire.
exposureToCbor :: RungExposure -> Cbor
exposureToCbor e = CArray
  [ CUInt (reDurationUs e)
  , CUInt (reIsoMilli e)
  , CUInt (zigzag (reEvCentistops e))
  ]

-- | The snapshot as a fixed triple @[arrivals, sampleVolumes, comovement]@;
-- an absent snapshot is the empty array (absent-as-empty).
telemetryToCbor :: Maybe TelemetrySnapshot -> Cbor
telemetryToCbor Nothing   = CArray []
telemetryToCbor (Just ts) = CArray
  [ CArray (map CUInt (tsArrivals ts))
  , CArray (map CUInt (tsSampleVolume ts))
  , CUInt (tsComovementPermille ts)
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

-- | Read the version field back out of a decoded record — the first thing
-- a v2 reader looks at.
versionFromCbor :: Cbor -> Maybe Integer
versionFromCbor (CMap kvs) =
  case [ v | (CText "v", v) <- kvs ] of
    [CUInt n] -> Just n
    _         -> Nothing
versionFromCbor _ = Nothing

-- | Read one per-rung cube (@\"c64\"@ \/ @\"c32\"@ \/ @\"c16\"@) back out of
-- a decoded record. A MISSING key reads as the empty cube — that one rule
-- is what makes the v2 reader total over v1 records
-- ('lawV1DecodesUnderV2Reader'); a PRESENT-but-malformed value still
-- refuses.
cubeFromCbor :: String -> Cbor -> Maybe [Integer]
cubeFromCbor key (CMap kvs) =
  case [ v | (CText k, v) <- kvs, k == key ] of
    []          -> Just []
    [CArray xs] -> traverse uintOf xs
    _           -> Nothing
cubeFromCbor _ _ = Nothing

-- | Read the per-rung exposures back out of a decoded record, un-zigzagging
-- the EV offsets. Missing key reads as no exposures (a v1 or derived-mode
-- record).
exposuresFromCbor :: Cbor -> Maybe [RungExposure]
exposuresFromCbor (CMap kvs) =
  case [ v | (CText "ev", v) <- kvs ] of
    []          -> Just []
    [CArray xs] -> traverse fromTriple xs
    _           -> Nothing
  where
    fromTriple (CArray [CUInt d, CUInt i, CUInt z]) =
      Just (RungExposure d i (unzigzag z))
    fromTriple _ = Nothing
exposuresFromCbor _ = Nothing

-- | Read the telemetry snapshot back out of a decoded record. Missing key
-- and the empty array both read as no snapshot; the outer 'Maybe' is parse
-- success, the inner is presence.
telemetryFromCbor :: Cbor -> Maybe (Maybe TelemetrySnapshot)
telemetryFromCbor (CMap kvs) =
  case [ v | (CText "tel", v) <- kvs ] of
    []          -> Just Nothing
    [CArray []] -> Just Nothing
    [CArray [CArray as, CArray ns, CUInt c]] -> do
      as' <- traverse uintOf as
      ns' <- traverse uintOf ns
      pure (Just (TelemetrySnapshot as' ns' c))
    _           -> Nothing
telemetryFromCbor _ = Nothing

-- | The unsigned leaf every array accessor shares.
uintOf :: Cbor -> Maybe Integer
uintOf (CUInt n) = Just n
uintOf _         = Nothing

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
  , crCube64           = []
  , crCube32           = []
  , crCube16           = []
  , crExposures        = []
  , crTelemetry        = Nothing
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

-- | The version-2 golden: the v1 sample plus every independent-rung field
-- populated small-but-real — three cubes, three exposures whose durations
-- AND ISOs double per rung (time gives some stops, gain the rest —
-- 'SixFour.Spec.CaptureDiversity.lawCadenceSpreadNeedsGainToTile'), a
-- NEGATIVE fine EV offset (a quarter-stop below the metered reference,
-- pinning the zigzag odd branch on the wire), and a telemetry snapshot
-- whose sample volumes are the 1:8:64 lattice
-- ('SixFour.Spec.RungTelemetry.lawDerivedSignificanceLattice').
goldenRecordV2 :: CaptureRecord
goldenRecordV2 = goldenRecord
  { crVersion   = 2
  , crCube64    = [4, 5]
  , crCube32    = [6]
  , crCube16    = [7, 8, 9]
  , crExposures =
      [ RungExposure 12500  1000 (-25) -- fine:   short, low gain, below reference
      , RungExposure 25000  2000 100   -- mid:    +1 stop
      , RungExposure 50000  4000 200   -- coarse: +2 stops
      ]
  , crTelemetry = Just TelemetrySnapshot
      { tsArrivals           = [64, 32, 16]
      , tsSampleVolume       = [1, 8, 64]
      , tsComovementPermille = 250
      }
  }

-- | The pinned deterministic bytes of 'goldenRecordV2' — hand-derived like
-- the v1 literal, never recomputed ('lawGoldenRecordV2Pinned'). Note the
-- bytewise key order interleaves old and new keys: @v \< d0 \< ev \< c16 \<
-- c32 \< c64 \< gct \< s16 \< tel \< win \< dtus \< weave@ (shorter encoded
-- keys sort first, then ASCII).
goldenRecordV2Bytes :: [Word8]
goldenRecordV2Bytes =
  [ 0xAC                                            -- map(12)
  , 0x61, 0x76, 0x02                                -- "v": 2
  , 0x62, 0x64, 0x30, 0x05                          -- "d0": 5
  , 0x62, 0x65, 0x76                                -- "ev":
  , 0x83                                            --   3 rung triples
  , 0x83, 0x19, 0x30, 0xD4, 0x19, 0x03, 0xE8, 0x18, 0x31
      -- [12500, 1000, zigzag(-25) = 49]
  , 0x83, 0x19, 0x61, 0xA8, 0x19, 0x07, 0xD0, 0x18, 0xC8
      -- [25000, 2000, zigzag(100) = 200]
  , 0x83, 0x19, 0xC3, 0x50, 0x19, 0x0F, 0xA0, 0x19, 0x01, 0x90
      -- [50000, 4000, zigzag(200) = 400]
  , 0x63, 0x63, 0x31, 0x36, 0x83, 0x07, 0x08, 0x09  -- "c16": [7,8,9]
  , 0x63, 0x63, 0x33, 0x32, 0x81, 0x06              -- "c32": [6]
  , 0x63, 0x63, 0x36, 0x34, 0x82, 0x04, 0x05        -- "c64": [4,5]
  , 0x63, 0x67, 0x63, 0x74, 0x43, 0x00, 0x01, 0x02  -- "gct": h'000102'
  , 0x63, 0x73, 0x31, 0x36, 0x83, 0x01, 0x02, 0x03  -- "s16": [1,2,3]
  , 0x63, 0x74, 0x65, 0x6C                          -- "tel":
  , 0x83                                            --   [arrivals, N, comovement]
  , 0x83, 0x18, 0x40, 0x18, 0x20, 0x10              --   [64,32,16]
  , 0x83, 0x01, 0x08, 0x18, 0x40                    --   [1,8,64]
  , 0x18, 0xFA                                      --   250 permille
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

-- | Zigzag is a non-negative-valued exact bijection: every signed integer
-- rides major 0 and comes back unchanged.
lawZigzagRoundTrips :: Integer -> Bool
lawZigzagRoundTrips n = zigzag n >= 0 && unzigzag (zigzag n) == n

-- | The weave word survives a VERSION-2 record in order too — adding keys
-- changed nothing about the keystone.
lawWeaveSurvivesTheRecordV2 :: [WeaveRung] -> Bool
lawWeaveSurvivesTheRecordV2 w =
  case decode (encodeRecord goldenRecordV2 { crWeave = w }) of
    Just (v, []) -> weaveFromCbor v == Just w
    _            -> False

-- | Every independent-rung field survives the bytes exactly: cubes as
-- written, exposures with their SIGNED EV offsets un-zigzagged, the
-- telemetry snapshot (or its absence) intact. Decode inverts encode on the
-- v2 record. Unsigned fields must be non-negative (the writer's carrier is
-- u64; the encoder clamps, it never invents sign).
lawRungFieldsSurviveTheRecord
  :: [Integer] -> [Integer] -> [Integer]
  -> [RungExposure] -> Maybe TelemetrySnapshot -> Bool
lawRungFieldsSurviveTheRecord c64 c32 c16 es tel =
  case decode (encodeRecord r) of
    Just (v, []) ->
      cubeFromCbor "c64" v == Just c64
        && cubeFromCbor "c32" v == Just c32
        && cubeFromCbor "c16" v == Just c16
        && exposuresFromCbor v == Just es
        && telemetryFromCbor v == Just tel
    _ -> False
  where
    r = goldenRecordV2 { crCube64 = c64, crCube32 = c32, crCube16 = c16
                       , crExposures = es, crTelemetry = tel }

-- | A v2 reader is TOTAL over v1 records: the pinned v1 golden bytes decode,
-- the version reads 1, the weave reads back, and every v2 accessor reads
-- absent-as-empty instead of refusing. Old records never break.
lawV1DecodesUnderV2Reader :: Bool
lawV1DecodesUnderV2Reader =
  case decode goldenRecordBytes of
    Just (v, []) ->
      versionFromCbor v == Just 1
        && weaveFromCbor v == Just [W16, W32, W64, W64]
        && cubeFromCbor "c64" v == Just []
        && cubeFromCbor "c32" v == Just []
        && cubeFromCbor "c16" v == Just []
        && exposuresFromCbor v == Just []
        && telemetryFromCbor v == Just Nothing
    _ -> False

-- | The v2 golden bytes are pinned: the encoder reproduces the hand-derived
-- literal byte for byte — the Swift v2 writer's parity gate — while the v1
-- golden stays pinned untouched ('lawGoldenRecordPinned' still holds on the
-- SAME bytes it always did).
lawGoldenRecordV2Pinned :: Bool
lawGoldenRecordV2Pinned = encodeRecord goldenRecordV2 == goldenRecordV2Bytes

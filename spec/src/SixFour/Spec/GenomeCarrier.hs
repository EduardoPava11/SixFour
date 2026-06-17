{- |
Module      : SixFour.Spec.GenomeCarrier
Description : Byte codec for the genome-in-GIF S4GN payload — Int32 LE Q16 in a
              GIF89a Application-Extension block, golden-pinned, codegen-mandatory.

Every exported GIF carries the chosen 384-DOF σ-pair genome inside a standards-compliant
GIF89a Application-Extension (@0x21 0xFF@) block so a receiver can pull it out and
seed\/blend it into their own taste ('SixFour.Spec.GenomeBlend').

== Element type is Int32 LE Q16, NOT int16

The shipped genome is @SIMD3\<Int32\>@ with @|L| ≤ 65536@, @|a|,|b| ≤ 26214@ (generators
~74k) — int16 (max 32767) silently truncates and breaks the round-trip
('lawQ16RoundTripExact'). The genome is serialized in @flattenHaar@ order as Int32 LE Q16,
behind the 24-byte versioned header ('S4GNHeader'), with a CRC32 footer over
@header || coeffs@.

== Wire shape

@
  0x21 0xFF                 -- Application-Extension introducer
  0x0B                      -- block size = 11
  \"SIXFOUR1\" ++ \"G10\"       -- the EXACTLY-11-byte identifier
  <data sub-blocks>         -- each: <len 1..255> <len bytes>
  0x00                      -- block terminator
@

The body = @header(24) || coeffs(4·n) || crc32(4)@; for the canonical @n = 384@ that is
@24 + 1536 + 4 = 1564@ bytes ⇒ 'subBlockCount' = 7 sub-blocks (6×255 + 34). The codec is
length-self-describing: it round-trips ANY coefficient count, so the laws are not pinned to
384 (the @384@ constants describe only the canonical genome).

== Extraction is TOTAL

'extractGenomeBlock' scans for the marker but never decodes LZW frames, and returns a
'CarrierError' that separates @NoBlock@ (absent — a normal GIF, or one whose block a
re-save dropped) from @Corrupt@ (present but bad magic\/CRC) from @VersionMismatch@
(incompatible MAJOR). This three-way distinction is the honest "your look didn't survive
transcoding" signal the UX needs (it maps onto 'SixFour.Spec.GenomeBlend.Extracted').

Re-save survival is FILE-LEVEL only: a GIF→MP4 transcode (or a tool that rewrites
extensions) drops the block — that surfaces as @NoBlock@, not silent corruption.

GHC-boot-only. Laws are exported predicates, to be QuickCheck'd in
@Properties.GenomeCarrier@ (test wiring pending — this module lands at build step 6).
-}
module SixFour.Spec.GenomeCarrier
  ( -- * Types
    S4GNHeader(..)
  , GenomePayload(..)
  , CarrierError(..)
    -- * Constants
  , appExtIntroducer
  , blockIdentifier
  , payloadBytes
  , totalBytes
  , subBlockCount
    -- * Codec
  , encodeGenomeBlock
  , extractGenomeBlock
  , crc32
    -- * Laws (to be QuickCheck'd in Properties.GenomeCarrier)
  , lawEmbedExtractRoundTrip
  , lawGif89aValidity
  , lawCapacityFits
  , lawQ16RoundTripExact
  , lawCRCRejectsCorruption
  , lawVersionTolerance
  ) where

import Data.Bits  (complement, shiftL, shiftR, xor, (.&.), (.|.))
import Data.Int   (Int32)
import Data.List  (foldl', isPrefixOf, tails)
import Data.Word  (Word8, Word16, Word32)

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------

-- | The 24-byte versioned header (magic @\"S4GN\"@ + these fields + reserved padding).
data S4GNHeader = S4GNHeader
  { s4Major        :: Word8   -- ^ major version (bumped on incompatible layout).
  , s4Minor        :: Word8   -- ^ minor version (forward-compatible additions).
  , s4Flags        :: Word16  -- ^ feature flags (e.g. deviceIdHash present).
  , s4Dof          :: Word16  -- ^ DOF, sourced from @NetContract.lookSigmaPairDOF@ (never a literal).
  , s4Radix        :: Word8   -- ^ palette radix tag.
  , s4DeviceIdHash :: Word32  -- ^ per-install salt, optional via flags.
  , s4BtCompares   :: Word32  -- ^ Compare count of the producing genome.
  } deriving (Eq, Show)

-- | The full payload: header followed by the Int32 LE Q16 coefficients in @flattenHaar@
-- order (1536 bytes for the canonical 384-DOF genome).
data GenomePayload = GenomePayload
  { gpHeader :: S4GNHeader
  , gpCoeffs :: [Int]  -- ^ Int32 Q16 coefficients in @flattenHaar@ order.
  } deriving (Eq, Show)

-- | Total-and-distinct extraction outcomes (@NoBlock@ distinct from @Corrupt@).
data CarrierError = NoBlock | Corrupt | VersionMismatch
  deriving (Eq, Show)

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------

-- | The @[0x21, 0xFF]@ Application-Extension introducer.
appExtIntroducer :: [Word8]
appExtIntroducer = [0x21, 0xFF]

-- | The EXACTLY-11-byte identifier @\"SIXFOUR1\" ++ \"G10\"@ (8-byte app id + 3-byte auth).
blockIdentifier :: [Word8]
blockIdentifier = map (fromIntegral . fromEnum) "SIXFOUR1G10"

-- | The coefficient payload length for the canonical genome: @384 × 4 = 1536@ bytes.
payloadBytes :: Int
payloadBytes = canonicalDof * 4

-- | Total body bytes for the canonical genome: @24 (header) + 1536 (coeffs) + 4 (CRC32)@.
totalBytes :: Int
totalBytes = headerLen + payloadBytes + 4

-- | The number of ≤255-byte data sub-blocks the canonical body splits into: @⌈1564\/255⌉ = 7@.
subBlockCount :: Int
subBlockCount = (totalBytes + 254) `div` 255

-- ---------------------------------------------------------------------------
-- Internal constants (not exported)
-- ---------------------------------------------------------------------------

-- | The header magic @\"S4GN\"@.
magicBytes :: [Word8]
magicBytes = [0x53, 0x34, 0x47, 0x4E]

-- | The fixed header size in bytes.
headerLen :: Int
headerLen = 24

-- | The current schema versions and canonical DOF.
currentMajor, currentMinor, canonicalDof :: Int
currentMajor = 1
currentMinor = 0
canonicalDof = 384

-- ---------------------------------------------------------------------------
-- Little-endian byte helpers
-- ---------------------------------------------------------------------------

-- | Safe byte index (0 past the end), so every reader is total.
ix :: [Word8] -> Int -> Word8
ix bs i = if i >= 0 && i < length bs then bs !! i else 0

u16LE :: Word16 -> [Word8]
u16LE w = [fromIntegral w, fromIntegral (w `shiftR` 8)]

u32LE :: Word32 -> [Word8]
u32LE w = [ fromIntegral (w `shiftR` (8 * i)) | i <- [0 .. 3] ]

-- | A signed Q16 coefficient as 4 little-endian bytes (two's complement, Int32 width).
i32LE :: Int -> [Word8]
i32LE n = u32LE (fromIntegral (fromIntegral n :: Int32))

readU16LE :: [Word8] -> Word16
readU16LE bs = fromIntegral (ix bs 0) .|. (fromIntegral (ix bs 1) `shiftL` 8)

readU32LE :: [Word8] -> Word32
readU32LE bs =
  fromIntegral (ix bs 0)
    .|. (fromIntegral (ix bs 1) `shiftL` 8)
    .|. (fromIntegral (ix bs 2) `shiftL` 16)
    .|. (fromIntegral (ix bs 3) `shiftL` 24)

-- | A signed Q16 coefficient from 4 little-endian bytes (sign-extended via Int32).
readI32LE :: [Word8] -> Int
readI32LE bs = fromIntegral (fromIntegral (readU32LE bs) :: Int32)

chunk4 :: [Word8] -> [[Word8]]
chunk4 [] = []
chunk4 xs = take 4 xs : chunk4 (drop 4 xs)

-- ---------------------------------------------------------------------------
-- CRC32 (ISO-HDLC, polynomial 0xEDB88320) — pure, table-free
-- ---------------------------------------------------------------------------

-- | Standard CRC32 over the body bytes that precede the footer (@header || coeffs@).
crc32 :: [Word8] -> Word32
crc32 = complement . foldl' step 0xFFFFFFFF
  where
    step crc b = foldl' bit (crc `xor` fromIntegral b) [1 .. 8 :: Int]
    bit c _ = if c .&. 1 /= 0 then (c `shiftR` 1) `xor` 0xEDB88320 else c `shiftR` 1

-- ---------------------------------------------------------------------------
-- Header serialization
-- ---------------------------------------------------------------------------

-- | Serialize the header to EXACTLY 'headerLen' (24) bytes: magic, fields, reserved zeros.
encodeHeader :: S4GNHeader -> [Word8]
encodeHeader h =
  magicBytes                       -- 4
    ++ [s4Major h, s4Minor h]      -- 2
    ++ u16LE (s4Flags h)           -- 2
    ++ u16LE (s4Dof h)             -- 2
    ++ [s4Radix h, 0]              -- 2 (radix + reserved)
    ++ u32LE (s4DeviceIdHash h)    -- 4
    ++ u32LE (s4BtCompares h)      -- 4
    ++ [0, 0, 0, 0]                -- 4 reserved

-- | Parse a 24-byte header; 'Nothing' on a short buffer or a wrong magic.
decodeHeader :: [Word8] -> Maybe S4GNHeader
decodeHeader body
  | length body < headerLen        = Nothing
  | take 4 body /= magicBytes      = Nothing
  | otherwise = Just S4GNHeader
      { s4Major        = ix body 4
      , s4Minor        = ix body 5
      , s4Flags        = readU16LE (drop 6 body)
      , s4Dof          = readU16LE (drop 8 body)
      , s4Radix        = ix body 10
      , s4DeviceIdHash = readU32LE (drop 12 body)
      , s4BtCompares   = readU32LE (drop 16 body)
      }

-- ---------------------------------------------------------------------------
-- Sub-block framing
-- ---------------------------------------------------------------------------

-- | Split a body into ≤255-byte GIF data sub-blocks, each prefixed by its length byte.
subBlockify :: [Word8] -> [Word8]
subBlockify [] = []
subBlockify xs = let (h, t) = splitAt 255 xs
                 in (fromIntegral (length h) : h) ++ subBlockify t

-- | Concatenate data sub-blocks until the @0x00@ terminator — the inverse of 'subBlockify'.
gatherSubBlocks :: [Word8] -> [Word8]
gatherSubBlocks []         = []
gatherSubBlocks (0 : _)    = []
gatherSubBlocks (n : rest) = let k = fromIntegral n in take k rest ++ gatherSubBlocks (drop k rest)

-- ---------------------------------------------------------------------------
-- Codec
-- ---------------------------------------------------------------------------

-- | The body @header || coeffs || crc32(header || coeffs)@.
encodeBody :: GenomePayload -> [Word8]
encodeBody (GenomePayload hdr coeffs) =
  let pre = encodeHeader hdr ++ concatMap i32LE coeffs
  in pre ++ u32LE (crc32 pre)

-- | Wrap a body in the GIF89a Application-Extension framing.
wrapBody :: [Word8] -> [Word8]
wrapBody body = appExtIntroducer ++ [0x0B] ++ blockIdentifier ++ subBlockify body ++ [0x00]

-- | Serialize a payload into the full Application-Extension byte stream.
encodeGenomeBlock :: GenomePayload -> [Word8]
encodeGenomeBlock = wrapBody . encodeBody

-- | Probe a GIF byte stream for the S4GN block (never decodes LZW frames). Total: returns
-- 'NoBlock' if the marker is absent, 'Corrupt' on a short body\/bad magic\/CRC mismatch,
-- and 'VersionMismatch' on an incompatible MAJOR (a newer MINOR is tolerated).
extractGenomeBlock :: [Word8] -> Either CarrierError GenomePayload
extractGenomeBlock stream =
  case findMarker stream of
    Nothing   -> Left NoBlock
    Just rest ->
      let body = gatherSubBlocks (drop (length marker) rest)
          n    = length body
      in if n < headerLen + 4
           then Left Corrupt
           else case decodeHeader body of
             Nothing  -> Left Corrupt
             Just hdr ->
               let preLen  = n - 4
                   crcGot  = readU32LE (drop preLen body)
                   crcCalc = crc32 (take preLen body)
                   coeffBs = take (preLen - headerLen) (drop headerLen body)
               in if crcGot /= crcCalc
                    then Left Corrupt
                    else if fromIntegral (s4Major hdr) /= currentMajor
                      then Left VersionMismatch
                      else Right (GenomePayload hdr (map readI32LE (chunk4 coeffBs)))
  where
    marker = appExtIntroducer ++ [0x0B] ++ blockIdentifier

-- | The stream starting at the first occurrence of the 14-byte marker, or 'Nothing'.
findMarker :: [Word8] -> Maybe [Word8]
findMarker stream =
  case filter (marker `isPrefixOf`) (tails stream) of
    (x : _) -> Just x
    []      -> Nothing
  where marker = appExtIntroducer ++ [0x0B] ++ blockIdentifier

-- ---------------------------------------------------------------------------
-- Laws (predicates; to be exercised by Properties.GenomeCarrier)
-- ---------------------------------------------------------------------------

-- | @extract . encode == Right id@ for a current-MAJOR payload — the genome survives the
-- GIF round-trip byte-for-byte.
lawEmbedExtractRoundTrip :: GenomePayload -> Bool
lawEmbedExtractRoundTrip p =
  fromIntegral (s4Major (gpHeader p)) /= currentMajor ||
  extractGenomeBlock (encodeGenomeBlock p) == Right p

-- | The encoded block is a well-formed GIF89a Application-Extension: @0x21 0xFF@ introducer,
-- @0x0B@ size byte, the 11-byte identifier, ≤255-byte data sub-blocks, and a @0x00@
-- terminator.
lawGif89aValidity :: GenomePayload -> Bool
lawGif89aValidity p =
  let blk = encodeGenomeBlock p
  in take 2 blk == appExtIntroducer
     && ix blk 2 == 0x0B
     && take 11 (drop 3 blk) == blockIdentifier
     && (not (null blk) && last blk == 0x00)
     && subBlocksWellFormed (drop 14 blk)
  where
    subBlocksWellFormed (0 : _)    = True
    subBlocksWellFormed (n : rest) = length (take (fromIntegral n) rest) == fromIntegral n
                                       && subBlocksWellFormed (drop (fromIntegral n) rest)
    subBlocksWellFormed []         = False   -- must be terminated by 0x00

-- | The canonical genome fits: @1536@ payload bytes, @1564@ total, @7@ sub-blocks, and the
-- gathered sub-block data of a real canonical block is exactly 'totalBytes' — bounded well
-- under any GIF size budget.
lawCapacityFits :: Bool
lawCapacityFits =
  payloadBytes == canonicalDof * 4
  && totalBytes == headerLen + payloadBytes + 4
  && subBlockCount == 7
  && length (gatherSubBlocks (drop 14 (encodeGenomeBlock canonical))) == totalBytes
  where
    canonical = GenomePayload
      (S4GNHeader (fromIntegral currentMajor) (fromIntegral currentMinor)
                  0 (fromIntegral canonicalDof) 0 0 0)
      (replicate canonicalDof 0)

-- | Int32 Q16 coefficients survive serialization exactly, for any coefficients within the
-- Int32 range — the property int16 would silently break.
lawQ16RoundTripExact :: GenomePayload -> Bool
lawQ16RoundTripExact p =
  let cs = gpCoeffs p
  in not (all inInt32 cs) ||
     map readI32LE (chunk4 (concatMap i32LE cs)) == cs
  where inInt32 n = n >= -2147483648 && n <= 2147483647

-- | The CRC32 catches corruption: flipping ANY body byte makes extraction fail to return the
-- original payload (bad magic, changed coeffs ⇒ CRC mismatch, or a flipped CRC byte).
lawCRCRejectsCorruption :: GenomePayload -> Int -> Bool
lawCRCRejectsCorruption p i =
  fromIntegral (s4Major (gpHeader p)) /= currentMajor ||
  let body = encodeBody p
      j    = i `mod` length body
      blk' = wrapBody (flipByte j body)
  in extractGenomeBlock blk' /= Right p
  where
    flipByte k bs = [ if t == k then b `xor` 0x01 else b | (t, b) <- zip [0 ..] bs ]

-- | Version handling: an exact MAJOR (any MINOR) yields the coefficients; a newer MAJOR is
-- rejected with 'VersionMismatch', never a partial parse. Minor is forward-compatible.
lawVersionTolerance :: GenomePayload -> Bool
lawVersionTolerance p =
  let withVer mj mn = p { gpHeader = (gpHeader p) { s4Major = mj, s4Minor = mn } }
      exact = withVer (fromIntegral currentMajor) (fromIntegral currentMinor)
      newer = withVer (fromIntegral currentMajor) (fromIntegral currentMinor + 1)
      bad   = withVer (fromIntegral currentMajor + 1) (fromIntegral currentMinor)
  in extractGenomeBlock (encodeGenomeBlock exact) == Right exact
     && extractGenomeBlock (encodeGenomeBlock newer) == Right newer
     && extractGenomeBlock (encodeGenomeBlock bad)   == Left VersionMismatch

{- |
Module      : SixFour.Spec.SwapCarrier
Description : The swap-economy gene carrier — a SECOND GIF89a Application-Extension block (S4GX) that lets ONE file be the whole trade artifact: the animation, the gene's lineage tag, and (grant profile only) the working weight bytes. The Trade hybrid model becomes a WIRE fact: a 'Showcase' physically carries no weights and expresses as the deterministic floor; a 'Grant' is mintable only for a creator the ledger has actually granted the gene to ('mintGrant').

"SixFour.Spec.GenomeCarrier" solved genome-in-GIF for the σ-pair look (the @S4GN@
block). This module is its swap-economy sibling: the @S4GX@ block carries ONE
tradeable gene — any registry entry, notably the somatic @theta-up@ every capture
now trains ("SixFour.Spec.DeviceTrainStep") — together with the social metadata the
governance layer folds over ("SixFour.Spec.Lineage" 'GeneTag': creator, parents,
mint epoch). Both blocks may ride in the same GIF ('lawBlocksCoexist'); every GIF
viewer on earth still plays the file, because decoders skip extension blocks by
spec (the app's own Zig parser already does — @kernels.zig s4_gif_decode@).

== The hybrid swap model, enforced at the wire

"SixFour.Spec.Trade" locked the design: /the tiny showcase GIF is public and
abundant, but the working weight blob moves only through a settled trade/. Here
that stops being policy and becomes bytes:

  * 'Showcase' — the public profile. 'encodeSwapBlock' physically serializes ZERO
    weight bytes for it ('lawShowcaseIsInert'), so a showcase received by anyone
    'expressionSource's as 'FloorExact' — viewable, coveted, INERT. This is the
    gene-registry floor claim ("SixFour.Spec.GeneTaxonomy"
    @lawEveryGeneClaimsAFloor@) surfacing at the file level: no gene ⇒ the
    deterministic byte-exact floor, never garbage.
  * 'Grant' — the working file, weights included. 'mintGrant' is the ONLY
    constructor and it consults the ledger: the gene's creator may always mint
    their own; anyone else must appear in "SixFour.Spec.Trade" 'holdings' — i.e.
    a trade must have SETTLED 'lawGrantOnlyFromSettledTrade'. 'mintFor' is the
    total game verb: ask for a file, and the ledger governs which profile you get.

== Carriage is memehood

The registry classes @theta-up@ as 'Somatic' (lives and dies with its capture).
The moment its bytes are minted into a carrier they have crossed the capture
boundary, so the CARRIED class is 'Meme' by definition — 'carriedClass' is
constant and 'lawCarriageIsMemehood' pins it against a real Somatic registry
member. The registry itself is untouched (its class⇒site coherence law still
holds); promotion is a property of carriage, not a registry rewrite. The carried
'GeneTag' has @parents = []@ for a wild capture — a shared somatic gene is an
ORIGIN in the lineage DAG, exactly as "SixFour.Spec.Lineage" defines one.

== Wire shape

@
  0x21 0xFF                  -- Application-Extension introducer
  0x0B                       -- block size = 11
  \"SIXFOUR1\" ++ \"X10\"        -- the EXACTLY-11-byte identifier (X = eXchange)
  \<data sub-blocks\>          -- each: \<len 1..255\> \<len bytes\>
  0x00                       -- block terminator
@

Body = @\"S4GX\" major minor profile nameLen name gene(i32) creator(i32)
minted(i32) parentCount parents(4·k) weightCount(u16) weights(4·m) crc32@.
All multi-byte integers little-endian; ids are the Int stand-ins for content
addresses, wrapped to Int32 ('normalizePayload'). CRC32 is shared with the S4GN
block (imported, one definition). Weight sizes are not free-form:
'grantWeightCountValid' derives the legal count from the gene registry
('lawWireSizesFromRegistry'), so the carrier cannot smuggle a mis-shaped blob.

Honest scope: this is the WIRE + MINT contract. It does not prove a granted
gene expresses well on a foreign capture (that is the V3 expression path,
@OctantCube.expandProposal@ + the Q16 re-entry seam); 'expressionSource' only
pins WHICH substrate runs — floor or learned. Extraction totality mirrors
"SixFour.Spec.GenomeCarrier": 'NoBlock' \/ @Corrupt@ \/ @VersionMismatch@ are
distinct. GHC-boot-only (@containers@). Laws QuickCheck'd in
@Properties.SwapCarrier@.
-}
-- COMPARTMENT: ZIG-FLOOR | tag:DeviceTag
module SixFour.Spec.SwapCarrier
  ( -- * Types
    SwapProfile(..)
  , SwapPayload(..)
  , ExpressionSource(..)
    -- * Constants
  , swapBlockIdentifier
  , swapMajor
  , swapMinor
    -- * Codec
  , encodeSwapBlock
  , encodeSwapBlockVersioned
  , extractSwapBlock
  , normalizePayload
    -- * The governance-swap verbs
  , mayGrant
  , mintGrant
  , mintFor
  , expressionSource
  , carriedClass
  , grantWeightCountValid
    -- * Laws (QuickCheck'd in @Properties.SwapCarrier@)
  , lawEmbedExtractRoundTrip
  , lawGif89aValidity
  , lawShowcaseIsInert
  , lawGrantOnlyFromSettledTrade
  , lawCarriageIsMemehood
  , lawWireSizesFromRegistry
  , lawBlocksCoexist
  , lawCRCRejectsCorruption
  , lawVersionTolerance
  ) where

import           Control.Monad (guard)
import           Data.Bits     (shiftL, shiftR, xor, (.&.), (.|.))
import           Data.Int      (Int32)
import           Data.List     (isPrefixOf, tails)
import           Data.Maybe    (isJust, isNothing)
import qualified Data.Set      as Set
import           Data.Word     (Word8, Word16)

import SixFour.Spec.GenomeCarrier (CarrierError (..), GenomePayload (..),
                                   S4GNHeader (..), crc32, encodeGenomeBlock,
                                   extractGenomeBlock)
import SixFour.Spec.GeneTaxonomy  (GeneClass (..), geneRegistry, gsClass,
                                   gsName, gsParams)
import SixFour.Spec.Lineage       (GeneTag (..))
import SixFour.Spec.Trade         (CreatorId (..), GeneId (..), Ledger,
                                   accept, decline, holdings, propose)

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------

-- | The two file profiles of the locked hybrid swap model: 'Showcase' is the
-- public, abundant, weight-free face; 'Grant' is the working file a settled
-- trade unlocks.
data SwapProfile = Showcase | Grant
  deriving (Eq, Show, Enum, Bounded)

-- | One carried gene: profile, registry name (routing + the size contract),
-- lineage tag (the social metadata governance folds over), and the Q16 weight
-- words — which the codec serializes ONLY for 'Grant'.
data SwapPayload = SwapPayload
  { spProfile  :: SwapProfile  -- ^ 'Showcase' (inert) or 'Grant' (working).
  , spGeneName :: String       -- ^ "SixFour.Spec.GeneTaxonomy" registry key (e.g. @\"theta-up\"@).
  , spTag      :: GeneTag      -- ^ provenance: content-address, creator, parents, mint epoch.
  , spWeights  :: [Int]        -- ^ Int32 Q16 weight words; @[]@ on the wire for 'Showcase'.
  } deriving (Eq, Show)

-- | Which substrate expresses a received file: the deterministic byte-exact
-- floor, or the carried learned weights (which then re-enter the Q16 seam).
data ExpressionSource = FloorExact | Learned [Int]
  deriving (Eq, Show)

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------

-- | The EXACTLY-11-byte Application-Extension identifier @\"SIXFOUR1\" ++ \"X10\"@
-- (8-byte app id + 3-byte auth code; X = eXchange). Distinct from the S4GN
-- look-genome block's @\"SIXFOUR1G10\"@ so the two coexist in one GIF.
swapBlockIdentifier :: [Word8]
swapBlockIdentifier = map (fromIntegral . fromEnum) "SIXFOUR1X10"

-- | Current MAJOR schema version (incompatible layout changes bump it).
swapMajor :: Word8
swapMajor = 1

-- | Current MINOR schema version (forward-compatible additions).
swapMinor :: Word8
swapMinor = 0

-- | The @[0x21, 0xFF]@ introducer (same as every Application-Extension).
appExt :: [Word8]
appExt = [0x21, 0xFF]

-- | The body magic @\"S4GX\"@.
swapMagic :: [Word8]
swapMagic = [0x53, 0x34, 0x47, 0x58]

-- | The 14-byte block marker: introducer + size byte + identifier.
swapMarker :: [Word8]
swapMarker = appExt ++ [0x0B] ++ swapBlockIdentifier

-- ---------------------------------------------------------------------------
-- Little-endian helpers (local twins of the S4GN ones; tiny by design)
-- ---------------------------------------------------------------------------

-- | An Int as 4 little-endian bytes at Int32 width (two's complement).
i32LE :: Int -> [Word8]
i32LE n = [ fromIntegral (w `shiftR` (8 * i)) | i <- [0 .. 3] ]
  where w = fromIntegral (fromIntegral n :: Int32) :: Word

-- | Sign-extending inverse of 'i32LE' (total: missing bytes read as 0).
readI32LE :: [Word8] -> Int
readI32LE bs = fromIntegral (fromIntegral u :: Int32)
  where
    u = byteAt 0 .|. (byteAt 1 `shiftL` 8) .|. (byteAt 2 `shiftL` 16) .|. (byteAt 3 `shiftL` 24)
    byteAt i = if i < length bs then fromIntegral (bs !! i) :: Word else 0

-- | A Word16 as 2 little-endian bytes.
u16LE :: Word16 -> [Word8]
u16LE w = [fromIntegral w, fromIntegral (w `shiftR` 8)]

-- | Inverse of 'u16LE' (total).
readU16LE :: [Word8] -> Word16
readU16LE bs = case bs of
  (a : b : _) -> fromIntegral a .|. (fromIntegral b `shiftL` 8)
  [a]         -> fromIntegral a
  []          -> 0

-- | An Int wrapped to Int32 range — the canonical width of every carried id.
wrap32 :: Int -> Int
wrap32 n = fromIntegral (fromIntegral n :: Int32)

-- | Group into 4-byte words.
chunk4 :: [Word8] -> [[Word8]]
chunk4 [] = []
chunk4 xs = take 4 xs : chunk4 (drop 4 xs)

-- | Exactly-k split, or Nothing — keeps the parser honest about truncation.
takeExact :: Int -> [Word8] -> Maybe ([Word8], [Word8])
takeExact k xs =
  let (h, t) = splitAt k xs
  in if length h == k then Just (h, t) else Nothing

-- ---------------------------------------------------------------------------
-- Normalization
-- ---------------------------------------------------------------------------

-- | The canonical form the wire can represent: name ≤255 latin-1 chars, ids and
-- weights at Int32 width, ≤255 parents, ≤65535 weight words — and, the load-
-- bearing clause, a 'Showcase' has NO weights. @extract . encode ≡ Right .
-- normalizePayload@.
normalizePayload :: SwapPayload -> SwapPayload
normalizePayload p = p
  { spGeneName = take 255 (map (toEnum . (`mod` 256) . fromEnum) (spGeneName p))
  , spTag      = normTag (spTag p)
  , spWeights  = case spProfile p of
      Showcase -> []
      Grant    -> map wrap32 (take 65535 (spWeights p))
  }
  where
    normTag t = t
      { gtGene    = wrapGene (gtGene t)
      , gtCreator = wrapCreator (gtCreator t)
      , gtParents = map wrapGene (take 255 (gtParents t))
      , gtMinted  = wrap32 (gtMinted t)
      }
    wrapGene (GeneId g)       = GeneId (wrap32 g)
    wrapCreator (CreatorId c) = CreatorId (wrap32 c)

-- ---------------------------------------------------------------------------
-- Codec
-- ---------------------------------------------------------------------------

-- | The body (before CRC) at a given version, over an already-normalized payload.
bodyBytes :: Word8 -> Word8 -> SwapPayload -> [Word8]
bodyBytes mj mn p =
  swapMagic
    ++ [mj, mn, profileByte (spProfile p)]
    ++ [fromIntegral (length name)] ++ name
    ++ i32LE gene ++ i32LE creator ++ i32LE (gtMinted tag)
    ++ [fromIntegral (length parents)] ++ concatMap i32LE parents
    ++ u16LE (fromIntegral (length (spWeights p)))
    ++ concatMap i32LE (spWeights p)
  where
    tag                = spTag p
    GeneId gene        = gtGene tag
    CreatorId creator  = gtCreator tag
    parents            = [ g | GeneId g <- gtParents tag ]
    name               = map (fromIntegral . (`mod` 256) . fromEnum) (spGeneName p)
    profileByte Showcase = 0
    profileByte Grant    = 1

-- | Wrap a body (+ its CRC32 footer) in the GIF89a Application-Extension framing.
wrapSwapBody :: [Word8] -> [Word8]
wrapSwapBody body = swapMarker ++ subBlockify (body ++ crcFooter) ++ [0x00]
  where
    crcFooter = [ fromIntegral (crc32 body `shiftR` (8 * i)) .&. 0xFF | i <- [0 .. 3] ]

-- | Split into ≤255-byte length-prefixed GIF data sub-blocks.
subBlockify :: [Word8] -> [Word8]
subBlockify [] = []
subBlockify xs = let (h, t) = splitAt 255 xs
                 in (fromIntegral (length h) : h) ++ subBlockify t

-- | Concatenate data sub-blocks until the @0x00@ terminator.
gatherSubBlocks :: [Word8] -> [Word8]
gatherSubBlocks []         = []
gatherSubBlocks (0 : _)    = []
gatherSubBlocks (n : rest) = let k = fromIntegral n in take k rest ++ gatherSubBlocks (drop k rest)

-- | Serialize at the CURRENT version (normalizes first — the wire is canonical).
encodeSwapBlock :: SwapPayload -> [Word8]
encodeSwapBlock = encodeSwapBlockVersioned swapMajor swapMinor

-- | Serialize at an explicit version — exists so 'lawVersionTolerance' can
-- manufacture a future-MAJOR block; production code uses 'encodeSwapBlock'.
encodeSwapBlockVersioned :: Word8 -> Word8 -> SwapPayload -> [Word8]
encodeSwapBlockVersioned mj mn p = wrapSwapBody (bodyBytes mj mn (normalizePayload p))

-- | Probe a GIF byte stream for the S4GX block (never decodes LZW frames).
-- Total, with the honest three-way outcome: 'NoBlock' (absent — a plain GIF, or
-- a transcode dropped it) \/ 'Corrupt' (bad magic\/CRC\/structure) \/
-- 'VersionMismatch' (a future MAJOR; a newer MINOR is tolerated).
extractSwapBlock :: [Word8] -> Either CarrierError SwapPayload
extractSwapBlock stream =
  case filter (swapMarker `isPrefixOf`) (tails stream) of
    []         -> Left NoBlock
    (found : _) ->
      let whole = gatherSubBlocks (drop (length swapMarker) found)
          n     = length whole
      in if n < 4
           then Left Corrupt
           else
             let body   = take (n - 4) whole
                 crcGot = readI32LE (drop (n - 4) whole)
             in if crcGot /= fromIntegral (fromIntegral (crc32 body) :: Int32)
                  then Left Corrupt
                  else case parseBody body of
                    Nothing        -> Left Corrupt
                    Just (mj, pay) ->
                      if mj /= swapMajor then Left VersionMismatch else Right pay

-- | Parse a CRC-verified body. Requires exact consumption (no trailing bytes),
-- so the wire form stays canonical.
parseBody :: [Word8] -> Maybe (Word8, SwapPayload)
parseBody bs0 = do
  (magic, bs1) <- takeExact 4 bs0
  guard (magic == swapMagic)
  (hdr, bs2) <- takeExact 3 bs1
  let (mj, prByte) = case hdr of
        [a, _, c] -> (a, c)
        _         -> (0, 255)
  prof <- case prByte of
    0 -> Just Showcase
    1 -> Just Grant
    _ -> Nothing
  (nl, bs3)    <- takeExact 1 bs2
  (nameB, bs4) <- takeExact (fromIntegral (head nl)) bs3
  (idsB, bs5)  <- takeExact 12 bs4
  (pc, bs6)    <- takeExact 1 bs5
  (parB, bs7)  <- takeExact (4 * fromIntegral (head pc)) bs6
  (wcB, bs8)   <- takeExact 2 bs7
  (wB, rest)   <- takeExact (4 * fromIntegral (readU16LE wcB)) bs8
  guard (null rest)
  let tag = GeneTag
        { gtGene    = GeneId (readI32LE idsB)
        , gtCreator = CreatorId (readI32LE (drop 4 idsB))
        , gtParents = map (GeneId . readI32LE) (chunk4 parB)
        , gtMinted  = readI32LE (drop 8 idsB)
        }
  pure ( mj
       , SwapPayload prof (map (toEnum . fromIntegral) nameB) tag
                     (map readI32LE (chunk4 wB)) )

-- ---------------------------------------------------------------------------
-- The governance-swap verbs
-- ---------------------------------------------------------------------------

-- | May @who@ hold this gene as a working 'Grant'? Yes iff they minted it
-- (creator sovereignty) or the trade ledger's grant fold says a settled trade
-- gave it to them — "SixFour.Spec.Trade" 'holdings' is the single authority.
mayGrant :: Ledger -> CreatorId -> SwapPayload -> Bool
mayGrant led who p =
  who == gtCreator tag || Set.member (gtGene tag) (holdings led who)
  where tag = spTag p

-- | THE gate: mint the 'Grant' profile, or refuse. This is the only constructor
-- of a working file, so the hybrid model cannot be bypassed in spec-land.
mintGrant :: Ledger -> CreatorId -> SwapPayload -> Maybe SwapPayload
mintGrant led who p
  | mayGrant led who p = Just (normalizePayload p { spProfile = Grant })
  | otherwise          = Nothing

-- | The total game verb: ask for a file and get the profile the ledger governs —
-- the 'Grant' if a trade settled (or it is yours), else the inert 'Showcase'.
mintFor :: Ledger -> CreatorId -> SwapPayload -> SwapPayload
mintFor led who p =
  case mintGrant led who p of
    Just g  -> g
    Nothing -> normalizePayload p { spProfile = Showcase }

-- | Which substrate expresses a received payload: a 'Grant' with weights runs
-- 'Learned' (re-entering the Q16 seam on device); everything else — every
-- 'Showcase', and a weightless grant — is the deterministic 'FloorExact'.
expressionSource :: SwapPayload -> ExpressionSource
expressionSource p =
  case (spProfile p, spWeights p) of
    (Grant, w) | not (null w) -> Learned w
    _                         -> FloorExact

-- | Carriage IS memehood: whatever the registry classes a gene's TYPE (a somatic
-- @theta-up@ lives and dies with its capture), the instance minted into a
-- carrier has crossed the capture boundary and is a 'Meme' by definition.
carriedClass :: SwapPayload -> GeneClass
carriedClass _ = Meme

-- | The size contract: a 'Grant' must carry EXACTLY the registry's parameter
-- count for its named gene (an unregistered name validates nothing); a
-- 'Showcase' is valid iff weight-free. The carrier cannot smuggle a mis-shaped
-- blob past the taxonomy.
grantWeightCountValid :: SwapPayload -> Bool
grantWeightCountValid p =
  case spProfile p of
    Showcase -> null (spWeights p)
    Grant    -> case [ g | g <- geneRegistry, gsName g == spGeneName p ] of
      [g] -> length (spWeights p) == gsParams g
      _   -> False

-- ---------------------------------------------------------------------------
-- Laws (QuickCheck'd in Properties.SwapCarrier)
-- ---------------------------------------------------------------------------

-- | @extract . encode ≡ Right . normalizePayload@ — the gene, its lineage tag,
-- and (grant only) its weights survive the GIF round-trip byte-for-byte.
lawEmbedExtractRoundTrip :: SwapPayload -> Bool
lawEmbedExtractRoundTrip p =
  extractSwapBlock (encodeSwapBlock p) == Right (normalizePayload p)

-- | The encoded block is a well-formed GIF89a Application-Extension: introducer,
-- size byte @0x0B@, the 11-byte identifier, ≤255-byte length-prefixed data
-- sub-blocks, and a @0x00@ terminator — which is WHY any GIF viewer plays the
-- file and any extension-skipping parser (the app's own Zig decoder) walks over it.
lawGif89aValidity :: SwapPayload -> Bool
lawGif89aValidity p =
  let blk = encodeSwapBlock p
  in take 14 blk == swapMarker
     && (not (null blk) && last blk == 0x00)
     && wellFormed (drop 14 blk)
  where
    wellFormed (0 : _)    = True
    wellFormed (n : rest) = length (take (fromIntegral n) rest) == fromIntegral n
                              && wellFormed (drop (fromIntegral n) rest)
    wellFormed []         = False

-- | The hybrid model's public half, as bytes: a 'Showcase' extraction has NO
-- weights and 'expressionSource's as 'FloorExact' — the public file is
-- viewable but inert, whatever weights the in-memory payload held.
lawShowcaseIsInert :: SwapPayload -> Bool
lawShowcaseIsInert p =
  case extractSwapBlock (encodeSwapBlock p { spProfile = Showcase }) of
    Right q -> null (spWeights q) && expressionSource q == FloorExact
    Left _  -> False

-- | The hybrid model's gated half: 'mintGrant' succeeds for the counterparty of
-- an ACCEPTED trade (and, hybrid grant, for the proposer over the counter-gene),
-- refuses on a merely-proposed or declined ledger, always honours the creator,
-- and 'mintFor' degrades the refusal to the inert 'Showcase' — never an error,
-- never a leak.
lawGrantOnlyFromSettledTrade :: Bool
lawGrantOnlyFromSettledTrade =
  let alice   = CreatorId 1
      bob     = CreatorId 2
      gA      = GeneId 100
      gB      = GeneId 200
      pend    = propose alice gA (Just gB) 0
      settled = accept bob (Just gB) pend
      dead    = decline pend
      pa      = SwapPayload Grant "sigma-look" (GeneTag gA alice [] 0) [7]
      pb      = SwapPayload Grant "sigma-look" (GeneTag gB bob [] 0) [9]
  in isJust    (mintGrant [settled] bob pa)          -- bob won alice's gene
     && isJust (mintGrant [settled] alice pb)        -- hybrid: alice gains bob's too
     && isNothing (mintGrant [pend] bob pa)          -- unsettled grants nothing
     && isNothing (mintGrant [dead] bob pa)          -- declined grants nothing
     && isJust (mintGrant [] alice pa)               -- creator sovereignty
     && spProfile (mintFor [pend] bob pa) == Showcase
     && null (spWeights (mintFor [pend] bob pa))     -- the fallback file is inert
     && spProfile (mintFor [settled] bob pa) == Grant

-- | Carriage is memehood, pinned against a REAL somatic registry member: the
-- registry says @theta-up@ is 'Somatic', yet its carried instance is a 'Meme'
-- (and a genuinely-'Meme' @sigma-look@ carries as one too). The registry's own
-- class⇒site law is untouched — promotion happens at the carrier, not in the
-- registry.
lawCarriageIsMemehood :: Bool
lawCarriageIsMemehood =
     classOf "theta-up"   == Just Somatic
  && classOf "sigma-look" == Just Meme
  && carriedClass (pl "theta-up")   == Meme
  && carriedClass (pl "sigma-look") == Meme
  where
    classOf n = case [ g | g <- geneRegistry, gsName g == n ] of
      [g] -> Just (gsClass g)
      _   -> Nothing
    pl n = SwapPayload Grant n (GeneTag (GeneId 1) (CreatorId 1) [] 0) []

-- | Wire sizes are DERIVED from the gene registry, not asserted: a grant of
-- @sigma-look@ must carry exactly its 384 words and @theta-up@ its 21; one word
-- off, or an unregistered name, fails validation.
lawWireSizesFromRegistry :: Bool
lawWireSizesFromRegistry =
     grantWeightCountValid (pl "sigma-look" 384)
  && grantWeightCountValid (pl "theta-up" 21)
  && not (grantWeightCountValid (pl "sigma-look" 383))
  && not (grantWeightCountValid (pl "theta-up" 22))
  && not (grantWeightCountValid (pl "no-such-gene" 21))
  && grantWeightCountValid (SwapPayload Showcase "anything"
                              (GeneTag (GeneId 1) (CreatorId 1) [] 0) [])
  where
    pl n k = SwapPayload Grant n (GeneTag (GeneId 1) (CreatorId 1) [] 0)
                         (replicate k 0)

-- | The two blocks share one GIF: a stream holding the S4GN look-genome block
-- AND the S4GX swap block yields each payload to its own extractor, and neither
-- extractor sees the other's block as its own ('NoBlock', not 'Corrupt').
lawBlocksCoexist :: Bool
lawBlocksCoexist =
  let gn   = GenomePayload (S4GNHeader 1 0 0 384 0 0 0) [7, -7, 65536, 0]
      sw   = SwapPayload Grant "theta-up"
               (GeneTag (GeneId 9) (CreatorId 3) [GeneId 1] 5)
               (replicate 21 1)
      gnB  = encodeGenomeBlock gn
      swB  = encodeSwapBlock sw
      both = gnB ++ swB
  in extractGenomeBlock both == Right gn
     && extractSwapBlock both == Right (normalizePayload sw)
     && extractSwapBlock gnB  == Left NoBlock
     && extractGenomeBlock swB == Left NoBlock

-- | The CRC32 catches STREAM corruption: flipping any body byte in the ENCODED
-- stream — post-signing, without recomputing the footer — makes extraction
-- refuse; it can never return the original payload. (Flip-then-REWRAP would be
-- re-encoding, not corruption: the wire honestly signs whatever body it
-- carries, and a re-signed minor-byte flip decodes to the same payload BY
-- DESIGN — minor is forward-compatible metadata the payload does not record.
-- QuickCheck found exactly that hole in the rewrapping formulation.)
lawCRCRejectsCorruption :: SwapPayload -> Int -> Bool
lawCRCRejectsCorruption p i =
  let q       = normalizePayload p
      blk     = encodeSwapBlock q
      bodyLen = length (bodyBytes swapMajor swapMinor q)
      j       = i `mod` bodyLen
      -- body byte j sits after the 14-byte marker and one length prefix per
      -- 255-byte sub-block chunk
      at      = 14 + 1 + j + (j `div` 255)
      blk'    = [ if t == at then b `xor` 0x01 else b | (t, b) <- zip [0 ..] blk ]
  in extractSwapBlock blk' /= Right q

-- | Version handling: the current MAJOR round-trips at any MINOR (forward-
-- compatible additions), a future MAJOR is refused as 'VersionMismatch' —
-- never a partial parse.
lawVersionTolerance :: SwapPayload -> Bool
lawVersionTolerance p =
  let q = normalizePayload p
  in extractSwapBlock (encodeSwapBlockVersioned swapMajor swapMinor q) == Right q
     && extractSwapBlock (encodeSwapBlockVersioned swapMajor (swapMinor + 1) q) == Right q
     && extractSwapBlock (encodeSwapBlockVersioned (swapMajor + 1) swapMinor q)
          == Left VersionMismatch

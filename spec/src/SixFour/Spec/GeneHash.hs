{- |
Module      : SixFour.Spec.GeneHash
Description : The content-address itself — a gene's 'GeneId' is the hash of a canonical preimage that INCLUDES its parents, so the identity commits to its ancestry. This is what makes "SixFour.Spec.Lineage"'s "acyclic by construction" a THEOREM rather than an assumption: a child hashes over its parents' ids, and a gene can only be minted from parents that already exist, so every parent edge points strictly backward and no gene can be its own ancestor.

Until now 'GeneId' was an @Int@ stand-in for "the hash of the canonical weight bytes"
("SixFour.Spec.Trade"), and "SixFour.Spec.Lineage" carried @gtGene@ and @gtParents@ as
INDEPENDENT fields — nothing forced the address to depend on the parents, so the DAG's
acyclicity was only assumed (the property tests generate acyclic DAGs by construction-order).
This module closes that gap by realising the address:

  * 'GenePreimage' — exactly what gets hashed: the canonical Q16 payload bytes PLUS the ordered
    parent ids (@[]@ = an origin / wild capture). Creator and epoch are provenance METADATA that
    ride in the "SixFour.Spec.Lineage".'GeneTag', NOT in the address — so identical content remixed
    from identical parents dedups to the same 'GeneId' regardless of who minted it (the Merkle-DAG
    dedup property; cf. IPFS CIDs).
  * 'canonicalBytes' \/ 'decodeCanonical' — a length-prefixed little-endian serialisation that
    ROUND-TRIPS ('lawCanonicalRoundTrip'), hence is injective: distinct preimages cannot share bytes,
    so distinct (payload, parents) cannot collide except through the hash itself.
  * 'fnv1a64' \/ 'geneHash' — FNV-1a (64-bit) over the canonical bytes. A small, well-specified,
    byte-exact hash chosen so the Swift\/Zig port reproduces the address bit-for-bit (golden-gate
    style). It is not cryptographic; a crypto hash can be substituted with no change to any law here,
    because every law holds for ANY deterministic hash of an injective encoding. (Tamper-EVIDENCE via
    a creator signature is a separate concern — the sigchain in the genome carrier, not here.)
  * 'mint' — the primitive constructor: hash (payload, parents) into a fresh 'GeneId' and append the
    tag, but ONLY if every parent already exists ('lawMintRequiresParentsPresent'); re-minting
    identical content+parents is an idempotent dedup. 'MintOp' \/ 'buildFrom' fold a whole genealogy
    from nothing, resolving parent references to already-built genes — so a genealogy so built is
    acyclic ('lawBuiltGenealogyAcyclic') and its edges point strictly backward ('lawBuiltEdgesPointBackward').

GHC-boot-only (@base@: @Data.Word@, @Data.Bits@, @Data.List@). Laws QuickCheck'd in
@Properties.GeneHash@. This is the addressing half of the swap economy: the trade LEDGER is
"SixFour.Spec.Trade", the genealogy DAG is "SixFour.Spec.Lineage", and THIS module is the hash that
binds a gene to its parents so the two compose.
-}
-- COMPARTMENT: SWIFT-APP-SOCIAL | tag:DisplaySide
module SixFour.Spec.GeneHash
  ( -- * The hashed preimage
    GenePreimage(..)
    -- * Canonical serialisation (injective ⇒ round-trips)
  , canonicalBytes
  , decodeCanonical
    -- * The hash
  , fnv1a64
  , geneHash
    -- * Construction (the bridge to "SixFour.Spec.Lineage")
  , mint
  , MintOp(..)
  , buildFrom
    -- * Laws (QuickCheck'd in @Properties.GeneHash@)
  , lawCanonicalRoundTrip
  , lawParentsChangeAddress
  , lawPayloadChangesAddress
  , lawMintIdIsContentHash
  , lawMintRequiresParentsPresent
  , lawMintedTagCommitsToParents
  , lawOriginMintSucceeds
  , lawBuiltEdgesPointBackward
  , lawBuiltGenealogyAcyclic
  ) where

import           Data.Bits (shiftL, shiftR, xor, (.|.))
import           Data.List (foldl')
import           Data.Word (Word8, Word64)

import           SixFour.Spec.Lineage
                   ( GeneTag(..), Genealogy, geneIds, isOrigin
                   , lawAcyclicNoSelfAncestor )
import           SixFour.Spec.Trade (CreatorId, Epoch, GeneId(..))

-- ─────────────────────────────────────────────────────────────────────────────
-- The hashed preimage.
-- ─────────────────────────────────────────────────────────────────────────────

-- | Exactly what a gene's content-address hashes over: the canonical Q16 payload (weight bytes) plus
-- the ORDERED parent ids it was remixed from (@[]@ = an origin). Order is significant — a graft of
-- @base@ onto @detail@ is a different gene from the reverse — so parents are kept as supplied, not
-- sorted. Creator\/epoch are NOT here: they are provenance metadata on the tag, so equal content from
-- equal parents dedups to one address.
data GenePreimage = GenePreimage
  { gpPayload :: [Int]      -- ^ the canonical Q16 weight bytes (e.g. the σ-pair coefficients)
  , gpParents :: [GeneId]   -- ^ the genes it derives from, in order (@[]@ = origin)
  } deriving (Eq, Show)

-- ─────────────────────────────────────────────────────────────────────────────
-- Canonical serialisation — length-prefixed LE, so it round-trips (hence injective).
-- ─────────────────────────────────────────────────────────────────────────────

-- | Little-endian 8-byte encoding of a 'Word64' (byte 0 = least significant).
word64le :: Word64 -> [Word8]
word64le w = [ fromIntegral (w `shiftR` (8 * i)) | i <- [0 .. 7] ]

-- | Decode 8 little-endian bytes back to a 'Word64', returning the remaining bytes. 'Nothing' if
-- fewer than 8 bytes remain.
readWord64le :: [Word8] -> Maybe (Word64, [Word8])
readWord64le bs = case splitAt 8 bs of
  (chunk, rest)
    | length chunk == 8 ->
        Just (foldl' (\acc (i, b) -> acc .|. (fromIntegral b `shiftL` (8 * i))) 0 (zip [0 :: Int ..] chunk), rest)
  _ -> Nothing

-- | The canonical byte string a gene is addressed by: @|payload| · payload · |parents| · parents@,
-- every field an 8-byte LE word, lengths prefixed. Length-prefixing is what makes it injective — the
-- payload region and the parent region can never be confused, so no two distinct preimages share
-- bytes ('lawCanonicalRoundTrip').
canonicalBytes :: GenePreimage -> [Word8]
canonicalBytes (GenePreimage payload parents) =
     word64le (fromIntegral (length payload))
  ++ concatMap (word64le . fromIntegral) payload
  ++ word64le (fromIntegral (length parents))
  ++ concatMap (\(GeneId i) -> word64le (fromIntegral i)) parents

-- | Inverse of 'canonicalBytes': parse a preimage back out, requiring the bytes to be consumed
-- exactly. Total; 'Nothing' on any malformed input. (Only ever applied to 'canonicalBytes' output in
-- practice, which always parses — see 'lawCanonicalRoundTrip'.)
decodeCanonical :: [Word8] -> Maybe GenePreimage
decodeCanonical bs0 = do
  (npay, bs1) <- readWord64le bs0
  (payW, bs2) <- readN (fromIntegral npay) bs1
  (npar, bs3) <- readWord64le bs2
  (parW, bs4) <- readN (fromIntegral npar) bs3
  if null bs4
    then Just (GenePreimage (map w64ToInt payW) (map (GeneId . w64ToInt) parW))
    else Nothing
  where
    readN :: Int -> [Word8] -> Maybe ([Word64], [Word8])
    readN k bs
      | k <= 0    = Just ([], bs)
      | otherwise = do
          (w, bs')   <- readWord64le bs
          (ws, bs'') <- readN (k - 1) bs'
          Just (w : ws, bs'')

-- | Reinterpret a 'Word64' as an 'Int' (two's-complement bits). Inverse of @fromIntegral :: Int ->
-- Word64@ on a 64-bit target, so the payload\/parent round-trip is exact.
w64ToInt :: Word64 -> Int
w64ToInt = fromIntegral

-- ─────────────────────────────────────────────────────────────────────────────
-- The hash.
-- ─────────────────────────────────────────────────────────────────────────────

-- | FNV-1a, 64-bit: @h ← offset; for each byte b: h ← (h ⊕ b) · prime@ (modular in 'Word64'). Chosen
-- for being tiny, deterministic and trivially byte-exact to hand-port to Swift\/Zig.
fnv1a64 :: [Word8] -> Word64
fnv1a64 = foldl' step 14695981039346656037
  where step h b = (h `xor` fromIntegral b) * 1099511628211

-- | A gene's content-address: FNV-1a over its 'canonicalBytes'. Because the preimage includes the
-- parents, the address COMMITS TO ANCESTRY — you cannot alter a parent without changing every
-- descendant's id.
geneHash :: GenePreimage -> GeneId
geneHash = GeneId . w64ToInt . fnv1a64 . canonicalBytes

-- ─────────────────────────────────────────────────────────────────────────────
-- Construction — the bridge to "SixFour.Spec.Lineage".
-- ─────────────────────────────────────────────────────────────────────────────

-- | Mint a gene into a genealogy: hash @(payload, parents)@ into a fresh 'GeneId' and append its
-- 'GeneTag'. Fails ('Nothing') if any parent is not already present — a gene can only be remixed from
-- genes that exist (the Merkle-DAG "build from the leaves" rule), which is exactly what forces every
-- parent edge to point backward. Re-minting identical content+parents is an idempotent dedup
-- (returns the existing address, genealogy unchanged).
mint :: Genealogy -> CreatorId -> [Int] -> [GeneId] -> Epoch -> Maybe (GeneId, Genealogy)
mint g creator payload parents epoch
  | not (all (`elem` present) parents) = Nothing
  | gid `elem` present                 = Just (gid, g)
  | otherwise                          = Just (gid, g ++ [GeneTag gid creator parents epoch])
  where
    present = geneIds g
    gid     = geneHash (GenePreimage payload parents)

-- | A single mint instruction for 'buildFrom'. Parents are given as INDICES into the genes built so
-- far (0-based, in build order); out-of-range indices are dropped. This models "you may only remix
-- genes you already hold", so the resolved parents always pre-exist.
data MintOp = MintOp
  { moCreator :: CreatorId  -- ^ who mints
  , moPayload :: [Int]      -- ^ the canonical payload bytes
  , moParents :: [Int]      -- ^ parent references as indices into already-built genes
  , moEpoch   :: Epoch      -- ^ mint epoch
  } deriving (Eq, Show)

-- | Fold a genealogy from nothing by replaying mint instructions, resolving each op's parent indices
-- to the ids of already-built genes. Because parents are always drawn from the existing prefix, the
-- result is acyclic ('lawBuiltGenealogyAcyclic') and every edge points strictly backward
-- ('lawBuiltEdgesPointBackward') — the theorem that content-addressing gives.
buildFrom :: [MintOp] -> Genealogy
buildFrom = foldl' step []
  where
    step g (MintOp cr pay pidx ep) =
      let present = geneIds g
          parents = [ present !! i | i <- pidx, i >= 0, i < length present ]
      in case mint g cr pay parents ep of
           Just (_, g') -> g'
           Nothing      -> g   -- unreachable: parents resolved from `present`, so all pre-exist

-- ─────────────────────────────────────────────────────────────────────────────
-- Laws (QuickCheck'd in @Properties.GeneHash@).
-- ─────────────────────────────────────────────────────────────────────────────

-- | The canonical encoding round-trips: @decodeCanonical (canonicalBytes p) == Just p@. Round-trip
-- ⇒ injective, so no two distinct preimages share bytes — collisions can only come from the hash.
lawCanonicalRoundTrip :: GenePreimage -> Bool
lawCanonicalRoundTrip p = decodeCanonical (canonicalBytes p) == Just p

-- | Changing the parents changes the address bytes: with the payload fixed, distinct parent lists
-- yield distinct 'canonicalBytes' (hence, hash-collisions aside, distinct 'GeneId's). This is the
-- literal statement of "@parents[]@ is in the gene hash".
lawParentsChangeAddress :: [Int] -> [GeneId] -> [GeneId] -> Bool
lawParentsChangeAddress payload ps qs =
  ps == qs
    || canonicalBytes (GenePreimage payload ps) /= canonicalBytes (GenePreimage payload qs)

-- | Changing the payload changes the address bytes too — the id is a true CONTENT address, not just a
-- lineage tag: with parents fixed, distinct payloads yield distinct 'canonicalBytes'.
lawPayloadChangesAddress :: [Int] -> [Int] -> [GeneId] -> Bool
lawPayloadChangesAddress p q parents =
  p == q
    || canonicalBytes (GenePreimage p parents) /= canonicalBytes (GenePreimage q parents)

-- | When 'mint' succeeds, the minted id is exactly @geneHash (GenePreimage payload parents)@ — the
-- construction site cannot produce an address that disagrees with the content+ancestry it claims.
lawMintIdIsContentHash :: Genealogy -> CreatorId -> [Int] -> [GeneId] -> Epoch -> Bool
lawMintIdIsContentHash g cr payload parents ep =
  case mint g cr payload parents ep of
    Just (gid, _) -> gid == geneHash (GenePreimage payload parents)
    Nothing       -> True

-- | 'mint' refuses to reference a parent that does not already exist: if any parent is absent from
-- the genealogy, the mint fails. This is the guard that forces edges to point backward.
lawMintRequiresParentsPresent :: Genealogy -> CreatorId -> [Int] -> [GeneId] -> Epoch -> Bool
lawMintRequiresParentsPresent g cr payload parents ep =
  all (`elem` geneIds g) parents
    || mint g cr payload parents ep == Nothing

-- | After a successful, non-dedup mint the NEW tag's address is the content-hash of the payload and
-- ITS OWN recorded parents: @gtGene t == geneHash (GenePreimage payload (gtParents t))@. This is the
-- bridge that makes "SixFour.Spec.Lineage"'s "a content-addressed child's hash depends on its
-- parents" literally true of the tags in the DAG.
lawMintedTagCommitsToParents :: Genealogy -> CreatorId -> [Int] -> [GeneId] -> Epoch -> Bool
lawMintedTagCommitsToParents g cr payload parents ep =
  case mint g cr payload parents ep of
    Just (gid, g')
      | length g' > length g   -- a genuinely new tag was appended (not a dedup)
      , (t : _) <- [ x | x <- g', gtGene x == gid, x `notElem` g ]
      -> gtGene t == geneHash (GenePreimage payload (gtParents t))
    _ -> True

-- | An origin (no parents) can always be minted — a wild capture needs no pre-existing gene — and the
-- resulting tag is an origin.
lawOriginMintSucceeds :: Genealogy -> CreatorId -> [Int] -> Epoch -> Bool
lawOriginMintSucceeds g cr payload ep =
  case mint g cr payload [] ep of
    Just (gid, g') -> all (\t -> gtGene t /= gid || isOrigin t) g'
    Nothing        -> False

-- | In a genealogy built by 'buildFrom', every gene's parents appear STRICTLY EARLIER than it — the
-- well-foundedness that content-addressed construction guarantees. (Stated as: each tag's parents are
-- all among the ids of the genealogy prefix that precedes it.)
lawBuiltEdgesPointBackward :: [MintOp] -> Bool
lawBuiltEdgesPointBackward ops =
  let g = buildFrom ops
  in and [ all (`elem` map gtGene prefix) (gtParents t)
         | (prefix, t) <- splits g ]
  where
    -- every (strict prefix, element) pair
    splits xs = [ (take i xs, xs !! i) | i <- [0 .. length xs - 1] ]

-- | THE THEOREM: a genealogy built by 'buildFrom' is acyclic — no gene is its own ancestor. This is
-- what "SixFour.Spec.Lineage" previously only ASSUMED (its DAG generator hand-builds acyclic input);
-- here it follows from the construction, because the hash binds a child to parents that already exist.
lawBuiltGenealogyAcyclic :: [MintOp] -> Bool
lawBuiltGenealogyAcyclic = lawAcyclicNoSelfAncestor . buildFrom

{- |
Module      : SixFour.Spec.ProjectionQuery
Description : RAG read-as-projections — a projection-ordering ("SixFour.Spec.ProjectionOrdering") used as a LOSSLESS retrieval QUERY against a stored 'CubeTensor', returning the SAME object viewed differently. The token-keyed lock the 'orderingHash' key has been missing.

The vision: the voxel cube is a RAG (a retrieval store of genes\/atoms) READ AS
PROJECTIONS — JEPA's latent accessed many different ways, each access a Z2-bijective
re-coordinatisation that names the SAME object. The query algebra is already proven;
what was missing is the LOCK on the key. "SixFour.Spec.ProjectionOrdering"
@orderingHash@ is an injective @Word32@ projection-mode token with ZERO call-sites — a
key with no lock; this module is the lock.

A store is one canonical 'CubeTensor' ("SixFour.Spec.CubeTensor"). A query is a
projection-ordering (or its hash). The READ is "SixFour.Spec.SameObjectInvariance"
@encodeUnder@ — distil the channel-split object under the ordering — and the retrieval
GUARANTEE is the keystone @lawReorderingPreservesObject@ re-exported AS read-consistency:

  * 'queryByOrdering' — the projection-keyed read: encode the stored cube under
    an ordering, returning its 'Genome' (the object viewed under that projection).
  * 'queryByHash' — the token-keyed RAG read: resolve a @Word32@ key to the genome of
    the ordering it names ('lawHashKeyResolves' — the token RESOLVES, delegating
    @ProjectionOrdering.lawHashInjective@).
  * 'lawQueryReadConsistency' (THE RAG correctness theorem) — two ordering-keys decode
    to the SAME object (delegates @SameObjectInvariance.lawReorderingPreservesObject@):
    "latent accessed many ways = same object."
  * 'lawCarrierFixedAcrossQueries' — the @L@ carrier sub-genome is IDENTICAL under every
    valid query (L-anchoring as a query-space constraint: a RAG keyed on the carrier
    digest retrieves the same gene regardless of which search projection is read).
  * 'lawQueryVocabularyIsTwo' — the query vocabulary is exactly the two XOR diagonals
    ("SixFour.Spec.ProjectionOrdering" @allOrderings@); a non-vocabulary key resolves to
    'Nothing' ('lawHashKeyRejectsUnknown' — the lock is not vacuous).

This is why a projection-query is a SAFE reinforcement-learning READ: it cannot corrupt
the stored object, only re-coordinate it — the orbit under the @Z2@ IS the gene. The
Swift landing is the un-built @GeneStore.retrieve(key:)@ \/ @nearest(carrierDigest:k:)@
the store's own STATUS comment promises, layered additively over the flat-JSON index.

Additive: reuses "SixFour.Spec.CubeTensor", "SixFour.Spec.ProjectionOrdering",
"SixFour.Spec.SameObjectInvariance", "SixFour.Spec.Dim6". No new substrate, no golden
re-pin. GHC-boot-only (base + Data.Word). Laws are exported predicates, QuickCheck'd in
"Properties.ProjectionQuery".
-}
module SixFour.Spec.ProjectionQuery
  ( -- * The store and its keys
    GeneStoreSpec(..)
  , GeneKey(..)
  , keyOf
    -- * Projection-keyed retrieval (the RAG read)
  , queryByOrdering
  , queryByHash
    -- * The carrier sub-genome (the L-anchored query embedding)
  , carrierBand
    -- * Laws (QuickCheck'd in @Properties.ProjectionQuery@)
  , lawQueryReadConsistency
  , lawHashKeyResolves
  , lawHashKeyRejectsUnknown
  , lawCarrierFixedAcrossQueries
  , lawQueryVocabularyIsTwo
  ) where

import Data.List (find)
import Data.Word (Word32)

import SixFour.Spec.CubeTensor (CubeTensor(..), toChannelSoA, validCubeTensor)
import SixFour.Spec.ProjectionOrdering
  ( Ordering6, orderingHash, allOrderings )
import SixFour.Spec.SameObjectInvariance
  ( Genome(..), Band, encodeUnder, decodeUnder, validCube )

-- | A store backed by ONE canonical 'CubeTensor'. (The runtime store is a catalog of
-- many such cubes; the per-cube read contract is what this module pins, so a store is
-- modelled as a single addressable cube here. The catalog-of-cubes lookup is the same
-- read applied per entry, "SixFour.Spec.CubeTensor"-addressed.)
newtype GeneStoreSpec = GeneStoreSpec
  { storeCube :: CubeTensor  -- ^ the canonical voxel-tensor object this store holds.
  } deriving (Eq, Show)

-- | The composite RAG key: WHICH projection-mode ('orderingHash'), the carrier content
-- digest (the @{L}@ band — search-mutable @a@\/@b@ are deliberately EXCLUDED so an A\/B
-- search never changes which gene is retrieved, only how it is rendered), and which rung
-- ('depth'). 'keyCarrier' is the carrier channel (the byte-digest is the Swift port's
-- concern; here the channel itself models the digest source).
data GeneKey = GeneKey
  { keyOrderingHash :: !Word32   -- ^ the projection-mode token ("SixFour.Spec.ProjectionOrdering" @orderingHash@).
  , keyCarrier      :: ![Int]    -- ^ the @L@ carrier band (the L-anchored, search-stable digest source).
  , keyDepth        :: !Int      -- ^ which rung (octant depth @d@).
  } deriving (Eq, Show)

-- | The key a store yields under a given ordering: the ordering's hash, the store's
-- carrier channel, and its depth. (The carrier is taken straight from the tensor's @L@
-- channel — "SixFour.Spec.CubeTensor" @ctL@ — so the key is L-anchored by construction.)
keyOf :: GeneStoreSpec -> Ordering6 -> GeneKey
keyOf s o = GeneKey (orderingHash o) (ctL (storeCube s)) (ctDepth (storeCube s))

-- | The carrier sub-genome of an encoded object: the @L@ band ("SixFour.Spec.SameObjectInvariance"
-- @gL@), the carrier\/DC lane that is invariant across the projection-choice.
carrierBand :: Genome -> Band
carrierBand = gL

-- | The PROJECTION-KEYED read: encode the stored cube under an ordering, returning the
-- 'Genome' — the SAME object viewed under that projection. (@encodeUnder@ at the store's
-- own depth.) This is the retrieval query: an ordering selects HOW the gene is read.
queryByOrdering :: GeneStoreSpec -> Ordering6 -> Genome
queryByOrdering s o = encodeUnder (ctDepth (storeCube s)) o (toChannelSoA (storeCube s))

-- | The TOKEN-KEYED RAG read: resolve a @Word32@ projection-mode token to the genome of
-- the ordering it names. 'Nothing' if the token is not in the query vocabulary (the lock
-- rejects unknown keys — 'lawHashKeyRejectsUnknown').
queryByHash :: GeneStoreSpec -> Word32 -> Maybe Genome
queryByHash s h = queryByOrdering s <$> find ((== h) . orderingHash) allOrderings

-- | Is the store well-formed at its declared depth (every channel @8^d@ voxels)?
validStore :: GeneStoreSpec -> Bool
validStore s = validCubeTensor (storeCube s)
            && validCube (ctDepth (storeCube s)) (toChannelSoA (storeCube s))

-- ============================================================================
-- Laws (predicates; QuickCheck'd in Properties.ProjectionQuery)
-- ============================================================================

-- | THE RAG CORRECTNESS THEOREM: two ordering-keys against the SAME store decode to the
-- SAME object — "latent accessed many ways = same object." Delegates the keystone
-- "SixFour.Spec.SameObjectInvariance" @lawReorderingPreservesObject@. Teeth: it asserts
-- the DECODED objects are equal, so a query that secretly reordered the cube (lost the
-- swap-undo) would decode to a different object and fail.
lawQueryReadConsistency :: GeneStoreSpec -> Ordering6 -> Ordering6 -> Bool
lawQueryReadConsistency s p p' =
  not (validStore s)
    || decodeUnder p  (queryByOrdering s p)
    == decodeUnder p' (queryByOrdering s p')

-- | The token RESOLVES: a key minted from a vocabulary ordering retrieves exactly the
-- genome that ordering reads — @queryByHash s (orderingHash o) == Just (queryByOrdering s o)@.
-- Delegates "SixFour.Spec.ProjectionOrdering" @lawHashInjective@ (distinct modes ⇒
-- distinct tokens ⇒ the right one resolves).
lawHashKeyResolves :: GeneStoreSpec -> Ordering6 -> Bool
lawHashKeyResolves s o =
  o `elem` allOrderings
    && queryByHash s (orderingHash o) == Just (queryByOrdering s o)

-- | The lock is NOT vacuous: a token that hashes no vocabulary ordering resolves to
-- 'Nothing'. Teeth: an implementation that returned an arbitrary genome for any key
-- (a vacuous "always-hit" store) would fail this.
lawHashKeyRejectsUnknown :: GeneStoreSpec -> Word32 -> Bool
lawHashKeyRejectsUnknown s h =
  if h `elem` map orderingHash allOrderings
    then True
    else queryByHash s h == Nothing

-- | L-ANCHORING as a query-space constraint: the @L@ carrier sub-genome is IDENTICAL
-- under every valid query (the @L@ band never depends on the XOR diagonal — only the
-- two search bands swap). A RAG keyed on the carrier digest therefore retrieves the
-- SAME gene regardless of which search projection is read. Teeth: 'carrierBand' is
-- compared for EQUALITY across the two orderings; a read that folded chroma into the
-- carrier would diverge and fail.
lawCarrierFixedAcrossQueries :: GeneStoreSpec -> Ordering6 -> Ordering6 -> Bool
lawCarrierFixedAcrossQueries s p p' =
  not (validStore s)
    || carrierBand (queryByOrdering s p) == carrierBand (queryByOrdering s p')

-- | The query vocabulary is exactly the two XOR diagonals ("SixFour.Spec.ProjectionOrdering"
-- @allOrderings@), and every minted key carries that store's carrier and depth — the key
-- is well-formed and the vocabulary is closed at two.
lawQueryVocabularyIsTwo :: GeneStoreSpec -> Bool
lawQueryVocabularyIsTwo s =
     length allOrderings == 2
  && all (\o -> let k = keyOf s o
                in keyOrderingHash k == orderingHash o
                   && keyCarrier k == ctL (storeCube s)
                   && keyDepth k == ctDepth (storeCube s))
         allOrderings
  && map orderingHash allOrderings == map (keyOrderingHash . keyOf s) allOrderings

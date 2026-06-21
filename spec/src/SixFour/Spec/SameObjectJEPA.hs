{- |
Module      : SixFour.Spec.SameObjectJEPA
Description : The JEPA objective, pinned — a context and a target are SIBLING projections (different XOR orderings) of ONE 64³ object, and the target is PREDICTABLE from the context. Frontier step 7.

Frontier capstone. "SixFour.Spec.SameObjectInvariance" proved both orderings of a cube
reconstruct the same object; this module turns that into the JEPA training objective:
a 'JepaPair' holds the encodings of ONE cube under a CONTEXT ordering and a TARGET
ordering, and 'predictTarget' recovers the target from the context.

The "same source object" is a STRUCTURAL guarantee, not a runtime check: 'mkJepaPair'
takes a SINGLE 'Cube' plus the two orderings, so the two stored genomes are
necessarily co-projections of one object (a plain pair of genomes could staple two
unrelated objects — this constructor cannot).

  * 'lawJepaPredictsTarget' (a ROUND-TRIP SANITY check — NOT a learning objective; see
    the demotion note below) — @predictTarget@ from the context recovers the ACTUAL
    target genome exactly (delegates "SixFour.Spec.SameObjectInvariance"
    @lawEncodeDecodeRoundTrip@).
  * 'lawJepaSameObject' — context and target decode to the SAME cube (delegates
    @lawReorderingPreservesObject@): they are co-projections, not two objects.
  * 'lawJepaContextIsCube' — the context faithfully encodes the source cube.

== Demotion note: 'lawJepaPredictsTarget' is a SANITY check, not the objective

@predictTarget = encodeUnder pt . decodeUnder pc@ recovers the sibling projection by
FULLY decoding the context to the cube and re-encoding under the target ordering — so
its loss is zero by the Z2 self-inverse round-trip and the predictor @f@ NEVER APPEARS.
It witnesses only that the two co-projections describe ONE object (a permutation
identity), carrying NO genuine prediction difficulty: it is the @lawTailNotAutoregressed@
/ @lawReconstructIsQ16@ vacuity family. It is kept here as a labelled sanity check.

The REAL masked-prediction objective lives in "SixFour.Spec.DetailMaskedPrediction"
(@lawConstantPredictorIncursLoss@): mask a detail band, predict it from the COARSE
context alone, and a CONSTANT (f-free) predictor incurs STRICTLY POSITIVE loss — the
existential failure this round-trip twin lacks. Do NOT cite 'lawJepaPredictsTarget' as
evidence of an information gain or as a training signal.

Additive law module, GHC-boot.
-}
module SixFour.Spec.SameObjectJEPA
  ( JepaPair          -- opaque: build only via 'mkJepaPair'
  , jpDepth
  , jpCtxOrd
  , jpCtx
  , jpTgtOrd
  , jpTgt
  , mkJepaPair
  , predictTarget
    -- * Laws (QuickCheck'd in @Properties.SameObjectJEPA@)
  , lawJepaPredictsTarget
  , lawJepaSameObject
  , lawJepaContextIsCube
  ) where

import SixFour.Spec.ProjectionOrdering   (Ordering6)
import SixFour.Spec.SameObjectInvariance
  ( Cube(..), Genome, encodeUnder, decodeUnder, sameObject )
import SixFour.Spec.OctreeGenome         (octreeLeafCount)

-- | A JEPA context/target pair: the encodings of ONE cube under two orderings, plus
-- the octant depth. The constructor is hidden — build only via 'mkJepaPair', so the
-- two genomes are GUARANTEED co-projections of a single object.
data JepaPair = JepaPair
  { jpDepth  :: Int        -- ^ octant depth of the encodings.
  , jpCtxOrd :: Ordering6  -- ^ the context ordering.
  , jpCtx    :: Genome     -- ^ the context encoding of the shared cube.
  , jpTgtOrd :: Ordering6  -- ^ the target ordering.
  , jpTgt    :: Genome     -- ^ the target encoding of the SAME cube.
  } deriving (Eq, Show)

-- | Build a JEPA pair from a SINGLE cube and two orderings. The single-@Cube@
-- argument is the structural guarantee that context and target are co-projections of
-- one object.
mkJepaPair :: Int -> Ordering6 -> Ordering6 -> Cube -> JepaPair
mkJepaPair d pc pt cube =
  JepaPair d pc (encodeUnder d pc cube) pt (encodeUnder d pt cube)

-- | Predict the target genome from the context: decode the context to recover the
-- object, then re-encode under the target ordering. By same-object invariance this
-- equals the actual target genome ('lawJepaPredictsTarget').
predictTarget :: Int -> Ordering6 -> Genome -> Ordering6 -> Genome
predictTarget d pc gc pt = encodeUnder d pt (decodeUnder pc gc)

-- | A cube is well-formed at depth @d@ if every channel has @8^d@ voxels.
validCube :: Int -> Cube -> Bool
validCube d (Cube cl ca cb) =
  d >= 0 && all (\c -> length c == octreeLeafCount d) [cl, ca, cb]

-- ============================================================================
-- Laws (predicates; QuickCheck'd in Properties.SameObjectJEPA)
-- ============================================================================

-- | ROUND-TRIP SANITY check (NOT the objective — see the module header's demotion
-- note): predicting the target from the context recovers the ACTUAL target genome,
-- loss zero by the Z2 self-inverse round-trip in which the predictor @f@ never appears.
-- The real masked-prediction objective is "SixFour.Spec.DetailMaskedPrediction"
-- @lawConstantPredictorIncursLoss@. Delegates the encode/decode round-trip.
lawJepaPredictsTarget :: Int -> Ordering6 -> Ordering6 -> Cube -> Bool
lawJepaPredictsTarget d pc pt cube =
  not (validCube d cube)
    || let jp = mkJepaPair d pc pt cube
       in predictTarget (jpDepth jp) (jpCtxOrd jp) (jpCtx jp) (jpTgtOrd jp) == jpTgt jp

-- | Context and target are co-projections of the SAME object (delegates
-- @SameObjectInvariance.lawReorderingPreservesObject@ via 'sameObject').
lawJepaSameObject :: Int -> Ordering6 -> Ordering6 -> Cube -> Bool
lawJepaSameObject d pc pt cube =
  not (validCube d cube)
    || let jp = mkJepaPair d pc pt cube
       in sameObject (jpCtxOrd jp) (jpCtx jp) (jpTgtOrd jp) (jpTgt jp)

-- | The context faithfully encodes the source cube (it decodes back to it) — the pair
-- really is built from one real object.
lawJepaContextIsCube :: Int -> Ordering6 -> Ordering6 -> Cube -> Bool
lawJepaContextIsCube d pc pt cube =
  not (validCube d cube)
    || let jp = mkJepaPair d pc pt cube
       in decodeUnder (jpCtxOrd jp) (jpCtx jp) == cube

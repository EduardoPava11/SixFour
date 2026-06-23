{- |
Module      : SixFour.Spec.CubeTensor
Description : The ONE canonical voxel-tensor object — Q16 OKLab over the (x,y,t) lattice, channel-split (L carrier + a,b search), Morton-ordered — and its lossless bridge to the projection/JEPA cube ("SixFour.Spec.SameObjectInvariance" @Cube@).

The vision's "soup where @L,a,b,x,y,t@ all live" needs ONE in-memory home. Today it
is scattered across four incompatible forms (the shipped @Surface.indexCube@ +
@framePixelsQ16@ + palettes; "SixFour.Spec.VoxelReduce" @VoxelCube@;
"SixFour.Spec.SameObjectInvariance" @Cube@; "SixFour.Spec.OctreeCell" @Cube l@), and
nothing converts between them. This module names that missing seam: a single
'CubeTensor' value with a PROVEN bijection to the channel-split 'Cube' the
projection/JEPA/RAG machinery already consumes.

A 'CubeTensor' is purely additive — three flat @[Int]@ channels (the @L@ carrier and
the two search channels @a@,@b@), each @8^d@ Q16 voxels in the octant-Morton order
"SixFour.Spec.OctreeCell" / "SixFour.Spec.SameObjectInvariance" already use. It does
NOT re-point the app's row-major @t·side²+y·side+x@ render cube (that stays a derived
VIEW reached by a lossless permutation; this module never touches
@FrontProjection@/@VoxelFit@). It is the rename that lets "SixFour.Spec.VoxelReduce"
feed "SixFour.Spec.SameObjectJEPA" and lets a projection-ordering become a retrieval
query (see "SixFour.Spec.ProjectionQuery").

  * 'toChannelSoA' \/ 'fromChannelSoA' — the lossless bridge to 'Cube'; it is a
    pure rename (same three @[Int]@ channels, same order), so the round-trips are the
    identity ('lawChannelSoARoundTrip', 'lawChannelSoARoundTripBack').
  * 'lawCarrierChannelIsL' — channel 0 is the "SixFour.Spec.Dim6" @DimL@ carrier
    ('isUniversal'); the search channels are @DimA@\/@DimB@ ('isSearch'). L-anchoring
    is a structural property of the container, not a convention.
  * 'lawCubeTensorVoxelCount' — every channel has exactly @8^d@ voxels (the octant
    lattice "SixFour.Spec.OctreeGenome" @octreeLeafCount@), and 'lawChannelsAligned'
    — the three channels are the SAME length (so a projection can range over all six
    "SixFour.Spec.Dim6" axes of ONE object).
  * 'lawSearchSwapFixesCarrier' — swapping the two search channels (the @Z2@ action
    the XOR ordering applies, "SixFour.Spec.ProjectionOrdering" @applyOp OpSwap@) never
    moves the @L@ carrier (teeth: the carrier is invariant to the projection-choice).

Additive: reuses "SixFour.Spec.SameObjectInvariance" @Cube@, "SixFour.Spec.Dim6",
"SixFour.Spec.OctreeGenome" @octreeLeafCount@. No new substrate, no golden re-pin.
GHC-boot-only (base). Laws are exported predicates, QuickCheck'd in
"Properties.CubeTensor".
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none | STRADDLER
module SixFour.Spec.CubeTensor
  ( -- * The one canonical voxel-tensor object
    CubeTensor(..)
  , channelOf
  , validCubeTensor
    -- * The carrier / search axes of the three channels
  , carrierChannel
  , searchChannels
    -- * Lossless bridge to the projection/JEPA cube
  , toChannelSoA
  , fromChannelSoA
  , swapSearch
    -- * Laws (QuickCheck'd in @Properties.CubeTensor@)
  , lawCubeTensorVoxelCount
  , lawChannelsAligned
  , lawCarrierChannelIsL
  , lawChannelSoARoundTrip
  , lawChannelSoARoundTripBack
  , lawSearchSwapFixesCarrier
  , lawCubeTensorRoundTripsThroughKernel
  , lawCorruptBridgeFailsRoundTrip
  ) where

import SixFour.Spec.Dim6          (Dim6(..), isUniversal, isSearch)
import SixFour.Spec.OctreeCell    (octantDistill, octantSynthesize)
import SixFour.Spec.OctreeGenome  (octreeLeafCount)
import SixFour.Spec.SameObjectInvariance (Cube(..))

-- | The ONE shared object: a Q16 OKLab voxel mass over the @(x,y,t)@ lattice, stored
-- channel-split (SoA) in octant-Morton order. This is simultaneously the JEPA latent,
-- the RAG store, and the data-engine input. @L@ is the carrier (never swapped by a
-- projection); @a@,@b@ are the search channels an ordering re-coordinates.
data CubeTensor = CubeTensor
  { ctDepth :: !Int    -- ^ octant depth @d@: @64³ ⇒ d=6@ (@8^6@ voxels), @16³ ⇒ d=4@.
  , ctL     :: ![Int]  -- ^ CARRIER channel — Q16 OKLab @L@ ("SixFour.Spec.Dim6" @DimL@), Morton @8^d@.
  , ctA     :: ![Int]  -- ^ SEARCH channel — Q16 OKLab @a@ (@DimA@), Morton @8^d@.
  , ctB     :: ![Int]  -- ^ SEARCH channel — Q16 OKLab @b@ (@DimB@), Morton @8^d@.
  } deriving (Eq, Show)

-- | Read one channel by its "SixFour.Spec.Dim6" colour axis (@DimL@\/@DimA@\/@DimB@);
-- a position\/time axis has no stored channel ('Nothing') — only the three colour axes
-- carry voxel mass in this container.
channelOf :: CubeTensor -> Dim6 -> Maybe [Int]
channelOf ct DimL = Just (ctL ct)
channelOf ct DimA = Just (ctA ct)
channelOf ct DimB = Just (ctB ct)
channelOf _  _    = Nothing

-- | The carrier channel of a tensor — always the @L@ channel (the universal\/balance
-- lane "SixFour.Spec.Dim6" @isUniversal@ marks; the DC backbone L-anchoring pins).
carrierChannel :: CubeTensor -> [Int]
carrierChannel = ctL

-- | The two search channels @(a, b)@ — the axes a projection-ordering re-coordinates
-- (and an A\/B search perturbs), never the carrier.
searchChannels :: CubeTensor -> ([Int], [Int])
searchChannels ct = (ctA ct, ctB ct)

-- | Swap the two SEARCH channels (the @Z2@ action on the object — the same swap
-- "SixFour.Spec.ProjectionOrdering" @applyOp OpSwap@ / "SixFour.Spec.SameObjectInvariance"
-- @swapAB@ apply). The carrier is untouched.
swapSearch :: CubeTensor -> CubeTensor
swapSearch (CubeTensor d cl ca cb) = CubeTensor d cl cb ca

-- | A tensor is well-formed at depth @d@: depth non-negative and every channel holds
-- exactly @8^d@ voxels (the octant lattice).
validCubeTensor :: CubeTensor -> Bool
validCubeTensor (CubeTensor d cl ca cb) =
  d >= 0 && all (\c -> length c == octreeLeafCount d) [cl, ca, cb]

-- | Lossless bridge to the projection\/JEPA cube ("SixFour.Spec.SameObjectInvariance"
-- @Cube@): a pure rename of the three channels (same order, same Q16 voxels). This is
-- the seam that lets the data-engine cube feed @encodeUnder@ \/ the JEPA pair.
toChannelSoA :: CubeTensor -> Cube
toChannelSoA (CubeTensor _ cl ca cb) = Cube cl ca cb

-- | The inverse rename: a 'Cube' back into a 'CubeTensor' at a given depth. Total;
-- 'validCubeTensor' holds iff the cube's channels each have @8^d@ voxels.
fromChannelSoA :: Int -> Cube -> CubeTensor
fromChannelSoA d (Cube cl ca cb) = CubeTensor d cl ca cb

-- ============================================================================
-- Laws (predicates; QuickCheck'd in Properties.CubeTensor)
-- ============================================================================

-- | Every channel of a well-formed tensor has exactly @8^d@ voxels (the octant
-- lattice). Teeth: a tensor whose channels are not @8^d@ long is rejected by
-- 'validCubeTensor', so a short\/dropped channel cannot masquerade as a valid object.
lawCubeTensorVoxelCount :: CubeTensor -> Bool
lawCubeTensorVoxelCount ct =
  not (validCubeTensor ct) || all ((== octreeLeafCount (ctDepth ct)) . length)
                                   [ctL ct, ctA ct, ctB ct]

-- | The three channels are aligned — the SAME length — so ONE object's six axes can be
-- ranged over by a single projection. (Independent of 'validCubeTensor': alignment is
-- the weaker shared-shape invariant the round-trip relies on.)
lawChannelsAligned :: CubeTensor -> Bool
lawChannelsAligned ct =
  not (validCubeTensor ct)
    || (length (ctL ct) == length (ctA ct) && length (ctA ct) == length (ctB ct))

-- | The carrier channel is the "SixFour.Spec.Dim6" @DimL@ axis ('isUniversal'), and the
-- two search channels are the @DimA@\/@DimB@ axes ('isSearch'). L-anchoring is a typed
-- property of the container, not a comment: 'channelOf' resolves the carrier to @ctL@
-- and the search axes to @ctA@\/@ctB@, and none of the position\/time axes carry mass.
lawCarrierChannelIsL :: CubeTensor -> Bool
lawCarrierChannelIsL ct =
     isUniversal DimL && channelOf ct DimL == Just (carrierChannel ct)
  && isSearch DimA && channelOf ct DimA == Just (fst (searchChannels ct))
  && isSearch DimB && channelOf ct DimB == Just (snd (searchChannels ct))
  && channelOf ct DimX == Nothing
  && channelOf ct DimY == Nothing
  && channelOf ct DimT == Nothing

-- | 'toChannelSoA' then 'fromChannelSoA' (at the tensor's own depth) is the identity —
-- the bridge to the projection cube loses nothing. Teeth: any reordering or dropped
-- channel in the bridge would change a channel and fail this on a well-formed tensor.
lawChannelSoARoundTrip :: CubeTensor -> Bool
lawChannelSoARoundTrip ct =
  not (validCubeTensor ct)
    || fromChannelSoA (ctDepth ct) (toChannelSoA ct) == ct

-- | The reverse round-trip: 'fromChannelSoA' then 'toChannelSoA' recovers the cube
-- (the rename is a bijection in both directions).
lawChannelSoARoundTripBack :: Int -> Cube -> Bool
lawChannelSoARoundTripBack d cube =
  toChannelSoA (fromChannelSoA d cube) == cube

-- | Swapping the two SEARCH channels (the @Z2@ projection action) NEVER moves the @L@
-- carrier, and is its own inverse. This is L-anchoring as a container invariant — the
-- carrier-digest a RAG keys on (see "SixFour.Spec.ProjectionQuery") is fixed across the
-- projection-choice. Teeth: a 'swapSearch' that touched @ctL@ would fail the first
-- conjunct; a non-involutive swap would fail the second.
lawSearchSwapFixesCarrier :: CubeTensor -> Bool
lawSearchSwapFixesCarrier ct =
     ctL (swapSearch ct) == ctL ct
  && swapSearch (swapSearch ct) == ct
  && toChannelSoA (swapSearch ct)
       == let Cube cl ca cb = toChannelSoA ct in Cube cl cb ca

-- | The tensor round-trips through the ACTUAL reversible kernel, not just the id-rename
-- bridge: bridge to the 'Cube', run EACH channel through the octant kernel
-- (@octantSynthesize . octantDistill d@ — the same bijection 'SixFour.Spec.SuccessiveRefinement'
-- @split@\/@refine@ ride), and bridge back. This is the seam-level reversibility the
-- prose claimed but no law exercised: it puts the @L@\/@a@\/@b@ channels through the kernel
-- the architecture assumes is lossless. Teeth: a lossy kernel, or a bridge that dropped or
-- reordered a channel, changes a channel and fails on any well-formed tensor.
lawCubeTensorRoundTripsThroughKernel :: CubeTensor -> Bool
lawCubeTensorRoundTripsThroughKernel ct =
  not (validCubeTensor ct) ||
    let d             = ctDepth ct
        thru ch       = octantSynthesize (octantDistill d ch)
        Cube cl ca cb = toChannelSoA ct
    in fromChannelSoA d (Cube (thru cl) (thru ca) (thru cb)) == ct

-- | NEGATIVE teeth: a CORRUPTED bridge that swaps the @L@ carrier with a search channel
-- does NOT round-trip — on a tensor whose channels differ, mis-mapping a channel changes
-- the object. This proves 'lawChannelSoARoundTrip' is not vacuously true for ANY bridge (a
-- dropped\/reordered channel is caught), which an id-rename round-trip alone cannot show.
-- (@d = 0@ ⇒ @8^0 = 1@ voxel per channel, three distinct values.)
lawCorruptBridgeFailsRoundTrip :: Bool
lawCorruptBridgeFailsRoundTrip =
  let ct            = CubeTensor 0 [10] [20] [30]   -- 1 voxel/channel, all distinct
      Cube cl ca cb = toChannelSoA ct
      corrupt       = Cube ca cl cb                 -- a WRONG bridge: L and a swapped
  in validCubeTensor ct
     && fromChannelSoA 0 (toChannelSoA ct) == ct    -- the REAL bridge round-trips
     && fromChannelSoA 0 corrupt /= ct              -- the corrupted bridge does NOT

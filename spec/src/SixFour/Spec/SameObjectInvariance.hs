{- |
Module      : SixFour.Spec.SameObjectInvariance
Description : The literal frontier sentence — the SAME 64³ object reconstructs identically under either XOR projection-ordering. Same object, orthogonal projection.

Frontier step 4. "SixFour.Spec.ProjectionOrdering" made the projection-mode a type
(the @Z2@ XOR diagonal). This module states the property that makes it a /projection/
of one object rather than two different objects: __reconstruction is invariant across
the ordering__.

A 'Cube' here is the three chroma-channel fields over the voxel lattice
(@L@ carrier + the two search channels). 'encodeUnder' an ordering distils each
channel, with the XOR diagonal deciding which search channel is stored first;
'decodeUnder' synthesises and UN-swaps by the same bit. Because the XOR swap is its
own inverse ("SixFour.Spec.ProjectionOrdering" @lawXorSelfInverse@) and each channel
round-trips by the octant bijection ("SixFour.Spec.OctreeCell"
@lawOctantLadderBijective@):

  * 'lawEncodeDecodeRoundTrip' — every ordering is an EXACT, reversible
    coordinatisation: @decodeUnder o . encodeUnder o == id@.
  * 'lawReorderingPreservesObject' (the KEYSTONE) — two different orderings of the
    SAME cube reconstruct to the SAME cube: @decodeUnder p . encodeUnder p
    == decodeUnder p' . encodeUnder p'@. The orbit under the XOR group IS the object.
  * 'lawDifferentEncodingsSameObject' — the GENOMES differ (different projection) yet
    'sameObject' holds (same object). This is "same object, orthogonal projection".
  * 'lawEquivariance' — swapping the ordering's XOR equals swapping the input's two
    search channels: @encodeUnder (OpSwap·o) c == encodeUnder o (swapAB c)@.

This is why the projection-choice is a SAFE reinforcement-learning action for the
JEPA: it cannot corrupt the object, only re-coordinate it.

Additive law module: reuses "SixFour.Spec.OctreeCell" + "SixFour.Spec.ProjectionOrdering";
no new substrate, no golden re-pin. GHC-boot.
-}
module SixFour.Spec.SameObjectInvariance
  ( -- * The object and its per-ordering encoding
    Cube(..)
  , Genome(..)
  , swapAB
  , encodeUnder
  , decodeUnder
  , sameObject
    -- * Laws (QuickCheck'd in @Properties.SameObjectInvariance@)
  , lawEncodeDecodeRoundTrip
  , lawReorderingPreservesObject
  , lawDifferentEncodingsSameObject
  , lawEquivariance
  ) where

import SixFour.Spec.OctreeCell        (Detail, octantDistill, octantSynthesize)
import SixFour.Spec.OctreeGenome      (octreeLeafCount)
import SixFour.Spec.ProjectionOrdering
  ( Ordering6, XorBit, xorOf, applyOp, OrderOp(..)
  , canonicalStraight, canonicalCross )

-- | The object: three channel fields (the @L@ carrier and the two search channels
-- @a@,@b@) over the @8^d@ voxel lattice. The XOR ordering only ever relabels the two
-- search channels; @L@ is invariant (the carrier).
data Cube = Cube
  { cubeL :: [Int]   -- ^ the carrier channel (never swapped).
  , cubeA :: [Int]   -- ^ search channel a.
  , cubeB :: [Int]   -- ^ search channel b.
  } deriving (Eq, Show)

-- | A distilled channel: coarse plane + detail bands (the "SixFour.Spec.OctreeCell"
-- octant pyramid output).
type Band = ([Int], [[Detail]])

-- | The encoded cube under an ordering: the carrier band, then the FIRST and SECOND
-- search bands (which physical channel is "first" depends on the XOR diagonal).
data Genome = Genome
  { gL   :: Band
  , gFst :: Band
  , gSnd :: Band
  } deriving (Eq, Show)

-- | Swap the two search channels of a cube (the @Z2@ action on the input).
swapAB :: Cube -> Cube
swapAB (Cube cl ca cb) = Cube cl cb ca

-- | Encode a cube under an ordering at octant depth @d@: distil each channel; the XOR
-- diagonal decides which search channel is stored first ('xorOf' True = cross = swapped).
encodeUnder :: Int -> Ordering6 -> Cube -> Genome
encodeUnder d o (Cube cl ca cb) =
  let (cFst, cSnd) = if xorOf o then (cb, ca) else (ca, cb)
  in Genome (octantDistill d cl) (octantDistill d cFst) (octantDistill d cSnd)

-- | Decode a genome under its ordering: synthesise each channel, then UN-swap the two
-- search channels by the same XOR bit (self-inverse).
decodeUnder :: Ordering6 -> Genome -> Cube
decodeUnder o (Genome bl bf bs) =
  let cl = octantSynthesize bl
      f  = octantSynthesize bf
      s  = octantSynthesize bs
      (ca, cb) = if xorOf o then (s, f) else (f, s)
  in Cube cl ca cb

-- | Two encodings name the SAME object iff they decode (under their own orderings) to
-- the same cube.
sameObject :: Ordering6 -> Genome -> Ordering6 -> Genome -> Bool
sameObject p g q h = decodeUnder p g == decodeUnder q h

-- | A cube is well-formed at depth @d@ if every channel has @8^d@ voxels.
validCube :: Int -> Cube -> Bool
validCube d (Cube cl ca cb) =
  d >= 0 && all (\c -> length c == octreeLeafCount d) [cl, ca, cb]

-- ============================================================================
-- Laws (predicates; QuickCheck'd in Properties.SameObjectInvariance)
-- ============================================================================

-- | Every ordering is an EXACT reversible coordinatisation: decode after encode is the
-- identity (delegates the octant bijection + the @Z2@ self-inverse un-swap).
lawEncodeDecodeRoundTrip :: Int -> Ordering6 -> Cube -> Bool
lawEncodeDecodeRoundTrip d o cube =
  not (validCube d cube) || decodeUnder o (encodeUnder d o cube) == cube

-- | THE KEYSTONE: two different orderings of the SAME cube reconstruct to the SAME
-- cube — reconstruction is INVARIANT across the projection-ordering (the orbit is the
-- object).
lawReorderingPreservesObject :: Int -> Ordering6 -> Ordering6 -> Cube -> Bool
lawReorderingPreservesObject d p p' cube =
  not (validCube d cube)
    || decodeUnder p (encodeUnder d p cube) == decodeUnder p' (encodeUnder d p' cube)

-- | Same object, ORTHOGONAL projection: when the two search channels differ, the two
-- XOR diagonals produce DIFFERENT genomes, yet 'sameObject' holds (both decode to the
-- one cube).
lawDifferentEncodingsSameObject :: Int -> Cube -> Bool
lawDifferentEncodingsSameObject d cube =
  not (validCube d cube && cubeA cube /= cubeB cube)
    || let gS = encodeUnder d canonicalStraight cube
           gC = encodeUnder d canonicalCross    cube
       in gS /= gC                                                   -- different projection
          && sameObject canonicalStraight gS canonicalCross gC      -- same object

-- | EQUIVARIANCE: relabeling the ordering by the XOR swap equals relabeling the input's
-- two search channels — @encodeUnder (OpSwap·o) c == encodeUnder o (swapAB c)@.
lawEquivariance :: Int -> Ordering6 -> Cube -> Bool
lawEquivariance d o cube =
  not (validCube d cube)
    || encodeUnder d (applyOp OpSwap o) cube == encodeUnder d o (swapAB cube)

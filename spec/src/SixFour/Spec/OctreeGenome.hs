{- |
Module      : SixFour.Spec.OctreeGenome
Description : The octant-ladder genome — bijective octree code, law-pinned scale counts, and the zero-genome==floor contract.

The octree-native genome: a cube is encoded by the octant ladder
("SixFour.Spec.OctreeCell" 'octantDistill') into a coarse value + detail bands,
and decoded by 'octantSynthesize'. This module pins the two scale COUNTS that will
later drive the Atlas head dimensions ('octreeNodeCount', 'octreeLeafCount') as
proven FORMULAS — so the numbers exist as laws before any consumer reads them (the
mitigation for the highest-fan-out re-pin) — and makes the @zero-genome == floor@
determinism contract concrete ('lawZeroGenomeIsFloor').

DEFERRED (genuine design decisions, NOT settled here — they parameterise, they do
not block this module): how σ-symmetry (a /colour/ reflection, 128 σ-pairs in the
retired "SixFour.Spec.SigmaPairHead") maps onto octant bands; how the 256-colour
palette relates to octree leaves (256 is not a power of 8); and the genome
CUT-DEPTH (the compression point). Those choose a specific depth/σ-reduction to
feed into the formulas below; the formulas themselves are fixed.

GHC-boot-only. Laws are exported predicates, QuickCheck'd in @Properties.OctreeGenome@.
-}
-- COMPARTMENT: ZIG-FLOOR | tag:DeviceTag
module SixFour.Spec.OctreeGenome
  ( -- * The genome (bijective octant code)
    Genome
  , genomeOf
  , paletteOf
    -- * Scale counts (law-pinned formulas; later driven to a specific depth)
  , octreeLeafCount
  , octreeNodeCount
    -- * The floor (zero-detail) genome
  , zeroGenome
  , isZeroDetail
    -- * Laws (QuickCheck'd in @Properties.OctreeGenome@)
  , lawGenomeRoundTrip
  , lawLeafCount
  , lawNodeCountGeometric
  , lawConstantHasZeroDetail
  , lawZeroGenomeIsFloor
  ) where

import SixFour.Spec.OctreeCell (Detail, octantDistill, octantSynthesize)

-- | A genome is the octant-ladder code: the coarsest value plus the detail bands
-- (finest-first), i.e. the output of 'octantDistill'. Bijective with the cube.
type Genome = ([Int], [[Detail]])

-- | Encode a @8^d@ cube into its genome.
genomeOf :: Int -> [Int] -> Genome
genomeOf = octantDistill

-- | Decode a genome back to the cube / leaf values it reconstructs.
paletteOf :: Genome -> [Int]
paletteOf = octantSynthesize

-- | The number of leaves (voxels) at octree depth @d@: @8^d@.
octreeLeafCount :: Int -> Int
octreeLeafCount d = 8 ^ d

-- | The number of internal octant NODES in a depth-@d@ octree: the geometric sum
-- @8^0 + 8^1 + … + 8^(d-1) = (8^d − 1) / 7@. This is the count the octree Atlas
-- head's slot/vocab dimensions will be derived from.
octreeNodeCount :: Int -> Int
octreeNodeCount d = (8 ^ d - 1) `div` 7

-- | True when every detail band of a genome is zero (the floor genome).
isZeroDetail :: Genome -> Bool
isZeroDetail (_, dets) = all (all (== (0,0,0,0,0,0,0))) dets

-- | The floor genome at depth @d@ with coarse value @c@: zero detail at every
-- scale (built by distilling a constant cube, which has zero detail by construction).
zeroGenome :: Int -> Int -> Genome
zeroGenome d c = octantDistill d (replicate (octreeLeafCount d) c)

-- | The genome round-trips: @paletteOf . genomeOf d ≡ id@ on a @8^d@ cube
-- (re-export of the octant-ladder bijection at the genome layer).
lawGenomeRoundTrip :: Int -> [Int] -> Bool
lawGenomeRoundTrip d xs =
  not (d >= 0 && length xs == octreeLeafCount d)
    || paletteOf (genomeOf d (take (octreeLeafCount d) xs)) == take (octreeLeafCount d) xs

-- | The leaf count is @8^d@.
lawLeafCount :: Int -> Bool
lawLeafCount d = d < 0 || octreeLeafCount d == product (replicate d 8)

-- | The node count is the geometric sum @Σ_{i=0}^{d-1} 8^i@.
lawNodeCountGeometric :: Int -> Bool
lawNodeCountGeometric d = d < 0 || octreeNodeCount d == sum [ 8 ^ i | i <- [0 .. d - 1] ]

-- | Distilling a constant cube yields zero detail at every scale (the balance/DC
-- carries everything; the search/detail is empty).
lawConstantHasZeroDetail :: Int -> Int -> Bool
lawConstantHasZeroDetail d c = d < 0 || isZeroDetail (genomeOf d (replicate (octreeLeafCount d) c))

-- | @zero-genome == floor@: a zero-detail genome reconstructs the constant floor
-- (every leaf = the coarse value). The determinism contract the float residual
-- must short-circuit to — concrete here.
lawZeroGenomeIsFloor :: Int -> Int -> Bool
lawZeroGenomeIsFloor d c = d < 0 || paletteOf (zeroGenome d c) == replicate (octreeLeafCount d) c

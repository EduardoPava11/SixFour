{- |
Module      : SixFour.Spec.ConstructionEncoder
Description : Encoder A — the GIF's "construction instructions" (a colour palette + an index map) as a SEMANTIC EMBEDDING that executes to the voxel cube. The first of the two encoders the dual-encoder H-JEPA proves are one object (the perceptual encoder B is "SixFour.Spec.PerceptualEncoder").

A GIF is described two ways at once. This module names the FIRST: the /construction/
view — a colour 'cPalette' (the table) plus a Morton-order 'cIndex' map (which palette
entry each voxel uses). It is literally "how to build the GIF": @palette[index[v]]@.

This is the Q16 SUBSTRATE twin of the shipped float forms "SixFour.Spec.Palette"
(@Palette k@, OKLab doubles) and "SixFour.Spec.Indices" (@CompleteVoxelVolume@, row-major
@t·side²+y·side+x@). It stays in the integer octant-Morton world so it bridges with NO
float detour to the perceptual cube ("SixFour.Spec.SameObjectInvariance" @Cube@), the
@d6@ metric ("SixFour.Spec.RelationalMemory"), and the reversible lift — exactly the way
"SixFour.Spec.CubeTensor" provides a Morton-order substrate twin without re-pointing the
shipped render cube.

  * 'buildPixels' — EXECUTE the build instructions: look each voxel's palette index up in
    the palette and split the result into the three @Cube@ channels @(L,a,b)@.
  * 'lawConstructionExecutesToPixels' — every built voxel equals its palette lookup (the
    encoder IS the lookup, not a constant collapse).
  * 'lawBuildIsTotalOnValid' — a 'validConstruction' builds exactly @8^d@ voxels per
    channel (the index map is total over the octant lattice).
  * 'lawBuildRespectsIndex' — changing one index entry to point at a differently-coloured
    palette slot changes exactly that voxel (teeth: the index map carries information; the
    encoder is injective in the index, the property the section law in
    "SixFour.Spec.GifDualView" rides).

Additive: reuses "SixFour.Spec.SameObjectInvariance" @Cube@ and
"SixFour.Spec.OctreeGenome" @octreeLeafCount@. No new substrate, no golden re-pin.
GHC-boot-only. Laws QuickCheck'd in "Properties.ConstructionEncoder".
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none
module SixFour.Spec.ConstructionEncoder
  ( -- * Encoder A: the construction view of a GIF
    QColour
  , Construction(..)
  , validConstruction
    -- * Executing the build instructions to pixels
  , buildPixels
  , constructionVoxelCount
    -- * The identity index (the A-form "no index map" core)
  , identityIndex
  , isIdentityIndex
    -- * Laws (QuickCheck'd in @Properties.ConstructionEncoder@)
  , lawConstructionExecutesToPixels
  , lawBuildIsTotalOnValid
  , lawBuildRespectsIndex
  , lawIdentityIndexIsPaletteInOrder
  ) where

import SixFour.Spec.OctreeGenome        (octreeLeafCount)
import SixFour.Spec.SameObjectInvariance (Cube(..))

-- | A Q16 OKLab colour @(L,a,b)@ — one palette entry. The integer twin of a
-- "SixFour.Spec.Palette" @OKLab@ float colour.
type QColour = (Int, Int, Int)

-- | Encoder A: the GIF as /construction instructions/. A colour table 'cPalette' plus a
-- Morton-order 'cIndex' map (one palette index per voxel, over the @8^d@ octant lattice).
-- This is the build recipe: @palette[index[v]]@ reconstructs every voxel.
data Construction = Construction
  { cDepth   :: !Int        -- ^ octant depth @d@ (@8^d@ voxels: @64³ ⇒ d=6@, @16³ ⇒ d=4@).
  , cPalette :: ![QColour]  -- ^ the colour table — the "palette" half of the instructions.
  , cIndex   :: ![Int]      -- ^ the index map — Morton-order palette index per voxel.
  } deriving (Eq, Show)

-- | Number of voxels the index map must cover at this depth (@8^d@).
constructionVoxelCount :: Construction -> Int
constructionVoxelCount = octreeLeafCount . cDepth

-- | A construction is well-formed at depth @d@ when: depth is non-negative, the palette is
-- non-empty, the index map covers exactly the @8^d@ voxel lattice, and every index is a
-- real palette slot @[0, |palette|)@. The smart predicate the build's totality rides on.
validConstruction :: Construction -> Bool
validConstruction c@(Construction d pal idx) =
     d >= 0
  && not (null pal)
  && length idx == constructionVoxelCount c
  && all (\i -> i >= 0 && i < length pal) idx

-- | EXECUTE the build instructions: replace each voxel's palette index by the colour it
-- names, then split the colour stream into the three "SixFour.Spec.SameObjectInvariance"
-- @Cube@ channels @(L,a,b)@. This is the construction encoder's decode — the GIF the
-- palette + index map /build/.
buildPixels :: Construction -> Cube
buildPixels (Construction _ pal idx) =
  let cols = [ pal !! i | i <- idx ]
  in Cube [ l | (l,_,_) <- cols ] [ a | (_,a,_) <- cols ] [ b | (_,_,b) <- cols ]

-- | The IDENTITY index map at depth @d@: @[0, 1, .., 8^d - 1]@. Under this index every
-- voxel @v@ reads palette slot @v@, so the palette laid in canonical (Morton) cell order IS
-- the pixel cube and the index field carries zero information. This is the A-form
-- "16 palettes, no index map" core: when the index is the identity, the palette alone
-- reconstructs the cube ("SixFour.Spec.CoarseIsPalette" @decodeAPalettesOnly@).
identityIndex :: Int -> [Int]
identityIndex d = [0 .. octreeLeafCount d - 1]

-- | Is this construction's index the identity permutation (so its index is droppable)?
isIdentityIndex :: Construction -> Bool
isIdentityIndex c = cIndex c == identityIndex (cDepth c)

-- ============================================================================
-- Laws (predicates; QuickCheck'd in Properties.ConstructionEncoder)
-- ============================================================================

-- | The encoder IS the palette lookup: for every voxel @v@, the built @(L,a,b)@ equals
-- @palette[index[v]]@. Stated against an INDEPENDENT recompute of the lookup so it is not a
-- restatement of 'buildPixels'. Teeth: an encoder that ignored the index (a constant
-- collapse) or read the wrong channel order fails on any construction with two differently
-- coloured slots.
lawConstructionExecutesToPixels :: Construction -> Bool
lawConstructionExecutesToPixels c
  | not (validConstruction c) = True
  | otherwise =
      let Cube ls as bs = buildPixels c
          look i        = cPalette c !! i
      in and [ (ls !! v, as !! v, bs !! v) == look (cIndex c !! v)
             | v <- [0 .. constructionVoxelCount c - 1] ]

-- | A valid construction builds exactly @8^d@ voxels in every channel — the index map is a
-- TOTAL function over the octant lattice (no dropped or short frame can masquerade as a
-- buildable GIF). Teeth: a short index map fails 'validConstruction', so it is excluded at
-- the call site; on a valid one the three channel lengths all equal @octreeLeafCount d@.
lawBuildIsTotalOnValid :: Construction -> Bool
lawBuildIsTotalOnValid c
  | not (validConstruction c) = True
  | otherwise =
      let Cube ls as bs = buildPixels c
          n             = constructionVoxelCount c
      in length ls == n && length as == n && length bs == n

-- | The index map CARRIES information: re-pointing one voxel's index at a differently
-- coloured palette slot changes exactly that voxel's built colour and no other. This is the
-- per-voxel injectivity the section law of "SixFour.Spec.GifDualView" rides — Encoder A is
-- not allowed to be lossy in its own index. Teeth: an encoder that collapsed indices (or
-- built a constant cube) leaves the voxel unchanged and fails. Closed witness so it stays
-- @:: Bool@.
lawBuildRespectsIndex :: Bool
lawBuildRespectsIndex =
  let pal  = [(10,20,30), (40,50,60)]         -- two distinct colours
      base = Construction 0 pal [0]            -- d=0 ⇒ 8^0 = 1 voxel, points at colour 0
      bumped = base { cIndex = [1] }           -- re-point the one voxel at colour 1
      Cube l0 a0 b0 = buildPixels base
      Cube l1 a1 b1 = buildPixels bumped
  in validConstruction base
     && validConstruction bumped
     && (head l0, head a0, head b0) == (10,20,30)
     && (head l1, head a1, head b1) == (40,50,60)   -- the voxel actually moved

-- | THE A-form "no index map" core: when the index is the IDENTITY, @buildPixels@ lays the
-- palette down VERBATIM (slot @v@ at voxel @v@), so the cube's three channels are exactly the
-- palette unzipped. The index field then holds zero information and is droppable: the palette
-- alone, in canonical order, reconstructs the cube. Teeth: a non-identity index would permute
-- the palette and break the verbatim equality, so this is not vacuously true for any index.
-- (The palette is padded\/truncated to exactly @8^d@ entries so the witness is total.)
lawIdentityIndexIsPaletteInOrder :: Int -> [QColour] -> Bool
lawIdentityIndexIsPaletteInOrder d pal0 =
  let n             = octreeLeafCount d
      pal           = take n (cycle (if null pal0 then [(0,0,0)] else pal0))
      c             = Construction d pal (identityIndex d)
      Cube ls as bs = buildPixels c
  in validConstruction c
     && isIdentityIndex c
     && ls == [ l | (l,_,_) <- pal ]
     && as == [ a | (_,a,_) <- pal ]
     && bs == [ b | (_,_,b) <- pal ]

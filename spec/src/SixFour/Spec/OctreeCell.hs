{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE ScopedTypeVariables #-}

{- |
Module      : SixFour.Spec.OctreeCell
Description : The 2×2×2 → 1 octree cell as a fixpoint — proving "1 at the bottom" is a STRUCTURED band, not a scalar.

The octree keystone of the cube ladder. The unit cell is a @2×2×2 → 1@ collapse
(8:1 — a 2×2 voxel face plus the 2×2 behind it in xyz), realised as the least
fixpoint of a cell-functor: @collapse@ is a catamorphism, @lift@ an anamorphism.

The open design question — does the recursion bottom out at a SCALAR leaf, or stay
STRUCTURED? — is settled here as an invariant proof. The octree EDGE is the
existing "SixFour.Spec.RGBTLift" @liftQuad@/@unliftQuad@ S-transform promoted from
the 2×2 face to the 2×2×2 octant (two xy-quad lifts + one integer Haar along z), so
it is an exact integer bijection @V8 Int ≅ OctBand@ = @1 coarse (LLL) + 7 detail@.

== Verdict (forced by the laws, not chosen)

@1@ at the bottom is __NOT a scalar LAB triple__ — the leaf must stay STRUCTURED,
its own @(coarse + 7-detail)@ band, i.e. operadically the same algebra as a node:

  * 'lawOctReversible' — reversibility forces 8 ints ↦ (1 coarse + 7 detail); a
    scalar leaf keeps only the coarse, an @8→1@ projection that destroys 7 dims.
  * 'lawCubeBijective' — @collapse@ then @lift@ is the identity ONLY with a
    structured leaf (the octree mirror of @CubeLadder.lawLadderBijective@).
  * 'lawSelfSimilar' — a leaf is interchangeable with a node of its lifted children
    ("replaceable by its own shape"): only well-typed if the leaf carries a band.
  * 'lawUnitWeightLossless' — PER-SCALE weights are only definable because each
    level owns detail bands; a scalar leaf has nothing to weight per scale.

A scalar leaf is exact only on a per-octant-constant cube
('lawScalarLeafFailsUnlessSmooth'), the measure-zero set of
@CubeLadder.lawSynthBeyondExactOnSmooth@.
-}
module SixFour.Spec.OctreeCell
  ( -- * The cell functor and its fixpoint
    V8(..)
  , OctF(..)
  , Fix(..)
  , Cube
  , cata
  , ana
    -- * The octant edge (2×2×2 ↔ 1 coarse + 7 detail)
  , Scalar
  , OctBand(..)
  , liftOct
  , unliftOct
    -- * Whole-cube collapse / lift (the structured-leaf verdict)
  , StructuredLeaf
  , buildCube
  , flatten
  , collapse
  , liftBack
    -- * Per-scale weights
  , ScaleWeight
  , reweight
    -- * Cube-ladder scales (octree levels)
  , octreeDepth
  , levelsBetween
    -- * Laws (QuickCheck'd in @Properties.OctreeCell@)
  , lawOctReversible
  , lawLadderSelfSimilar
  , lawOctReversible'
  , lawCubeBijective
  , lawSelfSimilar
  , lawUnitWeightLossless
  , scalarCollapseLossy
  , lawScalarLeafFailsUnlessSmooth
  ) where

import SixFour.Spec.RGBTLift (liftQuad, unliftQuad)

-- | Eight children in fixed Morton lane order (the order is load-bearing).
data V8 a = V8 a a a a a a a a deriving (Eq, Show, Functor)

-- | The octree-cell functor: a cell is EITHER a leaf carrying payload @l@, OR a
-- node of eight sub-cells. The leaf payload type @l@ is exactly the open question.
data OctF l a = Leaf l | Node (V8 a) deriving (Eq, Show, Functor)

-- | The least fixed point of a functor — an octree cube is @Fix (OctF l)@.
newtype Fix f = Fix { unFix :: f (Fix f) }

-- | An octree cube with leaf payload @l@.
type Cube l = Fix (OctF l)

-- | Catamorphism (the @collapse@ direction).
cata :: Functor f => (f b -> b) -> Fix f -> b
cata alg = alg . fmap (cata alg) . unFix

-- | Anamorphism (the @lift@ direction).
ana :: Functor f => (b -> f b) -> b -> Fix f
ana coalg = Fix . fmap (ana coalg) . coalg

-- | A scalar octant payload (one OKLab channel value at a voxel).
type Scalar = Int

-- | The lifted cell: ONE coarse sub-band + SEVEN detail sub-bands — the
-- irreducible shape of an octree node's information (the 3-D analogue of
-- "SixFour.Spec.RGBTLift"'s @R + (G,B,T)@).
data OctBand = OctBand
  { ocCoarse :: Int                              -- ^ @LLL@: the DC value that becomes the parent.
  , ocDetail :: (Int,Int,Int,Int,Int,Int,Int)   -- ^ the seven detail sub-bands.
  } deriving (Eq, Show)

-- | @2×2×2 → (coarse, 7 detail)@ — an exact integer bijection, lifting the spec's
-- 2×2 S-transform along the z axis.
liftOct :: V8 Int -> OctBand
liftOct (V8 a b c d e f g h) =
  let (r0,g0,b0,t0) = liftQuad (a,b,c,d)   -- near-z face xy-Haar
      (r1,g1,b1,t1) = liftQuad (e,f,g,h)   -- far-z  face xy-Haar
      (rr, dz)      = sLift r0 r1           -- Haar along z on the two DC faces
  in OctBand rr (g0,b0,t0, g1,b1,t1, dz)

-- | The exact inverse of 'liftOct'.
unliftOct :: OctBand -> V8 Int
unliftOct (OctBand rr (g0,b0,t0, g1,b1,t1, dz)) =
  let (r0, r1)      = sUnlift rr dz
      (a,b,c,d)     = unliftQuad (r0,g0,b0,t0)
      (e,f,g,h)     = unliftQuad (r1,g1,b1,t1)
  in V8 a b c d e f g h

-- | The 1-D reversible S-transform along z (same floor convention as the spec's
-- 2×2 lifting; kept local because it is identical math).
sLift :: Int -> Int -> (Int, Int)
sLift x y = let d = x - y in (y + (d `div` 2), d)

-- | The exact inverse of 'sLift'.
sUnlift :: Int -> Int -> (Int, Int)
sUnlift lo hi = let y = lo - (hi `div` 2) in (y + hi, y)

-- | The STRUCTURED leaf: a fully-collapsed cell still carries the band that
-- reconstructs its eight children. "1 at the bottom" = @(coarse, the shape that made it)@.
type StructuredLeaf = OctBand

-- | A perfectly-balanced cube of given depth from a flat Morton-ordered voxel list.
buildCube :: Int -> [Scalar] -> Cube Scalar
buildCube 0 (v:_) = Fix (Leaf v)
buildCube d xs =
  let n   = 8 ^ d
      blk = n `div` 8
      ch i = buildCube (d-1) (take blk (drop (i*blk) xs))
  in Fix (Node (V8 (ch 0)(ch 1)(ch 2)(ch 3)(ch 4)(ch 5)(ch 6)(ch 7)))

-- | Flatten a scalar cube back to its Morton-ordered voxel list.
flatten :: Cube Scalar -> [Scalar]
flatten = cata alg
  where alg (Leaf v) = [v]
        alg (Node (V8 a b c d e f g h)) = a++b++c++d++e++f++g++h

-- | COLLAPSE: fold a scalar cube to a STRUCTURED cube (leaf type @OctBand@, not
-- @Int@) so no detail is discarded — the move that makes round-trip possible.
collapse :: Cube Scalar -> Cube StructuredLeaf
collapse = cata alg
  where
    alg :: OctF Scalar (Cube StructuredLeaf) -> Cube StructuredLeaf
    alg (Leaf v)  = Fix (Leaf (OctBand v (0,0,0,0,0,0,0)))
    alg (Node ch) = Fix (Node ch)

-- | LIFT back to scalars — the exact inverse fold of 'collapse'.
liftBack :: Cube StructuredLeaf -> Cube Scalar
liftBack = cata alg
  where
    alg :: OctF StructuredLeaf (Cube Scalar) -> Cube Scalar
    alg (Leaf (OctBand v _)) = Fix (Leaf v)
    alg (Node ch)            = Fix (Node ch)

-- | A depth-indexed gain on the detail bands (@1@ = lossless).
type ScaleWeight = Int -> Int

-- | Re-weight the detail bands per scale — a well-typed endomorphism on the
-- structured cube (only definable because the leaf is structured).
reweight :: ScaleWeight -> Cube StructuredLeaf -> Cube StructuredLeaf
reweight w = go 0
  where
    go depth (Fix (Leaf (OctBand c (a,b,d,e,f,g,h)))) =
      let s = w depth
      in Fix (Leaf (OctBand c (a*s,b*s,d*s,e*s,f*s,g*s,h*s)))
    go depth (Fix (Node (V8 c0 c1 c2 c3 c4 c5 c6 c7))) =
      Fix (Node (V8 (go (depth+1) c0)(go (depth+1) c1)(go (depth+1) c2)(go (depth+1) c3)
                    (go (depth+1) c4)(go (depth+1) c5)(go (depth+1) c6)(go (depth+1) c7)))

-- | Reversibility at the edge: the @2×2×2@ octant S-transform is an exact bijection
-- (mirrors @RGBTLift.lawLiftUnliftExact@ lifted to the octree).
lawOctReversible :: V8 Int -> Bool
lawOctReversible v = unliftOct (liftOct v) == v

-- | Reversibility at the edge, the other direction.
lawOctReversible' :: OctBand -> Bool
lawOctReversible' b = liftOct (unliftOct b) == b

-- | Whole-tree bijection: @collapse@ then @lift@ is the identity on the voxel data
-- IFF the leaf is structured (the octree mirror of @CubeLadder.lawLadderBijective@).
lawCubeBijective :: Int -> [Scalar] -> Bool
lawCubeBijective d xs =
  not (d >= 0 && length xs == 8 ^ d)
    || (flatten . liftBack . collapse . buildCube d) xs == take (8 ^ d) xs

-- | Self-similarity / operadic replaceability: a leaf is interchangeable with a
-- node of its lifted children — @Leaf l ~ Node (V8 (Leaf l'))@ at every scale.
lawSelfSimilar :: V8 Int -> Bool
lawSelfSimilar v =
  let band   = liftOct v
      asLeaf = ocCoarse band
      asNode = ocCoarse (liftOct (unliftOct band))
  in asLeaf == asNode && unliftOct band == v

-- | Per-scale weights are expressible AND unit weight is lossless (scale weights
-- are only definable because the leaf is structured).
lawUnitWeightLossless :: Int -> [Scalar] -> Bool
lawUnitWeightLossless d xs =
  not (d >= 0 && length xs == 8 ^ d)
    || (flatten . liftBack . reweight (const 1) . collapse . buildCube d) xs
         == take (8 ^ d) xs

-- | The COUNTER-functor: a scalar leaf keeps only the coarse band — an @8→1@
-- projection that is NOT invertible.
scalarCollapseLossy :: V8 Int -> Int
scalarCollapseLossy = ocCoarse . liftOct

-- | A scalar leaf is exact ONLY on a per-octant-constant cube (measure-zero) —
-- exactly @CubeLadder.lawSynthBeyondExactOnSmooth@; off it, the DC alone cannot invert.
lawScalarLeafFailsUnlessSmooth :: Int -> Bool
lawScalarLeafFailsUnlessSmooth v =
  let constOct = V8 v v v v v v v v
  in scalarCollapseLossy constOct == v

-- | Octree depth of a linear dimension that is a power of two: the number of
-- @2×2×2@ levels down to a single voxel, @log2 dim@ (e.g. @octreeDepth 256 = 8@).
octreeDepth :: Int -> Int
octreeDepth = go 0
  where go n d = if d <= 1 then n else go (n + 1) (d `div` 2)

-- | The number of octree (@2×2×2@) levels between two rung linear dimensions
-- @hi ≥ lo@ (powers of two): @log2 hi − log2 lo@. Each level is a ×2 linear
-- (×8 volume) step, so a ×4-linear cube-ladder rung is exactly 2 octree levels.
levelsBetween :: Int -> Int -> Int
levelsBetween hi lo = octreeDepth hi - octreeDepth lo

-- | Cube-ladder self-similarity: equal linear ratios ⇒ equal octree distance, so
-- @16³ : 64³ :: 64³ : 256³@ holds because @levelsBetween 64 16 == levelsBetween 256 64@
-- (each is 2 levels). This is WHY one octant operator covers every rung.
lawLadderSelfSimilar :: Bool
lawLadderSelfSimilar = levelsBetween 64 16 == levelsBetween 256 64

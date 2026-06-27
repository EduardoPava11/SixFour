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
-- COMPARTMENT: ZIG-FLOOR | tag:DeviceTag
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
    -- * The octant ladder (a real Haar pyramid built on 'liftOct')
  , Detail
  , detailBand
  , detailToList
  , octantDistill
  , octantSynthesize
    -- * Laws (QuickCheck'd in @Properties.OctreeCell@)
  , lawOctReversible
  , lawLadderSelfSimilar
  , lawOctReversible'
  , lawCubeBijective
  , lawSelfSimilar
  , lawUnitWeightLossless
  , scalarCollapseLossy
  , lawScalarLeafFailsUnlessSmooth
  , lawOctantLadderBijective
  , lawDetailBandSelectsSlot
    -- * The build→flatten pair, NAMED a hylomorphism (re-uses "SixFour.Spec.Recursion")
  , buildCoalg
  , lawOctantBuildFlattenIsHylo
  ) where

import SixFour.Spec.RGBTLift (liftQuad, unliftQuad)
-- The fixpoint vocabulary now lives in ONE place ("SixFour.Spec.Recursion") instead of being
-- re-declared here; re-exported below so existing importers of @OctreeCell (Fix, cata, ana)@ are
-- unaffected. @hylo@ names the build→flatten pair ('lawOctantBuildFlattenIsHylo').
import SixFour.Spec.Recursion (Fix(..), cata, ana, hylo)

-- | Eight children in fixed Morton lane order (the order is load-bearing).
data V8 a = V8 a a a a a a a a deriving (Eq, Show, Functor)

-- | The octree-cell functor: a cell is EITHER a leaf carrying payload @l@, OR a
-- node of eight sub-cells. The leaf payload type @l@ is exactly the open question.
data OctF l a = Leaf l | Node (V8 a) deriving (Eq, Show, Functor)

-- | An octree cube with leaf payload @l@ — the least fixed point @Fix (OctF l)@. 'Fix', 'cata'
-- (collapse), and 'ana' (lift) are imported from "SixFour.Spec.Recursion" and re-exported.
type Cube l = Fix (OctF l)

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

-- | 'buildCube' expressed as an F-coalgebra over the seed @(depth, voxels)@, so @ana buildCoalg@
-- reproduces 'buildCube'. This is what lets the existing build→flatten pair be NAMED a hylomorphism
-- ('lawOctantBuildFlattenIsHylo') using the shared "SixFour.Spec.Recursion" combinators, rather than
-- the recursion living implicitly inside 'buildCube'.
buildCoalg :: (Int, [Scalar]) -> OctF Scalar (Int, [Scalar])
buildCoalg (0, xs) = Leaf (case xs of (v : _) -> v; [] -> 0)
buildCoalg (d, xs) =
  let blk  = (8 ^ d) `div` 8
      ch i = (d - 1, take blk (drop (i * blk) xs))
  in Node (V8 (ch 0) (ch 1) (ch 2) (ch 3) (ch 4) (ch 5) (ch 6) (ch 7))

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

-- | The seven detail sub-bands of an octant (same shape as 'OctBand''s detail).
type Detail = (Int,Int,Int,Int,Int,Int,Int)

-- | The seven detail sub-bands as a list in canonical (positional) order — THE one place the
-- band ordering is defined.
detailToList :: Detail -> [Int]
detailToList (b0, b1, b2, b3, b4, b5, b6) = [b0, b1, b2, b3, b4, b5, b6]

-- | The @i@-th detail sub-band (positional, @0..6@; out-of-range yields 0). THE canonical band
-- selector, living in the home of 'Detail': the JEPA target ("SixFour.Spec.MaskedBandPrediction"
-- @bandAt@), the held label ("SixFour.Spec.JepaData" @detailAt@) and the per-band entropy
-- ("SixFour.Spec.DetailEntropy" @detailColumn@) ALL read a band through this — so "they read the
-- same band" is structural, not three parallel destructures that happen to agree.
detailBand :: Detail -> Int -> Int
detailBand d i = if i >= 0 && i < 7 then detailToList d !! i else 0

-- | Group a list into consecutive 8-tuples (one per octant, Morton order).
chunk8 :: [a] -> [[a]]
chunk8 [] = []
chunk8 xs = take 8 xs : chunk8 (drop 8 xs)

-- | Pack the first eight elements into a 'V8' (total; pads with 0 if short, which
-- never happens for a well-formed @8^d@ cube).
toV8 :: [Int] -> V8 Int
toV8 (a:b:c:d:e:f:g:h:_) = V8 a b c d e f g h
toV8 _                   = V8 0 0 0 0 0 0 0 0

-- | Flatten a 'V8' to its eight elements in Morton order.
unV8 :: V8 a -> [a]
unV8 (V8 a b c d e f g h) = [a,b,c,d,e,f,g,h]

-- | One octant ladder level: @8^k@ Morton voxels ↦ @8^(k-1)@ coarse values + the
-- per-octant detail bands. This is where the pyramid DELEGATES to 'liftOct'.
octantStep :: [Int] -> ([Int], [Detail])
octantStep xs = unzip [ (ocCoarse b, ocDetail b) | oct <- chunk8 xs, let b = liftOct (toV8 oct) ]

-- | Descend the octant ladder @d@ levels: a @8^d@ cube ↦ the single coarsest value
-- plus the detail bands finest-first. The real 3-D Haar pyramid (cf. the 2-D
-- "SixFour.Spec.CubeLadder"), built entirely on the reversible 'liftOct' edge.
octantDistill :: Int -> [Int] -> ([Int], [[Detail]])
octantDistill 0 xs = (xs, [])
octantDistill d xs =
  let (coarse, det) = octantStep xs
      (c', dets)    = octantDistill (d - 1) coarse
  in (c', det : dets)

-- | Exact inverse of 'octantDistill': replay the detail bands (coarsest-first) to
-- rebuild the @8^d@ cube via 'unliftOct'.
octantSynthesize :: ([Int], [[Detail]]) -> [Int]
octantSynthesize (coarse, [])         = coarse
octantSynthesize (coarse, det : dets) =
  let inner = octantSynthesize (coarse, dets)
  in concatMap unV8 (zipWith (\co de -> unliftOct (OctBand co de)) inner det)

-- | The octant ladder loses nothing: @octantSynthesize . octantDistill d ≡ id@ on
-- a @8^d@ cube — the 3-D mirror of @CubeLadder.lawLadderBijective@, delegating to
-- the 'liftOct' edge at every level.
lawOctantLadderBijective :: Int -> [Int] -> Bool
lawOctantLadderBijective d xs =
  not (d >= 0 && length xs == 8 ^ d)
    || octantSynthesize (octantDistill d (take (8 ^ d) xs)) == take (8 ^ d) xs

-- | 'detailToList' is the canonical positional order and 'detailBand' indexes it (out-of-range
-- yields 0) — the shared primitive the three band-readers route through. Teeth: a permuted order
-- or an off-by-one selector fails.
lawDetailBandSelectsSlot :: Detail -> Int -> Bool
lawDetailBandSelectsSlot d@(b0, b1, b2, b3, b4, b5, b6) i =
  let j = ((i `mod` 7) + 7) `mod` 7
  in detailToList d == [b0, b1, b2, b3, b4, b5, b6]
     && detailBand d j == [b0, b1, b2, b3, b4, b5, b6] !! j
     && detailBand d 7 == 0 && detailBand d (-1) == 0

-- | The build→flatten pair IS a hylomorphism over the octree functor: building a cube from a flat
-- voxel list ('buildCube' = @ana 'buildCoalg'@) then flattening it ('flatten' = @cata flattenAlg@)
-- equals the fused 'SixFour.Spec.Recursion.hylo' in one pass — and both equal the identity on the
-- @8^d@ voxels. This NAMES the existing pair with the shared combinators; it is NOT a reversibility
-- claim (that is 'lawOctantLadderBijective', which goes through the averaging 'liftOct' edge — a
-- DIFFERENT, byte-exact fact). Teeth: a @buildCoalg@ with a permuted child order, or a @flattenAlg@
-- that reordered the eight sub-lists, breaks the identity.
lawOctantBuildFlattenIsHylo :: Int -> [Scalar] -> Bool
lawOctantBuildFlattenIsHylo d xs =
  not (d >= 0 && d <= 5 && length xs == 8 ^ d)
    || (h == flatten (buildCube d ys) && h == ys)
  where
    ys = take (8 ^ d) xs
    h  = hylo flattenAlg buildCoalg (d, ys)
    flattenAlg :: OctF Scalar [Scalar] -> [Scalar]
    flattenAlg (Leaf v)                            = [v]
    flattenAlg (Node (V8 c0 c1 c2 c3 c4 c5 c6 c7)) = c0++c1++c2++c3++c4++c5++c6++c7

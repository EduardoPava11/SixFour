{- |
Module      : SixFour.Spec.SplitTree
Description : The median-cut spatial partition of the palette — the renderer's navigable structure.

The Review-screen LAB color-volume renders the 256 per-frame palette entries as a
navigable hierarchy. The structure is a **median-cut split tree**: recursively split
the set of OKLab points along its widest axis at the median, until each leaf holds one
colour. Since @256 = 2⁸@ the canonical tree is a *perfect binary tree of depth 8*, and
every leaf carries a unique 8-bit prefix address (the "drill-in" path).

The three on-screen structures the user picked from — @16²@, @4⁴@, @2⁸@ — are NOT three
trees. They are three **views** of the one binary tree, obtained by collapsing @k@ binary
levels into one @2^k@-ary level:

  * @b = 2@  → collapse 1 level  → binary tree, depth 8   (median-cut, one axis per level)
  * @b = 4@  → collapse 2 levels → quadtree,    depth 4   (two axes per level)
  * @b = 16@ → collapse 4 levels → flat,        depth 2   (a 16-wide arrangement)

with @bᵈ = 256@ for all three. Octree (@b = 8@) is excluded *by arithmetic*: @3 ∤ 8@, so
no integer depth gives @8ᵈ = 256@ — the same gap that forbids a 3-D cube of 256 and forces
the app's "Octree" quantizer to prune/merge. This is pinned as 'lawBranchingArithmetic'.

This module is distinct from "SixFour.Spec.PairTree": that is the NN's σ-balanced **Haar
pairing pyramid** (mirror pairs @parent ± δ@, 768 DOF); this is the renderer's **spatial
median-cut partition** (where each colour sits in OKLab space + how you navigate to it).

Contract-first: every function is a total reference implementation (no stubs). The Swift
port (@SixFour/Palette/SplitTree.swift@) is verified bit-for-bit against this; determinism
under the pinned @(axisCoord, paletteIndex)@ tie-break is what makes that parity exact.
-}
module SixFour.Spec.SplitTree
  ( -- * Geometry primitives
    SplitAxis(..)
  , IndexedColor(..)
  , OKLabBox(..)
  , axisCoord
  , boundingBox
  , widestAxis
    -- * The canonical binary median-cut tree
  , SplitTree(..)
  , buildSplitTree
  , treeDepth
  , leaves
  , leafIndices
    -- * Split planes (for the renderer's translucent slabs)
  , SplitPlane(..)
  , splitPlanes
  , numPlanes
    -- * Prefix addressing (the drill-in gesture)
  , leafPaths
  , subtreeAt
    -- * Branching views (16² / 4⁴ / 2⁸ as level-collapses)
  , Branching(..)
  , branchFactor
  , branchDepth
  , collapseK
  , NaryTree(..)
  , descendantsAt
  , collapseLevels
  , viewBranching
  , naryLeaves
  , naryChildCounts
    -- * SixFour's pinned shape (256 = 2⁸ leaves)
  , paletteDepth
  , numLeaves
    -- * Laws (predicates; QuickCheck'd in Properties.SplitTree)
  , lawLeafCountIsInput
  , lawPartition
  , lawDeterministicUnderPermutation
  , lawChildBoxesNested
  , lawPlaneCount
  , lawAddressRoundTrip
  , lawAddressesDistinct
  , lawCollapsePreservesLeaves
  , lawViewChildCount
  , lawBranchingArithmetic
  , lawCollapseDepthInvariant
  ) where

import Data.List (sortBy, foldl')
import Data.Ord  (comparing)

import SixFour.Spec.Color (OKLab(..))
import SixFour.Spec.Shape (kVal)

-- | The three OKLab axes, in 'SIMD3' lane order (matches the Swift @SplitAxis@).
data SplitAxis = AxisL | AxisA | AxisB
  deriving (Eq, Show, Enum, Bounded)

-- | A palette colour with its original slot index pinned. The index is the position
-- in @perFrameCells[frame]@ / @palettesForDisplay[frame]@ on the Swift side, and it is
-- the tie-break key that makes 'buildSplitTree' deterministic regardless of input order.
data IndexedColor = IndexedColor
  { icIndex :: Int
  , icColor :: OKLab
  } deriving (Eq, Show)

-- | An axis-aligned bounding box in OKLab.
data OKLabBox = OKLabBox { boxLo :: OKLab, boxHi :: OKLab }
  deriving (Eq, Show)

-- | Coordinate of a colour along one axis.
axisCoord :: SplitAxis -> OKLab -> Double
axisCoord AxisL (OKLab l _ _) = l
axisCoord AxisA (OKLab _ a _) = a
axisCoord AxisB (OKLab _ _ b) = b

-- | Tight bounding box of a non-empty point set. (Empty → degenerate box at origin.)
boundingBox :: [OKLab] -> OKLabBox
boundingBox [] = OKLabBox (OKLab 0 0 0) (OKLab 0 0 0)
boundingBox (p0 : ps) = OKLabBox (OKLab lLo aLo bLo) (OKLab lHi aHi bHi)
  where
    OKLab l0 a0 b0 = p0
    (lLo, lHi, aLo, aHi, bLo, bHi) =
      foldl' acc (l0, l0, a0, a0, b0, b0) ps
    acc (!lmn, !lmx, !amn, !amx, !bmn, !bmx) (OKLab l a b) =
      (min lmn l, max lmx l, min amn a, max amx a, min bmn b, max bmx b)

-- | The axis along which the box is widest. Ties resolve @L > a > b@ (a total, stable
-- rule — part of the determinism contract).
widestAxis :: OKLabBox -> SplitAxis
widestAxis (OKLabBox (OKLab lLo aLo bLo) (OKLab lHi aHi bHi))
  | extL >= extA && extL >= extB = AxisL
  | extA >= extB                 = AxisA
  | otherwise                    = AxisB
  where
    extL = lHi - lLo
    extA = aHi - aLo
    extB = bHi - bLo

-- | The canonical binary median-cut tree. A 'Branch' records the axis it split on, the
-- separating plane position, and its two children (@lo@ = below the plane, @hi@ = above).
data SplitTree
  = Leaf IndexedColor
  | Branch SplitAxis Double SplitTree SplitTree
  deriving (Eq, Show)

-- | Median-cut: pick the widest axis, sort by @(coord, index)@ (the pinned total order),
-- split into equal halves at the median, recurse. For @2^d@ points this is a perfect
-- binary tree of depth @d@. The @(coord, index)@ key makes the result a deterministic
-- function of the /set/ of points, independent of input order ('lawDeterministicUnderPermutation').
buildSplitTree :: [IndexedColor] -> SplitTree
buildSplitTree ics = case ics of
  []   -> Leaf (IndexedColor 0 (OKLab 0 0 0))   -- unreachable for non-empty input
  [ic] -> Leaf ic
  _    ->
    let ax     = widestAxis (boundingBox (map icColor ics))
        sorted = sortBy (comparing (\ic -> (axisCoord ax (icColor ic), icIndex ic))) ics
        n      = length ics
        (lo, hi) = splitAt (n `div` 2) sorted
        pos    = 0.5 * ( axisCoord ax (icColor (last lo))
                       + axisCoord ax (icColor (head hi)) )
    in Branch ax pos (buildSplitTree lo) (buildSplitTree hi)

-- | Depth of the tree (a single leaf has depth 0).
treeDepth :: SplitTree -> Int
treeDepth (Leaf _)         = 0
treeDepth (Branch _ _ l r) = 1 + max (treeDepth l) (treeDepth r)

-- | Leaves in canonical in-order (@lo@ before @hi@) — the SoA storage order the renderer
-- uploads.
leaves :: SplitTree -> [IndexedColor]
leaves (Leaf ic)         = [ic]
leaves (Branch _ _ l r)  = leaves l ++ leaves r

-- | Original slot indices of the leaves, in canonical order.
leafIndices :: SplitTree -> [Int]
leafIndices = map icIndex . leaves

-- | A separating plane: which axis, where, and at what binary level (root = 0).
data SplitPlane = SplitPlane
  { planeAxis  :: SplitAxis
  , planePos   :: Double
  , planeLevel :: Int
  } deriving (Eq, Show)

-- | All internal split planes, top-down. A perfect depth-@d@ tree has @2^d − 1@ planes.
splitPlanes :: SplitTree -> [SplitPlane]
splitPlanes = go 0
  where
    go _   (Leaf _)            = []
    go lvl (Branch ax pos l r) = SplitPlane ax pos lvl : go (lvl + 1) l ++ go (lvl + 1) r

-- | Number of internal planes.
numPlanes :: SplitTree -> Int
numPlanes = length . splitPlanes

-- | Each leaf paired with its prefix address (@0@ = lo, @1@ = hi), in canonical order.
-- The address is the drill-in path; its length equals the leaf's depth.
leafPaths :: SplitTree -> [([Int], IndexedColor)]
leafPaths = go []
  where
    go p (Leaf ic)        = [(reverse p, ic)]
    go p (Branch _ _ l r) = go (0 : p) l ++ go (1 : p) r

-- | Follow a prefix address to a subtree. @Nothing@ if the path runs past a leaf or uses
-- a digit outside @{0,1}@.
subtreeAt :: [Int] -> SplitTree -> Maybe SplitTree
subtreeAt []          t                = Just t
subtreeAt (0 : rest) (Branch _ _ l _)  = subtreeAt rest l
subtreeAt (1 : rest) (Branch _ _ _ r)  = subtreeAt rest r
subtreeAt _           _                = Nothing

-- | The branching factor a view uses. @16² / 4⁴ / 2⁸@.
data Branching = B16 | B4 | B2
  deriving (Eq, Show, Enum, Bounded)

-- | Children per internal node in this view.
branchFactor :: Branching -> Int
branchFactor B16 = 16
branchFactor B4  = 4
branchFactor B2  = 2

-- | View depth: @branchFactor b ^ branchDepth b == 256@.
branchDepth :: Branching -> Int
branchDepth B16 = 2
branchDepth B4  = 4
branchDepth B2  = 8

-- | How many binary levels collapse into one view level (@log2 (branchFactor b)@).
-- Invariant: @collapseK b * branchDepth b == paletteDepth@ ('lawCollapseDepthInvariant').
collapseK :: Branching -> Int
collapseK B16 = 4
collapseK B4  = 2
collapseK B2  = 1

-- | An @n@-ary view of the partition (children count = @2^k@ at full internal nodes).
data NaryTree = NLeaf IndexedColor | NBranch [NaryTree]
  deriving (Eq, Show)

-- | The subtrees rooted at binary depth @k@ (clamped at leaves). For a tree of depth
-- @>= k@ this returns @2^k@ subtrees.
descendantsAt :: Int -> SplitTree -> [SplitTree]
descendantsAt k t
  | k <= 0          = [t]
descendantsAt _ t@(Leaf _) = [t]
descendantsAt k (Branch _ _ l r) =
  descendantsAt (k - 1) l ++ descendantsAt (k - 1) r

-- | Collapse every @k@ binary levels into one @2^k@-ary level.
collapseLevels :: Int -> SplitTree -> NaryTree
collapseLevels _ (Leaf ic) = NLeaf ic
collapseLevels k t         = NBranch (map (collapseLevels k) (descendantsAt k t))

-- | The branching view: @b@ chooses how many levels to collapse.
viewBranching :: Branching -> SplitTree -> NaryTree
viewBranching b = collapseLevels (collapseK b)

-- | Leaves of an n-ary view, in canonical order.
naryLeaves :: NaryTree -> [IndexedColor]
naryLeaves (NLeaf ic)  = [ic]
naryLeaves (NBranch cs) = concatMap naryLeaves cs

-- | Child counts of every internal n-ary node (for the "exactly @b@ children" law).
naryChildCounts :: NaryTree -> [Int]
naryChildCounts (NLeaf _)   = []
naryChildCounts (NBranch cs) = length cs : concatMap naryChildCounts cs

-- | SixFour pins the depth at 8 → @2⁸ = 256@ leaves (= @K@ = 'kVal').
paletteDepth :: Int
paletteDepth = 8

-- | Leaf count @2^paletteDepth@ (= 256).
numLeaves :: Int
numLeaves = 2 ^ paletteDepth

--------------------------------------------------------------------------------
-- Laws (predicates; exercised by Properties.SplitTree)
--------------------------------------------------------------------------------

-- Implication, low fixity so @p ==> x == y@ parses as @p ==> (x == y)@.
infix 1 ==>
(==>) :: Bool -> Bool -> Bool
p ==> q = not p || q

-- | The tree's leaves are exactly the input colours (as a multiset of indices): a true
-- partition keeps every colour, once.
lawLeafCountIsInput :: [IndexedColor] -> Bool
lawLeafCountIsInput ics =
  not (null ics) ==>
    length (leaves (buildSplitTree ics)) == length ics

-- | The partition is exact: the set of leaf indices equals the set of input indices,
-- with no duplication or loss (for distinct input indices).
lawPartition :: [IndexedColor] -> Bool
lawPartition ics =
  let idxs = map icIndex ics
  in not (null ics) && distinct idxs ==>
       sortInt (leafIndices (buildSplitTree ics)) == sortInt idxs
  where
    distinct xs   = sortInt xs == dedup (sortInt xs)
    dedup (x:y:r) | x == y    = dedup (y:r)
                  | otherwise = x : dedup (y:r)
    dedup xs      = xs
    sortInt       = sortBy compare

-- | 'buildSplitTree' depends only on the /set/ of points, not their order: building from
-- a reversed input yields an identical tree (the @(coord, index)@ key is a total order).
lawDeterministicUnderPermutation :: [IndexedColor] -> Bool
lawDeterministicUnderPermutation ics =
  buildSplitTree ics == buildSplitTree (reverse ics)

-- | Each child's bounding box is contained in its parent's (the split never grows a box).
lawChildBoxesNested :: [IndexedColor] -> Bool
lawChildBoxesNested ics = not (null ics) ==> go (buildSplitTree ics)
  where
    go (Leaf _) = True
    go (Branch _ _ l r) =
      contains (boxOf l) && contains (boxOf r) && go l && go r
      where
        parent = boundingBox (map icColor (leaves (Branch AxisL 0 l r)))
        contains b = boxInside b parent
    boxOf t = boundingBox (map icColor (leaves t))
    boxInside (OKLabBox (OKLab l1 a1 b1) (OKLab l2 a2 b2))
              (OKLabBox (OKLab pl1 pa1 pb1) (OKLab pl2 pa2 pb2)) =
         l1 >= pl1 && a1 >= pa1 && b1 >= pb1
      && l2 <= pl2 && a2 <= pa2 && b2 <= pb2

-- | A perfect depth-@d@ tree (from @2^d@ points) has exactly @2^d − 1@ split planes.
lawPlaneCount :: Int -> Bool
lawPlaneCount d =
  let n = 2 ^ max 0 (min 8 d)
      t = buildSplitTree (sampleColors n)
  in numPlanes t == n - 1

-- | Every leaf is reachable by its own address, and the address resolves back to it.
lawAddressRoundTrip :: [IndexedColor] -> Bool
lawAddressRoundTrip ics = not (null ics) ==>
  all ok (leafPaths t)
  where
    t = buildSplitTree ics
    ok (path, ic) = case subtreeAt path t of
      Just (Leaf ic') -> ic' == ic
      _               -> False

-- | All leaf addresses are distinct (the addressing is injective).
lawAddressesDistinct :: [IndexedColor] -> Bool
lawAddressesDistinct ics = not (null ics) ==>
  let ps = map fst (leafPaths (buildSplitTree ics))
  in length ps == length (nubPaths ps)
  where
    nubPaths []       = []
    nubPaths (x : xs) = x : nubPaths (filter (/= x) xs)

-- | Collapsing the binary tree to ANY branching preserves the leaf sequence exactly.
lawCollapsePreservesLeaves :: Branching -> [IndexedColor] -> Bool
lawCollapsePreservesLeaves b ics = not (null ics) ==>
  naryLeaves (viewBranching b t) == leaves t
  where t = buildSplitTree ics

-- | In the SixFour-shape tree (perfect depth 8, where @collapseK b@ divides 8), every
-- internal node of the @b@-view has exactly @branchFactor b@ children.
lawViewChildCount :: Branching -> Bool
lawViewChildCount b =
  let t = buildSplitTree (sampleColors numLeaves)
      counts = naryChildCounts (viewBranching b t)
  in all (== branchFactor b) counts && not (null counts)

-- | The arithmetic through-line: @256 = 16² = 4⁴ = 2⁸@, every view satisfies
-- @bᵈ = 256@, and octree (@b = 8@) is impossible because @3 ∤ 8@ (no integer @d@ with
-- @8ᵈ = 256@). Also @numLeaves == kVal@.
lawBranchingArithmetic :: Bool
lawBranchingArithmetic =
     (16 ^ (2 :: Int) == (256 :: Int))
  && (4  ^ (4 :: Int) == 256)
  && (2  ^ (8 :: Int) == 256)
  && all (\b -> branchFactor b ^ branchDepth b == 256) [B16, B4, B2]
  && not (any (\d -> (8 :: Int) ^ d == 256) [1 .. 8 :: Int])
  && numLeaves == kVal

-- | The collapse bookkeeping: @collapseK b * branchDepth b == paletteDepth@ for every view.
lawCollapseDepthInvariant :: Bool
lawCollapseDepthInvariant =
  all (\b -> collapseK b * branchDepth b == paletteDepth) [B16, B4, B2]

--------------------------------------------------------------------------------
-- internal: a deterministic, distinct colour sample (for the `once` shape laws)
--------------------------------------------------------------------------------

-- | @n@ distinct OKLab colours spread across all three axes (so median-cut splits each
-- axis). Pure and deterministic — used to build fixed-shape trees in the `once` laws.
sampleColors :: Int -> [IndexedColor]
sampleColors n =
  [ IndexedColor i (OKLab (frac (fromIntegral i * 0.6180339887498949))
                          (0.4 * (frac (fromIntegral i * 0.3819660112501051) * 2 - 1))
                          (0.4 * (frac (fromIntegral i * 0.2360679774997897) * 2 - 1)))
  | i <- [0 .. n - 1] ]
  where frac x = x - fromIntegral (floor x :: Int)

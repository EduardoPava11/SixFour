{- |
Module      : SixFour.Spec.Quad4
Description : Depth-4 4-ary opponent-quadrant palette tree (an alternative to 'Spec.PairTree').

A second 'Spec.PairTree'-equivalent, structurally distinct: a 4-ary tree of depth 4.
Same 256 leaves, same balanced-mean property, but each non-leaf node has **four**
children parameterised by **two** independent OKLab offset vectors @(δ₁, δ₂)@:

    child(s1, s2) = parent + s1·δ₁ + s2·δ₂      where (s1, s2) ∈ {+1, −1}²

The four children form a 2×2 mirror grid about the parent, so the sum of children
equals 4·parent — the balanced-mean law transfers verbatim from 'Spec.PairTree'.

== Opponent-quadrant inductive bias

If @δ₁@ and @δ₂@ are aligned with the OKLab a and b axes (e.g.
@δ₁ = (0, x, 0)@, @δ₂ = (0, 0, y)@), the four children land in the four
chromatic-opponent quadrants relative to the parent — the Hering opponent-process
inductive bias (geometric, not perceptual; cf. Conway et al. 2023, /End of Hering's
Opponent-Colors Theory/, Trends Cogn Sci). The module does not /force/ that
alignment — the 6 DOF per node admit any chromatic split — but the 4-ary topology
is the natural structural carrier for it.

== Genome budget

    Levels (ℓ = 0..3):       4-ary
    Non-leaf nodes / level:  1, 4, 16, 64
    Total non-leaf nodes:    1 + 4 + 16 + 64 = 85
    Free reals:              3 (root)
                           + 6 (two OKLab offsets per non-leaf) × 85
                           = 513

So Quad4 has **513 DOF** vs PairTree's **768** (a 33% reduction). The saving is
the structural cost of the 4-ary topology, paid back as inductive bias.

== Compatibility with PairTree

There is an injective linear map @Quad4Palette → HaarPalette@: the two binary
splits implicit in each Quad4 node (first by ±δ₁, then by ±δ₂) embed as two
consecutive levels of the binary Haar pyramid. This means the v1 1+1-ES search
('studio/look-nn', see @spec/COMPETITION.md@) can bootstrap one space from the
other without losing structure.

This module ADDS an alternative; it does NOT replace 'Spec.PairTree'. The choice
between binary Haar and 4-ary opponent-quadrant is resolved by empirical
measurement on captured data, per the plan in
@~/.claude/plans/flickering-dazzling-dewdrop.md@.

Laws (see @Properties.Quad4@): leaf count = 256; DOF = 513;
@reconstruct ∘ Quad4Palette ∘ unflatten = id@ (vector round-trip);
balanced mean (mean of leaves = root); σ-equivariance
(@reconstruct (σ qp) ≡ map σ (reconstruct qp)@).
-}
-- COMPARTMENT: MLX-MODEL | tag:MacTag
module SixFour.Spec.Quad4
  ( -- * The 4-ary opponent-quadrant tree
    Quad4Palette(..)
  , quad4Depth
  , quad4Leaves
  , quad4NodesPerLevel
  , quad4NonLeafNodes
  , quad4DegreesOfFreedom
  , quad4WellFormed
    -- * Forward / inverse
  , reconstruct
  , quad4Analyze
  , reconstructFromVector
  , toVector
  , paletteToVec
    -- * Laws
  , lawLeafCount256
  , lawDOF513
  , lawBalancedMean
  , lawSigmaEquivariance
  , lawReconstructRoundTrip
  , lawQuad4AnalyzeRoundTrip
  ) where

import qualified Data.Vector.Unboxed as U
import           Data.Vector.Unboxed (Vector)

import SixFour.Spec.Color    (OKLab(..))
import SixFour.Spec.PairTree (sigmaReflect)

-- | Flatten a 256-leaf palette to a flat 768-vector @(L₀, a₀, b₀, L₁, a₁, b₁, …)@.
-- (Moved here from the retired @Spec.Quad4Fit@ capacity-analysis experiment — this
-- was its only production reuse; see docs/SIXFOUR-BURES-DISCRETE-CORRECTION.md §0.)
paletteToVec :: [OKLab] -> Vector Double
paletteToVec leaves = U.fromList (concatMap okToList leaves)
  where okToList (OKLab l a b) = [l, a, b]

-- | A depth-4 4-ary palette tree. Each non-leaf node carries two independent OKLab
-- offsets @(δ₁, δ₂)@; the four children are @parent ± δ₁ ± δ₂@. Levels are top-down;
-- @nodeOffsets !! ℓ@ has @4^ℓ@ entries, each a pair of OKLab offsets.
data Quad4Palette = Quad4Palette
  { quad4Root        :: OKLab
  , quad4NodeOffsets :: [[(OKLab, OKLab)]]
  } deriving (Eq, Show)

-- | Pinned depth: 4 levels of 4-ary splits → @4^4 = 256@ leaves.
quad4Depth :: Int
quad4Depth = 4

-- | Leaf count: @4^quad4Depth = 256@.
quad4Leaves :: Int
quad4Leaves = 4 ^ quad4Depth

-- | Non-leaf nodes per level: @4^ℓ@ for @ℓ = 0..3@.
quad4NodesPerLevel :: [Int]
quad4NodesPerLevel = [ 4 ^ l | l <- [0 .. quad4Depth - 1] ]

-- | Total non-leaf nodes = @1 + 4 + 16 + 64 = 85@.
quad4NonLeafNodes :: Int
quad4NonLeafNodes = sum quad4NodesPerLevel

-- | DOF: @3 (root) + 6 (two OKLab offsets per non-leaf node) × 85 = 513@.
quad4DegreesOfFreedom :: Int
quad4DegreesOfFreedom = 3 + 6 * quad4NonLeafNodes

-- | A 'Quad4Palette' is well-formed iff it has exactly 'quad4Depth' levels and
-- level @ℓ@ has @4^ℓ@ offset pairs.
quad4WellFormed :: Quad4Palette -> Bool
quad4WellFormed (Quad4Palette _ lvls) =
  length lvls == quad4Depth &&
  and [ length (lvls !! l) == quad4NodesPerLevel !! l
      | l <- [0 .. quad4Depth - 1] ]

-- internal OKLab vector ops (kept local — mirrors 'Spec.PairTree' to avoid a
-- public OKLab vector-space export from Color).
addOK, subOK :: OKLab -> OKLab -> OKLab
addOK (OKLab l a b) (OKLab l' a' b') = OKLab (l + l') (a + a') (b + b')
subOK (OKLab l a b) (OKLab l' a' b') = OKLab (l - l') (a - a') (b - b')

scaleOK :: Double -> OKLab -> OKLab
scaleOK s (OKLab l a b) = OKLab (s * l) (s * a) (s * b)

-- | Expand a 'Quad4Palette' into its 256 leaves, in fixed @(+ +), (+ −), (− +),
-- (− −)@ sign order per node (so the leaf index has a natural 2-bit-per-level
-- encoding @(s₁, s₂)@).
reconstruct :: Quad4Palette -> [OKLab]
reconstruct (Quad4Palette rt lvls) = foldl step [rt] lvls
  where
    step nodes offs = concat
      [ let pp = addOK parent d1
            pm = subOK parent d1
        in [ addOK pp d2, subOK pp d2, addOK pm d2, subOK pm d2 ]
      | (parent, (d1, d2)) <- zip nodes offs
      ]

-- | Forward 4-ary transform: analyse 256 leaves into a 'Quad4Palette' (the inverse of
-- 'reconstruct' on the Quad4 subspace). Group the leaves in fours in
-- @(+ +),(+ −),(− +),(− −)@ order; per quad recover @parent = mean@,
-- @δ₁ = ((c₀+c₁) − (c₂+c₃))/4@, @δ₂ = ((c₀−c₁) + (c₂−c₃))/4@; recurse on the parents.
--
-- NOTE: Quad4 is a **513-DOF subspace** of the 768-DOF leaf space (Quad4's
-- balanced-mean constraint @c₀ − c₁ − c₂ + c₃ = 0@ per node). So for leaves that are
-- themselves a 'reconstruct' of some Quad4Palette this is an EXACT inverse
-- ('lawQuad4AnalyzeRoundTrip'); for arbitrary leaves it is the mean-pyramid
-- **projection** onto the opponent-quadrant subspace (the closest 4-ary genome — the
-- lossy bias the @4⁴@ branching deliberately imposes on the global palette).
quad4Analyze :: [OKLab] -> Quad4Palette
quad4Analyze leaves0 = go leaves0 []
  where
    go cur acc
      | length cur <= 1 = Quad4Palette (headOr0 cur) acc
      | otherwise       = let reduced = quadReduce cur
                          in go (map fst reduced) (map snd reduced : acc)
    quadReduce (c0 : c1 : c2 : c3 : rest) =
      let p  = scaleOK 0.25 (c0 `addOK` c1 `addOK` c2 `addOK` c3)
          d1 = scaleOK 0.25 ((c0 `addOK` c1) `subOK` (c2 `addOK` c3))
          d2 = scaleOK 0.25 ((c0 `subOK` c1) `addOK` (c2 `subOK` c3))
      in (p, (d1, d2)) : quadReduce rest
    quadReduce _ = []
    headOr0 (x : _) = x
    headOr0 []      = OKLab 0 0 0

-- | Flatten a 'Quad4Palette' to its 513-coefficient genome vector. Order:
-- root, then @(δ₁_L, δ₁_a, δ₁_b, δ₂_L, δ₂_a, δ₂_b)@ per non-leaf node in
-- top-down level-major order.
toVector :: Quad4Palette -> Vector Double
toVector (Quad4Palette rt lvls) =
  U.fromList $
    okLabToList rt ++ concatMap (concatMap pairToList) lvls
  where
    okLabToList (OKLab l a b) = [l, a, b]
    pairToList (d1, d2) = okLabToList d1 ++ okLabToList d2

-- | Inverse of 'toVector': read a 513-vector back into a 'Quad4Palette' and
-- expand. Returns 'Nothing' on a length mismatch.
reconstructFromVector :: Vector Double -> Maybe [OKLab]
reconstructFromVector v
  | U.length v /= quad4DegreesOfFreedom = Nothing
  | otherwise =
      let rt   = OKLab (v U.! 0) (v U.! 1) (v U.! 2)
          xs   = U.toList (U.drop 3 v)
          lvls = unflatten xs quad4NodesPerLevel
      in Just (reconstruct (Quad4Palette rt lvls))
  where
    unflatten _  []     = []
    unflatten ys (n:ns) =
      let (now, rest) = splitAt (6 * n) ys
      in chunksOfPair now : unflatten rest ns
    chunksOfPair (l1:a1:b1:l2:a2:b2:rest) =
      (OKLab l1 a1 b1, OKLab l2 a2 b2) : chunksOfPair rest
    chunksOfPair _ = []

-- * Laws

-- | A well-formed 'Quad4Palette' reconstructs to exactly 256 leaves.
lawLeafCount256 :: Quad4Palette -> Bool
lawLeafCount256 qp =
  not (quad4WellFormed qp) || length (reconstruct qp) == quad4Leaves

-- | The dimensional accounting: 513 = 3 + 6·85, 85 = 1+4+16+64, leaves = 256.
lawDOF513 :: Bool
lawDOF513 =
     quad4DegreesOfFreedom == 513
  && quad4NonLeafNodes     == 85
  && quad4Leaves           == 256
  && quad4Depth            == 4
  && quad4NodesPerLevel    == [1, 4, 16, 64]

-- | Balanced mean: the sum of children equals 4·parent at every node, so the
-- mean of all 256 leaves equals the root.
lawBalancedMean :: Double -> Quad4Palette -> Bool
lawBalancedMean tol qp =
  not (quad4WellFormed qp) ||
  let ls = reconstruct qp
      n  = length ls
      m  = scaleOK (1 / fromIntegral n) (foldl addOK (OKLab 0 0 0) ls)
  in okClose tol m (quad4Root qp)

-- | σ-equivariance: applying σ to the root + every offset gives a palette equal
-- to the σ-reflection of the original.
lawSigmaEquivariance :: Double -> Quad4Palette -> Bool
lawSigmaEquivariance tol qp@(Quad4Palette rt lvls) =
  let qpS = Quad4Palette (sigmaReflect rt)
              [ [ (sigmaReflect d1, sigmaReflect d2) | (d1, d2) <- lvl ] | lvl <- lvls ]
      lhs = map sigmaReflect (reconstruct qp)
      rhs = reconstruct qpS
  in length lhs == length rhs && and (zipWith (okClose tol) lhs rhs)

-- | On the Quad4 subspace, 'quad4Analyze' inverts 'reconstruct': analysing the leaves of
-- a well-formed palette and reconstructing returns the same leaves. (For arbitrary leaves
-- 'quad4Analyze' is the lossy opponent-quadrant projection — not covered by this law.)
lawQuad4AnalyzeRoundTrip :: Double -> Quad4Palette -> Bool
lawQuad4AnalyzeRoundTrip tol qp =
  not (quad4WellFormed qp) ||
  let leaves = reconstruct qp
      back   = reconstruct (quad4Analyze leaves)
  in length back == length leaves && and (zipWith (okClose tol) back leaves)

-- | @reconstructFromVector ∘ toVector = reconstruct@.
lawReconstructRoundTrip :: Double -> Quad4Palette -> Bool
lawReconstructRoundTrip tol qp =
  not (quad4WellFormed qp) ||
  case reconstructFromVector (toVector qp) of
    Nothing -> False
    Just ls -> let target = reconstruct qp
               in length ls == length target && and (zipWith (okClose tol) ls target)

-- internal: per-channel closeness (mirrors 'Spec.PairTree')
okClose :: Double -> OKLab -> OKLab -> Bool
okClose tol (OKLab l a b) (OKLab l' a' b') =
  abs (l - l') <= tol && abs (a - a') <= tol && abs (b - b') <= tol

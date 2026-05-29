{- |
Module      : SixFour.Spec.PairTree
Description : The recursive σ-balanced pairing tree — the palette's dimensional space.

The global palette is not "256 colours" but a **perfect binary tree of balanced
pairs**, @[(1:1):(1:1)]:…@. Since @256 = 2⁸@ the tree has 8 levels of pairing. Each
node splits into two children that are **mirror images about the parent**
(@childₗ = parent + δ@, @childᵣ = parent − δ@) — i.e. the **Haar multiresolution**:
the parent is the average, the offset @δ@ is the detail. The palette is the inverse
Haar transform of a tree of @2⁸ − 1 = 255@ offset vectors.

This module *opens the NN's dimensional space*: it fixes what is structural (the
dyadic topology and the by-construction balance) and exposes the free parameters
(the root + 255 offsets = @3·256 = 768@ reals, addressed as 8 levels of detail).
See @spec/NN_SPACE_NOTES.md@. Contract-first: every function here is a total
reference implementation (no stubs); the network is one inhabitant.
-}
module SixFour.Spec.PairTree
  ( -- * The pairing tree
    HaarPalette(..)
  , wellFormed
  , treeDepth
    -- * SixFour's choice (256 = 2⁸ leaves)
  , paletteDepth
  , numLeaves
  , numInternal
  , degreesOfFreedom
  , levelDof
    -- * Forward / inverse Haar (palette ↔ tree)
  , reconstruct
  , analyze
    -- * Degrees of freedom of interest
  , pairOffsets
  , pairDistances
  , offsetMagnitude
  , levelMeanMagnitude
    -- * φ self-similar coefficient decay (the golden falloff)
  , phi
  , goldenDecay
  , lawGoldenDecayRatio
  , lawGoldenDecayHaltPriorMonotone
    -- * The chroma reflection σ (the exact, continuous OKLab complement)
  , sigmaReflect
    -- * Laws (predicates; QuickCheck'd in Properties.PairTree)
  , lawReconstructAnalyzeRoundTrip
  , lawSigmaInvolution
  , lawSigmaEuclideanIsometry
  , lawBalancedMean
  , lawLeafCount
  , lawDegreesOfFreedom
  , lawGamutClosure
  , inGamut
  ) where

import SixFour.Spec.Color (OKLab(..), okLabDistanceSquared)
import SixFour.Spec.Shape (kVal)

-- | A palette as a Haar pyramid: a @root@ (the mean/DC colour) plus, for each of
-- the @D@ levels, the offset vectors applied at that split. Level @i@ (0-based)
-- carries @2^i@ offsets, so the tree has @2^D@ leaves. 'wellFormed' checks this.
data HaarPalette = HaarPalette
  { root   :: OKLab
  , levels :: [[OKLab]]   -- ^ top-down; @levels !! i@ has @2^i@ offsets
  } deriving (Eq, Show)

-- | Number of pairing levels @D@.
treeDepth :: HaarPalette -> Int
treeDepth = length . levels

-- | A palette is well-formed iff level @i@ has exactly @2^i@ offsets.
wellFormed :: HaarPalette -> Bool
wellFormed (HaarPalette _ lvls) =
  and [ length (lvls !! i) == 2 ^ i | i <- [0 .. length lvls - 1] ]

-- | The chroma reflection @σ(L,a,b) = (L,−a,−b)@ — the exact, **continuous** OKLab
-- complement (the @a@/@b@ axes are the red–green / yellow–blue opponent channels).
-- This replaces the deleted category complement map: the complement falls out of the
-- geometry of OKLab, with no 11-category lookup and no @[4,2,1]@ metric. It is the
-- σ the decoder's L6 equivariance @D(σ·z) = σ·D(z)@ is stated against, and the
-- special case of the tree's mirror balance @parent ± δ@ when the parent is neutral.
sigmaReflect :: OKLab -> OKLab
sigmaReflect (OKLab l a b) = OKLab l (negate a) (negate b)

-- | SixFour pins the depth at 8 → @2⁸ = 256@ leaves (= @K@).
paletteDepth :: Int
paletteDepth = 8

-- | Leaf count @2^paletteDepth@ (= 256 = 'kVal').
numLeaves :: Int
numLeaves = 2 ^ paletteDepth

-- | Internal-node (offset) count @2^D − 1 = 255@.
numInternal :: Int
numInternal = numLeaves - 1

-- | Free reals: @3@ for the root + @3@ per offset = @3·2^D = 768@. The tree does
-- not add or remove freedom — it reorganises the 256·3 palette reals into a
-- multiresolution the network can specialise over.
degreesOfFreedom :: Int
degreesOfFreedom = 3 * numLeaves

-- | Offset degrees of freedom per level @[3, 6, 12, …, 384]@ (@3·2^(ℓ-1)@).
levelDof :: [Int]
levelDof = [ 3 * 2 ^ (l - 1) | l <- [1 .. paletteDepth] ]

-- internal OKLab vector ops
addOK, subOK :: OKLab -> OKLab -> OKLab
addOK (OKLab l a b) (OKLab l' a' b') = OKLab (l + l') (a + a') (b + b')
subOK (OKLab l a b) (OKLab l' a' b') = OKLab (l - l') (a - a') (b - b')

scaleOK :: Double -> OKLab -> OKLab
scaleOK s (OKLab l a b) = OKLab (s * l) (s * a) (s * b)

-- | Inverse Haar: expand the tree into its @2^D@ leaves (the palette), in a fixed
-- order. At each level a node @n@ with offset @d@ yields @[n+d, n−d]@.
reconstruct :: HaarPalette -> [OKLab]
reconstruct (HaarPalette rt lvls) = foldl step [rt] lvls
  where step nodes offs = concat [ [addOK n d, subOK n d] | (n, d) <- zip nodes offs ]

-- | Forward Haar: collapse a palette of @2^D@ leaves into its tree. Adjacent
-- leaves @(x,y)@ give parent @(x+y)/2@ and offset @(x−y)/2@; recurse to the root.
-- Inverse of 'reconstruct' (see 'lawReconstructAnalyzeRoundTrip').
analyze :: [OKLab] -> HaarPalette
analyze leaves0 = go leaves0 []
  where
    go cur acc
      | length cur <= 1 = HaarPalette (headOr0 cur) acc
      | otherwise =
          let reduced = pairReduce cur
          in go (map fst reduced) (map snd reduced : acc)
    pairReduce (x : y : rest) = (scaleOK 0.5 (addOK x y), scaleOK 0.5 (subOK x y)) : pairReduce rest
    pairReduce _ = []
    headOr0 (x : _) = x
    headOr0 []      = OKLab 0 0 0

-- | All @2^D − 1@ offset vectors (flattened, top-down).
pairOffsets :: HaarPalette -> [OKLab]
pairOffsets = concat . levels

-- | Euclidean magnitude of an offset.
offsetMagnitude :: OKLab -> Double
offsetMagnitude (OKLab l a b) = sqrt (l * l + a * a + b * b)

-- | The distance *within* each pair (= @2‖δ‖@) — the "range of distances" the
-- distance-head of the network controls.
pairDistances :: HaarPalette -> [Double]
pairDistances = map ((* 2) . offsetMagnitude) . pairOffsets

-- | Mean offset magnitude at each level (for characterising φ self-similarity).
levelMeanMagnitude :: HaarPalette -> [Double]
levelMeanMagnitude (HaarPalette _ lvls) =
  [ sum (map offsetMagnitude offs) / fromIntegral (max 1 (length offs)) | offs <- lvls ]

-- | The golden ratio φ = (1+√5)/2.
phi :: Double
phi = (1 + sqrt 5) / 2

-- | Self-similar coefficient decay: offset scale at @level@ = @base·(1/φ)^level@.
-- The φ hypothesis — a fractal palette whose detail shrinks by the golden ratio
-- per level (level 0 = base). Measured against free per-level scale (open Q).
goldenDecay :: Double -> Int -> Double
goldenDecay base level = base * (1 / phi) ^^ level

-- | The decay is self-similar: the ratio between consecutive levels is exactly
-- @1/φ@, for every level @0..paletteDepth-2@. Pure arithmetic; this pins the
-- /shape/ of the signal→noise falloff (not its empirical fit — that is a
-- trainer-side metric). @base@ must be non-zero.
lawGoldenDecayRatio :: Double -> Double -> Bool
lawGoldenDecayRatio tol base =
  base /= 0 &&
  all (\l -> abs (goldenDecay base (l + 1) / goldenDecay base l - (1 / phi)) <= tol)
      [0 .. paletteDepth - 2]

-- | goldenDecay as a halting prior: detail energy is strictly DECREASING per
-- level (coarse = signal, fine = noise), so the natural per-level "ponder budget"
-- @b_ℓ = goldenDecay base ℓ@ is strictly decreasing in @ℓ@ — equivalently, the
-- implied halt probability is monotone NON-DECREASING (more likely to halt as we
-- descend into the noise levels). For @base > 0@ over the @paletteDepth@ levels.
-- This pins the prior's monotone shape (Mixture-of-Recursions over Haar levels);
-- it is what makes "the math gives us signal to noise" a testable statement.
lawGoldenDecayHaltPriorMonotone :: Double -> Bool
lawGoldenDecayHaltPriorMonotone base =
  base <= 0 ||
  let budgets = [ goldenDecay base l | l <- [0 .. paletteDepth - 1] ]
  in and (zipWith (>) budgets (drop 1 budgets))   -- strictly decreasing

-- | A colour is in the working OKLab gamut (matches the Look contract bounds).
inGamut :: OKLab -> Bool
inGamut (OKLab l a b) =
  l >= 0 && l <= 1 && a >= -0.4 && a <= 0.4 && b >= -0.4 && b <= 0.4

-- | 'analyze' inverts 'reconstruct': re-analysing a palette and reconstructing it
-- returns the same leaves (Haar is an exact orthogonal transform).
lawReconstructAnalyzeRoundTrip :: Double -> [OKLab] -> Bool
lawReconstructAnalyzeRoundTrip tol leaves =
  let n = length leaves
  in not (isPow2 n) || n == 0 ||
     let back = reconstruct (analyze leaves)
     in length back == n && and (zipWith (okClose tol) back leaves)
  where isPow2 m = m > 0 && (m == 2 ^ (round (logBase 2 (fromIntegral m :: Double)) :: Int))

-- | Aggregate balance: the offsets cancel, so the mean of the leaves equals the
-- root. ("The pairs balance each other.")
lawBalancedMean :: Double -> HaarPalette -> Bool
lawBalancedMean tol hp =
  let ls = reconstruct hp
      m  = scaleOK (1 / fromIntegral (max 1 (length ls))) (foldl addOK (OKLab 0 0 0) ls)
  in okClose tol m (root hp)

-- | A well-formed tree of depth @D@ reconstructs to exactly @2^D@ leaves.
lawLeafCount :: HaarPalette -> Bool
lawLeafCount hp = not (wellFormed hp) || length (reconstruct hp) == 2 ^ treeDepth hp

-- | The bookkeeping identity @3 + 3·(2^D − 1) = 3·2^D@, and 'levelDof' sums to the
-- offset DOF. Pins the dimensional-space accounting (and that leaves match @K@).
lawDegreesOfFreedom :: Bool
lawDegreesOfFreedom =
     numLeaves == kVal
  && degreesOfFreedom == 3 + 3 * numInternal
  && sum levelDof == 3 * numInternal

-- | Gamut closure (conditional): if every reconstructed leaf is in gamut, the
-- palette is valid. (A bounded-offset tree satisfies this — see the generator.)
lawGamutClosure :: HaarPalette -> Bool
lawGamutClosure = all inGamut . reconstruct

-- | σ is an involution: @σ(σ x) = x@ (exact — negation is exact in 'Double').
lawSigmaInvolution :: OKLab -> Bool
lawSigmaInvolution x = sigmaReflect (sigmaReflect x) == x

-- | σ is an isometry of the (identity-metric) Euclidean OKLab distance:
-- @‖σx − σy‖² = ‖x − y‖²@. Exact — the @a@/@b@ deltas only flip sign, then square.
-- (This is the research-default metric; the deleted @[4,2,1]@ weighting is gone.)
lawSigmaEuclideanIsometry :: OKLab -> OKLab -> Bool
lawSigmaEuclideanIsometry x y =
  okLabDistanceSquared (sigmaReflect x) (sigmaReflect y) == okLabDistanceSquared x y

-- internal: per-channel closeness
okClose :: Double -> OKLab -> OKLab -> Bool
okClose tol (OKLab l a b) (OKLab l' a' b') =
  abs (l - l') <= tol && abs (a - a') <= tol && abs (b - b') <= tol

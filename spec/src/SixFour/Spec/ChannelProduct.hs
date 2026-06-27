{- |
Module      : SixFour.Spec.ChannelProduct
Description : ABSTRACT AGAIN: all NINE colour-by-space channel comparisons as FREE channels, none privileged. The colour axes @{L,a,b}@ and the space axes @{x,y,t}@ form a complete 3x3 bilinear comparison @M[c][s] = colour(c) * space(s)@ (the pairs @L:t, L:x, L:y, a:x, a:y, a:t, b:x, b:y, b:t@). This ONE object is three things at once: it is GIF89a (a separable @value (palette) x content (index)@ = a RANK-1 matrix, @lawComparisonIsSeparable@); it is a TRANSFORMER attention logit (the all-pairs outer product @q ⊗ k@ before softmax, @lawComparisonIsOuterProduct@); and it GENERALIZES "SixFour.Spec.DualCube" — that module paired only the φ6 DIAGONAL @{L:t, a:x, b:y}@, the three φ6-fixed cells; this compares the whole matrix.

PonderNet + transformers at the architecture level: the comparison matrix is the rank-1 attention
between the colour "query" and the space "key"; a learned head lifts it to full rank, and PonderNet
("SixFour.Spec.ScalePonder"\/"SixFour.Spec.LocalPonder") adapts how many refinement passes run over
it. H-JEPA stays the core (the self-supervised target is over this matrix), but the model is BIGGER
because the comparison is COMPLETE, not L-anchored.

The two lenses fall out of the matrix blocks: the balance:balance corner @L:t@ is a plain @ℤ@ lattice
product (DISCRETE GEOMETRY); the 2x2 search:search block @{a,b} x {x,y}@ ASSEMBLES into the @ℤ[i]@
Gaussian product @(a+b·i)(x+y·i)@ ("SixFour.Spec.GaussianChroma", ALGEBRAIC NUMBER THEORY,
@lawSearchBlockIsGaussianProduct@). KEYSTONE 'lawAllChannelsSeeWhatLAnchorMisses': two points that
differ only in chroma are IDENTICAL to the L-anchored (single-row) view but DISTINCT under the full
nine-channel comparison — the provable expressiveness gap behind the band-at-floor result. Pure-spec,
emits no golden.
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none
module SixFour.Spec.ChannelProduct
  ( -- * The 6 axis values of a point
    colorVal
  , spaceVal
  , colorVec
  , spaceVec
    -- * The nine free channel-pairs and their comparison matrix
  , pairings
  , comparePair
  , compareMatrix
  , phi6Fixed
    -- * Laws
  , lawNineFreeChannels
  , lawComparisonIsOuterProduct
  , lawComparisonIsSeparable
  , lawDiagonalIsPhi6Fixed
  , lawSearchBlockIsGaussianProduct
  , lawAllChannelsSeeWhatLAnchorMisses
  ) where

import SixFour.Spec.RefinementSystem (Gaussian(..), rmul)
import SixFour.Spec.XYTLabDuality    (Axis(..), Chroma(..), phi)
import SixFour.Spec.DualCube         (P6(..))

-- | The value of a colour axis at a point.
colorVal :: P6 -> Chroma -> Integer
colorVal p A = pA p
colorVal p B = pB p
colorVal p L = pL p

-- | The value of a space axis at a point.
spaceVal :: P6 -> Axis -> Integer
spaceVal p X = pX p
spaceVal p Y = pY p
spaceVal p T = pT p

-- | The colour vector @(a, b, L)@ in axis order (the GIF89a "value" / attention query).
colorVec :: P6 -> [Integer]
colorVec p = [ colorVal p c | c <- [minBound .. maxBound] ]

-- | The space vector @(x, y, t)@ in axis order (the GIF89a "content" / attention key).
spaceVec :: P6 -> [Integer]
spaceVec p = [ spaceVal p s | s <- [minBound .. maxBound] ]

-- | The nine FREE channel-pairs: every colour axis against every space axis. None privileged.
pairings :: [(Chroma, Axis)]
pairings = [ (c, s) | c <- [minBound .. maxBound], s <- [minBound .. maxBound] ]

-- | The bilinear comparison of one pair (the outer-product entry @colour(c) * space(s)@).
comparePair :: P6 -> (Chroma, Axis) -> Integer
comparePair p (c, s) = colorVal p c * spaceVal p s

-- | The full 3x3 comparison matrix (rows = colour axes, cols = space axes).
compareMatrix :: P6 -> [[Integer]]
compareMatrix p = [ [ comparePair p (c, s) | s <- [minBound .. maxBound] ]
                  | c <- [minBound .. maxBound] ]

-- | The three φ6-FIXED pairs (the "SixFour.Spec.DualCube" diagonal): a colour axis paired with the
-- space axis it is dual to under φ (@A:X, B:Y, L:T@). These are the cells φ6 leaves on the diagonal.
phi6Fixed :: [(Chroma, Axis)]
phi6Fixed = [ (c, s) | (c, s) <- pairings, phi s == c ]

-- ---------------------------------------------------------------------------
-- Laws
-- ---------------------------------------------------------------------------

-- | There are exactly NINE free channels (3 colour x 3 space), all distinct: the COMPLETE bipartite
-- comparison, no axis privileged. Teeth: a design that compared only one row (L-anchoring) sees 3.
lawNineFreeChannels :: Bool
lawNineFreeChannels =
  length pairings == 9 && length (nub pairings) == 9
  where nub = foldr (\x acc -> if x `elem` acc then acc else x : acc) []

-- | The comparison matrix is the OUTER PRODUCT @colourVec ⊗ spaceVec@ (the rank-1 attention logits
-- @q ⊗ k@). Teeth: any non-bilinear comparison breaks the factorization.
lawComparisonIsOuterProduct :: P6 -> Bool
lawComparisonIsOuterProduct p =
  compareMatrix p == [ [ c * s | s <- spaceVec p ] | c <- colorVec p ]

-- | GIF89a SEPARABILITY: the matrix is RANK 1 — every 2x2 minor vanishes, i.e. it factors as
-- @value (palette/colour) x content (index/space)@, exactly how GIF89a separates the palette from
-- the index map. Teeth: a rank-2 comparison (entangled value\/content) has a non-zero minor.
lawComparisonIsSeparable :: P6 -> Bool
lawComparisonIsSeparable p =
  let m = compareMatrix p
      at i j = (m !! i) !! j
  in and [ at i j * at i' j' == at i j' * at i' j
         | i <- [0 .. 2], i' <- [0 .. 2], j <- [0 .. 2], j' <- [0 .. 2] ]

-- | The "SixFour.Spec.DualCube" diagonal is exactly the φ6-fixed subset: the three pairs
-- @{(L,T), (A,X), (B,Y)}@. So the old L-anchored\/diagonal design is the φ6-fixed restriction of the
-- full nine-channel comparison, not a different object.
lawDiagonalIsPhi6Fixed :: Bool
lawDiagonalIsPhi6Fixed =
  length phi6Fixed == 3
  && all (\(c, s) -> phi s == c) phi6Fixed
  && (L, T) `elem` phi6Fixed && (A, X) `elem` phi6Fixed && (B, Y) `elem` phi6Fixed

-- | The SEARCH:SEARCH block @{a,b} x {x,y}@ assembles into the @ℤ[i]@ Gaussian product of the two
-- cubes' search planes: @(a+b·i)(x+y·i) = (ax - by) + (ay + bx)i@. So the off-diagonal chroma/space
-- comparisons ARE algebraic-number-theory: the product of the colour plane and the space plane. The
-- balance corner @L:t@ is the plain @ℤ@ lattice product (discrete geometry). Both lenses, one matrix.
lawSearchBlockIsGaussianProduct :: P6 -> Bool
lawSearchBlockIsGaussianProduct p =
  let chroma = Gaussian (pA p, pB p)            -- a + b i  (the colour search plane)
      plane  = Gaussian (pX p, pY p)            -- x + y i  (the space search plane)
      Gaussian (re, im) = rmul chroma plane
  in re == comparePair p (A, X) - comparePair p (B, Y)     -- ax - by
     && im == comparePair p (A, Y) + comparePair p (B, X)  -- ay + bx
     && comparePair p (L, T) == pL p * pT p                -- balance corner = the lattice product

-- | THE KEYSTONE (why bigger is strictly better): two points that differ ONLY in chroma @(a,b)@ are
-- IDENTICAL to the L-anchored view (the @L@ row of comparisons) but DISTINCT under the full
-- nine-channel comparison. The L-anchored model is provably blind to a difference the complete
-- comparison sees: the formal core of the band-at-floor result. Teeth: if the full matrix did not
-- distinguish them, comparing all channels would buy nothing.
lawAllChannelsSeeWhatLAnchorMisses :: Bool
lawAllChannelsSeeWhatLAnchorMisses =
  let p1 = P6 5 1 2 3 4 6      -- L=5, a=1, b=2, x=3, y=4, t=6
      p2 = P6 5 9 8 3 4 6      -- same L,x,y,t; chroma a,b differ
      lRow pt = [ comparePair pt (L, s) | s <- [minBound .. maxBound] ]   -- the L-anchored single row
  in lRow p1 == lRow p2                 -- L-anchoring sees them as IDENTICAL
     && compareMatrix p1 /= compareMatrix p2   -- the full nine-channel comparison distinguishes them

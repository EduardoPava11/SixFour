{- |
Module      : SixFour.Spec.Quad4Fixed
Description : The OWNED integer (Q16) Quad4 genome — exact on its subspace.

The integer twin of 'SixFour.Spec.Quad4' (the 4⁴ opponent-quadrant genome). Like
'SixFour.Spec.SigmaPairFixed', it is a STRUCTURED transform, so it integerizes with
NO quantization error: on the Quad4 subspace the four children of a node are
@p ± δ₁ ± δ₂@, hence

    c₀+c₁+c₂+c₃ = 4p,   (c₀+c₁)−(c₂+c₃) = 4δ₁,   (c₀−c₁)+(c₂−c₃) = 4δ₂

are EXACT multiples of 4. So integer @÷4@ (floor division == arithmetic shift
@>> 2@; the Swift/Zig ports use the same floor convention) recovers @(p, δ₁, δ₂)@
EXACTLY — 'lawQuad4FixedAnalyzeReconstructExact' holds with NO tolerance. On an
arbitrary palette @quad4AnalyzeFixed@ is a deterministic floor-PROJECTION onto the
opponent-quadrant subspace, and 'reconstructQuad4Fixed' ALWAYS emits the balance
constraint @c₀−c₁−c₂+c₃ = 0@ exactly ('lawQuad4FixedReconstructBalanced').

This keeps the 4⁴ GIFB global colour table byte-exact cross-device (the 2⁸ genome
is 'SixFour.Spec.SigmaPairFixed'; 16² is the identity). The trained look-NN is a
separate concern (dyadic fixed-point quantization), not these exact genome transforms.
-}
-- COMPARTMENT: ZIG-FLOOR | tag:DeviceTag
module SixFour.Spec.Quad4Fixed
  ( Quad4PaletteI(..)
  , quad4FixedDepth
  , quad4FixedWellFormed
  , reconstructQuad4Fixed
  , quad4AnalyzeFixed
  , quad4ProjectFixed
    -- * Laws (QuickCheck'd in Properties.Quad4Fixed)
  , lawQuad4FixedAnalyzeReconstructExact
  , lawQuad4FixedReconstructBalanced
  ) where

import SixFour.Spec.PairTreeFixed (OKLabI)

-- | A depth-4 4-ary integer palette tree. @nodeOffsets !! ℓ@ has @4^ℓ@ entries,
-- each an integer offset pair @(δ₁, δ₂)@ (matches 'SixFour.Spec.Quad4').
data Quad4PaletteI = Quad4PaletteI
  { quad4RootI        :: OKLabI
  , quad4NodeOffsetsI :: [[(OKLabI, OKLabI)]]
  } deriving (Eq, Show)

-- | Pinned depth: 4 levels → @4^4 = 256@ leaves.
quad4FixedDepth :: Int
quad4FixedDepth = 4

-- | Well-formedness of an integer Quad4 palette: exactly 'quad4FixedDepth' levels with the right widths.
quad4FixedWellFormed :: Quad4PaletteI -> Bool
quad4FixedWellFormed (Quad4PaletteI _ lvls) =
  length lvls == quad4FixedDepth &&
  and [ length (lvls !! l) == 4 ^ l | l <- [0 .. quad4FixedDepth - 1] ]

-- integer OKLab ops + floor div-by-4 (== arithmetic shift >> 2)
addI, subI :: OKLabI -> OKLabI -> OKLabI
addI (l, a, b) (l', a', b') = (l + l', a + a', b + b')
subI (l, a, b) (l', a', b') = (l - l', a - a', b - b')

div4I :: OKLabI -> OKLabI
div4I (l, a, b) = (l `div` 4, a `div` 4, b `div` 4)   -- floor; exact on multiples of 4

-- | Expand a 'Quad4PaletteI' into its leaves in @(+ +),(+ −),(− +),(− −)@ order.
reconstructQuad4Fixed :: Quad4PaletteI -> [OKLabI]
reconstructQuad4Fixed (Quad4PaletteI rt lvls) = foldl step [rt] lvls
  where
    step nodes offs = concat
      [ let pp = addI parent d1
            pm = subI parent d1
        in [ addI pp d2, subI pp d2, addI pm d2, subI pm d2 ]
      | (parent, (d1, d2)) <- zip nodes offs ]

-- | Forward 4-ary integer analyse: per quad, @p = ⌊Σ/4⌋@, @δ₁ = ⌊((c₀+c₁)−(c₂+c₃))/4⌋@,
-- @δ₂ = ⌊((c₀−c₁)+(c₂−c₃))/4⌋@; recurse on the parents (offsets coarsest-first).
quad4AnalyzeFixed :: [OKLabI] -> Quad4PaletteI
quad4AnalyzeFixed leaves0 = go leaves0 []
  where
    go cur acc
      | length cur <= 1 = Quad4PaletteI (headOr0 cur) acc
      | otherwise       = let reduced = quadReduce cur
                          in go (map fst reduced) (map snd reduced : acc)
    quadReduce (c0 : c1 : c2 : c3 : rest) =
      let p  = div4I (c0 `addI` c1 `addI` c2 `addI` c3)
          d1 = div4I ((c0 `addI` c1) `subI` (c2 `addI` c3))
          d2 = div4I ((c0 `subI` c1) `addI` (c2 `subI` c3))
      in (p, (d1, d2)) : quadReduce rest
    quadReduce _ = []
    headOr0 (x : _) = x
    headOr0 []      = (0, 0, 0)

-- | The 4⁴ genome PROJECTION: @reconstructQuad4Fixed ∘ quad4AnalyzeFixed@. The
-- byte-exact 256-leaf palette the 4⁴ control yields (lossy opponent-quadrant bias).
quad4ProjectFixed :: [OKLabI] -> [OKLabI]
quad4ProjectFixed = reconstructQuad4Fixed . quad4AnalyzeFixed

-- ---------------------------------------------------------------------------
-- Laws
-- ---------------------------------------------------------------------------

-- | EXACT (no tolerance): on the Quad4 subspace the children sums are multiples of
-- 4, so @quad4AnalyzeFixed ∘ reconstructQuad4Fixed = id@ on the tree.
lawQuad4FixedAnalyzeReconstructExact :: Quad4PaletteI -> Bool
lawQuad4FixedAnalyzeReconstructExact qp =
  not (quad4FixedWellFormed qp) ||
  quad4AnalyzeFixed (reconstructQuad4Fixed qp) == qp

-- | 'reconstructQuad4Fixed' ALWAYS emits the opponent-quadrant balance constraint
-- @c₀−c₁−c₂+c₃ = 0@ per leaf-quad (so the projection lands in the Quad4 subspace),
-- exactly in integers — for ANY well-formed tree.
lawQuad4FixedReconstructBalanced :: Quad4PaletteI -> Bool
lawQuad4FixedReconstructBalanced qp =
  not (quad4FixedWellFormed qp) ||
  let leaves = reconstructQuad4Fixed qp
  in all balancedQuad (chunk4 leaves)
  where
    chunk4 (a : b : c : d : rest) = (a, b, c, d) : chunk4 rest
    chunk4 _                      = []
    balancedQuad (c0, c1, c2, c3) =
      (c0 `subI` c1 `subI` c2 `addI` c3) == (0, 0, 0)

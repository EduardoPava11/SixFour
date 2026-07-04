{- |
Module      : SixFour.Spec.RootLatticeDecoder
Description : Inference on the detail band IS closest-vector decoding on A_{b-1}. This module is the decoder CONTRACT promised by spec/exploration/ModelAlgebra.hs: the exact Conway–Sloane closest-point algorithm for A_{b-1} (round each coordinate, then repair the sum deficiency at the coordinates with the worst rounding error), certified GLOBALLY optimal by beating every root e_i − e_j — because for A_{b-1} the Voronoi-relevant vectors are exactly the roots, local optimality against the b(b-1) roots is a global CVP certificate, in exact rational arithmetic, no floats.

Discrete geometry + algebraic number theory (the model side): a JEPA prediction of the detail
is a point of the Σ=0 plane with coefficients in ℤ[1/2] (dyadic model outputs); realizing it as
a byte-exact detail means decoding to the nearest point of A_{b-1} = ker Σ. The neural-decoder
literature (Corlay et al.) proves shallow learned decoders of A_n need EXPONENTIAL width, that
Weyl-group FOLDING (reflections = sorting into the fundamental chamber) collapses the decision
boundary to 2(b-1)-1 affine pieces (13 for the shipped A_7), and that gradient descent fails to
find the folding on its own. The design law this module gates: the folding is WIRED
('lawDecodeFactorsThroughFold'), learning only ever acts on the residual before decoding.

The Weyl group of A_{b-1} is S_b acting by coordinate permutation; the decoder commutes with it
('lawDecodeWeylEquivariant') and with lattice translations ('lawDecodeTranslationEquivariant'),
so the decode is gauge-honest: it depends on the geometry, not the chart.

HONEST BOUNDARY: 'round' at half-integers and equal rounding errors make the nearest point
genuinely NON-UNIQUE (the input sits on a Voronoi wall). Optimality ('lawDecodeVoronoiOptimal',
'lawDecodeInLattice') holds for EVERY input; the equivariance and folding laws are stated on the
generic (tie-free) stratum 'genericPoint' — on walls any minimizer is correct but the tiebreak
is chart-dependent, and we do not pretend otherwise. See "SixFour.Spec.RootLatticeDetail" for
the SES 0 → A_{b-1} → ℤ^b → ℤ → 0 that makes the detail band the kernel this decoder targets.
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none
module SixFour.Spec.RootLatticeDecoder
  ( -- * The exact Conway–Sloane closest-point decoder for A_{b-1}
    decodeClosest
  , allRoots
  , distSq
    -- * The generic (tie-free) stratum on which the chart-level laws are stated
  , genericPoint
    -- * Laws
  , lawDecodeInLattice
  , lawDecodeVoronoiOptimal
  , lawDecodeIdempotentOnLattice
  , lawDecodeTranslationEquivariant
  , lawDecodeWeylEquivariant
  , lawDecodeFactorsThroughFold
  , lawDecodeMatchesBruteForce
  ) where

import Data.List (nub, sortBy)
import Data.Ord (comparing)

-- | Exact Conway–Sloane closest-point decoding for @A_{b-1}@: round every coordinate,
-- then repair the integer sum deficiency d by stepping the |d| coordinates whose rounding
-- error makes the step cheapest (d > 0: subtract 1 where the error is most negative;
-- d < 0: add 1 where it is most positive). Consumes points of the Σ=0 plane; returns an
-- integer vector with Σ=0, i.e. a point of A_{b-1}.
decodeClosest :: [Rational] -> [Integer]
decodeClosest x
  | d > 0     = adjust d          (sortBy (comparing snd) idelta)            (subtract 1)
  | d < 0     = adjust (negate d) (sortBy (comparing (negate . snd)) idelta) (+ 1)
  | otherwise = f0
  where
    f0     = map round x
    delta  = zipWith (\xi fi -> xi - fromInteger fi) x f0
    idelta = zip [0 :: Int ..] delta
    d      = sum f0
    adjust k order op =
      let picked = map fst (take (fromInteger k) order)
      in [ if i `elem` picked then op fi else fi | (i, fi) <- zip [0 ..] f0 ]

-- | All @b(b-1)@ roots @e_i − e_j@ (i ≠ j) of @A_{b-1}@. For A_{b-1} these are exactly
-- the Voronoi-relevant vectors, so they define the Voronoi cell: beating all of them is
-- a GLOBAL closest-point certificate, not merely a local one.
allRoots :: Int -> [[Integer]]
allRoots b =
  [ [ unit i k - unit j k | k <- [0 .. b - 1] ]
  | i <- [0 .. b - 1], j <- [0 .. b - 1], i /= j ]
  where unit a k = if a == k then 1 else 0

-- | Exact squared Euclidean distance between a plane point and a lattice point.
distSq :: [Rational] -> [Integer] -> Rational
distSq x f = sum [ (xi - fromInteger fi) ^ (2 :: Int) | (xi, fi) <- zip x f ]

-- | The generic stratum: no coordinate sits at a rounding tie (|error| = 1/2) and all
-- rounding errors are pairwise distinct. Off this stratum the input lies on a Voronoi
-- wall and the nearest point is non-unique; optimality still holds, chart-level
-- equivariances are only stated here.
genericPoint :: [Rational] -> Bool
genericPoint x = all ((/= (1 / 2)) . abs) delta && length (nub delta) == length delta
  where delta = zipWith (\xi fi -> xi - fromInteger fi) x (map round x :: [Integer])

-- | LAW: the decode lands in the lattice — integer coordinates with Σ = 0
-- (membership in A_{b-1} = ker Σ). Holds for EVERY plane point, walls included.
lawDecodeInLattice :: [Rational] -> Bool
lawDecodeInLattice x = sum (decodeClosest x) == 0

-- | LAW (the global CVP certificate): the decoded point beats every root neighbour,
-- @distSq x f ≤ distSq x (f + r)@ for all roots r. Because the roots are the
-- Voronoi-relevant vectors of A_{b-1}, this is GLOBAL optimality, certified in exact
-- rational arithmetic. Holds for EVERY plane point.
lawDecodeVoronoiOptimal :: [Rational] -> Bool
lawDecodeVoronoiOptimal x =
  and [ distSq x f <= distSq x (zipWith (+) f r) | r <- allRoots (length x) ]
  where f = decodeClosest x

-- | LAW: a lattice point decodes to itself (zero residual is a fixed point).
lawDecodeIdempotentOnLattice :: [Integer] -> Bool
lawDecodeIdempotentOnLattice v = decodeClosest (map fromInteger v) == v

-- | LAW (generic stratum): translating by a lattice vector commutes with decoding,
-- @decode (x + λ) == decode x + λ@ — the decoder sees geometry, not position.
lawDecodeTranslationEquivariant :: [Rational] -> [Integer] -> Bool
lawDecodeTranslationEquivariant x lam
  | not (genericPoint x) = True
  | otherwise =
      decodeClosest (zipWith (\xi li -> xi + fromInteger li) x lam)
        == zipWith (+) (decodeClosest x) lam

-- | LAW (generic stratum): the decoder commutes with the Weyl group S_b acting by
-- coordinate permutation, @decode (σ·x) == σ·(decode x)@.
lawDecodeWeylEquivariant :: [Rational] -> [Int] -> Bool
lawDecodeWeylEquivariant x perm
  | not (genericPoint x) = True
  | otherwise = decodeClosest (apply x) == apply (decodeClosest x)
  where apply :: [a] -> [a]
        apply xs = map (xs !!) perm

-- | LAW (generic stratum, the WIRED FOLDING): decoding factors through the fold —
-- sort into the fundamental Weyl chamber, decode there, unsort:
-- @unsort (decode (sort x)) == decode x@. This is the executable shadow of the
-- 2(b-1)-1-piece folded-boundary theorem (13 pieces for the shipped A_7); the
-- reflections are structural, never learned.
lawDecodeFactorsThroughFold :: [Rational] -> Bool
lawDecodeFactorsThroughFold x
  | not (genericPoint x) = True
  | otherwise = unsorted == decodeClosest x
  where
    pairs    = sortBy (comparing fst) (zip x [0 :: Int ..])
    ds       = decodeClosest (map fst pairs)
    unsorted = map snd (sortBy (comparing fst) (zip (map snd pairs) ds))

-- | LAW (teeth for the Voronoi certificate, small dimension): in A_2 (b = 3) the
-- decoder agrees with brute-force nearest over an exhaustive box of lattice points —
-- independent confirmation that beating the roots really is global optimality.
lawDecodeMatchesBruteForce :: [Rational] -> Bool
lawDecodeMatchesBruteForce x =
  distSq x (decodeClosest x) == minimum (map (distSq x) candidates)
  where
    r = 2 + maximum (map (abs . round) x) :: Integer
    candidates =
      [ [a, b, negate (a + b)]
      | a <- [negate r .. r], b <- [negate r .. r]
      , abs (a + b) <= r ]

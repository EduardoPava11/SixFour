{- |
Module      : SixFour.Spec.MetricLattice
Description : The relational metric d6 generalized to an ℓ^p NORM on the integer lattice ℤ^d, with the norm exponent @p@ as a KNOB. The model runs @p = 1@ (the ℓ¹ / taxicab d6, whose unit ball is the cross-polytope / orthoplex); flipping the knob to @p = ∞@ gives the Chebyshev metric (unit ball = hypercube). Both are genuine integer lattice metrics (non-negative, faithful, symmetric, triangle), and they are GEOMETRICALLY DISTINCT — so the knob is real, not a rename.

Discrete geometry: the @ℓ¹@ unit ball is the cross-polytope with @2d+1@ integer points (centre + the
@±e_i@), the @ℓ^∞@ unit ball is the hypercube with @3^d@ integer points; @lawL1UnitBallIsCrossPolytope@
and @lawLInfUnitBallIsHypercube@ count them, and @lawUnitBallsDiffer@ shows they part company at @d ≥ 2@.
The @p = 1@ instance re-homes the d6 metric laws ("SixFour.Spec.RelationalMemory" @lawD6*@).

HONEST BOUNDARY (doc): @p = 2@ (Euclidean) is the knob value that unlocks the dual-lattice /
theta-series / sphere-packing machinery, but its triangle inequality needs Cauchy–Schwarz (a real,
not integer-comparison, fact) — it is NOT gated here; only the two integer-exact corners @p ∈ {1, ∞}@
are. The model itself uses @p = 1@.
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none
module SixFour.Spec.MetricLattice
  ( -- * The ℓ^p knob
    NormP(..)
  , norm
  , dist
  , unitBall
    -- * Laws
  , lawNormNonNeg
  , lawNormFaithful
  , lawDistSymmetric
  , lawTriangle
  , lawLInfBoundedByL1
  , lawL1UnitBallIsCrossPolytope
  , lawLInfUnitBallIsHypercube
  , lawUnitBallsDiffer
  ) where

-- | The norm exponent knob. @L1@ = the model's d6 (taxicab); @LInf@ = Chebyshev (max). (@p = 2@ is
-- a documented but un-gated extension — see the module note.)
data NormP = L1 | LInf deriving (Eq, Show)

-- | The ℓ^p norm of an integer lattice vector (integer-exact for @p ∈ {1, ∞}@).
norm :: NormP -> [Integer] -> Integer
norm L1   = sum . map abs
norm LInf = foldr (max . abs) 0

-- | The induced lattice metric @d_p(x,y) = ||x − y||_p@. (Vectors are taken at equal length.)
dist :: NormP -> [Integer] -> [Integer] -> Integer
dist p x y = norm p (zipWith (-) x y)

-- | The integer points of the radius-1 ball in @ℤ^d@ under norm @p@ (enumerated over @{-1,0,1}^d@,
-- which contains every radius-1 lattice point for both norms).
unitBall :: NormP -> Int -> [[Integer]]
unitBall p d = [ v | v <- box d, norm p v <= 1 ]
  where
    box 0 = [[]]
    box k = [ x : xs | x <- [-1, 0, 1], xs <- box (k - 1) ]

-- ---------------------------------------------------------------------------
-- Laws (the metric axioms hold for BOTH p instances; the geometry differs).
-- ---------------------------------------------------------------------------

-- | Non-negativity: @||v||_p ≥ 0@.
lawNormNonNeg :: NormP -> [Integer] -> Bool
lawNormNonNeg p v = norm p v >= 0

-- | Faithful (identity of indiscernibles): @||v||_p == 0@ iff @v@ is the zero vector.
lawNormFaithful :: NormP -> [Integer] -> Bool
lawNormFaithful p v = (norm p v == 0) == all (== 0) v

-- | Symmetry of the induced metric: @d_p(x,y) == d_p(y,x)@ (vectors zipped at equal length).
lawDistSymmetric :: NormP -> [Integer] -> [Integer] -> Bool
lawDistSymmetric p x y =
  let n = min (length x) (length y)
      x' = take n x; y' = take n y
  in dist p x' y' == dist p y' x'

-- | Triangle inequality: @||x + y||_p ≤ ||x||_p + ||y||_p@ (Minkowski; integer-exact for p ∈ {1,∞}).
lawTriangle :: NormP -> [Integer] -> [Integer] -> Bool
lawTriangle p x y =
  let n = min (length x) (length y)
      x' = take n x; y' = take n y
  in norm p (zipWith (+) x' y') <= norm p x' + norm p y'

-- | The norm inequality @||v||_∞ ≤ ||v||_1@ (the ℓ^∞ ball contains the ℓ¹ ball): a genuine lattice
-- geometry fact relating the two knob settings.
lawLInfBoundedByL1 :: [Integer] -> Bool
lawLInfBoundedByL1 v = norm LInf v <= norm L1 v

-- | The ℓ¹ unit ball is the CROSS-POLYTOPE (orthoplex): @2d + 1@ integer points (centre + @±e_i@).
lawL1UnitBallIsCrossPolytope :: Int -> Bool
lawL1UnitBallIsCrossPolytope d0 =
  let d = abs d0 `mod` 5
  in length (unitBall L1 d) == 2 * d + 1

-- | The ℓ^∞ unit ball is the HYPERCUBE: @3^d@ integer points (all of @{-1,0,1}^d@).
lawLInfUnitBallIsHypercube :: Int -> Bool
lawLInfUnitBallIsHypercube d0 =
  let d = abs d0 `mod` 5
  in length (unitBall LInf d) == 3 ^ d

-- | The knob is REAL: the two unit balls differ as soon as @d ≥ 2@ (@2d+1 < 3^d@), so @p = 1@ and
-- @p = ∞@ are genuinely different geometries, not a rename.
lawUnitBallsDiffer :: Bool
lawUnitBallsDiffer =
     length (unitBall L1 2) == 5      -- cross-polytope in ℤ²
  && length (unitBall LInf 2) == 9    -- hypercube in ℤ²
  && length (unitBall L1 2) /= length (unitBall LInf 2)

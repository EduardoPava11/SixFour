{- |
Module      : SixFour.Spec.GaussianLadder
Description : THE ARITHMETIC OF THE LADDER — one structure with four faces: DISCRETE GEOMETRY (the ℤ[i] square lattice and its quadtree), ALGEBRAIC NUMBER THEORY (the ramified prime (1+i) and its (1+i)-adic filtration), RADIOMETRY ("SixFour.Spec.ColorTime": the ideal NORM is the color-time), and SIMT MEMORY (the Morton/Z-order is at once the residue system and the GPU thread index whose contiguous fibers are the coalesced reduction). This module makes the identifications exact and proves them.

THE RING AND ITS RAMIFIED PRIME. The 2-D spatial sample lattice is the Gaussian integers @ℤ[i]@ (points @a+bi@), a Euclidean domain with multiplicative norm @N(a+bi)=a²+b²@ ('lawNormMultiplicative'). The rational prime 2 is NOT inert here: it RAMIFIES as @2 = -i·(1+i)²@ ('lawTwoRamifies'), so the single Gaussian prime @π = 1+i@ (with @N(π)=2@) sits above it. Halving the spatial resolution — the ladder's atomic move — is therefore division by one factor of 2 = one factor of @π²@. The rung-k pooling ideal is @π^{2k} = (2^k)@, and its norm (= the number of lattice points per pooled cell = the cell AREA) is @N(π^{2k}) = 2^{2k} = 4^k@ ('lawRungNormIsFour').

THE CROWN IDENTITY. The ideal norm and the color-time are the SAME 4^k: @N(π^{2k}) · Δ₀ = τ_c(k)@ ('lawNormIsColorTime', importing "SixFour.Spec.ColorTime"). The discrete-geometry area of a pooled cell and its radiometric integration window coincide because the ladder is ISOTROPIC — space and time coarsen by the same factor of 2. Norm multiplicativity makes the whole ladder a MONOID HOMOMORPHISM @(ℕ,+) → (ℕ,×)@, @k ↦ 4^k@ ('lawNormIsMonoidHom'): the algebraic reason the rungs form a geometric progression and compose (the number-theoretic shadow of "SixFour.Spec.ColorTime"'s @lawSumsCompose@).

THE SIMT UNIFICATION. A complete residue system for @ℤ[i]/π^{2k}@ is a @2^k × 2^k@ grid, and the MORTON code (bit-interleave of x,y) enumerates it bijectively into @[0,4^k)@ ('lawMortonBijection'). This Z-order is also the GPU global-memory layout. Two facts make the SIMT reduction correct BY CONSTRUCTION: (1) dropping resolution is a bit-shift — @parentCode = code ≫ 2@ — the memory image of the quotient @ℤ[i]/π^{2k} ↠ ℤ[i]/π^{2(k-1)}@ ('lawParentIsShift'); (2) the four geometric children @(2x+dx, 2y+dy)@ of a parent occupy four CONTIGUOUS codes @{4m, 4m+1, 4m+2, 4m+3}@ ('lawFiberContiguous'). So one SIMT thread per parent reduces a contiguous, coalesced 4-word fiber, and that memory-order quad reduction equals the geometric 2×2 spatial pool exactly ('lawSimtEqualsGeometric'). The Morton fiber IS the warp's coalesced load; the number theory guarantees the memory access pattern.

RELATION TO THE 3-D SPACETIME LADDER. This is the SPATIAL (2-D) slice: @ℤ[i]@, prime @(1+i)@, one octant-pair. The full isotropic 2×2×2 ladder tensors it with the 1-D TEMPORAL 2-adic line @ℤ₂@; the product residue field per rung is @(ℤ/2)³@ — the Morton "gene" @(Z_2)^3@ that "SixFour.Spec.ModelAlgebra"'s @SpineRing@ already carries. Pure-spec; exact @Integer@ / @Rational@.
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none
module SixFour.Spec.GaussianLadder
  ( -- * The Gaussian integers ℤ[i]
    GInt(..)
  , gAdd
  , gMul
  , gNorm
  , gConj
  , unitNegI
  , piGauss
  , gPow
    -- * The ramified ladder ideal
  , rungIdealNorm
    -- * Morton / Z-order — residue system == SIMT thread index
  , morton
  , unmorton
  , parentCode
  , childrenCodes
    -- * SIMT reduction vs geometric pooling
  , simtQuadReduce
  , geometricPool
    -- * Laws
  , lawNormMultiplicative
  , lawTwoRamifies
  , lawRungNormIsFour
  , lawNormIsColorTime
  , lawNormIsMonoidHom
  , lawMortonBijection
  , lawParentIsShift
  , lawFiberContiguous
  , lawSimtEqualsGeometric
  ) where

import Data.Bits (shiftL, shiftR, (.&.), (.|.))
import Data.List (sort)

import SixFour.Spec.ColorTime (colorTime)

-- | A Gaussian integer @a + b·i@ in the spatial sample lattice ℤ[i].
data GInt = GInt !Integer !Integer
  deriving (Eq, Show)

-- | Ring addition in ℤ[i].
gAdd :: GInt -> GInt -> GInt
gAdd (GInt a b) (GInt c d) = GInt (a + c) (b + d)

-- | Ring multiplication in ℤ[i]: @(a+bi)(c+di) = (ac−bd) + (ad+bc)i@.
gMul :: GInt -> GInt -> GInt
gMul (GInt a b) (GInt c d) = GInt (a * c - b * d) (a * d + b * c)

-- | The (multiplicative) field norm @N(a+bi) = a² + b² = (a+bi)(a−bi)@.
gNorm :: GInt -> Integer
gNorm (GInt a b) = a * a + b * b

-- | Complex conjugation @a+bi ↦ a−bi@ (the nontrivial Galois automorphism of ℚ(i)/ℚ).
gConj :: GInt -> GInt
gConj (GInt a b) = GInt a (negate b)

-- | The unit @−i@ (one of the four units @±1, ±i@); the associate factor in @2 = −i·(1+i)²@.
unitNegI :: GInt
unitNegI = GInt 0 (-1)

-- | The Gaussian prime @π = 1 + i@ above the rational prime 2. @N(π) = 2@.
piGauss :: GInt
piGauss = GInt 1 1

-- | Naive power @x^n@ in ℤ[i] (@n ≥ 0@); @x^0 = 1@.
gPow :: GInt -> Int -> GInt
gPow _ n | n <= 0 = GInt 1 0
gPow x n          = gMul x (gPow x (n - 1))

-- | Norm of the rung-k pooling ideal @π^{2k} = (2^k)@: @N(π^{2k}) = 4^k@. This is the pooled
-- cell AREA (lattice points per bin) and, by 'lawNormIsColorTime', the color-time factor.
rungIdealNorm :: Int -> Integer
rungIdealNorm k = 4 ^ max 0 k

-- | The Morton (Z-order) code of @(x,y)@ on a @2^k × 2^k@ grid: interleave the low @k@ bits,
-- x into the even positions, y into the odd. A bijection onto @[0, 4^k)@ ('lawMortonBijection')
-- and the SIMT global-memory index.
morton :: Int -> Int -> Int -> Int
morton k x y =
  foldr (.|.) 0
    [ (bitAt x i `shiftL` (2 * i)) .|. (bitAt y i `shiftL` (2 * i + 1))
    | i <- [0 .. k - 1] ]
  where bitAt v i = (v `shiftR` i) .&. 1

-- | Inverse of 'morton' at level @k@: split the interleaved bits back into @(x,y)@.
unmorton :: Int -> Int -> (Int, Int)
unmorton k c = (gather 0, gather 1)
  where gather o = foldr (.|.) 0 [ ((c `shiftR` (2 * i + o)) .&. 1) `shiftL` i | i <- [0 .. k - 1] ]

-- | The parent code one level coarser: @code ≫ 2@ — the memory image of the ring quotient
-- @ℤ[i]/π^{2k} ↠ ℤ[i]/π^{2(k-1)}@ (dropping resolution = dropping one factor of @π²@).
parentCode :: Int -> Int
parentCode c = c `shiftR` 2

-- | The four child codes of parent @m@: @{4m, 4m+1, 4m+2, 4m+3}@ — CONTIGUOUS, hence a
-- coalesced SIMT fiber ('lawFiberContiguous').
childrenCodes :: Int -> [Int]
childrenCodes m = [4 * m, 4 * m + 1, 4 * m + 2, 4 * m + 3]

-- | The SIMT reduction: one thread per parent sums its contiguous 4-word memory fiber.
-- @buf@ is a @4^k@-length buffer in Morton order; result is @4^{k-1}@ per-quad sums.
simtQuadReduce :: [Integer] -> [Integer]
simtQuadReduce buf =
  [ sum (take 4 (drop (4 * m) buf)) | m <- [0 .. length buf `div` 4 - 1] ]

-- | The GEOMETRIC 2×2 spatial pool of a Morton buffer: for each coarse cell (indexed by its
-- parent Morton code @m@) sum the four values at the geometric children @(2x+dx, 2y+dy)@.
-- Equal to 'simtQuadReduce' by Morton contiguity ('lawSimtEqualsGeometric').
geometricPool :: Int -> [Integer] -> [Integer]
geometricPool k buf =
  [ sum [ buf !! morton k (2 * px + dx) (2 * py + dy) | dx <- [0, 1], dy <- [0, 1] ]
  | m <- [0 .. 4 ^ (k - 1) - 1], let (px, py) = unmorton (k - 1) m ]

-- ─────────────────────────────────────────────────────────────────────────────
-- Laws
-- ─────────────────────────────────────────────────────────────────────────────

-- | The norm is multiplicative: @N(xy) = N(x)·N(y)@ (ℤ[i] is a normed ring / the norm is a
-- monoid hom on multiplication).
lawNormMultiplicative :: GInt -> GInt -> Bool
lawNormMultiplicative x y = gNorm (gMul x y) == gNorm x * gNorm y

-- | 2 RAMIFIES in ℤ[i]: @2 = −i·(1+i)²@ and @N(1+i) = 2@. The ladder's "halve the resolution"
-- is exactly "divide by one factor of the ramified prime squared".
lawTwoRamifies :: Bool
lawTwoRamifies = gMul unitNegI (gPow piGauss 2) == GInt 2 0 && gNorm piGauss == 2

-- | The rung ideal has norm @4^k@, whether counted as the declared 'rungIdealNorm' or computed
-- as @N(π^{2k})@ directly. This is the pooled cell area.
lawRungNormIsFour :: Int -> Bool
lawRungNormIsFour k =
  let kk = abs k
  in rungIdealNorm kk == 4 ^ kk && gNorm (gPow piGauss (2 * kk)) == rungIdealNorm kk

-- | THE CROWN IDENTITY: the pooling-ideal norm IS the color-time factor —
-- @N(π^{2k}) · Δ₀ = τ_c(k)@. Discrete-geometry area = radiometric integration window.
lawNormIsColorTime :: Rational -> Int -> Bool
lawNormIsColorTime d0 k =
  let kk = abs k in fromInteger (rungIdealNorm kk) * d0 == colorTime d0 kk

-- | The norm makes the ladder a MONOID HOMOMORPHISM @(ℕ,+) → (ℕ,×)@: @N(π^{2(a+b)}) =
-- N(π^{2a})·N(π^{2b})@, i.e. @4^{a+b} = 4^a·4^b@. Why rungs compose as a geometric progression.
lawNormIsMonoidHom :: Int -> Int -> Bool
lawNormIsMonoidHom a b =
  let (aa, bb) = (abs a, abs b)
  in rungIdealNorm (aa + bb) == rungIdealNorm aa * rungIdealNorm bb

-- | MORTON IS A BIJECTION: the @2^k × 2^k@ grid enumerates a complete residue system for
-- @ℤ[i]/π^{2k}@ exactly onto @[0, 4^k)@ — no thread index collides, none is skipped.
lawMortonBijection :: Int -> Bool
lawMortonBijection k =
  let kk = abs k `mod` 5   -- keep 4^kk small for the exhaustive check
      side = 2 ^ kk
  in sort [ morton kk x y | x <- [0 .. side - 1], y <- [0 .. side - 1] ] == [0 .. 4 ^ kk - 1]

-- | PARENT IS A SHIFT: @parentCode (morton k x y) = morton (k-1) (x÷2) (y÷2)@ — coarsening is a
-- 2-bit right shift, the memory realization of the ring quotient by @π²@.
lawParentIsShift :: Int -> Int -> Int -> Bool
lawParentIsShift k x y =
  let kk = max 1 (abs k `mod` 6)
      side = 2 ^ kk
      (xx, yy) = (x `mod` side, y `mod` side)
  in parentCode (morton kk xx yy) == morton (kk - 1) (xx `div` 2) (yy `div` 2)

-- | FIBER CONTIGUITY (the SIMT coalescing guarantee): the four geometric children of a parent
-- occupy the four contiguous codes @{4m … 4m+3}@. The warp's 2×2 pool is one coalesced load.
lawFiberContiguous :: Int -> Int -> Int -> Bool
lawFiberContiguous k x y =
  let kk = max 1 (abs k `mod` 6)
      side = 2 ^ (kk - 1)
      (px, py) = (x `mod` side, y `mod` side)
      m = morton (kk - 1) px py
  in sort [ morton kk (2 * px + dx) (2 * py + dy) | dx <- [0, 1], dy <- [0, 1] ]
       == childrenCodes m

-- | THE SIMT/GEOMETRY UNIFICATION: reducing a Morton buffer by contiguous memory quads equals
-- the geometric 2×2 spatial pool, cell for cell. The GPU never computes coordinates — the number
-- theory guarantees the flat, coalesced reduction is spatially correct.
lawSimtEqualsGeometric :: Int -> [Integer] -> Bool
lawSimtEqualsGeometric k buf
  | k < 1 || length buf /= 4 ^ k = True   -- vacuous unless a well-formed rung buffer
  | otherwise = simtQuadReduce buf == geometricPool k buf

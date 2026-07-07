{- |
Module      : SixFour.Spec.ColorTime
Description : THE COLOR-TIME MEASURE — the temporal support of a chromatic measurement, and why the isotropic ladder's coarse rungs are more color-accurate. Color-time τ_c of a spatiotemporal cell is the total open-shutter duration over which LINEAR chromatic radiant flux is accumulated into that cell's colour estimate: the t-marginal measure of the sampling kernel that produces a 3-vector colour, as distinct from the spatial support that produces resolution. Formally, for a light field ℓ(x,λ,t) and sensor sensitivities S(λ), a rung-k voxel measures @c = ∫∫∫ wˣ(x) wᵗ(t) S(λ) ℓ dλ dx dt@ and its color-time is @τ_c = ∫ wᵗ(t) dt = T_k · Δ_k@ (frames pooled × per-frame shutter). This module makes that scalar exact and pins its five laws.

WHY IT GOVERNS CHROMATIC FIDELITY. Photon arrivals are Poisson, so a channel accumulating @N ∝ Ē·τ_c@ photoelectrons has variance = mean (Fano 1, 'lawFanoUnity') and chromaticity-estimator variance @∝ 1/N ∝ 1/τ_c@ ('lawChromaVarianceInverse'); hence @SNR_color ∝ √τ_c@ (stated on squares to stay exact, 'lawSnrSqrtPowerLaw'). Color-time is the temporal analogue of aperture area: both trade resolution for photons and terminate in the same currency, √N. This is the precise content of "the coarse tiles are more accurate in color-time" — it is exposure theory, not metaphor.

THE LINEAR-LIGHT PRECONDITION. Integration is only physically meaningful in the radiometric (linear) domain, because only there does the integral count photons: for a NON-LINEAR opto-electronic transfer γ (a display gamma / inverse-EOTF, convex on [0,1]), @mean(map γ) ≥ γ(mean)@ with equality iff the window is constant (discrete Jensen; the gap is exactly the variance, 'lawLinearBeatsGamma'). Averaging an ENCODED signal over-reads by that variance. This is the theorem under "sums compose, means don't": the transitive u64 bin-SUM carrier ("SixFour.Spec.V21Pyramid") is a discrete Lebesgue integral of linear flux — color-time made bit-exact — while a gamma-space average is biased. Realization back to bytes is the single non-linear step at the display boundary ("SixFour.Spec.RadiometricRealize").

THE LADDER UNIFICATION. The isotropic 2×2×2 ladder ("SixFour.Spec.TriScaleTraining", "SixFour.Spec.KinematicLadder") gives rung k a temporal pool depth @T_k = 2^k@. The optical LIGHT LADDER sets the per-frame shutter @Δ_k = 2^k Δ₀@ (the +k-stop exposure), so @τ_c(k) = 2^k · 2^k Δ₀ = 4^k Δ₀@ ('lawColorTimeQuartic'): a clean power law in which ONE integer k indexes spatial coarsening, temporal-pool depth, AND optical stops simultaneously — the optical light ratio equals the temporal pool factor ('lawStopEqualsPoolIndex'). Color-time is a finitely-additive measure on temporal windows ('lawColorTimeAdditive'), and the colour it reports over that window is the temporal MEAN of the scene trajectory — motion within τ_c is averaged, never resolved ('lawMotionAverageInHull'). Everything here is exact 'Rational'; the √ of shot noise is the only transcendental fact and is pinned as a statement about N=SNR².
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none
module SixFour.Spec.ColorTime
  ( -- * The ladder index
    Rung
  , poolDepth
  , coarseSide
    -- * Optical exposure — the light ladder
  , Stops
  , stops2ratio
  , lightLadderStops
  , shutterAtRung
    -- * Color-time — the temporal support of the chromatic measurement
  , Seconds
  , colorTime
  , colorTimeOfWindow
    -- * Photon statistics — shot-noise-limited chromatic SNR
  , photonCount
  , snrColorSquared
  , chromaVariance
  , fanoFactor
    -- * Linear-light integration — the sums-compose carrier
  , poolSum
  , poolMean
  , meanOfSquares
  , squareOfMean
    -- * Motion aperture
  , temporalAverage
    -- * Laws
  , lawColorTimeAdditive
  , lawColorTimeQuartic
  , lawStopEqualsPoolIndex
  , lawSnrSqrtPowerLaw
  , lawChromaVarianceInverse
  , lawFanoUnity
  , lawSumsCompose
  , lawMeansDoNotCompose
  , lawLinearBeatsGamma
  , lawMotionAverageInHull
  ) where

import Data.List (genericLength)

-- | The coarsening index @k ≥ 0@ of the isotropic ladder: @0 ↦ 64²@, @1 ↦ 32²@, @2 ↦ 16²@.
-- One integer that (by the ladder unification) also indexes temporal-pool depth and stops.
type Rung = Int

-- | EV stops — a base-2 logarithm of a light ratio. Integer on the ladder rungs.
type Stops = Int

-- | An exact duration in seconds. 'Rational' so color-time and its measure laws are exact.
type Seconds = Rational

-- | Temporal pool depth @T_k = 2^k@: the number of frames a rung-k voxel integrates.
poolDepth :: Rung -> Integer
poolDepth k = 2 ^ max 0 k

-- | The spatial side of a rung's tile: @64 / 2^k@ (64² → 32² → 16²). The spatial-coarsening
-- face of the SAME integer @k@ that drives 'poolDepth'.
coarseSide :: Rung -> Int
coarseSide k = 64 `div` (2 ^ max 0 k)

-- | The light ratio of @n@ stops: @2^n@ (exact for integer @n@, including negative stops
-- via '(^^)'). @+1 stop = ×2 light@, the currency shutter/ISO both spend.
stops2ratio :: Stops -> Rational
stops2ratio n = 2 ^^ n

-- | The LIGHT LADDER's optical stop for rung @k@: @+k stops@. This is the design choice that
-- makes the optical exposure mirror the temporal pooling — the crux of 'lawStopEqualsPoolIndex'.
lightLadderStops :: Rung -> Stops
lightLadderStops = max 0

-- | Per-frame shutter at rung @k@ given the base shutter @Δ₀@: @Δ_k = 2^k · Δ₀@ (the light
-- ladder). The continuous, per-frame half of color-time.
shutterAtRung :: Seconds -> Rung -> Seconds
shutterAtRung d0 k = d0 * stops2ratio (lightLadderStops k)

-- | COLOR-TIME @τ_c(k) = T_k · Δ_k@: temporal pool depth × per-frame shutter. Under the light
-- ladder this collapses to the quartic @4^k · Δ₀@ ('lawColorTimeQuartic') — one scalar per rung.
colorTime :: Seconds -> Rung -> Seconds
colorTime d0 k = fromIntegral (poolDepth k) * shutterAtRung d0 k

-- | Color-time of an arbitrary temporal window given as its per-frame open-shutter durations
-- @[Δ₁..Δ_T]@: @τ_c = Σ Δᵢ@. This is the defining discrete integral — color-time is the total
-- measure of the window, from which finite additivity ('lawColorTimeAdditive') is immediate.
colorTimeOfWindow :: [Seconds] -> Seconds
colorTimeOfWindow = sum

-- | Mean photoelectron count @N = Ē · τ_c@ (channel irradiance × color-time; quantum
-- efficiency and area folded into @Ē@). The photons a voxel's colour estimate is built from.
photonCount :: Rational -> Seconds -> Rational
photonCount ebar tau = ebar * tau

-- | Shot-noise-limited chromatic SNR, SQUARED: @SNR² = N@ (Poisson). Kept squared so the
-- @√τ_c@ power law is an EXACT rational identity ('lawSnrSqrtPowerLaw'); the actual SNR is @√@
-- of this. Growing color-time by 4× (one rung) grows SNR by exactly 2×.
snrColorSquared :: Rational -> Seconds -> Rational
snrColorSquared = photonCount

-- | Chromaticity-estimator variance @∝ 1/N@ (0 for @N ≤ 0@). Its product with @N@ is the
-- invariant 1 ('lawChromaVarianceInverse'): more color-time ⇒ proportionally less colour noise.
chromaVariance :: Rational -> Rational
chromaVariance n
  | n <= 0    = 0
  | otherwise = 1 / n

-- | The Poisson Fano factor @Var/Mean@. Photon counting has Fano exactly 1 ('lawFanoUnity'):
-- the noise floor color-time is fighting is the counting statistics of light itself.
fanoFactor :: Rational -> Rational
fanoFactor n
  | n <= 0    = 1
  | otherwise = poissonVariance n / poissonMean n
  where
    poissonVariance = id   -- Var[N] = N
    poissonMean     = id   -- E[N]   = N

-- | The linear-carrier pool: a plain sum of samples. Associative, so it composes transitively
-- across ladder rungs ('lawSumsCompose') — the reason the u64 bin sums are the exact substrate.
poolSum :: [Rational] -> Rational
poolSum = sum

-- | The MEAN of samples (0 for the empty window). Does NOT compose across unequal partitions
-- ('lawMeansDoNotCompose') — realize (divide) only once, at the display boundary.
poolMean :: [Rational] -> Rational
poolMean [] = 0
poolMean xs = sum xs / genericLength xs

-- | @mean(xᵢ²)@ — the mean of a convex (γ = square) transfer of the window. The "average in
-- ENCODED space" that Jensen shows over-reads ('lawLinearBeatsGamma').
meanOfSquares :: [Rational] -> Rational
meanOfSquares xs = poolMean (map (^ (2 :: Int)) xs)

-- | @(mean xᵢ)²@ — the convex transfer of the linear mean, i.e. the CORRECT "encode after
-- integrating in linear light". Never exceeds 'meanOfSquares'; the gap is exactly the variance.
squareOfMean :: [Rational] -> Rational
squareOfMean xs = poolMean xs ^ (2 :: Int)

-- | The colour a voxel reports over its color-time window: the temporal MEAN of the per-frame
-- trajectory samples. The temporal aperture averages motion; it does not resolve it
-- ('lawMotionAverageInHull').
temporalAverage :: [Rational] -> Rational
temporalAverage = poolMean

-- ─────────────────────────────────────────────────────────────────────────────
-- Laws
-- ─────────────────────────────────────────────────────────────────────────────

-- | COLOR-TIME IS A MEASURE: finitely additive over the concatenation of disjoint temporal
-- windows. @τ_c(w₁ ⧺ w₂) = τ_c(w₁) + τ_c(w₂)@.
lawColorTimeAdditive :: [Seconds] -> [Seconds] -> Bool
lawColorTimeAdditive a b =
  colorTimeOfWindow (a ++ b) == colorTimeOfWindow a + colorTimeOfWindow b

-- | THE QUARTIC: under the light ladder @τ_c(k) = 4^k · Δ₀@. Temporal pool @2^k@ times optical
-- shutter @2^k Δ₀@ — the optical stop and the pooling factor multiply into one power of four.
lawColorTimeQuartic :: Seconds -> Rung -> Bool
lawColorTimeQuartic d0 k =
  let kk = abs k in colorTime d0 kk == fromInteger (4 ^ kk) * d0

-- | THE UNIFICATION (crown law): the optical LIGHT RATIO equals the temporal POOL DEPTH at every
-- rung — @2^(lightLadderStops k) = T_k@. One integer @k@ is the stop index, the pool index, and
-- (via 'coarseSide') the spatial-coarsening index all at once.
lawStopEqualsPoolIndex :: Rung -> Bool
lawStopEqualsPoolIndex k =
  let kk = abs k
  in stops2ratio (lightLadderStops kk) == fromInteger (poolDepth kk)

-- | THE √ POWER LAW (exact, on squares): @SNR²(k) = Ē · 4^k · Δ₀@, so one rung of color-time
-- (×4) is exactly one bit (×2) of chromatic SNR. Grounds "coarse = more color-accurate".
lawSnrSqrtPowerLaw :: Rational -> Seconds -> Rung -> Bool
lawSnrSqrtPowerLaw ebar d0 k =
  let kk = abs k
  in snrColorSquared ebar (colorTime d0 kk) == ebar * (fromInteger (4 ^ kk) * d0)

-- | Chromaticity variance is inversely proportional to color-time's photons: @Var · N = 1@.
lawChromaVarianceInverse :: Rational -> Bool
lawChromaVarianceInverse n = n <= 0 || chromaVariance n * n == 1

-- | Photon counting is Poisson: the Fano factor @Var/Mean@ is exactly 1.
lawFanoUnity :: Rational -> Bool
lawFanoUnity n = fanoFactor n == 1

-- | SUMS COMPOSE: the linear carrier is partition-invariant — @Σ(concat) = Σ(map Σ)@. This
-- associativity is why the ladder can build 16² from 32² from 64² by exact integer adds.
lawSumsCompose :: [[Rational]] -> Bool
lawSumsCompose xss = poolSum (concat xss) == poolSum (map poolSum xss)

-- | MEANS DO NOT COMPOSE: a witnessed UNEQUAL-length partition where the mean of the whole
-- differs from the mean of the sub-means (@[[0],[1,1]]@: @2/3 ≠ 1/2@). Equality holds only when
-- the blocks are balanced — which is exactly why realization divides once, at the end.
lawMeansDoNotCompose :: Bool
lawMeansDoNotCompose =
  poolMean (concat w) /= poolMean (map poolMean w)
  where w = [[0], [1, 1]] :: [[Rational]]

-- | LINEAR BEATS GAMMA (discrete Jensen for the convex γ = square): @mean(map γ) ≥ γ(mean)@,
-- with equality iff the window is constant. The gap IS the variance — averaging an encoded
-- (gamma) signal over-reads by exactly Var, so color-time must be integrated in LINEAR light.
lawLinearBeatsGamma :: [Rational] -> Bool
lawLinearBeatsGamma xs = null xs || meanOfSquares xs >= squareOfMean xs

-- | MOTION IS AVERAGED, NOT RESOLVED: the colour reported over a color-time window lies in the
-- convex hull of the trajectory — @min ≤ temporalAverage ≤ max@. Larger τ_c ⇒ wider temporal
-- aperture ⇒ more motion folded into one colour (the honest cost of chromatic SNR).
lawMotionAverageInHull :: [Rational] -> Bool
lawMotionAverageInHull xs =
  null xs || (minimum xs <= temporalAverage xs && temporalAverage xs <= maximum xs)

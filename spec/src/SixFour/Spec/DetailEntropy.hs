{- |
Module      : SixFour.Spec.DetailEntropy
Description : The integer-coefficient histogram Shannon entropy over octant 'Detail' bands — the "bits = compressible surplus" primitive. A flat (well-predicted) band costs ~0 bits; a skewed band costs strictly fewer bits than a uniform one. The missing Tier-0 estimator that makes adaptive rung deltas a MEASURED bit saving, not a dimension count.

The efficiency story rests on one fact the spec could not previously compute:
the entropy of the reversible Haar/octant DETAIL bands. "SixFour.Spec.OctreeCell"
@liftOct@ is the whitening operator (detail = data − prediction) and
"SixFour.Spec.CarrierL" @lawSearchIsZeroOnConstant@ proves a flat octant has ZERO
detail — so the entropy of the detail coefficients IS the compressible surplus, the
spendable bit budget. Before this module the only entropy in the spec was
"SixFour.Spec.Diversity" @gaussianColorEntropy@ (a differential entropy over OKLab
Gaussians); there was NO discrete histogram entropy over the integer 'Detail' tuples,
so "bits = Σ H(band)" was not expressible and "rungs accelerate/decelerate in deltas"
could only be an EXPRESSIVITY claim, never a measured saving.

== What it computes

@shannonBits@ is the empirical Shannon entropy (in BITS) of a multiset of integer
coefficients: @H = −Σ p·log₂ p@ over the histogram. The detail bands are read
PER-BAND ("SixFour.Spec.DetailEntropy" 'detailColumn' j = the j-th of the seven octant
coefficients across a list of details), because pooling the seven bands into one
histogram is a DIFFERENT (and wrong) number — 'lawPerBandDiffersFromPooled' has teeth
against that shortcut. @detailEntropyBits@ = the per-band coded-bit budget, @Σⱼ
|bandⱼ|·H(bandⱼ)@.

== Operational content (not numerology)

The link "a good predictor makes the residual compressible" is made falsifiable by
'lawSkewedStrictlyBelowUniform': a SKEWED coefficient distribution (the signature of a
band that mostly predicted correctly, i.e. mostly the same value) has entropy STRICTLY
below the uniform maximum @log₂ K@. An estimator that ignored frequencies (returned
@log₂(distinct)@ regardless of skew) would FAIL that law — that is the tooth that
separates a real entropy from a distinct-count fake.

Additive: a new leaf primitive (no module imports it yet). GHC-boot (@containers@).
The histogram keys/counts are integers on the Q16 floor; entropy is a Mac-side
@Double@ used only for bit-budget DECISIONS (a coding mode, like
"SixFour.Spec.Entropy" @scopeVerdict@), never on the bit-exact device path.
-}
-- COMPARTMENT: ZIG-FLOOR | tag:DeviceTag
module SixFour.Spec.DetailEntropy
  ( -- * Histogram + entropy of an integer coefficient multiset
    histogram
  , alphabetSize
  , shannonBits
  , codedBits
    -- * Per-band reading of octant detail
  , detailColumn
  , detailBands7
  , detailEntropyBits
  , pooledCoeffs
    -- * Laws (QuickCheck'd in @Properties.DetailEntropy@)
  , lawEntropyNonNegative
  , lawEntropyZeroIffSingleSymbol
  , lawEntropyMaxAtUniform
  , lawEntropyUpperBound
  , lawSkewedStrictlyBelowUniform
  , lawConstantDetailZeroBits
  , lawPerBandDiffersFromPooled
  ) where

import           Data.List       (foldl')
import qualified Data.Map.Strict as Map

import SixFour.Spec.OctreeCell (Detail)

-- ---------------------------------------------------------------------------
-- Histogram + entropy
-- ---------------------------------------------------------------------------

-- | The integer histogram (value → count) of a coefficient multiset.
histogram :: [Int] -> Map.Map Int Int
histogram = foldl' (\m x -> Map.insertWith (+) x 1 m) Map.empty

-- | The number of DISTINCT coefficients (the alphabet size @K@). @0@ on the empty
-- multiset.
alphabetSize :: [Int] -> Int
alphabetSize = Map.size . histogram

-- | The empirical Shannon entropy in BITS of a coefficient multiset:
-- @H = −Σ (cᵢ/n)·log₂(cᵢ/n)@ over the histogram counts. @0@ for the empty or the
-- single-symbol multiset (a delta distribution carries no information).
shannonBits :: [Int] -> Double
shannonBits xs
  | n == 0    = 0
  | otherwise = negate (sum [ p c * logBase 2 (p c) | c <- Map.elems h, c > 0 ])
  where
    h   = histogram xs
    n   = sum (Map.elems h)
    p c = fromIntegral c / fromIntegral n

-- | The total coded-bit budget of a band under its OWN empirical distribution:
-- @|band|·H(band)@ — the number of bits an ideal entropy coder spends on the band.
codedBits :: [Int] -> Double
codedBits xs = fromIntegral (length xs) * shannonBits xs

-- ---------------------------------------------------------------------------
-- Per-band reading of octant detail
-- ---------------------------------------------------------------------------

-- | The @j@-th of the seven octant detail coefficients across a list of details
-- (the @j@-th "band" as a coefficient column). Out-of-range @j@ yields @[]@.
detailColumn :: Int -> [Detail] -> [Int]
detailColumn j ds = [ pick d | d <- ds ]
  where
    pick (a, b, c, e, f, g, h) = case j of
      0 -> a; 1 -> b; 2 -> c; 3 -> e; 4 -> f; 5 -> g; 6 -> h
      _ -> 0

-- | All seven detail bands as coefficient columns.
detailBands7 :: [Detail] -> [[Int]]
detailBands7 ds = [ detailColumn j ds | j <- [0 .. 6] ]

-- | The per-band coded-bit budget of a detail list: @Σⱼ |bandⱼ|·H(bandⱼ)@. Reading
-- per-band (not pooled) is the point — see 'lawPerBandDiffersFromPooled'.
detailEntropyBits :: [Detail] -> Double
detailEntropyBits ds = sum [ codedBits b | b <- detailBands7 ds ]

-- | The WRONG pooling: all seven bands flattened into one histogram. Exists only so
-- 'lawPerBandDiffersFromPooled' can reject treating the detail as one band.
pooledCoeffs :: [Detail] -> [Int]
pooledCoeffs ds = concat (detailBands7 ds)

-- ============================================================================
-- Laws (predicates; QuickCheck'd in Properties.DetailEntropy)
-- ============================================================================

-- | Entropy is non-negative. Teeth: rejects a sign-flipped or mis-based formula that
-- can go negative.
lawEntropyNonNegative :: [Int] -> Bool
lawEntropyNonNegative xs = shannonBits xs >= -1e-9

-- | Entropy is zero IFF the multiset has at most one distinct symbol (a delta
-- distribution). Teeth: rejects an estimator that returns @> 0@ for a constant band
-- (the @zero-bits@ floor a flat/well-predicted octant must hit) OR @0@ for a genuinely
-- varied band (which would hide all compressible surplus).
lawEntropyZeroIffSingleSymbol :: [Int] -> Bool
lawEntropyZeroIffSingleSymbol xs =
  (alphabetSize xs <= 1) == (shannonBits xs < 1e-9)

-- | Entropy is MAXIMISED at the uniform distribution: @n@ DISTINCT equally-frequent
-- symbols carry exactly @log₂ n@ bits. Teeth: rejects a wrong logarithm base or a
-- broken normalisation (both miss @log₂ n@).
lawEntropyMaxAtUniform :: [Int] -> Bool
lawEntropyMaxAtUniform raw =
  let xs = distinctList raw           -- each symbol exactly once ⇒ uniform
      n  = length xs
  in n == 0 || abs (shannonBits xs - logBase 2 (fromIntegral n)) < 1e-9

-- | Entropy never exceeds the max-entropy bound @log₂ K@ (K = alphabet size). Teeth:
-- rejects an estimator that overshoots the information-theoretic ceiling.
lawEntropyUpperBound :: [Int] -> Bool
lawEntropyUpperBound xs =
  let k = alphabetSize xs
  in k == 0 || shannonBits xs <= logBase 2 (fromIntegral k) + 1e-9

-- | THE operational compression law: a SKEWED distribution costs STRICTLY fewer bits
-- than the uniform maximum over the same alphabet. We build a skew explicitly (one
-- dominant symbol repeated, plus the rest once each) over an alphabet of @≥ 2@, and
-- assert @H < log₂ K@ by a real margin. Teeth: rejects a frequency-IGNORING estimator
-- that returns @log₂(distinct)@ regardless of skew — exactly the "distinct-count fake"
-- that would make "good prediction ⇒ cheap residual" vacuous.
lawSkewedStrictlyBelowUniform :: [Int] -> Bool
lawSkewedStrictlyBelowUniform raw =
  case distinctList raw of
    alphabet@(dom : rest)
      | length alphabet >= 2 ->
          let k      = length alphabet
              skewed = replicate (k + 2) dom ++ rest   -- dom dominates
          in shannonBits skewed < logBase 2 (fromIntegral k) - 1e-6
    _ -> True

-- | A list of IDENTICAL detail tuples has zero coded-bit budget: every band is
-- constant, so @detailEntropyBits == 0@. Teeth: rejects an estimator that does not
-- bottom out at the flat-residual floor (e.g. one that counts dimensions instead of
-- entropy would report @7·n·log₂1 = 0@ only by luck; a count-of-distinct fake would
-- report nonzero). Non-vacuous: requires a non-empty list of a genuine off-floor tuple.
lawConstantDetailZeroBits :: Detail -> Int -> Bool
lawConstantDetailZeroBits d nRaw =
  let n  = 1 + (abs nRaw `mod` 8)            -- ≥ 1 identical copies
      ds = replicate n d
  in detailEntropyBits ds < 1e-9

-- | Reading detail PER-BAND is not the same as pooling all seven bands into one
-- histogram: there is a witness where @detailEntropyBits@ (per-band sum) differs from
-- the pooled @codedBits (pooledCoeffs ds)@. Teeth: rejects the lazy impl that pools
-- the seven coefficients into one band (the research's "per-band, not concatenated"
-- requirement). The witness has bands with DIFFERENT per-band distributions so pooling
-- genuinely changes the count.
lawPerBandDiffersFromPooled :: Bool
lawPerBandDiffersFromPooled =
  -- two details: band 0 is constant (0 bits per-band), band 1 varies; pooling band 0's
  -- zeros with band 1's spread inflates the pooled count above the per-band sum.
  let ds = [ (0, 10, 0, 0, 0, 0, 0)
           , (0, 20, 0, 0, 0, 0, 0) ]
  in abs (detailEntropyBits ds - codedBits (pooledCoeffs ds)) > 1e-6

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- | The distinct values of a list, order-stable (each symbol once) — the uniform
-- alphabet used by the max-entropy laws.
distinctList :: [Int] -> [Int]
distinctList = Map.keys . histogram

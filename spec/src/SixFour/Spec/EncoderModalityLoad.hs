{- |
Module      : SixFour.Spec.EncoderModalityLoad
Description : The three per-modality information LOADS on ONE non-negative bit axis — so the encoder channel budget can be EARNED (allocated by entropy share), not chosen. The load-bearing fix: the palette load is the RIDGED coding rate (provably ≥0), NOT the raw differential entropy (which goes NEGATIVE on a tight palette and would invert a softmax).

To EARN the encoder widths (next module), the three modality entropies must be COMMENSURABLE
— same unit (bits), all non-negative — before any softmax share. They are not, raw:

  * M1 INDEX (categorical) — DISCRETE Shannon ("SixFour.Spec.DetailEntropy" @codedBits@): bits, ≥0. OK.
  * M2 PALETTE (continuous OKLab) — the DIFFERENTIAL entropy ½ln((2πe)³|Σ|)
    ("SixFour.Spec.Diversity" @gaussianColorEntropy@) is in NATS and **goes NEGATIVE** when the
    palette is tighter than the quantizer (verified: a 2-colour palette = −9.559 nats). A softmax
    over a negative "entropy" inverts the allocation. THIS is the un-earned joint the workflow found.
  * M3 PERCEPTUAL (residual) — CONDITIONAL detail bits ("SixFour.Spec.DetailEntropy" @codedBits@
    of the held remainder): bits, ≥0. OK.

THE FIX = the RIDGED colour coding rate 'ridgedColorRateBits':
@R(Σ) = ½ log₂ det(I + Σ/σ₀²) = ½ log₂ ( det(Σ + σ₀²I) / σ₀⁶ )@ — the coding bits BEYOND the
quantizer LSB floor σ₀². It is ≥0 for ANY PSD Σ (each eigenvalue factor @λᵢ+σ₀² ≥ σ₀²@ so the
ratio ≥1), in bits, and UNBOUNDED above (no [0,3] cap), so it sits on the same axis as the other
two. Computed from Σ's invariants alone — no eigen-decomposition — via the characteristic
polynomial @det(Σ+σ₀²I) = σ₀⁶ + e₁σ₀⁴ + e₂σ₀² + e₃@ with @e₁=tr Σ@, @e₂=½(tr²−‖Σ‖²_F)@, @e₃=det Σ@.

  * 'lawPaletteLoadNonNegative' — the ridged rate is ≥0 on every palette (tight / spread / degenerate
    / greyscale).
  * 'lawRidgedBeatsNaiveOnTightPalette' (TEETH) — on the tight palette the NAIVE differential is
    NEGATIVE (−9.559) while the ridged rate is ≥0, and the rate is monotone (more colour ⇒ more rate).
    This is exactly why the ridge is necessary, not a wrapper.
  * 'lawLoadsAreNonNegativeBits' — all three modality loads are non-negative bit quantities, hence
    commensurable for the entropy-share allocation ("SixFour.Spec.EncoderWidthAlloc", next).

GHC-boot-only; re-pins nothing. Laws QuickCheck'd in "Properties.EncoderModalityLoad".
-}
-- COMPARTMENT: MLX-MODEL | tag:MacTag
module SixFour.Spec.EncoderModalityLoad
  ( -- * The reference quantizer + the ridged colour rate
    referenceVar
  , ridgedColorRateBits
    -- * The three per-modality loads (one non-negative bit axis)
  , indexLoadBits
  , paletteLoadBits
  , perceptualLoadBits
  , modalityLoads
    -- * Laws (QuickCheck'd in @Properties.EncoderModalityLoad@)
  , lawPaletteLoadNonNegative
  , lawRidgedBeatsNaiveOnTightPalette
  , lawLoadsAreNonNegativeBits
  ) where

import SixFour.Spec.Color       (OKLab(..))
import SixFour.Spec.Diversity   (weightedCovariance, covTrace, covDeterminant, covFrobeniusSq, gaussianColorEntropy)
import SixFour.Spec.DetailEntropy (codedBits)

-- | The reference quantizer variance σ₀² (the per-axis LSB floor below which colours are
-- indistinguishable). The ridged rate is non-negative for ANY @σ₀² > 0@; this is the
-- calibration constant (here a unit reference in OKLab Q16 units).
referenceVar :: Double
referenceVar = 1.0

-- | The RIDGED colour coding rate in BITS: @½ log₂ ( det(Σ + σ₀²I) / σ₀⁶ )@. Provably ≥0
-- (the ratio is @∏(λᵢ+σ₀²)/σ₀⁶ ≥ 1@), in bits, unbounded above. Computed from Σ's invariants
-- via @det(Σ+σ₀²I) = σ₀⁶ + e₁σ₀⁴ + e₂σ₀² + e₃@ — no eigen-decomposition.
ridgedColorRateBits :: Double -> [(OKLab, Double)] -> Double
ridgedColorRateBits s0 cands
  | null cands = 0
  | otherwise =
      let cov  = weightedCovariance cands
          e1   = covTrace cov                       -- Σλ
          e3   = covDeterminant cov                 -- Πλ
          e2   = 0.5 * (e1 * e1 - covFrobeniusSq cov) -- Σ_{i<j} λᵢλⱼ ≥ 0 for PSD
          s2   = s0 * s0
          rdet = s2 * s0 + e1 * s2 + e2 * s0 + e3   -- det(Σ + σ₀²I) = ∏(λᵢ+σ₀²)
      in 0.5 * logBase 2 (rdet / (s2 * s0))

-- | M1 INDEX load: discrete Shannon coded bits of the index detail band (bits, ≥0).
indexLoadBits :: [Int] -> Double
indexLoadBits = codedBits

-- | M2 PALETTE load: the ridged colour coding rate (bits, ≥0) — NOT the raw differential entropy.
paletteLoadBits :: [(OKLab, Double)] -> Double
paletteLoadBits = ridgedColorRateBits referenceVar

-- | M3 PERCEPTUAL load: discrete Shannon coded bits of the HELD remainder detail band — the
-- conditional information beyond the surfaced coarse (bits, ≥0).
perceptualLoadBits :: [Int] -> Double
perceptualLoadBits = codedBits

-- | The three modality loads on one non-negative bit axis: @(index, palette, perceptual)@.
modalityLoads :: [Int] -> [(OKLab, Double)] -> [Int] -> (Double, Double, Double)
modalityLoads idxBand palette heldBand =
  (indexLoadBits idxBand, paletteLoadBits palette, perceptualLoadBits heldBand)

-- =============================================================================
-- Witnesses
-- =============================================================================

-- | A near-degenerate palette: two colours one LSB apart on L — tighter than the quantizer, the
-- case where the NAIVE differential entropy goes negative.
tightPalette :: [(OKLab, Double)]
tightPalette = [(OKLab 0 0 0, 1), (OKLab 1 0 0, 1)]

-- | A full-gamut palette spread across all three OKLab axes.
spreadPalette :: [(OKLab, Double)]
spreadPalette = [(OKLab 0 0 0, 1), (OKLab 100 50 30, 1), (OKLab 40 80 20, 1)]

-- | A single repeated colour: zero covariance ⇒ the ridged rate is exactly 0.
degeneratePalette :: [(OKLab, Double)]
degeneratePalette = [(OKLab 7 7 7, 1), (OKLab 7 7 7, 1)]

-- | A greyscale palette (a=b=0): variance only on L.
greyscalePalette :: [(OKLab, Double)]
greyscalePalette = [(OKLab 0 0 0, 1), (OKLab 80 0 0, 1)]

-- =============================================================================
-- Laws (predicates; QuickCheck'd in Properties.EncoderModalityLoad)
-- =============================================================================

-- | The ridged palette load is NON-NEGATIVE on every palette — so it can enter the entropy-share
-- softmax without inverting it. (Tolerance @1e-9@ for float rounding of a provably-≥1 ratio.)
lawPaletteLoadNonNegative :: Bool
lawPaletteLoadNonNegative =
  all (\p -> paletteLoadBits p >= -1e-9)
      [tightPalette, spreadPalette, degeneratePalette, greyscalePalette]

-- | TEETH (why the ridge is necessary, not a wrapper): on the tight palette the NAIVE differential
-- entropy is NEGATIVE (≈ −9.559 nats) while the ridged rate is ≥0; and the rate is monotone
-- (the full-gamut palette earns strictly more bits than the tight one).
lawRidgedBeatsNaiveOnTightPalette :: Bool
lawRidgedBeatsNaiveOnTightPalette =
     gaussianColorEntropy (map fst tightPalette) (map snd tightPalette) < 0
  && paletteLoadBits tightPalette  >= -1e-9
  && paletteLoadBits spreadPalette >  paletteLoadBits tightPalette

-- | All three modality loads are non-negative bit quantities — hence COMMENSURABLE for the
-- entropy-share allocation of the fixed 512-channel waist (the @lawFuseIsMidpoint@ budget).
lawLoadsAreNonNegativeBits :: Bool
lawLoadsAreNonNegativeBits =
  let (i, p, c) = modalityLoads [0,1,1,2,0,1,3,0] spreadPalette [3,0,0,1,0,2]
  in i >= 0 && p >= -1e-9 && c >= 0

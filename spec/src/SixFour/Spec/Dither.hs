{- |
Module      : SixFour.Spec.Dither
Description : The binary (Bernoulli) distribution that realises a balanced pair.

Each pixel, over the @T@-frame loop, is a **Bernoulli(p)** process on one
'SixFour.Spec.PairTree' pair: it shows the anchor (0) or the partner (1). The eye
temporally averages, so the perceived colour is the convex blend
@(1−p)·anchor + p·partner@ — i.e. **p ∈ [0,1] is the continuous position on the
dither axis** between a pair. Over the loop the partner-count is @Binomial(T, p)@:

  * the **mean** @T·p@ is the colour (correctness),
  * the **variance** @T·p(1−p)@ is the flicker (the dirty-window effect; maximal at
    @p = 0.5@).

i.i.d. sampling hits the mean but with high variance. A **low-discrepancy ordering**
— the golden-ratio sequence @frac(n·φ)@ in time (or a tileable STBN3D mask in
space-time) — keeps the mean while driving the variance of the running average to
near zero. This module pins that contract with reference functions + laws; the
network never produces the binary stream directly, only the continuous @p@ field.
See @spec/NN_SPACE_NOTES.md@ §4.
-}
-- COMPARTMENT: METAL-GPU | tag:none | STRADDLER
module SixFour.Spec.Dither
  ( -- * Realising a pair
    ditheredColor
  , realize
  , temporalMean
    -- * The binomial mean/variance (the flicker budget)
  , binomialMean
  , binomialVariance
    -- * Low-discrepancy ordering
  , goldenThresholds
    -- * Laws (predicates; QuickCheck'd in Properties.Dither)
  , lawDitheredColorConvex
  , lawDitherMeanRecoversP
  , lawVarianceMaxAtHalf
  ) where

import SixFour.Spec.Color    (OKLab(..))
import SixFour.Spec.PairTree (phi)

-- | The perceived colour of a pair dithered at position @p@:
-- @(1−p)·anchor + p·partner@. @p=0@ ⇒ anchor, @p=1@ ⇒ partner.
ditheredColor :: Double -> OKLab -> OKLab -> OKLab
ditheredColor p (OKLab al aa ab) (OKLab pl pa pb) =
  OKLab (mix al pl) (mix aa pa) (mix ab pb)
  where mix x y = (1 - p) * x + p * y

-- | The binary draw against a threshold mask: show the partner iff @p > threshold@.
realize :: Double -> Double -> Bool
realize p threshold = p > threshold

-- | The fraction of frames showing the partner — the eye's temporal average.
temporalMean :: [Bool] -> Double
temporalMean bs = fromIntegral (length (filter id bs)) / fromIntegral (max 1 (length bs))

-- | Binomial mean @T·p@ — the realised colour position over @T@ frames.
binomialMean :: Int -> Double -> Double
binomialMean t p = fromIntegral t * p

-- | Binomial variance @T·p(1−p)@ — the flicker budget (the dirty-window effect).
binomialVariance :: Int -> Double -> Double
binomialVariance t p = fromIntegral t * p * (1 - p)

-- | The golden-ratio low-discrepancy threshold sequence @{ frac(n·φ) : n = 1..count }@.
-- Consecutive gaps oscillate 0.382/0.618; minimum toroidal spacing is constant —
-- the most-spread 1-D sequence, ideal for temporal dither ordering.
goldenThresholds :: Int -> [Double]
goldenThresholds count = [ frac (fromIntegral n * phi) | n <- [1 .. count] ]
  where frac x = x - fromIntegral (floor x :: Int)

-- | The dithered colour is a convex combination — every channel lies between the
-- anchor's and partner's, for any @p ∈ [0,1]@.
lawDitheredColorConvex :: Double -> OKLab -> OKLab -> Bool
lawDitheredColorConvex p a@(OKLab al aa ab) b@(OKLab bl ba bb) =
  p < 0 || p > 1 ||
  let OKLab rl ra rb = ditheredColor p a b
  in between al bl rl && between aa ba ra && between ab bb rb
  where between lo hi x = x >= min lo hi - 1e-9 && x <= max lo hi + 1e-9

-- | The mean over the golden-ordered binary stream recovers @p@ to within the
-- sequence's (low) discrepancy — so the binary distribution reproduces the colour.
lawDitherMeanRecoversP :: Double -> Int -> Double -> Bool
lawDitherMeanRecoversP tol n p =
  p < 0 || p > 1 ||
  abs (temporalMean (map (realize p) (goldenThresholds n)) - p) <= tol

-- | Flicker (binomial variance) is maximal at @p = 0.5@: the hardest mid-tones.
-- (A φ-positioned tone at 0.382/0.618 is therefore lower-flicker than 50/50.)
lawVarianceMaxAtHalf :: Int -> Double -> Bool
lawVarianceMaxAtHalf t p = binomialVariance t 0.5 + 1e-12 >= binomialVariance t p

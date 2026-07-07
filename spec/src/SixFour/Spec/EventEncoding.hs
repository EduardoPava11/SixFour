{- |
Module      : SixFour.Spec.EventEncoding
Description : THE CAPTURE AS AN ENCODED EVENT — a high-precision signal is written into the GIF89a's low-bit-depth frame stack by TEMPORAL (ordered) DITHER, which RAISES the per-frame entropy while the temporal integration ("SixFour.Spec.ColorTime") recovers the signal EXACTLY. The exact "entropy up, signal captured" theorem is Hermite's identity; its recovery precision is the same @1/T = 1/N@ that color-time and the ideal norm ("SixFour.Spec.GaussianLadder") deliver, now derived from coding theory. The process is deterministic given context, hence LEARNABLE: a model conditioned on (signal, frame-phase) has zero irreducible loss and can generate meaningful frames.

THE EVENT AND ITS CHANNEL. The GIF89a is a narrow channel: 8-bit palette indices, one code per pixel per frame. A capture carries far more than 8 bits of linear colour. Encode the true signal @s@ (in units of the coarse quantum) across @T@ frames by ordered dither: frame @i@ emits @xᵢ = ⌊s + i/T⌋@ — the quantised value with a deterministic sub-quantum offset swept over @[0,1)@. Each individual code is a coarse, LOSSY read of @s@.

ENTROPY UP. If @s@ is off the coarse grid (fractional part @f ∈ [1/T, 1)@) the frames are NOT constant: they take two adjacent codes @{⌊s⌋, ⌊s⌋+1}@ in the proportion set by @f@ ('lawEncodingRaisesEntropy'). The marginal per-frame entropy jumps from 0 (a single quantised value) to @H(f) > 0@. Encoding has ADDED entropy — it has spread the one signal into a stochastic-looking symbol stream. This is the temporal analogue of Floyd–Steinberg: dither in TIME.

SIGNAL CAPTURED (EXACTLY). Yet the sum of the frames is Hermite's identity @Σᵢ ⌊s + i/T⌋ = ⌊T·s⌋@ ('lawHermiteDither'), so the temporal mean — the color-time integration / the SIMT quad-reduce of "SixFour.Spec.GaussianLadder" — is @⌊T·s⌋ / T@, which recovers @s@ to a distortion @< 1/T@ ('lawDecodeRecoversSignal'). The decode lands on the refined @(1/T)@-grid ('lawDecodeOnFineGrid'): @T@ ordered-dither frames buy exactly @log₂ T@ extra bits of colour, so the ladder's @T = 2^k@ temporal pool adds @k@ bits ('lawLadderDitherBits'). This is rate–distortion made exact: rate = frames = entropy budget, distortion = @1/T@. The entropy the encoder injected is precisely the entropy color-time removes; the two are matched encoder/decoder.

LEARNABLE FROM CONTEXT. The encoder @(s, i) ↦ ⌊s + i/T⌋@ is a deterministic total function, so a predictor GIVEN the context (the signal estimate and the frame phase) has ZERO irreducible conditional entropy — the residual after context is pure, learnable structure, not noise. "Given enough context we can learn this process" is the statement that @H(xᵢ | s, i) = 0@; the model that captures it can then GENERATE meaningful GIF89a frames (sample the dither it learned), not merely reproduce them. Pure-spec; exact @Rational@ / @Integer@.
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none
module SixFour.Spec.EventEncoding
  ( -- * The encoder — temporal ordered dither
    ditherSweep
  , encodeFrame
  , encodeEvent
  , fracPart
    -- * The decoder — temporal integration (color-time)
  , decodeMean
  , hermiteSum
  , distinctCodes
    -- * Laws
  , lawHermiteDither
  , lawDecodeRecoversSignal
  , lawDecodeOnFineGrid
  , lawEncodingRaisesEntropy
  , lawLadderDitherBits
  ) where

import Data.List (nub)
import Data.Ratio ((%), denominator)

import SixFour.Spec.ColorTime (poolDepth)

-- | The ordered dither sweep for @T@ frames: the sub-quantum offsets @[0/T, 1/T, …, (T-1)/T]@
-- that tile @[0,1)@ uniformly. Deterministic (ordered), so recovery is bias-free to @1/T@.
ditherSweep :: Int -> [Rational]
ditherSweep t = [ fromIntegral i / fromIntegral t | i <- [0 .. t - 1] ]

-- | One encoded frame: the signal @s@ quantised (floor) after adding the @i@-th dither offset —
-- @xᵢ = ⌊s + i/T⌋@. A coarse, lossy read on its own.
encodeFrame :: Rational -> Int -> Int -> Integer
encodeFrame s t i = floor (s + fromIntegral i / fromIntegral t)

-- | The whole event encoded to @T@ frames: the GIF89a frame stack for signal @s@.
encodeEvent :: Rational -> Int -> [Integer]
encodeEvent s t = [ encodeFrame s t i | i <- [0 .. t - 1] ]

-- | Fractional part @s − ⌊s⌋ ∈ [0,1)@ — the sub-quantum residue the dither is spreading.
fracPart :: Rational -> Rational
fracPart s = s - fromInteger (floor s)

-- | The decoder: the temporal MEAN @(Σ xᵢ)/T@ — the color-time integration of the frames.
decodeMean :: [Integer] -> Int -> Rational
decodeMean cs t = sum cs % fromIntegral t

-- | Hermite's identity closed form @Σᵢ ⌊s + i/T⌋ = ⌊T·s⌋@: what the frame-sum MUST equal.
hermiteSum :: Rational -> Int -> Integer
hermiteSum s t = floor (fromIntegral t * s)

-- | The distinct codes appearing in a frame stack — its symbol alphabet (entropy support).
distinctCodes :: [Integer] -> [Integer]
distinctCodes = nub

-- ─────────────────────────────────────────────────────────────────────────────
-- Laws
-- ─────────────────────────────────────────────────────────────────────────────

-- | THE ENTROPY-UP-SIGNAL-CAPTURED THEOREM (Hermite's identity): the frame sum equals @⌊T·s⌋@.
-- The coarse, dithered frames — individually lossy — sum to the signal at @T×@ resolution.
lawHermiteDither :: Rational -> Int -> Bool
lawHermiteDither s t = t <= 0 || sum (encodeEvent s t) == hermiteSum s t

-- | RATE–DISTORTION: the decoded temporal mean recovers @s@ with distortion @0 ≤ d < 1/T@.
-- Rate = frames = entropy budget; distortion falls as the inverse rate.
lawDecodeRecoversSignal :: Rational -> Int -> Bool
lawDecodeRecoversSignal s t
  | t <= 0    = True
  | otherwise = let d = s - decodeMean (encodeEvent s t) t
                in d >= 0 && d * fromIntegral t < 1

-- | ADDED BITS: the decode lands on the refined @(1/T)@-grid (its denominator divides @T@),
-- so @T@ ordered-dither frames buy @log₂ T@ extra bits of colour precision.
lawDecodeOnFineGrid :: Rational -> Int -> Bool
lawDecodeOnFineGrid s t =
  t <= 0 || (fromIntegral t `mod` denominator (decodeMean (encodeEvent s t) t) == (0 :: Integer))

-- | ENCODING RAISES ENTROPY: for an off-grid signal (@f ≥ 1/T@) the frames use TWO codes, not
-- one — marginal per-frame entropy goes @0 → H(f) > 0@ — even as the sum (above) still captures
-- @s@. The injected entropy is exactly what the color-time decode removes.
lawEncodingRaisesEntropy :: Rational -> Int -> Bool
lawEncodingRaisesEntropy s t =
  t < 2
    || fracPart s < 1 % fromIntegral t
    || length (distinctCodes (encodeEvent s t)) == 2

-- | LADDER LINK: at rung @k@ the temporal pool depth is @T = 2^k@ ("SixFour.Spec.ColorTime"),
-- so ordered dither over those frames lands the decode on the @2^k@-grid — rung @k@ adds exactly
-- @k@ bits of colour. Coding rate, color-time, and the @2^k@ of the Gaussian ladder agree.
lawLadderDitherBits :: Rational -> Int -> Bool
lawLadderDitherBits s k =
  let t = fromInteger (poolDepth (abs k `mod` 9)) :: Int   -- 2^k dither frames (bounded for the check)
  in t <= 0 || (fromIntegral t `mod` denominator (decodeMean (encodeEvent s t) t) == (0 :: Integer))

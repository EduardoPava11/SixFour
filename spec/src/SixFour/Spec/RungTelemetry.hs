{- |
Module      : SixFour.Spec.RungTelemetry
Description : WHAT THE GRID SHOWS PER RUNG — the exact telemetry algebra of a ladder rung, for BOTH capture modes. Once the three rungs (64²\@20 Hz / 32²\@10 Hz / 16²\@5 Hz) become independent data signals ("SixFour.Spec.MultiScaleCapture"), the surface must report, per rung and AS IT ARRIVES: its exposure state, its arrival pulse, its statistical significance, and whether it is genuinely independent or has silently fallen back to derived pooling. This module makes each of those four quantities exact (Integer/Rational carriers, no floats) and pins the laws the widgets read.

ONE EXPOSURE VOCABULARY. A rung's effective EV has two producers: OPTICAL stops in independent mode
(the actual duration × ISO exposure product versus the fine-rung reference, an exact 'Rational' light
ratio) and POOLING-EQUIVALENT stops in derived mode (the ladder index @k@ itself — "SixFour.Spec.ColorTime"'s
@lawStopEqualsPoolIndex@ axis, where pooling @2^k@ frames buys exactly the light of @+k@ stops). The
crux is that these are the SAME vocabulary: on the light-ladder schedule (rung @k@ exposes @2^k · Δ₀@
at the reference gain) the optical light ratio equals the pooling-equivalent ratio at every rung —
one integer @k@ ('lawExposureVocabulariesAgreeOnLadder'). A widget can therefore label both modes in
stops without lying about either.

ARRIVAL. The rungs share one clock ("SixFour.Spec.WeaveOrder"): native intervals 5\/10\/20 cs, hence
exactly 64\/32\/16 pulses on the 320 cs burst window ('lawExpectedArrivalsPinned'). Health is decidable
from the interval list alone: the clean cadence has zero late and zero missing pulses
('lawCleanCadenceIsHealthy'), and a dropped pulse produces EXACTLY one over-long interval plus one
missing arrival while conserving the window span ('lawDroppedPulseIsDetectable') — so the arrival
widget needs no side channel, only intervals.

SIGNIFICANCE. A rung-@k@ voxel's sample volume in derived mode is @N(k) = 8^k · N₀@ — composed, not
invented: temporal pool depth @2^k@ ("SixFour.Spec.ColorTime".'SixFour.Spec.ColorTime.poolDepth') ×
spatial cell area @4^k@ ("SixFour.Spec.GaussianLadder".'SixFour.Spec.GaussianLadder.rungIdealNorm').
The three rungs are the @1 : 8 : 64@ lattice ('lawDerivedSignificanceLattice'); each rung buys ×8
samples = +3 bits of @N@ ('lawRungBuysThreeBits'). In independent mode @N@ is the ACTUAL owned sample
count ('independentSampleVolume' — frames owned × pixels, whatever the weave delivered), monotone
under new evidence ('lawIndependentCountsMonotone'). The meter shows @√N@; since squaring is monotone
on non-negatives, the @√N@ order IS the @N@ order ('lawSignificanceSqrtMonotone', stated on squares
like ColorTime's @lawSnrSqrtPowerLaw@ — exactness costs nothing).

INDEPENDENCE HEALTH. The fallback failure mode is silent: a "coarse" stream that is really the exact
pool of the fine stream looks plausible bin by bin. The detector is an exact integer co-movement
statistic: pool the finer stream to the coarser lattice ('poolTo', a block sum — pooling composes,
'lawPoolCompose'), take per-bin deltas ('binDeltas'), and count sign agreements ('comovement',
normalized by 'comovementRatio'). Derived pooling makes the two streams IDENTICAL, so the statistic
is MAXIMAL — ratio 1, fully determined — and stays maximal under any further SHARED pooling
('lawDerivedPoolingIsMaximal', the foil; 'lawDerivedStaysMaximalUnderSharedPool', the
scale-equivariance). Genuinely independent streams are bounded away: dead-time photons the fine read
never saw ("SixFour.Spec.MultiScaleCapture"'s @lawSlowMinusPoolIsDeadTime@ story) flip a delta's sign
and the statistic drops strictly below maximal ('lawIndependentNoiseBoundedAway' witness;
'lawDisagreementIsDetected' in general). @'comovementRatio' == 1@ is therefore the exact meaning of
the GRID's warning light: "this rung fell back to derived pooling". 'isDerivedPool' is the sharper
byte-exact signature (stream == exact pool) for stamping provenance into the capture record.
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none
module SixFour.Spec.RungTelemetry
  ( -- * Exposure state — one vocabulary for both modes
    MicroSeconds
  , Iso
  , exposureProduct
  , opticalLightRatio
  , poolingEquivalentStops
  , poolingEquivalentRatio
    -- * Arrival — the native cadences on the 320 cs window
  , expectedArrivals
  , cleanCadence
  , lateArrivals
  , missingArrivals
  , dropPulse
    -- * Significance — sample volume and the √N meter
  , derivedSampleVolume
  , independentSampleVolume
    -- * Independence health — the exact decorrelation statistic
  , Stream
  , poolTo
  , binDeltas
  , comovement
  , comovementRatio
  , fullyDetermined
  , isDerivedPool
    -- * Laws — exposure
  , lawExposureVocabulariesAgreeOnLadder
    -- * Laws — arrival
  , lawExpectedArrivalsPinned
  , lawCleanCadenceIsHealthy
  , lawDroppedPulseIsDetectable
    -- * Laws — significance
  , lawDerivedSignificanceLattice
  , lawRungBuysThreeBits
  , lawSignificanceSqrtMonotone
  , lawIndependentCountsMonotone
    -- * Laws — independence health
  , lawPoolCompose
  , lawDerivedPoolingIsMaximal
  , lawDerivedStaysMaximalUnderSharedPool
  , lawIndependentNoiseBoundedAway
  , lawDisagreementIsDetected
  ) where

import Data.Ratio ((%))

import SixFour.Spec.ColorTime
  ( Rung, Stops, lightLadderStops, poolDepth, stops2ratio )
import SixFour.Spec.GaussianLadder (rungIdealNorm)
import SixFour.Spec.WeaveOrder
  ( WeaveRung (..), delayCsOf, unitsOf, windowCs, windowUnits )

-- ─────────────────────────────────────────────────────────────────────────────
-- Exposure state
-- ─────────────────────────────────────────────────────────────────────────────

-- | An exact exposure duration in microseconds (the capture record's integer unit).
type MicroSeconds = Integer

-- | Sensor gain as an exact integer (ISO, in whole or milli units — only ratios matter here).
type Iso = Integer

-- | The photon-equivalent exposure product @duration × gain@ — the one scalar both shutter
-- time and ISO spend into ('SixFour.Spec.ColorTime' calls its log the stop axis). Negative
-- inputs clamp to 0 (no anti-photons).
exposureProduct :: MicroSeconds -> Iso -> Integer
exposureProduct dur iso = max 0 dur * max 0 iso

-- | INDEPENDENT-MODE exposure state: the rung's light ratio versus the fine reference,
-- @((dur, iso) rung) \/ ((dur, iso) fine)@ as an exact 'Rational'. 0 for a degenerate
-- (non-positive) reference. @+1 stop = ratio 2@.
opticalLightRatio :: (MicroSeconds, Iso) -> (MicroSeconds, Iso) -> Rational
opticalLightRatio (d, i) (d0, i0)
  | ref <= 0  = 0
  | otherwise = exposureProduct d i % ref
  where ref = exposureProduct d0 i0

-- | DERIVED-MODE exposure state: pooling @2^k@ frames is worth exactly @+k@ stops — the
-- ladder's 'lightLadderStops' (@= k@), i.e. "SixFour.Spec.ColorTime"'s one-integer axis.
poolingEquivalentStops :: Rung -> Stops
poolingEquivalentStops = lightLadderStops

-- | The derived-mode light RATIO: @2^('poolingEquivalentStops' k) = 2^k@, comparable
-- one-for-one with 'opticalLightRatio'.
poolingEquivalentRatio :: Rung -> Rational
poolingEquivalentRatio = stops2ratio . poolingEquivalentStops

-- ─────────────────────────────────────────────────────────────────────────────
-- Arrival
-- ─────────────────────────────────────────────────────────────────────────────

-- | Pulses a rung delivers on the 320 cs burst window: @'windowUnits' \/ 'unitsOf'@ —
-- 64 \/ 32 \/ 16 for W64 \/ W32 \/ W16 ('lawExpectedArrivalsPinned').
expectedArrivals :: WeaveRung -> Int
expectedArrivals r = windowUnits `div` unitsOf r

-- | The healthy interval list: 'expectedArrivals' pulses, each at the rung's native
-- interval 'delayCsOf' (5 \/ 10 \/ 20 cs). What the arrival widget expects to see.
cleanCadence :: WeaveRung -> [Int]
cleanCadence r = replicate (expectedArrivals r) (delayCsOf r)

-- | LATE pulses in an observed interval list: intervals strictly longer than the rung's
-- native interval. Zero on the clean cadence.
lateArrivals :: WeaveRung -> [Int] -> Int
lateArrivals r = length . filter (> delayCsOf r)

-- | MISSING pulses: how far the observed count falls short of 'expectedArrivals' (never
-- negative). Zero on the clean cadence.
missingArrivals :: WeaveRung -> [Int] -> Int
missingArrivals r intervals = max 0 (expectedArrivals r - length intervals)

-- | Drop the pulse after interval @j@ (index normalized into range): its interval merges
-- into the next — the exact signature of a dropped frame. Identity on lists too short to
-- merge.
dropPulse :: Int -> [Int] -> [Int]
dropPulse j intervals =
  case splitAt j' intervals of
    (pre, a : b : post) -> pre ++ (a + b) : post
    _                   -> intervals
  where j' = if length intervals < 2 then 0 else abs j `mod` (length intervals - 1)

-- ─────────────────────────────────────────────────────────────────────────────
-- Significance
-- ─────────────────────────────────────────────────────────────────────────────

-- | DERIVED-MODE sample volume of a rung-@k@ voxel: @N(k) = 'poolDepth' k · 'rungIdealNorm' k
-- · N₀ = 8^k · N₀@ — temporal pool depth × spatial cell area, the SAME integer @k@ on both
-- factors. Composed from the pinned exports, never re-derived. Negative @N₀@ clamps to 0.
derivedSampleVolume :: Rung -> Integer -> Integer
derivedSampleVolume k n0 = poolDepth k * rungIdealNorm k * max 0 n0

-- | INDEPENDENT-MODE sample volume: the sum of the ACTUAL owned sample counts (frames owned
-- × pixels each, whatever the weave delivered) — evidence counted, not assumed. Negative
-- counts clamp to 0.
independentSampleVolume :: [Integer] -> Integer
independentSampleVolume = sum . map (max 0)

-- ─────────────────────────────────────────────────────────────────────────────
-- Independence health
-- ─────────────────────────────────────────────────────────────────────────────

-- | A rung's per-bin exact integer carrier values on some shared lattice ordering (the u64
-- bin sums, flattened) — the streams the decorrelation statistic compares.
type Stream = [Integer]

-- | Pool a stream to a coarser lattice by exact block sums of @b@ bins (incomplete trailing
-- blocks are dropped, so pooling composes — 'lawPoolCompose'). @b <= 0@ yields the empty
-- stream.
poolTo :: Int -> Stream -> Stream
poolTo b = map sum . chunksOf b

-- complete blocks of size b (the trailing partial block is dropped).
chunksOf :: Int -> [a] -> [[a]]
chunksOf b xs0
  | b <= 0    = []
  | otherwise = go xs0
  where
    go xs = case splitAt b xs of
      (blk, rest) | length blk == b -> blk : go rest
                  | otherwise       -> []

-- | Per-bin deltas of a stream: @x_{i+1} − x_i@. The MOVEMENT the co-movement statistic reads.
binDeltas :: Stream -> [Integer]
binDeltas xs = zipWith (-) (drop 1 xs) xs

-- | THE STATISTIC: @(agreements, comparisons)@ — over the aligned delta pairs of the two
-- streams, how many move with the SAME sign (0 counts as a sign). Both components exact 'Int's.
comovement :: Stream -> Stream -> (Int, Int)
comovement a b = (length (filter id agrees), length agrees)
  where agrees = zipWith (\x y -> signum x == signum y) (binDeltas a) (binDeltas b)

-- | The normalized statistic @agreements \/ comparisons@ as an exact 'Rational' in @[0,1]@.
-- 1 = fully determined (the BAD pole: derived pooling); no comparisons at all also reads 1
-- (no evidence of independence is not evidence of independence).
comovementRatio :: Stream -> Stream -> Rational
comovementRatio a b
  | total == 0 = 1
  | otherwise  = fromIntegral agree % fromIntegral total
  where (agree, total) = comovement a b

-- | The warning-light predicate: the two streams co-move everywhere ('comovementRatio' 1) —
-- the observable signature that the coarse rung is (or is indistinguishable from) a derived
-- pool of the fine one.
fullyDetermined :: Stream -> Stream -> Bool
fullyDetermined a b = comovementRatio a b == 1

-- | The SHARP byte-exact fallback signature: the coarse stream IS the exact block-sum pool
-- of the fine one ("SixFour.Spec.MultiScaleCapture"'s @poolFastToSlow == readSlow@ detection,
-- on the carrier). This is the provenance bit the capture record should stamp.
isDerivedPool :: Int -> Stream -> Stream -> Bool
isDerivedPool b fine coarse = not (null coarse) && coarse == poolTo b fine

-- ─────────────────────────────────────────────────────────────────────────────
-- Laws — exposure
-- ─────────────────────────────────────────────────────────────────────────────

-- normalise QuickCheck ints into the real regimes.
normRung :: Int -> Rung
normRung k = abs k `mod` 3                 -- the three shipped rungs

normPos :: Integer -> Integer
normPos x = 1 + abs x                      -- a strictly positive integer

-- | LAW (ONE VOCABULARY — the two exposure states agree on the k-axis): on the light-ladder
-- schedule (rung @k@ exposes @'poolDepth' k · Δ₀@ at the reference gain), the OPTICAL light
-- ratio versus the fine reference equals the POOLING-EQUIVALENT ratio @2^k@ — one integer
-- @k@ indexes both modes' exposure state, for every base duration and gain.
lawExposureVocabulariesAgreeOnLadder :: Integer -> Integer -> Int -> Bool
lawExposureVocabulariesAgreeOnLadder d0Raw isoRaw kRaw =
  opticalLightRatio (poolDepth k * d0, iso) (d0, iso) == poolingEquivalentRatio k
    && poolingEquivalentRatio k == fromInteger (poolDepth k)
  where
    k   = normRung kRaw
    d0  = normPos d0Raw
    iso = normPos isoRaw

-- ─────────────────────────────────────────────────────────────────────────────
-- Laws — arrival
-- ─────────────────────────────────────────────────────────────────────────────

-- | LAW (the cadence contract, pinned): the three rungs deliver exactly 64 \/ 32 \/ 16
-- pulses per window, and every rung's @pulses × native interval@ spans exactly the 320 cs
-- window — the shared-clock identity the arrival widget renders.
lawExpectedArrivalsPinned :: Bool
lawExpectedArrivalsPinned =
  map expectedArrivals [W64, W32, W16] == [64, 32, 16]
    && all (\r -> expectedArrivals r * delayCsOf r == windowCs) [W64, W32, W16]

-- | LAW (clean cadence is healthy): the native interval list has zero late pulses, zero
-- missing pulses, and spans exactly the window — health is the fixed point of the detector.
lawCleanCadenceIsHealthy :: Bool
lawCleanCadenceIsHealthy = all healthy [W64, W32, W16]
  where
    healthy r =
      lateArrivals r (cleanCadence r) == 0
        && missingArrivals r (cleanCadence r) == 0
        && sum (cleanCadence r) == windowCs

-- | LAW (a dropped pulse is DETECTABLE from intervals alone): dropping any one pulse from
-- the clean cadence yields exactly ONE late interval and ONE missing arrival while the
-- window span is conserved — the fault has a unique, visible signature; no side channel
-- needed.
lawDroppedPulseIsDetectable :: Int -> Int -> Bool
lawDroppedPulseIsDetectable rRaw j =
  lateArrivals r broken == 1
    && missingArrivals r broken == 1
    && sum broken == windowCs
  where
    r      = [W64, W32, W16] !! normRung rRaw
    broken = dropPulse j (cleanCadence r)

-- ─────────────────────────────────────────────────────────────────────────────
-- Laws — significance
-- ─────────────────────────────────────────────────────────────────────────────

-- | LAW (the 1:8:64 lattice): derived-mode sample volumes at the three rungs are exactly
-- @[N₀, 8·N₀, 64·N₀]@, and in general @N(k) = 8^k · N₀@ — the composition of 'poolDepth'
-- (@2^k@, time) with 'rungIdealNorm' (@4^k@, area), never a third power law.
lawDerivedSignificanceLattice :: Integer -> Bool
lawDerivedSignificanceLattice n0Raw =
  [ derivedSampleVolume k n0 | k <- [0, 1, 2] ] == [ n0, 8 * n0, 64 * n0 ]
    && all (\k -> derivedSampleVolume k n0 == 8 ^ k * n0) [0 .. 5 :: Int]
  where n0 = normPos n0Raw

-- | LAW (one rung = +3 bits of N): each derived rung multiplies the sample volume by
-- exactly 8 = 2³ — three doublings of @N@ per rung (√8 of SNR, read on squares).
lawRungBuysThreeBits :: Integer -> Int -> Bool
lawRungBuysThreeBits n0Raw kRaw =
  derivedSampleVolume (k + 1) n0 == 8 * derivedSampleVolume k n0
  where
    k  = abs kRaw `mod` 8
    n0 = normPos n0Raw

-- | LAW (the √N meter reads exactly on N): squaring is order-preserving on non-negatives —
-- @x ≤ y ⟺ x² ≤ y²@ — so comparing significances by @N = SNR²@ IS comparing them by
-- @√N = SNR@, with no irrational value ever computed (the ColorTime squares discipline).
lawSignificanceSqrtMonotone :: Integer -> Integer -> Bool
lawSignificanceSqrtMonotone xRaw yRaw =
  (x <= y) == (x * x <= y * y)
  where x = abs xRaw; y = abs yRaw

-- | LAW (independent evidence never decreases significance): adding an owned sample count
-- to an independent rung's ledger can only grow its volume — the meter is monotone in
-- arrivals.
lawIndependentCountsMonotone :: Integer -> [Integer] -> Bool
lawIndependentCountsMonotone c cs =
  independentSampleVolume (c : cs) >= independentSampleVolume cs

-- ─────────────────────────────────────────────────────────────────────────────
-- Laws — independence health
-- ─────────────────────────────────────────────────────────────────────────────

normBlock :: Int -> Int
normBlock b = 1 + abs b `mod` 4            -- pooling block 1..4

-- | LAW (pooling composes): @'poolTo' c ∘ 'poolTo' b == 'poolTo' (b·c)@ — block sums are
-- associative, so "the coarser's lattice" is well-defined no matter how many shared
-- coarsening steps produced it (the sums-compose fact, on the statistic's own carrier).
lawPoolCompose :: Int -> Int -> [Integer] -> Bool
lawPoolCompose bRaw cRaw xs =
  poolTo c (poolTo b xs) == poolTo (b * c) xs
  where b = normBlock bRaw; c = normBlock cRaw

-- | LAW (THE FOIL — derived pooling saturates the statistic): when the coarse stream is the
-- exact pool of the fine one, the aligned streams are identical, every delta pair co-moves,
-- and 'comovementRatio' is exactly 1 (over at least two real comparisons — non-vacuous).
-- 'isDerivedPool' recognizes the pair. This maximal pole is what "fell back to derived
-- pooling" looks like on the meter.
lawDerivedPoolingIsMaximal :: Int -> [Integer] -> Bool
lawDerivedPoolingIsMaximal bRaw fineRaw =
  comovementRatio pooled coarse == 1
    && snd (comovement pooled coarse) >= 2
    && isDerivedPool b fine coarse
  where
    b      = normBlock bRaw
    fine   = fineRaw ++ replicate (3 * b) 1   -- ensure >= 3 coarse bins (>= 2 deltas)
    coarse = poolTo b fine
    pooled = poolTo b fine

-- | LAW (scale-equivariance — the verdict commutes with the shared pool): pooling BOTH
-- streams of a derived pair by any further shared factor keeps the statistic maximal, and
-- the pooled pair is still an exact derived pool at the composed factor ('lawPoolCompose'
-- doing the work). The detector gives the same answer on every shared lattice.
lawDerivedStaysMaximalUnderSharedPool :: Int -> Int -> [Integer] -> Bool
lawDerivedStaysMaximalUnderSharedPool bRaw cRaw fineRaw =
  comovementRatio (poolTo c pooled) (poolTo c coarse) == 1
    && isDerivedPool (b * c) fine (poolTo c coarse)
  where
    b      = normBlock bRaw
    c      = normBlock cRaw
    fine   = fineRaw ++ replicate (3 * b * c) 1
    coarse = poolTo b fine
    pooled = coarse

-- | LAW (WITNESS — independent noise is bounded away from the maximal pole): a coarse
-- stream that integrated dead-time photons the fine read never saw (the
-- "SixFour.Spec.MultiScaleCapture" independence source) moves AGAINST the pooled fine
-- stream on a delta, so the statistic sits strictly below maximal and 'isDerivedPool'
-- rejects the pair. The non-vacuity foil: the meter genuinely separates the two modes.
lawIndependentNoiseBoundedAway :: Bool
lawIndependentNoiseBoundedAway =
  agree < total
    && comovementRatio pooled coarse < 1
    && not (isDerivedPool b fine coarse)
  where
    b      = 4
    -- pooled fine = [40, 80, 120]: rising everywhere (deltas +40, +40).
    fine   = [10, 10, 10, 10, 20, 20, 20, 20, 30, 30, 30, 30]
    -- the long read caught a mid-window dimming the short reads slept through:
    -- deltas +60, −10 — the second delta co-moves AGAINST the pooled fine.
    coarse = [40, 100, 90]
    pooled = poolTo b fine
    (agree, total) = comovement pooled coarse

-- | LAW (every sign disagreement is seen): if ANY aligned delta pair of the two streams
-- disagrees in sign, the ratio drops strictly below 1 — the warning light cannot stay green
-- past a single counter-movement.
lawDisagreementIsDetected :: [Integer] -> [Integer] -> Bool
lawDisagreementIsDetected a b =
  not disagreeSomewhere || comovementRatio a b < 1
  where
    disagreeSomewhere =
      or (zipWith (\x y -> signum x /= signum y) (binDeltas a) (binDeltas b))

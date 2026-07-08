{- |
Module      : SixFour.Spec.BitLedger
Description : THE INFORMATION LEDGER OF THE SIGNAL PATH — exact bit accounting from the 10-bit sensor code to the 8-bit GIF89a byte, answering "how does 10-bit become 8-bit" with a theorem instead of a shrug: you NEVER quantize 10→8 directly. The path is DECODE-WIDEN (10-bit HLG code → 16-bit linear, an injective relabeling, zero bits lost, 'lawStrictMonotoneDecodeIsLossless') → INTEGRATE (u64 block sums in linear light — pooling n samples GAINS depth: the sum of n b-bit samples carries @n·(2^b−1)+1@ distinct levels, 'lawPoolingGainsDepth', so a 16²-bin pooled from a 1024² crop holds ≈22 effective bits of a 10-bit signal) → REALIZE ONCE (round-half-up mean to the 8-bit byte — the SINGLE lossy step, discarding exactly @effectiveDepth − 8@ bits, and using the whole 8-bit code space, 'lawByteCodesAllReachable'). Eight bits is not a compromise at the end of this path; it is the GIF89a wire width fed by an integrator that spent color-time to EARN more depth than the sensor gave per sample.

== The ledger, stage by stage

@
  stage                width      lossy?   law
  ─────────────────────────────────────────────────────────────────────
  x420 HLG code        10 bit     —        codes 0..1023, refuse > 1023
  inverse-EOTF LUT     16 bit     NO       strictly monotone ⇒ injective
  spatial block sum    10+2·log₂q NO       'lawPoolSumWidthExact'
  temporal accumulate  +log₂T     NO       sums compose (ColorTime)
  u64 carrier          ≤ 63 bit   NO       'lawU64CarriesTheWorstCrop'
  realize (mean→byte)  8 bit      ONCE     round-half-up, surjective
  GIF89a index         ≤ 8 bit    palette  the color head's second
                                           quantization (256 slots)
@

== Why pooling GAINS depth (the crux)

The MEAN of @n@ samples of @b@ bits takes @n·(2^b−1)+1@ distinct values
('meanLevels') — more codes than any single sample has. Pooling is not
averaging away information; in linear light it is INTEGRATION, the same
currency as color-time ("SixFour.Spec.ColorTime": SNR ∝ √τ_c is the
statistical face; 'lawPoolingGainsDepth' is the exact combinatorial face).
This is why the 8-bit realization at the END outranks an 8-bit truncation
at the START by exactly the pooled bits: truncate first and the bits are
gone; integrate first and the byte is the correct rounding of a ≈22-bit
measurement.

== The ladder and the three GIFs (what the CNNs may measure)

On the POOLED path the 32² and 16² rungs are exact functions of the 64²
sums (sums compose — "SixFour.Spec.ColorTime" 'SixFour.Spec.ColorTime.lawSumsCompose',
"SixFour.Spec.V21Pyramid" transitivity): derived rungs add ZERO bits, so a
CNN asked to relate the three pooled GIFs can only learn the wash (the
zero-detail section, "SixFour.Spec.MixSKI"). Rung relationships become
MEASURABLE exactly when the rungs own disjoint photons — the LOOM's
independent exposures ("SixFour.Spec.MultiScaleIntegrate"
@lawConservesPhotons@ / @lawVolumeUsesOnlyOwnedPhotons@) — and then the
learnable content is the transition detail, whose bits the ladder keeps
disjoint by the telescoping chain rule
("SixFour.Spec.TriScaleTraining" @lawLadderTelescopesExactly@).

Pure arithmetic on 'Integer'; GHC-boot-only. Additive.
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none
module SixFour.Spec.BitLedger
  ( -- * Widths
    bitsFor
  , sampleMax10
  , linearMax16
  , byteMax8
    -- * Pooling arithmetic
  , poolSumMax
  , poolSumBits
  , meanLevels
  , effectiveDepthBits
  , realizeLossBits
  , roundHalfUpMean
    -- * Laws
  , lawStrictMonotoneDecodeIsLossless
  , lawPoolSumWidthExact
  , lawU64CarriesTheWorstCrop
  , lawPoolingGainsDepth
  , lawShippedLedgerPinned
  , lawByteCodesAllReachable
  ) where

import Data.List (nub)

-- | The smallest bit-width holding values 0..v: @⌈log₂(v+1)⌉@ (0 for v = 0).
bitsFor :: Integer -> Int
bitsFor v = length (takeWhile (<= v) (iterate (* 2) 1))

-- | The x420 sample ceiling: 10-bit codes, 0..1023 (full-range; the kernel
-- REFUSES codes above — totality, never absorption).
sampleMax10 :: Integer
sampleMax10 = 1023

-- | The linear carrier ceiling after the inverse-EOTF: 16-bit, 0..65535.
linearMax16 :: Integer
linearMax16 = 65535

-- | The GIF89a wire width: one byte, 0..255 — index and palette channel alike.
byteMax8 :: Integer
byteMax8 = 255

-- | Largest possible sum of n samples each ≤ m.
poolSumMax :: Integer -> Integer -> Integer
poolSumMax n m = n * m

-- | Bits the sum of n samples of max m needs.
poolSumBits :: Integer -> Integer -> Int
poolSumBits n m = bitsFor (poolSumMax n m)

-- | Distinct values the SUM (equivalently the mean, before rounding) of n
-- b-bit-max samples can take: @n·m+1@ for m = 2^b − 1. The exact face of
-- "pooling gains depth".
meanLevels :: Integer -> Integer -> Integer
meanLevels n m = n * m + 1

-- | The effective quantization depth of the pooled measurement, in bits.
effectiveDepthBits :: Integer -> Integer -> Int
effectiveDepthBits n m = bitsFor (meanLevels n m - 1)

-- | Bits the single realization step discards: effective depth minus the
-- 8-bit wire (never negative).
realizeLossBits :: Integer -> Integer -> Int
realizeLossBits n m = max 0 (effectiveDepthBits n m - 8)

-- | Round-half-up integer mean — the realization arithmetic
-- (@s4_sums_to_srgb8@): @(s + n div 2) div n@.
roundHalfUpMean :: Integer -> Integer -> Integer
roundHalfUpMean s n = (s + n `div` 2) `div` n

-- | DECODE LOSES NOTHING: a strictly increasing LUT is injective — two
-- distinct 10-bit codes always decode to distinct linear16 values, so the
-- 10→16 widening is a lossless relabeling. Quantified over arbitrary
-- strictly-increasing tables (the shipped HLG/sRGB tables are such).
lawStrictMonotoneDecodeIsLossless :: [Integer] -> Bool
lawStrictMonotoneDecodeIsLossless xs =
  let lut = scanl1 (\a d -> a + abs d + 1) xs   -- force strict increase
  in and (zipWith (<) lut (drop 1 lut))         -- strictly monotone …
       && length lut == length (nub lut)        -- … hence injective (no collisions)

-- | POOL WIDTH, EXACT: for n = 2^k samples of b-bit max (b ≥ 1), the sum
-- needs EXACTLY b + k bits — @2^k·(2^b−1) = 2^(b+k) − 2^k@ sits just under
-- the boundary. The widening ladder (u8→u32→u64 lanes in KernelsSIMT) is
-- this law made silicon.
lawPoolSumWidthExact :: Int -> Int -> Bool
lawPoolSumWidthExact kRaw bRaw =
  let k = abs kRaw `mod` 24
      b = 1 + (abs bRaw `mod` 16)
  in poolSumBits (2 ^ k) (2 ^ b - 1) == b + k

-- | THE u64 CARRIER SUFFICES with room to spare: the worst shipped shape —
-- 16-bit linear samples, a (4096/16)² = 65536-pixel bin, 64 frames
-- accumulated — needs 38 bits; the carrier has 63 unsigned-safe. (The Zig
-- header's "255·65536² < 2^63" comment, promoted to a law.)
lawU64CarriesTheWorstCrop :: Bool
lawU64CarriesTheWorstCrop =
  poolSumBits (65536 * 64) linearMax16 <= 63
    && poolSumBits (65536 * 64) linearMax16 == 38

-- | POOLING GAINS DEPTH: the pooled measurement has strictly more levels
-- than any single sample whenever n > 1 — and the gain is exact:
-- @meanLevels n m = n·m + 1@. A 10-bit signal in a 4096-sample bin carries
-- 22 effective bits ('lawShippedLedgerPinned' pins that instance).
lawPoolingGainsDepth :: Integer -> Bool
lawPoolingGainsDepth nRaw =
  let n = 2 + (abs nRaw `mod` 100000)
  in meanLevels n sampleMax10 > sampleMax10 + 1
       && effectiveDepthBits n sampleMax10 >= 10

-- | THE SHIPPED LEDGER, PINNED: 16² bins from a 1024² crop = 4096 samples
-- per bin; a 10-bit sample pools to 22 effective bits, so realizing to the
-- 8-bit GIF byte discards exactly 14 bits — ONCE, at the end. Truncating
-- 10→8 at the start would have discarded 2 bits of EVERY sample and
-- foreclosed the 12 pooled bits entirely.
lawShippedLedgerPinned :: Bool
lawShippedLedgerPinned =
  effectiveDepthBits 4096 sampleMax10 == 22
    && realizeLossBits 4096 sampleMax10 == 14
    && effectiveDepthBits 1 sampleMax10 == 10   -- no pooling, no gain
    && realizeLossBits 1 byteMax8 == 0          -- an 8-bit sample realizes losslessly

-- | THE BYTE IS FULLY USED: every 8-bit code is reachable through the
-- round-half-up realization — for any bin size n ≥ 1 and any target byte v,
-- the sum v·n realizes to exactly v. The 8-bit wire is surjective output,
-- not a truncation artifact.
lawByteCodesAllReachable :: Integer -> Integer -> Bool
lawByteCodesAllReachable nRaw vRaw =
  let n = 1 + abs nRaw
      v = abs vRaw `mod` 256
  in roundHalfUpMean (v * n) n == v

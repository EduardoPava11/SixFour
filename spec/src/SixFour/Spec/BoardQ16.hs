{- |
Module      : SixFour.Spec.BoardQ16
Description : The DETERMINISTIC integer board-mass derivation — closes the float input gap.

The AlphaZero policy reads the 16³ board ('SixFour.Spec.AtlasBoard'). Its base mass channels are
built today by 'AtlasBoard.histogram', which (a) accumulates @1 / fromIntegral n@ — a non-dyadic
float added in input order, so the per-bin mass is NOT bit-reproducible across summation orders or
devices, and (b) bins via the float 'Coverage.okLabBin', which can flip a bin on a 1-ULP nudge.
The design (SIXFOUR-ALPHAZERO-COLLAPSE-DESIGN §5.2) flags this: float leaking in at the FIRST
matmul is exactly what destabilises the policy @argmax@ cross-device.

This module is the byte-exact replacement, the Haskell source of truth for the Zig/Swift ports
(the M2 golden). Colours arrive already quantized to Q16 ('AtlasBoard.OKLabQ16'); binning is
integer floor-division (matching 'okLabBin' off the lattice planes); occupancy is an INTEGER count
(associative + commutative, so permutation-invariant EXACTLY — 'lawCountsOrderIndependent'); and
the Q16 mass is ONE rounding of @count·2^16 / total@ per bin, never an order-dependent float
accumulation.
-}
-- COMPARTMENT: ZIG-FLOOR | tag:DeviceTag
module SixFour.Spec.BoardQ16
  ( -- * Q16 grid constants
    q16One, binWidthQ16, halfQ16
    -- * Deterministic integer binning + mass
  , binOfQ16
  , countsQ16
  , massQ16
  , boardMassQ16
    -- * Laws (predicates; QuickCheck'd in Properties.BoardQ16)
  , lawBinOfQ16InRange
  , lawBinQ16RoundTripsCenters
  , lawCountsSumToLength
  , lawCountsOrderIndependent
  , lawMassQ16Bounded
  ) where

import qualified Data.Vector as V

import SixFour.Spec.Coverage  (coverageBinsPerAxis)
import SixFour.Spec.AtlasBoard
  ( BinIdx(..), OKLabQ16, binIndex, binInRange, boardBins, binCenter, okLabToQ16 )

-- ---------------------------------------------------------------------------
-- Q16 grid constants
-- ---------------------------------------------------------------------------

-- | The Q16 representation of @1.0@ (the fixed-point scale, @2^16@).
q16One :: Int
q16One = 65536

-- | Width of one bin in Q16 units: @2^16 / 16 = 4096@. (Floor-dividing a Q16
-- value by this is exactly @floor(v·16)@ for the working range.)
binWidthQ16 :: Int
binWidthQ16 = q16One `div` coverageBinsPerAxis

-- | The Q16 representation of @0.5@ (the a\/b axis offset). @2^15 = 32768@.
halfQ16 :: Int
halfQ16 = q16One `div` 2

-- ---------------------------------------------------------------------------
-- Deterministic integer binning + mass
-- ---------------------------------------------------------------------------

-- | The bin of a Q16 OKLab triple, by integer floor-division — the byte-exact
-- mirror of 'Coverage.okLabBin' (@clamp(floor(v·16))@ on @L@, @clamp(floor((v+0.5)·16))@
-- on @a,b@). 'div' floors (toward −∞), matching 'floor'; a Metal port must use an
-- explicit floor-div helper here (int @\/@ truncates toward zero). Total: always in range.
binOfQ16 :: OKLabQ16 -> BinIdx
binOfQ16 (l, a, b) =
  BinIdx ( clamp (l `div` binWidthQ16)
         , clamp ((a + halfQ16) `div` binWidthQ16)
         , clamp ((b + halfQ16) `div` binWidthQ16) )
  where clamp i = max 0 (min (coverageBinsPerAxis - 1) i)

-- | Integer per-bin occupancy counts. Integer addition is associative and
-- commutative, so this is permutation-invariant EXACTLY (the property the float
-- histogram lacks). Layout is 'AtlasBoard.binIndex'.
countsQ16 :: [OKLabQ16] -> V.Vector Int
countsQ16 cs =
  V.accum (+) (V.replicate boardBins 0)
          [ (binIndex (binOfQ16 c), 1) | c <- cs ]

-- | The Q16-normalised mass from integer counts: ONE round-half-up of
-- @count·2^16 / total@ per bin (no order-dependent float accumulation). @total = 0@
-- gives the all-zero mass.
massQ16 :: Int -> V.Vector Int -> V.Vector Int
massQ16 total =
  V.map (\c -> if total <= 0 then 0 else (c * q16One + total `div` 2) `div` total)

-- | The full deterministic mass channel for a colour list: count, then Q16-normalise
-- by the exact element count. Byte-exact and order-independent.
boardMassQ16 :: [OKLabQ16] -> V.Vector Int
boardMassQ16 cs = massQ16 (length cs) (countsQ16 cs)

-- ---------------------------------------------------------------------------
-- Laws
-- ---------------------------------------------------------------------------

-- | 'binOfQ16' is total: every Q16 colour lands on the board (clamp guarantees range).
lawBinOfQ16InRange :: OKLabQ16 -> Bool
lawBinOfQ16InRange = binInRange . binOfQ16

-- | The integer binning recovers bin centres exactly: for an in-range bin, quantizing its
-- centre to Q16 and re-binning returns the same bin. Pins 'binOfQ16' to the 'okLabBin' grid
-- (centres are dyadic, so this is exact — the robust, boundary-free correctness anchor).
lawBinQ16RoundTripsCenters :: BinIdx -> Bool
lawBinQ16RoundTripsCenters bi =
  not (binInRange bi) || binOfQ16 (okLabToQ16 (binCenter bi)) == bi

-- | Every colour is counted exactly once: @Σ counts == length@ (totality, integer-exact).
lawCountsSumToLength :: [OKLabQ16] -> Bool
lawCountsSumToLength cs = V.sum (countsQ16 cs) == length cs

-- | Counts are permutation-invariant: reordering the input cannot change a single bin
-- (the determinism the float histogram fails). Stated against an explicit permutation here;
-- @Properties.BoardQ16@ also QuickChecks it against random shuffles.
lawCountsOrderIndependent :: [OKLabQ16] -> Bool
lawCountsOrderIndependent cs = countsQ16 cs == countsQ16 (reverse cs)

-- | The Q16 mass is bounded: every entry ∈ @[0, 2^16]@, and (non-empty) the total is within
-- 'boardBins' of @2^16@ (the accumulated round-half-up error is < 1 per occupied bin).
lawMassQ16Bounded :: [OKLabQ16] -> Bool
lawMassQ16Bounded cs =
  let m = boardMassQ16 cs
      inUnit v = v >= 0 && v <= q16One
  in V.all inUnit m
     && (null cs || abs (V.sum m - q16One) <= boardBins)

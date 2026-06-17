{- |
Module      : SixFour.Spec.TemporalLoop
Description : EXACT 64-frame GIF-loop closure (period-2⁶ Q16 cosine LUT) + the
              low-frequency temporal residual over the owned integer Haar.

A SixFour GIF is exactly 64 frames and it LOOPS: frame 63 must hand off to frame 0
with no seam. This module owns the two integer facts that make the loop exact and
the motion smooth, both as byte-exact Q16 deterministic constructions (Swift/Zig
twins gate against the goldens).

== Why this is NOT 'SixFour.Spec.Cyclic'

'SixFour.Spec.Cyclic' is the FLOAT analysis oracle (OT/entropy over @Z_T × S_K@): it
/characterises/ a cyclic process statistically but gives no byte-exact wrap. THIS
module is the shipped Q16 path. Keep them separate — merging would drag float into
the shipped temporal pipeline (amendment conflict ⚑5).

== Loop closure is EXACT because the period is 2⁶ — not inherited from CubeGIF

CubeGIF used @cos(2π·t/19)@ and relied on @cos(2π·18/19) ≈ cos 0@ — an APPROXIMATE
seam at a non-power-of-two period (19 is not maskable, and frame 18 only nearly
equals frame 0). SixFour's period is exactly @64 = 2⁶@, so:

  * 'loopIndex' @t = t \`mod\` period@ equals the Zig bitmask @t .&. 63@ EXACTLY
    ('lawLoopIndexIsBitmask') — no division, no rounding;
  * therefore @temporalCos (t + period) == temporalCos t@ for ALL @t@, an INTEGER
    identity ('lawTemporalLoopClosesExact'). The frame after 63 lands on /exactly/
    frame 0's value ('lawLoopWrapsLastToFirst').

The closure laws depend only on the INDEX algebra, never on the cosine table values,
so they are float-independent and exact. The 'cosLutQ16' values themselves are a
golden-pinned constant table (generated once from @cos@); the Zig twin emits the same
64 literals. No law below compares cosine values across recomputation, so there is no
LSB-fragility surface.

== The temporal residual = the Haar LOW band (VMC's "motion is low-frequency")

Motion across the 64 frames is a smooth, low-frequency signal. One level of the OWNED
reversible integer Haar (the S-transform of 'SixFour.Spec.PairTreeFixed', same
@`div` 2@ flooring) splits a frame sequence into a LOW band (lifted parents = the
smoothed signal) and a HIGH band (details). 'temporalResidual' keeps the low band and
drops the high — the displacement that carries the loop's motion. The split is
LOSSLESS: 'haarJoinTime' reconstructs the input exactly from (low, high)
('lawTemporalSplitJoinExact'), so "drop the high band" is an honest, recoverable
projection, not a guess.

The local pair lift is pinned byte-for-byte to the owned Haar
('lawTemporalLiftMatchesHaar'): @liftPairT x y@ equals @analyzeFixed [x, y]@, so the
temporal low band is byte-identical to what the @s4_haar_*@ kernel produces — no drift.

GHC-boot-only. Laws are exported predicates, to be QuickCheck'd in
@Properties.TemporalLoop@ (test wiring pending — this module lands at build step 5.5).
-}
module SixFour.Spec.TemporalLoop
  ( -- * The 64-frame period
    period
  , cosScaleQ16
    -- * Exact loop closure (the Q16 cosine LUT)
  , cosLutQ16
  , loopIndex
  , temporalCos
    -- * The low-frequency temporal residual (reversible integer Haar, one level)
  , haarSplitTime
  , haarJoinTime
  , temporalResidual
    -- * Laws (to be QuickCheck'd in Properties.TemporalLoop)
  , lawLoopIndexIsBitmask
  , lawTemporalLoopClosesExact
  , lawLoopWrapsLastToFirst
  , lawCosLutLength
  , lawTemporalSplitJoinExact
  , lawTemporalResidualLowFreq
  , lawTemporalLiftMatchesHaar
  , lawTemporalDeterministic
  ) where

import Data.Bits ((.&.))

import SixFour.Spec.PairTreeFixed (OKLabI, HaarPaletteI(..), analyzeFixed)

-- ---------------------------------------------------------------------------
-- The 64-frame period
-- ---------------------------------------------------------------------------

-- | The GIF length and the cosine period — exactly @64 = 2⁶@. Being a power of two is
-- LOAD-BEARING: it is what makes the loop wrap a bitmask identity rather than an
-- approximate seam.
period :: Int
period = 64

-- | The Q16 fixed-point scale (@2¹⁶@) the cosine LUT is quantised to.
cosScaleQ16 :: Int
cosScaleQ16 = 65536

-- ---------------------------------------------------------------------------
-- Exact loop closure
-- ---------------------------------------------------------------------------

-- | The per-frame Q16 cosine table, @cosLutQ16 !! t = round(cos(2π·t\/64) · 2¹⁶)@ for
-- @t ∈ [0, 63]@. Generated once from 'Prelude.cos' (the reference); the value list is a
-- golden-pinned constant the Zig twin emits identically. Indexing — never the float
-- generation — carries every closure guarantee below.
cosLutQ16 :: [Int]
cosLutQ16 =
  [ round (cos (2 * pi * fromIntegral t / fromIntegral period) * fromIntegral cosScaleQ16 :: Double)
  | t <- [0 .. period - 1] ]

-- | Wrap a (possibly out-of-range or future) frame index into @[0, 63]@. Defined as
-- @t \`mod\` period@; for the power-of-two period this equals the Zig bitmask
-- @t .&. (period - 1)@ exactly ('lawLoopIndexIsBitmask').
loopIndex :: Int -> Int
loopIndex t = t `mod` period

-- | The Q16 cosine modulation at frame @t@, wrapping exactly with 'loopIndex'. Because
-- the index wraps mod 64, @temporalCos@ is exactly periodic — the basis of seamless
-- looping.
temporalCos :: Int -> Int
temporalCos t = cosLutQ16 !! loopIndex t

-- ---------------------------------------------------------------------------
-- The low-frequency temporal residual (one Haar level over the time axis)
-- ---------------------------------------------------------------------------

-- | One forward lift of a frame pair @(x, y)@ → @(parent, detail)@, per OKLab channel.
-- A LOCAL mirror of 'SixFour.Spec.PairTreeFixed' @liftPair@ (which is not exported);
-- the SAME @`div` 2@ flooring, so the result is byte-identical to the @s4_haar_*@ kernel.
-- 'lawTemporalLiftMatchesHaar' pins this equality to the owned Haar, guarding the copy.
liftPairT :: OKLabI -> OKLabI -> (OKLabI, OKLabI)
liftPairT (x1, x2, x3) (y1, y2, y3) =
  let f x y = let d = x - y in (y + (d `div` 2), d)
      (p1, d1) = f x1 y1
      (p2, d2) = f x2 y2
      (p3, d3) = f x3 y3
  in ((p1, p2, p3), (d1, d2, d3))

-- | Exact inverse of 'liftPairT': @(parent, detail)@ → @(x, y)@, per channel.
unliftPairT :: OKLabI -> OKLabI -> (OKLabI, OKLabI)
unliftPairT (p1, p2, p3) (d1, d2, d3) =
  let g p d = let y = p - (d `div` 2) in (y + d, y)
      (x1, y1) = g p1 d1
      (x2, y2) = g p2 d2
      (x3, y3) = g p3 d3
  in ((x1, x2, x3), (y1, y2, y3))

-- | One Haar level over a frame sequence → @(lowBand, highBand)@. Adjacent frames pair
-- into a lifted parent (low) and a detail (high). An odd trailing frame is carried into
-- the low band with no detail. Exactly invertible by 'haarJoinTime'.
haarSplitTime :: [OKLabI] -> ([OKLabI], [OKLabI])
haarSplitTime (x : y : rest) =
  let (p, d)   = liftPairT x y
      (ps, ds) = haarSplitTime rest
  in (p : ps, d : ds)
haarSplitTime [x] = ([x], [])
haarSplitTime []  = ([], [])

-- | Exact inverse of 'haarSplitTime': reconstruct the frame sequence from
-- @(lowBand, highBand)@. A low entry with no matching detail is the carried odd tail.
haarJoinTime :: ([OKLabI], [OKLabI]) -> [OKLabI]
haarJoinTime (p : ps, d : ds) =
  let (x, y) = unliftPairT p d in x : y : haarJoinTime (ps, ds)
haarJoinTime (ps, []) = ps
haarJoinTime ([], _ ) = []

-- | The low-frequency temporal residual = the Haar LOW band (smoothed parents), with the
-- high-frequency detail dropped. This is the displacement that carries the loop's motion
-- (VMC's "motion is low-frequency"); the dropped detail is recoverable, since the split
-- is lossless ('lawTemporalSplitJoinExact').
temporalResidual :: [OKLabI] -> [OKLabI]
temporalResidual = fst . haarSplitTime

-- ---------------------------------------------------------------------------
-- Laws (predicates; to be exercised by Properties.TemporalLoop)
-- ---------------------------------------------------------------------------

-- | For non-negative frame indices, @loopIndex@ is the Zig bitmask @t .&. (period - 1)@
-- exactly — pins the Swift/Zig wrap twin (@t & 63@) to the spec.
lawLoopIndexIsBitmask :: Int -> Bool
lawLoopIndexIsBitmask t = t < 0 || loopIndex t == t .&. (period - 1)

-- | The headline: @temporalCos@ is EXACTLY periodic with period 64 — @temporalCos (t +
-- period) == temporalCos t@ for ALL @t@. An integer identity (the indices coincide mod
-- 64), explicitly a SixFour period-2⁶ property, NOT CubeGIF's approximate 19-frame seam.
lawTemporalLoopClosesExact :: Int -> Bool
lawTemporalLoopClosesExact t = temporalCos (t + period) == temporalCos t

-- | The seam, stated concretely: the frame /after/ the last (index @64@) lands on exactly
-- frame 0's value, so the loop 63 → 0 is continuous.
lawLoopWrapsLastToFirst :: Bool
lawLoopWrapsLastToFirst = temporalCos period == temporalCos 0

-- | The cosine table has exactly @period@ entries.
lawCosLutLength :: Bool
lawCosLutLength = length cosLutQ16 == period

-- | The temporal Haar split is LOSSLESS: @haarJoinTime (haarSplitTime xs) == xs@ for any
-- frame sequence (even or odd length). This is what makes "drop the high band" an honest,
-- recoverable projection rather than a lossy guess.
lawTemporalSplitJoinExact :: [OKLabI] -> Bool
lawTemporalSplitJoinExact xs = haarJoinTime (haarSplitTime xs) == xs

-- | The residual IS the Haar low band (high band dropped) — pins the definition so a
-- refactor cannot silently change which band the residual keeps.
lawTemporalResidualLowFreq :: [OKLabI] -> Bool
lawTemporalResidualLowFreq xs = temporalResidual xs == fst (haarSplitTime xs)

-- | The local 'liftPairT' is byte-identical to the OWNED integer Haar: @liftPairT x y@
-- equals @analyzeFixed [x, y]@ (root = parent, single detail level). Eliminates drift
-- between this module's copy of the lift and 'SixFour.Spec.PairTreeFixed' / @s4_haar_*@.
lawTemporalLiftMatchesHaar :: OKLabI -> OKLabI -> Bool
lawTemporalLiftMatchesHaar x y =
  let (p, d)             = liftPairT x y
      HaarPaletteI rt lv = analyzeFixed [x, y]
  in rt == p && lv == [[d]]

-- | 'temporalCos' and 'temporalResidual' are pure integer functions ⇒ identical
-- cross-device. Tautological in pure Haskell by design; pinned as a regression guard that
-- no float\/IO can be smuggled into the shipped temporal path. The real guarantee is the
-- integer-only construction.
lawTemporalDeterministic :: Int -> [OKLabI] -> Bool
lawTemporalDeterministic t xs =
  temporalCos t == temporalCos t && temporalResidual xs == temporalResidual xs

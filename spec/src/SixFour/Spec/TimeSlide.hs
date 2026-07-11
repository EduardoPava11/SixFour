{- |
Module      : SixFour.Spec.TimeSlide
Description : THE TIME SLIDE — one vertical finger slide dilates the Decide hero's playback between the three lawful rungs, and every quantity it displays is an exact integer of the ladder. The slide QUANTIZES to a detent k ∈ {0,1,2} ('detentOf' — 'cellsPerDetent' hero-lattice cells of travel per rung step, down = coarser); a detent's playback period is EXACTLY the rung's weave units ('periodOf' = 'SixFour.Spec.WeaveOrder.unitsOf' — 1\/2\/4 ticks = 20\/10\/5 Hz; 'lawDetentsAreRungs' refuses the seductive 3-tick delay because 64 mod 3 ≠ 0 cannot tile the window), the playhead is a pure function of the one 20 Hz tick ('pos', anchored at the latch), and the frame SHOWN at a coarse detent is a true temporal integral: u64-style Integer sums over the ALIGNED group window, divided ONCE by @2^k@ with round-half-up ('integralQ16' \/ 'divRoundHalfUp' — total over the NEGATIVE Q16 OKLab a\/b channels, Haskell @div@ floor semantics pinned by 'lawDivRoundHalfUpNegatives'). The keystone convention pin is 'lawGroupWindowIsPouredWindow': group @j@'s 0-based frames @[j·2^k .. j·2^k+2^k−1]@ are EXACTLY 'SixFour.Spec.ColorTimeDisplay.pouredWindow' at the realize tick @r = (j+1)·2^k@ under 1-based bookkeeping — the window ENDS at the realize tick, killing the off-by-one a 0-based port would ship against @goldenSchedule16@. Wall time is INVARIANT: the loop is 64 ticks = 320 cs at EVERY detent ('lawLoopWallTimeInvariant' — 'SixFour.Spec.WeaveOrder.lawWeaveColorTimeConserved' made display-visible; "slower" is chunkier holds, never a longer loop). And the slide is DISPLAY ONLY: no detent or playhead transition ever emits a game op ('lawSlideNeverWritesTheWord' — the decision word is THE MERGE's alone, "SixFour.Spec.MergeBoard"). Parent: "SixFour.Spec.ColorTimeDisplay" (this module re-uses its 'SixFour.Spec.ColorTimeDisplay.realizesAt' \/ 'SixFour.Spec.ColorTimeDisplay.pouredWindow' and never restates them). 'goldenPlayhead16' and 'goldenIntegralQ16' are the cross-language goldens the Swift twin mirrors verbatim. GHC-boot-only.
-}
-- COMPARTMENT: SWIFT-COREAI | tag:DisplaySide
module SixFour.Spec.TimeSlide
  ( -- * The slide → detent quantizer
    cellsPerDetent
  , detentOf
    -- * Detents are rungs
  , rungAt
  , periodOf
    -- * The playhead on the one clock
  , pos
  , displayGroup
  , groupFrames
  , groupEndFrame
    -- * The temporal integral (divide once, round half up)
  , divRoundHalfUp
  , volumeQ16
  , integralQ16
    -- * The slide's word contribution (none, ever)
  , slideOps
    -- * The cross-language goldens
  , goldenPlayhead16
  , goldenVolumeQ16
  , goldenIntegralQ16
    -- * Laws
  , lawDetentTotal
  , lawDetentMonotone
  , lawDetentEndpoints
  , lawDetentsAreRungs
  , lawGroupChangesExactlyOnRealize
  , lawGroupWindowIsPouredWindow
  , lawIntegralFineIsIdentity
  , lawIntegralIsSumsDividedOnce
  , lawLoopWallTimeInvariant
  , lawDivRoundHalfUpNegatives
  , lawSlideNeverWritesTheWord
  ) where

import SixFour.Spec.ColorTimeDisplay (Tick, pouredWindow, realizesAt)
import SixFour.Spec.MergeBoard (GameOp, playAll)
import SixFour.Spec.WeaveOrder
  ( WeaveRung (..), delayCsOf, unitsOf, windowCs, windowUnits )

-- ─────────────────────────────────────────────────────────────────────────────
-- The slide → detent quantizer
-- ─────────────────────────────────────────────────────────────────────────────

-- | THE ONE NAMED TUNING INTEGER: hero-lattice cells of vertical finger travel
-- per rung step (16 = one region side). Retuning the slide's feel on device is
-- a one-line, spec-visible change to this constant — never a scattered float.
cellsPerDetent :: Int
cellsPerDetent = 16

-- | Quantize a slide to a detent: @detentOf kAtLatch dyCells@ =
-- @min 2 (max 0 (kAtLatch + dyCells \`div\` cellsPerDetent))@ — the detent
-- latched when the finger went down, moved one rung per 'cellsPerDetent' cells
-- of travel, clamped to the three lawful rungs. Downward travel (positive dy)
-- is COARSER (toward the 16-rung). Haskell @div@ FLOORS, so the negative
-- (upward) branch crosses its first detent one cell in — the same
-- negative-operand discipline 'divRoundHalfUp' pins; the Swift twin must use
-- floor division, not truncation.
detentOf :: Int -> Int -> Int
detentOf kAtLatch dyCells =
  min 2 (max 0 (kAtLatch + dyCells `div` cellsPerDetent))

-- ─────────────────────────────────────────────────────────────────────────────
-- Detents are rungs
-- ─────────────────────────────────────────────────────────────────────────────

-- | The rung a detent names: 0 → 'W64', 1 → 'W32', 2 → 'W16' (out-of-range
-- clamps — total). The Int↔rung bridge the Swift port mirrors.
rungAt :: Int -> WeaveRung
rungAt k = [W64, W32, W16] !! min 2 (max 0 k)

-- | A detent's playback period in ticks: 'unitsOf' of its rung = @2^k@
-- (1\/2\/4 ticks = 20\/10\/5 Hz). DELEGATION, not a constant — the slide's
-- cadence and the GIF89a delay ladder are the same integer.
periodOf :: Int -> Int
periodOf = unitsOf . rungAt

-- ─────────────────────────────────────────────────────────────────────────────
-- The playhead on the one clock
-- ─────────────────────────────────────────────────────────────────────────────

-- | The playhead frame at tick @t@, anchored at the latch: @(anchorFrame +
-- (t − anchorTick)) \`mod\` 64@ — one frame per tick around the 64-frame loop
-- ('SixFour.Spec.WeaveOrder.windowUnits'), total over ticks before the anchor
-- (@mod@ keeps it in @[0..63]@). The playhead is a pure function of the ONE
-- 20 Hz tick; no second timer exists.
pos :: Tick -> Int -> Tick -> Int
pos anchorTick anchorFrame t =
  (anchorFrame + (t - anchorTick)) `mod` windowUnits

-- | The display group the playhead sits in at detent @k@: 'pos' divided by the
-- period @2^k@ — the index of the temporal-integral frame the hero SHOWS. The
-- latch convention (the runtime invariant the Swift port must honor) snaps
-- @anchorFrame@ to a group boundary, so the group steps exactly on the realize
-- ticks ('lawGroupChangesExactlyOnRealize').
displayGroup :: Int -> Tick -> Int -> Tick -> Int
displayGroup k anchorTick anchorFrame t =
  pos anchorTick anchorFrame t `div` periodOf k

-- | The 0-based source frames of group @j@ at detent @k@: the ALIGNED window
-- @[j·2^k .. j·2^k+2^k−1]@ — pool boundaries never stray off the aligned
-- partition (means composed off-partition are the classic teeth).
groupFrames :: Int -> Int -> [Int]
groupFrames j k = [j * p .. j * p + p - 1]
  where p = periodOf k

-- | The LAST frame of group @j@ at detent @k@: @j·2^k + 2^k − 1@ — the
-- 'SixFour.Spec.ColorTimeDisplay.pouredWindow' END frame, i.e. the playhead
-- value right after that group's realize.
groupEndFrame :: Int -> Int -> Int
groupEndFrame j k = j * periodOf k + periodOf k - 1

-- ─────────────────────────────────────────────────────────────────────────────
-- The temporal integral
-- ─────────────────────────────────────────────────────────────────────────────

-- | Round-half-up integer mean: @divRoundHalfUp s n = (2·s + n) \`div\` (2·n)@ —
-- TOTAL over negative @s@ (Q16 OKLab a\/b run negative) by Haskell @div@ FLOOR
-- semantics, pinned by 'lawDivRoundHalfUpNegatives'. Halves round UP (toward
-- +∞): @−1.5 → −1@. A truncating (@quot@) port silently differs at negative
-- operands. Non-positive divisors answer 0 (totality; the ladder's divisors
-- are @2^k ≥ 1@).
divRoundHalfUp :: Integer -> Integer -> Integer
divRoundHalfUp s n
  | n <= 0    = 0
  | otherwise = (2 * s + n) `div` (2 * n)

-- | Build a rectangular Q16 volume (frames × @w@ voxels) from a flat
-- frame-major list; the trailing partial frame is dropped, @w ≤ 0@ yields the
-- empty volume. The QuickCheck-friendly constructor.
volumeQ16 :: Int -> [Integer] -> [[Integer]]
volumeQ16 w xs
  | w <= 0    = []
  | otherwise = go xs
  where
    go ys = case splitAt w ys of
      (fr, rest) | length fr == w -> fr : go rest
                 | otherwise      -> []

-- | THE INTEGRAL FRAME of group @j@ at detent @k@: per voxel, the Integer SUM
-- over the aligned window 'groupFrames' of Q16 OKLab values, then ONE
-- 'divRoundHalfUp' by @2^k@ — sums are the transitive carrier, the divide
-- happens once at the display boundary, and the divisor is the FRAME count
-- @2^k@ ('SixFour.Spec.ColorTimeDisplay.framesPerRealize'), NEVER the spatial
-- ride-along @8^k@ ('lawIntegralIsSumsDividedOnce'). Frames or voxels outside
-- the volume read 0 (totality); the voxel width is frame 0's.
integralQ16 :: Int -> Int -> [[Integer]] -> [Integer]
integralQ16 kRaw j vol =
  [ divRoundHalfUp (sum [ at f v | f <- groupFrames j k ]) (2 ^ k)
  | v <- [0 .. nVox - 1] ]
  where
    k    = min 2 (max 0 kRaw)
    nVox = case vol of { [] -> 0; (f0 : _) -> length f0 }
    at f v
      | f < 0 || f >= length vol = 0
      | otherwise = let fr = vol !! f
                    in if v < length fr then fr !! v else 0

-- ─────────────────────────────────────────────────────────────────────────────
-- The slide's word contribution
-- ─────────────────────────────────────────────────────────────────────────────

-- | The game ops a detent transition (from detent @kFrom@ to @kTo@)
-- contributes to THE MERGE's decision word: NONE, EVER — the slide re-times
-- the display, it never plays the board. Pinned as the empty list so
-- 'lawSlideNeverWritesTheWord' is a theorem, not a comment.
slideOps :: Int -> Int -> [GameOp]
slideOps _ _ = []

-- ─────────────────────────────────────────────────────────────────────────────
-- The cross-language goldens
-- ─────────────────────────────────────────────────────────────────────────────

-- | The 16-tick playhead golden: per detent @k ∈ {0,1,2}@ and tick
-- @t ∈ [0..15]@ (anchor tick 0, anchor frame 0) —
-- @(k, t, playhead frame, display group, realizes?)@. The Swift twin mirrors
-- this table VERBATIM; its realize gating is that of
-- 'SixFour.Spec.ColorTimeDisplay.goldenSchedule16', keyed by detent.
goldenPlayhead16 :: [(Int, Int, Int, Int, Bool)]
goldenPlayhead16 =
  [ (k, t, pos 0 0 t, displayGroup k 0 0 t, realizesAt (rungAt k) t)
  | k <- [0 .. 2], t <- [0 .. 15] ]

-- | The golden integral volume: 4 frames × 12 voxels (2×2 spatial × 3
-- channels, channel-interleaved) with NEGATIVE a\/b entries throughout — the
-- rounding vectors a truncating port trips on.
goldenVolumeQ16 :: [[Integer]]
goldenVolumeQ16 =
  [ [ 4, -3, 2, -5, 0,  7, 1, -1, 6, -6, 3, -2]
  , [ 6, -4, 1, -5, 1,  8, 2, -2, 5, -7, 4, -3]
  , [ 5, -6, 3, -4, 2,  9, 3, -3, 4, -8, 5, -4]
  , [ 7, -5, 4, -6, 3, 10, 4, -4, 3, -9, 6, -5]
  ]

-- | The golden integral frames of 'goldenVolumeQ16' per detent: @(k, groups)@
-- for @k ∈ {0,1,2}@ — 4 identity frames at k=0, 2 pair-integrals at k=1, 1
-- whole-window integral at k=2. The literal expected values are pinned in the
-- property battery; the Swift twin mirrors them byte-for-byte.
goldenIntegralQ16 :: [(Int, [[Integer]])]
goldenIntegralQ16 =
  [ (k, [ integralQ16 k j goldenVolumeQ16
        | j <- [0 .. (length goldenVolumeQ16 `div` periodOf k) - 1] ])
  | k <- [0 .. 2] ]

-- ─────────────────────────────────────────────────────────────────────────────
-- Laws
-- ─────────────────────────────────────────────────────────────────────────────

-- | The quantizer is TOTAL: every latch\/travel pair lands in @{0,1,2}@ — no
-- slide input can name a rung the ladder does not have.
lawDetentTotal :: Int -> Int -> Bool
lawDetentTotal k dy = let d = detentOf k dy in d >= 0 && d <= 2

-- | The quantizer is MONOTONE in travel: more downward travel never yields a
-- finer detent (floor division and clamping both preserve order).
lawDetentMonotone :: Int -> Int -> Int -> Bool
lawDetentMonotone k dy1 dy2 =
  dy1 > dy2 || detentOf k dy1 <= detentOf k dy2

-- | The endpoints: zero travel holds the (clamped) latch detent; one
-- 'cellsPerDetent' of travel moves exactly one rung from the middle; far
-- travel clamps to the rails.
lawDetentEndpoints :: Int -> Bool
lawDetentEndpoints k =
     detentOf k 0 == min 2 (max 0 k)
  && detentOf 1 cellsPerDetent == 2
  && detentOf 1 (negate cellsPerDetent) == 0
  && detentOf 0 (10 * cellsPerDetent) == 2
  && detentOf 2 (negate (10 * cellsPerDetent)) == 0

-- | DETENTS ARE RUNGS: the playback periods are exactly @{1,2,4}@ ticks (the
-- 'SixFour.Spec.WeaveOrder.unitsOf' ladder), every period tiles the 64-tick
-- window — and the seductive 3-tick delay is REFUSED: @64 mod 3 ≠ 0@, a
-- uniform 3-tick cadence cannot tile 'windowUnits' (off-ladder dilation is a
-- different, honestly-labelled mechanic, never a detent).
lawDetentsAreRungs :: Bool
lawDetentsAreRungs =
     map periodOf [0, 1, 2] == [1, 2, 4]
  && and [ windowUnits `mod` periodOf k == 0 | k <- [0 .. 2] ]
  && windowUnits `mod` 3 /= 0

-- | The display group STEPS exactly on the realize ticks: with the anchor
-- frame snapped to a group boundary (the latch convention), the group at
-- detent @k@ changes between consecutive ticks iff
-- 'SixFour.Spec.ColorTimeDisplay.realizesAt' fires on the tick offset from
-- the anchor — the hero's bake gate IS the spec's realize gate.
lawGroupChangesExactlyOnRealize :: Int -> Int -> Int -> Int -> Bool
lawGroupChangesExactlyOnRealize kRaw aTickRaw aFrameRaw tRaw =
  let k  = abs kRaw `mod` 3
      p  = periodOf k
      aT = abs aTickRaw
      aF = p * (abs aFrameRaw `mod` (windowUnits `div` p))
      t  = aT + 1 + abs tRaw
      stepped = displayGroup k aT aF t /= displayGroup k aT aF (t - 1)
  in stepped == realizesAt (rungAt k) (t - aT)

-- | KEYSTONE CONVENTION PIN — the group window IS the poured window: group
-- @j@'s 0-based frames, shifted to 1-based tick bookkeeping (@+1@), are
-- EXACTLY 'pouredWindow' at the realize tick @r = (j+1)·2^k@ — the window
-- ENDS at the realize tick, @r ≥ 2^k@ so the negative-tick edge of
-- @lawPourWindowExact@'s @r = 0@ is never touched, and the group's last frame
-- is 'groupEndFrame'. A 0-based port that read the window as STARTING at the
-- realize tick would ship the 32\/16 detents one frame off @goldenSchedule16@;
-- this law is the off-by-one killer.
lawGroupWindowIsPouredWindow :: Int -> Int -> Bool
lawGroupWindowIsPouredWindow kRaw jRaw =
  let k = abs kRaw `mod` 3
      p = periodOf k
      j = abs jRaw `mod` (windowUnits `div` p)
      r = (j + 1) * p
  in map (+ 1) (groupFrames j k) == pouredWindow (rungAt k) r
     && realizesAt (rungAt k) r
     && last (groupFrames j k) == groupEndFrame j k
     && r >= p

-- | The fine detent's integral is the IDENTITY: at k=0 every group is one
-- frame and 'divRoundHalfUp' by 1 changes nothing — the 64-rung playback
-- shows the frames untouched.
lawIntegralFineIsIdentity :: Int -> Int -> [Integer] -> Bool
lawIntegralFineIsIdentity wRaw jRaw flat =
  let w   = 1 + abs wRaw `mod` 8
      vol = volumeQ16 w flat
  in null vol
     || (let j = abs jRaw `mod` length vol
         in integralQ16 0 j vol == vol !! j)

-- | SUMS COMPOSE, DIVIDE ONCE, AND BY THE RIGHT DIVISOR: a pooled detent's
-- integral equals the round-half-up of the window sum assembled from HALF-
-- window subsums ('SixFour.Spec.ColorTime' @lawSumsCompose@ on this carrier —
-- means of means never appear), the divisor is the frame count @2^k@
-- ('SixFour.Spec.ColorTimeDisplay.framesPerRealize'), a constant window
-- realizes to its constant — and the spatial ride-along divisor @8^k@
-- ('SixFour.Spec.ColorTimeDisplay.realizeSamples') is the WRONG one here:
-- applying it to a constant-5 window does not return 5. Temporal and spatial
-- divisors must never double-divide.
lawIntegralIsSumsDividedOnce :: Int -> Int -> [Integer] -> Bool
lawIntegralIsSumsDividedOnce kRaw jRaw flat =
  let k = 1 + abs kRaw `mod` 2
      p = periodOf k
      w = 4
      j = abs jRaw `mod` 2
      vol = volumeQ16 w (flat ++ replicate (w * p * (j + 1)) 3)
      (h1, h2) = splitAt (p `div` 2) (groupFrames j k)
      subSum h v = sum [ (vol !! f) !! v | f <- h ]
      cvol = replicate (p * (j + 1)) (replicate w 5)
  in integralQ16 k j vol
       == [ divRoundHalfUp (subSum h1 v + subSum h2 v) (toInteger p)
          | v <- [0 .. w - 1] ]
     && integralQ16 k j cvol == replicate w 5
     && divRoundHalfUp (5 * toInteger p) (8 ^ k) /= 5

-- | WALL TIME IS INVARIANT: at every detent the loop shows
-- @'windowUnits' \/ 2^k@ integral frames of @'delayCsOf'@ = @5·2^k@ cs each —
-- exactly 'windowCs' = 320 cs, always
-- ('SixFour.Spec.WeaveOrder.lawWeaveColorTimeConserved' made
-- display-visible). "Slower" is chunkier 4-frame holds at the SAME loop
-- length, never a longer loop; true slow motion would be off-ladder dilation
-- and is deliberately not a detent.
lawLoopWallTimeInvariant :: Bool
lawLoopWallTimeInvariant =
  and [ (windowUnits `div` periodOf k) * delayCsOf (rungAt k) == windowCs
      | k <- [0 .. 2] ]
    && windowCs == 320

-- | The negative-operand vectors, pinned: halves round toward +∞ on BOTH
-- signs, the specific vector @divRoundHalfUp (−5) 4 = −1@ separates floor
-- ('div') from truncation ('quot' — a truncating port answers 0), and plain
-- floor division is NOT round-half-up (@−3 \`div\` 2 = −2 ≠ −1@). These are
-- the exact bytes the Swift twin's negative Q16 a\/b channels ride on.
lawDivRoundHalfUpNegatives :: Bool
lawDivRoundHalfUpNegatives =
     map (`divRoundHalfUp` 2) [-3, -1, 1, 3] == [-1, 0, 1, 2]
  && map (`divRoundHalfUp` 4) [-7, -6, -5, -2, 2, 5, 6, 7]
       == [-2, -1, -1, 0, 1, 1, 2, 2]
  && divRoundHalfUp (-5) 4 == -1
  && (-3 :: Integer) `div` 2 == -2
  && divRoundHalfUp (-3) 2 == -1

-- | THE SLIDE NEVER WRITES THE WORD: no detent\/playhead transition yields a
-- game op ('slideOps' is empty for every pair), so appending a slide's
-- contribution to any op list replays to the SAME board — the display
-- mechanic is invisible to 'SixFour.Spec.MergeBoard.lawWordReplaysBoard' and
-- to the @.s4cr@ @dw@ key.
lawSlideNeverWritesTheWord :: Int -> Int -> [GameOp] -> Bool
lawSlideNeverWritesTheWord kFrom kTo ops =
  null (slideOps kFrom kTo)
    && playAll (ops ++ slideOps kFrom kTo) == playAll ops

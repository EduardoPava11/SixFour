{- |
Module      : SixFour.Spec.ColorTimeDisplay
Description : The cadence-honest display beat — the 4:2:1 rung refresh, the intake
              tallies, and the banked capture ledger, all derived from ONE 20 Hz tick.

THE POUR (docs/UI-FORM-FOLLOWS-FUNCTION.md, THE DESIGN D0–D2/E7): the live pyramid must
SHOW the ladder's real time law — one 16² frame integrates the light of FOUR consecutive
64² frames (same total photons, coarser space, 4× the time). This module pins the exact
integer schedule the UI animates, so every cadence the surface beats at is a THEOREM of
the ladder, never a free animation constant:

  * __The one clock__: all timing derives from the 20 Hz @SurfaceClock.tick@
    (1 tick = 1 weave unit = 5 cs, 'SixFour.Spec.WeaveOrder' base delay). No second
    timer exists in this module's vocabulary — every function takes THE tick.
  * __Display cadence__ ('displayPeriodTicks' / 'realizesAt'): a rung's display
    refresh period is its 'SixFour.Spec.WeaveOrder.unitsOf' =
    'SixFour.Spec.ColorTime.poolDepth' — 64\@20 Hz \/ 32\@10 Hz \/ 16\@5 Hz
    ('lawDisplayCadenceIsPoolDepth'). The coarse tiles realize as TRUE temporal
    integrals: u64 accumulators divide ONCE at the display boundary by
    'realizeSamples' (1 : 8 : 64 per-voxel samples, 'lawRealizeSamplesLadder').
  * __The gathering beat__ ('tallySlots' / 'tallySlot' / 'pouredWindow'): the intake
    tallies make the 4-into-1 pour COUNTABLE — slot counts equal 'unitsOf' (rail
    lengths are NOT free constants, 'lawTallyEqualsUnits'), each period's ticks fill
    every slot exactly once ('lawTallyCyclicCover'), and the window poured at a
    realize tick is exactly the 'framesPerRealize' ticks that closed it
    ('lawPourWindowExact').
  * __The banked ledger__ ('ledgerCells' / 'ledgerFillCount' / 'bankedWindowCs'):
    during capture the 16² shutter fills as an EXACT function of banked frames, never
    float progress — frame n owns raster cells @[4(n−1) .. 4n−1]@, 64 frames × 4
    cells = 256 partitions the tile ('lawLedgerConserves', the
    'SixFour.Spec.WeaveOrder' block arithmetic drawn live), each landed frame banks
    exactly 5 cs of window ('lawBankedWindowExact', the \"160\/320cs\" overlay).
  * __The flux quantizer__ ('fluxFillCount'): the 16×1 flux bar's lit-cell count is
    the log₂ magnitude of the per-cadence palette-W1 impulse
    ('SixFour.Spec.ColorMomentum' flux) — integer bit-length, clamped, monotone
    ('lawFluxMonotoneBounded'), so the bar rebakes only when the integer count steps.

'goldenSchedule16' is the 16-tick cross-language schedule vector (realize flags + tally
slots per tick) the Swift port re-derives — the D6 golden the UI's cadence gating is
tested against.

GHC-boot-only: base, plus "SixFour.Spec.WeaveOrder" \/ "SixFour.Spec.ColorTime".
-}
-- COMPARTMENT: SWIFT-COREAI | tag:DisplaySide
module SixFour.Spec.ColorTimeDisplay
  ( -- * The one clock
    Tick
  , displayPeriodTicks
  , realizesAt
    -- * The temporal integral (divide once, at the display boundary)
  , framesPerRealize
  , realizeSamples
    -- * The gathering beat — intake tallies (the pour made countable)
  , tallySlots
  , tallySlot
  , pouredWindow
    -- * The banked capture ledger (the shutter fill, exact)
  , burstFrames
  , ledgerCellsPerFrame
  , ledgerCells
  , ledgerFillCount
  , bankedWindowCs
    -- * The flux-bar quantizer
  , fluxBarCells
  , fluxFillCount
    -- * The golden cross-language schedule
  , goldenSchedule16
    -- * Laws
  , lawDisplayCadenceIsPoolDepth
  , lawRealizeSamplesLadder
  , lawTallyEqualsUnits
  , lawTallyCyclicCover
  , lawPourWindowExact
  , lawLedgerConserves
  , lawLedgerStepExact
  , lawBankedWindowExact
  , lawFluxMonotoneBounded
  ) where

import Data.List (sort)

import SixFour.Spec.ColorTime (poolDepth)
import SixFour.Spec.WeaveOrder
  ( WeaveRung (..), rungIndex, sideOf, unitsOf, delayCsOf, windowUnits, windowCs )

-- | A surface-clock tick — the ONE 20 Hz counter (@SurfaceClock.tick@) every display
-- cadence derives from. 1 tick = 1 weave unit = 5 cs ('SixFour.Spec.WeaveOrder').
-- A bare 'Int' (the same 'Int' the Swift clock publishes; a newtype would only churn
-- the goldens) — the alias is documentation.
type Tick = Int

-- ─────────────────────────────────────────────────────────────────────────────
-- The one clock — display cadence
-- ─────────────────────────────────────────────────────────────────────────────

-- | A rung's display refresh period in ticks: 'unitsOf' (= 2^k = 'poolDepth') — the
-- 64² repaints every tick (20 Hz), the 32² every 2 (10 Hz), the 16² every 4 (5 Hz).
-- DELEGATION, not a constant: the UI cadence and the GIF89a delay ladder are the
-- same integer ('lawDisplayCadenceIsPoolDepth').
displayPeriodTicks :: WeaveRung -> Int
displayPeriodTicks = unitsOf

-- | True iff rung @p@ realizes (swaps its whole tile) at tick @t@: @t ≡ 0@ (mod
-- 'displayPeriodTicks'). Crisp whole-tile swaps at the rung's native cadence — the
-- accumulator divides here and only here (sums are the transitive carrier; means
-- never compose).
realizesAt :: WeaveRung -> Tick -> Bool
realizesAt p t = t `mod` displayPeriodTicks p == 0

-- ─────────────────────────────────────────────────────────────────────────────
-- The temporal integral — what one realize banks
-- ─────────────────────────────────────────────────────────────────────────────

-- | How many fine (64²) frames one rung-@p@ realize integrates: 'unitsOf' — the
-- gathering-beat frame count. Four 64-ticks pour into one 16² update; two into one
-- 32² update; the 64² is itself (Daniel's equivalence, made exact).
framesPerRealize :: WeaveRung -> Int
framesPerRealize = unitsOf

-- | The u64-accumulator divisor at a rung's realize: samples per coarse voxel =
-- spatial pool area × frames = @(2^k)² · 2^k = 8^k@ — the 1 : 8 : 64 per-voxel-
-- samples ladder ('lawRealizeSamplesLadder', the √N significance story's other
-- face). ONE divide, at the display boundary.
realizeSamples :: WeaveRung -> Int
realizeSamples p = framesPerRealize p * unitsOf p * unitsOf p

-- ─────────────────────────────────────────────────────────────────────────────
-- The gathering beat — intake tallies
-- ─────────────────────────────────────────────────────────────────────────────

-- | The number of intake-tally slots a rung's gutter rail carries: 'unitsOf' —
-- 2 slots over the 32², 4 over the 16². Pinned by 'lawTallyEqualsUnits' so the rail
-- lengths can never drift from the pool depths they teach.
tallySlots :: WeaveRung -> Int
tallySlots = unitsOf

-- | Which tally slot tick @t@ fills: @t@ mod 'tallySlots'. Every tick inks one slot
-- with that frame's DC (the 'SixFour.Spec.ColorMomentum' mass band); on the realize
-- tick the filled slots flash and pour into the coarse swap.
tallySlot :: WeaveRung -> Tick -> Int
tallySlot p t = t `mod` tallySlots p

-- | The ticks whose frames pour at realize tick @r@: the 'framesPerRealize' ticks
-- ENDING at @r@ (@[r−n+1 .. r]@). Only meaningful when @'realizesAt' p r@; the pour
-- window closes on slot 0 ('lawPourWindowExact').
pouredWindow :: WeaveRung -> Tick -> [Tick]
pouredWindow p r = [r - framesPerRealize p + 1 .. r]

-- ─────────────────────────────────────────────────────────────────────────────
-- The banked capture ledger — the shutter fill as exact block arithmetic
-- ─────────────────────────────────────────────────────────────────────────────

-- | The burst length in frames (= ticks = weave units): 64
-- ('SixFour.Spec.WeaveOrder.windowUnits').
burstFrames :: Int
burstFrames = windowUnits

-- | Raster cells of the 16² ledger each landed frame owns permanently: 4 —
-- BOTH @16²\/64@ (the tile split evenly over the burst) AND 'unitsOf' 'W16' (the
-- coarse rung's pool depth); 'lawLedgerConserves' proves the two derivations agree.
ledgerCellsPerFrame :: Int
ledgerCellsPerFrame = sideOf W16 * sideOf W16 `div` burstFrames

-- | The 16² raster cells landed frame @n@ (1-based) takes, permanently:
-- @[4(n−1) .. 4n−1]@ — each 4-cell strip is a genuine time-woven sample, 5 cs apart.
ledgerCells :: Int -> [Int]
ledgerCells n = [ ledgerCellsPerFrame * (n - 1) .. ledgerCellsPerFrame * n - 1 ]

-- | Filled ledger cells after @landed@ frames — the shutter fill as an EXACT function
-- of banked frames (never float progress), clamped to the burst: @4·landed@, 256 at
-- the full 64 ('lawLedgerStepExact').
ledgerFillCount :: Int -> Int
ledgerFillCount landed = ledgerCellsPerFrame * min burstFrames (max 0 landed)

-- | The banked window in centiseconds after @landed@ frames: @5·landed@ (each fine
-- frame banks one 'delayCsOf' 'W64' quantum) — the transient \"160\/320cs\" burst
-- overlay, stepping 5 cs per landed frame to 'windowCs' = 320
-- ('lawBankedWindowExact').
bankedWindowCs :: Int -> Int
bankedWindowCs landed = delayCsOf W64 * min burstFrames (max 0 landed)

-- ─────────────────────────────────────────────────────────────────────────────
-- The flux-bar quantizer — the single-number wave meter
-- ─────────────────────────────────────────────────────────────────────────────

-- | The flux bar's cell count: 16 (= 'sideOf' 'W16' — the bar sits under the 16²
-- shutter at its width).
fluxBarCells :: Int
fluxBarCells = sideOf W16

-- | Lit flux-bar cells for a per-cadence palette-W1 impulse @w@: the integer
-- bit-length of @w@ (log₂ scaling — @w ∈ [2^(c−1), 2^c)@ lights @c@ cells), clamped
-- to 'fluxBarCells'; 0 (or a nil GCT feed) renders all-ghost. Integer-exact so the
-- bar rebakes only when the count steps ('lawFluxMonotoneBounded').
fluxFillCount :: Int -> Int
fluxFillCount w = min fluxBarCells (bitLen (max 0 w))
  where
    bitLen :: Int -> Int
    bitLen 0 = 0
    bitLen n = 1 + bitLen (n `div` 2)

-- ─────────────────────────────────────────────────────────────────────────────
-- The golden cross-language schedule
-- ─────────────────────────────────────────────────────────────────────────────

-- | The 16-tick golden schedule (D6): per tick @t ∈ [0..15]@ —
-- @(t, realizesAt W32 t, realizesAt W16 t, tallySlot W32 t, tallySlot W16 t)@.
-- Mirrored into a Swift test so the UI's cadence gating (the mod-2\/mod-4 realize,
-- the tally raster) is pinned byte-for-byte against this vector.
goldenSchedule16 :: [(Int, Bool, Bool, Int, Int)]
goldenSchedule16 =
  [ (t, realizesAt W32 t, realizesAt W16 t, tallySlot W32 t, tallySlot W16 t)
  | t <- [0 .. 15] ]

-- ─────────────────────────────────────────────────────────────────────────────
-- Laws
-- ─────────────────────────────────────────────────────────────────────────────

-- | THE CADENCE LAW — a rung's display refresh period IS its pool depth: for every
-- rung, 'displayPeriodTicks' equals 'SixFour.Spec.ColorTime.poolDepth' of its index,
-- the ladder is pinned at @[1,2,4]@ (64\@20 Hz \/ 32\@10 Hz \/ 16\@5 Hz), tick 0
-- realizes every rung (the aligned start), and a rung realizes exactly on the
-- multiples of its period. A sample-and-hold that latched at any other period — or a
-- \"smoother\" refresh — breaks this law.
lawDisplayCadenceIsPoolDepth :: WeaveRung -> Tick -> Bool
lawDisplayCadenceIsPoolDepth p t =
     displayPeriodTicks p == fromInteger (poolDepth (rungIndex p))
  && map displayPeriodTicks [W64, W32, W16] == [1, 2, 4]
  && realizesAt p 0
  && realizesAt p t == (t `mod` displayPeriodTicks p == 0)

-- | The per-realize divisor ladder: 'realizeSamples' = frames × spatial pool area =
-- @('unitsOf')³@, pinned at 1 : 8 : 64 — the per-voxel-samples equivalence the intake
-- tallies corroborate (and the √N bars' other face). The 32² realize divides by 8
-- (4 px · 2 frames), the 16² by 64 (16 px · 4 frames), exactly as THE DESIGN E1.
lawRealizeSamplesLadder :: Bool
lawRealizeSamplesLadder =
     map realizeSamples [W64, W32, W16] == [1, 8, 64]
  && and [ realizeSamples p == unitsOf p ^ (3 :: Int) | p <- [W64, W32, W16] ]

-- | TALLY = UNITS — the intake rail's slot count equals the rung's weave units
-- ('lawTallyEqualsUnits' of D1): 2 slots over the 32², 4 over the 16². Rail lengths
-- are theorems of the ladder, never free layout constants.
lawTallyEqualsUnits :: Bool
lawTallyEqualsUnits =
     and [ tallySlots p == unitsOf p | p <- [W64, W32, W16] ]
  && (tallySlots W32, tallySlots W16) == (2, 4)

-- | CYCLIC COVER — from ANY start tick, one full period's ticks fill every slot
-- exactly once (no slot starved, none double-inked), and a realize tick always
-- carries slot 0 (the fresh window opens where the pour closed). A tally that
-- skipped or repeated a slot would break the count the user is being taught.
lawTallyCyclicCover :: WeaveRung -> Tick -> Bool
lawTallyCyclicCover p t =
  let n = tallySlots p
  in sort [ tallySlot p (t + i) | i <- [0 .. n - 1] ] == [0 .. n - 1]
     && (not (realizesAt p t) || tallySlot p t == 0)

-- | THE POUR — at an (aligned) realize tick @r = m·n@ the poured window is exactly
-- the 'framesPerRealize' ticks that closed it, it ends AT the realize tick, and its
-- slot walk is @[1, 2, …, n−1, 0]@ — the rail fills left to right and the realize
-- tick itself lands the last (zeroth) slot, so fill-4 → flash → pour is one exact
-- integer story.
lawPourWindowExact :: WeaveRung -> Int -> Bool
lawPourWindowExact p m =
  let n = framesPerRealize p
      r = m * n                                  -- an aligned realize tick
      w = pouredWindow p r
  in realizesAt p r
     && length w == n
     && last w == r
     && map (tallySlot p) w == ([1 .. n - 1] ++ [0])

-- | LEDGER CONSERVATION — 64 frames × 4 cells = 256 = the whole 16² tile, the two
-- derivations of 'ledgerCellsPerFrame' agree (@16²\/64@ == 'unitsOf' 'W16' — the
-- WeaveOrder block arithmetic drawn live), and the per-frame cell ranges PARTITION
-- @[0..255]@ in order: every raster cell is owned by exactly one landed frame.
lawLedgerConserves :: Bool
lawLedgerConserves =
     burstFrames * ledgerCellsPerFrame == sideOf W16 * sideOf W16
  && ledgerCellsPerFrame == unitsOf W16
  && concatMap ledgerCells [1 .. burstFrames] == [0 .. sideOf W16 * sideOf W16 - 1]

-- | LEDGER STEP — the shutter fill is exact and monotone: empty at 0, full (256) at
-- ≥ 64, each landed frame in the burst adds EXACTLY 'ledgerCellsPerFrame' cells, and
-- out-of-range inputs clamp (a re-entrant callback can never overfill the tile).
lawLedgerStepExact :: Int -> Bool
lawLedgerStepExact n =
     ledgerFillCount 0 == 0
  && ledgerFillCount burstFrames == sideOf W16 * sideOf W16
  && (n < 1 || n > burstFrames
       || ledgerFillCount n - ledgerFillCount (n - 1) == ledgerCellsPerFrame)
  && ledgerFillCount n >= 0
  && ledgerFillCount n <= sideOf W16 * sideOf W16

-- | BANKED WINDOW — each landed frame banks one 5 cs quantum ('delayCsOf' 'W64');
-- the full burst banks exactly 'windowCs' = 320 cs. The \"160\/320cs\" overlay is a
-- readout of this function, never an animation.
lawBankedWindowExact :: Int -> Bool
lawBankedWindowExact n =
     bankedWindowCs n == delayCsOf W64 * min burstFrames (max 0 n)
  && bankedWindowCs burstFrames == windowCs
  && bankedWindowCs 32 == 160

-- | FLUX QUANTIZER — the bar is bounded (@0 ≤ fill ≤ 16@), zero exactly at zero
-- impulse, MONOTONE in the impulse (more flux never shows fewer cells), and log₂:
-- doubling the impulse lights at most one more cell. So the bar is an honest,
-- step-rebaked magnitude meter.
lawFluxMonotoneBounded :: Int -> Int -> Bool
lawFluxMonotoneBounded w1 w2 =
  let a = min w1 w2
      b = max w1 w2
  in fluxFillCount a >= 0
     && fluxFillCount b <= fluxBarCells
     && fluxFillCount 0 == 0
     && fluxFillCount 1 == 1
     && fluxFillCount a <= fluxFillCount b
     && (a < 0 || fluxFillCount (2 * a) <= fluxFillCount a + 1)

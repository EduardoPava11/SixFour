{- |
Module      : SixFour.Spec.CellMechanics
Description : The grid-cell INTERACTION algebra — a widget's lifetime, haptics, and
              reactive (color/pulse) feedback, as pure golden-pinned math.

"SixFour.Spec.MovableLayout" owns a widget's GEOMETRY (footprint, dock, and the proven
disjoint 'move'). This module owns its __MECHANICS__: how an interaction lives and dies,
what the user FEELS (haptics) and SEES (color + pulse) as they touch, hold, and drag a
big cell. It adds NO geometry authority — the drop verdict is closed over 'move', so the
on-screen feedback can never disagree with what the move operator actually does
('lawDropColorMatchesMove'); this is the green-frame correctness, lifted into a law.

Everything here is INTEGER and PURE so it ports to Swift byte-for-byte (the impure leaves
— playing a haptic, animating a tint — are Swift-side effects DRIVEN by the tokens this
module emits, exactly like 'SixFour.Spec.Display' events drive the surface). Continuous
touch lives in points on device; the boundary converts points→cells (the lattice atom),
and from there every decision in this module is over whole cells.

== The lifetime (the interaction FSM)

@Resting → Pressed → Lifted → Settling → Resting@. 'gestureStep' is total
('lawGestureTotal'); every phase is reachable ('lawGestureNoOrphan'); and crucially you
__cannot reach 'Lifted' (drag) without passing 'HoldElapsed'__ ('lawDragRequiresHold'),
so a clean TAP (a fast 'TouchUp' from 'Pressed') never lifts and never fires a burst —
the structural guarantee the @.exclusively(before:)@ gesture only approximates.

== The detent (why cells are BIG)

Big cells give the user precision: each cell boundary the lifted widget crosses is ONE
felt 'CellTick'. 'cellsCrossed' counts those boundaries, and 'lawTickConservation' proves
a unit drag fires EXACTLY that many ticks (no miss, no double) — the drag is detented to
the lattice, so "how far did I drag" is legible by feel, not just sight.

== The reactive feedback

While lifted, the widget breathes: 'reactivePulse' picks a 'PulseSpec' from the live drop
verdict + how far the finger has travelled (farther ⇒ faster, 'lawReactiveFaster'), and
'pulseSampleQ16' is a portable integer triangle wave the renderer samples per frame to
lerp the cell tint between its base and the verdict accent ('verdictInk' / 'tintLerpQ16').
Accept = a calm green breath; reject = an urgent red flit.

GHC-boot-only: base, containers, plus "SixFour.Spec.MovableLayout".
-}
module SixFour.Spec.CellMechanics
  ( -- * The interaction lifetime (FSM)
    GesturePhase(..), GestureEvent(..)
  , allPhases, allEvents
  , gestureStep, producesTap
  , phaseName, eventName
    -- * Haptics (the closed token alphabet)
  , Haptic(..), allHaptics, hapticName
  , hapticOnTransition
    -- * The detent (cell-crossing ticks)
  , cellsCrossed, tickPath
    -- * The drop verdict (closed over the proven move)
  , DropVerdict(..), dropVerdict, verdictName, verdictInk
    -- * Reactive color + pulse
  , PulseSpec(..), q16One, pulseSampleQ16
  , reactivePulse, tintLerpQ16
    -- * Per-widget mechanics
  , Mechanics(..), mechanicsFor
    -- * The golden cross-language trace
  , goldenGesture, goldenPhaseTrace, goldenHaptics
  , goldenPulse, goldenDragMag
    -- * Laws
  , lawGestureTotal
  , lawGestureNoOrphan
  , lawDragRequiresHold
  , lawTapIsFastRelease
  , lawSettleReturnsResting
  , lawTickConservation
  , lawTickSymmetric
  , lawDropColorMatchesMove
  , lawPulseBounded
  , lawPulsePeriodic
  , lawReactiveFaster
  ) where

import Data.List (nub)

import SixFour.Spec.MovableLayout
  ( ColorIdentity(..), allIdentities, Placement, move )

-- =============================================================================
-- The interaction lifetime — the FSM (Σ = GesturePhase)
-- =============================================================================

-- | The phases of ONE interaction with a movable cell. This is the "lifetime" the
-- author declares per widget: how a touch becomes a lift becomes a drag becomes a drop.
--
--   * 'Resting'  — no touch; the widget sits docked.
--   * 'Pressed'  — finger down, the hold timer is running; NOT yet liftable. A fast
--                  release here is a TAP ('producesTap'), not a move.
--   * 'Lifted'   — the hold elapsed; the widget is grabbed and tracks the finger.
--   * 'Settling' — finger up; the widget animates to its snapped (or snapped-back) cell.
data GesturePhase = Resting | Pressed | Lifted | Settling
  deriving (Eq, Ord, Enum, Bounded, Show)

-- | The transition triggers. Out-of-band data (the live drag offset in cells, the drop
-- verdict) is carried by the renderer, never the alphabet — so 'gestureStep' stays a
-- tiny total function (the 'SixFour.Spec.Display' discipline).
data GestureEvent
  = TouchDown    -- ^ finger contacts the cell
  | HoldElapsed  -- ^ the long-press duration ('mcHoldTicks') passed: arm the lift
  | Drag         -- ^ a movement sample while lifted (magnitude is out-of-band)
  | TouchUp      -- ^ finger lifted
  | SettleDone   -- ^ the snap animation finished
  | Cancel       -- ^ the system cancelled the gesture (e.g. a phone call)
  deriving (Eq, Ord, Enum, Bounded, Show)

-- | Every 'GesturePhase', in 'Enum' order (for totality checks and table generation).
allPhases :: [GesturePhase]
allPhases = [minBound .. maxBound]

-- | Every 'GestureEvent', in 'Enum' order.
allEvents :: [GestureEvent]
allEvents = [minBound .. maxBound]

-- | @δ@ — the TOTAL interaction transition ('lawGestureTotal'). Unhandled (phase,event)
-- pairs are self-loops, so it is defined everywhere with no ⊥. The hold gate
-- ('Pressed' --'HoldElapsed'--> 'Lifted') is the ONLY door into 'Lifted', which is what
-- makes tap and drag disjoint ('lawDragRequiresHold').
gestureStep :: GesturePhase -> GestureEvent -> GesturePhase
gestureStep ph ev = case (ph, ev) of
  (Resting,  TouchDown)   -> Pressed
  (Pressed,  HoldElapsed) -> Lifted
  (Pressed,  TouchUp)     -> Resting     -- a clean TAP — no lift (producesTap)
  (Pressed,  Cancel)      -> Resting
  (Lifted,   Drag)        -> Lifted       -- track the finger (offset accrues out-of-band)
  (Lifted,   TouchUp)     -> Settling      -- commit: snap to the dropped cell (or back)
  (Lifted,   Cancel)      -> Settling      -- snap back
  (Settling, SettleDone)  -> Resting
  (Settling, Cancel)      -> Resting
  _                       -> ph            -- TOTAL: ignore irrelevant events

-- | True iff this transition is a clean TAP — a fast release from 'Pressed' before the
-- hold armed the lift. The renderer fires the widget's tap action (e.g. the shutter)
-- here, and ONLY here, so a long-press→drag never triggers it.
producesTap :: GesturePhase -> GestureEvent -> Bool
producesTap Pressed TouchUp = True
producesTap _       _       = False

-- | Stable cross-language phase token (the Swift port must use these exact strings).
phaseName :: GesturePhase -> String
phaseName Resting  = "resting"
phaseName Pressed  = "pressed"
phaseName Lifted   = "lifted"
phaseName Settling = "settling"

-- | Stable cross-language event token.
eventName :: GestureEvent -> String
eventName TouchDown   = "touchDown"
eventName HoldElapsed = "holdElapsed"
eventName Drag        = "drag"
eventName TouchUp     = "touchUp"
eventName SettleDone  = "settleDone"
eventName Cancel      = "cancel"

-- =============================================================================
-- Haptics — the closed token alphabet (effects are Swift-side, driven by these)
-- =============================================================================

-- | The closed set of haptic INTENTS. The spec decides WHEN each fires; the Swift
-- @Haptics@ enum maps the token to a concrete @UIFeedbackGenerator@ (the only impure
-- leaf). Closed ⇒ adding a feel is a spec edit, never a free call site.
data Haptic
  = LiftPop     -- ^ Pressed→Lifted: "you've grabbed it" (medium impact)
  | CellTick    -- ^ each cell boundary crossed while lifted (selection tick — the detent)
  | EdgeStop    -- ^ a drag clamped at the lattice edge (rigid impact)
  | DropAccept  -- ^ Lifted→Settling onto a valid cell (success notification)
  | DropReject  -- ^ Lifted→Settling that snaps back (error notification)
  deriving (Eq, Ord, Enum, Bounded, Show)

-- | Every 'Haptic', in 'Enum' order.
allHaptics :: [Haptic]
allHaptics = [minBound .. maxBound]

-- | The stable string name of a 'Haptic' (the key the Swift haptic layer dispatches on).
hapticName :: Haptic -> String
hapticName LiftPop    = "liftPop"
hapticName CellTick   = "cellTick"
hapticName EdgeStop   = "edgeStop"
hapticName DropAccept = "dropAccept"
hapticName DropReject = "dropReject"

-- | The haptic a discrete transition emits, given the live drop verdict (needed only to
-- choose 'DropAccept' vs 'DropReject' on the commit edge). 'CellTick' is NOT here — it is
-- fired by 'cellsCrossed' on continuous 'Drag' samples, not on a phase change.
hapticOnTransition :: GesturePhase -> GestureEvent -> DropVerdict -> Maybe Haptic
hapticOnTransition Pressed HoldElapsed _       = Just LiftPop
hapticOnTransition Lifted  TouchUp     Accept  = Just DropAccept
hapticOnTransition Lifted  TouchUp     Reject  = Just DropReject
hapticOnTransition Lifted  Cancel      _       = Just DropReject
hapticOnTransition _       _           _       = Nothing

-- =============================================================================
-- The detent — cell-crossing ticks (why big cells give precision)
-- =============================================================================

-- | The number of cell boundaries between two lifted positions (Manhattan in cells).
-- Each unit is one 'CellTick': the drag is detented to the lattice, so distance is felt,
-- not merely seen. 'lawTickConservation' proves a unit walk fires exactly this many.
cellsCrossed :: (Int, Int) -> (Int, Int) -> Int
cellsCrossed (c0, r0) (c1, r1) = abs (c1 - c0) + abs (r1 - r0)

-- | The axis-aligned unit walk from @a@ to @b@ (cols first, then rows): the intermediate
-- cells a real drag passes through. Its length IS 'cellsCrossed' ('lawTickConservation'),
-- so the renderer can fire one tick per element and feel exactly right.
tickPath :: (Int, Int) -> (Int, Int) -> [(Int, Int)]
tickPath (c0, r0) (c1, r1) =
  [ (c, r0) | c <- between c0 c1 ] ++ [ (c1, r) | r <- between r0 r1 ]
  where
    between a b
      | a <= b    = [a + 1 .. b]      -- the cells STEPPED INTO (excludes the origin)
      | otherwise = reverse [b .. a - 1]

-- =============================================================================
-- The drop verdict — closed over the proven move (the green-frame correctness)
-- =============================================================================

-- | What a drop WILL do, decided by the one move operator — never a second opinion.
data DropVerdict = Accept | Reject
  deriving (Eq, Show)

-- | The verdict for dropping identity @i@ by cell delta @d@ in placement @p@: 'Accept'
-- iff it is a no-op OR 'move' actually moves it (move only accepts disjoint+in-bounds
-- candidates, else returns @p@ unchanged). This is the SINGLE source the green/red drop
-- outline reads, so the feedback cannot lie about the commit ('lawDropColorMatchesMove').
dropVerdict :: Placement -> ColorIdentity -> (Int, Int) -> DropVerdict
dropVerdict p i d
  | d == (0, 0)     = Accept
  | move p i d /= p = Accept
  | otherwise       = Reject

-- | The stable string name of a 'DropVerdict' (the key the Swift drop handler dispatches on).
-- | Stable cross-language token for a verdict (for the contract / debugging).
verdictName :: DropVerdict -> String
verdictName Accept = "accept"
verdictName Reject = "reject"

-- | The accent ink (sRGB8) for a verdict — the exact greens/reds the drop outline draws.
-- (Matches the legacy @dropOverlay@ inks so the look is unchanged; now it is spec-owned.)
verdictInk :: DropVerdict -> (Int, Int, Int)
verdictInk Accept = ( 70, 200,  90)   -- calm green
verdictInk Reject = (220,  60,  60)   -- urgent red

-- =============================================================================
-- Reactive color + pulse — integer, portable (the renderer samples per frame)
-- =============================================================================

-- | Q16 fixed-point unit (1.0). Amplitudes live in @[0, q16One]@.
q16One :: Int
q16One = 65536

-- | A pulse profile: a triangle wave in Q16 amplitude with an integer period.
data PulseSpec = PulseSpec
  { psPeriodTicks :: !Int   -- ^ ticks per full cycle (≥ 2)
  , psMinQ16      :: !Int   -- ^ trough amplitude (Q16)
  , psMaxQ16      :: !Int   -- ^ peak amplitude (Q16)
  } deriving (Eq, Show)

-- | Sample the pulse at an integer tick — a portable triangle wave (no floats), periodic
-- in 'psPeriodTicks' and bounded to @[psMinQ16, psMaxQ16]@ ('lawPulseBounded' /
-- 'lawPulsePeriodic'). The renderer feeds it the frame counter and lerps the tint.
pulseSampleQ16 :: PulseSpec -> Int -> Int
pulseSampleQ16 (PulseSpec period lo hi) tick =
  let p     = max 2 period
      phase = tick `mod` p
      half  = p `div` 2
      tri   = if phase <= half then phase else p - phase   -- 0 .. half
  in if half == 0 then lo else lo + (hi - lo) * tri `div` half

-- | Choose the live pulse from the drop verdict and how far (in cells) the finger has
-- travelled: REJECT pulses faster and wider than ACCEPT (urgency), and farther drags
-- pulse faster still (down to a floor) — the feedback tracks the user's intent
-- ('lawReactiveFaster'). @dragMag@ is 'cellsCrossed' from the lift origin.
reactivePulse :: Mechanics -> DropVerdict -> Int -> PulseSpec
reactivePulse mc verdict dragMag =
  let base   = mcPulse mc
      urgent = case verdict of Accept -> 0; Reject -> psPeriodTicks base `div` 2
      faster = min (psPeriodTicks base - 2) (max 0 dragMag)   -- shorten with distance
      period = max 4 (psPeriodTicks base - urgent - faster)
      hi     = case verdict of
                 Accept -> psMaxQ16 base
                 Reject -> min q16One (psMaxQ16 base + (q16One `div` 8))  -- wider on reject
  in base { psPeriodTicks = period, psMaxQ16 = hi }

-- | Lerp a base sRGB8 toward an accent by a Q16 amplitude (integer, portable). The
-- widget's cells tint toward 'verdictInk' by the live 'pulseSampleQ16' — so it visibly
-- breathes green when the drop is valid, flits red when not.
tintLerpQ16 :: (Int, Int, Int) -> (Int, Int, Int) -> Int -> (Int, Int, Int)
tintLerpQ16 (br, bg, bb) (ar, ag, ab) ampQ16 =
  let a   = max 0 (min q16One ampQ16)
      mix x y = x + (y - x) * a `div` q16One
  in (mix br ar, mix bg ag, mix bb ab)

-- =============================================================================
-- Per-widget mechanics — the "lifetime" an author declares alongside the footprint
-- =============================================================================

-- | The mechanics knobs for one widget identity. GEOMETRY (footprint/dock) stays in
-- "SixFour.Spec.MovableLayout" (the proof owner); this is the FEEL: how long to hold
-- before lifting, how coarse the detent, and the resting pulse profile. To add a widget
-- you add its geometry row there and one 'mechanicsFor' case here.
data Mechanics = Mechanics
  { mcHoldTicks :: !Int        -- ^ ticks at the logic rate before Pressed→Lifted arms
  , mcLiftHaptic :: !Haptic    -- ^ the pop on lift (default 'LiftPop')
  , mcTickEvery  :: !Int       -- ^ fire 'CellTick' every N cells crossed (≥ 1)
  , mcPulse      :: !PulseSpec  -- ^ the resting pulse profile (mutated by 'reactivePulse')
  } deriving (Eq, Show)

-- | The mechanics for each closed identity. Bigger / coarser widgets get a longer hold
-- and a coarser detent; the live preview ('Field64') breathes slow, the palette/shutter
-- ('Palette16') ticks every cell for fine placement, the gauge ('DiversityRing') sits
-- between. (Source of truth for the Swift @CellMechanicsContract@.)
mechanicsFor :: ColorIdentity -> Mechanics
mechanicsFor Field64       = Mechanics 6 LiftPop 2 (PulseSpec 40 (q16One `div` 6) (q16One `div` 2))
mechanicsFor Palette16     = Mechanics 6 LiftPop 1 (PulseSpec 30 (q16One `div` 5) (q16One * 5 `div` 8))
mechanicsFor DiversityRing = Mechanics 6 LiftPop 1 (PulseSpec 34 (q16One `div` 5) (q16One * 9 `div` 16))

-- =============================================================================
-- The golden cross-language trace (the cabal-gated, Swift-pinned witness)
-- =============================================================================

-- | A fixed gesture script exercising the whole lifetime: down → hold (lift) → two drag
-- samples → up (settle) → settle-done. Emitted to the Swift contract and re-folded by the
-- Swift @gestureStep@ port ('goldenPhaseTrace' is the bit-pin).
goldenGesture :: [GestureEvent]
goldenGesture = [TouchDown, HoldElapsed, Drag, Drag, TouchUp, SettleDone]

-- | The phase trace from 'Resting' over 'goldenGesture' (@scanl gestureStep@):
-- @[Resting, Pressed, Lifted, Lifted, Lifted, Settling, Resting]@.
goldenPhaseTrace :: [GesturePhase]
goldenPhaseTrace = scanl gestureStep Resting goldenGesture

-- | The drag magnitude (cells from the lift origin) at each 'goldenGesture' step — drives
-- the golden reactive pulse + tick count. The two 'Drag' samples step +3 then +4 cells.
goldenDragMag :: [Int]
goldenDragMag = [0, 0, 3, 7, 7, 7]

-- | The haptic emitted at each 'goldenGesture' transition (verdict = 'Accept' here, a
-- clean valid drop): @[Nothing, Just LiftPop, Nothing, Nothing, Just DropAccept, Nothing]@.
goldenHaptics :: [Maybe Haptic]
goldenHaptics =
  [ hapticOnTransition ph ev Accept
  | (ph, ev) <- zip goldenPhaseTrace goldenGesture ]

-- | The first 8 samples of 'Field64''s resting pulse — a portable Q16 table the Swift
-- @selfCheck@ re-derives, pinning 'pulseSampleQ16' cross-language.
goldenPulse :: [Int]
goldenPulse = [ pulseSampleQ16 (mcPulse (mechanicsFor Field64)) t | t <- [0 .. 7] ]

-- =============================================================================
-- Laws
-- =============================================================================

-- | @gestureStep@ is TOTAL: defined (no ⊥) for every (phase, event) pair.
lawGestureTotal :: Bool
lawGestureTotal = all (\(p, e) -> gestureStep p e `seq` True)
                      [ (p, e) | p <- allPhases, e <- allEvents ]

-- | No orphan phase: every 'GesturePhase' is reachable from 'Resting' by some event
-- sequence (a BFS fixpoint). A phase nothing reaches would be dead interaction.
lawGestureNoOrphan :: Bool
lawGestureNoOrphan = all (`elem` reached) allPhases
  where
    reached = fixpoint [Resting]
    fixpoint seen =
      let next = nub (seen ++ [ gestureStep p e | p <- seen, e <- allEvents ])
      in if length next == length seen then seen else fixpoint next

-- | KEYSTONE — tap and drag are disjoint: 'Lifted' (the drag state) is reachable ONLY
-- through the hold gate. (1) you cannot lift straight from 'Resting' on any event, and
-- (2) from 'Pressed', 'HoldElapsed' is the ONLY event that reaches 'Lifted'. So a release
-- before the hold can never have lifted — the structural "a tap never moves the widget".
lawDragRequiresHold :: Bool
lawDragRequiresHold =
     all (\e -> gestureStep Resting e /= Lifted) allEvents
  && all (\e -> (gestureStep Pressed e == Lifted) == (e == HoldElapsed)) allEvents

-- | A fast release from 'Pressed' is a TAP: it returns to 'Resting' AND is flagged by
-- 'producesTap' (so the shutter tap fires), and no lift occurred.
lawTapIsFastRelease :: Bool
lawTapIsFastRelease =
     gestureStep Pressed TouchUp == Resting
  && producesTap Pressed TouchUp
  && not (producesTap Lifted TouchUp)   -- a drop is never mistaken for a tap

-- | A commit always lands back at rest: 'Lifted' --'TouchUp'--> 'Settling', and
-- 'Settling' --'SettleDone'--> 'Resting'. The interaction has no dangling state.
lawSettleReturnsResting :: Bool
lawSettleReturnsResting =
     gestureStep Lifted TouchUp == Settling
  && gestureStep Settling SettleDone == Resting

-- | TICK CONSERVATION — a unit drag from @a@ to @b@ steps through exactly 'cellsCrossed'
-- cells, so firing one 'CellTick' per stepped-into cell feels exactly right: no boundary
-- is skipped or double-counted. (The detent that makes big cells precise.)
lawTickConservation :: (Int, Int) -> (Int, Int) -> Bool
lawTickConservation a b = length (tickPath a b) == cellsCrossed a b

-- | The detent metric is symmetric and zero on the diagonal — dragging back undoes the
-- same count of ticks it cost to drag out.
lawTickSymmetric :: (Int, Int) -> (Int, Int) -> Bool
lawTickSymmetric a b = cellsCrossed a b == cellsCrossed b a && cellsCrossed a a == 0

-- | THE GREEN-FRAME LAW — the drop outline's colour equals what 'move' will actually do:
-- @dropVerdict p i d == Accept@ iff the drop is a no-op or 'move' accepts it. The feedback
-- reads this ONE verdict, so it can never show green on a drop that snaps back (or red on
-- one that lands). The bug "the frame disagrees with the commit" is impossible by law.
lawDropColorMatchesMove :: Placement -> ColorIdentity -> (Int, Int) -> Bool
lawDropColorMatchesMove p i d =
  (dropVerdict p i d == Accept) == (d == (0, 0) || move p i d /= p)

-- | The pulse stays inside its declared band for every tick: @psMin ≤ sample ≤ psMax@
-- (assuming @psMin ≤ psMax@). No tint over- or under-shoots.
lawPulseBounded :: PulseSpec -> Int -> Bool
lawPulseBounded spec tick =
  psMinQ16 spec > psMaxQ16 spec
    || (let s = pulseSampleQ16 spec tick in s >= psMinQ16 spec && s <= psMaxQ16 spec)

-- | The pulse is periodic in 'psPeriodTicks': the breath repeats exactly, so the
-- animation never drifts. (Stated for even periods, where the triangle closes cleanly.)
lawPulsePeriodic :: PulseSpec -> Int -> Bool
lawPulsePeriodic spec tick =
  let p = max 2 (psPeriodTicks spec)
  in even p
       `implies` (pulseSampleQ16 spec tick == pulseSampleQ16 spec (tick + p))
  where implies a b = not a || b

-- | The feedback tracks intent: a REJECT pulses no slower than an ACCEPT, and dragging
-- FARTHER never slows the pulse (period is non-increasing in the drag magnitude). So the
-- closer the user gets to a bad drop / the more committed the gesture, the more insistent
-- the feel — never the reverse.
lawReactiveFaster :: Mechanics -> Int -> Int -> Bool
lawReactiveFaster mc m1 m2 =
     psPeriodTicks (reactivePulse mc Reject d1) <= psPeriodTicks (reactivePulse mc Accept d1)
  && (d1 <= d2) `implies`
       (psPeriodTicks (reactivePulse mc v d2) <= psPeriodTicks (reactivePulse mc v d1))
  where
    d1 = max 0 m1
    d2 = max 0 m2
    v  = Accept
    implies a b = not a || b

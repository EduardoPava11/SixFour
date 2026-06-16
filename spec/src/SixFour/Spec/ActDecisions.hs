{- |
Module      : SixFour.Spec.ActDecisions
Description : The five-Acts decision algebra — Act -> [Decision], each act capped at
              'maxDecisionsPerAct' real Display events. Layered ON TOP of the Display
              FSM (it cites 'SixFour.Spec.Display.allEvents'); it adds NO transitions.

The one-surface app is five Acts (Live -> Capture -> Browse -> Render -> Review). This
module pins, per Act, the SMALL fixed set of user DECISIONS available on that act's cell
field — each decision is a real 'SixFour.Spec.Display.Event' that mutates the display
state \(\Sigma\) (its phase is governed by 'SixFour.Spec.Display.step'; most decisions are
phase self-loops). The keystone is 'maxDecisionsPerAct' = 3: a screen with more than three
live affordances is, by this law, off-contract. 'completionFor' names the ONE event that
ends each act (advances the phase).

The Acts map onto Display phases: ActLive~Live, ActCapture~Capturing, ActBrowse~Browsing,
ActRender~Rendering, ActReview~Review. This slice is the decision TABLE + the cap law; the
Swift UI router that consumes it is a deferred slice.

GHC-boot-only: base + 'SixFour.Spec.Display'.
-}
module SixFour.Spec.ActDecisions
  ( -- * The five acts
    Act(..), allActs
    -- * A decision = (event, surface, target)
  , Surface(..), Target(..), Decision(..)
    -- * The decision table
  , decisionsFor, completionFor, maxDecisionsPerAct
  , goldenDecisionTable
    -- * Stable tokens (cross-language contract)
  , actName, surfaceName, targetName
    -- * Laws (8)
  , lawDecisionBudget        -- keystone: every act has <= maxDecisionsPerAct decisions
  , lawEventCoversDecisions  -- every dEvent is a real Display.Event
  , lawCompletionIsEvent     -- every completionFor is a real Display.Event
  , lawCompletionDistinct    -- completionFor a is NOT among a's decision events
  , lawNoButtons             -- every dSurface is a real cell-field surface (no chrome)
  , lawDecisionsDistinct     -- an act lists no duplicate decision events
  , lawActsExhaustive        -- decisionsFor is defined for every act (total table)
  , lawTableMatchesGolden    -- the live table equals the pinned golden
  ) where

import Data.List (nub)
import qualified SixFour.Spec.Display as D

-- | The five acts of the one-surface authoring story.
data Act = ActLive | ActCapture | ActBrowse | ActRender | ActReview
  deriving (Eq, Show, Enum, Bounded)

-- | Every act (for the totality / cap laws and the codegen contract).
allActs :: [Act]
allActs = [minBound .. maxBound]

-- | The real cell-field surfaces a decision can live on — NOT chrome buttons
-- ('lawNoButtons'). These are regions of the one persistent cell field.
data Surface = HeroGif | Palette16 | Scrubber | Gutter
  deriving (Eq, Show, Enum, Bounded)

-- | The \(\Sigma\)-mutation a decision performs (the semantic tag; the actual write is
-- owned by the Swift router in the deferred slice).
data Target
  = BeginBurst      -- ^ arm + start the 64-frame capture
  | ShiftLook       -- ^ swipe the OKLab look transform (mutates the palette in \(\Sigma\))
  | OpenSettingsT   -- ^ enter the in-surface settings phase
  | MoveCursor      -- ^ scrub the Z_64 cursor
  | PickAnchor      -- ^ mark one of the 4 anchor frames
  | SetCut          -- ^ set the 2^k collapse cut depth
  | ExportCube      -- ^ emit the .cube LUT
  deriving (Eq, Show, Enum, Bounded)

-- | One available decision on an act's cell field: a real Display event, the surface
-- it is gestured on, and the \(\Sigma\)-mutation it performs.
data Decision = Decision
  { dEvent   :: !D.Event   -- ^ a real 'SixFour.Spec.Display.Event'
  , dSurface :: !Surface   -- ^ the cell-field region it lives on
  , dTarget  :: !Target    -- ^ the \(\Sigma\)-mutation it performs
  } deriving (Eq, Show)

-- | THE CAP: no act offers more than three live decisions. The keystone
-- 'lawDecisionBudget'.
maxDecisionsPerAct :: Int
maxDecisionsPerAct = 3

-- | The decision table: each act's <= 3 user decisions. Capture and Render are
-- deterministic / in-flight, so they offer none. 'D.ShutterTap' is the act-COMPLETER
-- of Live ('completionFor' ActLive), so it is NOT a listed Live decision
-- ('lawCompletionDistinct') — Live offers LookSwipe + OpenSettings only. Pick-four is
-- 'D.SelectFrame' (Browse), and the Browse-commit is 'D.Picked4'
-- ('completionFor' ActBrowse).
decisionsFor :: Act -> [Decision]
decisionsFor ActLive =
  [ Decision D.LookSwipe    HeroGif   ShiftLook
  , Decision D.OpenSettings Gutter    OpenSettingsT ]
decisionsFor ActCapture = []
decisionsFor ActBrowse =
  [ Decision D.ScrubTick    Scrubber  MoveCursor
  , Decision D.SelectFrame  Scrubber  PickAnchor ]
decisionsFor ActRender = []
decisionsFor ActReview =
  [ Decision D.ScrubTick    HeroGif   MoveCursor
  , Decision D.CutLever     Palette16 SetCut
  , Decision D.ExportLut    Gutter    ExportCube ]

-- | The ONE event that completes each act (advances the Display phase). Distinct from
-- that act's decision events ('lawCompletionDistinct').
completionFor :: Act -> D.Event
completionFor ActLive    = D.ShutterTap
completionFor ActCapture = D.BurstComplete
completionFor ActBrowse  = D.Picked4
completionFor ActRender  = D.Committed
completionFor ActReview  = D.Retake

-- | The pinned golden table (acts paired with their decision lists) — written out as
-- explicit literals (NOT reusing 'decisionsFor') so 'lawTableMatchesGolden' compares two
-- independently-authored sources and binds against drift.
goldenDecisionTable :: [(Act, [Decision])]
goldenDecisionTable =
  [ ( ActLive
    , [ Decision D.LookSwipe    HeroGif   ShiftLook
      , Decision D.OpenSettings Gutter    OpenSettingsT ] )
  , ( ActCapture, [] )
  , ( ActBrowse
    , [ Decision D.ScrubTick    Scrubber  MoveCursor
      , Decision D.SelectFrame  Scrubber  PickAnchor ] )
  , ( ActRender, [] )
  , ( ActReview
    , [ Decision D.ScrubTick    HeroGif   MoveCursor
      , Decision D.CutLever     Palette16 SetCut
      , Decision D.ExportLut    Gutter    ExportCube ] )
  ]

-- | Stable cross-language token for an act.
actName :: Act -> String
actName ActLive    = "live"
actName ActCapture = "capture"
actName ActBrowse  = "browse"
actName ActRender  = "render"
actName ActReview  = "review"

-- | Stable cross-language token for a surface.
surfaceName :: Surface -> String
surfaceName HeroGif   = "heroGif"
surfaceName Palette16 = "palette16"
surfaceName Scrubber  = "scrubber"
surfaceName Gutter    = "gutter"

-- | Stable cross-language token for a target (the \(\Sigma\)-mutation tag).
targetName :: Target -> String
targetName BeginBurst    = "beginBurst"
targetName ShiftLook     = "shiftLook"
targetName OpenSettingsT = "openSettings"
targetName MoveCursor    = "moveCursor"
targetName PickAnchor    = "pickAnchor"
targetName SetCut        = "setCut"
targetName ExportCube    = "exportCube"

-- =============================================================================
-- Laws (8)
-- =============================================================================

-- | KEYSTONE — the budget: every act offers at most 'maxDecisionsPerAct' decisions.
-- Falsified by adding a 4th 'Decision' to any 'decisionsFor' clause (Review currently
-- sits at the cap of 3, so a 4th there fails this immediately).
lawDecisionBudget :: Bool
lawDecisionBudget = all (\a -> length (decisionsFor a) <= maxDecisionsPerAct) allActs

-- | Every decision's event is a real 'D.Event' (member of 'D.allEvents'). Its real
-- guard: it pins that the 4 new events were actually added to 'D.allEvents' — if a future
-- edit dropped @LookSwipe@ from 'D.allEvents' while keeping it as a decision, this goes
-- RED.
lawEventCoversDecisions :: Bool
lawEventCoversDecisions =
  all (\d -> dEvent d `elem` D.allEvents) (concatMap decisionsFor allActs)

-- | Every completion event is a real 'D.Event'. Falsified by a 'completionFor' not in
-- 'D.allEvents'.
lawCompletionIsEvent :: Bool
lawCompletionIsEvent = all (\a -> completionFor a `elem` D.allEvents) allActs

-- | The completion event of an act is NOT one of that act's decision events — a decision
-- affordance never doubles as the act's exit. 'D.ShutterTap' (Live's completer) is
-- deliberately absent from 'decisionsFor' ActLive for this law to bind. Falsified by
-- re-adding ShutterTap as a Live decision.
lawCompletionDistinct :: Bool
lawCompletionDistinct =
  all (\a -> completionFor a `notElem` map dEvent (decisionsFor a)) allActs

-- | Every decision lives on a real cell-field surface, never a chrome button. The roster
-- is asserted to be EXACTLY the 4 cell-field regions: if a 5th 'Surface' constructor
-- (e.g. a chrome button) is later added and routed to, the @== 4@ clause goes RED.
lawNoButtons :: Bool
lawNoButtons =
  length ([minBound .. maxBound] :: [Surface]) == 4
    && all (\d -> dSurface d `elem` [HeroGif, Palette16, Scrubber, Gutter])
           (concatMap decisionsFor allActs)

-- | An act lists no duplicate decision EVENTS (two affordances can't fire the same event
-- on the same act). Falsified by repeating an event in a 'decisionsFor' clause.
lawDecisionsDistinct :: Bool
lawDecisionsDistinct =
  all (\a -> let es = map dEvent (decisionsFor a) in length (nub es) == length es) allActs

-- | The table is total: 'decisionsFor' is defined (no bottom) for every act, and
-- 'allActs' enumerates all five. Falsified by a non-total 'decisionsFor' or a missing act
-- in 'allActs'.
lawActsExhaustive :: Bool
lawActsExhaustive =
  length allActs == 5 && all (\a -> decisionsFor a `seq` True) allActs

-- | The live table equals the pinned 'goldenDecisionTable' (written as explicit literals).
-- Falsified by any drift between 'decisionsFor' and the golden.
lawTableMatchesGolden :: Bool
lawTableMatchesGolden = goldenDecisionTable == [ (a, decisionsFor a) | a <- allActs ]

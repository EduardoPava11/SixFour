{- |
Module      : SixFour.Spec.ABSurface
Description : The simplified 8-phase capture → A/B → export FSM (the user story), replacing ONLY the
              phase-FSM half of 'SixFour.Spec.Display'.

The whole multi-phase Surface (browse, refine, palette explorers, movable widgets, voxel
tools, 5-stage render) collapses to capture → A/B → export. This module owns the new
phase machine; the CLOCK half of 'SixFour.Spec.Display' (the 20 fps κ, the projections, the
@Lattice@ atom) is imported unchanged.

== Phases and events

@
Phase  = Bootstrap | Unauthorized | Live | Captured | Picked | Exporting | Done | Error
Event  = SessionReady | AuthDenied | ShutterTap | LockComplete | BurstComplete
       | PickA | PickB | ExportFamily | ExportDone | Retake | Fault
@

Lock + burst are INTERNAL to Live (camera freezes; not visible sub-phases). PickA and
PickB are BOTH live edges out of Captured, both landing in Picked (the user "plays the game":
repeated picks self-loop in Picked while θ folds — see 'SixFour.Spec.DivergenceSchedule'). Export
is gated on a prior pick (Exporting is entered ONLY from Picked). Retake bails from
Done\/Captured\/Picked back to Live (mid-A/B bail allowed). δ is total with a catch-all self-loop;
'Fault' from any phase lands in Error.

== Captured is the A/B screen — two 16×16 candidate tiles

Candidate A and B are disjoint 16×16 cell rectangles on the lattice (symmetric about centre), the
orthogonal 'SixFour.Spec.GenomePair' pair. 'lawABCellGrid' pins their disjointness + in-bounds.

GHC-boot-only. Laws QuickCheck'd in @Properties.ABSurface@.
-}
-- COMPARTMENT: SWIFT-COREAI | tag:DisplaySide
module SixFour.Spec.ABSurface
  ( -- * Alphabet
    ABPhase(..)
  , ABEvent(..)
  , allABPhases
  , allABEvents
    -- * The machine
  , abStep
  , abPhaseName
  , abEventName
    -- * The A/B candidate cell rectangles
  , candidateRegionA
  , candidateRegionB
  , latticeCols
  , latticeRows
    -- * Golden gate
  , goldenABHappyPath
  , goldenABPhaseTrace
    -- * Laws (QuickCheck'd in Properties.ABSurface)
  , lawABPhaseTotal
  , lawABNoOrphan
  , lawABReachable
  , lawExportGatedOnPick
  , lawDoneExplicit
  , lawABCellGrid
  , lawABGoldenTrace
  ) where

import Data.List (scanl', sort, nub)

-- | The 8 UI-lifecycle phases (one surface, no screens).
data ABPhase
  = Bootstrap | Unauthorized | Live | Captured | Picked | Exporting | Done | Error
  deriving (Eq, Ord, Show, Enum, Bounded)

-- | The 11 events.
data ABEvent
  = SessionReady | AuthDenied | ShutterTap | LockComplete | BurstComplete
  | PickA | PickB | ExportFamily | ExportDone | Retake | Fault
  deriving (Eq, Show, Enum, Bounded)

-- | All phases (gate enumeration).
allABPhases :: [ABPhase]
allABPhases = [minBound .. maxBound]

-- | All events (gate enumeration).
allABEvents :: [ABEvent]
allABEvents = [minBound .. maxBound]

-- | The total transition function δ. 'Fault' anywhere → Error; the documented edges; otherwise a
-- catch-all self-loop (Lock\/Shutter are internal to Live; repeated Pick* self-loop in Picked).
abStep :: ABPhase -> ABEvent -> ABPhase
abStep _ Fault              = Error
abStep Bootstrap SessionReady = Live
abStep Bootstrap AuthDenied   = Unauthorized
abStep Live BurstComplete     = Captured          -- lock + burst are internal to Live
abStep Captured PickA         = Picked
abStep Captured PickB         = Picked
abStep Picked   ExportFamily  = Exporting
abStep Exporting ExportDone   = Done
abStep p Retake
  | p `elem` [Captured, Picked, Done] = Live       -- bail back to live
abStep p _                    = p                  -- catch-all self-loop

-- | Cross-language phase token (stable lowercase).
abPhaseName :: ABPhase -> String
abPhaseName Bootstrap    = "bootstrap"
abPhaseName Unauthorized = "unauthorized"
abPhaseName Live         = "live"
abPhaseName Captured     = "captured"
abPhaseName Picked       = "picked"
abPhaseName Exporting    = "exporting"
abPhaseName Done         = "done"
abPhaseName Error        = "error"

-- | Cross-language event token (stable lowerCamel).
abEventName :: ABEvent -> String
abEventName SessionReady  = "sessionReady"
abEventName AuthDenied    = "authDenied"
abEventName ShutterTap    = "shutterTap"
abEventName LockComplete  = "lockComplete"
abEventName BurstComplete = "burstComplete"
abEventName PickA         = "pickA"
abEventName PickB         = "pickB"
abEventName ExportFamily  = "exportFamily"
abEventName ExportDone    = "exportDone"
abEventName Retake        = "retake"
abEventName Fault         = "fault"

-- ---------------------------------------------------------------------------
-- The A/B candidate cell rectangles (col, row, width, height) on the 100×218 lattice
-- ---------------------------------------------------------------------------

-- | Candidate A's 16×16 tile (left of centre).
candidateRegionA :: (Int, Int, Int, Int)
candidateRegionA = (16, 100, 16, 16)

-- | Candidate B's 16×16 tile (right of centre, symmetric — 36-col gutter to A).
candidateRegionB :: (Int, Int, Int, Int)
candidateRegionB = (68, 100, 16, 16)

latticeCols, latticeRows :: Int
latticeCols = 100
latticeRows = 218

rectsDisjoint :: (Int, Int, Int, Int) -> (Int, Int, Int, Int) -> Bool
rectsDisjoint (c1, r1, w1, h1) (c2, r2, w2, h2) =
  c1 + w1 <= c2 || c2 + w2 <= c1 || r1 + h1 <= r2 || r2 + h2 <= r1

rectInBounds :: (Int, Int, Int, Int) -> Bool
rectInBounds (c, r, w, h) = c >= 0 && r >= 0 && c + w <= latticeCols && r + h <= latticeRows

-- ---------------------------------------------------------------------------
-- Golden
-- ---------------------------------------------------------------------------

-- | The golden happy-path event sequence.
goldenABHappyPath :: [ABEvent]
goldenABHappyPath =
  [SessionReady, ShutterTap, BurstComplete, PickA, ExportFamily, ExportDone, Retake]

-- | The golden phase trace @scanl' abStep Bootstrap goldenABHappyPath@.
goldenABPhaseTrace :: [ABPhase]
goldenABPhaseTrace =
  [Bootstrap, Live, Live, Captured, Picked, Exporting, Done, Live]

-- ---------------------------------------------------------------------------
-- Laws
-- ---------------------------------------------------------------------------

implies :: Bool -> Bool -> Bool
implies a b = not a || b

-- BFS reachability closure under δ from a seed set.
reachClosure :: [ABPhase] -> [ABPhase]
reachClosure seed = go seed seed
  where
    go frontier seen
      | null next = seen
      | otherwise = go next (seen ++ next)
      where step = [ abStep p e | p <- frontier, e <- allABEvents ]
            next = nub [ q | q <- step, q `notElem` seen ]

-- | 'abStep' is total over every (phase, event) — every result is a valid 'ABPhase'.
lawABPhaseTotal :: Bool
lawABPhaseTotal = and [ abStep p e `elem` allABPhases | p <- allABPhases, e <- allABEvents ]

-- | Every phase is reachable from Bootstrap (BFS closure = all phases).
lawABNoOrphan :: Bool
lawABNoOrphan = sort (reachClosure [Bootstrap]) == sort allABPhases

-- | BOTH PickA and PickB are live edges out of Captured, both landing in Picked.
lawABReachable :: Bool
lawABReachable = abStep Captured PickA == Picked && abStep Captured PickB == Picked

-- | Exporting is ENTERED (a genuine transition, not the self-loop) ONLY from Picked via ExportFamily.
lawExportGatedOnPick :: Bool
lawExportGatedOnPick =
  and [ (abStep p e == Exporting && p /= Exporting) `implies` (p == Picked && e == ExportFamily)
      | p <- allABPhases, e <- allABEvents ]

-- | Done is ENTERED (a genuine transition, not the self-loop) ONLY via ExportDone.
lawDoneExplicit :: Bool
lawDoneExplicit =
  and [ (abStep p e == Done && p /= Done) `implies` (e == ExportDone)
      | p <- allABPhases, e <- allABEvents ]

-- | The two A/B candidate cell rectangles are disjoint and in-bounds (every phase shows the same
-- committed layout; absent tiles are trivially disjoint). Pins the 16×16 candidate geometry.
lawABCellGrid :: ABPhase -> Bool
lawABCellGrid _ =
  rectsDisjoint candidateRegionA candidateRegionB
    && rectInBounds candidateRegionA && rectInBounds candidateRegionB

-- | @scanl' abStep Bootstrap goldenABHappyPath == goldenABPhaseTrace@.
lawABGoldenTrace :: Bool
lawABGoldenTrace = scanl' abStep Bootstrap goldenABHappyPath == goldenABPhaseTrace

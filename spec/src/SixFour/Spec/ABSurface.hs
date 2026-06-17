{- |
Module      : SixFour.Spec.ABSurface
Description : The simplified 8-phase capture → A/B → export FSM, replacing ONLY the
              phase-FSM half of 'SixFour.Spec.Display'.

The whole multi-phase Surface (browse, refine, palette explorers, movable widgets, voxel
tools, 5-stage render) collapses to capture → A/B → export. This module owns the new
phase machine; the CLOCK half of 'SixFour.Spec.Display' (T1–T9, the 20 fps κ,
@projGif@/@projPalette@/@projShutter@, the @Lattice@ atom) is imported unchanged.

== Phases and events

@
Phase  = Bootstrap | Unauthorized | Live | Captured | Picked | Exporting | Done | Error
Event  = SessionReady | AuthDenied | ShutterTap | LockComplete | BurstComplete
       | PickA | PickB | ExportFamily | ExportDone | Retake | Fault
@

Lock + burst are INTERNAL to Live (camera freezes; not visible sub-phases). PickA and
PickB are BOTH live edges out of Captured, both landing in Picked. Export is gated on a
prior pick (Exporting is entered ONLY from Picked). Retake bails from
Done\/Captured\/Picked back to Live (mid-A/B bail allowed). δ is total with a catch-all
self-loop.

== Captured is the A/B screen on the 100×218 4pt lattice

64³ reference HERO (cols 18–81, rendered through the BASE genome g0 GLOBAL table — NOT
per-frame palettes, so preview≡ship), candidate A tile (cols 16–31), candidate B tile
(cols 68–83), symmetric about center 50 with a 36-col gutter — ONE committed coordinate
set fed through 'SixFour.Spec.GridLayout'. Tapping a tile IS the pick. All regions are
disjoint cell rectangles ('lawABCellGrid').

GHC-boot-only.
-}
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

import Data.List (scanl')

-- Clock half imported unchanged (Lattice atom + 20fps κ live in Display).
import SixFour.Spec.Lattice (gifPx)

-- | The 8 UI-lifecycle phases (one surface, no screens).
data ABPhase
  = Bootstrap | Unauthorized | Live | Captured | Picked | Exporting | Done | Error
  deriving (Eq, Show, Enum, Bounded)

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

-- | The total transition function δ (catch-all self-loop on unhandled pairs).
abStep :: ABPhase -> ABEvent -> ABPhase
abStep = error "TODO: total δ per the FSM table; default = self-loop"

-- | Cross-language phase token.
abPhaseName :: ABPhase -> String
abPhaseName = error "TODO"

-- | Cross-language event token.
abEventName :: ABEvent -> String
abEventName = error "TODO"

-- | The golden happy-path event sequence.
goldenABHappyPath :: [ABEvent]
goldenABHappyPath =
  [SessionReady, ShutterTap, BurstComplete, PickA, ExportFamily, ExportDone, Retake]

-- | The golden phase trace @scanl abStep Bootstrap goldenABHappyPath@.
goldenABPhaseTrace :: [ABPhase]
goldenABPhaseTrace =
  [Bootstrap, Live, Live, Captured, Picked, Exporting, Done, Live]

-- ---------------------------------------------------------------------------
-- Laws
-- ---------------------------------------------------------------------------

-- | 'abStep' is total over every (phase, event) (catch-all self-loop).
lawABPhaseTotal :: Bool
lawABPhaseTotal = error "TODO"

-- | Every phase reachable from Bootstrap (BFS reachability).
lawABNoOrphan :: Bool
lawABNoOrphan = error "TODO"

-- | BOTH PickA and PickB are live edges out of Captured, both land in Picked.
lawABReachable :: Bool
lawABReachable = error "TODO"

-- | Exporting entered ONLY from Picked via ExportFamily.
lawExportGatedOnPick :: Bool
lawExportGatedOnPick = error "TODO"

-- | Done entered ONLY via ExportDone.
lawDoneExplicit :: Bool
lawDoneExplicit = error "TODO"

-- | Every phase IS a full cell-field configuration on the committed disjoint rectangles.
lawABCellGrid :: ABPhase -> Bool
lawABCellGrid = error "TODO"

-- | @scanl abStep Bootstrap goldenABHappyPath == goldenABPhaseTrace@.
lawABGoldenTrace :: Bool
lawABGoldenTrace = error "TODO"

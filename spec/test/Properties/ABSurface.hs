module Properties.ABSurface (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.ABSurface

tests :: TestTree
tests = testGroup "ABSurface (capture → A/B → export FSM — the user story)"
  [ testProperty "δ is total (every (phase,event) → a valid phase)" (once lawABPhaseTotal)
  , testProperty "no orphan phase (all 8 reachable from Bootstrap)" (once lawABNoOrphan)
  , testProperty "PickA and PickB both land in Picked" (once lawABReachable)
  , testProperty "Exporting only from Picked via ExportFamily" (once lawExportGatedOnPick)
  , testProperty "Done only via ExportDone" (once lawDoneExplicit)
  , testProperty "A/B candidate rectangles disjoint + in-bounds" $
      forAll (elements allABPhases) lawABCellGrid
  , testProperty "GOLDEN happy-path phase trace" (once lawABGoldenTrace)
  ]

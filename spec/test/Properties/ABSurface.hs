module Properties.ABSurface (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.ABSurface

tests :: TestTree
tests = testGroup "ABSurface (capture → A/B → export FSM — the user story)"
  [ testProperty "δ is total (every (phase,event) → a valid phase)" (once lawABPhaseTotal)
  , testProperty "no orphan phase (all 10 reachable from Bootstrap)" (once lawABNoOrphan)
  , testProperty "PickA and PickB both land in Picked" (once lawABReachable)
  , testProperty "Exporting only from Picked via ExportFamily" (once lawExportGatedOnPick)
  , testProperty "Done only via ExportDone" (once lawDoneExplicit)
  , testProperty "A/B candidate rectangles disjoint + in-bounds" $
      forAll (elements allABPhases) lawABCellGrid
  , testProperty "GOLDEN happy-path phase trace" (once lawABGoldenTrace)
  -- V3.0 decide loop (Deciding phase + BeginDecide/DecideAccept/DecideAgain)
  , testProperty "Deciding entered only from Captured via BeginDecide" (once lawDecideEntryGated)
  , testProperty "decide verdicts resolve (accept→Picked, again/retake→Live, fault→Error)" (once lawDecideVerdictsResolve)
  , testProperty "GOLDEN decide-path phase trace (reject loop then accept then export)" (once lawDecideGoldenTrace)
  -- LAUNCH curate excursion (Curating phase + BeginCurate/CurateDone; a Picked self-excursion)
  , testProperty "Curating entered only from Picked via BeginCurate" (once lawCurateEntryGated)
  , testProperty "curate resolves (done→Picked, retake→Live, fault→Error)" (once lawCurateResolves)
  , testProperty "GOLDEN curate-path phase trace (decide-accept, curate loop, export)" (once lawCurateGoldenTrace)
  ]

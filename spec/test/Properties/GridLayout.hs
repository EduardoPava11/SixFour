module Properties.GridLayout (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.GridLayout

tests :: TestTree
tests = testGroup "GridLayout (the capture-scene contention proof — every widget is a disjoint cell claim)"
  [ testProperty "DISJOINT: no two widgets claim the same cell (sceneContested == [])" $
      once (lawSceneDisjoint captureScene)

  , testProperty "in-bounds: every claimed cell is inside the 100×218 screen lattice" $
      once (lawSceneInBounds captureScene)

  , testProperty "interactive regions clear the 44 pt touch floor in both dims" $
      once (lawInteractiveTouchFloor captureScene)

  , testProperty "every region clears both OS safe areas (island 62 pt / home 34 pt)" $
      once (lawSafeAreaClearance captureScene)

  , testProperty "priorities are distinct (deterministic contest winner)" $
      once (lawPriorityDistinct captureScene)

  , testProperty "algebraic no-contest == geometric AABB no-overlap (bridge)" $
      once (lawDisjointMatchesRects captureScene)

  -- The laws are robust on arbitrary scenes too: an overlapping pair is BOTH
  -- contested and AABB-overlapping (the bridge holds off the canonical scene).
  , testProperty "bridge holds on an overlapping 2-region scene" $
      once $ lawDisjointMatchesRects
        [ ("a", LRegion 0 0 10 10 0 0 False)
        , ("b", LRegion 5 5 10 10 1 1 False) ]
        .&&. not (lawSceneDisjoint
        [ ("a", LRegion 0 0 10 10 0 0 False)
        , ("b", LRegion 5 5 10 10 1 1 False) ])
  ]

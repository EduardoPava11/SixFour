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

  , testProperty "TOTAL: disjoint claims + complement partition the 100×218 lattice (cover groundwork)" $
      once (lawCoverPartitions captureScene)

  , testProperty "WIDGET SIZING: every widget cell is on the rounded display (clears the corners)" $
      once (lawWidgetsClearCorners captureScene)

  -- The V3.0 DECISION scene (the post-capture 16\179 iterate surface) passes the
  -- same eight laws: every user-changeable knob is a proven, contention-free claim.
  , testProperty "decisionScene: disjoint" $ once (lawSceneDisjoint decisionScene)
  , testProperty "decisionScene: in-bounds" $ once (lawSceneInBounds decisionScene)
  , testProperty "decisionScene: interactive touch floor" $ once (lawInteractiveTouchFloor decisionScene)
  , testProperty "decisionScene: safe-area clearance" $ once (lawSafeAreaClearance decisionScene)
  , testProperty "decisionScene: priorities distinct" $ once (lawPriorityDistinct decisionScene)
  , testProperty "decisionScene: algebraic == geometric disjointness" $ once (lawDisjointMatchesRects decisionScene)
  , testProperty "decisionScene: cover partitions the lattice" $ once (lawCoverPartitions decisionScene)
  , testProperty "decisionScene: widgets clear the rounded corners" $ once (lawWidgetsClearCorners decisionScene)

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

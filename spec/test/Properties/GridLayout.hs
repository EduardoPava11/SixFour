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

  -- THE TWO VERBS (THE DESIGN D3, 2026-07-08): the rebuilt Decide layout is
  -- pinned — the judgment hero with its 16³ coarse + static tally beside it,
  -- the advanced fold (chevron + demoted W1 bench region), and the verb band
  -- at 4× the touch floor (44×16 each, 4-cell gaps: 4+44+4+44+4 = 100 cols).
  , testProperty "decisionScene D3 witness: hero/coarse/tally/fold/advanced/again/accept at the pinned rects" $
      once $ and
        [ pin decisionScene "hero"     (14, 30,  64, 64)
        , pin decisionScene "coarse"   (82, 30,  16, 16)
        , pin decisionScene "tally"    (82, 26,  16,  2)
        , pin decisionScene "fold"     (44, 98,  12, 12)
        , pin decisionScene "advanced" (18, 112, 64, 76)
        , pin decisionScene "again"    ( 4, 188, 44, 16)
        , pin decisionScene "accept"   (52, 188, 44, 16)
        ]
  , testProperty "decisionScene D3: coarse + tally are display-only; the other five are controls" $
      once $ and
        (  [ maybe False (not . lrInteractive) (lookup nm decisionScene)
           | nm <- ["coarse", "tally"] ]
        ++ [ maybe False lrInteractive (lookup nm decisionScene)
           | nm <- ["hero", "fold", "advanced", "again", "accept"] ] )

  -- The LAUNCH CURATE scene (the 256³ curation loop surface) passes the same
  -- eight laws: the hero inspection pane, the t-slab rail, and the three
  -- iterate knobs are proven, contention-free claims.
  , testProperty "curateScene: disjoint" $ once (lawSceneDisjoint curateScene)
  , testProperty "curateScene: in-bounds" $ once (lawSceneInBounds curateScene)
  , testProperty "curateScene: interactive touch floor" $ once (lawInteractiveTouchFloor curateScene)
  , testProperty "curateScene: safe-area clearance" $ once (lawSafeAreaClearance curateScene)
  , testProperty "curateScene: priorities distinct" $ once (lawPriorityDistinct curateScene)
  , testProperty "curateScene: algebraic == geometric disjointness" $ once (lawDisjointMatchesRects curateScene)
  , testProperty "curateScene: cover partitions the lattice" $ once (lawCoverPartitions curateScene)
  , testProperty "curateScene: widgets clear the rounded corners" $ once (lawWidgetsClearCorners curateScene)

  -- The LIVE TELEMETRY scene (the rung-ladder instrument flanks + the system
  -- machine ring beside/below the self-centered inverted pyramid) passes the
  -- same eight laws: every meter is a proven, contention-free, NON-interactive
  -- claim that clears the arcs, the safe areas, and the shutter.
  , testProperty "liveScene: disjoint" $ once (lawSceneDisjoint liveScene)
  , testProperty "liveScene: in-bounds" $ once (lawSceneInBounds liveScene)
  , testProperty "liveScene: interactive touch floor" $ once (lawInteractiveTouchFloor liveScene)
  , testProperty "liveScene: safe-area clearance" $ once (lawSafeAreaClearance liveScene)
  , testProperty "liveScene: priorities distinct" $ once (lawPriorityDistinct liveScene)
  , testProperty "liveScene: algebraic == geometric disjointness" $ once (lawDisjointMatchesRects liveScene)
  , testProperty "liveScene: cover partitions the lattice" $ once (lawCoverPartitions liveScene)
  , testProperty "liveScene: widgets clear the rounded corners" $ once (lawWidgetsClearCorners liveScene)

  -- THE POUR instruments (THE DESIGN D2, 2026-07-08): the intake tallies, flux
  -- bar, and gesture rails are pinned at their designed gutter coordinates —
  -- non-interactive display overlays whose quantities live in
  -- Spec.ColorTimeDisplay (slot counts = unitsOf by lawTallyEqualsUnits).
  , testProperty "liveScene POUR witness: intake32/intake16/fluxBar/evRail/lookStrip at the pinned rects" $
      once $ and
        [ pin liveScene "intake32"  (34, 114, 32, 2)
        , pin liveScene "intake16"  (42, 149, 16, 2)
        , pin liveScene "fluxBar"   (42, 172, 16, 1)
        , pin liveScene "evRail"    ( 2, 120,  2, 26)
        , pin liveScene "lookStrip" (18,  44, 64, 4)
        ]
  , testProperty "liveScene POUR: all five instruments are non-interactive (gestures stay on the ground layer)" $
      once $ and
        [ maybe False (not . lrInteractive) (lookup nm liveScene)
        | nm <- ["intake32", "intake16", "fluxBar", "evRail", "lookStrip"] ]

  -- THE SCROLL scene (the infinite-tube viewport, a `.live` render-state
  -- self-excursion) passes the same eight laws: the tube hero rides EXACTLY the
  -- liveScene field64 band, the pour tally reuses the intake16 geometry, the
  -- position rail is a display-only 2-cell flank, and the two verbs clear the
  -- touch floor.
  , testProperty "scrollScene: disjoint" $ once (lawSceneDisjoint scrollScene)
  , testProperty "scrollScene: in-bounds" $ once (lawSceneInBounds scrollScene)
  , testProperty "scrollScene: interactive touch floor" $ once (lawInteractiveTouchFloor scrollScene)
  , testProperty "scrollScene: safe-area clearance" $ once (lawSafeAreaClearance scrollScene)
  , testProperty "scrollScene: priorities distinct" $ once (lawPriorityDistinct scrollScene)
  , testProperty "scrollScene: algebraic == geometric disjointness" $ once (lawDisjointMatchesRects scrollScene)
  , testProperty "scrollScene: cover partitions the lattice" $ once (lawCoverPartitions scrollScene)
  , testProperty "scrollScene: widgets clear the rounded corners" $ once (lawWidgetsClearCorners scrollScene)

  -- THE SCROLL witnesses: the hero is pinned to the liveScene field64 band (the
  -- scroll takes over the pyramid's fine band — entering/leaving the tube never
  -- moves the eye), the pour tally shares the intake16 slot geometry, and only
  -- the hero + the two verbs are controls.
  , testProperty "scrollScene witness: hero/pour/rail/exit/reseed at the pinned rects" $
      once $ and
        [ pin scrollScene "hero"   (18, 49,  64, 64)
        , pin scrollScene "pour"   (42, 114, 16, 2)
        , pin scrollScene "rail"   (84, 49,  2, 128)
        , pin scrollScene "exit"   (18, 184, 20, 12)
        , pin scrollScene "reseed" (62, 184, 20, 12)
        ]
  , testProperty "scrollScene: hero rides the liveScene field64 band exactly" $
      once $ case (lookup "hero" scrollScene, lookup "field64" liveScene) of
        (Just h, Just f) ->
          (lrCol h, lrRow h, lrW h, lrH h) == (lrCol f, lrRow f, lrW f, lrH f)
        _ -> False
  , testProperty "scrollScene: pour + rail are display-only; hero/exit/reseed are controls" $
      once $ and
        (  [ maybe False (not . lrInteractive) (lookup nm scrollScene)
           | nm <- ["pour", "rail"] ]
        ++ [ maybe False lrInteractive (lookup nm scrollScene)
           | nm <- ["hero", "exit", "reseed"] ] )

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
  where
    pin scene nm (c, r, w, h) = case lookup nm scene of
      Just lr -> (lrCol lr, lrRow lr, lrW lr, lrH lr) == (c, r, w, h)
      Nothing -> False

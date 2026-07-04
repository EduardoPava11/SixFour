module Properties.CubeBrush (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.CubeBrush

-- A random aligned cube: depth 0..2, origin on its own grid.
genCube :: Gen Cube
genCube = do
  d <- choose (0, 2)
  let per = 8 `div` cubeSideOf d
  o <- (,,) <$> choose (0, per - 1) <*> choose (0, per - 1) <*> choose (0, per - 1)
  pure (Cube d o)

genCubes :: Gen [Cube]
genCubes = do
  n <- choose (0, 6)
  vectorOf n genCube

genVolume :: Gen [Integer]
genVolume = vectorOf (8 * 8 * 8) (choose (0, 255))

genDepths :: Gen [Int]
genDepths = vectorOf 8 (choose (0, 2))

tests :: TestTree
tests = testGroup "CubeBrush (resolution-typed paint: overlapping cubes, network constructs)"
  [ testGroup "The stroke algebra (semilattice: order-free, undo-friendly)"
      [ testProperty "strokes commute and duplicates absorb" $
          forAll genCubes lawStrokesCommuteAndAbsorb
      , testProperty "finest wins at overlaps (constructive)" $
          once lawFinestWinsAtOverlap
      , testProperty "a cube moves only its own voxels" $
          forAll arbitrary $ \d -> forAll arbitrary $ \o ->
            forAll genCubes $ \cs -> forAll genVolume (lawCubeIsLocal d o cs)
      ]

  , testGroup "Typed paint has full bandwidth (the pigeonhole dissolved)"
      [ testProperty "canonical cubes realize any region field; render agrees with PullField" $
          forAll genDepths $ \ds -> forAll genVolume (lawTypedPaintHasFullBandwidth ds)
      ]

  , testGroup "Why the network constructs"
      [ testProperty "clean refinement never increases exact SSE (monotone per stroke)" $
          forAll arbitrary $ \d -> forAll arbitrary $ \o ->
            forAll genVolume (lawWholeBlockDeepeningImprovesFidelity d o)
      , testProperty "TEETH: overlapping pull-only rendering can strictly regress (exact witness)" $
          once lawOverlapPullCanRegress
      ]
  ]

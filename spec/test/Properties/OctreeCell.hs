module Properties.OctreeCell (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.OctreeCell
import qualified SixFour.Spec.VoxelReduce as VR

-- Q16-range integers, including negatives (the regime the device uses).
genInt :: Gen Int
genInt = choose (-65536, 65536)

genV8 :: Gen (V8 Int)
genV8 = V8 <$> genInt <*> genInt <*> genInt <*> genInt
           <*> genInt <*> genInt <*> genInt <*> genInt

genBand :: Gen OctBand
genBand = OctBand <$> genInt
                  <*> ((,,,,,,) <$> genInt <*> genInt <*> genInt
                                <*> genInt <*> genInt <*> genInt <*> genInt)

genDetail :: Gen Detail
genDetail = (,,,,,,) <$> genInt <*> genInt <*> genInt
                     <*> genInt <*> genInt <*> genInt <*> genInt

-- A depth in {0,1,2} with a matching flat voxel list of length 8^depth.
genDepthXs :: Gen (Int, [Int])
genDepthXs = do
  d  <- elements [0, 1, 2]
  xs <- vectorOf (8 ^ d) genInt
  pure (d, xs)

tests :: TestTree
tests = testGroup "OctreeCell (2x2x2 <-> 1 octree: structured-leaf invariant)"
  [ testProperty "octant edge is an exact bijection: unliftOct . liftOct = id" $
      forAll genV8 lawOctReversible

  , testProperty "octant edge bijection (other direction): liftOct . unliftOct = id" $
      forAll genBand lawOctReversible'

  , testProperty "whole cube round-trips IFF leaf structured: collapse then lift = id" $
      forAll genDepthXs (uncurry lawCubeBijective)

  , testProperty "self-similar: a leaf is its own shape (Leaf l ~ Node (V8 (Leaf l')))" $
      forAll genV8 lawSelfSimilar

  , testProperty "per-scale weights expressible; unit weight is lossless" $
      forAll genDepthXs (uncurry lawUnitWeightLossless)

  , testProperty "scalar leaf is exact ONLY on a constant octant (measure-zero)" $
      forAll genInt lawScalarLeafFailsUnlessSmooth

  , -- golden pin: a fixed octant's coarse band (cross-language reproducible)
    testProperty "golden: liftOct (V8 10 20 30 44 10 20 30 44) coarse = 26" $
      once (ocCoarse (liftOct (V8 10 20 30 44 10 20 30 44)) == 26)

  , testProperty "octree depth: 256^3 -> 1 is 8 levels (octreeDepth 256 = 8)" $
      once (octreeDepth 256 == 8 && octreeDepth 64 == 6 && octreeDepth 16 == 4)

  , testProperty "self-similar ladder: 64^3->16^3 == 256^3->64^3 (2 levels each)" $
      once (levelsBetween 64 16 == 2 && levelsBetween 256 64 == 2 && lawLadderSelfSimilar)

  , testProperty "octant ladder round-trips (delegates to liftOct): synth . distill = id" $
      forAll genDepthXs (uncurry lawOctantLadderBijective)

  , testProperty "build->flatten IS a hylo: hylo flattenAlg buildCoalg == flatten . buildCube == id" $
      forAll genDepthXs (uncurry lawOctantBuildFlattenIsHylo)

  , testProperty "detailBand is the shared canonical band selector (slot order pinned; OOR = 0)" $
      forAll genDetail $ \d -> forAll genInt (lawDetailBandSelectsSlot d)

  , testProperty "cross-module: VoxelReduce 64->16 and 256->64 are each 2 octree levels" $
      once ( VR.reducedSide 2 64 == 16 && VR.reducedFrames 2 64 == 16
           && VR.reducedSide 2 256 == 64
           && levelsBetween 64 16 == 2 && levelsBetween 256 64 == 2 )
  ]

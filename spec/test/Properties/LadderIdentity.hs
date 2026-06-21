module Properties.LadderIdentity (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.OctreeCell (V8(..))
import SixFour.Spec.LadderIdentity

genInt :: Gen Int
genInt = choose (-65536, 65536)

genV8 :: Gen (V8 Int)
genV8 = V8 <$> genInt <*> genInt <*> genInt <*> genInt
           <*> genInt <*> genInt <*> genInt <*> genInt

genQuad :: Gen (Int, Int, Int, Int)
genQuad = (,,,) <$> genInt <*> genInt <*> genInt <*> genInt

tests :: TestTree
tests = testGroup "LadderIdentity (two operators named apart; octant pinned as the token substrate — B2)"
  [ testProperty "the two operators have different per-level data factors (4 != 8)" $
      once lawDistinctVolumeFactor

  , testProperty "detail shapes differ, proven by destructuring liftOct (7) vs liftQuad (3)" $
      forAll genV8 $ \v -> forAll genQuad $ \q -> lawDistinctDetailShape v q

  , testProperty "both reach a rung in 2 levels (levelsBetween 64 16 == 256 64 == 2)" $
      once lawSameLevelsPerRung

  , testProperty "voxel rungs are octant tiers: octantTierLeaves d == d^3 for 16/64/256" $
      once lawVolumeRungsAreOctant

  , testProperty "a Haar tier is a plane (s^2), not the s^3 octant volume (powers of two)" $
      forAll (elements [2, 4, 8, 16, 32, 64, 128, 256]) lawHaarTierIsPlaneNotVolume

  , testProperty "B2 pin: tokenSubstrate = VolumeOctant, withinRungOp = SpatialHaar, distinct" $
      once lawTokenSubstrateIsOctant

  , testProperty "shared self-similarity: 16^3:64^3 :: 64^3:256^3" $
      once lawLadderSelfSimilarShared
  ]

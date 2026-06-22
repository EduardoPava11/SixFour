module Properties.RungPivot (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.OctreeGenome (octreeLeafCount)
import SixFour.Spec.RungPivot

genCapture :: Int -> Gen [Int]
genCapture d = vectorOf (octreeLeafCount d) (choose (-32768, 32768))

tests :: TestTree
tests = testGroup "RungPivot (the canonical 64³-pivot rung; never-surfaced 32³/128³ latent)"
  [ testProperty "the pivot is 64" $ once lawPivotIs64
  , testProperty "a rung is exactly two octant levels" $ once lawRungIsTwoLevels
  , testProperty "the two rungs are self-similar (same octant distance)" $ once lawRungSelfSimilar
  , testProperty "the intermediate sits at the symmetric mid-level (32·128 = 64²)" $ once lawIntermediateIsMidLevel
  , testProperty "KEYSTONE: the intermediate never surfaces (sub-quantum collapse)" $ once lawIntermediateNeverSurfaces
  , testProperty "Down = Held, Up = Invented" $ once lawDownIsHeldUpIsInvented
  , testProperty "the Down rung's surfaced endpoint round-trips exactly" $
      forAll (choose (0, 3)) $ \d ->
        forAll (choose (0, d)) $ \k ->
          forAll (genCapture d) $ \cap -> lawRungEndpointExact k d cap
  ]

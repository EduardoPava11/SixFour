module Properties.SelfSupervisedRung (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.OctreeGenome (octreeLeafCount)
import SixFour.Spec.SelfSupervisedRung

-- a fine cube of the right length for a small depth d
genCube :: Int -> Gen [Int]
genCube d = vectorOf (octreeLeafCount d) (choose (-32768, 32768))

tests :: TestTree
tests = testGroup "SelfSupervisedRung (two self-supervision regimes; one operator)"
  [ testProperty "the supervision dichotomy is total and exclusive (Held=target, Invented=gate)" $
      once lawSupervisionMatchesRung
  , testProperty "SELF-SUPERVISION: the Held label is manufactured from the capture (refine.split==id)" $
      forAll (choose (0, 3)) $ \d ->
        forAll (choose (0, d)) $ \k ->
          forAll (genCube d) $ \cap -> lawHeldLabelIsDataManufactured k d cap
  , testProperty "the label-free Invented rung is scored by re-downsample CONSISTENCY" $
      forAll (choose (1, 3)) $ \d ->
        forAll (choose (1, d)) $ \k ->
          forAll (genCube d) $ \fine -> lawInventedScoredByConsistency k d fine
  , testProperty "one operator, two supervisions (scorers differ; θ_B reused)" $
      forAll (vectorOf 63 (choose (-2.0, 2.0))) $ \ps ->
        forAll (choose (0, 65536)) $ \v -> lawOneOperatorTwoSupervisions ps v
  , testProperty "the manufactured Held label is LEARNABLE (training drives heldLoss down)" $
      forAll (choose (0, 1000000)) lawSelfSupervisedLabelIsLearnable
  ]

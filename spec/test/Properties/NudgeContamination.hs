module Properties.NudgeContamination (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.NudgeContamination

-- A valid (k, d, cube): an 8^d cube pooled 1 <= k <= d levels. Small d so octantDistill runs fast.
genCase :: Gen (Int, Int, [Int])
genCase = do
  d <- choose (1, 2)                 -- 8 or 64 voxels
  k <- choose (1, d)
  cube <- vectorOf (8 ^ d) (choose (0, 4096))
  pure (k, d, cube)

tests :: TestTree
tests = testGroup "NudgeContamination (the user-taste quarantine: a nudge cannot move the self-supervised energy)"
  [ testProperty "KEYSTONE: a taste nudge leaves the coarse/energy band invariant (gate still passes)" $
      forAll genCase $ \(k, d, cube) -> forAll (choose (-50, 50)) $ \b ->
        lawUserNudgeIsTasteOffEnergy k d b cube
  , testProperty "TEETH: a leaky coarse-touching nudge drifts the energy band and the gate rejects it" $
      forAll genCase $ \(k, d, cube) -> lawLeakyCoarseNudgeDriftsEnergy k d cube
  , testProperty "taste nudges share the gate's invented-detail null space (any two both pass)" $
      forAll genCase $ \(k, d, cube) -> forAll (choose (-50, 50)) $ \b1 -> forAll (choose (-50, 50)) $ \b2 ->
        lawTasteNudgesShareGateNullSpace k d b1 b2 cube
  ]

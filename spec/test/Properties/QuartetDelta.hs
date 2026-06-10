module Properties.QuartetDelta (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Test.QuickCheck

import SixFour.Spec.Color        (OKLab(..))
import SixFour.Spec.QuartetDelta

genOKLab :: Gen OKLab
genOKLab = OKLab <$> choose (0, 1) <*> choose (-0.4, 0.4) <*> choose (-0.4, 0.4)

genQSlot :: Gen QSlot
genQSlot = QSlot <$> genOKLab <*> genOKLab <*> genOKLab <*> genOKLab

-- A list of K aligned QSlots (a quartet's slot trajectories).
genSlots :: Gen [QSlot]
genSlots = listOf genQSlot

genThreshold :: Gen Double
genThreshold = choose (0, 2)

tests :: TestTree
tests = testGroup "QuartetDelta (Act II — 4⁴ quartet core/displacement)"
  [ testProperty "a static slot (all 4 frames equal) has zero displacement" $
      forAll genOKLab lawStaticSlotZeroDisplacement

  , testProperty "displacement >= each endpoint hop" $
      forAll genQSlot lawDisplacementGeqEndpoints

  , testProperty "delta count matches the frame window" $
      forAll genQSlot lawDeltaCount

  , testProperty "slot count is preserved through toSlots (4 equal-length palettes)" $
      forAll (choose (0, 16)) $ \n ->
        forAll ((,,,) <$> vectorOf n genOKLab <*> vectorOf n genOKLab
                      <*> vectorOf n genOKLab <*> vectorOf n genOKLab) $
          \(a, b, c, d) -> lawSlotCountPreserved a b c d

  , testProperty "core membership is monotone in the threshold" $
      forAll genSlots lawCoreMonotoneInThreshold

  , testProperty "the core is the low-displacement slots" $
      forAll genThreshold $ \t -> forAll genSlots (lawCoreIsLowDisplacement t)
  ]

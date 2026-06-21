module Properties.NudgeStep (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.LatentNavigation (Gesture(..))
import SixFour.Spec.NudgeStep

genGesture :: Gen Gesture
genGesture = Gesture <$> choose (-8, 8)
                     <*> ((,) <$> choose (-64, 64) <*> choose (-64, 64))

genVoxels :: Gen [Double]
genVoxels = listOf (choose (-2.0, 2.0))

tests :: TestTree
tests = testGroup "NudgeStep (one gesture -> one shared-latent step -> P re-projects a fresh 16^3 Q16)"
  [ testProperty "a nudge is EXACTLY one gesture compose, not a batch" $
      forAll genGesture $ \g -> forAll genVoxels $ \xs ->
        lawSingleNudgeIsOneStep g xs

  , testProperty "nudge then project = a well-defined fresh 16^3 (same shape, total)" $
      forAll genGesture $ \g -> forAll genVoxels $ \xs ->
        lawNudgeThenProject g xs

  , testProperty "P is many-to-one: distinct latents collide to one 16^3 (so P has no inverse)" $
      once lawProjectIsManyToOne

  , testProperty "undo = history-replay, delegated to LatentNavigation.lawUndoNeedsHistoryNotInverse" $
      once lawNudgeUndoIsHistory
  ]

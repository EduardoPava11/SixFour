module Properties.BudgetHead (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.BudgetHead
import SixFour.Spec.SelfSimilarReconstruct (expandRungVolume)
import SixFour.Spec.SwapCarrier (SwapPayload(..), SwapProfile(..))
import SixFour.Spec.Lineage     (GeneTag(..))
import SixFour.Spec.Trade       (GeneId(..), CreatorId(..))

defaultTag :: GeneTag
defaultTag = GeneTag (GeneId 1) (CreatorId 1) [] 0

showcasePay, grantPay :: SwapPayload
showcasePay = SwapPayload Showcase "theta-up" defaultTag []
grantPay    = SwapPayload Grant    "theta-up" defaultTag (replicate 21 7)

genHead :: Gen BudgetHead
genHead = BudgetHead <$> listOf (choose (-2, 5))

genVol :: Gen (Int, [Int])
genVol = do
  side <- choose (1, 3)
  vol  <- vectorOf (side*side*side) (choose (0, 65535))
  pure (side, vol)

tests :: TestTree
tests = testGroup "BudgetHead (advisory budget: safe because it only gates the detail Maybe fork)"
  [ testProperty "GOLDEN: a starved head reproduces the byte-exact floor (replicate 8 200)" $
      once goldenStarvedHeadIsFloor

  , testProperty "KEYSTONE: only the Maybe-fork routing is floor-safe (adversarial family)" $
      forAll genVol $ \(s,vol) -> lawOnlyMaybeForkIsFloorSafe s vol

  , testProperty "NON-VACUITY: MaybeForkOnly reproduces the floor; TruncateToEstimate does NOT" $
      once ( runStrategy MaybeForkOnly (starveHead defaultHead) 1 [200] == expandRungVolume 1 [200] Nothing
           && runStrategy TruncateToEstimate defaultHead 1 [200] /= expandRungVolume 1 [200] Nothing )

  , testProperty "capped bound: spent packets never exceed the cap, even for a lying head" $
      forAll genHead $ \bh -> forAll (choose (0,20)) $ \cap -> forAll genVol $ \(s,vol) ->
        lawBudgetHeadBoundsActualPackets bh cap s vol

  , testProperty "forward-compatible: budget-blind extractor keeps expressionSource + swapMajor" $
      forAll genHead $ \bh ->
        lawBudgetHeadForwardCompatible showcasePay bh && lawBudgetHeadForwardCompatible grantPay bh

  , testProperty "tag identity is advisory-independent (two advisories, one base, same bytes)" $
      forAll genHead $ \bh1 -> forAll genHead $ \bh2 ->
        lawBudgetAdvisoryDoesNotChangeTagIdentity showcasePay bh1 bh2
        && lawBudgetAdvisoryDoesNotChangeTagIdentity grantPay bh1 bh2
  ]

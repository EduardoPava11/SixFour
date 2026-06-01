{- |
Module      : Properties.PaletteOracle
Description : Property tests for 'SixFour.Spec.PaletteOracle' — the concrete value
              head (aesthetic reward) + reference policy for the search.

Palettes are generated at depth ≥ 3 (≥ 8 leaves) so the Gaussian colour-entropy
term has a full-rank covariance (a 2-leaf palette is rank-deficient ⇒ −∞ entropy).
-}
module Properties.PaletteOracle (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Test.QuickCheck

import SixFour.Spec.Color         (OKLab(..))
import SixFour.Spec.PairTree      (HaarPalette(..))
import SixFour.Spec.PaletteSearch (leafNode, runSearch, defaultHyperparams, Halting(..), stVisits)
import SixFour.Spec.PaletteOracle

genOKLab :: Gen OKLab
genOKLab = OKLab <$> choose (0, 1) <*> choose (-0.4, 0.4) <*> choose (-0.4, 0.4)

-- | Well-formed palette of depth 3..5 (≥ 8 leaves ⇒ non-degenerate covariance).
genHaar :: Gen HaarPalette
genHaar = do
  d    <- choose (3, 5) :: Gen Int
  rt   <- genOKLab
  lvls <- mapM (\i -> vectorOf (2 ^ i) genOKLab) [0 .. d - 1]
  pure (HaarPalette rt lvls)

genWeights :: Gen RewardWeights
genWeights = RewardWeights <$> choose (0, 2) <*> choose (0, 2)

tests :: TestTree
tests = testGroup "PaletteOracle (concrete value head + reference policy)"
  [ testProperty "reward is deterministic" $
      forAll genWeights $ \w -> forAll genHaar $ lawRewardDeterministic w
  , testProperty "reward is linear in the weights" $
      forAll (choose (0, 5)) $ \k -> forAll genWeights $ \w -> forAll genHaar $ lawRewardLinear k w
  , testProperty "reference policy targets only in-range moves" $
      forAll genHaar lawReferencePolicyInRange
  , testProperty "reference policy priors sum to 1" $
      forAll genHaar lawReferencePolicyNormalized
  , testProperty "the oracle's value equals the reward" $
      forAll genWeights $ \w -> forAll genHaar $ lawOracleValueIsReward w
  , testProperty "search with the concrete oracle grows the tree (N iters ⇒ N visits)" $
      forAll genHaar $ \rt -> forAll (choose (1, 40)) $ \n -> forAll (choose (1, 1000000)) $ \seed ->
        stVisits (runSearch (referenceOracle defaultWeights) defaultHyperparams
                            (HaltOnVisits n) seed (leafNode 1.0 rt)) == n
  ]

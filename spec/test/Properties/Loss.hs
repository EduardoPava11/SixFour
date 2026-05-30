{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}

module Properties.Loss (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Test.QuickCheck

import qualified Data.Vector         as V
import           Data.Maybe          (fromJust)

import SixFour.Spec.Color    (OKLab(..))
import SixFour.Spec.Palette  (mkPalette)
import SixFour.Spec.Cyclic   (CyclicStack(..))
import SixFour.Spec.PairTree (HaarPalette(..))
import SixFour.Spec.Loss

genOKLabInGamut :: Gen OKLab
genOKLabInGamut =
  OKLab <$> choose (0, 1) <*> choose (-0.3, 0.3) <*> choose (-0.3, 0.3)

-- A small Haar tree of depth 3 (8 leaves) with bounded offsets, so every
-- reconstructed leaf stays in gamut. Mirrors Properties.PairTree's pattern.
genBoundedHaar :: Gen HaarPalette
genBoundedHaar = do
  rt  <- OKLab <$> choose (0.4, 0.6) <*> choose (-0.05, 0.05) <*> choose (-0.05, 0.05)
  lvs <- mapM (\i -> vectorOf (2 ^ i)
                 (OKLab <$> choose (-0.02, 0.02) <*> choose (-0.01, 0.01) <*> choose (-0.01, 0.01)))
              [0 .. 2]
  pure (HaarPalette rt lvs)

-- A trivial CyclicStack with a single 4-colour frame (lets us call
-- fidelityLoss without huge generation cost). Type-level T=1, K=4.
genTinyStack :: Gen (CyclicStack 1 4)
genTinyStack = do
  cs <- vectorOf 4 genOKLabInGamut
  let pal = fromJust (mkPalette @4 cs)
      w   = V.fromList [0.25, 0.25, 0.25, 0.25]
  pure (CyclicStack (V.fromList [(pal, w)]))

tests :: TestTree
tests = testGroup "Loss (math-first training loss: fidelity + coverage + Ou-Luo beauty)"

  [ testProperty "fidelity loss is non-negative (Bures-Wasserstein squared)" $
      forAll genBoundedHaar $ \hp ->
        forAll genTinyStack (lawFidelityNonNegative hp)

  , testProperty "coverage loss ∈ [0, 1]" $
      forAll genBoundedHaar lawCoverageBounded

  , testProperty "chromatic-similarity term is monotone non-increasing in chromatic distance" $
      forAll genOKLabInGamut $ \c ->
        forAll (choose (-0.2, 0.2)) $ \d1 ->
          forAll (choose (-0.2, 0.2)) $ \d2 ->
            lawBeautyMonotonicInChromaticSimilarity c d1 d2

  , testProperty "lightness-sum term is monotone in lightness" $
      forAll genOKLabInGamut $ \c1 ->
        forAll genOKLabInGamut $ \c2 ->
          forAll (choose (-0.3, 0.3)) $ \dL ->
            lawBeautyMonotonicInLightnessSum c1 c2 dL

  , testProperty "beauty loss decomposes exactly over Haar σ-pairs" $
      forAll genBoundedHaar lawBeautyDecomposesOverPairs

  , testProperty "default loss weights sum to a positive number" $
      once (lawLossWeightsSumPositive defaultLossWeights)

  , testProperty "Ou-Luo terms have expected bounds: chromaticSimilarity ∈ (0,1], lightnessAsymmetry ∈ [0,1], lightnessSum ∈ [0,1]" $
      forAll genOKLabInGamut $ \c1 ->
        forAll genOKLabInGamut $ \c2 ->
             let chrom = pairChromaticSimilarity c1 c2
                 asym  = pairLightnessAsymmetry  c1 c2
                 lsum  = pairLightnessSum        c1 c2
             in chrom > 0 && chrom <= 1
             && asym  >= 0 && asym  <= 1
             && lsum  >= 0 && lsum  <= 1

  , testProperty "identical pair has chromatic-similarity = 1 and lightness-asymmetry = 0" $
      forAll genOKLabInGamut $ \c ->
        pairChromaticSimilarity c c == 1.0
        && pairLightnessAsymmetry c c == 0.0

  , testProperty "leaf-list fidelity core agrees exactly with the Haar-tree fidelity loss" $
      forAll genBoundedHaar $ \hp ->
        forAll genTinyStack (lawFidelityLeavesAgreesWithHaar hp)

  , testProperty "leaf-list beauty core = negated sum over adjacent leaf pairs" $
      forAll (vectorOf 8 genOKLabInGamut) lawBeautyLeavesAgreesWithPairs

  , testProperty "PonderNet halting distribution sums to 1 over the static unroll" $
      forAll (vectorOf 8 (choose (0, 1))) lawHaltingDistributionSumsToOne

  , testProperty "PonderNet halting loss (KL to geometric prior) is non-negative" $
      forAll (choose (0.05, 0.95)) $ \lp ->
        forAll (vectorOf 8 (choose (0, 1))) (lawHaltingLossNonNegative lp)

  , testProperty "PonderNet halting loss is zero when the halting dist IS the prior" $
      once lawHaltingLossZeroAtPrior
  ]

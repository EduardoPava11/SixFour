{- |
Module      : Properties.PersonalGenome
Description : Property tests for 'SixFour.Spec.PersonalGenome' — the per-device
              taste lifecycle (cold start, replay determinism, gated promotion).

Wires the eight exported laws into the suite (the source module's "test wiring
pending — build step 3"). Generators mirror 'Properties.PreferenceUpdate': small
consistent-dimension embeddings keep the bound and convex-descent checks sharp;
the cold-start and replay laws are dimension-structural and hold at any vector
size, so an 8-D generator faithfully exercises a 770-D taste vector's laws.
-}
module Properties.PersonalGenome (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Test.QuickCheck

import SixFour.Spec.Preference     (Embedding)
import SixFour.Spec.PersonalGenome

-- | A small vector dimension keeps the finite checks sharp.
genDim :: Gen Int
genDim = choose (1, 8)

genVecN :: Int -> Gen [Double]
genVecN n = vectorOf n (choose (-2, 2))

genEmb :: Gen Embedding
genEmb = genDim >>= genVecN

genPickN :: Int -> Gen Pick
genPickN n = (,) <$> genVecN n <*> genVecN n

-- | A single-dimension ordered pick log (oldest first).
genLog :: Gen [Pick]
genLog = do
  n <- genDim
  k <- choose (0, 8)
  vectorOf k (genPickN n)

genGenome :: Gen PersonalGenome
genGenome = do
  n  <- genDim
  th <- genVecN n
  c  <- choose (0, 40)
  pure (PersonalGenome th c genomeVersion)

tests :: TestTree
tests = testGroup "PersonalGenome (per-device taste lifecycle)"
  [ testProperty "cold start is the deterministic floor (beta=0, score=0, n=0)" $
      forAll genEmb lawColdStartIsDeterministicFloor
  , testProperty "replay from cold start equals btFit over the ordered log" $
      forAll genLog lawReplayDeterministic
  , testProperty "replay is checkpoint-prunable (prefix++tail equals checkpoint then tail)" $
      forAll genLog $ \prefix -> forAll genLog $ \tl ->
        lawReplayFromCheckpoint prefix tl
  , testProperty "personalBeta is a monotone trust ramp in the Compare count" $
      forAll (choose (0, 100000)) $ \a -> forAll (choose (0, 100000)) $ \b ->
        lawBetaMonotoneRamp a b
  , testProperty "one applyPick from cold start keeps theta bounded by dmax/lambda" $
      forAll (choose (0.1, 4)) $ \dmax -> forAll genDim $ \n ->
        forAll (vectorOf n (choose (-dmax, dmax))) $ \d ->
          lawApplyPickBounded dmax (d, replicate n 0)
  , testProperty "an informative pick does not increase the regularized objective" $
      forAll genDim $ \n ->
        forAll (genVecN n) $ \theta -> forAll (genPickN n) $ \pick ->
          forAll (choose (0.001, 0.5)) $ \eta ->
            lawRegularizedObjectiveDecreases eta theta pick
  , testProperty "the gate rejects regressions (a failing candidate is not promoted)" $
      forAll genGenome $ \current -> forAll genGenome $ \candidate ->
        forAll genLog $ \recent -> lawGateRejectsRegression current candidate recent
  , testProperty "promotion is exactly gated (candidate iff gatePasses, else current)" $
      forAll genGenome $ \current -> forAll genGenome $ \candidate ->
        forAll genLog $ \recent -> lawGatedPromotion current candidate recent
  ]

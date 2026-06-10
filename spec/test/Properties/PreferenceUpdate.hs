{- |
Module      : Properties.PreferenceUpdate
Description : Property tests for 'SixFour.Spec.PreferenceUpdate' — the
              on-device Bradley–Terry SGD step.

Fold order-independence is the DOCUMENTED NON-LAW (SGD never commutes) and is
deliberately absent here.
-}
module Properties.PreferenceUpdate (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Test.QuickCheck

import SixFour.Spec.PreferenceUpdate

-- | Same-dimension (theta, winner, loser) triples — small dims keep the
-- finite-difference check sharp.
genTriple :: Gen ([Double], [Double], [Double])
genTriple = do
  n <- choose (1, 8)
  t <- vectorOf n (choose (-2, 2))
  w <- vectorOf n (choose (-2, 2))
  l <- vectorOf n (choose (-2, 2))
  pure (t, w, l)

tests :: TestTree
tests = testGroup "PreferenceUpdate (per-Compare Bradley-Terry SGD)"
  [ testProperty "gradient matches central finite differences (1e-6)" $
      forAll genTriple $ \(t, w, l) -> lawGradientFiniteDiff t w l
  , testProperty "one small-eta step strictly decreases the pair loss" $
      forAll genTriple $ \(t, w, l) -> forAll (choose (0.001, 1)) $ \eta ->
        lawStepDecreasesLoss eta t w l
  , testProperty "swap antisymmetry: P(w>l) + P(l>w) = 1" $
      forAll genTriple $ \(t, w, l) -> lawSwapAntisymmetry t w l
  , testProperty "L2 keeps theta bounded under any Compare stream" $
      forAll genTriple $ \(t, w, l) ->
      forAll (choose (0.01, 1)) $ \eta -> forAll (choose (0.001, 1)) $ \lam ->
        let dmax = maximum (0 : map abs (zipWith (-) w l))
        in lawThetaBounded eta lam dmax t w l
  , testProperty "btFit folds oldest-first (definition pin, order-DEPENDENT)" $
      forAll genTriple $ \(t, w, l) ->
        btFit defaultEta defaultLambda t [(w, l), (l, w)]
          == btUpdate defaultEta defaultLambda
               (btUpdate defaultEta defaultLambda t (w, l)) (l, w)
  , testProperty "theta dimension is the 770-D atlas embedding" $
      property (thetaDim == 770)
  ]

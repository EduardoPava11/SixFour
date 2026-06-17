{-# LANGUAGE ScopedTypeVariables #-}

module Properties.GumbelSearch (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Test.QuickCheck

import SixFour.Spec.GumbelSearch

-- Gumbel-AlphaZero root selection (M5) + the Q16 cross-tier determinism boundary. The headline is
-- lawArgmaxKeyDependsOnlyOnKeys: a GPU float that differs sub-key from the CPU still picks the same
-- move (the antidote to Metal's unspecified simd_sum reduction order).

-- A pair of value lists that share Q16 keys: same integer key, values nudged +0.1 vs +0.3 of a
-- Q16 unit (both well inside the key's bucket, so the float wobble is sub-key).
genKeyPair :: Gen ([(Double, Int)], [(Double, Int)], Int)
genKeyPair = do
  n    <- choose (1, 8)
  keys <- vectorOf n (choose (-100000, 100000) :: Gen Int)
  seed <- arbitrary
  let mk off = [ ((fromIntegral k + off) / 65536, i) | (k, i) <- zip keys [0 ..] ]
  pure (mk 0.1, mk 0.3, seed)

genPaired :: Gen ([Double], [Double])
genPaired = do
  n  <- choose (1, 8)
  ps <- vectorOf n (choose (0, 1))
  vs <- vectorOf n (choose (0, 1))
  pure (ps, vs)

genVisits :: Gen [Int]
genVisits = do
  n <- choose (0, 8)
  vectorOf n (choose (0, 100))

tests :: TestTree
tests = testGroup "GumbelSearch (root selection + the Q16 cross-tier determinism key)"

  [ testProperty "argmax decision depends ONLY on Q16 keys (sub-key float wobble cannot flip it)" $
      forAll genKeyPair $ \(a, b, s) -> lawArgmaxKeyDependsOnlyOnKeys a b s

  , testProperty "Sequential Halving returns an in-range arm (lawSHWinnerInRange)" $
      forAll genPaired $ \(ps, vs) -> lawSHWinnerInRange ps vs

  , testProperty "with distinct value keys, SH picks the max-value arm (lawSHPicksMaxValue)" $
      forAll genPaired $ \(ps, vs) -> lawSHPicksMaxValue ps vs

  , testProperty "the SH winner has the max visit count (lawSHWinnerHasMaxVisits)" $
      forAll genPaired $ \(ps, vs) -> lawSHWinnerHasMaxVisits ps vs

  , testProperty "the visit policy target sums to 1 (lawVisitTargetSumsToOne)" $
      forAll genVisits lawVisitTargetSumsToOne

  , testProperty "GOLDEN: argmaxKeyWithSeed picks the max-key index" $
      once $ fst (argmaxKeyWithSeed [(0.1, 0), (0.9, 1), (0.5, 2)] 0) == 1

  , testProperty "GOLDEN: SH over values [0.2,0.9,0.5] wins arm 1, with its max visits" $
      once $
        let (w, visits) = sequentialHalving [0.3, 0.3, 0.4] [0.2, 0.9, 0.5]
        in w == 1 && visits !! 1 == maximum visits
  ]

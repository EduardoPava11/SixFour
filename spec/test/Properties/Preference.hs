module Properties.Preference (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Test.QuickCheck
import Data.List (nub)

import SixFour.Spec.Preference

genEmb :: Gen Embedding
genEmb = vectorOf 3 (choose (-1, 1))

genTheta :: Gen [Double]
genTheta = vectorOf 3 (choose (-1, 1))

tests :: TestTree
tests = testGroup "Preference (continuous personalization: utility + DPP gallery)"
  [ -- Bradley–Terry link: the preference probability is well-behaved.
    testProperty "btProbability: σ(0)=½, symmetric, monotone in the utility gap" $
      forAll (choose (-5, 5)) $ \g ->
        forAll (choose (0.01, 3)) $ \d ->
             abs (btProbability 0 - 0.5) < 1e-12
          && abs (btProbability g + btProbability (negate g) - 1) < 1e-9
          && btProbability (g + d) > btProbability g

  , testProperty "prefers is shift-invariant (a utility bias changes nothing)" $
      forAll genTheta $ \th ->
        forAll genEmb $ \a -> forAll genEmb $ \b ->
          forAll (choose (-3, 3)) $ \c ->
            let u  = linearUtility th
                u' = \x -> u x + c
            in prefers u a b == prefers u' a b

  , testProperty "prefers is a strict total order (transitive, antisymmetric)" $
      forAll genTheta $ \th ->
        forAll genEmb $ \a -> forAll genEmb $ \b -> forAll genEmb $ \c ->
          let u = linearUtility th
          in not (prefers u a b && prefers u b c) || prefers u a c

  , -- RBF similarity basics.
    testProperty "rbfKernel: K(x,x)=1, symmetric, ∈(0,1]" $
      forAll (choose (0.1, 2)) $ \ell ->
        forAll genEmb $ \x -> forAll genEmb $ \y ->
          let kxy = rbfKernel ell x y
          in abs (rbfKernel ell x x - 1) < 1e-12
             && abs (kxy - rbfKernel ell y x) < 1e-12
             && kxy > 0 && kxy <= 1 + 1e-12

  , -- Cholesky log-det against hand-computed determinants.
    testProperty "choleskyLogDet: diag(2,3,4) ⇒ log 24; [[2,1],[1,2]] ⇒ log 3" $
      once $
        case (choleskyLogDet [[2,0,0],[0,3,0],[0,0,4]], choleskyLogDet [[2,1],[1,2]]) of
          (Just d1, Just d2) -> abs (d1 - log 24) < 1e-9 && abs (d2 - log 3) < 1e-9
          _                  -> False

  , testProperty "choleskyLogDet: a singular (duplicate-row) matrix is rejected" $
      once $ choleskyLogDet [[1,1],[1,1]] == Nothing

  , -- DPP diversity: a single item has zero log-volume; duplicates collapse it.
    testProperty "dppLogDet: singleton ⇒ 0; an exact duplicate ⇒ Nothing (no volume)" $
      forAll genEmb $ \x ->
        case dppLogDet 1.0 [x] of
          Just d  -> abs d < 1e-9 && dppLogDet 1.0 [x, x] == Nothing
          Nothing -> False

  , -- Diversity increases with separation: a spread pair spans more volume than a
    -- close pair (the property the gallery exploits).
    testProperty "dppLogDet: well-separated pair is more diverse than a close pair" $
      once $
        let far   = dppLogDet 0.5 [[0,0,0], [1,1,1]]
            close = dppLogDet 0.5 [[0,0,0], [0.02,0,0]]
        in case (far, close) of
             (Just f, Just c) -> f > c
             _                -> False

  , -- The gallery (continuous MAP-Elites replacement): distinct, bounded, quality-led.
    testProperty "greedyGallery returns distinct indices, |gallery| ≤ k" $
      forAll (choose (1, 4)) $ \k ->
        forAll (listOf1 ((,) <$> choose (-1, 1) <*> genEmb)) $ \items ->
          let g = greedyGallery k 1.0 0.5 items
          in length g == length (nub g)
             && length g <= k
             && all (\i -> i >= 0 && i < length items) g

  , testProperty "greedyGallery: high α ⇒ the first pick is the max-utility item" $
      once $
        let items = [ (0.1, [0,0,0]), (0.9, [1,0,0]), (0.3, [0,1,0]) ]
            g     = greedyGallery 1 5.0 0.5 items
        in g == [1]

  , -- With pure diversity (α=0), three collinear points ⇒ the two extremes.
    testProperty "greedyGallery (α=0): 3 collinear points ⇒ the two extremes" $
      once $
        let items = [ (0, [0,0,0]), (0, [0.5,0,0]), (0, [1,0,0]) ]
            g     = greedyGallery 2 0.0 0.4 items
        in g == [0, 2] || g == [2, 0]
  ]

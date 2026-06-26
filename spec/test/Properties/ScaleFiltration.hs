module Properties.ScaleFiltration (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.ScaleFiltration

-- An octant address: a short word over the 8-symbol octant alphabet (depth ≤ 6).
genPath :: Gen Path
genPath = do
  n <- choose (0, 6)
  vectorOf n (choose (0, 7))

-- A ball level (allow a couple past the max depth to exercise the empty tail).
genLevel :: Gen Int
genLevel = choose (0, 8)

tests :: TestTree
tests = testGroup "ScaleFiltration (the scale spine as a descending chain + octree-ball ULTRAMETRIC)"
  [ testGroup "The s-adic valuation is an ULTRAMETRIC (the non-archimedean scale metric)"
      [ testProperty "symmetric" $
          forAll genPath $ \p -> forAll genPath $ \q -> lawValuationSymmetric p q
      , testProperty "STRONG triangle: v(p,r) ≥ min(v(p,q), v(q,r))" $
          forAll genPath $ \p -> forAll genPath $ \q -> forAll genPath $ \r ->
            lawValuationUltrametric p q r
      , testProperty "isosceles theorem: the minimum valuation repeats in every triangle" $
          forAll genPath $ \p -> forAll genPath $ \q -> forAll genPath $ \r ->
            lawUltrametricIsIsosceles p q r
      ]

  , testGroup "DISTINCT from d6/ℓ¹ (archimedean) — closes the 'd6 is 2-adic' overclaim"
      [ testProperty "ℓ¹ word metric is NOT an ultrametric (a 1,2,3 chain is not isosceles)" $
          once lawL1NotUltrametric
      ]

  , testGroup "Octree balls = nested clopen cylinders (the filtration)"
      [ testProperty "finer ball ⊆ coarser ball" $
          forAll genLevel $ \n -> forAll genPath $ \p -> forAll genPath $ \q ->
            lawBallsNested n p q
      , testProperty "ball membership ⟺ shares ≥ n leading octant digits" $
          forAll genLevel $ \n -> forAll genPath $ \p -> forAll genPath $ \q ->
            lawBallIsValuationSublevel n p q
      ]

  , testGroup "Descending sublattice chain refines by b = sⁿ per level"
      [ testProperty "[L_k : L_{k+1}] = sⁿ for any base s, dimension n" lawDescendingChainIndex
      , testProperty "the shipped 2×2×2 octant: branching 2 3 == 8" $
          once lawOctantBranchingIs8
      ]
  ]

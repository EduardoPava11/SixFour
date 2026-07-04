module Properties.RootLatticeDecoder (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.RootLatticeDecoder
import SixFour.Spec.RootLatticeDetail (fromRootCoords)

-- A dyadic point of the Σ=0 plane in dimension b: mean-centred sixteenths, the shape of
-- a Z[1/2] model prediction of the detail band.
genPlanePoint :: Int -> Gen [Rational]
genPlanePoint b = do
  raw <- vectorOf b (choose (-64, 64 :: Integer))
  let v = map (\k -> fromInteger k / 16) raw
      m = sum v / fromIntegral b
  pure (map (subtract m) v)

-- A generic (tie-free) plane point: off the Voronoi walls, where the chart-level
-- equivariance/folding laws are stated.
genGenericPoint :: Int -> Gen [Rational]
genGenericPoint b = genPlanePoint b `suchThat` genericPoint

-- A lattice point of A_{b-1} via the free root-coordinate chart of RootLatticeDetail.
genLatticePoint :: Int -> Gen [Integer]
genLatticePoint b = fromRootCoords b <$> vectorOf (b - 1) (choose (-8, 8))

-- The shipped octant branching.
octant :: Int
octant = 8

tests :: TestTree
tests = testGroup "RootLatticeDecoder (inference on the detail band = exact CVP on A_{b-1})"
  [ testGroup "Global optimality certificate (roots = Voronoi-relevant vectors), any input"
      [ testProperty "A_7 (shipped): decode lands in ker(sum)" $
          forAll (genPlanePoint octant) lawDecodeInLattice
      , testProperty "A_7 (shipped): decode beats all 56 roots (global CVP, exact)" $
          forAll (genPlanePoint octant) lawDecodeVoronoiOptimal
      , testProperty "any branching b in [2..10]: in-lattice AND root-optimal" $
          forAll (choose (2, 10)) $ \b -> forAll (genPlanePoint b) $ \x ->
            lawDecodeInLattice x && lawDecodeVoronoiOptimal x
      , testProperty "teeth: b=3 decode == brute-force nearest over an exhaustive box" $
          forAll (genPlanePoint 3) lawDecodeMatchesBruteForce
      ]

  , testGroup "Zero residual is a fixed point"
      [ testProperty "a lattice point decodes to itself" $
          forAll (genLatticePoint octant) lawDecodeIdempotentOnLattice
      ]

  , testGroup "Gauge honesty on the generic stratum (geometry, not chart)"
      [ testProperty "translation by a lattice vector commutes with decode" $
          forAll (genGenericPoint octant) $ \x ->
            forAll (genLatticePoint octant) $ \lam ->
              lawDecodeTranslationEquivariant x lam
      , testProperty "Weyl group S_8 (coordinate permutations) commutes with decode" $
          forAll (genGenericPoint octant) $ \x ->
            forAll (shuffle [0 .. octant - 1]) $ \perm ->
              lawDecodeWeylEquivariant x perm
      ]

  , testGroup "The WIRED folding (sort -> decode -> unsort == decode; learn only the residual)"
      [ testProperty "A_7 (shipped): decoding factors through the fundamental-chamber fold" $
          forAll (genGenericPoint octant) lawDecodeFactorsThroughFold
      , testProperty "any branching b in [3..10]: folding factorization holds" $
          forAll (choose (3, 10)) $ \b ->
            forAll (genPlanePoint b `suchThat` genericPoint) lawDecodeFactorsThroughFold
      ]
  ]

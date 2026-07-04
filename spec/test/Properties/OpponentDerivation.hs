module Properties.OpponentDerivation (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.OpponentDerivation

genRGB :: Gen (Integer, Integer, Integer)
genRGB = (,,) <$> c <*> c <*> c where c = choose (-500, 500)

genFunctional :: Gen (Integer, Integer, Integer)
genFunctional = (,,) <$> c <*> c <*> c where c = choose (-6, 6)

tests :: TestTree
tests = testGroup "OpponentDerivation (Lab is a theorem: the isotypic decomposition of S3 on RGB)"
  [ testGroup "The decomposition is derived, not chosen"
      [ testProperty "luma spans the trivial rep: invariant iff p == q == r (the iff)" $
          forAll genFunctional lawLumaIsTheUniqueInvariant
      , testProperty "chroma is A_2 = ker Sigma — the b=3 instance of the octant SES" $
          forAll genRGB lawChromaIsA2OfChannels
      ]

  , testGroup "The group acts as Eisenstein units"
      [ testProperty "root chart: 3-cycle = omega (det 1, tr -1, M^3=I); swap = reflection" $
          forAll genRGB lawRootChartIsEquivariant
      ]

  , testGroup "The stored chart's price, and the determinant's two primes"
      [ testProperty "index 2 in A_2: b-a = 2*alpha2; parity obstruction; half-integral cycle" $
          forAll arbitrary $ \c1 -> forAll arbitrary $ \c2 ->
            forAll genRGB (lawStoredChartTradesSymmetryForBytes c1 c2)
      , testProperty "det 6 = 3 x 2, each factor a named lattice index (SES owns 3, chart owns 2)" $
          forAll genRGB lawDetIsProductOfIndices
      ]

  , testGroup "The image congruences and the exact inverse"
      [ testProperty "fromLab . opponent == id; image iff two congruences; teeth on both" $
          forAll genRGB lawInverseAndImage
      ]
  ]

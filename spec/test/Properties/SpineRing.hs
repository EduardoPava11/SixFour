module Properties.SpineRing (tests) where

import Data.List (sort)
import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.SpineRing

-- The depth-1 transported kernel, for the boundary teeth test.
sortedKernel :: [Integer]
sortedKernel = sort (tCollapseKernelChart 1)

-- A product-ring element at depth k (coordinates reduced by the laws themselves).
genTriple :: Gen (Integer, Integer, Integer)
genTriple = (,,) <$> c <*> c <*> c where c = choose (0, 255)

tests :: TestTree
tests = testGroup "SpineRing (DECISION: spine algebra = product (Z_2)^3; Morton = chart, 8-adic = view)"
  [ testGroup "Axis identity exists in the product and CANNOT exist on the 8-adic side"
      [ testProperty "e_x + e_y + e_t = 1, orthogonal, idempotent (depths 1..8)" $
          once (all lawAxisIdempotentsResolveIdentity [1 .. 8])
      , testProperty "Morton-index ring Z/2^{3k} is local: idempotents = {0,1} (k=1..4, exhaustive)" $
          once (all lawMortonRingHasOnlyTrivialIdempotents [1 .. 4])
      ]

  , testGroup "Morton is a CHART: faithful at tree level, dead at ring level"
      [ testProperty "bijective + inverse-exact + truncation-compatible (k=1..3, exhaustive)" $
          once (all lawMortonIsChart [1 .. 3])
      , testProperty "teeth: Morton is not additive (carries cross axes)" $
          once lawMortonNotAdditive
      ]

  , testGroup "The t-collapse (V2.1 time-axis drop) is ALGEBRA in the product ..."
      [ testProperty "its kernel {(0,0,t)} is an ideal (depth 2, exhaustive mult-closure)" $
          once (lawTCollapseKernelIsIdealInProduct 2)
      , testProperty "coarsenT is a ring hom into the mixed-depth product (k=4)" $
          forAll genTriple $ \a -> forAll genTriple $ \b ->
            forAll (choose (0, 4)) $ \j ->
              lawTCoarseningIsRingHom 4 j a b
      ]

  , testGroup "... and NOT algebra through the chart"
      [ testProperty "transported kernel is not additively closed (witness 4+4=8)" $
          once lawTCollapseKernelNotAdditiveInChart
      , testProperty "transported kernel matches NO ideal of Z/2^{3k} (k=2..4; gene turns on at depth 2)" $
          once (all lawTCollapseIsNoIdealOfMortonRing [2 .. 4])
      , testProperty "teeth for the depth-1 boundary: at k=1 the kernel IS the ideal (4) of Z/8" $
          once (sortedKernel `elem` mortonRingIdeals 1)
      , testProperty "on the 8-adic side the t-collapse is only a bit-mask (k=1..3, exhaustive)" $
          once (all lawTMaskIsChartLevelOnly [1 .. 3])
      ]

  , testGroup "Three independent pyramids (the product filtration)"
      [ testProperty "per-axis truncations commute across axes and are transitive within (k=8)" $
          forAll genTriple (lawAxesCoarsenIndependently 8)
      ]
  ]

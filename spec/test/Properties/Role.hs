module Properties.Role (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.Role

-- A dimension-consistent portfolio: n genes, each a length-d vector (so translation/permutation of
-- the whole portfolio stays well-formed).
data Case = Case Int Portfolio deriving Show

instance Arbitrary Case where
  arbitrary = do
    d <- choose (1, 5)
    n <- choose (0, 8)
    p <- vectorOf n (vectorOf d (choose (-5, 5)))
    pure (Case d p)

approx :: Double -> Double -> Bool
approx a b = abs (a - b) <= 1e-6 * (1 + abs a + abs b)

tests :: TestTree
tests = testGroup "Role (the specialist↔generalist spectrum = effective genome dimension)"
  [ testProperty "the spectrum is at least 1" $
      \(Case _ p) -> lawEffectiveDimAtLeastOne p
  , testProperty "the spectrum is bounded by the gene count" $
      \(Case _ p) -> lawEffectiveDimBoundedByCount p
  , testProperty "invariant under reordering the portfolio" $
      \(Case _ p) -> forAll (shuffle p) $ \q ->
        approx (effectiveGenomeDim p) (effectiveGenomeDim q)
  , testProperty "invariant under translating the whole portfolio" $
      \(Case d p) -> forAll (vectorOf d (choose (-5, 5))) $ \s ->
        approx (effectiveGenomeDim p) (effectiveGenomeDim (map (zipWith (+) s) p))
  , testProperty "SYNTHETIC: colinear genes score exactly 1 (pure specialist)" $
      \(NonEmpty ts) -> forAll (vectorOf 4 (choose (-5, 5))) $ \v ->
        lawColinearIsSpecialist v ts
  , testProperty "SYNTHETIC: genes on k orthogonal axes score exactly k (generalist)" $
      once (all lawAxisPairsGiveDimK [1 .. 6])
  ]

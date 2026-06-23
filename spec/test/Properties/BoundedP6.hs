module Properties.BoundedP6 (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.Dim6 (Dim6(..))
import SixFour.Spec.RelationalResidual (P6(..))
import SixFour.Spec.SubstrateDomain (substrateBound)
import SixFour.Spec.BoundedP6

-- in-domain default
genP6 :: Gen P6
genP6 = P6 <$> g <*> g <*> g <*> g <*> g <*> g
  where g = choose (-32768, 32768)

-- AT the edge but still in-domain (for the move laws: start in-domain, a +1 can cross out)
genP6Edge :: Gen P6
genP6Edge = P6 <$> e <*> e <*> e <*> e <*> e <*> e
  where e = elements [b, b - 1, b - 2, -b, -b + 1, -1, 0, 1]
        b = substrateBound

-- OVER the edge (so the reject law is non-vacuous: some coord is out of domain)
genP6Over :: Gen P6
genP6Over = P6 <$> e <*> e <*> e <*> e <*> e <*> e
  where e = elements [b + 1, b + 2, -b - 1, -b - 2, b, 0]
        b = substrateBound

genAxis :: Gen Dim6
genAxis = elements [DimL, DimA, DimB, DimX, DimY, DimT]

genDelta :: Gen Int
genDelta = elements [-2, -1, 1, 2]

tests :: TestTree
tests = testGroup "BoundedP6 (type-enforced domain: out-of-domain is unrepresentable on the committing surface)"
  [ testProperty "mkBoundedP6 accepts an in-domain point (and round-trips it)" $
      forAll genP6 lawMkBoundedAcceptsInDomain
  , testProperty "mkBoundedP6 REJECTS an out-of-domain point (tested OVER the edge)" $
      forAll genP6Over lawMkBoundedRejectsOutOfDomain
  , testProperty "a BoundedP6 is in-domain on every coordinate (the carried invariant)" $
      forAll genP6 lawUnBoundedIsInDomain
  , testProperty "nudgeBounded never produces an out-of-domain carrier (at the edge)" $
      forAll genAxis $ \ax -> forAll genDelta $ \d -> forAll genP6Edge $ \p ->
        lawNudgeBoundedPreservesDomain ax d p
  , testProperty "nudgeBounded refuses exactly when the move crosses the edge" $
      forAll genAxis $ \ax -> forAll genDelta $ \d -> forAll genP6Edge $ \p ->
        lawNudgeBoundedRefusesAtEdge ax d p
  ]

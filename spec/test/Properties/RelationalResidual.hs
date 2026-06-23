module Properties.RelationalResidual (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.Dim6 (Dim6(..))
import SixFour.Spec.RelationalResidual
import SixFour.Spec.SubstrateDomain (substrateBound)

genI :: Gen Int
genI = choose (-32768, 32768)

genP6 :: Gen P6
genP6 = P6 <$> genI <*> genI <*> genI <*> genI <*> genI <*> genI

genAxis :: Gen Dim6
genAxis = elements [DimL, DimA, DimB, DimX, DimY, DimT]

-- a coordinate AT or NEAR the substrate-domain edge (+-B), so the domain law is not vacuous
genEdge :: Gen Int
genEdge = elements
  [ b, b - 1, b - 2, -b, -b + 1, -b + 2, -1, 0, 1 ]
  where b = substrateBound

genP6Edge :: Gen P6
genP6Edge = P6 <$> genEdge <*> genEdge <*> genEdge <*> genEdge <*> genEdge <*> genEdge

-- a small move delta (the +-1/+-2 quantum, which can step across the edge)
genDelta :: Gen Int
genDelta = elements [-2, -1, 1, 2]

tests :: TestTree
tests = testGroup "RelationalResidual (the Zig-floor 6D-point substrate + the safeNudge domain guard)"
  [ testProperty "DOMAIN: safeNudge refuses exactly when the kernel would (tested AT the edge)" $
      forAll genAxis $ \ax -> forAll genDelta $ \d -> forAll genP6Edge $ \p ->
        lawNudgeRespectsDomain ax d p
  ]

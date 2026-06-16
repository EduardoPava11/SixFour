module Properties.RGBTLift (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.PairTreeFixed (OKLabI)
import SixFour.Spec.RGBTLift

-- Q16-range integers, including negatives (the regime the device uses).
genInt :: Gen Int
genInt = choose (-65536, 65536)

genQuad :: Gen Quad
genQuad = (,,,) <$> genInt <*> genInt <*> genInt <*> genInt

genOKLabI :: Gen OKLabI
genOKLabI = (,,) <$> genInt <*> genInt <*> genInt

genOKQuad :: Gen (OKLabI, OKLabI, OKLabI, OKLabI)
genOKQuad = (,,,) <$> genOKLabI <*> genOKLabI <*> genOKLabI <*> genOKLabI

tests :: TestTree
tests = testGroup "RGBTLift (2x2 <-> RGBT reversible integer lifting)"
  [ testProperty "unliftQuad . liftQuad = id (EXACT, the (2x2)<->1 bijection)" $
      forAll genQuad lawLiftUnliftExact

  , testProperty "liftQuad . unliftQuad = id (EXACT, genuine bijection)" $
      forAll genQuad lawUnliftLiftExact

  , testProperty "coarse R stays within the block range (gamut-closed distill)" $
      forAll genQuad lawCoarseInBlockRange

  , testProperty "constant block => zero detail: liftQuad (v,v,v,v) = (v,0,0,0)" $
      forAll genInt lawDetailZeroOnConstant

  , testProperty "OKLab spatial edge round-trips exactly (per-channel)" $
      forAll genOKQuad lawLiftUnliftExactOK

  , -- golden pin: a fixed block's sub-bands (cross-language reproducible)
    testProperty "golden: liftQuad (10,20,30,44) = (26,-22,-12,4)" $
      once (liftQuad (10, 20, 30, 44) == (26, -22, -12, 4))
  ]

{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE TypeApplications #-}

-- | Laws for 'SixFour.Spec.AxisNet': the grey-anchor / dynamic-range algebra.
-- L is the σ-fixed grey centre that sets the dynamic range; A,B are σ-antisymmetric
-- chroma deviations from grey.
module Properties.AxisNet (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.Color    (OKLab(..))
import SixFour.Spec.PairTree (sigmaReflect)
import SixFour.Spec.Pipeline (Stage(..))
import SixFour.Spec.AxisNet

genOKLab :: Gen OKLab
genOKLab = OKLab <$> choose (0, 1) <*> choose (-0.4, 0.4) <*> choose (-0.4, 0.4)

genPal :: Gen [OKLab]
genPal = resize 32 (listOf1 genOKLab)

eqLab :: OKLab -> OKLab -> Bool
eqLab (OKLab l1 a1 b1) (OKLab l2 a2 b2) = l1 == l2 && a1 == a2 && b1 == b2

eqPal :: [OKLab] -> [OKLab] -> Bool
eqPal xs ys = length xs == length ys && and (zipWith eqLab xs ys)

tests :: TestTree
tests = testGroup "AxisNet (grey-anchor / dynamic-range algebra)"
  [ testProperty "greyPoint is σ-fixed" $
      eqLab (sigmaReflect greyPoint) greyPoint

  , testProperty "grey axis (a=b=0) is the σ-fixed centre ∀ L" $
      forAll (choose (0, 1)) $ \l -> eqLab (sigmaReflect (OKLab l 0 0)) (OKLab l 0 0)

  , testProperty "achromatic decomposition round-trips: fromDeviation ∘ toDeviation ≡ id" $
      forAll genOKLab $ \x -> eqLab (fromDeviation (toDeviation x)) x

  , testProperty "σ negates chroma, fixes grey: toDeviation ∘ σ ≡ sigmaDeviation ∘ toDeviation" $
      forAll genOKLab $ \x -> toDeviation (sigmaReflect x) == sigmaDeviation (toDeviation x)

  , testProperty "AxisL projection is σ-fixed (grayscale = the σ-symmetric image)" $
      forAll genOKLab $ \x -> let p = projectAxis AxisL x in eqLab (sigmaReflect p) p

  , testProperty "AxisA/AxisB projections are σ-equivariant: σ ∘ proj ≡ proj ∘ σ" $
      forAll genOKLab $ \x ->
           eqLab (sigmaReflect (projectAxis AxisA x)) (projectAxis AxisA (sigmaReflect x))
        && eqLab (sigmaReflect (projectAxis AxisB x)) (projectAxis AxisB (sigmaReflect x))

  , testProperty "axisSigmaSign: +1 for L (σ-fixed), -1 for A,B (σ-negated)" $
      axisSigmaSign AxisL == 1 && axisSigmaSign AxisA == (-1) && axisSigmaSign AxisB == (-1)

  , testProperty "axisIsAchromatic: only L is the grey backbone" $
      axisIsAchromatic AxisL && not (axisIsAchromatic AxisA) && not (axisIsAchromatic AxisB)

  , testProperty "injectAxis L places lightness on grey; chroma axes sit at grey lightness" $
      forAll (choose (0, 1)) $ \v ->
        case (injectAxis AxisL v, injectAxis AxisA v) of
          (OKLab l a b, OKLab l2 a2 b2) ->
            l == v && a == 0 && b == 0 && l2 == greyLightness && a2 == v && b2 == 0

  , testProperty "dynamic range contains its own grey midpoint" $
      forAll genPal $ \ps -> let dr = dynamicRangeOf ps in inDynamicRange dr (greyOf dr)

  , testProperty "dynamic range is monotone: adding a colour can only widen [Lmin,Lmax]" $
      forAll genPal $ \ps -> forAll genOKLab $ \x ->
        let DynamicRange lo  hi  = dynamicRangeOf ps
            DynamicRange lo' hi' = dynamicRangeOf (x : ps)
        in lo' <= lo && hi' >= hi

  , testProperty "AxisNet 'AxisL Stage: output is all-grey (chroma 0) AND σ-fixed" $
      forAll genPal $ \ps ->
        let out = step @(AxisNet 'AxisL) ps
        in all (\(OKLab _ a b) -> a == 0 && b == 0) out && eqPal (map sigmaReflect out) out
  ]

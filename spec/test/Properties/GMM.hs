module Properties.GMM (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Test.QuickCheck
import Data.List (permutations)

import SixFour.Spec.Color     (OKLab(..))
import SixFour.Spec.Diversity (Cov3, weightedCovariance)
import SixFour.Spec.GMM

genOKLab :: Gen OKLab
genOKLab = OKLab <$> choose (0, 1) <*> choose (-0.4, 0.4) <*> choose (-0.4, 0.4)

-- A small PSD covariance (Σ = k·L Lᵀ, diagonal of L bounded away from 0).
genCov :: Gen Cov3
genCov = do
  l00 <- choose (0.1, 1.0); l10 <- choose (-0.5, 0.5); l11 <- choose (0.1, 1.0)
  l20 <- choose (-0.5, 0.5); l21 <- choose (-0.5, 0.5); l22 <- choose (0.1, 1.0)
  let k   = 0.05
      sll = l00*l00
      sla = l00*l10
      slb = l00*l20
      saa = l10*l10 + l11*l11
      sab = l10*l20 + l11*l21
      sbb = l20*l20 + l21*l21 + l22*l22
  pure (k*sll, k*sla, k*slb, k*saa, k*sab, k*sbb)

genGaussian :: Gen Gaussian
genGaussian = Gaussian <$> genOKLab <*> genCov <*> choose (0.1, 5)

genGMM :: Gen GMM
genGMM = choose (1, 8) >>= \n -> vectorOf n genGaussian

cov3Near :: Cov3 -> Cov3 -> Double -> Bool
cov3Near (a,b,c,d,e,f) (a',b',c',d',e',f') tol =
  all (< tol) [abs (a-a'), abs (b-b'), abs (c-c'), abs (d-d'), abs (e-e'), abs (f-f')]

okNear :: OKLab -> OKLab -> Double -> Bool
okNear (OKLab l a b) (OKLab l' a' b') tol =
  abs (l-l') < tol && abs (a-a') < tol && abs (b-b') < tol

tests :: TestTree
tests = testGroup "GMM (continuous Gaussian-mixture substrate)"
  [ testProperty "token width is 10 (μ3 + Σ6 + w1), replacing the 88 category code" $
      once $
        gmmTokenDim == 10
        && all ((== 10) . length . gaussianToken)
               [ Gaussian (OKLab 0.5 0.1 (-0.1)) (1,2,3,4,5,6) 0.7 ]

  , testProperty "poolGMM renormalises weights to sum 1" $
      forAll (choose (1, 5) >>= \n -> vectorOf n genGMM) $ \gms ->
        let pooled = poolGMM gms
        in null pooled || abs (totalWeight pooled - 1) < 1e-9

  , testProperty "poolGMM preserves component count (multiset union)" $
      forAll (choose (1, 5) >>= \n -> vectorOf n genGMM) $ \gms ->
        length (poolGMM gms) == sum (map length gms)

  , testProperty "mixtureMean is permutation-invariant" $
      forAll genGMM $ \gm ->
        let perms = take 6 (permutations gm)
            m0    = mixtureMean gm
        in all (\p -> okNear (mixtureMean p) m0 1e-9) perms

  , testProperty "mixtureCovariance is permutation-invariant" $
      forAll genGMM $ \gm ->
        let perms = take 6 (permutations gm)
            c0    = mixtureCovariance gm
        in all (\p -> cov3Near (mixtureCovariance p) c0 1e-9) perms

  , testProperty "single component: mixture moments are that component's" $
      forAll genGaussian $ \g ->
        let gm = [g { gWeight = 1 }]
        in okNear (mixtureMean gm) (gMean g) 1e-12
           && cov3Near (mixtureCovariance gm) (gCov g) 1e-12

  , -- The bridge to the existing variety measure: the BETWEEN-component term of the
    -- law of total covariance (point masses ⇒ Σᵢ = 0) equals Diversity.weightedCovariance.
    testProperty "law of total covariance: point-mass mixture == weightedCovariance" $
      forAll (choose (2, 16) >>= \n ->
                vectorOf n ((,) <$> genOKLab <*> choose (0.1, 5))) $ \cands ->
        cov3Near (mixtureCovariance (pointMassGMM cands))
                 (weightedCovariance cands)
                 1e-9
  ]

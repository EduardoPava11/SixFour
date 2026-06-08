module Properties.Bures (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Test.QuickCheck

import SixFour.Spec.Color     (OKLab(..), okLabDistanceSquared)
import SixFour.Spec.Diversity (Cov3)
import SixFour.Spec.GMM       (Gaussian(..), pointMass)
import SixFour.Spec.Bures

genOKLab :: Gen OKLab
genOKLab = OKLab <$> choose (0, 1) <*> choose (-0.4, 0.4) <*> choose (-0.4, 0.4)

-- Strictly-PD covariance (diagonal of L ≥ 0.1 ⇒ no near-singular Σ for the iterations).
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

matNear :: Mat3 -> Mat3 -> Double -> Bool
matNear (Mat3 a b c d e f g h i) (Mat3 a' b' c' d' e' f' g' h' i') tol =
  all (< tol) (zipWith (\x y -> abs (x - y)) [a,b,c,d,e,f,g,h,i] [a',b',c',d',e',f',g',h',i'])

cov3Near :: Cov3 -> Cov3 -> Double -> Bool
cov3Near (a,b,c,d,e,f) (a',b',c',d',e',f') tol =
  all (< tol) [abs (a-a'), abs (b-b'), abs (c-c'), abs (d-d'), abs (e-e'), abs (f-f')]

tests :: TestTree
tests = testGroup "Bures (Gaussian Wasserstein-2 collapse backbone)"
  [ testProperty "sqrtPSD squares back to the original (Σ^½ · Σ^½ ≈ Σ)" $
      forAll genCov $ \c ->
        let m = fromCov3 c
            r = sqrtPSD m
        in matNear (matMul r r) m 1e-4

  , testProperty "sqrtPSD of identity is identity" $
      once $ matNear (sqrtPSD matId) matId 1e-4

  , testProperty "inverse3 · M ≈ I" $
      forAll genCov $ \c ->
        let m = fromCov3 c
        in matNear (matMul (inverse3 m) m) matId 1e-6

  , testProperty "Bures self-distance is zero" $
      forAll genGaussian $ \g ->
        abs (buresDistanceSq g g) < 1e-4

  , testProperty "Bures distance is symmetric" $
      forAll genGaussian $ \g1 ->
        forAll genGaussian $ \g2 ->
          abs (buresDistanceSq g1 g2 - buresDistanceSq g2 g1) < 1e-4

  , -- THE bridge law: as Σ → 0 the Bures distance collapses to plain Euclidean OKLab,
    -- so the Gaussian collapse degenerates to the k-means free-support floor.
    testProperty "Σ→0 reduction: point-mass Bures == okLabDistanceSquared" $
      forAll genOKLab $ \c1 ->
        forAll genOKLab $ \c2 ->
          abs (buresDistanceSq (pointMass c1 1) (pointMass c2 1)
               - okLabDistanceSquared c1 c2) < 1e-4

  ,-- The barycenter is symmetric in its (equally-weighted) arguments — the
    -- 2-measure iteration converges to the same covariance regardless of order.
    testProperty "barycenter covariance is order-independent (equal weights)" $
      forAll genCov $ \c1 ->
        forAll genCov $ \c2 ->
          cov3Near (buresBarycenterCov [(0.5, c1), (0.5, c2)])
                   (buresBarycenterCov [(0.5, c2), (0.5, c1)])
                   1e-4
  ]

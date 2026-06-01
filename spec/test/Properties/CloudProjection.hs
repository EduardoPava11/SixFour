module Properties.CloudProjection (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Test.QuickCheck

import SixFour.Spec.Color          (OKLab(..))
import SixFour.Spec.Quad4          (Quad4Palette(..))
import SixFour.Spec.CloudProjection

genOKLab :: Gen OKLab
genOKLab = OKLab <$> choose (0, 1) <*> choose (-0.4, 0.4) <*> choose (-0.4, 0.4)

genVec3 :: Gen Vec3
genVec3 = Vec3 <$> choose (-2, 2) <*> choose (-2, 2) <*> choose (-2, 2)

genQuad4 :: Gen Quad4Palette
genQuad4 = do
  rt   <- genOKLab
  lvls <- mapM (\l -> vectorOf (4 ^ l) ((,) <$> genSmall <*> genSmall)) [0 .. 3]
  pure (Quad4Palette rt lvls)
  where genSmall = OKLab <$> choose (-0.1, 0.1) <*> choose (-0.1, 0.1) <*> choose (-0.1, 0.1)

tests :: TestTree
tests = testGroup "CloudProjection (P4 OKLab Temporal Cloud — distance honesty)"
  [ testProperty "world map is a similarity: worldDist = scale · oklabDist" $
      forAll genOKLab $ \c1 -> forAll genOKLab (lawWorldIsometry 1e-9 c1)

  , testProperty "orbit (yaw,pitch) preserves 3-D distance (rotation isometry)" $
      forAll (choose (-pi, pi)) $ \yaw ->
        forAll (choose (-1.5, 1.5)) $ \pitch ->
          forAll genVec3 $ \p -> forAll genVec3 (lawRotationIsometry 1e-9 yaw pitch p)

  , testProperty "orthographic is EXACT for same-depth pairs (in-plane)" $
      forAll (choose (-2, 2)) $ \x0 -> forAll (choose (-2, 2)) $ \y0 ->
        forAll (choose (-2, 2)) $ \x1 -> forAll (choose (-2, 2)) $ \y1 ->
          forAll (choose (-2, 2)) (lawOrthographicInPlaneExact 1e-9 x0 y0 x1 y1)

  , testProperty "orthographic never expands distance (1-Lipschitz)" $
      forAll genVec3 $ \p -> forAll genVec3 (lawOrthographicContracts 1e-9 p)

  , testProperty "perspective distorts: equal segments differ on-screen by > 0.5" $
      once $ property (lawPerspectiveDistorts 0.5)

  , testProperty "AABB hull contains every input point" $
      forAll (listOf genOKLab) lawHullContainsAll

  , testProperty "AABB hull is deterministic (order-independent)" $
      forAll (listOf genOKLab) lawHullDeterministic

  , testProperty "population→radius is monotone non-decreasing" $
      forAll (choose (1, 4096)) $ \maxC ->
        forAll (choose (0, 4096)) $ \c1 -> forAll (choose (0, 4096)) (lawRadiusMonotone maxC c1)

  , testProperty "population→radius stays in [radiusMin, radiusMax]" $
      forAll (choose (1, 4096)) $ \maxC -> forAll (choose (0, 8192)) (lawRadiusBounded maxC)

  , testProperty "temporalLerp endpoints exact (t=0→p, t=1→q)" $
      forAll genVec3 $ \p -> forAll genVec3 (lawLerpEndpoints 1e-12 p)

  , testProperty "temporalLerp lies on the segment p→q" $
      forAll (choose (0, 1)) $ \t -> forAll genVec3 $ \p -> forAll genVec3 (lawLerpOnSegment 1e-9 t p)

  , testProperty "Quad4 ghost error is zero on the Quad4 subspace (lossy proj exact there)" $
      forAll genQuad4 (lawGhostZeroOnSubspace 1e-9)

    -- Pinned goldens (fix the exact constants the Swift port mirrors).
  , testProperty "golden: canonical centre = (0.5,0,0), scale = 2" $
      once $ (canonicalCentre === OKLab 0.5 0 0) .&&. (canonicalScale === 2.0)

  , testProperty "golden: oklabToWorld neutral mid-grey → origin" $
      once $ oklabToWorld (OKLab 0.5 0 0) === Vec3 0 0 0

  , testProperty "golden: axis map a→x, L→y, b→z at (0.6, 0.1, -0.2)" $
      once $ let Vec3 x y z = oklabToWorld (OKLab 0.6 0.1 (-0.2))
             -- a→x = (0.1-0)·2, L→y = (0.6-0.5)·2, b→z = (-0.2-0)·2.
             in property (abs (x - 0.2) < 1e-9 && abs (y - 0.2) < 1e-9 && abs (z - (-0.4)) < 1e-9)

  , testProperty "golden: axis-pair snap angles (AB top-down, LA front, LB side)" $
      once $ (axisPairOrbit PlaneLA === (0, 0))
        .&&. (axisPairOrbit PlaneLB === (pi / 2, 0))
        .&&. (axisPairOrbit PlaneAB === (0, -pi / 2))

  , testProperty "golden: radius bounds 0.6 / 3.0 and √-law midpoint" $
      once $ (radiusMin === 0.6) .&&. (radiusMax === 3.0)
        .&&. (populationRadius 4 0 === 0.6) .&&. (populationRadius 4 4 === 3.0)
  ]

module Properties.SteeringSpine (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.LatentNavigation (Gesture(..))
import SixFour.Spec.OctreeCell (Detail)
import SixFour.Spec.SteeringSpine

genI :: Gen Int
genI = choose (-256, 256)

genD :: Gen Double
genD = choose (-100, 100)

genGesture :: Gen Gesture
genGesture = Gesture <$> choose (-8, 8)
                     <*> ((,) <$> choose (-64, 64) <*> choose (-64, 64))

genDetail :: Gen Detail
genDetail = (,,,,,,) <$> genI <*> genI <*> genI <*> genI <*> genI <*> genI <*> genI

genBands :: Gen [[Detail]]
genBands = do
  nb <- choose (0, 2)
  vectorOf nb (do n <- choose (0, 4); vectorOf n genDetail)

genCut :: Gen (Int, Int, [Int])
genCut = do
  d  <- elements [0, 1, 2]
  k  <- choose (0, d)
  xs <- vectorOf (8 ^ d) genI
  pure (k, d, xs)

genCoarserCase :: Gen (Int, [Double])
genCoarserCase = do
  d  <- elements [1, 2]
  xs <- vectorOf (8 ^ d) genD
  pure (d, xs)

tests :: TestTree
tests = testGroup "SteeringSpine (capstone: latent -> nudge -> project 16^3 -> reconstruct 256^3)"
  [ testProperty "the shown rung is STRICTLY COARSER than the latent (P reduces dimension)" $
      forAll genCoarserCase $ \(d, xs) -> forAll genGesture $ \g ->
        lawSpineShownIsCoarser d g xs

  , testProperty "design-pin: the spine uses the canonical structural P (LatentProjection.project)" $
      forAll genGesture $ \g -> forAll (listOf genD) $ \xs ->
        lawSpineUsesStructuralP 1 g xs

  , testProperty "256^3 reconstruction uses the same octant operator both rungs (delegated)" $
      forAll (vectorOf 8 genI) $ \coarse -> forAll genBands $ \det ->
        lawSpineReconstructSelfSimilar coarse det

  , testProperty "16->64 is bit-exact within capture (delegated)" $
      forAll genCut (\(k, d, xs) -> lawSpineWithinCaptureExact k d xs)
  ]

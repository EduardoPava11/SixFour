module Properties.SameObjectInvariance (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.ProjectionOrdering (allOrderings)
import SixFour.Spec.SameObjectInvariance

genI :: Gen Int
genI = choose (-256, 256)

-- a well-formed cube at depth d (8^d voxels per channel)
genCube :: Gen (Int, Cube)
genCube = do
  d <- elements [0, 1]
  let n = 8 ^ d
  c <- Cube <$> vectorOf n genI <*> vectorOf n genI <*> vectorOf n genI
  pure (d, c)

tests :: TestTree
tests = testGroup "SameObjectInvariance (same 64^3 object, orthogonal XOR projections)"
  [ testProperty "every ordering round-trips: decode . encode = id" $
      forAll genCube $ \(d, c) -> forAll (elements allOrderings) $ \o ->
        lawEncodeDecodeRoundTrip d o c

  , testProperty "KEYSTONE: both orderings reconstruct the SAME object" $
      forAll genCube $ \(d, c) ->
        forAll (elements allOrderings) $ \p ->
          forAll (elements allOrderings) $ \p' -> lawReorderingPreservesObject d p p' c

  , testProperty "same object, orthogonal projection: genomes differ, object same" $
      forAll genCube $ \(d, c) -> lawDifferentEncodingsSameObject d c

  , testProperty "equivariance: swap the ordering == swap the input channels" $
      forAll genCube $ \(d, c) -> forAll (elements allOrderings) $ \o ->
        lawEquivariance d o c
  ]

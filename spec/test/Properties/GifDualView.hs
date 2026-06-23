module Properties.GifDualView (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.SameObjectInvariance (Cube(..))
import SixFour.Spec.GifDualView

-- | A well-formed GIF object at a small octant depth. Small colour range so distinct
-- colours recur (exercising the palettization's nub).
genGifObject :: Gen GifObject
genGifObject = do
  d <- choose (0, 2)
  let n = 8 ^ d
  cl <- vectorOf n (choose (-8, 8))
  ca <- vectorOf n (choose (-8, 8))
  cb <- vectorOf n (choose (-8, 8))
  pure (GifObject d (Cube cl ca cb))

tests :: TestTree
tests = testGroup "GifDualView (KEYSTONE: two encoders, one GIF object)"
  [ testProperty "both views decode to the SAME pixels (the commutative square)" $
      forAll genGifObject lawSameObjectBothViews
  , testProperty "Encoder B is a lossless section (decodeB . viewB == id), with teeth" $
      forAll genGifObject lawSectionEmbedsLossless
  , testProperty "construction view round-trips (palettizeExact is a section of buildPixels)" $
      forAll genGifObject lawRetractionRoundTrip
  ]

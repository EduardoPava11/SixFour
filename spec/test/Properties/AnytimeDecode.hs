module Properties.AnytimeDecode (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.RefinementSystem (unliftVec)
import SixFour.Spec.AnytimeDecode

genPair :: Gen (Integer, [Integer])
genPair = do
  c  <- choose (-100, 100)
  ds <- map fromIntegral <$> listOf (choose (-50, 50 :: Int))
  pure (fromIntegral (c :: Int), ds)

tests :: TestTree
tests = testGroup "AnytimeDecode (partial decode never fails: scheme-1 prefix + floor totality)"
  [ testProperty "golden: unliftVec (100,[5,-3,7]) == [100,105,102,109], k=2 prefix matches" $
      once ( unliftVec (100,[5,-3,7]) == [100,105,102,109]
           && takeBands 3 (100,[5,-3,7]) == unliftVec (dropDetailBeyond 2 (100,[5,-3,7])) )

  , testProperty "KEYSTONE: reading k+1 bands == full decode truncated to depth k (random)" $
      forAll genPair $ \p -> forAll (choose (0, 12)) (lawDecodeIsAnytime p)

  , testProperty "NON-VACUITY: the correct decoder is anytime; the tail-dependent badRenorm is NOT" $
      once ( and [ anytimeUnder unliftVec (100,[5,-3,7]) k | k <- [0..3] ]
           && not (anytimeUnder badRenorm (100,[5,-3,7]) 2) )

  , testProperty "floor is ALWAYS decodable (zero-detail expand total, length 8*s^3)" $
      forAll (choose (1,4)) $ \s -> forAll (vectorOf (s*s*s) (choose (0, 65535)))
        (lawFloorAlwaysDecodable s)

  , testProperty "floor stays non-negative on a non-negative coarse cube" $
      forAll (choose (1,4)) $ \s -> forAll (vectorOf (s*s*s) (choose (-40000, 40000)))
        (lawFloorNonNegOnNonNeg s)
  ]

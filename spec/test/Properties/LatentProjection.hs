module Properties.LatentProjection (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.LatentProjection
import SixFour.Spec.OctreeGenome (octreeLeafCount)

-- | Mac-side floats for the latent cube.
genD :: Gen Double
genD = choose (-1000, 1000)

genFloats :: Gen [Double]
genFloats = do
  n <- choose (0, 64)
  vectorOf n genD

-- | A valid (cut, depth, 8^d-sized float cube) for the pooling-delegation law.
genCutDepthCube :: Gen (Int, Int, [Double])
genCutDepthCube = do
  d   <- choose (0, 2)
  cut <- choose (0, d)
  xs  <- vectorOf (octreeLeafCount d) genD
  pure (cut, d, xs)

tests :: TestTree
tests = testGroup "LatentProjection (P = pool then reenterQ16: lossy, many-to-one, undo=replay)"
  [ testProperty "P is MANY-TO-ONE: distinct latents project to the same [Q16] (witness)" $
      once lawProjectionManyToOne

  , testProperty "P factors THROUGH the single reenterQ16 crossing (no raw round)" $
      forAll (choose (0, 2)) $ \cut ->
        forAll genFloats $ \xs ->
          lawProjectionThroughReentry cut xs

  , testProperty "P's lossy half IS pooling (delegates SuccessiveRefinement.lawMarkovByPooling)" $
      forAll genCutDepthCube $ \(cut, d, xs) ->
        lawProjectionIsPooling cut d xs

  , testProperty "non-injective P => undo must be history-replay, not rung-inversion (witness)" $
      once lawUndoNeedsReplayBecauseNonInjective
  ]

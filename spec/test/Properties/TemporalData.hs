module Properties.TemporalData (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.ConstructionEncoder (Construction(..))
import SixFour.Spec.TemporalData

-- A same-shape, VALID frame pair (one clip's two frames): shared depth, palette size and index
-- length, every index a real palette slot. This is the regime the round-trip is stated over.
genFramePair :: Gen (Construction, Construction)
genFramePair = do
  d <- choose (0, 2)                       -- 8^d voxels: 1, 8, or 64
  k <- choose (1, 4)                        -- palette size
  let n      = 8 ^ d
      qcol   = (,,) <$> choose (-3000, 3000) <*> choose (-3000, 3000) <*> choose (-3000, 3000)
      palG   = vectorOf k qcol
      idxG   = vectorOf n (choose (0, k - 1))
  ct     <- Construction d <$> palG <*> idxG
  ctNext <- Construction d <$> palG <*> idxG
  pure (ct, ctNext)

tests :: TestTree
tests = testGroup "TemporalData (the time-axis data engine: (t, t+1) pairs + invertibility round-trip)"
  [ testProperty "KEYSTONE: reconstructNext (manufacture ct ctNext) == ctNext (lossy generator fails)" $
      forAll genFramePair $ \(ct, ctNext) -> lawTemporalEngineRoundTrips ct ctNext
  , testProperty "channels disjoint: VALUE touches only palette, POLICY only index (heads train independently)" $
      forAll genFramePair $ \(ct, ctNext) -> lawTemporalChannelsDisjoint ct ctNext
  , testProperty "multi-scale bridge: octant-banded luminance delta reconstructs the raw L data delta" $
      forAll genFramePair $ \(ct, ctNext) -> lawTemporalBandingReconstructs ct ctNext
  ]

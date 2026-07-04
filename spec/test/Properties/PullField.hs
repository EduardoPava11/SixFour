module Properties.PullField (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.PullField

genVolume :: Gen [Integer]
genVolume = vectorOf (8 * 8 * 8) (choose (0, 255))

tests :: TestTree
tests = testGroup "PullField (influence is the game: three rungs in one GIF89a)"
  [ testGroup "The render-side paint laws"
      [ testProperty "full influence everywhere == the 64-rung identity" $
          forAll genVolume lawFullInfluenceIsIdentity
      , testProperty "zero influence everywhere == the coarse pull (independent replicate check)" $
          forAll genVolume lawZeroInfluenceIsCoarsePull
      , testProperty "one region's influence moves only that region's pixels" $
          forAll (choose (0, 7)) $ \r -> forAll genVolume (lawInfluenceIsLocal r)
      ]

  , testGroup "Bytes follow influence (what GIF89a charges)"
      [ testProperty "spatial: a pulled region has zero interior index transitions (LZW-free)" $
          forAll genVolume lawInteriorRunsAreFree
      , testProperty "temporal: a pulled region is identical across its 4-frame window (changed-rect omits it)" $
          forAll genVolume lawTemporalPullSkipsFrames
      ]
  ]

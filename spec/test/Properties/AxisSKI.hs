module Properties.AxisSKI (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.AxisSKI

genVolume :: Gen [Integer]
genVolume = vectorOf (8 * 8 * 8) (choose (0, 255))

genBlock :: Gen [Integer]
genBlock = vectorOf 8 (choose (-4000, 4000))

tests :: TestTree
tests = testGroup "AxisSKI (SKI reconsidered dimensionally: axis-indexed K and S over x:y:t)"
  [ testGroup "The axes are independent operators"
      [ testProperty "axis washes commute pairwise and are idempotent (projections)" $
          withMaxSuccess 40 $ forAll genVolume lawAxisWashesCommuteAndProject
      , testProperty "the isotropic pull factors as the three axis washes, every order" $
          withMaxSuccess 30 $ forAll genVolume lawIsotropicPullFactors
      ]

  , testGroup "The axis family strictly extends the diagonal"
      [ testProperty "crisp-but-still (t-washed only) matches NO isotropic depth (witness)" $
          once lawAnisotropicStrictlyExtends
      ]

  , testGroup "The gene decomposes by axis"
      [ testProperty "the doubled wash along a kills exactly the a-bands, all three axes" $
          forAll genBlock lawAxisWashKillsItsBands
      , testProperty "w_t is arrow-blind; the t-band it discards is reversal-odd" $
          withMaxSuccess 40 $ forAll genVolume lawZeroSectionIsArrowBlind
      ]
  ]

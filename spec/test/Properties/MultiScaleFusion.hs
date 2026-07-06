module Properties.MultiScaleFusion (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.MultiScaleFusion

tests :: TestTree
tests = testGroup "MultiScaleFusion (the loop closed: capture diversity IS trainability)"
  [ testGroup "Recoverability equals diversity"
      [ testProperty "a stop is recoverable IFF covered (and to its true value)" $
          \w dr evs xs q -> lawRecoverableIffCovered w dr evs xs q
      , testProperty "the recoverable-stop count == coverage (recoverability IS diversity)" $
          \w dr evs xs -> lawRecoverableCountIsDiversity w dr evs xs
      , testProperty "redundant reads agree (measurement consistency / denoising signal)" $
          \w dr evs xs -> lawOverlapObservationsAgree w dr evs xs
      ]

  , testGroup "Full recovery vs collapse"
      [ testProperty "tiling recovers the whole scene when it fits the window budget" $
          \w dr xs -> lawTilingRecoversFullScene w dr xs
      , testProperty "convergent exposures are non-identifiable (a lost, uncovered stop)" $
          once lawConvergenceLosesScene
      , testProperty "KEYSTONE: the only freedom is off-cover; covered stops are pinned to truth" $
          \w dr evs xs ds -> lawFusionFreedomIsExactlyUncovered w dr evs xs ds
      ]
  ]

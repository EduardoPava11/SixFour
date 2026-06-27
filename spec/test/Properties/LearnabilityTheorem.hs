module Properties.LearnabilityTheorem (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.LearnabilityTheorem

tests :: TestTree
tests = testGroup "LearnabilityTheorem (the model WILL learn, conditional on w_value > 0)"
  [ testProperty "SIGNAL: non-floor detail energy exists in the two lenses (flat = boundary)"
      lawLearnableSignalExists
  , testProperty "EXPRESSIVITY: the target is an A_7 residual that survives the Q16 commit"
      lawTargetExpressibleAboveFloor
  , testProperty "IDENTIFIABILITY (rank-3): cellLoss is a sufficient statistic for the 9 aggregate entries"
      lawCellLossIdentifiesRank3Subspace
  , testProperty "IDENTIFIABILITY (complement): cellLoss is blind to checkerboard parity; the value head sees it (needs w_value>0)"
      lawValueHeadIdentifiesComplement
  , testProperty "DESCENT: monotone descent recovers the golden band 3000 byte-exact"
      lawDescentReachesGoldenByteExact
  , testProperty "NO-COLLAPSE: the VICReg std hinge keeps both cross-moment factors above the variance floor"
      lawNoCollapseKeepsCrossMomentFullRank
  , testProperty "CAPSTONE: the model WILL learn at w_value>0 and FAILS to identify the complement at w_value=0"
      lawModelWillLearn
  , testProperty "the joint objective identifies the complement IFF w_value > 0 (quantified)" $
      \w -> complementIdentifiedAt (abs w + 1) && not (complementIdentifiedAt 0)
  ]

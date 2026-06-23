module Properties.ScaleIndexedCorrespondence (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.ScaleIndexedCorrespondence

tests :: TestTree
tests = testGroup "ScaleIndexedCorrespondence (the H-JEPA hierarchy of the two encoders)"
  [ testProperty "Analysis 16³: the two encoders are EXACT (16²=256 identity)" $
      once lawAnalysisIsExact
  , testProperty "Pivot 64³: the correspondence is LOSSY (frame pixels > palette slots)" $
      once lawPivotIsLossy
  , testProperty "Synthesis 256³: the detail is INVENTED (beyond capture)" $
      once lawSynthesisIsInvented
  , testProperty "KEYSTONE: the correspondence hierarchy matches the scale spine" $
      once lawCorrespondenceHierarchyMatchesScaleSpine
  , testProperty "the latent midpoint is a separate kind, never surfaced, spine enum intact" $
      once lawMidpointCorrespondenceNeverSurfaces
  ]

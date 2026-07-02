module Properties.GeneTaxonomy (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.GeneTaxonomy

tests :: TestTree
tests = testGroup "GeneTaxonomy (the V3.0 gene registry — lifecycle classes + the Shader-ML fold-in boundary)"
  [ testProperty "sizes are DERIVED, not asserted (θ_up=21 from DetailPredictor, θ_B=63 from MaskedBandPrediction)" $
      once lawSizesAreDerivedNotAsserted
  , testProperty "class determines site (Somatic⇒per-capture, Identity⇒per-user, Germline/Meme⇒never per-capture)" $
      once lawClassDeterminesSite
  , testProperty "germline never trains on a phone (the base is immutable per release)" $
      once lawGermlineNeverTrainsOnDevice
  , testProperty "every registered gene claims zero-gene == floor" $
      once lawEveryGeneClaimsAFloor
  , testProperty "the cascade fold boundary is REAL on both sides (θ_up/θ_cell fold; time-rung/value-pref do not)" $
      once lawFoldBoundaryIsRealOnBothSides
  , testProperty "registry names are unique (the gene store indexes by name)" $
      once lawRegistryNamesUnique
  ]

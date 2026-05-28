module Main (main) where

import Test.Tasty

import qualified Properties.Color        as Color
import qualified Properties.Gauge        as Gauge
import qualified Properties.Surjectivity as Surj
import qualified Properties.Wu           as Wu
import qualified Properties.Coverage     as Coverage
import qualified Properties.Collapse     as Collapse
import qualified Properties.Diversity    as Diversity
import qualified Properties.GMM          as GMM
import qualified Properties.Bures        as Bures
import qualified Properties.PairTree     as PairTree
import qualified Properties.Dither       as Dither
import qualified Properties.LookNet      as LookNet
import qualified Properties.LookCore     as LookCore
import qualified Properties.Layer        as Layer
import qualified Properties.Scale        as Scale
import qualified Properties.Preference   as Preference
import qualified Properties.Bottleneck16 as Bottleneck16
import qualified Properties.SigmaDecomp  as SigmaDecomp
import qualified Properties.Quad4        as Quad4
import qualified Properties.Quad4Fit     as Quad4Fit
import qualified Properties.Pipeline     as Pipeline
import qualified Properties.Significance as Significance
import qualified Properties.Hybrid       as Hybrid
import qualified Properties.Cyclic       as Cyclic
import qualified Properties.Look         as Look

main :: IO ()
main = defaultMain $ testGroup "sixfour-spec"
  [ Color.tests
  , Gauge.tests
  , Surj.tests
  , Wu.tests
  , Coverage.tests
  , Collapse.tests
  , Diversity.tests
  , GMM.tests
  , Bures.tests
  , PairTree.tests
  , Dither.tests
  , LookNet.tests
  , LookCore.tests
  , Layer.tests
  , Preference.tests
  , Bottleneck16.tests
  , SigmaDecomp.tests
  , Quad4.tests
  , Quad4Fit.tests
  , Pipeline.tests
  , Significance.tests
  , Hybrid.tests
  , Cyclic.tests
  , Look.tests
  , Scale.tests
  ]

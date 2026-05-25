module Main (main) where

import Test.Tasty

import qualified Properties.Color        as Color
import qualified Properties.Gauge        as Gauge
import qualified Properties.Surjectivity as Surj
import qualified Properties.Wu           as Wu
import qualified Properties.Coverage     as Coverage
import qualified Properties.Collapse     as Collapse
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
  , Hybrid.tests
  , Cyclic.tests
  , Look.tests
  ]

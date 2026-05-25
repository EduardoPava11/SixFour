module Main (main) where

import Test.Tasty

import qualified Properties.Color        as Color
import qualified Properties.Gauge        as Gauge
import qualified Properties.Surjectivity as Surj
import qualified Properties.Wu           as Wu
import qualified Properties.Hybrid       as Hybrid
import qualified Properties.Cyclic       as Cyclic

main :: IO ()
main = defaultMain $ testGroup "sixfour-spec"
  [ Color.tests
  , Gauge.tests
  , Surj.tests
  , Wu.tests
  , Hybrid.tests
  , Cyclic.tests
  ]

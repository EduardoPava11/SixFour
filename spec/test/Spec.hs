module Main (main) where

import Test.Tasty

import qualified Properties.Color        as Color
import qualified Properties.Gauge        as Gauge
import qualified Properties.Surjectivity as Surj
import qualified Properties.Wu           as Wu
import qualified Properties.Sinkhorn     as Sinkhorn
import qualified Properties.Hybrid       as Hybrid

main :: IO ()
main = defaultMain $ testGroup "sixfour-spec"
  [ Color.tests
  , Gauge.tests
  , Surj.tests
  , Wu.tests
  , Sinkhorn.tests
  , Hybrid.tests
  ]

module Properties.CubeLadder (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.CubeLadder

genInt :: Gen Int
genInt = choose (-1000, 1000)

-- a power-of-2 side (small, so the O(side^4) reference scan is cheap)
genSide :: Gen Int
genSide = elements [2, 4, 8]

genGrid :: Int -> Gen [Int]
genGrid side = vectorOf (side * side) genInt

tests :: TestTree
tests = testGroup "CubeLadder (16/64/256 tiers — reversible within capture, predictive beyond)"
  [ testProperty "one level reversible: unliftLevel . liftLevel = id (EXACT)" $
      forAll genSide $ \side -> forAll (genGrid side) (lawLevelReversible side)

  , testProperty "LADDER BIJECTIVE (EXACT): synthesize . distill = id within captured resolution" $
      forAll genSide $ \side ->
        forAll (choose (0, 3)) $ \levels ->
          forAll (genGrid side) $ \g ->
            (side `mod` (2 ^ levels) == 0) ==> lawLadderBijective levels side g

  , testProperty "distilled coarse plane is gamut-closed (within source range)" $
      forAll genSide $ \side -> forAll (genGrid side) (lawDistillCoarseGamutClosed side)

  , testProperty "synthBeyond (zero detail) = nearest-neighbour replicate2D (the floor)" $
      forAll (elements [1, 2, 4]) $ \h -> forAll (genGrid h) (lawSynthBeyondIsNearestNeighbour h)

  , testProperty "synthBeyond is EXACT on smooth grids (loss confined to real detail)" $
      forAll (elements [1, 2, 4]) $ \h -> forAll (genGrid h) (lawSynthBeyondExactOnSmooth h)

  , testProperty "tier64 is the substrate itself (1b: every tier is a view on one layer)" $
      forAll genSide $ \side -> forAll (genGrid side) lawTier64IsIdentity
  ]

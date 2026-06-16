module Properties.CubeLadder (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Data.Word (Word64)

import SixFour.Spec.CubeLadder
import SixFour.Spec.Upscale256 (fnv1a64)

genInt :: Gen Int
genInt = choose (-1000, 1000)

-- A FIXED 8×8 grid — the cross-language golden anchor (the Q16 target a port must hit).
goldenGrid :: [Int]
goldenGrid = [ ((i * 37 + 11) `mod` 251) - 125 | i <- [0 .. 63] ]

chk :: Show a => a -> Word64
chk x = fnv1a64 (map (fromIntegral . fromEnum) (show x))

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

    -- GOLDEN (Phase 4): byte-exact Q16 targets a Swift/Metal port must reproduce.
  , testProperty "GOLDEN: distill 2 8 of the fixed grid (FNV-1a-64 pin)" $
      once (chk (distill 2 8 goldenGrid) == (0xec4c99589f5d45dc :: Word64))

  , testProperty "GOLDEN: synthBeyond 8 1 of the fixed grid (FNV-1a-64 pin)" $
      once (chk (synthBeyond 8 1 goldenGrid) == (0x0f539f45353d9145 :: Word64))

  , testProperty "GOLDEN: round-trip recovers the fixed grid exactly" $
      once (synthesize 2 (distill 2 8 goldenGrid) == goldenGrid)
  ]

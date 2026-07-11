module Properties.LadderColorTime (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Data.Ratio ((%))

import SixFour.Spec.LadderColorTime

-- Exact nonnegative rationals for cell masses (linear-flux sums), including exact 0.
genMass :: Gen Rational
genMass = frequency
  [ (1, pure 0)
  , (9, (%) <$> choose (0, 4096) <*> choose (1, 4096))
  ]

-- A cubic volume of the given power-of-two side (kept small: the laws are side-generic).
genVolume :: Int -> Gen Volume
genVolume side = vectorOf side (vectorOf side (vectorOf side genMass))

-- Sides divisible by 4 so both poolBy 2 . poolBy 2 and poolBy 4 are defined.
genVolume4 :: Gen Volume
genVolume4 = elements [4, 8] >>= genVolume

-- Integer scalar streams (u64-like) for the fold-order laws.
genInts :: Gen [Integer]
genInts = choose (0, 64) >>= \n -> vectorOf n (choose (0, 1023))

-- Cell-tensor streams: rows of channel values (width trimmed by the law itself).
genCells :: Gen [[Integer]]
genCells = choose (0, 32) >>= \n -> vectorOf n (choose (1, 8) >>= \w -> vectorOf w (choose (0, 1023)))

tests :: TestTree
tests = testGroup "LadderColorTime (the {16,32,64} ladder trains color time — fold algebra + bridge)"
  [ testProperty "FOLD SYMMETRY: foldl == foldr == reversed traversal (commutative monoid)" $
      forAll genInts lawFoldOrderInvariant
  , testProperty "TENSOR LIFT: the fold symmetry holds for whole cell tensors (product monoid)" $
      forAll genCells lawCellTensorLifts
  , testProperty "TRANSITIVITY: poolBy 2 ∘ poolBy 2 == poolBy 4 (64→32→16 IS 64→16)" $
      forAll genVolume4 lawPoolTransitive
  , testProperty "RETRACTION: poolHalf ∘ expandDouble == id (64 is a retract of every finer rung)" $
      forAll (elements [2, 4, 8] >>= genVolume) lawPoolExpandIdentity
  , testProperty "LADDER SYMMETRY: octaves over {16,32,64,128,256} read 2,1,0,1,2" $
      once lawLadderSymmetricAboutCanonical
  , testProperty "BRIDGE: one fold step == one color-time quadrupling (side halves, τ_c ×4)" $
      forAll ((%) <$> choose (1, 4096) <*> choose (1, 4096)) $ \d0 ->
        forAll (choose (0, 4)) $ \k -> lawRungIsColorTimeStop d0 k
  ]

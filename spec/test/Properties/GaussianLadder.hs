module Properties.GaussianLadder (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Data.Ratio ((%))

import SixFour.Spec.GaussianLadder

genGInt :: Gen GInt
genGInt = GInt <$> choose (-64, 64) <*> choose (-64, 64)

genPos :: Gen Rational
genPos = do
  n <- choose (1, 4096) :: Gen Integer
  d <- choose (1, 4096) :: Gen Integer
  pure (n % d)

genRung :: Gen Int
genRung = choose (0, 6)

-- Grid levels small enough for exhaustive bijection checks (4^4 = 256).
genLevel :: Gen Int
genLevel = choose (1, 4)

-- A well-formed rung buffer: (k, 4^k Morton-ordered values).
genBufK :: Gen (Int, [Integer])
genBufK = do
  k   <- choose (2, 3)
  buf <- vectorOf (4 ^ k) (choose (-1000, 1000) :: Gen Integer)
  pure (k, buf)

tests :: TestTree
tests = testGroup "GaussianLadder (ℤ[i] ramified prime (1+i) ≡ color-time ≡ Morton/SIMT)"
  [ testProperty "N is multiplicative: N(xy) = N(x)·N(y)" $
      forAll genGInt $ \x -> forAll genGInt $ \y -> lawNormMultiplicative x y
  , testProperty "2 RAMIFIES: 2 = −i·(1+i)² and N(1+i) = 2" $
      once lawTwoRamifies
  , testProperty "rung ideal norm N(π^{2k}) = 4^k (pooled cell area)" $
      forAll genRung lawRungNormIsFour
  , testProperty "CROWN: ideal norm · Δ₀ = color-time τ_c(k)" $
      forAll genPos $ \d0 -> forAll genRung $ \k -> lawNormIsColorTime d0 k
  , testProperty "norm is a monoid hom (ℕ,+)→(ℕ,×): 4^{a+b} = 4^a·4^b" $
      forAll genRung $ \a -> forAll genRung $ \b -> lawNormIsMonoidHom a b
  , testProperty "MORTON is a bijection onto [0, 4^k)" $
      forAll genLevel lawMortonBijection
  , testProperty "parent = code ≫ 2 (memory image of the quotient by π²)" $
      forAll genLevel $ \k ->
        forAll (choose (0, 255)) $ \x -> forAll (choose (0, 255)) $ \y -> lawParentIsShift k x y
  , testProperty "SIMT COALESCING: children are contiguous {4m … 4m+3}" $
      forAll genLevel $ \k ->
        forAll (choose (0, 255)) $ \x -> forAll (choose (0, 255)) $ \y -> lawFiberContiguous k x y
  , testProperty "UNIFICATION: Morton contiguous-quad reduce == geometric 2×2 pool" $
      forAll genBufK $ \(k, buf) -> lawSimtEqualsGeometric k buf
  ]

module Properties.GaugeAction (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Test.QuickCheck (shuffle)

import SixFour.Spec.GaugeAction

-- A palette-gauge configuration together with two same-size permutations of its K slots.
genCfgGH :: Gen (PaletteConfig, Perm, Perm)
genCfgGH = do
  k   <- choose (1, 6)
  pal <- vectorOf k (choose (0, 999))
  m   <- choose (0, 8)
  idx <- vectorOf m (choose (0, max 0 (k - 1)))
  p   <- shuffle [0 .. k - 1]
  q   <- shuffle [0 .. k - 1]
  pure (PaletteConfig (pal, idx), Perm p, Perm q)

-- A channel pair with two ℤ/2 elements.
genPairGH :: Gen (ChannelPair, Z2, Z2)
genPairGH = do
  a <- choose (-50, 50)
  b <- choose (-50, 50)
  s <- arbitrary
  t <- arbitrary
  pure (ChannelPair (a, b), Z2 s, Z2 t)

tests :: TestTree
tests = testGroup "GaugeAction (finite group actions; observable = orbit invariant; invariant theory, NOT Galois)"
  [ testGroup "Palette gauge S_K — permute palette + remap index = same rendered image"
      [ testProperty "act is a group action (homomorphism + identity)" $
          forAll genCfgGH $ \(x, g, h) -> lawActIsGroupAction g h x
      , testProperty "every gauge is invertible (act g⁻¹ ∘ act g = id)" $
          forAll genCfgGH $ \(x, g, _) -> lawGaugeInvertible g x
      , testProperty "observable (the gather palette[index]) is the ORBIT INVARIANT" $
          forAll genCfgGH $ \(x, g, _) -> lawObservableIsOrbitInvariant g x
      , testProperty "S_K is NON-ABELIAN (not the cyclic Frobenius Gal(F_256/F_2)=ℤ/8)" $
          once lawPaletteGaugeIsNonAbelian
      ]

  , testGroup "ℤ/2 channel/ordering involution (swapAB / XOR ordering / phi6) — a SECOND instance"
      [ testProperty "act is a group action" $
          forAll genPairGH $ \(x, g, h) -> lawActIsGroupAction g h x
      , testProperty "observable (the unordered pair) is invariant under swap" $
          forAll genPairGH $ \(x, g, _) -> lawObservableIsOrbitInvariant g x
      , testProperty "involution is its own inverse" $
          forAll genPairGH $ \(x, g, _) -> lawGaugeInvertible g x
      ]
  ]

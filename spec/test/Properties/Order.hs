module Properties.Order (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Test.QuickCheck

import SixFour.Spec.Color    (OKLab(..))
import SixFour.Spec.GridAxis (GridAxis, IndexedColor(..), allAxes, gridSide)
import SixFour.Spec.Order

-- A random permutation on n elements.
genOrderN :: Int -> Gen Order
genOrderN n = Order <$> shuffle [0 .. n - 1]

genOrder :: Gen Order
genOrder = choose (1, 12) >>= genOrderN

-- Three permutations of the SAME size (associativity needs matching carriers).
genTriple :: Gen (Order, Order, Order)
genTriple = do
  n <- choose (1, 10)
  (,,) <$> genOrderN n <*> genOrderN n <*> genOrderN n

genOKLab :: Gen OKLab
genOKLab = OKLab <$> choose (0, 1) <*> choose (-0.4, 0.4) <*> choose (-0.4, 0.4)

genFullPalette :: Gen [IndexedColor]
genFullPalette = do
  cols <- vectorOf (gridSide * gridSide) genOKLab
  pure (zipWith IndexedColor [0 ..] cols)

genAxis :: Gen GridAxis
genAxis = elements allAxes

tests :: TestTree
tests = testGroup "Order (centralized slot→rank authority — FinitePerm group)"
  [ testProperty "every Order is a bijection on [0..n-1] (no hole/dup)" $
      forAll genOrder lawPermBijection

  , testProperty "left identity: compose (identity n) p = p" $
      forAll genOrder lawIdentityLeft

  , testProperty "right identity: compose p (identity n) = p" $
      forAll genOrder lawIdentityRight

  , testProperty "associativity: (h∘g)∘f = h∘(g∘f)" $
      forAll genTriple $ \(f, g, h) -> lawComposeAssoc f g h

  , testProperty "left inverse: compose (invert p) p = identity n" $
      forAll genOrder lawInverseLeft

  , testProperty "right inverse: compose p (invert p) = identity n" $
      forAll genOrder lawInverseRight

  , testProperty "rowMajor n is the identity permutation" $
      forAll (choose (0, 20)) lawRowMajorIsIdentity

  , testProperty "serpentine side is a permutation (resolve-sweep order)" $
      forAll (choose (1, 16)) lawSerpentineBijection

  , testProperty "golden: serpentine 2 = Order [0,1,3,2] (row 1 reversed)" $
      once $ serpentine 2 === Order [0, 1, 3, 2]

  , testProperty "slotAt ∘ rankOf = id (round-trip on a random Order)" $
      forAll genOrder $ \o ->
        and [ slotAt o (rankOf o i) == i | i <- [0 .. size o - 1] ]

  , testProperty "axisOrder inherits the gridLayout bijection (full 256 palette)" $
      forAll genAxis $ \x -> forAll genAxis $ \y -> forAll genFullPalette (lawAxisOrderBijection x y)

  , testProperty "golden: fromGrid [[0,3],[2,1]] = Order [0,3,2,1]" $
      once $ fromGrid [[0, 3], [2, 1]] === Order [0, 3, 2, 1]

  , testProperty "golden: rowMajor 4 = Order [0,1,2,3]" $
      once $ rowMajor 4 === Order [0, 1, 2, 3]
  ]

module Properties.GridAxis (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Test.QuickCheck

import SixFour.Spec.Color    (OKLab(..))
import SixFour.Spec.GridAxis

genOKLab :: Gen OKLab
genOKLab = OKLab <$> choose (0, 1) <*> choose (-0.4, 0.4) <*> choose (-0.4, 0.4)

-- A FULL palette: exactly gridSide² (256) colours with distinct slot indices
-- [0..255] (the real shape). Order is arbitrary, exercising order-invariance.
genFullPalette :: Gen [IndexedColor]
genFullPalette = do
  cols <- vectorOf (gridSide * gridSide) genOKLab
  pure (zipWith IndexedColor [0 ..] cols)

genAxis :: Gen GridAxis
genAxis = elements allAxes

-- Hand-computed golden (side = 2, 4 colours; x = L, y = a):
--   sort by (L,index): (0.1,0),(0.2,2),(0.8,3),(0.9,1) → [0,2,3,1]
--   columns of 2:      col0 = [0,2], col1 = [3,1]
--   col0 by (a,index): idx0 a=0.2, idx2 a=0.3 → rows [0,2]
--   col1 by (a,index): idx3 a=-0.2, idx1 a=-0.1 → rows [3,1]
--   grid[row][col]:    row0 = [0,3], row1 = [2,1]
goldenInput :: [IndexedColor]
goldenInput =
  [ IndexedColor 0 (OKLab 0.1   0.2  0)
  , IndexedColor 1 (OKLab 0.9 (-0.1) 0)
  , IndexedColor 2 (OKLab 0.2   0.3  0)
  , IndexedColor 3 (OKLab 0.8 (-0.2) 0)
  ]

tests :: TestTree
tests = testGroup "GridAxis (user-assignable 2-axis 16×16 palette grid)"
  [ testProperty "layout is a bijection onto the input slot set (no loss/dup)" $
      forAll genAxis $ \x -> forAll genAxis $ \y -> forAll genFullPalette (lawLayoutIsBijection x y)

  , testProperty "full layout is 16×16" $
      forAll genAxis $ \x -> forAll genAxis $ \y -> forAll genFullPalette (lawLayoutDimensions x y)

  , testProperty "columns are X-ordered blocks (col c max-X ≤ col c+1 min-X)" $
      forAll genAxis $ \x -> forAll genAxis $ \y -> forAll genFullPalette (lawColumnsXOrdered x y)

  , testProperty "rows are Y-sorted within each column" $
      forAll genAxis $ \x -> forAll genAxis $ \y -> forAll genFullPalette (lawRowsYSorted x y)

  , testProperty "deterministic: layout xs = layout (reverse xs)" $
      forAll genAxis $ \x -> forAll genAxis $ \y -> forAll genFullPalette (lawDeterministicUnderPermutation x y)

  , testProperty "golden: side=2, x=L y=a → [[0,3],[2,1]]" $
      once $ gridLayoutN 2 AxisL AxisA goldenInput === [[0, 3], [2, 1]]

  , testProperty "axis count: 6 assignable axes" $
      once $ length allAxes === 6

  , testProperty "grid arithmetic: side=16, cells=256" $
      once $ (gridSide === 16) .&&. (gridCells === 256)

  , testProperty "wrong-size input → empty layout (full-palette contract)" $
      forAll (choose (0, 20)) $ \n ->
        n /= gridSide * gridSide ==>
          gridLayout AxisL AxisA (zipWith IndexedColor [0 ..] (replicate n (OKLab 0.5 0 0))) === []
  ]

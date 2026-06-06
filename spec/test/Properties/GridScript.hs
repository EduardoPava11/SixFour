module Properties.GridScript (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Test.QuickCheck

import SixFour.Spec.Color    (OKLab(..))
import SixFour.Spec.GridAxis (GridAxis, IndexedColor(..), allAxes, gridSide)
import SixFour.Spec.Order    (Order(..), fromGrid)
import SixFour.Spec.GridScript

-- A GridScript with a random permutation order over a side×side grid, paired with
-- a palette of that many DISTINCT elements (distinctness makes the permutation
-- law meaningful).
genScriptAndPalette :: Gen (GridScript, [Int])
genScriptAndPalette = do
  side <- choose (1, 5)
  let n = side * side
  perm <- shuffle [0 .. n - 1]
  let palette = [10, 20 ..]                  -- distinct, deterministic
  pure (GridScript "gen" side (Order perm), take n palette)

genOKLab :: Gen OKLab
genOKLab = OKLab <$> choose (0, 1) <*> choose (-0.4, 0.4) <*> choose (-0.4, 0.4)

genFullPalette :: Gen [IndexedColor]
genFullPalette = do
  cols <- vectorOf (gridSide * gridSide) genOKLab
  pure (zipWith IndexedColor [0 ..] cols)

genAxis :: Gen GridAxis
genAxis = elements allAxes

tests :: TestTree
tests = testGroup "GridScript (form-follows-function spine + render equivalence)"
  [ testProperty "surface preserves cell count (total)" $
      forAll genScriptAndPalette $ \(gs, pal) -> lawSurfaceTotal gs pal

  , testProperty "surface is a permutation of the palette (no synthesis/loss/dup)" $
      forAll genScriptAndPalette $ \(gs, pal) -> lawSurfacePermutes gs pal

  , testProperty "RENDER EQUIVALENCE: bitmap backend == concat canvas backend" $
      forAll genScriptAndPalette $ \(gs, pal) -> lawRenderEquivalence gs pal

  , testProperty "captureScript is row-major: surface = palette unchanged" $
      forAll (choose (1, 6)) $ \side ->
        let pal = take (side * side) [0 :: Int ..]
        in surfaceBitmap (captureScript side) pal === pal

  , testProperty "reviewAxisScript surface permutes the full 256 palette" $
      forAll genAxis $ \x -> forAll genAxis $ \y -> forAll genFullPalette $ \cols ->
        let pal = map icIndex cols
        in lawSurfacePermutes (reviewAxisScript gridSide x y cols) pal

  , testProperty "golden: fromGrid [[0,3],[2,1]] places [10,20,30,40] → [10,40,30,20]" $
      once $ surfaceBitmap (GridScript "g" 2 (fromGrid [[0, 3], [2, 1]])) ([10, 20, 30, 40] :: [Int])
               === [10, 40, 30, 20]

  , testProperty "golden: captureScript 2 on [10,20,30,40] is identity" $
      once $ surfaceBitmap (captureScript 2) ([10, 20, 30, 40] :: [Int]) === [10, 20, 30, 40]
  ]

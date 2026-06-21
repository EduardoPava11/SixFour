module Properties.OctreeForward (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.OctreeForward

genInt :: Gen Int
genInt = choose (-65536, 65536)

genCut :: Gen (Int, Int, [Int])
genCut = do
  d  <- elements [0, 1, 2]
  k  <- choose (0, d)
  xs <- vectorOf (8 ^ d) genInt
  pure (k, d, xs)

tests :: TestTree
tests = testGroup "OctreeForward (capstone FSM: surface + held -> refine -> commit)"
  [ testProperty "surface is lossless: surfaced + held reconstructs the capture" $
      forAll genCut (\(k, d, xs) -> lawSurfaceLossless k d xs)

  , testProperty "surfaced cube is the 8^(d-cut) rung (16^3 at the product cut)" $
      forAll genCut (\(k, d, xs) -> lawSurfacedIsRung k d xs)

  , testProperty "refining one level preserves the capture" $
      forAll genCut (\(k, d, xs) -> lawRefineOneLossless k d xs)

  , testProperty "refining one level drops the held cut by one" $
      forAll genCut (\(k, d, xs) -> lawRefineOneShrinksHeld k d xs)

  , testProperty "commit changes nothing but phase (capture preserved)" $
      forAll genCut (\(k, d, xs) -> lawCommitPreservesCapture k d xs)

  , testProperty "commit is idempotent" $
      forAll genCut (\(k, d, xs) -> lawCommitIdempotent k d xs)

  , -- golden: 64-voxel capture surfaced at cut 2 -> 1-voxel shown, lossless
    testProperty "golden: surface 2 2 [0..63] shows 1 voxel and round-trips" $
      once (length (surfacedCube (surface 2 2 [0 .. 63])) == 1
            && refineSession (surface 2 2 [0 .. 63]) == [0 .. 63])

  , -- the product run: every 64^3 capture surfaces exactly one 16^3 (4096) rung
    testProperty "surface-16: a 64^3 capture surfaces exactly one 16^3 (4096) rung" $
      once (lawRunSurfacesExactlyOne16 [0 .. 8 ^ (6 :: Int) - 1])
  ]

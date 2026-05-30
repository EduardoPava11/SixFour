module Properties.SplitTree (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Test.QuickCheck

import SixFour.Spec.Color    (OKLab(..))
import SixFour.Spec.SplitTree

genOKLab :: Gen OKLab
genOKLab = OKLab <$> choose (0, 1) <*> choose (-0.4, 0.4) <*> choose (-0.4, 0.4)

-- A non-empty point set with distinct slot indices [0..n-1] (the real shape: indices are
-- array positions). Order is arbitrary, exercising order-invariance.
genIndexed :: Gen [IndexedColor]
genIndexed = do
  n    <- choose (1, 40)
  cols <- vectorOf n genOKLab
  pure (zipWith IndexedColor [0 ..] cols)

genBranching :: Gen Branching
genBranching = elements [B16, B4, B2]

-- Hand-computed golden: four greyscale points (a = b = 0) so the widest axis is L.
-- Sorted by (L, index): (0.1,0),(0.2,2),(0.8,3),(0.9,1) → split → lo=[0,2], hi=[3,1].
goldenInput :: [IndexedColor]
goldenInput =
  [ IndexedColor 0 (OKLab 0.1 0 0)
  , IndexedColor 1 (OKLab 0.9 0 0)
  , IndexedColor 2 (OKLab 0.2 0 0)
  , IndexedColor 3 (OKLab 0.8 0 0)
  ]

tests :: TestTree
tests = testGroup "SplitTree (median-cut spatial partition — the renderer's navigable structure)"
  [ testProperty "partition: leaf count = input count" $
      forAll genIndexed lawLeafCountIsInput

  , testProperty "partition is exact: leaf index set = input index set (no loss/dup)" $
      forAll genIndexed lawPartition

  , testProperty "deterministic: build xs = build (reverse xs) (pinned (coord,index) tie-break)" $
      forAll genIndexed lawDeterministicUnderPermutation

  , testProperty "child bounding boxes are nested inside the parent" $
      forAll genIndexed lawChildBoxesNested

  , testProperty "addressing: every leaf round-trips through its prefix path" $
      forAll genIndexed lawAddressRoundTrip

  , testProperty "addressing: all leaf addresses are distinct (injective)" $
      forAll genIndexed lawAddressesDistinct

  , testProperty "collapse to any branching preserves the leaf sequence" $
      forAll genBranching $ \b -> forAll genIndexed (lawCollapsePreservesLeaves b)

  , testProperty "perfect depth-d tree has 2^d − 1 split planes" $
      forAll (choose (0, 8)) lawPlaneCount

  , -- SixFour-shape laws (pinned, deterministic).
    testProperty "256-leaf view: every internal node has exactly b children" $
      forAll genBranching lawViewChildCount

  , testProperty "arithmetic: 256 = 16² = 4⁴ = 2⁸; bᵈ=256 ∀ views; octree impossible (3∤8)" $
      once lawBranchingArithmetic

  , testProperty "collapse bookkeeping: collapseK b · branchDepth b = paletteDepth = 8" $
      once lawCollapseDepthInvariant

  , testProperty "SixFour shape: depth 8, 256 leaves; b/d table 16×2, 4×4, 2×8" $
      once $
           paletteDepth == 8
        && numLeaves == 256
        && map branchFactor [B16, B4, B2] == [16, 4, 2]
        && map branchDepth  [B16, B4, B2] == [2, 4, 8]
        && map collapseK    [B16, B4, B2] == [4, 2, 1]

  , -- Golden vector the Swift port must reproduce bit-for-bit.
    testProperty "golden: 4 greyscale points → leaf order [0,2,3,1], root splits L at 0.5" $
      once $
        let t = buildSplitTree goldenInput
            rootOK = case t of
              Branch ax pos _ _ -> ax == AxisL && abs (pos - 0.5) < 1e-12
              _                 -> False
            addrs = [ (icIndex ic, path) | (path, ic) <- leafPaths t ]
        in leafIndices t == [0, 2, 3, 1]
           && rootOK
           && lookup 0 addrs == Just [0, 0]
           && lookup 2 addrs == Just [0, 1]
           && lookup 3 addrs == Just [1, 0]
           && lookup 1 addrs == Just [1, 1]
  ]

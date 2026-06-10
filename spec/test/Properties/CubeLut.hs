module Properties.CubeLut (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.ColorFixed   (q16One, linearToOklabQ16, oklabToLinearSRGBQ16)
import SixFour.Spec.ZoneProfile  (ZoneProfileQ16, analyzeZoneProfileQ16)
import SixFour.Spec.LookTransfer (defaultTransferParamsQ16, transferOklabQ16)
import SixFour.Spec.RedFrontEnd  (redDecodeToLinearQ16, gamutCompressQ16, applyBlackLiftQ16)
import SixFour.Spec.CubeLut

genPalette :: Gen [(Int, Int, Int)]
genPalette = listOf1 $ do
  l <- choose (0, q16One)
  a <- choose (negate (q16One `div` 4), q16One `div` 4)
  b <- choose (negate (q16One `div` 4), q16One `div` 4)
  pure (l, a, b)

tests :: TestTree
tests = testGroup "CubeLut"
  [ -- ★ Grid ordering: the element at the .cube index bi·n² + gi·n + ri is the
    -- voxel for (ri,gi,bi). This is the law that prevents an R/B-swapped LUT.
    testProperty "★ buildCubeQ16 is in .cube order (bi·n² + gi·n + ri)" $
      forAll genPalette $ \pal ->
        let zp = analyzeZoneProfileQ16 pal
            n  = cubeSizeGolden
            cube = buildCubeQ16 defaultTransferParamsQ16 zp n
            ok (ri,gi,bi) = cube !! (bi*n*n + gi*n + ri)
                              == cubeVoxelQ16 defaultTransferParamsQ16 zp n (ri,gi,bi)
        in and [ ok (ri,gi,bi) | bi <- [0..n-1], gi <- [0..n-1], ri <- [0..n-1] ]

  , -- Grid coordinate anchors: index 0 → 0, index n-1 → q16One.
    testProperty "cubeGridCoordQ16 anchors: 0→0, (n-1)→q16One" $
      forAll (choose (2, 65)) $ \n ->
        cubeGridCoordQ16 n (0,0,0) == (0,0,0)
        && cubeGridCoordQ16 n (n-1,n-1,n-1) == (q16One,q16One,q16One)

  , -- Every voxel is a valid sRGB-encoded triple in [0, q16One].
    testProperty "every voxel is in [0, q16One]" $
      forAll genPalette $ \pal ->
        let zp = analyzeZoneProfileQ16 pal
            n  = cubeSizeGolden
            inRange v = v >= 0 && v <= q16One
            ok (r,g,b) = inRange r && inRange g && inRange b
        in all ok (buildCubeQ16 defaultTransferParamsQ16 zp n)

  , -- ★ preview ≡ cube: the cube voxel is EXACTLY the documented composition
    -- around transferOklabQ16 — i.e. the cube uses the SAME look transform the
    -- preview maps over the palette. A regression guard on that equality.
    testProperty "★ preview ≡ cube: voxel == compose(transferOklabQ16, …)" $
      forAll genPalette $ \pal ->
        let zp = analyzeZoneProfileQ16 pal
            p  = defaultTransferParamsQ16
            n  = cubeSizeGolden
            recompose idx =
              let coord  = cubeGridCoordQ16 n idx
                  oklab  = linearToOklabQ16 (redDecodeToLinearQ16 coord)
                  graded = transferOklabQ16 p zp oklab
                  (cr,cg,cb) = gamutCompressQ16 (applyBlackLiftQ16 (oklabToLinearSRGBQ16 graded))
              in (srgbEncodeSampleQ16 cr, srgbEncodeSampleQ16 cg, srgbEncodeSampleQ16 cb)
            ok idx = cubeVoxelQ16 p zp n idx == recompose idx
        in and [ ok (ri,gi,bi) | bi <- [0..n-1], gi <- [0..n-1], ri <- [0..n-1] ]

  , -- Size: an N³ cube has exactly N³ entries (n=2 ⇒ 8 corners).
    testProperty "buildCubeQ16 has exactly n³ entries" $
      forAll genPalette $ \pal ->
        let zp = analyzeZoneProfileQ16 pal
        in length (buildCubeQ16 defaultTransferParamsQ16 zp 2) == 8
           && length (buildCubeQ16 defaultTransferParamsQ16 zp cubeSizeGolden) == cubeSizeGolden^(3::Int)
  ]

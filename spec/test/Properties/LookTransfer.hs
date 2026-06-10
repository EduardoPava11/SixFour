module Properties.LookTransfer (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.ColorFixed  (q16One)
import SixFour.Spec.ZoneProfile  (ZoneProfileQ16, analyzeZoneProfileQ16, sampleZoneTargetQ16, chromaQ16)
import SixFour.Spec.LookTransfer

-- A small synthetic palette to build a non-trivial profile from.
genPalette :: Gen [(Int, Int, Int)]
genPalette = listOf1 genPx

genPx :: Gen (Int, Int, Int)
genPx = do
  l <- choose (0, q16One)
  a <- choose (negate (q16One `div` 4), q16One `div` 4)
  b <- choose (negate (q16One `div` 4), q16One `div` 4)
  pure (l, a, b)

tests :: TestTree
tests = testGroup "LookTransfer"
  [ -- ★ THE load-bearing law: the transform is chrominance-ONLY — lightness L is
    -- never touched. (gif_palette_lut.py "keep filmic L*, only shift a*/b*".)
    testProperty "★ luminance preservation: output L == input L" $
      forAll genPalette $ \pal -> forAll genPx $ \(l, a, b) ->
        let zp = analyzeZoneProfileQ16 pal
            (l', _, _) = transferOklabQ16 defaultTransferParamsQ16 zp (l, a, b)
        in l' == l

  , -- strength 0 ⇒ identity (for non-neutral inputs, so we are out of the
    -- epsilon-chroma branch). No look = no change.
    testProperty "strength 0 is the identity (chroma ≥ eps)" $
      forAll genPalette $ \pal -> forAll genPx $ \(l, a, b) ->
        let zp = analyzeZoneProfileQ16 pal
            p0 = defaultTransferParamsQ16 { tpStrength = 0 }
            inC = chromaQ16 a b
        in inC < tpChromaEps p0  -- skip neutral inputs
           || transferOklabQ16 p0 zp (l, a, b) == (l, a, b)

  , -- At full strength the output chrominance lies along the TARGET direction
    -- (both the normal branch and the epsilon-snap branch are collinear with the
    -- polarity-applied target). Cross-product ≈ 0 up to integer truncation.
    testProperty "full strength: output (a,b) is collinear with the zone target" $
      forAll genPalette $ \pal -> forAll genPx $ \(l, a, b) ->
        let zp = analyzeZoneProfileQ16 pal
            pF = defaultTransferParamsQ16 { tpStrength = q16One }
            (_, aOut, bOut) = transferOklabQ16 pF zp (l, a, b)
            (tA, tB, _)     = sampleZoneTargetQ16 zp l
            cross = aOut * tB - bOut * tA
            slack = abs tA + abs tB + 4
        in abs cross <= slack

  , -- Polarity inversion flips the target hue: the +pol and -pol targets are
    -- negatives, so at full strength the two outputs point in opposite
    -- directions (their a/b dot product is ≤ 0 up to truncation).
    testProperty "inverted polarity opposes normal polarity at full strength" $
      forAll genPalette $ \pal -> forAll genPx $ \(l, a, b) ->
        let zp  = analyzeZoneProfileQ16 pal
            pP  = defaultTransferParamsQ16 { tpStrength = q16One, tpPolarity = q16One }
            pN  = defaultTransferParamsQ16 { tpStrength = q16One, tpPolarity = negate q16One }
            (_, aP, bP) = transferOklabQ16 pP zp (l, a, b)
            (_, aN, bN) = transferOklabQ16 pN zp (l, a, b)
            dot = aP * aN + bP * bN
            (tA, tB, _) = sampleZoneTargetQ16 zp l
        in (tA == 0 && tB == 0)            -- degenerate target: no direction to flip
           || dot <= abs tA + abs tB + 4   -- otherwise the dot is ≤ ~0

  , -- The preview is exactly the per-entry map (this is what lets the cube reuse
    -- the same core per voxel).
    testProperty "transferPaletteQ16 == map transferOklabQ16" $
      forAll genPalette $ \pal -> forAll genPalette $ \inp ->
        let zp = analyzeZoneProfileQ16 pal
            p  = defaultTransferParamsQ16
        in transferPaletteQ16 p zp inp == map (transferOklabQ16 p zp) inp
  ]

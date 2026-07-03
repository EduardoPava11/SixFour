module Properties.CaptureFormat (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Test.QuickCheck

import SixFour.Spec.CaptureFormat
import SixFour.Spec.Export (decimate2D, replicate2D)

-- A full captureSide² index plane (256-valued cells, the per-frame palette indices).
genPlane :: Gen [Int]
genPlane = vectorOf (captureSide * captureSide) (choose (0, 255))

-- A smaller full side² plane for the generic decimate∘replicate inverse (side ∈ 1..6, factor ∈ 1..4).
genSmall :: Gen (Int, Int, [Int])
genSmall = do
  side   <- choose (1, 6)
  factor <- choose (1, 4)
  cells  <- vectorOf (side * side) (choose (0, 255))
  pure (factor, side, cells)

-- A full capture at the CANONICAL shape: captureFrames frames of (256-entry sRGB8 palette,
-- captureSide² index plane). Heavy (64 × 4096 cells per case), so the property runs few cases —
-- the shape is what matters, not the case count (audit G6, 2026-07-03).
genCapture :: Gen [([(Int, Int, Int)], [Int])]
genCapture =
  vectorOf captureFrames $ do
    pal   <- vectorOf capturePaletteEntries
               ((,,) <$> choose (0, 255) <*> choose (0, 255) <*> choose (0, 255))
    plane <- vectorOf (captureSide * captureSide) (choose (0, 255))
    pure (pal, plane)

tests :: TestTree
tests = testGroup "CaptureFormat (app export GIF == encoder input; 64³ logical, 256²×64 wire)"
  [ testProperty "keystone: importWireToCapture ∘ exportFrameToWire == id on a 64² index plane" $
      forAll genPlane lawExportImportRoundTripsIndices

  , testProperty "FULL ARTIFACT: the whole 64-frame capture (palettes + planes) round-trips; palettes verbatim on the wire" $
      withMaxSuccess 5 $ forAll genCapture lawExportImportRoundTripsCapture

  , testProperty "generic: decimate2D ∘ replicate2D == id for any side/factor" $
      forAll genSmall $ \(f, s, c) ->
        decimate2D f (f * s) (replicate2D f s c) === c

  , testProperty "time axis is UNSCALED at the wire (256²×64, never 256³)" $
      once lawTimeAxisUnscaledAtWire

  , testProperty "wire is spatial-only 4× (wireSide = captureSide·4, frames unchanged)" $
      once lawWireIsSpatialFourXOnly

  , testProperty "capture is nudge-aligned (16³ grid divides 64³, one cell per 4³ block)" $
      once lawCaptureNudgeAligned

  , testProperty "palette is per-frame sRGB8 (256 entries, 8-bit, no GCT)" $
      once lawCapturePaletteIsPerFrameSrgb8

  , testProperty "shipping constants: capture 64×64×64, wire 256×256×64, cell span 4" $
      once $ (captureSide === 64) .&&. (captureFrames === 64)
               .&&. (wireSide === 256) .&&. (wireFrames === 64)
               .&&. (captureCellSpan === 4)

  , testProperty "the capture-format capstone (lawCaptureFormatSound) holds" $
      once lawCaptureFormatSound

  , testProperty "golden: a 2×2 plane [10,20,30,40] replicates to 4×4 and decimates back" $
      once $ decimate2D 2 4 (replicate2D 2 2 ([10, 20, 30, 40] :: [Int]))
               === [10, 20, 30, 40]
  ]

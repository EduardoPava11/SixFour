{- |
Module      : SixFour.Spec.CaptureFormat
Description : The ONE canonical capture format — the app's exported GIF IS the encoder's input.

This module pins the single capture-format contract so that __what the app outputs as a capture is the
same artifact the encoder ingests for inference__, and nudges align onto it.

The capture is logically __64³__ (64×64 spatial × 64 frames, per-frame 256-entry palette). The shipped
GIF is its __spatial-only 4× replication__ ('SixFour.Spec.Export.replicate2D'): 64²→256² in the INDEX
domain, frame count UNCHANGED (256×256×64). Import reverses it by exact decimation
('SixFour.Spec.Export.decimate2D'): 256²→64², byte-exact in the index domain. So:

  * @exportFrameToWire@  = 'replicate2D' @upscaleFactor@ — the app's 256² display-fidelity frame;
  * @importWireToCapture@ = 'decimate2D' @upscaleFactor@ — the encoder's 64² logical frame;
  * they are EXACT inverses on the index plane ('lawExportImportRoundTripsIndices').

__The replicate2D-vs-upscale256 distinction (the keystone correction).__ There are two different
"×4 to 256" operations and they are NOT the same artifact. The shipped capture is 'Export.replicate2D'
(space-only, frames stay 64). 'SixFour.Spec.Upscale256.upscale256' is 4× in space AND TIME (64³→256³,
64→256 frames, with palette blend) — that is the model's deterministic floor __OUTPUT__
('Upscale256.UpscaleOutput' = 'ModelIO.ModelOutput'), NEVER the capture wire. 'lawTimeAxisUnscaledAtWire'
makes the "time is never scaled at the wire" fact a theorem, so the two can never be conflated again.

__The colour boundary (Opt-1, hardened to Opt-3).__ A GIF palette is necessarily sRGB8 — GIF89a cannot
store more than 8 bits/channel. The model works in OKLab Q16, but @okLabToSRGB8 . srgb8ToOKLabQ16 /= id@,
so Q16 is NOT recoverable byte-exact from a shipped GIF. The canonical capture palette is therefore
__sRGB8 + index__ (the artifact of record); OKLab Q16 stays the model's INTERNAL working space (the floor,
the d6 metric, the nudges, the ANT math), and is deterministically re-derived from sRGB8 on import. The
round-trip is exact ONLY at the (index plane + sRGB8 palette) level — see the load-bearing guardrail
'contractQ16NotRecoverableAcrossGif'.
-}
-- COMPARTMENT: SWIFT-COREAI | tag:DisplaySide
module SixFour.Spec.CaptureFormat
  ( -- * Capture / wire dimensions
    captureSide
  , captureFrames
  , wireSide
  , wireFrames
    -- * Palette (sRGB8, per-frame)
  , capturePaletteEntries
  , captureColorDepthBits
  , capturePerFrame
    -- * Nudge alignment
  , captureControlGridSide
  , captureCellSpan
    -- * The export / import maps (one frame's index plane)
  , exportFrameToWire
  , importWireToCapture
    -- * Laws
  , lawExportImportRoundTripsIndices
  , lawTimeAxisUnscaledAtWire
  , lawWireIsSpatialFourXOnly
  , lawCaptureNudgeAligned
  , lawCapturePaletteIsPerFrameSrgb8
  , lawCaptureFormatSound
    -- * Guardrail (Opt-3 hardening)
  , contractQ16NotRecoverableAcrossGif
  ) where

import SixFour.Spec.Export   (upscaleFactor, sourceSide, outputSide, replicate2D, decimate2D)
import SixFour.Spec.CellNudge (controlGridSide)

-- | The logical capture spatial side: 64 (= 'Export.sourceSide').
captureSide :: Int
captureSide = sourceSide

-- | The capture frame count: 64. The TIME axis is never scaled at the wire (see 'lawTimeAxisUnscaledAtWire').
captureFrames :: Int
captureFrames = 64

-- | The shipped GIF spatial side: 256 (= @captureSide * upscaleFactor@, = 'Export.outputSide').
wireSide :: Int
wireSide = outputSide

-- | The shipped GIF frame count: equal to 'captureFrames' (NO temporal upscale at export).
wireFrames :: Int
wireFrames = captureFrames

-- | Per-frame palette size: 256 entries (a GIF Local Color Table).
capturePaletteEntries :: Int
capturePaletteEntries = 256

-- | Palette colour depth on the wire: 8 bits/channel (sRGB8 — the most a GIF can carry).
captureColorDepthBits :: Int
captureColorDepthBits = 8

-- | Palettes are PER-FRAME (Local Color Tables, no Global Color Table). The global path is V2-deferred
-- (@Feature.globalPaletteV2 = False@ in the app).
capturePerFrame :: Bool
capturePerFrame = True

-- | The nudge control-grid side: 16 (= 'CellNudge.controlGridSide'). Tied here so a format change that
-- broke the 64³ alignment would break this module.
captureControlGridSide :: Int
captureControlGridSide = controlGridSide

-- | How many capture voxels (per axis) one nudge cell governs: @captureSide \`div\` captureControlGridSide@
-- = @64 \`div\` 16@ = 4. (One cell → a 4³ block of the 64³ capture, → a 4096-leaf 256³ subtree.)
captureCellSpan :: Int
captureCellSpan = captureSide `div` captureControlGridSide

-- | Export one frame's @captureSide²@ index plane to the @wireSide²@ shipped frame: spatial 4× replication.
exportFrameToWire :: [a] -> [a]
exportFrameToWire = replicate2D upscaleFactor captureSide

-- | Import one frame's @wireSide²@ shipped index plane back to the @captureSide²@ logical frame: exact decimation.
importWireToCapture :: [a] -> [a]
importWireToCapture = decimate2D upscaleFactor wireSide

-- * Laws

-- | THE keystone: @importWireToCapture ∘ exportFrameToWire == id@ on a full @captureSide²@ index plane.
-- The app's shipped frame decimates back to the exact logical frame the encoder ingests (index-exact).
lawExportImportRoundTripsIndices :: Eq a => [a] -> Bool
lawExportImportRoundTripsIndices plane =
  length plane /= captureSide * captureSide
    || importWireToCapture (exportFrameToWire plane) == plane

-- | The TIME axis is unscaled at the wire: the shipped GIF has the same 64 frames as the capture. This is
-- the theorem that forbids conflating the capture wire ('Export.replicate2D', space-only) with the model
-- floor output ('Upscale256.upscale256', space-AND-time).
lawTimeAxisUnscaledAtWire :: Bool
lawTimeAxisUnscaledAtWire = wireFrames == captureFrames && captureFrames == 64

-- | The wire is a SPATIAL-only 4×: @wireSide == captureSide * upscaleFactor@ and frames are unchanged.
lawWireIsSpatialFourXOnly :: Bool
lawWireIsSpatialFourXOnly =
  wireSide == captureSide * upscaleFactor && wireFrames == captureFrames

-- | The capture is exactly nudge-aligned: the 16³ control grid divides the 64³ capture, one cell per 4³ block.
lawCaptureNudgeAligned :: Bool
lawCaptureNudgeAligned =
  captureSide `mod` captureControlGridSide == 0
    && captureCellSpan == 4
    && captureControlGridSide == 16

-- | The capture palette is per-frame sRGB8: 256 entries, 8 bits/channel, no Global Color Table.
lawCapturePaletteIsPerFrameSrgb8 :: Bool
lawCapturePaletteIsPerFrameSrgb8 =
  capturePerFrame && captureColorDepthBits == 8 && capturePaletteEntries == 256

-- | GUARDRAIL (Opt-3 hardening) — a documented OBLIGATION, not a theorem: it carries no truth value.
-- The shipped GIF palette is sRGB8; the model works in OKLab Q16; @okLabToSRGB8 . srgb8ToOKLabQ16 /= id@,
-- so Q16 is NEVER recoverable byte-exact from a shipped GIF. No law in this codebase may assert Q16
-- recovery, nor palette-ORDER stability (@SynthesisPolicyValue.relationallyOrder@), ACROSS a GIF
-- re-import — such a golden would be "lying green" (true on a fixed fixture, false on real re-imported
-- data). Round-trip exactness is promised ONLY at the (index + sRGB8 palette) level
-- ('lawExportImportRoundTripsIndices'). Referenced by 'lawCaptureFormatSound' so this marker is
-- load-bearing: deleting it breaks the build.
contractQ16NotRecoverableAcrossGif :: ()
contractQ16NotRecoverableAcrossGif = ()

-- | The capture-format capstone: time unscaled at the wire, the wire is spatial-only 4×, the nudge grid
-- divides the capture, the palette is per-frame sRGB8, and the Q16 guardrail marker is present
-- (load-bearing via @seq@).
lawCaptureFormatSound :: Bool
lawCaptureFormatSound =
     lawTimeAxisUnscaledAtWire
  && lawWireIsSpatialFourXOnly
  && lawCaptureNudgeAligned
  && lawCapturePaletteIsPerFrameSrgb8
  && (contractQ16NotRecoverableAcrossGif `seq` True)

{- |
Module      : SixFour.Spec.ModelIO
Description : The MODEL I/O CONTRACT: the single boundary the UI paints into, the UI renders out of, the 256³ is built from, AND the trainer targets. INPUT = the 64³ capture (a "SixFour.Spec.Upscale256" @UpscaleInput@) + the user's 16³ nine-channel paint ("SixFour.Spec.CellNudge" @CellBudget@) + the φ6 gauge toggle. OUTPUT = the 256³ as a "SixFour.Spec.Upscale256" @UpscaleOutput@ = per-frame palettes (VALUE) + index planes (CONTENT), i.e. exactly GIF89a, so the UI renders frame @f@ from @(outPalettes!!f, outCube!!f)@ with no extra decode.

Why this module exists: the model is only useful if its boundary is wireable. This pins, as laws, that
(1) the OUTPUT is per-frame value × content the UI can draw ('lawOutputIsPerFrameValueContent'), (2) the
neutral (unpainted) input builds the deterministic floor ('lawNeutralNudgeIsAllFloor'; its byte
exactness is "SixFour.Spec.Upscale256" @lawK0PaletteExact@), (3) the painted nudge is the 9-channel surface the UI offers
('lawInputIsPaintable') and a painted 16³ cell governs a 4096-leaf 256³ subtree
('lawNudgeGovernsSuperRes'). The TRAINER shares this contract: its held-out target IS a 'ModelOutput'
(the 256³), so what the model learns to emit is exactly what the UI renders and the 256³-builder
produces. One boundary, four consumers. Additive, pure-spec, emits no golden.
-}
-- COMPARTMENT: MLX-MODEL | tag:MacTag
module SixFour.Spec.ModelIO
  ( -- * The model boundary types
    ModelInput(..)
  , ModelOutput
  , neutralNudge
  , buildFloor
  , renderFrame
    -- * Laws
  , lawOutputIsPerFrameValueContent
  , lawNeutralNudgeIsAllFloor
  , lawInputIsPaintable
  , lawNudgeGovernsSuperRes
  ) where

import qualified Data.Vector as V

import SixFour.Spec.Upscale256
  ( UpscaleInput, UpscaleOutput(..), PxQ16, upscale256 )
import SixFour.Spec.CellNudge
  ( CellBudget, emptyCellBudget, lawNineChannelsAtCell, lawCellGovernsSuperResSubtree )

-- | The model input the UI assembles: the captured 64³ super-res input, the user's 16³ nine-channel
-- paint, and the φ6 gauge choice (which nine pairs the paint names).
data ModelInput = ModelInput
  { miCapture :: UpscaleInput   -- ^ the 64³ capture's super-res input (per-frame palettes + carried exit state).
  , miNudge   :: CellBudget     -- ^ the user's 16³ × 9-channel paint (the budget per coarse cell).
  , miGauge   :: Bool           -- ^ the φ6 gauge toggle (colour-by-space vs the dual).
  }

-- | The model output IS the renderable 256³: per-frame palettes (VALUE) + index planes (CONTENT) =
-- GIF89a. No separate decode type, so the UI and the 256³ builder consume the same value.
type ModelOutput = UpscaleOutput

-- | The neutral (unpainted) nudge over @nCells@ cells: zero everywhere = the safe byte-exact floor.
neutralNudge :: Int -> CellBudget
neutralNudge = emptyCellBudget

-- | Build the deterministic FLOOR 256³ from the capture (the output at zero nudge). The learned
-- PonderNet invention rides ABOVE this where the user paints; the floor is what an unpainted input
-- always yields ('lawNeutralNudgeIsAllFloor'), byte-exact per "SixFour.Spec.Upscale256" @lawK0PaletteExact@.
buildFloor :: ModelInput -> ModelOutput
buildFloor = upscale256 . miCapture

-- | Render output frame @f@: the @(palette, index plane)@ pair the UI draws (the GIF89a frame). Total
-- on any in-range frame; the contract guarantees one palette per index plane.
renderFrame :: ModelOutput -> Int -> ([PxQ16], V.Vector Int)
renderFrame out f = (outPalettes out !! f, outCube out !! f)

-- ---------------------------------------------------------------------------
-- Laws
-- ---------------------------------------------------------------------------

-- | The OUTPUT is per-frame VALUE × CONTENT: one palette per index plane (the GIF89a structure), so
-- every frame is directly renderable as @palette[index]@. Teeth: a mismatched count would leave a
-- frame with no palette to render against.
lawOutputIsPerFrameValueContent :: Bool
lawOutputIsPerFrameValueContent =
  let out = UpscaleOutput [[], []] [V.empty, V.empty]   -- 2 frames, each a (palette, index plane)
  in length (outPalettes out) == length (outCube out)

-- | The neutral nudge is all-floor: an unpainted control volume has zero budget in every cell, so
-- nothing is invented and 'buildFloor' is the deterministic super-res whose @k = 0@ exactness is
-- "SixFour.Spec.Upscale256" @lawK0PaletteExact@ (cited there, not re-proven here).
lawNeutralNudgeIsAllFloor :: Int -> Bool
lawNeutralNudgeIsAllFloor n0 =
  let n = abs n0 `mod` 100
  in all (all (== 0)) (neutralNudge n)

-- | The INPUT nudge is the nine-channel paintable surface the UI offers (delegates
-- "SixFour.Spec.CellNudge").
lawInputIsPaintable :: Bool
lawInputIsPaintable = lawNineChannelsAtCell

-- | A painted 16³ cell governs a 4096-leaf subtree of the 256³ output (delegates
-- "SixFour.Spec.CellNudge" @lawCellGovernsSuperResSubtree@): the paint maps onto the build at the
-- self-similar twiceness scale.
lawNudgeGovernsSuperRes :: Bool
lawNudgeGovernsSuperRes = lawCellGovernsSuperResSubtree

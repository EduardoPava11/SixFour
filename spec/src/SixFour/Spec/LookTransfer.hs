{- |
Module      : SixFour.Spec.LookTransfer
Description : The chrominance-only LOOK transform — the ONE function the live
              preview and the exported .cube LUT both call (preview ≡ cube).

Given a 'ZoneProfileQ16' (the look, derived from the captured palette) and an
input OKLab Q16 colour, KEEP the lightness @L@ and bend the chrominance @(a,b)@
toward the zone target at that @L@, then scale chroma toward the blended target
chroma. This is the OKLab port of the @gif_palette_lut.py@ chrominance-only
transfer (lines 271–286): "keep filmic L*, only shift a*/b*".

== Why this is the keystone
The whole feature pivots on the live 256-colour preview and the 65³ cube using a
BYTE-IDENTICAL transfer. So this function is the single source; 'transferPaletteQ16'
is the preview (map over the palette) and "SixFour.Spec.CubeLut" calls
'transferOklabQ16' per voxel. @Properties.LookTransfer@ + @Properties.CubeLut@
pin the "preview ≡ cube" equality as a LAW, not a hope.

== Parameters
A look variant is a choice of 'TransferParamsQ16' (strength + polarity); the
PROFILE is always live-derived, so the look is data-driven, not canned.
-}
-- COMPARTMENT: SWIFT-COREAI | tag:DisplaySide
module SixFour.Spec.LookTransfer
  ( TransferParamsQ16(..)
  , defaultTransferParamsQ16
  , transferOklabQ16
  , transferPaletteQ16
  ) where

import SixFour.Spec.ColorFixed (q16One)
import SixFour.Spec.ZoneProfile (ZoneProfileQ16, chromaQ16, sampleZoneTargetQ16)

-- | Transfer parameters, all Q16. A "look variant" is one of these over a
-- live-derived profile.
data TransferParamsQ16 = TransferParamsQ16
  { tpStrength  :: !Int  -- ^ blend toward target, @[0, q16One]@ (python @TRANSFER_STRENGTH@)
  , tpChromaMin :: !Int  -- ^ chroma-scale clamp low (python @0.1@)
  , tpChromaMax :: !Int  -- ^ chroma-scale clamp high (python @3.0@)
  , tpPolarity  :: !Int  -- ^ @+q16One@ normal, @-q16One@ inverts the target (complement)
  , tpChromaEps :: !Int  -- ^ below this blended chroma, snap to the target direction
  } deriving (Eq, Show)

-- | Defaults matching @gif_palette_lut.py@: strength 0.75, chroma clamp [0.1,3.0],
-- normal polarity, a tiny epsilon for the neutral-colour branch.
defaultTransferParamsQ16 :: TransferParamsQ16
defaultTransferParamsQ16 = TransferParamsQ16
  { tpStrength  = (3 * q16One) `div` 4   -- 0.75
  , tpChromaMin = q16One `div` 10        -- 0.1
  , tpChromaMax = 3 * q16One             -- 3.0
  , tpPolarity  = q16One                 -- +1
  , tpChromaEps = 64                     -- ≈ 0.001
  }

-- | The look transform on ONE OKLab Q16 colour. Keeps @L@; blends @(a,b)@ toward
-- the (polarity-applied) zone target by @strength@; scales chroma toward the
-- blended chroma target, clamped to @[tpChromaMin, tpChromaMax]@. Below
-- 'tpChromaEps' blended chroma the @(a,b)@ direction is numerically unstable, so
-- we snap straight to the target direction scaled to the blended chroma.
transferOklabQ16 :: TransferParamsQ16 -> ZoneProfileQ16 -> (Int, Int, Int) -> (Int, Int, Int)
transferOklabQ16 p zp (l, a, b) =
  let s = tpStrength p
      (targetA0, targetB0, targetC) = sampleZoneTargetQ16 zp l
      pol = tpPolarity p
      ta = (targetA0 * pol) `quot` q16One   -- polarity flips the target hue
      tb = (targetB0 * pol) `quot` q16One
      -- blend a/b toward the (polarity-applied) target by strength
      aOut0 = (a * (q16One - s) + ta * s) `quot` q16One
      bOut0 = (b * (q16One - s) + tb * s) `quot` q16One
      curC = chromaQ16 aOut0 bOut0
      inC  = chromaQ16 a b
      -- blend chroma magnitude toward the target chroma by strength
      cTargetBlended = (inC * (q16One - s) + targetC * s) `quot` q16One
  in if curC < tpChromaEps p
       then -- unstable direction → use the target direction at the blended chroma
            let dirC    = chromaQ16 ta tb
                safeDir = max 1 dirC
                aSnap   = (ta * cTargetBlended) `quot` safeDir
                bSnap   = (tb * cTargetBlended) `quot` safeDir
            in (l, aSnap, bSnap)
       else
            let safeC    = max 1 curC
                rawScale = (cTargetBlended * q16One) `quot` safeC
                cScale   = max (tpChromaMin p) (min (tpChromaMax p) rawScale)
                aOut     = (aOut0 * cScale) `quot` q16One
                bOut     = (bOut0 * cScale) `quot` q16One
            in (l, aOut, bOut)

-- | The PREVIEW look: map the transform over a whole palette. Each entry is
-- independent (no cross-pixel state), which is exactly why the cube can reuse
-- 'transferOklabQ16' per voxel.
transferPaletteQ16 :: TransferParamsQ16 -> ZoneProfileQ16 -> [(Int, Int, Int)] -> [(Int, Int, Int)]
transferPaletteQ16 p zp = map (transferOklabQ16 p zp)

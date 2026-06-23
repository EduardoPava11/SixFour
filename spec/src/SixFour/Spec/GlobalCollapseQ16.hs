-- COMPARTMENT: ZIG-FLOOR | tag:DeviceTag
{- |
Module      : SixFour.Spec.GlobalCollapseQ16
Description : The SHIPPED byte-exact Q16 global collapse (GIFA -> GIFB) + the HARD-MUST-1 PaletteScope gate — the device-reproducible integer half split OUT of "SixFour.Spec.Collapse" (whose float OKLab maximin baseline stays METAL-GPU). This is the Zig @s4_global_collapse@ reference: maximin over integer @PxQ16@ so the golden index sequence reproduces bit-for-bit on device.

Destructive compartment pivot: @Collapse@ was a genuine straddler — a float OKLab maximin
baseline (a Metal/spec reference, determinism class TOL) co-resident with this shipped
byte-exact Q16 collapse (determinism class EXACT, the Zig integer reference via
"SixFour.Spec.QuantFixed"). A single golden cannot gate both as one unit, so they split along
the determinism seam: the @[OKLab]@ 'Double' baseline stays in @Collapse@ (METAL-GPU), the
@PxQ16@ integer substrate is here (ZIG-FLOOR).

⚠️ V2-DEFERRED-GLOBAL-PALETTE — the single-global-collapse is the global (GIFB) path, deferred
to V2 behind the Swift gate @Feature.globalPaletteV2@ (false in MVP1); kept + golden-gated for
V2. The 'PaletteScope' gate ('shippedScope' == 'PerFrame') is the spec-level statement of HARD
MUST #1 (per-frame palettes only). GHC-boot-only. Laws QuickCheck'd in "Properties.GlobalCollapseQ16".
-}
module SixFour.Spec.GlobalCollapseQ16
  ( -- * The shipped Q16 collapse (byte-exact, device-reproducible)
    PxQ16
  , pooledCandidatesQ16
  , globalCollapseQ16
  , globalCollapseIndicesQ16
  , reindexFrameQ16
    -- * Palette-scope gate (HARD MUST #1: per-frame palettes only)
  , PaletteScope(..)
  , shippedScope
  , poolsAcrossFrames
  ) where

import qualified Data.Vector as V

import SixFour.Spec.QuantFixed
  ( farthestPointSeedsQ16, farthestPointSeedIndicesQ16, nearestCentroidQ16 )

-- | A Q16 OKLab triple (scale @2^16@) — the integer substrate of
-- 'SixFour.Spec.ColorFixed' / the Zig core. The shipped collapse works here, not
-- in 'Double', so its golden index sequence reproduces bit-for-bit on device (a
-- greedy maximin argmax over near-tied 'Double's would diverge between platforms).
type PxQ16 = (Int, Int, Int)

-- | Pool every entry across the 64 per-frame Q16 palettes — the candidate cloud
-- the collapse selects from (order-invariant multiset; @concat@).
pooledCandidatesQ16 :: [[PxQ16]] -> [PxQ16]
pooledCandidatesQ16 = concat

-- | The per-frame → single-palette collapse in Q16: maximin (farthest-point)
-- selection of @k@ representatives over the pooled cloud. This is the SAME
-- operator 'SixFour.Spec.QuantFixed.farthestPointSeedsQ16' applies to one frame's
-- pixels — here applied to the union of all frames — so it is already mirrored
-- byte-for-byte by the Zig @s4_quantize_frame@ seed phase. Every chosen colour is
-- an actual input colour (gamut-closed); ties resolve to the lowest index.
--
-- ⚠️ V2-DEFERRED-GLOBAL-PALETTE — this single-global-collapse (and its siblings
-- 'globalCollapseIndicesQ16' / 'reindexFrameQ16') is the global (GIFB) path, deferred to V2 behind
-- the Swift gate Feature.globalPaletteV2 (false in MVP1). Kept + golden-gated for V2, not a live
-- MVP1 path. The GENERIC 'Collapse.farthestPointCollapse' / 'Collapse.pooledCandidates' stay live
-- (the maximin floor). Do not add new callers.
globalCollapseQ16 :: Int -> [[PxQ16]] -> [PxQ16]
globalCollapseQ16 k = farthestPointSeedsQ16 k . pooledCandidatesQ16

-- | The collapse's chosen-index sequence into the pooled cloud (the golden pins
-- this exact order). @globalCollapseQ16 k = map (pooled !!) . globalCollapseIndicesQ16 k@.
globalCollapseIndicesQ16 :: Int -> [[PxQ16]] -> [Int]
globalCollapseIndicesQ16 k = farthestPointSeedIndicesQ16 k . pooledCandidatesQ16

-- | Re-index one frame's colours against the collapsed global leaves: each colour
-- maps to its nearest leaf (squared Q16 distance, strict @<@ ⇒ lowest index on
-- ties — the GIF GCT index map). Mirrors 'nearestCentroidQ16'.
reindexFrameQ16 :: [PxQ16] -> [PxQ16] -> [Int]
reindexFrameQ16 leaves = map (nearestCentroidQ16 (V.fromList leaves))

-- ---------------------------------------------------------------------------
-- Palette-scope gate (HARD MUST #1: per-frame palettes only)
-- ---------------------------------------------------------------------------

-- | Which palette scope a render path uses. 'PerFrame' gives every frame its own
-- 256-colour palette (GIFA — the shipped MVP1 product); 'Global' pools all frames
-- into one shared palette via 'globalCollapseQ16' (GIFB — V2-deferred). This is the
-- spec-level mirror of the Swift @Feature.globalPaletteV2@ flag.
data PaletteScope = PerFrame | Global
  deriving (Eq, Show, Enum, Bounded)

-- | The scope the shipped product renders in. Pinned to 'PerFrame': the spec-level
-- statement of HARD MUST #1 (per-frame palettes only, no global-palette collapse),
-- mirroring @Feature.globalPaletteV2 = false@. 'Properties.GlobalCollapseQ16' gates that
-- this never silently becomes 'Global'.
shippedScope :: PaletteScope
shippedScope = PerFrame

-- | Whether a scope pools colours across frames (the global-collapse path). Only
-- 'Global' does; 'PerFrame' keeps each frame independent. So
-- @not (poolsAcrossFrames shippedScope)@ is exactly "the shipped path never invokes
-- 'globalCollapseQ16'".
poolsAcrossFrames :: PaletteScope -> Bool
poolsAcrossFrames PerFrame = False
poolsAcrossFrames Global   = True

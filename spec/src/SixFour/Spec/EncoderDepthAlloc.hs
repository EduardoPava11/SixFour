{- |
Module      : SixFour.Spec.EncoderDepthAlloc
Description : The EARNED encoder DEPTH (layer count) — sized by the octant ladder, not "L=6 by convention". The structural ceiling is @levelsBetween 64 4 = 4@ (the octant levels from the 64³ capture to the 4³ token waist); a modality's depth is how many of those levels still carry positive detail. Teeth: a cut one level short destroys @octreeLeafCount(d−l) − octreeLeafCount(d−l−1)@ non-recoverable detail dims.

This earns the last un-earned encoder axis. WIDTH ("SixFour.Spec.EncoderWidthAlloc") is a
partition of the fixed 512; DEPTH is orthogonal (the layer count) and is sized by the octant
rate-distortion ladder, NOT chosen:

  * 'structuralDepthCeiling' = @levelsBetween 64 4 = 4@ — the octant levels @64³ → 32³ → 16³ → 8³ → 4³@.
    Each level is one @octantLift@ (volume ÷ 8). This is the CEILING any encoder can need; it is a
    proven count (@octreeLeafCount 6 / octreeLeafCount 2 = 8⁴@), NOT the @octreeDepth 64 = 6@ coincidence.
  * 'drainedDepth' / 'encoderDepth' — a modality's depth is the deepest octant level that still
    carries positive detail (the drained-remainder count), capped at the ceiling. A modality whose
    detail flattens early (the index, going constant in flat regions) earns a SHALLOW encoder; one
    whose detail persists at every level (the perceptual field) earns the full DEEP encoder.
  * 'droppedFinestDetail' + 'lawPrematureCutDropsDetail' (TEETH) — truncating at level @l@ destroys
    @octreeLeafCount(d−l) − octreeLeafCount(d−l−1) = 7·8^(d−l−1)@ detail dims (@d=4 ⇒ [3584,448,56,7]@),
    non-recoverable because a coarse DC alone cannot invert an off-flat octant. So depth MUST reach
    the deepest level with detail — a too-shallow encoder provably loses information.

HONEST: the FORM is earned (depth = drained octant levels, capped at the proven ceiling). The
specific per-modality numbers (index≈2, palette≈1, perceptual=4) await a measured corpus to pin
the detail profiles — the witnesses below demonstrate the mechanism, they are not corpus numbers.

GHC-boot-only; re-pins nothing. Laws QuickCheck'd in "Properties.EncoderDepthAlloc".
-}
-- COMPARTMENT: MLX-MODEL | tag:MacTag
module SixFour.Spec.EncoderDepthAlloc
  ( -- * The octant-ladder depth
    captureSide
  , waistSide
  , structuralDepthCeiling
  , droppedFinestDetail
  , drainedDepth
  , encoderDepth
    -- * Laws (QuickCheck'd in @Properties.EncoderDepthAlloc@)
  , lawDepthCeilingIsOctantLadder
  , lawDepthIsDrainedRemainder
  , lawPrematureCutDropsDetail
  ) where

import SixFour.Spec.OctreeCell   (levelsBetween)
import SixFour.Spec.OctreeGenome (octreeLeafCount)

-- | The capture side: the 64³ burst the encoders read.
captureSide :: Int
captureSide = 64

-- | The token-waist side: the 4³ = 64 octant-leaf lattice the ViT attends over.
waistSide :: Int
waistSide = 4

-- | The structural depth ceiling = the octant levels from capture to waist
-- (@64³ → 32³ → 16³ → 8³ → 4³@). A proven count, the most layers any encoder can need.
structuralDepthCeiling :: Int
structuralDepthCeiling = levelsBetween captureSide waistSide

-- | The detail dims destroyed by truncating a depth-@d@ encoder at level @l@ (the finest dropped
-- level): @octreeLeafCount(d−l) − octreeLeafCount(d−l−1) = 7·8^(d−l−1)@. Always positive for
-- @0 ≤ l < d@, so any premature cut loses non-recoverable detail.
droppedFinestDetail :: Int -> Int -> Int
droppedFinestDetail d l = octreeLeafCount (d - l) - octreeLeafCount (d - l - 1)

-- | The drained depth of a per-level detail profile: the deepest level (1-indexed) that still
-- carries positive detail. Detail that flattens early ⇒ shallow; detail everywhere ⇒ deep.
drainedDepth :: [Double] -> Int
drainedDepth bits = case [ i | (i, b) <- zip [1 :: Int ..] bits, b > 0 ] of
  [] -> 0
  xs -> maximum xs

-- | A modality's EARNED encoder depth: its drained depth, capped at the structural ceiling.
encoderDepth :: [Double] -> Int
encoderDepth = min structuralDepthCeiling . drainedDepth

-- =============================================================================
-- Laws
-- =============================================================================

-- | The depth ceiling is the octant ladder count (@64³ → 4³@ = 4 levels), a PROVEN structural
-- number @octreeLeafCount 6 / octreeLeafCount 2 = 8⁴@ — NOT the @octreeDepth 64 = 6@ coincidence.
lawDepthCeilingIsOctantLadder :: Bool
lawDepthCeilingIsOctantLadder =
     structuralDepthCeiling == levelsBetween 64 4
  && structuralDepthCeiling == 4
  && octreeLeafCount 6 `div` octreeLeafCount 2 == 8 ^ structuralDepthCeiling

-- | Depth tracks the drained remainder: detail flattening early earns a shallow encoder, detail
-- at every level earns the full-depth encoder, and the depth is capped at the structural ceiling.
-- (Representative profiles — the index≈2 / palette≈1 / perceptual=4 numbers await a corpus.)
lawDepthIsDrainedRemainder :: Bool
lawDepthIsDrainedRemainder =
     encoderDepth [5, 2, 0, 0]        == 2                       -- index-like: flat after 2 levels
  && encoderDepth [5, 4, 3, 2]        == 4                       -- perceptual-like: positive everywhere
  && encoderDepth [3, 0, 0, 0]        == 1                       -- palette-like: one level
  && encoderDepth [5, 4, 3, 2, 9, 9]  == structuralDepthCeiling  -- capped at the ceiling

-- | TEETH (the rate-distortion core): truncating at any level short destroys positive,
-- non-recoverable detail — verified @d=4 ⇒ [3584, 448, 56, 7]@ — so the encoder depth MUST reach
-- the deepest level that carries detail; a shallower encoder provably loses information.
lawPrematureCutDropsDetail :: Bool
lawPrematureCutDropsDetail =
     [ droppedFinestDetail 4 l | l <- [0, 1, 2, 3] ] == [3584, 448, 56, 7]
  && all (\l -> droppedFinestDetail structuralDepthCeiling l > 0) [0 .. structuralDepthCeiling - 1]

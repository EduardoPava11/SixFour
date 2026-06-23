{- |
Module      : SixFour.Spec.PerceptualEncoder
Description : Encoder B — the GIF as a PERCEPTUAL point cloud over the six axes (L,a,b,x,y,t): human-eye colour acuity (Lab) plus 2D+1D space-time (xyt). The second of the two encoders the dual-encoder H-JEPA proves are one object (the construction encoder A is "SixFour.Spec.ConstructionEncoder").

Where Encoder A ("SixFour.Spec.ConstructionEncoder") is the /build recipe/ (palette +
index), Encoder B is the /perception/: every voxel becomes a comparable 6D point
'P6' @(L,a,b,x,y,t)@ — its colour from the three "SixFour.Spec.SameObjectInvariance" @Cube@
channels, its position @(x,y,t)@ lifted from the implicit octant-Morton index (exactly the
lift "SixFour.Spec.RelationalResidual" describes: "position lifted from the implicit Morton
index into a real value so distance is computable across regions"). The distance between
two voxels is then the relational metric @d6@ ("SixFour.Spec.RelationalMemory").

This module is deliberately THIN: it adds the @Cube → [P6]@ adapter and nothing else, so it
does not collide with the in-flight L/t integration in
"SixFour.Spec.RelationalResidual"\/"SixFour.Spec.RelationalMemory" (treated here as
read-only inputs).

  * 'mortonToXYT' — de-interleave a linear octant-Morton index into @(x,y,t)@ (a bijection
    on @[0, 8^d)@; the position lift).
  * 'perceptualEmbed' — @Cube@ at depth @d@ to its @[P6]@ point cloud.
  * 'lawPerceptualEmbedsAllSixAxes' — every voxel maps to a P6 carrying BOTH its colour and
    a DISTINCT position (the position lift is injective; all six axes are populated).
  * 'lawPerceptualReusesD6' — voxel distance IS "SixFour.Spec.RelationalMemory" @d6@, and it
    is position-aware: two voxels of equal colour at different positions are distinguished
    (delegates @lawPositionDistinguishesSameColour@).

Additive: reuses "SixFour.Spec.SameObjectInvariance" @Cube@, "SixFour.Spec.RelationalResidual"
@P6@, "SixFour.Spec.RelationalMemory" @d6@\/@dColour@, "SixFour.Spec.OctreeGenome"
@octreeLeafCount@. GHC-boot-only. Laws QuickCheck'd in "Properties.PerceptualEncoder".
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none
module SixFour.Spec.PerceptualEncoder
  ( -- * Encoder B: the perceptual point cloud
    mortonToXYT
  , perceptualEmbed
  , perceptualDistance
    -- * Laws (QuickCheck'd in @Properties.PerceptualEncoder@)
  , lawPerceptualEmbedsAllSixAxes
  , lawPerceptualReusesD6
  ) where

import Data.Bits  ((.&.), (.|.), shiftR, shiftL)
import Data.List  (nub)

import SixFour.Spec.SameObjectInvariance (Cube(..), validCube)
import SixFour.Spec.OctreeGenome         (octreeLeafCount)
import SixFour.Spec.RelationalResidual   (P6(..))
import SixFour.Spec.RelationalMemory     (d6, dColour)

-- | De-interleave a linear octant-Morton index @m@ at depth @d@ into @(x,y,t)@: each base-8
-- digit of @m@ is one 2×2×2 lane whose three bits are the @(x,y,t)@ parities at that level.
-- A bijection from @[0, 8^d)@ to @[0, 2^d)³@ — the position lift Encoder B reads off the
-- implicit index ("SixFour.Spec.RelationalResidual").
mortonToXYT :: Int -> Int -> (Int, Int, Int)
mortonToXYT d = go 0 0 0 0
  where
    go k x y t n
      | k >= d    = (x, y, t)
      | otherwise =
          let dig = n .&. 7
              bx  =  dig        .&. 1
              by  = (dig `shiftR` 1) .&. 1
              bt  = (dig `shiftR` 2) .&. 1
          in go (k + 1)
                (x .|. (bx `shiftL` k))
                (y .|. (by `shiftL` k))
                (t .|. (bt `shiftL` k))
                (n `shiftR` 3)

-- | Encode a 'Cube' at octant depth @d@ as its perceptual point cloud: voxel @v@ becomes the
-- 6D point @P6 L a b x y t@ — colour @(L,a,b)@ from the three channels, position @(x,y,t)@
-- from 'mortonToXYT'. The order matches the channels' Morton order, so index @v@ lines up.
perceptualEmbed :: Int -> Cube -> [P6]
perceptualEmbed d (Cube cl ca cb) =
  [ let (x, y, t) = mortonToXYT d v in P6 l a b x y t
  | (v, l, a, b) <- zip4 [0 ..] cl ca cb ]
  where
    zip4 (w:ws) (p:ps) (q:qs) (r:rs) = (w, p, q, r) : zip4 ws ps qs rs
    zip4 _      _      _      _      = []

-- | The perceptual distance between two voxels of a cube — the relational metric @d6@ over
-- their 'P6' embeddings ("SixFour.Spec.RelationalMemory"). The function the dual-encoder
-- distance ("SixFour.Spec.CrossEncoderDistance") measures the inter-semantic gap with.
perceptualDistance :: Int -> Cube -> Int -> Int -> Int
perceptualDistance d cube i j =
  let pts = perceptualEmbed d cube in d6 (pts !! i) (pts !! j)

-- ============================================================================
-- Laws (predicates; QuickCheck'd in Properties.PerceptualEncoder)
-- ============================================================================

-- | Encoder B is total and faithful over all six axes: a well-formed cube embeds to exactly
-- @8^d@ points, each P6's colour equals its channel values, and the POSITION lift is
-- injective — every voxel gets a DISTINCT @(x,y,t)@ (so two voxels are never confused on
-- position). Teeth: a position lift that collapsed voxels (e.g. constant position) makes the
-- distinct-position count drop below @8^d@ and fails.
lawPerceptualEmbedsAllSixAxes :: Int -> Cube -> Bool
lawPerceptualEmbedsAllSixAxes d cube
  | not (validCube d cube) = True
  | otherwise =
      let pts          = perceptualEmbed d cube
          Cube cl ca cb = cube
          n            = octreeLeafCount d
          colours      = [ (p6L p, p6A p, p6B p) | p <- pts ]
          positions    = [ (p6X p, p6Y p, p6T p) | p <- pts ]
      in length pts == n
         && colours == zip3 cl ca cb                 -- colour faithfully carried
         && length (nub positions) == n              -- positions all DISTINCT (injective lift)

-- | The perceptual distance IS "SixFour.Spec.RelationalMemory" @d6@, and it is
-- POSITION-AWARE: a colour-only view (@dColour@) is blind to two equal-coloured voxels at
-- different positions, but @d6@ separates them. This is what makes Encoder B a genuine
-- /perceptual/ encoder (Lab acuity + xyt locality), not a palette histogram. Closed witness
-- (a 2-voxel cube at @d=1@-style positions) so it stays @:: Bool@; teeth: a position-blind
-- distance collapses the two and fails the final conjunct.
lawPerceptualReusesD6 :: Bool
lawPerceptualReusesD6 =
  let -- two voxels, SAME colour, different Morton positions (indices 0 and 1 ⇒ x differs)
      cube       = Cube [5,5,5,5,5,5,5,5] [7,7,7,7,7,7,7,7] [9,9,9,9,9,9,9,9]  -- d=1, 8 voxels
      pts        = perceptualEmbed 1 cube
      p0         = head pts
      p1         = pts !! 1
  in validCube 1 cube
     && perceptualDistance 1 cube 0 1 == d6 p0 p1          -- the distance IS d6
     && dColour p0 p1 == 0                                  -- colour-only is blind
     && d6 p0 p1 > 0                                        -- d6 (position-aware) separates them

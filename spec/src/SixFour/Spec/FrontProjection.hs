{- |
Module      : SixFour.Spec.FrontProjection
Description : RULE-CUBE-2D-IDENTITY — the 2D GIF hero IS the front projection of the
              3D index cube at the rest pose. The Haskell source of truth the
              Swift-only @VoxelRestPoseIdentityTests@ was missing.

The Review screen shows the same data two ways: the flat 2D GIF and the 64³ voxel
cube. The unifying claim ('SixFour.Spec.RepresentationUnification') is that these are
not two representations but ONE — the 2D image is exactly the cube's near face. This
module makes that a /theorem/ rather than a Swift-local assertion: it pins the depth→
frame map and proves the rest-pose pixel identity, reusing the already-proven clock.

== The depth → frame map

The cube's raymarcher maps a depth slice @z ∈ [0,N)@ to a frame
@f(z) = (cursor - (N-1) + z) mod N@ ('SixFour.Spec.PlaybackClock.frontFaceFrame'). At
the NEAR face @z = N-1@ this collapses to @f(N-1) = clampFrame cursor@ — the SAME
frame the 2D path shows ('twoDFrame'). So the front face is the current GIF frame
('lawFrontIsCurrentFrame'), and the front-projected /pixel/ equals the 2D /pixel/ for
every cursor and place ('lawRestPoseEqualsGifFrame').

== Reuse, not re-proof

The pixel identity is DISCHARGED by 'SixFour.Spec.PlaybackClock''s
@threeDFrontFace == twoDFrame@ law (already @cabal test@-green): both projections read
the same frame and the same @(palette, index)@ gather, so equal frame ⇒ equal pixel.
No new geometric argument is introduced.

GHC-boot-only: base + 'SixFour.Spec.PlaybackClock' / '.Lattice' / '.PairTreeFixed'.
-}
-- COMPARTMENT: SWIFT-COREAI | tag:DisplaySide
module SixFour.Spec.FrontProjection
  ( -- * The cube and its faces
    IndexCube, Palettes, Pixel
  , fieldSide
  , gifFrame, frontFaceFrame        -- which frame each path shows
    -- * The two projections
  , gifIndexAt, frontIndexAt        -- the index each path reads at (x,y)
  , gifPixelAt, frontPixelAt        -- the colour each path shows at (x,y)
    -- * Laws
  , lawFrontIsCurrentFrame          -- near face (z=N-1) shows frame == cursor
  , lawRestPoseEqualsGifFrame       -- 2D pixel == 3D front-face pixel ∀ cursor,(x,y)
  , lawFrontIndexInRange            -- totality: the projection stays on the field
  ) where

import SixFour.Spec.PlaybackClock (FrameCount, twoDFrame, threeDFrontFace)
import SixFour.Spec.Lattice       (previewCells)
import SixFour.Spec.PairTreeFixed (OKLabI)

-- | The GIF field side @H = W = 64@ ('previewCells').
fieldSide :: Int
fieldSide = previewCells

-- | The index cube: @N@ frames, each a row-major @fieldSide·fieldSide@ list of
-- palette indices (the deterministic Zig core's output).
type IndexCube = [[Int]]

-- | Per-frame palettes: @N@ frames, each a 256-leaf Q16 OKLab palette.
type Palettes = [[OKLabI]]

-- | A displayed pixel (Q16 OKLab, pre-sRGB8; the gather output).
type Pixel = OKLabI

-- | The frame the flat 2D GIF shows for a cursor — the clamped cursor
-- ('SixFour.Spec.PlaybackClock.twoDFrame').
gifFrame :: FrameCount -> Int -> Int
gifFrame = twoDFrame

-- | The frame the cube's NEAR face (@z = N-1@) shows for a cursor
-- ('SixFour.Spec.PlaybackClock.threeDFrontFace').
frontFaceFrame :: FrameCount -> Int -> Int
frontFaceFrame = threeDFrontFace

-- | The index a frame holds at @(x,y)@ (row-major), total over a well-formed cube.
indexOf :: IndexCube -> Int -> (Int, Int) -> Int
indexOf cube frame (x, y) = (cube !! frame) !! (y * fieldSide + x)

-- | The index the 2D GIF reads at @(x,y)@.
gifIndexAt :: FrameCount -> IndexCube -> Int -> (Int, Int) -> Int
gifIndexAt n cube cur p = indexOf cube (gifFrame n cur) p

-- | The index the cube's near face reads at @(x,y)@.
frontIndexAt :: FrameCount -> IndexCube -> Int -> (Int, Int) -> Int
frontIndexAt n cube cur p = indexOf cube (frontFaceFrame n cur) p

-- | The colour a frame's palette gives an index.
colourOf :: Palettes -> Int -> Int -> Pixel
colourOf pals frame idx = (pals !! frame) !! idx

-- | The 2D GIF pixel at @(x,y)@: gather the clamped-cursor frame's index.
gifPixelAt :: FrameCount -> IndexCube -> Palettes -> Int -> (Int, Int) -> Pixel
gifPixelAt n cube pals cur p = colourOf pals (gifFrame n cur) (gifIndexAt n cube cur p)

-- | The cube's near-face pixel at @(x,y)@: gather the front-face frame's index.
frontPixelAt :: FrameCount -> IndexCube -> Palettes -> Int -> (Int, Int) -> Pixel
frontPixelAt n cube pals cur p =
  colourOf pals (frontFaceFrame n cur) (frontIndexAt n cube cur p)

-- LAWS ----------------------------------------------------------------------

-- | The near face (@z = N-1@) shows the CURRENT frame: @frontFaceFrame == gifFrame@.
-- Discharge: REUSE 'SixFour.Spec.PlaybackClock' (@threeDFrontFace == twoDFrame@).
lawFrontIsCurrentFrame :: FrameCount -> Int -> Bool
lawFrontIsCurrentFrame n cur = frontFaceFrame n cur == gifFrame n cur

-- | RULE-CUBE-2D-IDENTITY: the 2D GIF pixel equals the 3D front-face pixel for every
-- cursor and place. Discharge: both read the SAME frame ('lawFrontIsCurrentFrame') and
-- the same @(palette, index)@ gather, so equal frame ⇒ equal pixel. No GPU snapshot,
-- no geometric re-proof.
lawRestPoseEqualsGifFrame
  :: FrameCount -> IndexCube -> Palettes -> Int -> (Int, Int) -> Bool
lawRestPoseEqualsGifFrame n cube pals cur p =
  frontPixelAt n cube pals cur p == gifPixelAt n cube pals cur p

-- | Totality: for a well-formed cube (≥ N frames, each ≥ @fieldSide²@ entries) and a
-- place on the field, the front projection's frame and index both stay in range — the
-- projection never reads off the cube.
lawFrontIndexInRange :: FrameCount -> IndexCube -> Int -> (Int, Int) -> Bool
lawFrontIndexInRange n cube cur (x, y) =
  frame >= 0 && frame < length cube
  && offset >= 0 && offset < length (cube !! frame)
  where
    frame  = frontFaceFrame n cur
    offset = y * fieldSide + x

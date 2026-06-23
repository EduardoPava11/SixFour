{- |
Module      : SixFour.Spec.GifDualView
Description : THE KEYSTONE of the dual-encoder H-JEPA — one GIF object, two encoders, and the commutative square that proves they are the SAME object. Encoder A ("SixFour.Spec.ConstructionEncoder", palette + index) and Encoder B ("SixFour.Spec.PerceptualEncoder", the (L,a,b,x,y,t) cloud) are two faithful VIEWS of one 'GifObject'; both decode to the same pixels.

A GIF is one object described two ways. This module names the object — 'GifObject' (a pixel
cube at an octant depth) — and both encodings as VIEWS of it:

  * 'viewA' = the construction view: palettize the pixels into a (palette, index) recipe
    ("SixFour.Spec.ConstructionEncoder"). 'decodeA' = @buildPixels@ executes it back.
  * 'viewB' = the perceptual view: the @(L,a,b,x,y,t)@ point cloud
    ("SixFour.Spec.PerceptualEncoder"). 'decodeB' recovers the pixels (drop position, keep
    colour in Morton order).

The square commutes: @decodeA . viewA == id == decodeB . viewB@. Both views are exact,
invertible coordinatisations of the one object — "two encoders, one GIF". (Encoder A here
uses an UNBOUNDED palette, so it is lossless; the lossy palette-BUDGET case and its @d6@
distortion live in "SixFour.Spec.CrossEncoderDistance", and the SCALE at which the gap opens
in "SixFour.Spec.ScaleIndexedCorrespondence".)

  * 'lawSameObjectBothViews' — KEYSTONE: both views decode to the SAME pixels.
  * 'lawSectionEmbedsLossless' — Encoder B is a lossless section: @decodeB . viewB == id@,
    with teeth (a view that dropped a channel fails).
  * 'lawRetractionRoundTrip' — 'palettizeExact' is a section of @buildPixels@:
    @decodeA . viewA == id@ for every object (the construction recipe rebuilds the GIF).

Additive: reuses "SixFour.Spec.ConstructionEncoder", "SixFour.Spec.PerceptualEncoder",
"SixFour.Spec.SameObjectInvariance" @Cube@. GHC-boot-only. Laws QuickCheck'd in
"Properties.GifDualView".
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none
module SixFour.Spec.GifDualView
  ( -- * The one object and its two views
    GifObject(..)
  , validGifObject
  , palettizeExact
  , viewA
  , viewB
  , decodeA
  , decodeB
    -- * Laws (QuickCheck'd in @Properties.GifDualView@)
  , lawSameObjectBothViews
  , lawSectionEmbedsLossless
  , lawRetractionRoundTrip
  ) where

import Data.List (nub, elemIndex)

import SixFour.Spec.SameObjectInvariance (Cube(..), validCube)
import SixFour.Spec.ConstructionEncoder  (Construction(..), buildPixels)
import SixFour.Spec.PerceptualEncoder    (perceptualEmbed)
import SixFour.Spec.RelationalResidual   (P6(..))

-- | The one object: a pixel 'Cube' at an octant depth @d@. Both encoders are views of this.
data GifObject = GifObject
  { goDepth  :: !Int   -- ^ octant depth @d@ (@8^d@ voxels).
  , goPixels :: !Cube  -- ^ the voxel cube — the object itself.
  } deriving (Eq, Show)

-- | A GIF object is well-formed when its pixel cube is well-formed at its depth.
validGifObject :: GifObject -> Bool
validGifObject (GifObject d c) = validCube d c

-- | The EXACT palettization: the palette is the distinct colours (first-occurrence order),
-- the index map points each voxel at its colour's slot. Unbounded budget, so it is always
-- lossless — @buildPixels . palettizeExact == id@. (The lossy fixed-budget palettization is
-- "SixFour.Spec.CrossEncoderDistance".)
palettizeExact :: Int -> Cube -> Construction
palettizeExact d (Cube cl ca cb) =
  let cols    = zip3 cl ca cb
      pal     = nub cols
      idxOf c = maybe 0 id (elemIndex c pal)
  in Construction d pal (map idxOf cols)

-- | Encoder A view of the object: its construction recipe (palette + index).
viewA :: GifObject -> Construction
viewA (GifObject d c) = palettizeExact d c

-- | Encoder B view of the object: its perceptual @(L,a,b,x,y,t)@ point cloud.
viewB :: GifObject -> [P6]
viewB (GifObject d c) = perceptualEmbed d c

-- | Decode Encoder A: execute the build instructions back to pixels.
decodeA :: Construction -> Cube
decodeA = buildPixels

-- | Decode Encoder B: recover the pixels from the point cloud — drop position, keep the
-- colour channels in their Morton order.
decodeB :: [P6] -> Cube
decodeB pts = Cube [ p6L p | p <- pts ] [ p6A p | p <- pts ] [ p6B p | p <- pts ]

-- ============================================================================
-- Laws (predicates; QuickCheck'd in Properties.GifDualView)
-- ============================================================================

-- | KEYSTONE: the two encoders are two views of the SAME GIF — both decode to the same
-- pixels. @decodeA (viewA g)@ (build the recipe) and @decodeB (viewB g)@ (read the cloud)
-- each equal the object's pixels. This is the literal "two encoders, one object" theorem the
-- whole dual-encoder H-JEPA rests on. Teeth: 'viewA' palettizes through a real @nub@ (not the
-- identity), and 'decodeB' really discards position, so neither side is a trivial copy.
lawSameObjectBothViews :: GifObject -> Bool
lawSameObjectBothViews g
  | not (validGifObject g) = True
  | otherwise =
      let px = goPixels g
      in decodeA (viewA g) == px && decodeB (viewB g) == px

-- | Encoder B is a LOSSLESS SECTION: @decodeB . viewB == id@ on the object's pixels — the
-- perceptual cloud loses nothing, position is the only thing dropped on decode and it is
-- recoverable from Morton order. Teeth: a corrupted decode that read the @a@ channel where
-- @L@ belongs collapses a cube whose channels differ, so the round-trip is not vacuous.
lawSectionEmbedsLossless :: GifObject -> Bool
lawSectionEmbedsLossless g
  | not (validGifObject g) = True
  | otherwise =
      let px@(Cube cl ca _) = goPixels g
          corrupt pts       = Cube [ p6A p | p <- pts ] [ p6L p | p <- pts ] [ p6B p | p <- pts ]
      in decodeB (viewB g) == px
         && (cl == ca || corrupt (viewB g) /= px)   -- teeth: only vacuous when L==a anyway

-- | 'palettizeExact' is a SECTION of @buildPixels@ (a right inverse): @decodeA . viewA == id@
-- for EVERY object. The construction recipe — distinct colours as a palette, each voxel
-- pointing at its colour — rebuilds the GIF exactly. This is the retraction half of the
-- section/retraction pair, the unbounded-budget (lossless) end of the spectrum
-- "SixFour.Spec.CrossEncoderDistance" measures the budget-limited gap of.
lawRetractionRoundTrip :: GifObject -> Bool
lawRetractionRoundTrip g
  | not (validGifObject g) = True
  | otherwise              = decodeA (viewA g) == goPixels g

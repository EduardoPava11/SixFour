-- COMPARTMENT: SWIFT-COREAI | tag:DisplaySide
{- |
Module      : SixFour.Spec.ScaleSurface
Description : The grid "exception" for the Tri-Scale Bench — a super-res 256³ surface renders into the SAME on-screen footprint as the 64³, decoupling DISPLAY FOOTPRINT (grid cells) from CONTENT RESOLUTION (pixels). So the 256³ cannot overflow the cell grid; its extra resolution is density, not size.

"SixFour.Spec.MovableLayout" measures a widget's footprint in CELLS: @cwFootprint Field64 ==
(previewCells, previewCells)@ = a @64×64@-cell, 256-pt slot. A literal @256³@ super-res surface, if
its footprint scaled with its pixel resolution, would want @256×256@ cells — 4× the footprint — and
overflow the grid (the owner's "too large for the grid"). The fix is NOT a bigger grid slot and NOT a
4th 'ColorIdentity' (which would re-pin the move-golden): it is to DECOUPLE the two axes. Every scale
rung (@16³@\/@64³@\/@256³@) renders into ONE shared DISPLAY footprint — the @64³@'s — and the rung's
pixel resolution rides as DENSITY inside that fixed footprint.

  * 'rungResolution' — the linear pixel resolution of a rung (@16@\/@64@\/@256@) — what DIFFERS.
  * 'rungDisplayCells' — the on-screen footprint in cells — UNIFORM (= @previewCells@) across rungs.
  * 'lawSuperResShareFootprintWith64' — the @256³@ surface occupies EXACTLY
    "SixFour.Spec.MovableLayout" @Field64@'s footprint, so it fits the grid the @64³@ already fits
    ("make the 256×256 the same size as the 64×64").
  * 'lawFootprintIndependentOfResolution' — the resolutions genuinely differ (@16 ≠ 256@) yet the
    footprints are equal: the grid "exception" stated as a theorem (footprint ⊥ resolution).
  * 'lawSuperResIsDensityNotSize' — the @256³@ packs 4× the @64³@'s linear pixels into the same
    footprint, so the gain is DENSITY (Retina sharpness), not screen area.

Additive: composes "SixFour.Spec.Lattice" (@previewCells@) and "SixFour.Spec.MovableLayout"
(@Field64@\/@cwFootprint@) — both already DisplaySide. Re-pins NOTHING: the 'ColorIdentity' alphabet,
the move operator, and the move-golden are untouched. GHC-boot-only. Laws QuickCheck'd in
"Properties.ScaleSurface".
-}
module SixFour.Spec.ScaleSurface
  ( ScaleRung(..)
  , allRungs
  , rungResolution
  , rungDisplayCells
    -- * Laws (QuickCheck'd in @Properties.ScaleSurface@)
  , lawSuperResShareFootprintWith64
  , lawFootprintIndependentOfResolution
  , lawSuperResIsDensityNotSize
  ) where

import SixFour.Spec.Lattice       (previewCells)
import SixFour.Spec.MovableLayout (ColorIdentity(Field64), cwFootprint)

-- | The three scale rungs of the spine the Tri-Scale Bench shows at once.
data ScaleRung = Analysis16 | Pivot64 | Synthesis256
  deriving (Eq, Ord, Enum, Bounded, Show)

-- | All rungs, @[minBound .. maxBound]@.
allRungs :: [ScaleRung]
allRungs = [minBound .. maxBound]

-- | The CONTENT resolution (linear pixels) of a rung — what genuinely differs across the spine.
rungResolution :: ScaleRung -> Int
rungResolution Analysis16   = 16
rungResolution Pivot64      = 64
rungResolution Synthesis256 = 256

-- | The on-screen DISPLAY footprint in grid cells — UNIFORM across every rung (= 'previewCells', the
-- @64³@'s footprint). THIS is the grid "exception": resolution does NOT scale the footprint, so a
-- rung's pixels ride as density inside one fixed on-screen size and the @256³@ never overflows the grid.
rungDisplayCells :: ScaleRung -> Int
rungDisplayCells _ = previewCells

-- ============================================================================
-- Laws (predicates; QuickCheck'd in Properties.ScaleSurface)
-- ============================================================================

-- | The @256³@ super-res surface occupies EXACTLY "SixFour.Spec.MovableLayout" @Field64@'s cell
-- footprint — "the 256×256 is the same size as the 64×64". So it fits the grid the @64³@ already fits,
-- with no new slot and no change to the move algebra. Teeth: a footprint that scaled with resolution
-- (256 cells) would not equal @Field64@'s @(previewCells, previewCells)@.
lawSuperResShareFootprintWith64 :: Bool
lawSuperResShareFootprintWith64 =
     rungDisplayCells Synthesis256 == rungDisplayCells Pivot64
  && (rungDisplayCells Synthesis256, rungDisplayCells Synthesis256) == cwFootprint Field64

-- | THE GRID EXCEPTION as a theorem: the rung resolutions genuinely DIFFER (@16 ≠ 256@) while their
-- display footprints are EQUAL — display footprint is independent of content resolution. Teeth: a
-- footprint keyed off resolution would make these two differ in lockstep.
lawFootprintIndependentOfResolution :: Bool
lawFootprintIndependentOfResolution =
     rungResolution Analysis16 /= rungResolution Synthesis256        -- resolutions differ (16 vs 256)
  && rungDisplayCells Analysis16 == rungDisplayCells Synthesis256     -- ...yet footprints are equal

-- | The @256³@'s win is DENSITY, not size: 4× the @64³@'s linear pixels (@256 == 4·64@) packed into
-- the SAME footprint. Teeth: were the footprint 4× too (256 cells), the density would be 1× and the
-- grid would overflow — exactly the failure this contract forbids.
lawSuperResIsDensityNotSize :: Bool
lawSuperResIsDensityNotSize =
     rungResolution Synthesis256 == 4 * rungResolution Pivot64
  && rungDisplayCells Synthesis256 == rungDisplayCells Pivot64

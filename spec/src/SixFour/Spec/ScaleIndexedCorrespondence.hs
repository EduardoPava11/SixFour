{- |
Module      : SixFour.Spec.ScaleIndexedCorrespondence
Description : THE H-JEPA ANSWER — the correspondence between the two encoders is not one map but a HIERARCHY indexed by the scale spine ("SixFour.Spec.HJepaLevels"): EXACT at the Analysis 16³ tier, LOSSY at the 64³ Pivot, INVENTED at the Synthesis 256³ tier. "There is a hierarchy here."

The user's framing — the construction encoder A and the perceptual encoder B do not relate
by a single isomorphism, they relate DIFFERENTLY at each level of abstraction. This module
makes that a theorem by attaching a 'CorrespondenceKind' to each "SixFour.Spec.HJepaLevels"
'ScaleLevel':

  * __Analysis (16³)__ — 'Exact'. A frame has @16² = 256@ cells = a palette, so the per-frame
    palette is an IDENTITY, not a compression: the two encoders coincide
    ("SixFour.Spec.CoarseIsPalette" @lawCoarsePaletteComparesToPerFrame@). Distance zero.
  * __Pivot (64³)__ — 'Lossy'. A frame has @64² = 4096@ pixels but the palette has only 256
    slots, so Encoder A must merge colours; the gap is "SixFour.Spec.CrossEncoderDistance"
    @constructionDistortion@ @> 0@.
  * __Synthesis (256³)__ — 'Invented'. Beyond capture neither encoder has the data; the
    detail is invented through the shared predictor
    ("SixFour.Spec.SelfSimilarReconstruct" @lawBeyondCaptureInvented@).

  * 'lawCorrespondenceHierarchyMatchesScaleSpine' — KEYSTONE: the three correspondence kinds
    are DISTINCT and assigned exactly along the scale spine (delegates
    "SixFour.Spec.HJepaLevels" @lawScaleIsTheSpine@). This is the typed form of "H-JEPA,
    there is a hierarchy here": a flat single-map reading fails because the kinds differ.

Additive: reuses "SixFour.Spec.HJepaLevels" @ScaleLevel@, "SixFour.Spec.CoarseIsPalette",
"SixFour.Spec.CrossEncoderDistance", "SixFour.Spec.GifDualView",
"SixFour.Spec.SelfSimilarReconstruct". GHC-boot-only. Laws QuickCheck'd in
"Properties.ScaleIndexedCorrespondence".
-}
-- COMPARTMENT: MLX-MODEL | tag:MacTag
module SixFour.Spec.ScaleIndexedCorrespondence
  ( -- * The scale-indexed correspondence
    CorrespondenceKind(..)
  , correspondenceAt
    -- * The latent-midpoint correspondence (a SEPARATE kind, off the spine enum)
  , MidpointCorrespondence(..)
  , correspondenceAtMidpoint
    -- * Laws (QuickCheck'd in @Properties.ScaleIndexedCorrespondence@)
  , lawAnalysisIsExact
  , lawPivotIsLossy
  , lawSynthesisIsInvented
  , lawCorrespondenceHierarchyMatchesScaleSpine
  , lawMidpointCorrespondenceNeverSurfaces
  ) where

import SixFour.Spec.HJepaLevels          (ScaleLevel(..), lawScaleIsTheSpine)
import SixFour.Spec.SameObjectInvariance (Cube(..))
import SixFour.Spec.GifDualView          (GifObject(..))
import SixFour.Spec.CrossEncoderDistance (constructionDistortion, isPalettizable)
import SixFour.Spec.RungPivot            (RungDir(..), lawIntermediateNeverSurfaces)
import qualified SixFour.Spec.CoarseIsPalette       as CP
import qualified SixFour.Spec.SelfSimilarReconstruct as SSR

-- | How the two encoders correspond at a given scale: they coincide ('Exact'), diverge by a
-- measurable palettization gap ('Lossy'), or have no shared data and must invent ('Invented').
data CorrespondenceKind = Exact | Lossy | Invented
  deriving (Eq, Show, Enum, Bounded)

-- | The correspondence kind at each scale-spine level — the hierarchy itself.
correspondenceAt :: ScaleLevel -> CorrespondenceKind
correspondenceAt Analysis  = Exact
correspondenceAt Pivot     = Lossy
correspondenceAt Synthesis = Invented

-- | The correspondence kind at a never-surfaced LATENT MIDPOINT (the 32³ DOWN / 128³ UP
-- intermediates). It is a SEPARATE kind, deliberately NOT a constructor of 'CorrespondenceKind'
-- and NOT in its @Bounded@ enumeration, so the spine keystone literal @[Exact,Lossy,Invented]@
-- stays intact. A midpoint never surfaces to a committed byte, so its "correspondence" is
-- always the latent-only kind.
data MidpointCorrespondence = LatentMidpoint
  deriving (Eq, Show, Enum, Bounded)

-- | Both rung midpoints (DOWN 32³, UP 128³) correspond only as a never-surfaced latent.
correspondenceAtMidpoint :: RungDir -> MidpointCorrespondence
correspondenceAtMidpoint _ = LatentMidpoint

-- ============================================================================
-- Laws (predicates; QuickCheck'd in Properties.ScaleIndexedCorrespondence)
-- ============================================================================

-- | At the Analysis 16³ tier the two encoders are EXACT: the per-frame palette equals the
-- perceptual colours (delegates "SixFour.Spec.CoarseIsPalette"
-- @lawCoarsePaletteComparesToPerFrame@ on a coarse witness), because @16²=256@ makes the
-- palette an identity. Teeth: the witness is a real depth-4 cube, so the coincidence is the
-- structural one, not a label.
lawAnalysisIsExact :: Bool
lawAnalysisIsExact =
     correspondenceAt Analysis == Exact
  && CP.lawCoarsePaletteComparesToPerFrame coarseWitness
  where
    coarseWitness = Cube [0 .. 4095] [0 .. 4095] [0 .. 4095]   -- 8^4 voxels per channel

-- | At the 64³ Pivot the correspondence is LOSSY: a frame has more pixels than the palette
-- has slots (@framePixels 64 = 4096 > 256 = paletteCells@), so Encoder A must merge colours
-- and "SixFour.Spec.CrossEncoderDistance" @constructionDistortion@ is positive on an
-- over-budget object. Teeth: an object that exceeds budget is NOT palettizable and its
-- distortion is strictly @> 0@ (a real divergence, witnessed concretely).
lawPivotIsLossy :: Bool
lawPivotIsLossy =
     correspondenceAt Pivot == Lossy
  && CP.framePixels 64 > CP.paletteCells                 -- WHY the pivot frame cannot be exact
  && not (isPalettizable budget overBudget)              -- the witness exceeds its budget
  && constructionDistortion budget overBudget > 0        -- so the two semantics diverge
  where
    budget     = 2
    -- 8 voxels, 3 distinct colours > budget 2 ⇒ a merge is forced (the pivot regime in miniature)
    overBudget = GifObject 1 (Cube [0,1,2,0,1,2,0,1]
                                   [0,0,0,0,0,0,0,0]
                                   [0,0,0,0,0,0,0,0])

-- | At the Synthesis 256³ tier the detail is INVENTED: beyond capture it is not derivable
-- from the data, so two different latent tails give different reconstructions (delegates
-- "SixFour.Spec.SelfSimilarReconstruct" @lawBeyondCaptureInvented@ on an 8-child witness).
lawSynthesisIsInvented :: Bool
lawSynthesisIsInvented =
     correspondenceAt Synthesis == Invented
  && SSR.lawBeyondCaptureInvented [0, 1, 2, 3, 4, 5, 6, 7]

-- | KEYSTONE: the correspondence is a genuine HIERARCHY that matches the H-JEPA scale spine.
-- The three kinds are DISTINCT (a flat single-map reading would collapse them) and assigned
-- exactly along @[Analysis, Pivot, Synthesis]@; the scale axis is the spine (delegates
-- "SixFour.Spec.HJepaLevels" @lawScaleIsTheSpine@). This is "H-JEPA, there is a hierarchy
-- here" as a theorem. Teeth: making any two kinds equal, or mis-ordering them, fails.
lawCorrespondenceHierarchyMatchesScaleSpine :: Bool
lawCorrespondenceHierarchyMatchesScaleSpine =
     lawScaleIsTheSpine
  && map correspondenceAt [Analysis, Pivot, Synthesis] == [Exact, Lossy, Invented]
  && Exact /= Lossy && Lossy /= Invented && Exact /= Invented

-- | The latent-midpoint correspondence is LATENT-ONLY and OFF the spine enumeration. Both
-- rungs' midpoints (DOWN 32³, UP 128³) map to 'LatentMidpoint' (never surfaced, delegates
-- "SixFour.Spec.RungPivot" @lawIntermediateNeverSurfaces@), AND the scale-spine keystone
-- enumeration is preserved EXACTLY: @[minBound .. maxBound] :: [CorrespondenceKind]@ is still
-- @[Exact, Lossy, Invented]@. Teeth: had 'LatentMidpoint' been added to 'CorrespondenceKind'
-- (instead of its own type), this literal would change and
-- 'lawCorrespondenceHierarchyMatchesScaleSpine' would break — so the separation is load-bearing.
lawMidpointCorrespondenceNeverSurfaces :: Bool
lawMidpointCorrespondenceNeverSurfaces =
     correspondenceAtMidpoint Down == LatentMidpoint
  && correspondenceAtMidpoint Up   == LatentMidpoint
  && lawIntermediateNeverSurfaces
  && [minBound .. maxBound] == [Exact, Lossy, Invented]   -- the spine enum is UNTOUCHED

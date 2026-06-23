{- |
Module      : SixFour.Spec.MinimalInstructionSet
Description : The MINIMUM decode-instruction set for the "16³ + data" object, in BOTH encoder forms — A: 16 ordered palettes (no index map); B: the L carrier over (x,y,t) (chroma demoted to data) — and the ASYMMETRIC duality between them. The umbrella that ties "SixFour.Spec.ConstructionEncoder", "SixFour.Spec.CoarseIsPalette", "SixFour.Spec.PerceptualEncoder" and "SixFour.Spec.DualEncoderJepa" into the owner's minimal-instruction question.

"16³ + data" is a two-part code: the coarse 16³ anchor plus the reversible-lift held detail
that reconstructs the finer cube (exact within capture, "SixFour.Spec.SuccessiveRefinement").
This module states, per encoder, the SMALLEST sufficient instruction set, and the honest
asymmetry between them.

  * __A-form ("16 palettes, no index map").__ At 16³ a t-frame is @16·16 = 256@ cells = one
    palette; under the canonical octant-Morton cell order a complete-256 frame has the
    IDENTITY index (droppable), so 16 ordered palettes reconstruct the cube
    ('lawSixteenPalettesSuffice', delegating "SixFour.Spec.CoarseIsPalette"
    @decodeAPalettesOnly@/@lawSixteenPalettesReconstructCube@, with the
    "SixFour.Spec.ConstructionEncoder" @identityIndex@ core). A keeps full @(L,a,b)@ colour and
    drops the explicit index.
  * __B-form ("(L,x,y,t) + data").__ The L carrier over the explicit Morton lattice; chroma
    @(a,b)@ is the "+data" residual. B is a LOSSY skeleton: @L → (a,b)@ is ill-posed, so chroma
    is predicted, never an exact inverse ('lawBSkeletonIsLossy', a closed two-cube witness).
    The @a,b@ axes are SEARCH (droppable), @L,t@ are carriers ('lawChromaIsSearchResidual',
    delegating "SixFour.Spec.Dim6").
  * __The duality is ASYMMETRIC.__ A and B are dual minimal projections of the SAME object, but
    @A → B@ (positions) is byte-exact while @B → A@ (chroma) is Invented/predicted only
    ('lawDualMinimalProjections', riding "SixFour.Spec.DualEncoderJepa"
    @lawCrossEncoderContextStrictlyHelps@ for the generic synergy and proving the chroma/position
    asymmetry CONTENT here).

Additive: all references are read-only delegations; touches no owned module. GHC-boot-only.
Laws QuickCheck'd in "Properties.MinimalInstructionSet".
-}
-- COMPARTMENT: MLX-MODEL | tag:MacTag
module SixFour.Spec.MinimalInstructionSet
  ( -- * The B-form skeleton extractor
    bSkeleton
    -- * Laws (QuickCheck'd in @Properties.MinimalInstructionSet@)
  , lawSixteenPalettesSuffice
  , lawBSkeletonIsLossy
  , lawChromaIsSearchResidual
  , lawDualMinimalProjections
  ) where

import SixFour.Spec.Dim6                 (Dim6(..), isUniversal, isSearch)
import SixFour.Spec.SameObjectInvariance (Cube(..))
import SixFour.Spec.PerceptualEncoder    (mortonToXYT)
import SixFour.Spec.GifDualView          (GifObject(..), viewA, decodeA)
import qualified SixFour.Spec.CoarseIsPalette as CP
import qualified SixFour.Spec.DualEncoderJepa as DEJ

-- | The B-form minimal skeleton of a cube at depth @d@: the L carrier paired with each voxel's
-- @(x,y,t)@ Morton position. Chroma @(a,b)@ is deliberately DROPPED — it is the "+data" residual.
-- Two cubes that differ only in @(a,b)@ share a skeleton (the witness 'lawBSkeletonIsLossy' uses).
bSkeleton :: Int -> Cube -> [(Int, Int, Int, Int)]
bSkeleton d (Cube cl _ _) =
  [ (l, x, y, t) | (v, l) <- zip [0 ..] cl, let (x, y, t) = mortonToXYT d v ]

-- ============================================================================
-- Laws (predicates; QuickCheck'd in Properties.MinimalInstructionSet)
-- ============================================================================

-- | A-FORM sufficiency: 16 ordered palettes reconstruct the 16³ cube with NO index map.
-- Delegates "SixFour.Spec.CoarseIsPalette" @lawSixteenPalettesReconstructCube@ on a concrete
-- depth-4 witness (4096 distinct colours), binding the real @decodeAPalettesOnly@ ∘
-- @coarseToPaletteStack@ round-trip. Teeth live in the delegated law (a lossy reshape fails it).
lawSixteenPalettesSuffice :: Bool
lawSixteenPalettesSuffice =
  CP.lawSixteenPalettesReconstructCube (Cube [0 .. 4095] [0 .. 4095] [0 .. 4095])

-- | B-FORM is LOSSY (the deliberately NEGATIVE keystone): a closed two-cube witness where the
-- two cubes share the same @(L,x,y,t)@ skeleton but differ in colour (only @b@ changes). So
-- chroma recovery from the B-skeleton is Invented/predicted, NEVER an exact inverse. Pinning
-- this prevents anyone later from wiring @B → chroma@ as a Held/exact decode. Closed witness
-- (in the style of "SixFour.Spec.ConstructionEncoder" @lawBuildRespectsIndex@) so it cannot
-- pass vacuously.
lawBSkeletonIsLossy :: Bool
lawBSkeletonIsLossy =
  let c1 = Cube (replicate 8 5) (replicate 8 0) (replicate 8 0)
      c2 = Cube (replicate 8 5) (replicate 8 0) (1 : replicate 7 0)   -- differ only in b
  in bSkeleton 1 c1 == bSkeleton 1 c2 && c1 /= c2

-- | The @(a,b)@ chroma the B-skeleton drops are SEARCH axes; the @(L,t)@ it keeps are carriers;
-- @(x,y)@ are also SEARCH but kept as the free Morton address (delegates "SixFour.Spec.Dim6"
-- @isSearch@\/@isUniversal@). Teeth: two cubes differing ONLY in @a@ share the @(L,x,y,t)@
-- skeleton, so chroma is genuinely outside the skeleton, not laundered in.
lawChromaIsSearchResidual :: Bool
lawChromaIsSearchResidual =
     isSearch DimA && isSearch DimB
  && isUniversal DimL && isUniversal DimT
  && isSearch DimX && isSearch DimY
  && bSkeleton 1 cA == bSkeleton 1 cB && cA /= cB
  where
    cA = Cube (replicate 8 5) (replicate 8 0) (replicate 8 0)
    cB = Cube (replicate 8 5) (2 : replicate 7 0) (replicate 8 0)     -- differ only in a

-- | The ASYMMETRIC duality: A and B are dual minimal projections of the same object, equivalent
-- only through the cross-encoder. (1) The generic synergy that two views beat one is delegated
-- to "SixFour.Spec.DualEncoderJepa" @lawCrossEncoderContextStrictlyHelps@. (2) The CONTENT,
-- proven here: A alone reconstructs (it kept the colour — @decodeA . viewA == id@ on the
-- witness), while B alone is lossy (@lawBSkeletonIsLossy@). So @A → B@ is exact and @B → A@ is
-- Invented: the asymmetry is the law's content, not inherited from the keystone.
lawDualMinimalProjections :: Bool
lawDualMinimalProjections =
     DEJ.lawCrossEncoderContextStrictlyHelps          -- (1) generic synergy (two views beat one)
  && decodeA (viewA gWit) == goPixels gWit            -- (2a) A reconstructs (kept colour, exact)
  && lawBSkeletonIsLossy                              -- (2b) B is lossy (chroma Invented only)
  where
    gWit = GifObject 1 (Cube [0 .. 7] [10 .. 17] [20 .. 27])   -- 8 distinct-colour voxels

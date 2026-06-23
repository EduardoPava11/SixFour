{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE FlexibleInstances   #-}
{-# LANGUAGE KindSignatures      #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}
{-# LANGUAGE TypeFamilies        #-}

{- |
Module      : SixFour.Spec.AxisNet
Description : The grey-anchor / dynamic-range algebra — L is the σ-fixed centre, A,B deviate from it.

The look-NN's MVP nucleus is the **L-NN**: it turns a colour capture into a global
GRAYSCALE palette. This module formalises the principle behind the L→A→B decomposition:

  * **Luminosity L sets the dynamic range and IS the grey/middle point.** The grey
    axis @a = b = 0@ is the σ-FIXED CENTRE of OKLab under @σ(L,a,b) = (L,-a,-b)@
    ('SixFour.Spec.PairTree.sigmaReflect'): L is σ-invariant.
  * **Chroma a,b are signed DEVIATIONS from grey.** They are σ-antisymmetric — σ
    negates them. The A-net and B-net produce these deviations around the L grey backbone.

So an OKLab colour decomposes as (grey lightness) + (σ-antisymmetric chroma deviation),
and each 'ColorAxis' isolates one component. 'AxisNet' is the typed projection of a palette
onto one axis: @AxisL@ is σ-fixed by construction (grayscale = the σ-symmetric image),
@AxisA@/@AxisB@ are σ-equivariant chroma deviations. This reuses the exact structure already
proven for 'SixFour.Spec.Pipeline.Quad4ReconAchroma' (achromatic root σ-fixed) and the
22/21/21 'SixFour.Spec.Tensor.sigma64Mask' grouping.

Laws live in @Properties.AxisNet@.
-}
-- COMPARTMENT: MLX-MODEL | tag:MacTag
module SixFour.Spec.AxisNet
  ( -- * The colour axes
    ColorAxis(..)
  , KnownAxis(..)
  , axisIsAchromatic
  , axisSigmaSign
    -- * The grey point + per-axis projection
  , greyPoint
  , greyLightness
  , projectAxis
  , injectAxis
    -- * Dynamic range (L extent)
  , DynamicRange(..)
  , dynamicRangeOf
  , greyOf
  , inDynamicRange
    -- * Achromatic decomposition (grey + chroma deviation)
  , AchromaticDeviation(..)
  , toDeviation
  , fromDeviation
  , sigmaDeviation
    -- * The axis-projection stage (σ-classified)
  , AxisNet
  ) where

import SixFour.Spec.Color    (OKLab(..))
import SixFour.Spec.PairTree (sigmaReflect)
import SixFour.Spec.Pipeline (Stage(..), SigmaEquivariant(..), SigmaSymmetricRange)

-- =============================================================================
-- The colour axes
-- =============================================================================

-- | The three OKLab axes. @AxisL@ is the achromatic (σ-fixed) grey backbone;
-- @AxisA@ (red-green) and @AxisB@ (blue-yellow) are the σ-antisymmetric chroma
-- deviations from grey. DataKinds-promoted so 'AxisNet' can carry it as a phantom.
data ColorAxis = AxisL | AxisA | AxisB
  deriving (Eq, Show, Enum, Bounded)

-- | Reify a promoted 'ColorAxis' to its value.
class KnownAxis (a :: ColorAxis) where
  axisVal :: ColorAxis

instance KnownAxis 'AxisL where axisVal = AxisL
instance KnownAxis 'AxisA where axisVal = AxisA
instance KnownAxis 'AxisB where axisVal = AxisB

-- | Is this the achromatic (σ-fixed, grey) axis? Only @AxisL@.
axisIsAchromatic :: ColorAxis -> Bool
axisIsAchromatic AxisL = True
axisIsAchromatic _     = False

-- | The σ eigenvalue of the axis: @+1@ for the σ-fixed L, @-1@ for the
-- σ-negated chroma axes. (@σ(L,a,b) = (L,-a,-b)@.)
axisSigmaSign :: ColorAxis -> Double
axisSigmaSign AxisL = 1
axisSigmaSign _     = -1

-- =============================================================================
-- Grey point + per-axis projection
-- =============================================================================

-- | The L lightness of the grey middle point. The OKLab L range is @[0,1]@, so
-- the neutral centre is @0.5@. (A capture-adaptive grey — the midpoint of the
-- actual L dynamic range — is 'greyOf'; this is the fixed fallback.)
greyLightness :: Double
greyLightness = 0.5

-- | The σ-fixed grey centre @(0.5, 0, 0)@: zero chroma, mid lightness.
greyPoint :: OKLab
greyPoint = OKLab greyLightness 0 0

-- | Project an OKLab colour onto a single axis, placing that component on a grey
-- background. @AxisL@ keeps the lightness with zero chroma (the GRAYSCALE
-- projection); @AxisA@/@AxisB@ keep one chroma deviation at the grey lightness.
projectAxis :: ColorAxis -> OKLab -> OKLab
projectAxis AxisL (OKLab l _ _) = OKLab l 0 0
projectAxis AxisA (OKLab _ a _) = OKLab greyLightness a 0
projectAxis AxisB (OKLab _ _ b) = OKLab greyLightness 0 b

-- | Place a single axis value on the grey point — the inverse of reading one
-- component back off 'projectAxis'.
injectAxis :: ColorAxis -> Double -> OKLab
injectAxis AxisL v = OKLab v 0 0
injectAxis AxisA v = OKLab greyLightness v 0
injectAxis AxisB v = OKLab greyLightness 0 v

-- =============================================================================
-- Dynamic range (the L extent the grey backbone spans)
-- =============================================================================

-- | The lightness dynamic range @[drMin, drMax]@ a palette spans — L IS the
-- dynamic range, so this is computed over the L channel alone.
data DynamicRange = DynamicRange
  { drMin :: !Double
  , drMax :: !Double
  } deriving (Eq, Show)

-- | The L extent of a palette. Empty palette ⇒ the degenerate point at the grey
-- lightness (a safe fallback that contains the grey point).
dynamicRangeOf :: [OKLab] -> DynamicRange
dynamicRangeOf [] = DynamicRange greyLightness greyLightness
dynamicRangeOf ps =
  let ls = [ l | OKLab l _ _ <- ps ]
  in DynamicRange (minimum ls) (maximum ls)

-- | The grey point OF a dynamic range: its midpoint (the capture-adaptive grey).
greyOf :: DynamicRange -> Double
greyOf (DynamicRange lo hi) = (lo + hi) / 2

-- | Does a lightness lie within the range?
inDynamicRange :: DynamicRange -> Double -> Bool
inDynamicRange (DynamicRange lo hi) l = l >= lo && l <= hi

-- =============================================================================
-- Achromatic decomposition: grey lightness + σ-antisymmetric chroma deviation
-- =============================================================================

-- | An OKLab colour split into its σ-fixed grey lightness ('adGrey') and its
-- σ-antisymmetric chroma deviation ('adA', 'adB') from grey.
data AchromaticDeviation = AchromaticDeviation
  { adGrey :: !Double
  , adA    :: !Double
  , adB    :: !Double
  } deriving (Eq, Show)

-- | Decompose. Trivially an isomorphism with OKLab — the point is the σ split.
toDeviation :: OKLab -> AchromaticDeviation
toDeviation (OKLab l a b) = AchromaticDeviation l a b

-- | Recompose (inverse of 'toDeviation').
fromDeviation :: AchromaticDeviation -> OKLab
fromDeviation (AchromaticDeviation g a b) = OKLab g a b

-- | σ on the decomposition: the grey is FIXED, the chroma deviation is NEGATED.
-- This is exactly 'sigmaReflect' lifted through the iso (the @Properties.AxisNet@
-- cross-check @toDeviation . sigmaReflect == sigmaDeviation . toDeviation@).
sigmaDeviation :: AchromaticDeviation -> AchromaticDeviation
sigmaDeviation (AchromaticDeviation g a b) = AchromaticDeviation g (negate a) (negate b)

-- =============================================================================
-- The axis-projection stage (composes AFTER the look-NN palette reconstruction)
-- =============================================================================

-- | Typed projection of a reconstructed palette onto one 'ColorAxis'. Phantom in
-- the axis. Composes after the look-NN's @… :> SigmaPairRecon@ (whose output is a
-- @[OKLab]@ palette) as @AxisNet axis :> …@. @AxisL@ is σ-fixed BY CONSTRUCTION
-- (grayscale output = the σ-symmetric image); @AxisA@/@AxisB@ are σ-equivariant.
data AxisNet (axis :: ColorAxis)

instance KnownAxis axis => Stage (AxisNet axis) where
  type In  (AxisNet axis) = [OKLab]
  type Out (AxisNet axis) = [OKLab]
  step = map (projectAxis (axisVal @axis))

-- @AxisL@: σ-equivariant AND σ-symmetric range (output chroma is 0 ⇒ σ-fixed).
instance SigmaEquivariant (AxisNet 'AxisL) where
  sigmaIn  = map sigmaReflect
  sigmaOut = map sigmaReflect    -- ≡ id on the grayscale image (proof: Properties.AxisNet)

instance SigmaSymmetricRange (AxisNet 'AxisL)

-- @AxisA@/@AxisB@: σ-equivariant (chroma deviations negate under σ), NOT σ-symmetric.
instance SigmaEquivariant (AxisNet 'AxisA) where
  sigmaIn  = map sigmaReflect
  sigmaOut = map sigmaReflect

instance SigmaEquivariant (AxisNet 'AxisB) where
  sigmaIn  = map sigmaReflect
  sigmaOut = map sigmaReflect

{- |
Module      : SixFour.Spec.RelationalResidual
Description : The bit-exact 6D-point SUBSTRATE the relational memory rides on — the @P6@ point @(L,a,b,x,y,t)@, the raw @nudge@, and the @safeNudge@ DOMAIN GUARD (the @RC_OUT_OF_RANGE@ sibling). The I-JEPA MEMORY half (the @d6@ metric + the 14-int residual budget + the metric laws) split out to the MLX-MODEL "SixFour.Spec.RelationalMemory".

Destructive compartment pivot (STEP 4): this module was a STRADDLER (it mixed the Zig-floor
substrate with the I-JEPA position memory). The MEMORY half is now "SixFour.Spec.RelationalMemory"
(MLX-MODEL); what remains here is the cohesive ZIG-FLOOR substrate:

  * 'P6' — the comparable point @(L,a,b,x,y,t)@ in Q16 integer units (position lifted from the
    implicit Morton index into a real value so distance is computable across regions).
  * 'nudge' — move one axis by @delta@ (the @+/-1@ gesture).
  * 'safeNudge' — the DOMAIN-RESPECTING move: @Just@ iff every coordinate stays in @|v| <= B@,
    @Nothing@ otherwise, mirroring the shipped Zig @liftChecked@ / @RC_OUT_OF_RANGE@.

GHC-boot-only. Laws QuickCheck'd in "Properties.RelationalResidual".
-}
-- COMPARTMENT: ZIG-FLOOR | tag:DeviceTag
module SixFour.Spec.RelationalResidual
  ( -- * The comparable 6D point (the bit-exact substrate the relational memory rides on)
    P6(..)
  , nudge
  , p6Coords
  , axisVal
  , safeNudge
    -- * Laws (QuickCheck'd in @Properties.RelationalResidual@)
  , lawNudgeRespectsDomain
  ) where

import SixFour.Spec.Dim6 (Dim6(..))
import SixFour.Spec.SubstrateDomain (inDomain)

-- | The comparable point: @(L,a,b,x,y,t)@ in Q16 integer units. Colour @(L,a,b)@ is
-- stored today; position @(x,y,t)@ is lifted from the implicit Morton index into a real
-- value so distance is computable across regions.
data P6 = P6
  { p6L :: !Int, p6A :: !Int, p6B :: !Int
  , p6X :: !Int, p6Y :: !Int, p6T :: !Int
  } deriving (Eq, Show)

-- | The six coordinates in axis order (@L,a,b,x,y,t@).
coords :: P6 -> [Int]
coords (P6 l a b x y t) = [l, a, b, x, y, t]

-- | The six coordinates (exported view of 'coords').
p6Coords :: P6 -> [Int]
p6Coords = coords

-- | Read one axis's value off a point.
axisVal :: Dim6 -> P6 -> Int
axisVal DimL = p6L
axisVal DimA = p6A
axisVal DimB = p6B
axisVal DimX = p6X
axisVal DimY = p6Y
axisVal DimT = p6T

-- | Move a single axis by @delta@ (the @+/-1@ gesture; via @phi6@ a nudge on search
-- colour @a@ is the same step as on position @x@).
nudge :: Dim6 -> Int -> P6 -> P6
nudge DimL d p = p { p6L = p6L p + d }
nudge DimA d p = p { p6A = p6A p + d }
nudge DimB d p = p { p6B = p6B p + d }
nudge DimX d p = p { p6X = p6X p + d }
nudge DimY d p = p { p6Y = p6Y p + d }
nudge DimT d p = p { p6T = p6T p + d }

-- | A DOMAIN-RESPECTING move: @Just@ the nudged point iff every resulting coordinate stays
-- inside the substrate domain @|v| <= B@ ("SixFour.Spec.SubstrateDomain" 'inDomain'),
-- @Nothing@ otherwise — the @RC_OUT_OF_RANGE@ sibling. The raw 'nudge' adds silently past B
-- (a P6 the shipped Zig kernel REFUSES, @liftChecked@); committing callers must route through
-- 'safeNudge' so the spec cannot emit a point the substrate rejects.
safeNudge :: Dim6 -> Int -> P6 -> Maybe P6
safeNudge ax d p =
  let q = nudge ax d p
  in if all inDomain (coords q) then Just q else Nothing

-- ============================================================================
-- Laws (predicates; QuickCheck'd in Properties.RelationalResidual)
-- ============================================================================

-- | 'safeNudge' REFUSES exactly when the result would leave the substrate domain, matching
-- the shipped Zig @liftChecked@ / @RC_OUT_OF_RANGE@: @Just@ implies every coordinate is
-- in-domain; @Nothing@ implies the nudged axis value is out of domain. Teeth: the raw 'nudge'
-- (which adds silently past B) would return an out-of-domain point where this law demands
-- @Nothing@ — caught only when QuickCheck'd at the DOMAIN EDGE (genP6Edge), not the
-- 16384x-inside-B default generator.
lawNudgeRespectsDomain :: Dim6 -> Int -> P6 -> Bool
lawNudgeRespectsDomain ax d p =
  case safeNudge ax d p of
    Just q  -> all inDomain (coords q)
    Nothing -> not (inDomain (axisVal ax p + d))

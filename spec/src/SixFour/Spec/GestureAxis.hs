-- COMPARTMENT: SWIFT-COREAI | tag:DisplaySide
{- |
Module      : SixFour.Spec.GestureAxis
Description : The missing keystone ARROW of the L,a,b design language: a screen swipe is decoded to a Dim6 search axis + signed step and COMMITTED through the domain guard (safeNudge) — composing the angle-gated detent swipe and the substrate guard that no module wired together before.

The nudge dataflow had two organs that were never composed in one place: the angle-gated @(a,b)@
swipe ("SixFour.Spec.DetentNudge" 'stepDelta') and the substrate domain guard
("SixFour.Spec.RelationalResidual" 'safeNudge', the @RC_OUT_OF_RANGE@ sibling). The design language's
PUSH verb needs a single arrow "swipe ⇒ a domain-checked move on the perceptual point", or a gesture
could emit a @P6@ the shipped Zig kernel refuses. This module is that arrow:

  * 'gestureSafeNudge' — decode a swipe to its @(a,b)@ step and route it through 'safeNudge' axis by
    axis, so a committing gesture provably passes the domain guard FIRST (it can only touch the
    @{a,b}@ search axes, never the @{L,t}@ carrier).
  * 'lawGestureRoutesThroughGuard' — a committed gesture's point is always in-domain (the guard is
    honoured); a gesture cannot bypass 'safeNudge'.
  * 'lawGestureRefusesAtEdge' — at the @+a@ domain edge a @+1@ swipe REFUSES ('Nothing') — the teeth
    (a raw nudge would silently overflow @B = 2^29-1@).
  * 'lawGestureTargetsSearchAxes' — a swipe leaves the universal carrier @{L,t}@ fixed and moves only
    the search axes @{a,b}@ (the carrier\/search register split the design language teaches by feel).
  * 'lawGestureColourHasPositionTwin' — via @phi6@ the colour search axes pair to position
    (@a↔x, b↔y@): the design-language hook that a colour gesture is also a spatial gesture.
  * 'lawGestureReversibleInDomain' — a swipe then its 'flipSign' returns to the start (the ±1 inverse,
    lifted through the guard).

Additive: composes "SixFour.Spec.Dim6", "SixFour.Spec.DetentNudge",
"SixFour.Spec.RelationalResidual" and "SixFour.Spec.SubstrateDomain" (the @safeNudge@ + detent organs
already in this DisplaySide compartment, cf. "SixFour.Spec.TwoMoveOctave"). Re-pins nothing.
GHC-boot-only. Laws QuickCheck'd in "Properties.GestureAxis".
-}
module SixFour.Spec.GestureAxis
  ( gestureSafeNudge
  , gestureSearchAxes
    -- * Laws (QuickCheck'd in @Properties.GestureAxis@)
  , lawGestureRoutesThroughGuard
  , lawGestureRefusesAtEdge
  , lawGestureTargetsSearchAxes
  , lawGestureColourHasPositionTwin
  , lawGestureReversibleInDomain
  ) where

import SixFour.Spec.Dim6              (Dim6(..), phi6, isSearch, isUniversal)
import SixFour.Spec.RelationalResidual (P6(..), safeNudge, p6Coords)
import SixFour.Spec.DetentNudge       (AdmissibleStep, Sign(..), ABAxis(..), mkAdmissibleStep, stepDelta, flipSign)
import SixFour.Spec.SubstrateDomain   (inDomain, substrateBound)
import SixFour.Spec.ChromaRotation    (Detent(..))

-- | Decode an angle-gated swipe to its @(a,b)@ step and COMMIT it through the substrate domain guard,
-- one axis at a time: @a@ by @da@ then @b@ by @db@, each via 'safeNudge'. 'Just' the moved point iff
-- both stay in the substrate domain, 'Nothing' otherwise. It touches ONLY the @{a,b}@ search axes —
-- there is no path here to the @{L,t}@ carrier.
gestureSafeNudge :: AdmissibleStep -> P6 -> Maybe P6
gestureSafeNudge st p =
  let (da, db) = stepDelta st
  in safeNudge DimA da p >>= safeNudge DimB db

-- | The two search axes a swipe can move (never the universal carrier @{L,t}@).
gestureSearchAxes :: [Dim6]
gestureSearchAxes = [DimA, DimB]

-- ============================================================================
-- Laws (predicates; QuickCheck'd in Properties.GestureAxis)
-- ============================================================================

-- | A committing gesture is ALWAYS domain-checked: when 'gestureSafeNudge' commits, every coordinate
-- of the result is in the substrate domain — so the gesture cannot emit a @P6@ the Zig floor refuses.
-- The arrow routes through 'safeNudge' by construction; teeth come from 'lawGestureRefusesAtEdge'
-- (a raw, unguarded nudge would produce an out-of-domain point this law forbids).
lawGestureRoutesThroughGuard :: AdmissibleStep -> P6 -> Bool
lawGestureRoutesThroughGuard st p =
  case gestureSafeNudge st p of
    Just q  -> all inDomain (p6Coords q)
    Nothing -> True

-- | TEETH — at the @+a@ domain edge (@a = B@) a @+1@ swipe on @a@ REFUSES: 'gestureSafeNudge' returns
-- 'Nothing' rather than overflowing @B = 2^29-1@. This is the @RC_OUT_OF_RANGE@ guard firing through
-- the gesture arrow, the non-vacuous proof that the route really passes the guard. Closed witness.
lawGestureRefusesAtEdge :: Bool
lawGestureRefusesAtEdge =
  case mkAdmissibleStep C12 0 Plus AxisA of
    Nothing -> False                                  -- C12 at 0° must be admissible
    Just st ->
      let edge = P6 0 substrateBound 0 0 0 0          -- a sits at the +domain edge
      in stepDelta st == (1, 0)                        -- this swipe is +1 on a, 0 on b
         && gestureSafeNudge st edge == Nothing         -- ...so it refuses at the edge

-- | A swipe moves ONLY the search axes @{a,b}@: the universal carrier @L@ and @t@ are left fixed by a
-- commit, and @a,b@ are search axes. This is the carrier\/search register split the design language
-- renders as two gesture feels (heavy balance vs light detent). Teeth: a decode that touched @L@ or
-- @t@ would change @p6L@\/@p6T@.
lawGestureTargetsSearchAxes :: AdmissibleStep -> P6 -> Bool
lawGestureTargetsSearchAxes st p =
  case gestureSafeNudge st p of
    Nothing -> True
    Just q  -> p6L q == p6L p && p6T q == p6T p
               && isSearch DimA && isSearch DimB

-- | The colour search axes have POSITION twins under @phi6@ (@a↔x, b↔y@), and both members of each
-- pair are search axes while the carrier @{L,t}@ stays the carrier. This is the design-language hook
-- that a colour gesture is geometrically a spatial gesture. Delegates "SixFour.Spec.Dim6" @phi6@.
lawGestureColourHasPositionTwin :: Bool
lawGestureColourHasPositionTwin =
     phi6 DimA == DimX && phi6 DimB == DimY
  && isSearch DimX && isSearch DimY
  && isUniversal DimL && isUniversal DimT

-- | A swipe then its 'flipSign' returns to the start, when both steps stay in the domain: the ±1
-- inverse lifted through the guard. Teeth: a non-reversible decode would not land back on @p@.
lawGestureReversibleInDomain :: AdmissibleStep -> P6 -> Bool
lawGestureReversibleInDomain st p =
  case gestureSafeNudge st p of
    Nothing -> True
    Just q  -> case gestureSafeNudge (flipSign st) q of
                 Just p' -> p' == p
                 Nothing -> True

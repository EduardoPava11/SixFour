{- |
Module      : SixFour.Spec.BoundedP6
Description : Type-enforced DOMAIN guard for the 6D point: a @BoundedP6@ is in-domain BY CONSTRUCTION (@|v| <= B = 2^29-1@), its constructor is HIDDEN, and a committing/reversible op typed to CONSUME a @BoundedP6@ cannot receive an unchecked @P6@ — an out-of-domain commit becomes a COMPILE error, not the runtime @safeNudge :: Maybe P6@ / Zig @RC_OUT_OF_RANGE@ refusal.

The escape today ("SixFour.Spec.RelationalResidual" 'nudge', :102): the raw @+/-1@ move
@nudge DimA d p = p { p6A = p6A p + d }@ has type @Dim6 -> Int -> P6 -> P6@ with NO domain
check on the result, so @nudge DimA 1 (P6 0 substrateBound 0 0 0 0)@ builds a @P6@ with
@p6A = 2^29@ — an out-of-domain point the shipped Zig kernel REFUSES (@liftChecked@,
@RC_OUT_OF_RANGE@). The escape is silent because @P6@'s coords are plain @Int@ and its
constructor is exported (@P6(..)@). It is caught only at RUNTIME ('safeNudge',
@lawNudgeRespectsDomain@) and only when QuickCheck reaches the domain edge.

This module makes the unchecked point UNREPRESENTABLE on the committing surface, by exactly
the "SixFour.Spec.ByteCarrier" template (phantom-style hidden constructor + smart builder):

  * @'BoundedP6'@ wraps a @P6@; its data constructor is NOT exported.
  * @'mkBoundedP6' :: P6 -> Maybe BoundedP6@ — the ONLY way to build one; @Just@ iff every
    coordinate is in-domain, @Nothing@ otherwise. Mirrors @ByteCarrier.mkLatent@ / the
    @reenterQ16@ requantisation seam.
  * @'unBounded' :: BoundedP6 -> P6@ — a read-only projection (safe: in-domain by
    construction). Mirrors @ByteCarrier.unLatent@ / @toByte@.
  * @'nudgeBounded'@ — a domain-respecting move that RE-VALIDATES after the @+/-1@, so the
    @BoundedP6@ invariant is preserved across moves.
  * @'commit' :: BoundedP6 -> [Int]@ — the model of a committing/reversible entry point: it
    CONSUMES a @BoundedP6@, so a raw @P6@ does not type-check (the teeth). Because the
    constructor is hidden, a client cannot write @commit (BoundedP6 rawP6)@ either — there is
    no path past the smart constructor.

ADDITIVE: the raw 'nudge' / 'applyMove' STAY for the in-domain algebra laws (which never
approach the edge); only the committing surface is typed to @BoundedP6@. No golden vector or
codegen contract references @P6@, so no shipped backend is re-pinned. GHC-boot-only (base).
Laws QuickCheck'd in "Properties.BoundedP6".
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:BoundedP6
module SixFour.Spec.BoundedP6
  ( -- * The in-domain carrier (constructor HIDDEN on purpose)
    BoundedP6
    -- * The only sanctioned constructor / projection
  , mkBoundedP6
  , unBounded
    -- * Domain-respecting move + the model committing op
  , nudgeBounded
  , commit
    -- * Laws (QuickCheck'd in @Properties.BoundedP6@)
  , lawMkBoundedAcceptsInDomain
  , lawMkBoundedRejectsOutOfDomain
  , lawUnBoundedIsInDomain
  , lawNudgeBoundedPreservesDomain
  , lawNudgeBoundedRefusesAtEdge
  ) where

import SixFour.Spec.Dim6 (Dim6(..))
import SixFour.Spec.RelationalResidual (P6(..), nudge, p6Coords, axisVal)
import SixFour.Spec.SubstrateDomain (inDomain)

-- | An in-domain 6D point: @|v| <= B@ on every coordinate, GUARANTEED by construction. The
-- constructor is NOT exported, so the only @BoundedP6@ a client can build is via
-- 'mkBoundedP6' / 'nudgeBounded' — exactly the "SixFour.Spec.ByteCarrier" @Carried@ pattern.
newtype BoundedP6 = BoundedP6 P6 deriving (Eq, Show)

-- | The ONLY way to build a 'BoundedP6': @Just@ iff every coordinate is in the substrate
-- domain @|v| <= B@ ("SixFour.Spec.SubstrateDomain" 'inDomain'), @Nothing@ otherwise — the
-- @RC_OUT_OF_RANGE@ refusal lifted to the TYPE. Mirrors @ByteCarrier.mkLatent@.
mkBoundedP6 :: P6 -> Maybe BoundedP6
mkBoundedP6 p
  | all inDomain (p6Coords p) = Just (BoundedP6 p)
  | otherwise                 = Nothing

-- | Read the underlying point (in-domain by construction). Mirrors @ByteCarrier.unLatent@:
-- a safe projection, no inverse @P6 -> BoundedP6@ is exported.
unBounded :: BoundedP6 -> P6
unBounded (BoundedP6 p) = p

-- | A DOMAIN-RESPECTING move on the typed carrier: nudge the underlying point and
-- RE-VALIDATE, so the result is @Just@ a 'BoundedP6' only when the @+/-1@ kept every
-- coordinate in-domain. This is the typed sibling of 'SixFour.Spec.RelationalResidual.safeNudge'
-- — it can never PRODUCE an out-of-domain carrier.
nudgeBounded :: Dim6 -> Int -> BoundedP6 -> Maybe BoundedP6
nudgeBounded ax d (BoundedP6 p) = mkBoundedP6 (nudge ax d p)

-- | The MODEL committing / reversible entry point (stand-in for "hand a point to the Zig
-- substrate"): it CONSUMES a 'BoundedP6'. THE TEETH — its type makes an unchecked @P6@
-- unrepresentable here (@commit (P6 0 0 0 0 0 0)@ does not type-check), and the hidden
-- constructor blocks @commit (BoundedP6 raw)@ too. Returns the in-domain coords.
commit :: BoundedP6 -> [Int]
commit = p6Coords . unBounded

-- ============================================================================
-- Laws (predicates; QuickCheck'd in Properties.BoundedP6)
-- ============================================================================

-- | An in-domain point is ACCEPTED: 'mkBoundedP6' returns @Just@ whose 'unBounded' is the
-- input. Teeth: a builder that rejected in-domain points fails.
lawMkBoundedAcceptsInDomain :: P6 -> Bool
lawMkBoundedAcceptsInDomain p =
  not (all inDomain (p6Coords p)) ||
    case mkBoundedP6 p of
      Just b  -> unBounded b == p
      Nothing -> False

-- | An out-of-domain point is REFUSED: 'mkBoundedP6' returns @Nothing@. Teeth: the silent
-- raw 'nudge' (which builds the out-of-domain @P6@ this law forbids carrying) cannot route
-- through here. Non-vacuous only at the edge (QuickCheck'd with an edge generator).
lawMkBoundedRejectsOutOfDomain :: P6 -> Bool
lawMkBoundedRejectsOutOfDomain p =
  all inDomain (p6Coords p) ||
    case mkBoundedP6 p of
      Just _  -> False
      Nothing -> True

-- | Every coordinate of a 'BoundedP6' is in-domain — the invariant the type CARRIES. Teeth:
-- if the constructor leaked an unchecked @P6@, this would fail.
lawUnBoundedIsInDomain :: P6 -> Bool
lawUnBoundedIsInDomain p =
  case mkBoundedP6 p of
    Just b  -> all inDomain (p6Coords (unBounded b))
    Nothing -> True

-- | 'nudgeBounded' can never PRODUCE an out-of-domain carrier: a @Just@ result is in-domain
-- on every coordinate. Teeth: skipping the re-validation (returning @Just . BoundedP6 . nudge@)
-- would fail when the move crosses @+/-B@.
lawNudgeBoundedPreservesDomain :: Dim6 -> Int -> P6 -> Bool
lawNudgeBoundedPreservesDomain ax d p =
  case mkBoundedP6 p of
    Nothing -> True
    Just b  -> case nudgeBounded ax d b of
      Just b' -> all inDomain (p6Coords (unBounded b'))
      Nothing -> not (inDomain (axisVal ax p + d))

-- | 'nudgeBounded' REFUSES (@Nothing@) exactly when the nudged axis crosses out of domain —
-- the @RC_OUT_OF_RANGE@ sibling, now type-preserving. Teeth: a non-refusing move at the edge
-- fails. Non-vacuous only at the edge.
lawNudgeBoundedRefusesAtEdge :: Dim6 -> Int -> P6 -> Bool
lawNudgeBoundedRefusesAtEdge ax d p =
  case mkBoundedP6 p of
    Nothing -> True
    Just b  -> case nudgeBounded ax d b of
      Nothing -> not (inDomain (axisVal ax p + d))
      Just _  -> inDomain (axisVal ax p + d)

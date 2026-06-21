{- |
Module      : SixFour.Spec.DetentNudge
Description : The angle-gated ±1 swipe — a unit (a,b) step is admissible ONLY at a projection detent angle, and the step is taken in the detent-rotated frame. Frontier 1c's missing wiring.

Frontier step 6. Three organs existed but nothing BOUND them: "SixFour.Spec.ChromaRotation"
owns the detents (@C12@/@C8@/@C6@ = 30/45/60deg) and the bit-exact quarter-turn
'rotateQuarter'; "SixFour.Spec.LatentNavigation"\/"SixFour.Spec.NudgeStep" own the ±1
@(a,b)@ step. This module makes a user swipe an 'AdmissibleStep' — a smart-ctor that
exists ONLY when the step's angle lands on the chosen detent grid, and whose increment
is the unit ±1 vector rotated into that frame.

We pin the BIT-EXACT subset: a quarter-turn angle @q*90deg@ is admissible on detent @d@
iff it lies on @d@'s grid (@q*90 `mod` detentStepDeg d == 0@). So @C12@ (30deg) and
@C8@ (45deg) admit all four quarter-turns, but @C6@ (60deg) admits only @0/180deg@ —
the octant mirror of "SixFour.Spec.ChromaRotation" @lawQuarterInDetent@ (C4 lives in
the 30/45 grids, not 60). Finer non-quarter detent angles are float-guidance that
re-enters the Q16 floor (ChromaRotation), out of this integer-exact module's scope.

  * 'lawStepOnlyAtDetent' — 'mkAdmissibleStep' succeeds IFF the angle is on the grid.
  * 'lawNonDetentStepInadmissible' — a 90deg step on the 60deg grid is unconstructible.
  * 'lawStepIsUnitInRotatedFrame' — the increment is the unit ±1 rotated by 'rotateQuarter'
    (and stays unit length: the rotation is an isometry).
  * 'lawStepReversible' — the opposite-sign step undoes it (the ±1 inverse).

Additive, GHC-boot, smart-ctor newtype.
-}
module SixFour.Spec.DetentNudge
  ( Sign(..)
  , ABAxis(..)
  , AdmissibleStep            -- opaque: build only via 'mkAdmissibleStep'
  , mkAdmissibleStep
  , baseVec
  , stepDelta
  , applyStep
  , flipSign
    -- * Laws (QuickCheck'd in @Properties.DetentNudge@)
  , lawStepOnlyAtDetent
  , lawNonDetentStepInadmissible
  , lawStepIsUnitInRotatedFrame
  , lawStepReversible
  ) where

import SixFour.Spec.ChromaRotation (Detent(..), detentStepDeg, rotateQuarter)

-- | The ±1 direction of a swipe.
data Sign = Minus | Plus
  deriving (Eq, Ord, Show, Enum, Bounded)

-- | Which chroma axis the swipe moves (the base, pre-rotation, axis).
data ABAxis = AxisA | AxisB
  deriving (Eq, Ord, Show, Enum, Bounded)

-- | An admissible swipe: a detent, a quarter-turn index @q@ whose angle @q*90deg@ is
-- on that detent's grid, a sign, and an axis. Construct only via 'mkAdmissibleStep'
-- (holding one is a value-level proof the step is angle-gated).
newtype AdmissibleStep = AdmissibleStep (Detent, Int, Sign, ABAxis)
  deriving (Eq, Show)

-- | Build a swipe iff its quarter-turn angle lands on the detent grid:
-- @0 <= q < 4@ and @(q*90) `mod` detentStepDeg d == 0@. 'Nothing' off the grid — so a
-- non-detent step is unconstructible.
mkAdmissibleStep :: Detent -> Int -> Sign -> ABAxis -> Maybe AdmissibleStep
mkAdmissibleStep d q s ax
  | q >= 0 && q < 4 && (q * 90) `mod` detentStepDeg d == 0
  = Just (AdmissibleStep (d, q, s, ax))
  | otherwise
  = Nothing

-- | The base (pre-rotation) unit step: ±1 on the chosen chroma axis.
baseVec :: ABAxis -> Sign -> (Int, Int)
baseVec AxisA Plus  = ( 1,  0)
baseVec AxisA Minus = (-1,  0)
baseVec AxisB Plus  = ( 0,  1)
baseVec AxisB Minus = ( 0, -1)

-- | The actual @(a,b)@ increment of a swipe: the base unit step rotated into the
-- detent frame by the bit-exact 'rotateQuarter'.
stepDelta :: AdmissibleStep -> (Int, Int)
stepDelta (AdmissibleStep (_, q, s, ax)) = rotateQuarter q (baseVec ax s)

-- | Apply a swipe to an @(a,b)@ point.
applyStep :: AdmissibleStep -> (Int, Int) -> (Int, Int)
applyStep st (a, b) = let (da, db) = stepDelta st in (a + da, b + db)

-- | The inverse swipe (opposite sign, same detent/quarter/axis).
flipSign :: AdmissibleStep -> AdmissibleStep
flipSign (AdmissibleStep (d, q, s, ax)) = AdmissibleStep (d, q, opp s, ax)
  where opp Plus = Minus
        opp Minus = Plus

-- ============================================================================
-- Laws (predicates; QuickCheck'd in Properties.DetentNudge)
-- ============================================================================

-- | A step is admissible IFF its angle lands on the detent grid — the angle-gating
-- the frontier (1c) demanded, with teeth in both directions.
lawStepOnlyAtDetent :: Detent -> Int -> Sign -> ABAxis -> Bool
lawStepOnlyAtDetent d q s ax =
  let onGrid = q >= 0 && q < 4 && (q * 90) `mod` detentStepDeg d == 0
  in case mkAdmissibleStep d q s ax of
       Just _  -> onGrid
       Nothing -> not onGrid

-- | A 90deg (or 270deg) step on the 60deg (@C6@) grid is UNCONSTRUCTIBLE — the
-- octant mirror of @ChromaRotation.lawQuarterInDetent@ (C4 is not in the 60deg grid).
lawNonDetentStepInadmissible :: Bool
lawNonDetentStepInadmissible =
  mkAdmissibleStep C6 1 Plus AxisA == Nothing
    && mkAdmissibleStep C6 3 Plus AxisA == Nothing
    && mkAdmissibleStep C6 0 Plus AxisA /= Nothing   -- 0deg IS on the 60deg grid
    && mkAdmissibleStep C6 2 Plus AxisA /= Nothing   -- 180deg IS on the 60deg grid

-- | The increment is the unit ±1 step taken in the detent-rotated frame
-- (delegates 'rotateQuarter'), and it stays UNIT length (the rotation is an isometry).
lawStepIsUnitInRotatedFrame :: Detent -> Int -> Sign -> ABAxis -> Bool
lawStepIsUnitInRotatedFrame d q s ax =
  case mkAdmissibleStep d q s ax of
    Nothing -> True
    Just st ->
      stepDelta st == rotateQuarter q (baseVec ax s)
        && let (da, db) = stepDelta st in da * da + db * db == 1

-- | The opposite-sign step undoes it: a ±1 then ∓1 returns to the start (the unit-step
-- inverse, the angle-gated form of @LatentNavigation@'s single-step reversibility).
lawStepReversible :: Detent -> Int -> Sign -> ABAxis -> (Int, Int) -> Bool
lawStepReversible d q s ax v =
  case mkAdmissibleStep d q s ax of
    Nothing -> True
    Just st -> applyStep (flipSign st) (applyStep st v) == v

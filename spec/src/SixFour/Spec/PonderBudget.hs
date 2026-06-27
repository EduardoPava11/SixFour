{- |
Module      : SixFour.Spec.PonderBudget
Description : THE USER NUDGE, abstract: a PAINTABLE per-octant detail-budget field over an (initially empty) 256³ volume that biases the PonderNet's refine/halt decision per region. The user paints sections they want the model to "think harder" on; the BRUSH is the 3-D octant TWICENESS @[2×2×2 ↔ 1]@ applied twice — one stroke covers exactly a two-octant-level subtree (@8^levelsPerStep = 64@ finest octants, the same two levels @SelfSimilarReconstruct@'s @reconstruct256@ = octantLift-twice spans). So the brush granularity IS the self-similar rung, not an arbitrary pixel radius.

The control law: an octant is REFINED (the up-rung invents detail there) iff its painted budget is
positive; the ZERO field is the byte-exact FLOOR (no invention anywhere — the deterministic coarse
upsample), 'lawZeroBudgetIsFloor'. Painting a stroke UP turns exactly that twiceness block to refine,
nothing else ('lawBudgetMonotoneInvention' + 'lawBudgetIsLocal'); the budget is clamped non-negative
('lawNudgeBoundedNonNegative'), and the brush spans exactly the two rung levels
('lawTwicenessBrushIsTwoLevels'). The nudge touches ONLY the halt/refine mask (the same per-octant
mask as "SixFour.Spec.LocalPonder"), never the coarse/DC, so the byte-exact floor at zero budget is
preserved by construction.

HONEST BOUNDARY (doc): monotone-in-invention is NOT monotone-in-quality — byte-exactness holds at the
zero-budget floor; the upper paint range is a soft learned prior, and the Q16 commit may snap fine
invented detail back toward the floor (the un-quantified super-res margin). Pure-spec, emits no golden.
-}
-- COMPARTMENT: MLX-MODEL | tag:MacTag
module SixFour.Spec.PonderBudget
  ( -- * The paintable budget field + the twiceness brush
    Budget
  , twicenessSpan
  , emptyBudget
  , paintStroke
  , budgetToMask
    -- * Laws
  , lawTwicenessBrushIsTwoLevels
  , lawZeroBudgetIsFloor
  , lawBudgetMonotoneInvention
  , lawBudgetIsLocal
  , lawNudgeBoundedNonNegative
  ) where

import SixFour.Spec.SelfSimilarReconstruct (levelsPerStep)

-- | The paintable detail-budget field: one non-negative budget per FINEST octant, Morton-ordered
-- (the flattened 256³ control volume the user paints). Zero everywhere = the empty floor.
type Budget = [Int]

-- | One brush stroke spans a TWO-octant-level subtree: @8 ^ levelsPerStep = 8² = 64@ finest octants.
-- This is the @[2×2×2 ↔ 1]@ twiceness — the same two levels @reconstruct256@ = octantLift-twice covers,
-- so the brush is the self-similar rung, not an arbitrary radius.
twicenessSpan :: Int
twicenessSpan = 8 ^ levelsPerStep

-- | An empty budget field over @n@ finest octants (the unpainted 256³ = the floor everywhere).
emptyBudget :: Int -> Budget
emptyBudget n = replicate n 0

-- | Paint the @s@-th twiceness block to budget value @v@ (clamped non-negative). Every finest octant
-- in block @s@ (indices @s·64 .. s·64+63@) gets @v@; the rest are untouched.
paintStroke :: Budget -> Int -> Int -> Budget
paintStroke b s v =
  [ if i `div` twicenessSpan == s then max 0 v else bi | (i, bi) <- zip [0 ..] b ]

-- | The refine/halt mask the PonderNet acts on (the "SixFour.Spec.LocalPonder" finest-level mask): an
-- octant is REFINED (invents detail) iff its budget is positive, else HALTED to the floor.
budgetToMask :: Budget -> [Bool]
budgetToMask = map (> 0)

-- ---------------------------------------------------------------------------
-- Laws
-- ---------------------------------------------------------------------------

-- | The brush IS the two-level octant reconstruct (the twiceness): one stroke spans
-- @8 ^ levelsPerStep == 64@ finest octants, and @levelsPerStep == 2@. Ties the paint granularity to
-- the self-similar rung, not an arbitrary radius.
lawTwicenessBrushIsTwoLevels :: Bool
lawTwicenessBrushIsTwoLevels =
  twicenessSpan == 8 ^ levelsPerStep && levelsPerStep == 2 && twicenessSpan == 64

-- | THE FLOOR: an empty (zero) budget refines NOTHING, so the model emits the byte-exact deterministic
-- floor (no invention). The nudge's neutral position is the lossless floor.
lawZeroBudgetIsFloor :: Int -> Bool
lawZeroBudgetIsFloor n0 =
  let n = abs n0 `mod` 257
  in not (or (budgetToMask (emptyBudget n)))

-- | Painting a stroke UP turns EXACTLY that twiceness block to refine (invention) and nothing else:
-- from the floor (no octant refined) to precisely the 64-octant brush block. Monotone and bounded to
-- the brush.
lawBudgetMonotoneInvention :: Int -> Bool
lawBudgetMonotoneInvention s0 =
  let s     = abs s0 `mod` 4
      n     = twicenessSpan * 4
      after = paintStroke (emptyBudget n) s 5
      ma    = budgetToMask after
  in not (or (budgetToMask (emptyBudget n)))                                  -- floor refines nothing
     && and [ ma !! i | i <- [s * twicenessSpan .. s * twicenessSpan + twicenessSpan - 1] ]
     && length (filter id ma) == twicenessSpan                               -- exactly the brush block

-- | LOCALITY: painting one stroke leaves every octant OUTSIDE its block untouched (zero). The nudge
-- is regional, not global.
lawBudgetIsLocal :: Bool
lawBudgetIsLocal =
  let n = twicenessSpan * 3
      b = paintStroke (emptyBudget n) 1 7      -- paint only block 1
  in all (\i -> b !! i == 0) [ i | i <- [0 .. n - 1], i `div` twicenessSpan /= 1 ]

-- | The budget is clamped NON-NEGATIVE: there is no "negative invention" (you cannot paint below the
-- floor; the floor is the lossless byte-exact bottom). A negative paint value saturates at 0.
lawNudgeBoundedNonNegative :: Int -> Int -> Bool
lawNudgeBoundedNonNegative s v =
  let n = twicenessSpan * 2
      b = paintStroke (emptyBudget n) (abs s `mod` 2) v
  in all (>= 0) b

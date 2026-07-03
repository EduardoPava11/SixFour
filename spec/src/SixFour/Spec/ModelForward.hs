{- |
Module      : SixFour.Spec.ModelForward
Description : The NUDGE-CONDITIONED FORWARD CONTRACT — the function the review found missing. "SixFour.Spec.ModelIO" defines the boundary types and the FLOOR (@buildFloor = upscale256 . miCapture@), but its @miNudge@/@miGauge@ fields are consumed NOWHERE: the learned nudge→invention mapping was unspecified. This module specs that mapping's FRAME as laws, leaving only the learned COEFFICIENTS opaque.

The decomposition. The committed output is the deterministic floor with an invented residual lifted on
top, through the one sanctioned float→device crossing:

    forward = octantLift floor (commit (gate budget (net …)))

Two responsibilities are split so the byte-exact guarantee never depends on trusting the network:

  * the user's paint BUDGET ("SixFour.Spec.CellNudge" @CellBudget@) GATES — it decides WHETHER a cell
    invents. Zero budget ⇒ zero residual, structurally, for ANY @net@ ('lawZeroNudgeForwardIsFloor').
  * the opaque learned head @net@ ('PonderHead') DECIDES WHAT — it emits the A_7 root coordinates of the
    invented detail. Its codomain is the A_7 chart ("SixFour.Spec.RootLatticeDetail" @fromRootCoords@),
    so every coefficient vector it can emit reconstructs a LEGAL mean-free residual
    ('lawResidualStaysInA7'). The type forbids it from leaving the lattice; we never have to trust it to.

Frame laws (the learned values stay opaque; the FRAME is proven):

  * 'lawZeroNudgeForwardIsFloor' — unpainted input is the byte-exact floor, for any head and either gauge
    (ties to "SixFour.Spec.ModelIO" @lawNeutralNudgeIsAllFloor@ and "SixFour.Spec.SelfSimilarReconstruct"
    @lawZeroTailIsFloor@).
  * 'lawNudgeMovesOutput' — a painted cell moves the committed output off the floor (delegates
    "SixFour.Spec.AboveFloorMargin" @lawAboveFloorMarginReachable@: a surviving residual is guaranteed to
    move the output because the octant lift is a reversible bijection).
  * 'lawResidualStaysInA7' — every head output reconstructs a mean-free (A_7-legal) residual.
  * 'lawForwardCommitIsQ16' — the only float→device path is "SixFour.Spec.ByteCarrier" @reenterQ16@; the
    invented coordinates re-enter the integer grid byte-exact (no drift), and the forward returns @[Int]@.

Scope. The frame is proved on ONE control cell over one octant's coarse: each 16³ cell governs its own
4096-leaf 256³ subtree ("SixFour.Spec.CellNudge" @lawCellGovernsSuperResSubtree@), so the per-cell frame
composes. 'forwardFromInput' consumes a "SixFour.Spec.ModelIO" @ModelInput@ (reading @miNudge@ and
@miGauge@), closing the unused-field gap. The full capture→@UpscaleOutput@ (GIF89a) builder is W1.2;
this module pins the invention frame it must respect. Additive, pure-spec, emits no golden.
-}
-- COMPARTMENT: MLX-MODEL | tag:MacTag
module SixFour.Spec.ModelForward
  ( -- * The opaque learned head (codomain = the A_7 chart)
    PonderHead
  , survHead
    -- * The nudge-conditioned forward
  , forwardOctant
  , forwardFromInput
  , floorOctant
  , paintOnlyInput
    -- * Laws
  , lawZeroNudgeForwardIsFloor
  , lawNudgeMovesOutput
  , lawForwardFromInputConsumesPaint
  , lawMissingBudgetRowIsFloor
  , lawResidualStaysInA7
  , lawForwardCommitIsQ16
  ) where

import SixFour.Spec.ByteCarrier          (mkLatent)
import SixFour.Spec.Q16                   (toQ16)
import SixFour.Spec.RootLatticeDetail     (fromRootCoords, inA)
import SixFour.Spec.SelfSimilarReconstruct (LatentTail(..), tailToDetail, octantLift)
import SixFour.Spec.CellNudge             (CellBudget, emptyCellBudget, paintCellPair)
import SixFour.Spec.ModelIO               (ModelInput(..))
import SixFour.Spec.Upscale256            (UpscaleInput(..))
import SixFour.Spec.AtlasCascade          (emptyExit)
import SixFour.Spec.AboveFloorMargin     (marginCoeffQ16)

-- | The opaque LEARNED head: given a control-cell index and the φ6 gauge, emit the 7 A_7 root
-- coordinates of that cell's invented detail. ModelForward proves the forward FRAME holds for ANY such
-- function; the trained net only fills in the coordinates. (The 7 = rank A_7 = the octant's detail bands.)
type PonderHead = Int -> Bool -> [Integer]

-- | A canonical witness head that emits the MINIMAL surviving detail (one Q16 LSB per band, the
-- "SixFour.Spec.AboveFloorMargin" margin) regardless of cell or gauge. Stands in for the trained net in
-- the laws; the real net emits learned coordinates in the same A_7 chart.
survHead :: PonderHead
survHead _ _ = replicate 7 (fromIntegral marginCoeffQ16)

-- Build the invented latent tail from a cell's 7 A_7 coordinates: each integer coordinate @c@ becomes a
-- Mac-side latent @toQ16 c@ so that re-entering it through the sole crossing commits back to @c@ exactly.
-- Internal (not exported).
headToTail :: [Integer] -> LatentTail
headToTail coords = LatentTail [[ (g 0, g 1, g 2, g 3, g 4, g 5, g 6) ]]
  where
    g i = mkLatent (toQ16 (fromIntegral (coordAt i)))
    coordAt i = if i >= 0 && i < length coords then coords !! i else 0

-- The budget GATE: a cell with zero budget invents nothing (the floor); otherwise the head decides the
-- A_7 coordinates. Zero-paint ⇒ zero residual holds for ANY head. Internal (not exported).
cellDetail :: PonderHead -> Bool -> Int -> [Int] -> [Integer]
cellDetail net gauge ci bs
  | sum bs == 0 = replicate 7 0
  | otherwise   = net ci gauge

-- The per-cell budget row (the 9-channel vector for one control cell). Internal (not exported).
budgetRow :: CellBudget -> Int -> [Int]
budgetRow b i = if i >= 0 && i < length b then b !! i else []

-- | The deterministic FLOOR octant: lift the coarse with zero invented detail (the unpainted output).
floorOctant :: [Int] -> [Int]
floorOctant coarse = octantLift coarse (tailToDetail (headToTail (replicate 7 0)))

-- | The nudge-conditioned forward over one octant's coarse children: lift the coarse with the head's
-- (budget-gated, A_7-legal, Q16-committed) invented detail for control cell @0@. The byte-exact floor
-- when the budget is empty; off the floor where painted.
forwardOctant :: PonderHead -> CellBudget -> Bool -> [Int] -> [Int]
forwardOctant net budget gauge coarse =
  octantLift coarse (tailToDetail (headToTail (cellDetail net gauge 0 (budgetRow budget 0))))

-- | The forward driven by a "SixFour.Spec.ModelIO" @ModelInput@: reads @miNudge@ (the paint) and
-- @miGauge@ (the φ6 toggle) and runs 'forwardOctant'. This is where the previously-unused @ModelInput@
-- fields are consumed; @miCapture@ supplies the coarse in the full builder (W1.2).
forwardFromInput :: PonderHead -> ModelInput -> [Int] -> [Int]
forwardFromInput net inp = forwardOctant net (miNudge inp) (miGauge inp)

-- ---------------------------------------------------------------------------
-- Laws
-- ---------------------------------------------------------------------------

-- | UNPAINTED INPUT IS THE BYTE-EXACT FLOOR, for any head and either gauge: an empty budget gates every
-- cell off, so the gated residual is zero whatever @survHead@ would emit, and the forward equals
-- 'floorOctant'. Ties to "SixFour.Spec.ModelIO" @lawNeutralNudgeIsAllFloor@ /
-- "SixFour.Spec.SelfSimilarReconstruct" @lawZeroTailIsFloor@. Teeth: a head that leaked detail past the
-- gate would diverge from the floor here.
lawZeroNudgeForwardIsFloor :: [Int] -> Bool
lawZeroNudgeForwardIsFloor coarse =
  length coarse /= 8 ||
     ( forwardOctant survHead (emptyCellBudget 1) False coarse == floorOctant coarse
    && forwardOctant survHead (emptyCellBudget 1) True  coarse == floorOctant coarse )

-- | A PAINTED CELL MOVES THE OUTPUT off the floor, for ANY of the nine channel pairs, ANY positive
-- budget, and EITHER gauge: one nonzero entry in control cell 0's row ungates the invention (the gate
-- is @sum bs == 0@), the surviving A_7 detail commits to nonzero, and the lift differs from
-- 'floorOctant'. The inequality is guaranteed by the reversibility of the octant lift (delegates
-- "SixFour.Spec.AboveFloorMargin" @lawAboveFloorMarginReachable@). Teeth: if the commit zeroed the
-- residual the outputs would coincide. (Generalized 2026-07-03 from the single fixed witness
-- cell-0\/pair-0\/budget-1; the pair index is taken mod 9 and the budget clamped positive, so the law
-- is total on all four arguments.)
lawNudgeMovesOutput :: Int -> Int -> Bool -> [Int] -> Bool
lawNudgeMovesOutput pair v gauge coarse =
  length coarse /= 8 ||
  let painted = paintCellPair (emptyCellBudget 1) 0 (abs pair `mod` 9) (max 1 (abs v))
  in forwardOctant survHead painted gauge coarse /= floorOctant coarse

-- | A capture-free 'ModelInput' carrying ONLY the fields 'forwardFromInput' consumes (the paint
-- and the gauge), with a canonical empty capture in @miCapture@. 'forwardFromInput' never reads
-- @miCapture@ (that is W1.2's builder seam); this constructor makes that a testable fact rather
-- than prose, and lets the laws drive the REAL input boundary without a real capture.
paintOnlyInput :: CellBudget -> Bool -> ModelInput
paintOnlyInput bud gauge = ModelInput
  { miCapture = UpscaleInput 0 0 [] [] [] [] [] (const False) emptyExit [] 1
  , miNudge   = bud
  , miGauge   = gauge
  }

-- | ★ THE INPUT BOUNDARY IS HONEST END-TO-END: driving the forward THROUGH the "SixFour.Spec.ModelIO"
-- boundary ('forwardFromInput', the function the app-side port actually mirrors) consumes exactly the
-- paint and the gauge — the unpainted input is the byte-exact floor and a painted input moves off it,
-- through 'ModelInput', not merely at 'forwardOctant'. (Added 2026-07-03: the audit found
-- 'forwardFromInput' exported but pinned by no law.)
lawForwardFromInputConsumesPaint :: Int -> Int -> Bool -> [Int] -> Bool
lawForwardFromInputConsumesPaint pair v gauge coarse =
  length coarse /= 8 ||
  let painted = paintCellPair (emptyCellBudget 1) 0 (abs pair `mod` 9) (max 1 (abs v))
  in    forwardFromInput survHead (paintOnlyInput (emptyCellBudget 1) gauge) coarse
          == floorOctant coarse
     && forwardFromInput survHead (paintOnlyInput painted gauge) coarse
          /= floorOctant coarse

-- | REFUSAL: a budget with NO row for the control cell invents nothing — 'budgetRow' answers the
-- empty row off the end of the list (never a crash, never a neighbour's row), the empty row gates
-- the head off, and the forward is the byte-exact floor, for any head and either gauge. Pins the
-- invalid-input direction the audit (2026-07-03) found unpinned: silent degradation is now a
-- CONTRACT (degrade to the floor), not an accident.
lawMissingBudgetRowIsFloor :: Bool -> [Int] -> Bool
lawMissingBudgetRowIsFloor gauge coarse =
  length coarse /= 8 ||
  forwardOctant survHead [] gauge coarse == floorOctant coarse

-- | THE HEAD'S CODOMAIN IS A_7: for ANY coordinates the head emits, reading them as A_7 root coordinates
-- reconstructs a mean-free (Σ = 0) residual, so the invention is a legal detail band by construction.
-- Teeth: a raw, non-mean-free voxel bump (@e_0@, Σ = 1) is NOT in A_7.
lawResidualStaysInA7 :: [Integer] -> Bool
lawResidualStaysInA7 cs =
     inA (fromRootCoords 8 (take 7 (cs ++ repeat 0)))
  && not (inA (1 : replicate 7 (0 :: Integer)))

-- | THE COMMIT IS BYTE-EXACT Q16: the invented A_7 coordinates cross to the device through the sole
-- sanctioned door "SixFour.Spec.ByteCarrier" @reenterQ16@ and land on the integer grid with NO drift
-- (the @toQ16 c@ latent re-enters to exactly @c@), and the forward returns @[Int]@. Teeth: a crossing
-- that forgot the @toQ16@ scaling would commit to @c * 65536@ and fail.
lawForwardCommitIsQ16 :: Bool
lawForwardCommitIsQ16 =
  let c = marginCoeffQ16
  in tailToDetail (headToTail (replicate 7 (fromIntegral c)))
       == [[ (c, c, c, c, c, c, c) ]]

{- |
Module      : SixFour.Spec.AboveFloorMargin
Description : The TRAINING GO/NO-GO: prove that invented 256³ detail can survive the Q16 commit and move the output OFF the deterministic floor, and pin the FINITE margin (the minimum per-band coefficient the trainer must exceed). The honest risk the review named was "the Q16 commit can snap invented float detail back to the floor"; this module turns that risk into a measured, gated number.

Why this is the cheapest possible de-risk. The learned up-rung (the PonderNet invention) rides
ABOVE the deterministic "SixFour.Spec.Upscale256" floor; its only path to a device byte is the single
sanctioned crossing "SixFour.Spec.ByteCarrier" @reenterQ16@ = "SixFour.Spec.Q16" @quantizeQ16@ =
@round (x * 65536)@ (round-half-to-even). Two facts decide whether days of training can ever beat the
floor, and BOTH are settled here for free, in-spec:

  1. __Survival is a threshold, and the threshold is finite__ ('lawFloorMarginIsFinite'). A latent of
     ONE Q16 LSB (@toQ16 1@) re-enters to the integer @1@ and survives; a quarter-LSB, and even an
     EXACT half-LSB (round-half-to-even sends @0.5@ to the even @0@), re-enter to @0@ and are absorbed
     by the floor. So invented detail below ~half a Q16 LSB is indistinguishable from no detail. That
     half-LSB is the margin the trainer's coefficients must exceed; 'marginCoeffQ16' / 'marginCoeffLatent'
     name it so the trainer can import the number.

  2. __Above the threshold the floor is NOT absorbing__ ('lawAboveFloorMarginReachable'). Because the
     octant lift ("SixFour.Spec.SelfSimilarReconstruct" 'octantLift' = "SixFour.Spec.OctreeCell"
     @octantSynthesize@) is a REVERSIBLE integer bijection on @(coarse, detail)@, ANY detail that
     survives the commit as nonzero is guaranteed to change the reconstructed cube. So a single
     surviving Q16 LSB of invented detail provably reaches the output, off the floor.

Discrete geometry + algebraic number theory grounding ('lawSurvivingDetailIsA7'). The 7 invented
bands of an octant are the root coordinates of the A_7 lattice ("SixFour.Spec.RootLatticeDetail":
@1 coarse + 7 detail@, the split exact sequence @0 → A_7 → ℤ^8 → ℤ → 0@). Reading the surviving bands
as A_7 root coordinates ('RootLatticeDetail.fromRootCoords') reconstructs a LEGAL mean-free residual
(@inA@, Σ = 0), so the learned head can be parameterized in the A_7 chart and every coefficient vector
it emits is a valid detail band by construction. This is what W1.1 ('Spec.ModelForward') will type the
invention's codomain as.

Verdict rule for the workflow (@docs/MODEL-BUILD-WORKFLOW.md@ W0.1): if these laws are green, the
floor is reachable in principle and Phase 3+ is justified; the EMPIRICAL margin (does the TRAINED model
actually produce coefficients above 'marginCoeffQ16') is W4.3. Additive, pure-spec, emits no golden.
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none
module SixFour.Spec.AboveFloorMargin
  ( -- * The margin (the number the trainer must exceed)
    marginCoeffQ16
  , marginCoeffLatent
  , survivesCommit
    -- * Laws
  , lawFloorMarginIsFinite
  , lawAboveFloorMarginReachable
  , lawSurvivingDetailIsA7
    -- * The empirical obligation (CONTRACT-ONLY)
  , contractAboveFloorMarginMeasured
  ) where

import SixFour.Spec.ByteCarrier          (mkLatent, reenterQ16, toByte)
import SixFour.Spec.Q16                   (toQ16)
import SixFour.Spec.RootLatticeDetail     (fromRootCoords, inA)
import SixFour.Spec.SelfSimilarReconstruct (LatentTail(..), tailToDetail, octantLift)

-- | The smallest per-band invented coefficient that survives the Q16 commit, in DEVICE units: one Q16
-- LSB (@= 1@). Anything the learned head emits whose commit rounds below this is absorbed by the floor.
marginCoeffQ16 :: Int
marginCoeffQ16 = 1

-- | The same margin in MAC-SIDE latent (float) units: @toQ16 1 = 1 / 65536@. A latent coefficient of
-- magnitude at least this re-enters to a nonzero byte; below ~half of it the commit snaps to the floor.
marginCoeffLatent :: Double
marginCoeffLatent = toQ16 1

-- | Does a Mac-side latent coefficient survive the single float→device crossing as nonzero detail? It
-- survives iff @quantizeQ16 x /= 0@, i.e. iff @|x| > half a Q16 LSB@ (round-half-to-even). This is the
-- exact predicate that separates invented detail from the floor.
survivesCommit :: Double -> Bool
survivesCommit x = commit x /= 0

-- The single sanctioned float→device crossing, scalar form: re-enter a Mac-side latent through the ONE
-- door 'ByteCarrier.reenterQ16' and read the committed byte. Definitionally equals @Q16.quantizeQ16@,
-- but routed through 'reenterQ16' so the @lint-q16-crossing@ contract holds (no module but ByteCarrier
-- may import @quantizeQ16@). Internal; not exported.
commit :: Double -> Int
commit = toByte . reenterQ16 . mkLatent

-- | THE MARGIN IS FINITE AND POSITIVE. One Q16 LSB survives the commit; a quarter-LSB and an EXACT
-- half-LSB are both absorbed (round-half-to-even rounds @0.5@ to the even @0@); zero is the floor. So
-- the survival threshold lies in @(½ LSB, 1 LSB]@: there is a smallest invented-detail magnitude below
-- which nothing reaches the output. Teeth: a commit that rounded half-away-from-zero (or used a coarser
-- grid) would survive at the half-LSB and fail the @== 0@ clause.
lawFloorMarginIsFinite :: Bool
lawFloorMarginIsFinite =
     commit (toQ16 1)       == marginCoeffQ16   -- one Q16 LSB survives (re-enters to 1)
  && survivesCommit (toQ16 1)                    -- ...stated via the survival predicate
  && commit (toQ16 1 / 2)   == 0                 -- exact half-LSB: round-half-to-even → floor
  && commit (toQ16 1 / 4)   == 0                 -- quarter-LSB: below half → floor
  && not (survivesCommit (toQ16 1 / 4))          -- ...stated via the survival predicate
  && commit 0               == 0                 -- zero is the floor

-- | ABOVE THE MARGIN THE FLOOR IS NOT ABSORBING. A latent tail of one Q16 LSB per band (the minimal
-- surviving coefficient) re-enters to nonzero integer detail (all @marginCoeffQ16@), and applying the
-- SAME octant operator with it versus the zero (floor) detail produces a DIFFERENT reconstructed
-- octant. The inequality is guaranteed by the reversibility of the lift (distinct detail ⇒ distinct
-- cube for fixed coarse), so a single surviving LSB provably reaches the output. Teeth: if the commit
-- zeroed a 1-LSB latent (margin > 1 LSB) the @survDet@ clause fails; if the lift ignored detail the
-- octant clause fails.
lawAboveFloorMarginReachable :: Bool
lawAboveFloorMarginReachable =
  let u        = mkLatent (toQ16 1)                   -- one Q16 LSB of invented detail per band
      z        = mkLatent 0                           -- the floor (no invention)
      survTail = LatentTail [[ (u,u,u,u,u,u,u) ]]
      zeroTail = LatentTail [[ (z,z,z,z,z,z,z) ]]
      coarse   = [0,0,0,0,0,0,0,0]                    -- one octant's 8 children (a fixed coarse)
      survDet  = tailToDetail survTail
      zeroDet  = tailToDetail zeroTail
  in survDet == [[ (marginCoeffQ16, marginCoeffQ16, marginCoeffQ16, marginCoeffQ16
                  , marginCoeffQ16, marginCoeffQ16, marginCoeffQ16) ]]   -- (a) survives the commit
     && zeroDet == [[ (0,0,0,0,0,0,0) ]]                                  -- floor detail is zero
     && octantLift coarse survDet /= octantLift coarse zeroDet            -- (b) moves the output off floor

-- | THE INVENTION LIVES IN A_7. The 7 surviving bands, read as the root coordinates of the A_7 lattice,
-- reconstruct a LEGAL mean-free residual (@inA@, Σ = 0) via 'RootLatticeDetail.fromRootCoords' — so the
-- learned head can be parameterized in the A_7 chart and every coefficient vector it emits is a valid
-- detail band by construction. The minimal surviving witness @[1,1,1,1,1,1,1]@ reconstructs the explicit
-- mean-free vector @[1,0,0,0,0,0,0,-1]@. Teeth: a raw, non-mean-free voxel bump (@e_0@, Σ = 1) is NOT a
-- legal A_7 detail.
lawSurvivingDetailIsA7 :: Bool
lawSurvivingDetailIsA7 =
  let coords = replicate 7 (fromIntegral marginCoeffQ16) :: [Integer]   -- the 7 surviving bands as A_7 coords
      vec    = fromRootCoords 8 coords                                    -- reconstruct the 8-voxel residual
  in inA vec                                                              -- legal A_7 detail (mean-free)
     && vec == [1,0,0,0,0,0,0,-1]                                         -- the explicit mean-free witness
     && not (inA (1 : replicate 7 0))                                     -- teeth: e_0 (Σ=1) is not in A_7

-- | CONTRACT-ONLY (unproven until trained) — the EMPIRICAL margin (W4.3). The laws above prove the floor
-- is reachable IN PRINCIPLE (a 1-LSB invention survives the commit and moves the cube). They do NOT prove
-- the TRAINED model actually emits coefficients above 'marginCoeffQ16' on real captures. That measurement
-- is the discharge metric: the FRACTION of the model's emitted latent detail coefficients with
-- @survivesCommit x == True@, reported by the trainer harness @trainer/mlx/above_floor_margin.py@ and
-- guarded against the mean-dominated cell margin. This marker carries no truth value; it is the documented
-- obligation, pinned in "SixFour.Spec.Model" @modelLawLedger@ as 'ContractOnly' so a green gate never reads
-- as "the up-rung learns detail". See @SIXFOUR-MODEL.md@ and @trainer/TRAINER-BUILD-PLAN.md@ (Phase 5).
contractAboveFloorMarginMeasured :: ()
contractAboveFloorMarginMeasured = ()

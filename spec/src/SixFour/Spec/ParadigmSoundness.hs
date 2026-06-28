{- |
Module      : SixFour.Spec.ParadigmSoundness
Description : THE MASTER THEOREM of the self-supervised paradigm, scoped to STRUCTURAL soundness — the single browsable capstone that conjoins ALL the necessary teachings into "the paradigm is STRUCTURALLY sound": the objective identifies the right thing, the readout has a unique reachable minimum, collapse is structurally impossible, and the crossing stays byte-exact. Every conjunct DELEGATES to an already-green teaching module, so this is the one place a reader sees the whole structural proof, and a regression in ANY teaching breaks it here. STRUCTURAL is the load-bearing word: this does NOT assert the real model has been trained on real captures (the only run to date floored; the full-matrix trainer does not yet exist) — that empirical obligation is 'contractEmpiricalSoundnessUnproven'. Renamed from @lawParadigmIsSound@ in the model-spec unification so a green gate never reads as "the model works".

This supersedes "SixFour.Spec.LearnabilityTheorem" @lawJointObjectiveIdentifiesFullPalette@ as the top of the chain in two
ways: (1) its CONVERGENCE conjunct uses the GENERAL guarantee "SixFour.Spec.Convergence"
@lawCompositeUniqueMinIffValueWeighted@ (a unique-global-minimum-reachable-by-GD proof) rather than the
single-fixture golden descent the learnability capstone delegated to; (2) it ADDS the two teachings the
learnability capstone omitted — ANTI-CHEAT ("SixFour.Spec.JepaTarget": the target is a data-manufactured
label, never the model's own output, so collapse is structurally impossible) and DETERMINISM
("SixFour.Spec.ByteCarrier"/"SixFour.Spec.Q16": the learned float re-enters the integer grid byte-exact,
so it never breaks cross-device replay).

The nine necessary teachings (each a delegated, green law) — the original seven plus HEAD-CONVERGENCE
(the actual ViT readout converges; trunk scoped out) and GENERALIZATION (held-out follows train, no shift):

  1. SIGNAL        — there is learnable signal, read through the owner's two lenses: discrete geometry
                     (the @d6@/ℓ¹ lattice norm on L) and algebraic number theory (the @ℤ[i]@ Gaussian norm
                     on chroma). "SixFour.Spec.AnchorDiagnostic".
  2. EXPRESSIVITY  — the target is reachable above the Q16 floor and lives in the @A_7@ root lattice.
                     "SixFour.Spec.AboveFloorMargin".
  3. IDENTIFIABILITY — the objective is a sufficient statistic for the target: the rank-3 cell aggregate
                     plus the value head jointly identify the full palette ("SixFour.Spec.LearnabilityTheorem"),
                     AND the recovered cell-blind complement is a genuine @A_7@ mean-free lattice vector,
                     admitted by the typed @mkMeanFreeChecked@ consumer (a non-mean-free @e_0@, @Σ=1@,
                     is REFUSED) — the inlined "SixFour.Spec.IdentifiabilityIsA7Bridge" fold, so @A_7@
                     membership is load-bearing in the capstone.
  4. CONVERGENCE   — the objective is a convex quadratic with a UNIQUE global minimum = the target
                     (reachable by GD, no spurious local minima), CONDITIONAL on @w_value > 0@.
                     "SixFour.Spec.Convergence".
  5. NO-COLLAPSE   — the per-factor variance floor keeps the cross-moment full rank.
                     "SixFour.Spec.VarianceFloorGuard".
  6. ANTI-CHEAT    — the target is data-manufactured (no EMA, no self-produced rollout), so the trivial
                     collapse predictor is rejected. "SixFour.Spec.JepaTarget".
  7. DETERMINISM   — the float→device crossing is byte-exact (re-entry to the Q16 grid is a fixpoint), so
                     the learned head never breaks the integer replay. "SixFour.Spec.ByteCarrier" / Q16.

The capstone 'lawParadigmIsStructurallySound' is the conjunction, carrying the SAME @w_value > 0@ side
condition as identifiability and convergence — it is TRUE with the value head on and FALSE with it off, so
it is load-bearing, not decorative. Pure-spec, GHC-boot-only; @once@-tested in "Properties.ParadigmSoundness".
Emits no golden (it is the assembly of STRUCTURAL guarantees, each already gated). The empirical gap (the
model actually trains to the minimum on real data) is 'contractEmpiricalSoundnessUnproven', not a law.
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none
module SixFour.Spec.ParadigmSoundness
  ( -- * The nine teachings, named
    teachingSignal
  , teachingExpressivity
  , teachingIdentifiability
  , teachingConvergence
  , teachingNoCollapse
  , teachingAntiCheat
  , teachingDeterminism
  , teachingHeadConvergence
  , teachingGeneralization
    -- * The master theorem (STRUCTURAL soundness — see the empirical-gap marker)
  , paradigmStructurallySound
  , lawParadigmIsStructurallySound
  , lawStructuralSoundnessNeedsValueHead
    -- * The honest boundary
  , contractEmpiricalSoundnessUnproven
  ) where

import SixFour.Spec.AnchorDiagnostic    (lawIsoLuminantSignalIsInChromaRingNotL, lawConstantChannelIsLatticeFloor)
import SixFour.Spec.AboveFloorMargin    (lawAboveFloorMarginReachable, lawSurvivingDetailIsA7)

import SixFour.Spec.IdentifiabilityIsA7Bridge (lawIdentifiabilityComplementIsA7)
import SixFour.Spec.Convergence         (lawCompositeUniqueMinIffValueWeighted, lawConvexNoSpuriousLocalMin)
import SixFour.Spec.HeadConvergence     (lawReadoutConvergesGivenFeatures, lawHeadDescentScopeIsReadoutNotTrunk)
import SixFour.Spec.Generalization      (lawNoDistributionShift, lawHeldErrorIsCoverageNotShift, lawModelGeneralizesUpToCoverage)
import SixFour.Spec.VarianceFloorGuard  (lawEitherCollapseTripsGuard)
import SixFour.Spec.JepaTarget          (lawTargetIsDataManufacturedNotEncoded, lawCollapseIsRejected, lawConstantOrbitMissesMovedFrame)
import SixFour.Spec.ByteCarrier         (lawReentryIsFloor)
import SixFour.Spec.Q16                 (lawTerminalQuantizationIdempotent)

-- | TEACHING 1 — SIGNAL exists, through the two owner-named lenses (discrete geometry on L, ANT on
-- chroma): an iso-luminant scene carries signal in the @ℤ[i]@ chroma ring (not L), and a constant
-- channel sits at the lattice floor (zero energy). Delegates "SixFour.Spec.AnchorDiagnostic".
teachingSignal :: Bool
teachingSignal = lawIsoLuminantSignalIsInChromaRingNotL && lawConstantChannelIsLatticeFloor 20000

-- | TEACHING 2 — EXPRESSIVITY: the target is reachable above the Q16 floor and is a legal @A_7@ residual.
-- Delegates "SixFour.Spec.AboveFloorMargin".
teachingExpressivity :: Bool
teachingExpressivity = lawAboveFloorMarginReachable && lawSurvivingDetailIsA7

-- | TEACHING 3 — IDENTIFIABILITY (A_7-witnessed): the rank-3 cell aggregate is a sufficient statistic for
-- 9 of 24 DOF and the value head identifies the 15-DOF complement, AND the recovered cell-blind direction
-- (the checkerboard parity) is a genuine @A_7@ mean-free lattice vector, admitted by the typed
-- @RootLatticeDetail.mkMeanFreeChecked@ consumer — with REAL teeth (a non-mean-free @e_0@, @Σ = 1@, is
-- REFUSED) — and the DOF accounting closes (@9 + 15 = 24@). So @A_7@ lattice membership is load-bearing IN
-- THE CAPSTONE. This is the single fold law "SixFour.Spec.IdentifiabilityIsA7Bridge"
-- @lawIdentifiabilityComplementIsA7@ (the bridge delegates the two BASE identifiability laws from
-- "SixFour.Spec.LearnabilityTheorem" directly, not @teachingIdentifiability@, so the fold imports here
-- with no module cycle — the bridge is now the SINGLE source of the A_7-witnessed identifiability fact).
teachingIdentifiability :: Bool
teachingIdentifiability = lawIdentifiabilityComplementIsA7

-- | TEACHING 4 — CONVERGENCE: the convex objective has a unique global minimum = the target (no spurious
-- local minima), reachable by GD, CONDITIONAL on @w_value > 0@. Delegates "SixFour.Spec.Convergence".
teachingConvergence :: Bool
teachingConvergence = lawCompositeUniqueMinIffValueWeighted seed && lawConvexNoSpuriousLocalMin seed seed
  where seed = [0.1, -0.2, 0.3, 0.05, -0.15, 0.25, 0.2, -0.1, 0.0, 0.12, -0.22, 0.31,
                0.07, -0.17, 0.27, 0.09, -0.19, 0.29, 0.11, -0.21, 0.33, 0.13, -0.23, 0.35]

-- | TEACHING 5 — NO-COLLAPSE: a collapse in either factor of the cross-moment trips the variance guard.
-- Delegates "SixFour.Spec.VarianceFloorGuard".
teachingNoCollapse :: Bool
teachingNoCollapse = lawEitherCollapseTripsGuard

-- | TEACHING 6 — ANTI-CHEAT (STRUCTURAL): the target is a data-manufactured label (not an encoded/EMA
-- output), the trivial collapse predictor is rejected, and the inter-frame constant orbit strictly
-- misses a moved frame. So the model cannot satisfy its own prediction by collapsing — the defining
-- STRUCTURAL soundness of a self-supervised paradigm. Delegates "SixFour.Spec.JepaTarget". (The earlier
-- @lawNoSelfProducedRolloutTarget@ conjunct was retired as a definitional restatement; the real motion
-- witness 'lawConstantOrbitMissesMovedFrame' replaces it.)
teachingAntiCheat :: Bool
teachingAntiCheat =
  lawTargetIsDataManufacturedNotEncoded && lawCollapseIsRejected && lawConstantOrbitMissesMovedFrame

-- | TEACHING 7 — DETERMINISM: the learned float re-enters the Q16 integer grid byte-exact (re-entry is a
-- fixpoint, requantisation is idempotent), so the learned head never breaks cross-device replay.
-- Delegates "SixFour.Spec.ByteCarrier" / "SixFour.Spec.Q16".
teachingDeterminism :: Bool
teachingDeterminism = lawReentryIsFloor 3000 && lawTerminalQuantizationIdempotent 3000

-- | TEACHING 8 — HEAD CONVERGENCE: the ViT value head's LAST layer (the linear readout over fixed
-- features) provably converges to the unique minimum, and the non-convex trunk is PROVEN outside that
-- guarantee (so the scope boundary is itself a theorem). Delegates "SixFour.Spec.HeadConvergence".
teachingHeadConvergence :: Bool
teachingHeadConvergence = lawReadoutConvergesGivenFeatures && lawHeadDescentScopeIsReadoutNotTrunk

-- | TEACHING 9 — GENERALIZATION: held-out follows train because the data-manufactured target is a
-- SEED-INDEPENDENT pure function (no distribution shift); held error is COVERAGE + the irreducible
-- masked-band residual, never a shift gap. Delegates "SixFour.Spec.Generalization".
teachingGeneralization :: Bool
teachingGeneralization =
  lawNoDistributionShift 17 [1, 2, 3, 4, 5, 6, 7] && lawHeldErrorIsCoverageNotShift 3
  && lawModelGeneralizesUpToCoverage 3

-- | The paradigm is STRUCTURALLY sound at value-head weight @wv@: ALL NINE teachings hold. The
-- CONVERGENCE and IDENTIFIABILITY teachings carry the @w_value > 0@ requirement, so soundness is gated
-- on @wv > 0@. STRUCTURAL means: the objective identifies the target, the readout converges to a unique
-- minimum, collapse is structurally impossible, and the float crossing is byte-exact. It does NOT mean
-- the real model has been trained to that minimum on a real corpus — see 'contractEmpiricalSoundnessUnproven'.
paradigmStructurallySound :: Double -> Bool
paradigmStructurallySound wv =
     teachingSignal
  && teachingExpressivity
  && teachingIdentifiability
  && (wv > 0 && teachingConvergence)   -- convergence's unique minimum needs the value head on
  && teachingNoCollapse
  && teachingAntiCheat
  && teachingDeterminism
  && teachingHeadConvergence           -- the actual ViT head's readout provably converges
  && teachingGeneralization            -- and held-out follows train (no distribution shift)

-- | THE MASTER THEOREM (STRUCTURAL): with the value head on (@w_value = 1@) the self-supervised paradigm
-- is STRUCTURALLY sound — every necessary teaching holds (the objective identifies the target, the
-- readout has a unique reachable minimum, collapse is impossible, the crossing is byte-exact). Non-vacuous:
-- 'lawStructuralSoundnessNeedsValueHead' shows it is FALSE at @w_value = 0@, so the conjunction is
-- load-bearing. This is NOT a claim that the model has learned, or will learn, on real captures — that is
-- 'contractEmpiricalSoundnessUnproven'. The name was @lawParadigmIsSound@ until the model-spec unification
-- scoped it to STRUCTURAL soundness (the only run to date floored; the full-matrix trainer does not yet exist).
lawParadigmIsStructurallySound :: Bool
lawParadigmIsStructurallySound = paradigmStructurallySound 1.0

-- | The side condition is load-bearing: structural soundness FAILS with the value head off
-- (@w_value = 0@) — convergence loses its unique minimizer (the 15-DOF complement is free). Teeth: this
-- is exactly the bug the @w_value = 1@ default fixes.
lawStructuralSoundnessNeedsValueHead :: Bool
lawStructuralSoundnessNeedsValueHead = lawParadigmIsStructurallySound && not (paradigmStructurallySound 0.0)

-- | CONTRACT-ONLY (unproven until trained). Structural soundness ('lawParadigmIsStructurallySound') proves
-- the objective, identifiability, convergence-of-readout, no-collapse, and determinism HOLD — it does NOT
-- prove the real model has been trained to the identified minimum on a real corpus. As of the model-spec
-- unification, the new full-matrix trainer does not exist and the only training run to date FLOORED
-- (held-out @L_band ≈ 5.4e-4@ vs the zero-prediction floor @≈ 3.5e-4@). This marker exists so a green gate
-- never reads as "the model works". It carries no truth value; it is the documented obligation. See
-- @SIXFOUR-MODEL.md@ §contract-only and @docs/NEXT-STEPS.md@ (W4.3).
contractEmpiricalSoundnessUnproven :: ()
contractEmpiricalSoundnessUnproven = ()

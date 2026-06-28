{- |
Module      : SixFour.Spec.IdentifiabilityIsA7Bridge
Description : The owner-requested FOLD, done additively: a single law that wires the ANT-load-bearing fact (the cell objective's BLIND direction is a typed @A_7@ lattice vector) into the master theorem's IDENTIFIABILITY conjunct, so the @A_7@ algebra stops being an unconnected side-bridge and becomes a guard on the capstone.

The gap this closes. "SixFour.Spec.ParadigmSoundness" @teachingIdentifiability@ delegates to the rank-3
sufficient-statistic law and the value-head complement law ("SixFour.Spec.LearnabilityTheorem"), but it
never asserts WHAT the recovered complement is made of. The fact that the direction the value head must
recover is a genuine @A_7@ mean-free residual — the only place the algebraic-number-theory substrate is
made load-bearing by a REAL typed consumer (@RootLatticeDetail.mkMeanFreeChecked@, exercised in
"SixFour.Spec.BlindComplementIsA7") — lived in a module unconnected to the master theorem. This module
conjoins the two into one law @lawIdentifiabilityComplementIsA7@ the owner can later inline into
@ParadigmSoundness@'s identifiability conjunct (rule 2 forbids editing @ParadigmSoundness@ in flight, so
the fold is staged here as an importing bridge).

HONESTY (no overclaim). This bridge asserts EXACTLY the sound core, not more. It does NOT claim the whole
15-DOF cell-blind complement @S^⊥@ IS the @A_7@ lattice — "SixFour.Spec.BlindComplementGeometry" already
proved @S^⊥@ (15-DOF) and @A_7@ (21-DOF) are DISTINCT, neither containing the other. What is true, and all
this bridge claims, is that the SPECIFIC blind direction the value head recovers — the checkerboard parity
@cb(v) = (−1)^popcount(v)@ — lives in the OVERLAP @S^⊥ ∩ A_7@: @cellLoss@ is blind to it (so the value head
must supply it) AND it passes the typed @mkMeanFreeChecked@ consumer as an @A_7@ vector. The DOF accounting
@9 + 15 = 24@ here is the cell-identified vs cell-blind split of the 24 colour DOF, NOT a claim that the 15
blind DOF are all lattice.

The teeth are the SAME real teeth that already guard "SixFour.Spec.BlindComplementIsA7", now guarding the
capstone: a NON-mean-free direction (@e_0@ with @Σ = 1@) is REFUSED by @mkMeanFreeChecked@
(@lawNonLatticeDirectionRefused@), so a non-@A_7@ direction cannot masquerade as the recovered complement.
Drop EITHER conjunct — the master-theorem identifiability or the @A_7@ membership — and the bridge breaks.
Pure-spec, GHC-boot-only, emits no golden; laws @once@-tested in "Properties.IdentifiabilityIsA7Bridge".
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none
module SixFour.Spec.IdentifiabilityIsA7Bridge
  ( -- * The DOF accounting carried through from the master theorem
    bridgeIdentifiedDof
  , bridgeBlindDof
  , bridgeTotalDof
    -- * The two halves of the fold
  , lawMasterIdentifiabilityHolds
  , lawRecoveredComplementAdmittedAsA7
  , lawNonA7DirectionCannotMasquerade
  , lawDofAccountingCloses
    -- * The fold (the owner can later inline this into ParadigmSoundness)
  , lawIdentifiabilityComplementIsA7
  ) where

import Data.Maybe (isJust)

import SixFour.Spec.BlindComplementIsA7 (lawCellBlindComplementIsA7, lawNonLatticeDirectionRefused, checkerboardMeanFree)
import SixFour.Spec.LearnabilityTheorem (lawCellLossIdentifiesRank3Subspace, lawValueHeadIdentifiesComplement, identifiedDof, blindDof, totalColourDof)

-- ---------------------------------------------------------------------------
-- The DOF accounting (re-surfaced from the master theorem's identifiability story)
-- ---------------------------------------------------------------------------

-- | The colour DOF the rank-3 cell aggregate IDENTIFIES (the 9 entries of @A = C·Sᵀ@). Carried through
-- from "SixFour.Spec.LearnabilityTheorem" so the fold's accounting tooth reads at a glance.
bridgeIdentifiedDof :: Int
bridgeIdentifiedDof = identifiedDof

-- | The colour DOF @cellLoss@ is BLIND to (@24 − 9 = 15@, the complement of @span(S)@). The recovered
-- checkerboard direction lives among these — and, additionally, in @A_7@ (the overlap @S^⊥ ∩ A_7@).
bridgeBlindDof :: Int
bridgeBlindDof = blindDof

-- | The full one-octant colour DOF (8 voxels × 3 OKLab channels = 24).
bridgeTotalDof :: Int
bridgeTotalDof = totalColourDof

-- ---------------------------------------------------------------------------
-- The two halves of the fold + teeth (QuickCheck'd in Properties.IdentifiabilityIsA7Bridge)
-- ---------------------------------------------------------------------------

-- | HALF 1 — the BASE identifiability holds: the rank-3 cell aggregate is a sufficient statistic
-- ("SixFour.Spec.LearnabilityTheorem" @lawCellLossIdentifiesRank3Subspace@) AND the value head identifies
-- the complement (@lawValueHeadIdentifiesComplement@). These ARE the two base laws
-- "SixFour.Spec.ParadigmSoundness" @teachingIdentifiability@ is built from; the bridge delegates them
-- DIRECTLY (not via @teachingIdentifiability@) so the fold can be imported INTO the capstone without a
-- module cycle. @ParadigmSoundness@ now sets @teachingIdentifiability = lawIdentifiabilityComplementIsA7@,
-- so the two stay identical by construction with the bridge as the single source.
lawMasterIdentifiabilityHolds :: Bool
lawMasterIdentifiabilityHolds = lawCellLossIdentifiesRank3Subspace && lawValueHeadIdentifiesComplement

-- | HALF 2 — the recovered complement direction is an @A_7@ lattice vector, witnessed by the TYPED
-- consumer. @cellLoss@ is blind to the checkerboard AND @mkMeanFreeChecked@ ADMITS it as a @MeanFree@/@A_7@
-- vector (@isJust checkerboardMeanFree@). Delegates "SixFour.Spec.BlindComplementIsA7"
-- @lawCellBlindComplementIsA7@ and additionally pins the typed-consumer admission locally.
lawRecoveredComplementAdmittedAsA7 :: Bool
lawRecoveredComplementAdmittedAsA7 =
     lawCellBlindComplementIsA7      -- cellLoss BLIND to cb  AND  Σ cb = 0 (an A_7 residual)
  && isJust checkerboardMeanFree     -- the typed mkMeanFreeChecked consumer ADMITS the blind direction

-- | TEETH — a NON-mean-free direction (@e_0@, @Σ = 1@) is REFUSED by @mkMeanFreeChecked@, so a non-@A_7@
-- direction cannot masquerade as the recovered complement. This is what makes HALF 2 non-vacuous: without
-- a refusal, "the blind direction is @A_7@" would be a claim with no false witness. Delegates
-- "SixFour.Spec.BlindComplementIsA7" @lawNonLatticeDirectionRefused@.
lawNonA7DirectionCannotMasquerade :: Bool
lawNonA7DirectionCannotMasquerade = lawNonLatticeDirectionRefused

-- | The DOF accounting closes: @9 identified + 15 blind = 24@ total. The checkerboard the value head
-- recovers lives among the 15 blind DOF (and, in the overlap, in @A_7@). HONEST scope: this is the
-- cell-identified vs cell-blind split, NOT a claim that all 15 blind DOF are lattice (cf.
-- "SixFour.Spec.BlindComplementGeometry": @S^⊥@ 15-DOF and @A_7@ 21-DOF are distinct).
lawDofAccountingCloses :: Bool
lawDofAccountingCloses =
     bridgeIdentifiedDof == 9
  && bridgeBlindDof == 15
  && bridgeIdentifiedDof + bridgeBlindDof == bridgeTotalDof

-- | THE FOLD — the master theorem's identifiability conjunct AND the @A_7@-membership of the recovered
-- complement, as ONE law. This is the bridge the owner asked for: it makes the @A_7@ algebra (load-bearing
-- only via @BlindComplementIsA7@'s @mkMeanFreeChecked@ typed consumer) a guard on the IDENTIFIABILITY
-- teaching of the master theorem, ready to be inlined into @ParadigmSoundness.teachingIdentifiability@.
-- Drop EITHER half and the conjunction is FALSE: without HALF 1 the value head does not identify the
-- complement; without HALF 2 the recovered direction is not witnessed as a lattice vector (and the refusal
-- teeth go unused). It introduces NO new algebra — it WIRES the existing typed consumer into the capstone.
lawIdentifiabilityComplementIsA7 :: Bool
lawIdentifiabilityComplementIsA7 =
     lawMasterIdentifiabilityHolds
  && lawRecoveredComplementAdmittedAsA7
  && lawNonA7DirectionCannotMasquerade
  && lawDofAccountingCloses

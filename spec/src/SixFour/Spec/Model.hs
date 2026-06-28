{- |
Module      : SixFour.Spec.Model
Description : THE SINGLE SOURCE for "the model" — the one place to start reading the Held-Out Full-Matrix H-JEPA. It assembles the model boundary (the I/O contract the UI paints into, the trainer targets, and the 256³ builds from), re-exports the load-bearing laws that survived the model-spec unification, PINS the two CONTRACT-ONLY honesty markers into the build, and carries the authoritative load-bearing-vs-contract taxonomy as a checked ledger.

This module exists because the model spec had accreted across many exploration pivots, with two grand
capstones (@lawModelWillLearn@, @lawParadigmIsSound@) whose NAMES asserted an empirical outcome the project
has never demonstrated (the only training run floored; the full-matrix trainer does not yet exist). The
unification (1) retired those overclaims — @lawModelWillLearn@ → 'lawJointObjectiveIdentifiesFullPalette'
(IDENTIFIABILITY, not reachability); @lawParadigmIsSound@ → 'lawParadigmIsStructurallySound' (STRUCTURAL,
not trained) — and (2) deleted the purely-definitional time-axis tautologies. This module is where the
honest boundary is made load-bearing: it references the two CONTRACT-ONLY markers as values, so removing
either one breaks the build, and 'lawNoEmpiricalOverclaim' fails if a "the-model-works" law is re-introduced
as load-bearing.

THE ARCHITECTURE (frozen per @docs/NEXT-STEPS.md@; this module consolidates, it does not redesign):

  INPUT  = 'ModelInput' = the 64³ capture ("SixFour.Spec.Upscale256" @UpscaleInput@)
           + the user's 16³ nine-channel paint ("SixFour.Spec.CellNudge" 'CellBudget')
           + the φ6 gauge toggle.
  OUTPUT = 'ModelOutput' = per-frame palettes (VALUE) + index planes (CONTENT) = GIF89a directly.
  FLOOR  = zero paint ⇒ 'buildFloor' = the deterministic "SixFour.Spec.Upscale256" super-res (byte-exact).
  LEARNED= the PonderNet invention rides ABOVE the floor where the user paints; one painted 16³ cell
           governs its 4096-leaf 256³ subtree.

WHAT IS PROVEN vs WHAT IS NOT (read 'modelLawLedger'):
  * LOAD-BEARING (real theorems over the real kernels): the renderable boundary, the byte-exact floor,
    the joint-objective IDENTIFIABILITY of the full palette (conditional on @w_value > 0@), STRUCTURAL
    soundness, and the above-floor Q16 margin reachability.
  * DIMENSIONAL IDENTITY: 'lawCellGovernsSuperResSubtree' (@(256/16)³ = 4096@) — true and load-bearing for
    the paint→subtree scale, but a compile-time constant identity, not a behavioural theorem.
  * STRUCTURAL WITNESS: the held-out time axis is a minimal @Int@ witness (the scale axis is a real-kernel
    witness); the strength is the motion-ambiguity ARGUMENT, not the toy computation.
  * CONTRACT-ONLY (UNPROVEN UNTIL TRAINED): that gradient descent actually REACHES the identified optimum
    on a real captured corpus. The new full-matrix trainer does not exist; the only run to date floored
    (held-out @L_band ≈ 5.4e-4@ vs the zero floor @≈ 3.5e-4@). See @SIXFOUR-MODEL.md@ and @docs/NEXT-STEPS.md@ (W4.3).

Pure-spec, GHC-boot-only, emits no golden. Laws @once@-tested in "Properties.Model".
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none
module SixFour.Spec.Model
  ( -- * The model boundary (the one I/O contract — start here)
    ModelInput(..)
  , ModelOutput
  , buildFloor
  , renderFrame
  , neutralNudge
    -- * The paint surface
  , CellBudget
  , paintCellPair
  , cellSubtreeLeaves
    -- * Load-bearing laws (re-exported from the proving modules)
  , lawOutputIsPerFrameValueContent
  , lawNeutralNudgeIsAllFloor
  , lawJointObjectiveIdentifiesFullPalette
  , lawParadigmIsStructurallySound
  , lawHeldOutReplacesMasking
    -- * The honest boundary (CONTRACT-ONLY markers — pinned here so they cannot silently vanish)
  , contractDescentOnRealDataUnproven
  , contractEmpiricalSoundnessUnproven
  , contractAboveFloorMarginMeasured
    -- * The model-law taxonomy (the authoritative load-bearing-vs-contract ledger)
  , LawStatus(..)
  , modelLawLedger
  , lawNoEmpiricalOverclaim
  ) where

import Data.List (isInfixOf)

import SixFour.Spec.ModelIO
  ( ModelInput(..), ModelOutput, buildFloor, renderFrame, neutralNudge
  , lawOutputIsPerFrameValueContent, lawNeutralNudgeIsAllFloor )
import SixFour.Spec.CellNudge
  ( CellBudget, paintCellPair, cellSubtreeLeaves )
import SixFour.Spec.LearnabilityTheorem
  ( lawJointObjectiveIdentifiesFullPalette, contractDescentOnRealDataUnproven )
import SixFour.Spec.ParadigmSoundness
  ( lawParadigmIsStructurallySound, contractEmpiricalSoundnessUnproven )
import SixFour.Spec.HeldOutTarget
  ( lawHeldOutReplacesMasking )
import SixFour.Spec.AboveFloorMargin
  ( contractAboveFloorMarginMeasured )

-- | The honesty status of a model-spec law. The taxonomy a green gate must be read THROUGH: a passing
-- 'LoadBearing' law is a real theorem; a passing 'ContractOnly' marker carries no truth value at all.
data LawStatus
  = LoadBearing          -- ^ a real theorem over the real kernels (identifiability, the floor, the boundary).
  | DimensionalIdentity  -- ^ a true compile-time constant identity (e.g. @(256/16)³ = 4096@), load-bearing but not behavioural.
  | StructuralWitness    -- ^ a minimal witness whose strength is the ARGUMENT, not the toy computation (the held-out time axis).
  | ContractOnly         -- ^ NOT proven — the documented obligation, unproven until trained. Carries no truth value.
  deriving (Eq, Show)

-- | THE AUTHORITATIVE LEDGER: every load-bearing claim of the model spec, tagged with how much weight it
-- can actually carry. This is the one place to learn what a green gate does and does NOT mean for the model.
modelLawLedger :: [(String, LawStatus)]
modelLawLedger =
  [ ("lawOutputIsPerFrameValueContent",          LoadBearing)         -- the output is renderable per-frame value × content
  , ("lawNeutralNudgeIsAllFloor",                LoadBearing)         -- zero paint = the byte-exact deterministic floor
  , ("lawJointObjectiveIdentifiesFullPalette",   LoadBearing)         -- rank-3 + value head identify the full palette (w_value>0)
  , ("lawValueHeadIdentifiesComplement",         LoadBearing)         -- the checkerboard-parity complement witness (net-new)
  , ("lawParadigmIsStructurallySound",           LoadBearing)         -- STRUCTURAL soundness (identifiable, convergent readout, no-collapse, byte-exact)
  , ("lawAboveFloorMarginReachable",             LoadBearing)         -- a 1-Q16-LSB invention survives the commit and moves the cube
  , ("lawCellGovernsSuperResSubtree",            DimensionalIdentity) -- (256/16)³ = 4096: the self-similar paint→subtree scale
  , ("lawHeldOutReplacesMasking",                StructuralWitness)   -- scale axis = real kernels; time axis = minimal Int witness
  , ("contractDescentOnRealDataUnproven",        ContractOnly)        -- GD reaching the optimum on real data: UNPROVEN (only run floored)
  , ("contractEmpiricalSoundnessUnproven",       ContractOnly)        -- the trained model working on real captures: UNPROVEN
  , ("contractAboveFloorMarginMeasured",         ContractOnly)        -- the trained up-rung's detail surviving the Q16 commit: UNMEASURED (W4.3)
  ]

-- | THE HONESTY META-LAW: the model spec contains NO law whose name claims the model is trained or works,
-- AND every empirical obligation is tagged 'ContractOnly'. This is the structural guard against a
-- "lying-green" regression: re-introduce a @lawModelWillLearn@-style claim as 'LoadBearing' and this fails.
--
-- It also REFERENCES the two contract markers as values, so deleting either marker breaks the build here —
-- the honest boundary cannot be quietly removed. Teeth: the @banned@ substrings are real (a load-bearing
-- entry named with any of them fails), and the ledger must actually carry the two contract-only markers.
lawNoEmpiricalOverclaim :: Bool
lawNoEmpiricalOverclaim =
     contractDescentOnRealDataUnproven == ()       -- pin the LearnabilityTheorem marker into the build
  && contractEmpiricalSoundnessUnproven == ()      -- pin the ParadigmSoundness marker into the build
  && contractAboveFloorMarginMeasured == ()        -- pin the AboveFloorMargin (W4.3) marker into the build
  && all (not . overclaims . fst) loadBearing      -- no load-bearing law NAME claims the model trains/works
  && map fst contractOnly == [ "contractDescentOnRealDataUnproven"
                             , "contractEmpiricalSoundnessUnproven"
                             , "contractAboveFloorMarginMeasured" ]  -- the markers ARE in the ledger, tagged ContractOnly
  where
    loadBearing  = filter ((== LoadBearing) . snd) modelLawLedger
    contractOnly = filter ((== ContractOnly) . snd) modelLawLedger
    overclaims n = any (`isInfixOf` n) ["WillLearn", "ModelWorks", "IsTrained", "ModelLearns"]

{- |
Module      : SixFour.Spec.SelfSupervisedRung
Description : The SELF-SUPERVISION split — the two rungs carry two KINDS of self-supervision: the within-capture rung (16³→64³) manufactures an EXACT label from the data itself via the reversible lift (a masked-band regression target), while the beyond-capture rung (64³→256³) has NO label and self-supervises by CONSISTENCY (the re-downsample gate). One operator, two supervisions.

This is a JEPA: the learning is self-supervised — no human annotation ever enters. This
module types WHERE the supervision signal comes from at each rung, the question the
user's "think about self-supervised learning" asks. The answer is that SixFour has TWO
self-supervision regimes, and they are exactly the two rungs:

  * __'HeldRung' (16³→64³, within capture) — RECONSTRUCTION self-supervision.__ Because
    the @(2×2):(2×2)→1@ lift is REVERSIBLE (@refine . split == id@), splitting a real
    capture MANUFACTURES an EXACT label: the held detail band. The masked-band predictor
    ("SixFour.Spec.MaskedBandPrediction") regresses that band — a target the DATA supplied,
    not a human. 'heldLoss' is the signal. This is the classic masked-prediction (MAE/
    I-JEPA) flavour, but the label is BIT-EXACT, not a pixel approximation.

  * __'InventedRung' (64³→256³, beyond capture) — CONSISTENCY self-supervision.__ Above
    the substrate there is NO captured high-frequency, so NO label can be manufactured.
    Supervision shifts to INVARIANCE: the invented detail is free, but the reconstruction
    must re-downsample to the SAME coarse band ("SixFour.Spec.RedownsampleGate" 'passesGate'
    — this module is its first consumer). 'inventedAccepts' is the signal. Self-supervision
    by consistency, not by reconstruction.

The OPERATOR is the same on both rungs (the 63-param @θ_B@,
"SixFour.Spec.MaskedBandPrediction" @lawMaskedReusesOnBothRungs@); only the SUPERVISION
differs ('lawOneOperatorTwoSupervisions'). This is what makes the two rungs RELATED rather
than two separate models: one self-supervised learner, two label regimes.

== The laws

  * 'lawSupervisionMatchesRung' — the dichotomy is total and exclusive: Held ⇒ a held
    target exists ('SelfSupervisedLoss'); Invented ⇒ none ('ConsistencyGate').
  * 'lawHeldLabelIsDataManufactured' — the Held label is generated FROM the capture by the
    reversible split (no annotation): @refine . split == id@ (delegates
    "SixFour.Spec.SuccessiveRefinement" @lawRefineRoundTrip@). The data labels itself.
  * 'lawInventedScoredByConsistency' — the label-free rung is scored by 'passesGate', which
    REJECTS coarse drift yet ACCEPTS invented high-frequency (delegates the gate's teeth).
  * 'lawOneOperatorTwoSupervisions' — one shared predictor, two distinct supervisions.
  * 'lawSelfSupervisedLabelIsLearnable' — the manufactured Held label carries learnable
    structure: training drives 'heldLoss' down (it is signal, not noise).

Additive: composes "SixFour.Spec.MaskedBandPrediction", "SixFour.Spec.SuccessiveRefinement",
and "SixFour.Spec.RedownsampleGate" (its first consumer). Re-pins NOTHING; GHC-boot-only.
The 'Held'\/'Invented' naming follows "SixFour.Spec.SelfSimilarReconstruct" @DetailSource@
(the detail-provenance analogue at the band level). Laws QuickCheck'd in
"Properties.SelfSupervisedRung".
-}
-- COMPARTMENT: MLX-MODEL | tag:DeviceTag | STRADDLER
module SixFour.Spec.SelfSupervisedRung
  ( -- * The two rungs and their supervision kinds
    Rung(..)
  , isHeld
  , isInvented
  , Supervision(..)
  , supervisionOf
  , hasHeldTarget
    -- * The two scorers (the supervision signals)
  , heldLoss
  , inventedAccepts
    -- * Laws (QuickCheck'd in @Properties.SelfSupervisedRung@)
  , lawSupervisionMatchesRung
  , lawHeldLabelIsDataManufactured
  , lawInventedScoredByConsistency
  , lawOneOperatorTwoSupervisions
  , lawSelfSupervisedLabelIsLearnable
  ) where

import SixFour.Spec.OctreeCell           (Detail)
import SixFour.Spec.OctreeGenome          (octreeLeafCount)
import SixFour.Spec.SuccessiveRefinement  (split, refine)
import SixFour.Spec.RedownsampleGate
  ( passesGate, redownsample, lawGateRejectsCoarseDrift, lawGateIgnoresInventedDetail )
import SixFour.Spec.MaskedBandPrediction
  ( MaskedBandExample, maskedBandLoss, trainBandJoint, zeroParamsB
  , lawMaskedReusesOnBothRungs, lawTransferRecoversGapUnderSelfSimilarity )

-- | The two rungs of the self-similar pair, named by their epistemic status. 'HeldRung'
-- is within capture (a label can be manufactured); 'InventedRung' is beyond capture (no
-- label exists).
data Rung = HeldRung | InventedRung
  deriving (Eq, Show)

-- | Is this the within-capture (label-manufacturing) rung?
isHeld :: Rung -> Bool
isHeld HeldRung     = True
isHeld InventedRung = False

-- | Is this the beyond-capture (label-free, consistency-scored) rung?
isInvented :: Rung -> Bool
isInvented = not . isHeld

-- | The KIND of self-supervision a rung carries: a regression loss against a
-- data-manufactured target, or a consistency gate when no target exists.
data Supervision
  = SelfSupervisedLoss   -- ^ a held target exists; score by 'heldLoss' (the data's own label).
  | ConsistencyGate      -- ^ no target; score by 'inventedAccepts' (re-downsample consistency).
  deriving (Eq, Show)

-- | The supervision a rung uses. The WHOLE thesis of this module: the rung selects the
-- supervision, never the operator.
supervisionOf :: Rung -> Supervision
supervisionOf HeldRung     = SelfSupervisedLoss
supervisionOf InventedRung = ConsistencyGate

-- | Does this rung have a data-manufactured target to regress onto? True only within
-- capture (the 'HeldRung').
hasHeldTarget :: Rung -> Bool
hasHeldTarget r = supervisionOf r == SelfSupervisedLoss

-- | The HELD rung's scorer: the self-supervised masked-band loss against the
-- data-manufactured target (= "SixFour.Spec.MaskedBandPrediction" @maskedBandLoss@).
heldLoss :: [Double] -> MaskedBandExample -> Double
heldLoss = maskedBandLoss

-- | The INVENTED rung's scorer: re-downsample consistency (= "SixFour.Spec.RedownsampleGate"
-- @passesGate k given cube@ — the reconstruction's coarse band, re-pooled @k@ levels, must
-- equal the @given@ rung). The label-free rung's self-supervision-by-invariance signal.
inventedAccepts :: Int -> [Int] -> [Int] -> Bool
inventedAccepts = passesGate

-- ============================================================================
-- Laws (predicates; QuickCheck'd in Properties.SelfSupervisedRung)
-- ============================================================================

-- | THE DICHOTOMY (the structural keystone): the supervision split is total and
-- exclusive. The 'HeldRung' has a data-manufactured target ('SelfSupervisedLoss'); the
-- 'InventedRung' has none ('ConsistencyGate'). Teeth: a model that claimed a held target
-- for the invented rung (scoring against a fiction) collapses the two arms and fails the
-- middle conjuncts.
lawSupervisionMatchesRung :: Bool
lawSupervisionMatchesRung =
     supervisionOf HeldRung     == SelfSupervisedLoss
  && supervisionOf InventedRung == ConsistencyGate
  && hasHeldTarget HeldRung
  && not (hasHeldTarget InventedRung)
  && supervisionOf HeldRung /= supervisionOf InventedRung

-- | SELF-SUPERVISION, made precise: the Held rung's label is MANUFACTURED FROM THE CAPTURE
-- by the reversible lift — no human annotation. Splitting a real capture and refining it
-- back recovers the capture bit-for-bit (@refine . split == id@), so the held detail used
-- as the regression target is a FAITHFUL, data-generated label. Delegates
-- "SixFour.Spec.SuccessiveRefinement" @lawRefineRoundTrip@. Teeth: were the split not
-- reversible, the "label" would be fiction and this would fail. (Guarded to a valid split.)
lawHeldLabelIsDataManufactured :: Int -> Int -> [Int] -> Bool
lawHeldLabelIsDataManufactured k d cap =
  not (d >= 0 && k >= 0 && k <= d && length cap == octreeLeafCount d)
    || refine d (split k d cap) == take (octreeLeafCount d) cap

-- | The label-free 'InventedRung' is scored by CONSISTENCY: 'inventedAccepts'
-- ('passesGate') REJECTS a drifted coarse band yet ACCEPTS invented high-frequency, so
-- genuine super-res is never punished but coarse-band confirmation-bias is caught. This
-- module is the FIRST consumer of "SixFour.Spec.RedownsampleGate" @passesGate@; the teeth
-- are delegated to @lawGateRejectsCoarseDrift@ / @lawGateIgnoresInventedDetail@, and the
-- final conjunct exercises 'inventedAccepts' directly on a self-consistent reconstruction.
lawInventedScoredByConsistency :: Int -> Int -> [Int] -> Bool
lawInventedScoredByConsistency k d fine =
     supervisionOf InventedRung == ConsistencyGate           -- label-free ⇒ gate-scored
  && lawGateRejectsCoarseDrift k d fine                      -- REJECTS coarse drift (teeth)
  && lawGateIgnoresInventedDetail k d fine                   -- ACCEPTS invented high-freq
  && (not (d >= 1 && k >= 1 && k <= d && length fine == octreeLeafCount d)
       || inventedAccepts k (redownsample k fine) fine)      -- ACCEPTS a self-consistent recon

-- | ONE OPERATOR, TWO SUPERVISIONS — what makes the rungs RELATED, not separate models.
-- The two scorers genuinely DIFFER (@SelfSupervisedLoss /= ConsistencyGate@), yet the
-- predictor is the SAME 63-param @θ_B@, pinned two ways:
--
--   * STRUCTURAL — @lawMaskedReusesOnBothRungs@ (one operator that CONSUMES sibling context,
--     and the self-similar octant distance @levelsBetween 64 16 == levelsBetween 256 64@).
--     This is where the option-B "siblings matter" claim lives.
--   * NUMERIC GENERALISATION — @lawTransferRecoversGapUnderSelfSimilarity@: a θ_B trained on
--     the DOWN-rung coarse range recovers most of the floor→oracle gap on the UNSEEN UP-rung
--     range. NOTE this is GENERALISATION ACROSS COARSE INPUT RANGES, not sibling reuse: the
--     transfer fixtures zero the siblings (band 0 masked, bands 1–6 = 0), so a coarse-only
--     model would also pass it. The sibling-consumption teeth are carried by the structural
--     conjunct above and by @lawMaskedConsumesSiblingContext@, NOT here.
--
-- Teeth: a single-rung operator fails the structural conjunct; a θ that did not generalise
-- across the input range fails the numeric conjunct; a collapsed supervision fails the first.
lawOneOperatorTwoSupervisions :: Bool
lawOneOperatorTwoSupervisions =
     supervisionOf HeldRung /= supervisionOf InventedRung    -- the supervisions differ
  && lawMaskedReusesOnBothRungs                              -- STRUCTURAL: one operator (consumes siblings), both rungs
  && lawTransferRecoversGapUnderSelfSimilarity               -- NUMERIC: θ generalises across coarse input ranges

-- | The data-manufactured Held label carries LEARNABLE structure (it is signal, not
-- noise): from the floor, training on the held example drives 'heldLoss' strictly down.
-- Teeth: a label that was random noise could not be fit; this uses a real off-floor target
-- and shows @trainBandJoint@ reduces the self-supervised loss. (@w@ varies the target.)
lawSelfSupervisedLabelIsLearnable :: Int -> Bool
lawSelfSupervisedLabelIsLearnable w =
  let v   = 20000
      tgt = 6000 + (abs w `mod` 12000)                       -- an off-floor data-manufactured target
      det = (tgt, 0, 0, 0, 0, 0, 0) :: Detail                -- band 0 is the held target
      ex  = (v, det, 0)
      l0  = heldLoss zeroParamsB ex
      lN  = heldLoss (trainBandJoint 400 [ex]) ex
  in l0 <= 0 || lN < l0

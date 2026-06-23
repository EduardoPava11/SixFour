{- |
Module      : SixFour.Spec.MidLatentCrossPrediction
Description : The MIDPOINT-LOCAL cross-encoder objective — predict a masked band of one encoder's 32³ latent from the visible 32³ context of the other. A distinct objective sited at the organisable midpoint, NOT the 16³→256³ inter-level hop; data-manufactured target (no EMA).

The dual-encoder objective ("SixFour.Spec.DualEncoderJepa") runs at the surfaced rungs. This
module sites a SECOND, midpoint-local instance at the never-surfaced 32³ latent (the
organisable level "SixFour.Spec.RungPivot" / "SixFour.Spec.HJepaLevels" prove is where the net
is free to organize). The top-down (16³ plan) and bottom-up (64³) flows meet at 32³, so
cross-encoder conditioning there is paper-plausible.

  * 'lawMidCrossEncoderStrictlyHelps' — KEYSTONE: at the midpoint, joint (A,B) context strictly
    beats B-context alone when A resolves a collision, AND ties when A is redundant (BOTH
    clauses, mirroring "SixFour.Spec.DualEncoderJepa" @lawCrossEncoderContextStrictlyHelps@ on
    fresh midpoint witnesses so it binds the midpoint objective, not just aliases the keystone).
  * 'lawMidObjectiveIsMidpointLocal' — the objective sits at the organisable scale midpoint
    (delegates "SixFour.Spec.HJepaLevels" @lawScaleIsTheSpine@ + "SixFour.Spec.RungPivot"
    @lawIntermediateIsMidLevel@); it does NOT delegate @lawInterLevelPredictorIsCrossScale@ (that
    is the distinct 16³→256³ hop, preserved separately and running THROUGH this midpoint).
  * 'lawMidTargetIsDataManufactured' — no EMA at the midpoint (delegates
    "SixFour.Spec.JepaTarget").

Additive: read-only delegations; reuses the "SixFour.Spec.DualEncoderJepa" loss machinery.
GHC-boot-only. Laws QuickCheck'd in "Properties.MidLatentCrossPrediction".
-}
-- COMPARTMENT: MLX-MODEL | tag:MacTag
module SixFour.Spec.MidLatentCrossPrediction
  ( -- * Laws (QuickCheck'd in @Properties.MidLatentCrossPrediction@)
    lawMidCrossEncoderStrictlyHelps
  , lawMidObjectiveIsMidpointLocal
  , lawMidTargetIsDataManufactured
  ) where

import SixFour.Spec.DualEncoderJepa (DualExample(..), bOnlyLoss, jointLoss)
import qualified SixFour.Spec.HJepaLevels as HJ
import qualified SixFour.Spec.RungPivot   as RP
import qualified SixFour.Spec.JepaTarget  as JT

-- ============================================================================
-- Laws (predicates; QuickCheck'd in Properties.MidLatentCrossPrediction)
-- ============================================================================

-- | KEYSTONE: at the 32³ midpoint, the joint (A,B) cross-encoder context STRICTLY beats the
-- B-latent context alone when Encoder A's midpoint latent resolves a collision B leaves, and
-- TIES when A is redundant. Carries BOTH clauses (strict-help + redundancy tooth), on fresh
-- midpoint witnesses, so it binds the midpoint objective rather than aliasing the surfaced-rung
-- keystone. Reuses the "SixFour.Spec.DualEncoderJepa" information-floor losses.
lawMidCrossEncoderStrictlyHelps :: Bool
lawMidCrossEncoderStrictlyHelps =
  let -- same B-latent context (7), A-latent context resolves it, distinct held bands
      helpful   = [ DualExample 7 0 100, DualExample 7 1 200 ]
      -- A-latent context redundant (does not vary): no free win
      redundant = [ DualExample 7 0 100, DualExample 7 0 200 ]
  in jointLoss helpful == 0                         -- A fully resolves the masked midpoint band
     && jointLoss helpful < bOnlyLoss helpful       -- cross-encoder strictly helps at the midpoint
     && bOnlyLoss helpful > 0                        -- B-latent alone cannot (the collision)
     && jointLoss redundant == bOnlyLoss redundant   -- teeth: no win when A is redundant

-- | The objective is MIDPOINT-LOCAL: it sits at the organisable scale midpoint, the unique axis
-- carrying a free intermediate (delegates "SixFour.Spec.HJepaLevels" @lawScaleIsTheSpine@) at
-- octree depth ±1 of the 64³ pivot (delegates "SixFour.Spec.RungPivot"
-- @lawIntermediateIsMidLevel@). It is deliberately NOT the 16³→256³ inter-level hop, so it does
-- NOT delegate @lawInterLevelPredictorIsCrossScale@.
lawMidObjectiveIsMidpointLocal :: Bool
lawMidObjectiveIsMidpointLocal = HJ.lawScaleIsTheSpine && RP.lawIntermediateIsMidLevel

-- | The midpoint target is the bit-exact data-manufactured held band, not a learned EMA
-- target-encoder output: no EMA, no collapse (delegates "SixFour.Spec.JepaTarget").
lawMidTargetIsDataManufactured :: Bool
lawMidTargetIsDataManufactured = JT.lawNoTargetEncoderNoEma && JT.lawCollapseIsRejected

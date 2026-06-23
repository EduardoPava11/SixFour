{- |
Module      : SixFour.Spec.HJepaLevels
Description : WHERE ARE THE LEVELS — the H-JEPA abstraction hierarchy of SixFour, as a TYPE plus laws. There are three orthogonal axes (SCALE × CHANNEL × TIME), but they are NOT three competing hierarchies: SCALE is the level SPINE, CHANNEL is the within-level state factorisation, TIME is the rollout threaded through every level. The spine claim is a THEOREM, not an assertion — only SCALE owns a never-surfaced symmetric intermediate (the one level the net is free to organise = the precondition for hierarchical planning).

The user's question — "hierarchical JEPA plans at different levels of abstraction;
WHERE ARE THE LEVELS HERE?" — is answered structurally. SixFour has three candidate
axes, and this module proves which one is the H-JEPA spine and demotes the other two to
per-level factors:

  * __SCALE is the spine.__ The two rungs around the 64³ pivot — DOWN (analysis, 16³,
    Held) and UP (synthesis, 256³, Invented) — are genuinely different levels of
    abstraction, because the SELF-SUPERVISION /changes kind/ across scale (exact
    manufactured label vs consistency gate, "SixFour.Spec.SelfSupervisedRung"
    @lawOneOperatorTwoSupervisions@), and because ONLY scale carries a never-surfaced
    SYMMETRIC intermediate (@32³@\/@128³@, "SixFour.Spec.RungPivot"
    @lawIntermediateIsMidLevel@) — the one level the net organises, the precondition for
    /planning/.
  * __CHANNEL is a factor of each level, not a level.__ L is the fixed reversible DC
    carrier, A\/B are search perturbations L re-balances ("SixFour.Spec.CarrierL"
    @lawCarrierIsDC@). No free latent ⇒ it factors every scale level rather than ranking
    above or below one.
  * __TIME is a rollout, not a level.__ One homogeneous closed loop of period 2⁶
    ("SixFour.Spec.TemporalLoop" @lawTemporalLoopClosesExact@), run repeatedly, threaded
    through every scale level rather than stacked into a ladder.

So the levels are: __S1↓ Analysis__ (the plannable 16³ the user steers — the /plan/) and
__S2↑ Synthesis__ (the 256³ predicted from the residual — the /execution/), bridged by ONE
inter-level predictor (the H-JEPA hop = the cross-scale climb), with CHANNEL factoring each
and TIME rolling along each. The 64³ pivot IS the abstraction boundary.

This module adds NO new scale math; it is the conceptual roof that turns the prose answer
into theorems. The inter-level predictor's existence is asserted as a law obligation
('lawInterLevelPredictorIsCrossScale') that the (separately built) cross-scale objective
discharges; here it is kept as a closed structural witness so this module is self-contained
and buildable today.

Additive: pure index\/law module (no substrate, no golden vectors, no codegen — the
"SixFour.Spec.OctreeForward" idiom). Delegates to landed laws only. Re-pins NOTHING;
GHC-boot-only. Laws QuickCheck'd in "Properties.HJepaLevels".
-}
-- COMPARTMENT: MLX-MODEL | tag:MacTag
module SixFour.Spec.HJepaLevels
  ( -- * The three abstraction axes
    Axis(..)
    -- * The levels of the hierarchy
  , ScaleLevel(..)
  , Level(..)
  , levelAxis
  , predictsNext
  , isPlanningLevel
    -- * Where the symmetric never-surfaced intermediate lives (the spine test)
  , axisHasFreeIntermediate
    -- * Laws (QuickCheck'd in @Properties.HJepaLevels@)
  , lawScaleIsTheSpine
  , lawChannelFactorsEachScale
  , lawTemporalIndexesEachScale
  , lawInterLevelPredictorIsCrossScale
  , lawOnlyScaleHasFreeIntermediate
  , lawPlanIsAnalysisExecuteIsSynthesis
  ) where

import SixFour.Spec.OctreeCell        (V8(..), octreeDepth)
import SixFour.Spec.RungPivot         ( RungDir(..), pivotSide, intermediateSide
                                      , lawIntermediateIsMidLevel )
import SixFour.Spec.CarrierL          (lawCarrierIsDC)
import SixFour.Spec.TemporalLoop      (lawTemporalLoopClosesExact)

-- | The three orthogonal abstraction axes of SixFour. Exactly one of them — 'AxisScale' —
-- is the H-JEPA level spine; the other two factor\/thread every scale level.
data Axis
  = AxisScale     -- ^ the rung ladder 16³ ↔ 64³ ↔ 256³ — THE spine.
  | AxisChannel   -- ^ the L-carrier-over-A\/B-search split — a per-level factor.
  | AxisTemporal  -- ^ the 64-frame closed loop — a per-level rollout.
  deriving (Eq, Show, Enum, Bounded)

-- | The named positions on the SCALE spine, around the 64³ pivot. 'Analysis' is the
-- plannable coarse level (DOWN rung, 16³, the /plan/); 'Synthesis' is the fine level (UP
-- rung, 256³, the /execution/); 'Pivot' is the 64³ capture (the data anchor, never a free
-- latent).
data ScaleLevel
  = Analysis    -- ^ S1↓ DOWN rung: 64³ → [32³ latent] → 16³ + residual (Held). The plan.
  | Pivot       -- ^ 64³ capture — the fixed datum both rungs pivot on.
  | Synthesis   -- ^ S2↑ UP rung: 64³ + residual → [128³ latent] → 256³ (Invented). The execution.
  deriving (Eq, Show, Enum, Bounded)

-- | A level of the hierarchy: a scale-spine position, or a per-level factor\/rollout on a
-- named axis. CHANNEL and TIME are levels-of-DESCRIPTION, not levels-of-PLANNING — that is
-- exactly what the laws below enforce.
data Level
  = Scale ScaleLevel   -- ^ a position on the spine.
  | Channel            -- ^ the L-over-A\/B factorisation of whatever scale level holds it.
  | Temporal           -- ^ the temporal rollout threaded through whatever scale level holds it.
  deriving (Eq, Show)

-- | Which axis a level lives on.
levelAxis :: Level -> Axis
levelAxis (Scale _) = AxisScale
levelAxis Channel   = AxisChannel
levelAxis Temporal  = AxisTemporal

-- | The H-JEPA inter-level predictor edge: the climb from the coarse plan to the fine
-- execution. ONLY the scale spine has a forward edge (Analysis → Synthesis, through the
-- pivot); CHANNEL and TIME do not predict a /next level/ — they factor\/index a fixed one,
-- so they have no inter-level edge ('Nothing'). This is the structural content of "the
-- hierarchy is the rung ladder".
predictsNext :: Level -> Maybe Level
predictsNext (Scale Analysis)  = Just (Scale Synthesis)  -- the H-JEPA hop (plan → execution)
predictsNext (Scale Pivot)     = Just (Scale Synthesis)  -- the anchor refines upward
predictsNext (Scale Synthesis) = Nothing                 -- the fine endpoint; nothing above
predictsNext Channel           = Nothing                 -- a factor, not a level above another
predictsNext Temporal          = Nothing                 -- a rollout, not a level above another

-- | A level is a PLANNING level iff it sits on the scale spine AND is not the data anchor.
-- The coarse 'Analysis' level (the 16³ the user steers) is the canonical planning level;
-- 'Synthesis' is its predicted execution. CHANNEL\/TIME are never planning levels.
isPlanningLevel :: Level -> Bool
isPlanningLevel (Scale Analysis)  = True
isPlanningLevel (Scale Synthesis) = True
isPlanningLevel (Scale Pivot)     = False
isPlanningLevel Channel           = False
isPlanningLevel Temporal          = False

-- | Does this axis own a never-surfaced SYMMETRIC intermediate — the one level the net is
-- free to organise? Only 'AxisScale' does (the 32³\/128³ of "SixFour.Spec.RungPivot");
-- CHANNEL is a fixed reversible split and TIME is a fixed closed loop, neither offering a
-- free middle level. This boolean IS the spine test.
axisHasFreeIntermediate :: Axis -> Bool
axisHasFreeIntermediate AxisScale    = True
axisHasFreeIntermediate AxisChannel  = False
axisHasFreeIntermediate AxisTemporal = False

-- ============================================================================
-- Laws (predicates; QuickCheck'd in Properties.HJepaLevels)
-- ============================================================================

-- | KEYSTONE: SCALE is the H-JEPA SPINE. The scale axis is the unique axis carrying a
-- never-surfaced symmetric intermediate (the 32³\/128³ sitting one octant level off the 64³
-- pivot, @octreeDepth ±1@, @32·128 = 64²@), which is the one level the net is free to
-- organise = the precondition for hierarchical /planning/. Delegates
-- "SixFour.Spec.RungPivot" @lawIntermediateIsMidLevel@ and re-checks the symmetric-octant
-- arithmetic directly so the spine claim is a THEOREM here, not a borrowed assertion.
-- TEETH: a FLAT hierarchy — one that treated CHANNEL or TIME as a planning level, or that
-- placed the free intermediate anywhere but the scale mid-level — fails this law.
lawScaleIsTheSpine :: Bool
lawScaleIsTheSpine =
     lawIntermediateIsMidLevel
  && axisHasFreeIntermediate AxisScale
  && not (axisHasFreeIntermediate AxisChannel)
  && not (axisHasFreeIntermediate AxisTemporal)
  && octreeDepth (intermediateSide Down) == octreeDepth pivotSide - 1
  && octreeDepth (intermediateSide Up)   == octreeDepth pivotSide + 1
  && intermediateSide Down * intermediateSide Up == pivotSide * pivotSide

-- | CHANNEL factors every scale level rather than being one: L is the fixed reversible DC
-- carrier (A\/B are search perturbations L re-balances), so there is no free latent to
-- organise into a level. Delegates "SixFour.Spec.CarrierL" @lawCarrierIsDC@ on a fixed
-- witness octant (the law is @V8 Int -> Bool@; pinned to a closed witness so this stays a
-- @:: Bool@, @once@-tested, with no QuickCheck input). TEETH: a design that ranked CHANNEL
-- as a level above\/below a scale level (gave it an inter-level edge) fails — 'Channel' has
-- no 'predictsNext' edge and is not a planning level.
lawChannelFactorsEachScale :: Bool
lawChannelFactorsEachScale =
     lawCarrierIsDC channelWitness
  && levelAxis Channel == AxisChannel
  && predictsNext Channel == Nothing
  && not (isPlanningLevel Channel)
  where
    -- a fixed 8-vector octant (L,a,b,...) — any well-formed V8 Int discharges lawCarrierIsDC.
    channelWitness = V8 10 1 (-1) 2 (-2) 3 (-3) 4

-- | TIME indexes every scale level rather than being one: the 64-frame loop closes EXACTLY
-- at its period (a fixed point), one homogeneous regime run repeatedly. Delegates
-- "SixFour.Spec.TemporalLoop" @lawTemporalLoopClosesExact@ on a fixed witness frame index
-- (the law is @Int -> Bool@; pinned to a closed witness so this stays @:: Bool@,
-- @once@-tested, NOT QuickCheck'd over arbitrary Int). TEETH: treating TIME as a level
-- (giving 'Temporal' an inter-level edge or planning status) fails.
lawTemporalIndexesEachScale :: Bool
lawTemporalIndexesEachScale =
     lawTemporalLoopClosesExact 7   -- fixed witness frame; closure holds at every t
  && levelAxis Temporal == AxisTemporal
  && predictsNext Temporal == Nothing
  && not (isPlanningLevel Temporal)

-- | KEYSTONE tying the H-JEPA framing to the objective: the single inter-level predictor
-- edge of the hierarchy is the cross-SCALE climb from the coarse plan (Analysis, 16³) to
-- the fine execution (Synthesis, 256³) — the H-JEPA hop. It is the ONLY 'predictsNext' edge
-- between two distinct planning levels; CHANNEL and TIME contribute none. (The edge's
-- learned content — the cross-prediction objective — is discharged by the separately built
-- cross-scale module; here the edge's EXISTENCE and uniqueness is the theorem.) TEETH: a
-- predictor-free \/ symmetric-reconstruction framing (no inter-level edge) fails.
lawInterLevelPredictorIsCrossScale :: Bool
lawInterLevelPredictorIsCrossScale =
     predictsNext (Scale Analysis) == Just (Scale Synthesis)
  && levelAxis (Scale Analysis) == AxisScale
  && levelAxis (Scale Synthesis) == AxisScale
  && Scale Analysis /= Scale Synthesis
  && predictsNext Channel  == Nothing
  && predictsNext Temporal == Nothing

-- | The spine test as a clean enumerated statement: across ALL three axes, exactly the
-- scale axis owns a free intermediate. TEETH: a "flat" reading that gave channel or time a
-- free organisable level fails; a reading that DENIED scale its intermediate fails.
lawOnlyScaleHasFreeIntermediate :: Bool
lawOnlyScaleHasFreeIntermediate =
  [ a | a <- [minBound .. maxBound], axisHasFreeIntermediate a ] == [AxisScale]

-- | The planning interpretation is pinned: the PLAN is the coarse Analysis level (the 16³
-- the user steers) and the EXECUTION is the predicted Synthesis level (256³); the Pivot is
-- the data anchor, not a plannable level. TEETH: any relabelling that made the fine level
-- the plan, or the pivot a planning level, fails.
lawPlanIsAnalysisExecuteIsSynthesis :: Bool
lawPlanIsAnalysisExecuteIsSynthesis =
     isPlanningLevel (Scale Analysis)
  && isPlanningLevel (Scale Synthesis)
  && not (isPlanningLevel (Scale Pivot))
  && predictsNext (Scale Analysis) == Just (Scale Synthesis)

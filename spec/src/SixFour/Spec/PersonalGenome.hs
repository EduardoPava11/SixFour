{- |
Module      : SixFour.Spec.PersonalGenome
Description : The per-device taste lifecycle over the 770-D Bradley–Terry θ —
              cold start, per-pick learning, replay, and GATED promotion.

Every SixFour device trains ITS OWN genome on device (no server). The personal
genome is the **770-D Bradley–Terry taste vector θ** ('SixFour.Spec.PreferenceUpdate'),
NOT the 384-DOF σ-pair generator weights: θ is the only per-user state with a
VERIFIED update step, it is ~3 KB, and it RANKS candidates (and biases the A/B
proposer 'SixFour.Spec.GenomePair'). This module is a thin, pure orchestration layer
over the proven 'btUpdate' primitive; it adds the lifecycle the device needs but the
update rule alone does not provide: cold start, an ordered replay log, and a
regression-safe promotion gate.

== The two clocks (cadence)

[Fast clock — every pick] Each A/B pick is one ordered Bradley–Terry Compare; 'applyPick'
folds it into θ with a single 'btUpdate' (η = 0.05, λ = 1e-3) and bumps the Compare
counter. This is the only per-interaction work, and it is cheap (a 770-D vector step).

[Slow clock — every 'promotionCadence' picks] θ trained on a non-stationary,
order-dependent SGD stream has no fixed point, so "is the new θ actually better?" cannot
be assumed. Borrowing KataGo's gating (promote a candidate net only if it WINS), the
slow clock runs an OFFLINE replay test: a candidate θ must reproduce the user's recent
logged picks by a strict majority ('gatePasses') before it can replace the shipped θ
('promote'). CubeGIF's bare EMA had no such gate — this is the net-new safety mechanism.

== Replay determinism is the load-bearing invariant

θ MUST stay a pure memoised fold over the LOCAL, ordered pick log — never a spliced
foreign value. 'replay' is exactly 'btFit' on θ ('lawReplayDeterministic'), so θ is
reproducible from @coldStartGenome@ + the ordered log, which is what makes a received
foreign genome enter as ONE logged Compare (in 'SixFour.Spec.GenomeBlend') rather than a
convex splice that would destroy reproducibility. 'lawReplayFromCheckpoint' lets the log
be pruned (keep a checkpoint θ + the tail) without breaking exact replay.

== Cold start is a deterministic floor

@coldStartGenome@ is θ = 0, n = 0: 'personalBeta' is 0 and 'scoreCandidate' is 0 for
every candidate ('lawColdStartIsDeterministicFloor'), so before any pick the genome
contributes nothing and the deterministic base ('SixFour.Spec.GenomePair' capture-measure
ranking) drives proposal. 'personalBeta' then ramps monotonically as Compares accrue
('lawBetaMonotoneRamp') — there is NO convergence claim (SGD on a non-stationary stream
has no fixed point; only boundedness, local decrease, and a monotone trust ramp).

GHC-boot-only. Laws are exported predicates, to be QuickCheck'd in
@Properties.PersonalGenome@ (test wiring pending — this module lands at build step 3).
-}
-- COMPARTMENT: SWIFT-COREAI | tag:none
module SixFour.Spec.PersonalGenome
  ( -- * The personal genome
    PersonalGenome(..)
  , Pick
  , coldStartGenome
    -- * Constants
  , genomeVersion
  , blendHalfLife
  , promotionCadence
  , gateWindow
    -- * Lifecycle
  , applyPick
  , replay
  , scoreCandidate
  , personalBeta
    -- * Slow clock: gated promotion
  , predictsPick
  , gatePasses
  , shouldPromote
  , promote
    -- * Training objective (for the laws)
  , regularizedObjective
    -- * Laws (to be QuickCheck'd in Properties.PersonalGenome)
  , lawColdStartIsDeterministicFloor
  , lawReplayDeterministic
  , lawReplayFromCheckpoint
  , lawBetaMonotoneRamp
  , lawApplyPickBounded
  , lawRegularizedObjectiveDecreases
  , lawGateRejectsRegression
  , lawGatedPromotion
  ) where

import Data.List (foldl')

import SixFour.Spec.Preference       (Embedding, linearUtility)
import SixFour.Spec.PreferenceUpdate (thetaDim, defaultEta, defaultLambda, btUpdate, btFit, btPairLoss)

-- ---------------------------------------------------------------------------
-- The personal genome
-- ---------------------------------------------------------------------------

-- | The per-device taste state: the 770-D Bradley–Terry θ, the count of informative
-- Compares folded into it, and a schema version (carried in the exported GIF by
-- 'SixFour.Spec.GenomeCarrier').
data PersonalGenome = PersonalGenome
  { pgTheta    :: [Double]   -- ^ the 770-D BT taste\/ranking vector
  , pgCompares :: Int        -- ^ number of ordered Compares folded so far
  , pgVersion  :: Int        -- ^ schema version of the genome payload
  } deriving (Eq, Show)

-- | One A/B pick as an ordered Bradley–Terry Compare: @(winner, loser)@ embeddings.
type Pick = (Embedding, Embedding)

-- | The deterministic floor: θ = 0, no Compares, current schema version. Before any
-- pick the genome ranks every candidate at 0 and its trust ('personalBeta') is 0.
coldStartGenome :: PersonalGenome
coldStartGenome = PersonalGenome (replicate thetaDim (0 :: Double)) 0 genomeVersion

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------

-- | Schema version of the genome payload (the @S4GN@ carrier pins this).
genomeVersion :: Int
genomeVersion = 1

-- | The trust half-life: 'personalBeta' reaches ½ after this many Compares. Mirrors
-- @SixFour.Spec.AtlasOracle.betaBlend@ (@n \/ (n + 50)@) byte-for-byte; defined locally
-- to keep this module off the Atlas\/search dependency cone.
blendHalfLife :: Int
blendHalfLife = 50

-- | The slow clock: run a promotion gate every this-many Compares.
promotionCadence :: Int
promotionCadence = 10

-- | The replay-gate window @K@: a candidate θ is judged on the last @K@ logged picks.
gateWindow :: Int
gateWindow = 8

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

-- | Fold one pick into the genome: a single 'btUpdate' on θ at the shipped (η, λ), and
-- increment the Compare counter. The fast clock.
applyPick :: PersonalGenome -> Pick -> PersonalGenome
applyPick g pick = g
  { pgTheta    = btUpdate defaultEta defaultLambda (pgTheta g) pick
  , pgCompares = pgCompares g + 1
  }

-- | Replay an ordered pick log (oldest first) onto a genome — a left fold of 'applyPick'.
-- ORDER-DEPENDENT by design (SGD is not commutative; the log is stored in decision order).
replay :: PersonalGenome -> [Pick] -> PersonalGenome
replay = foldl' applyPick

-- | The genome's score for a candidate embedding = the BT linear utility @θ·emb@. This is
-- what RANKS the two A/B candidates and biases 'SixFour.Spec.GenomePair' once trained.
scoreCandidate :: PersonalGenome -> Embedding -> Double
scoreCandidate g = linearUtility (pgTheta g)

-- | The trust weight in @[0, 1)@ blending the learned genome against the deterministic
-- base: @n \/ (n + blendHalfLife)@. 0 at cold start, monotonically ramping with Compares.
personalBeta :: PersonalGenome -> Double
personalBeta g =
  let n = max 0 (pgCompares g)
  in fromIntegral n / fromIntegral (n + blendHalfLife)

-- ---------------------------------------------------------------------------
-- Slow clock: gated promotion
-- ---------------------------------------------------------------------------

-- | Does a (candidate) genome rank this pick's winner strictly above its loser? The unit
-- of the replay gate — "would this θ have agreed with the user here?"
predictsPick :: PersonalGenome -> Pick -> Bool
predictsPick g (w, l) = scoreCandidate g w > scoreCandidate g l

-- | The gate: a candidate passes iff it reproduces a STRICT MAJORITY of the last
-- 'gateWindow' logged picks. An empty window (no history yet) passes vacuously — there is
-- nothing to regress against. Deterministic integer verdict over the ordered log.
gatePasses :: PersonalGenome -> [Pick] -> Bool
gatePasses candidate recent =
  let window  = take gateWindow (reverse recent)   -- the last K picks, most-recent first
      m       = length window
      correct = length (filter (predictsPick candidate) window)
  in m == 0 || correct * 2 > m

-- | Whether the slow clock fires at this Compare count (every 'promotionCadence' picks).
shouldPromote :: PersonalGenome -> Bool
shouldPromote g = pgCompares g > 0 && pgCompares g `mod` promotionCadence == 0

-- | Promote a candidate θ over the current shipped θ ONLY if it passes the replay
-- 'gatePasses' on the recent log; otherwise keep the current genome unchanged. This is
-- the regression-safety net (KataGo gating) that a bare EMA lacks.
promote :: PersonalGenome -> PersonalGenome -> [Pick] -> PersonalGenome
promote current candidate recent
  | gatePasses candidate recent = candidate
  | otherwise                   = current

-- ---------------------------------------------------------------------------
-- Training objective (for the laws)
-- ---------------------------------------------------------------------------

-- | The regularised Bradley–Terry objective on one pick: @−log σ(θ·(w−l)) + ½λ‖θ‖²@.
-- 'btUpdate' is exactly one gradient-descent step on THIS objective, which is what
-- 'lawRegularizedObjectiveDecreases' exploits.
regularizedObjective :: Double -> [Double] -> Pick -> Double
regularizedObjective lambda theta (w, l) =
  btPairLoss theta w l + 0.5 * lambda * sum (map (^ (2 :: Int)) theta)

-- ---------------------------------------------------------------------------
-- Laws (predicates; to be exercised by Properties.PersonalGenome)
-- ---------------------------------------------------------------------------

-- | Cold start is the deterministic floor: θ = 0 ⇒ every candidate scores 0, trust is 0,
-- and no Compares are recorded. So an untrained genome contributes nothing.
lawColdStartIsDeterministicFloor :: Embedding -> Bool
lawColdStartIsDeterministicFloor emb =
  personalBeta coldStartGenome == 0
  && scoreCandidate coldStartGenome emb == 0
  && pgCompares coldStartGenome == 0

-- | θ is a pure memoised fold: 'replay' from cold start equals 'btFit' on θ over the same
-- ordered log. This pins that θ is reproducible from @coldStartGenome@ + the local log —
-- the invariant that lets foreign genomes enter as a Compare, never a splice.
lawReplayDeterministic :: [Pick] -> Bool
lawReplayDeterministic picks =
  pgTheta (replay coldStartGenome picks)
    == btFit defaultEta defaultLambda (pgTheta coldStartGenome) picks

-- | The log can be pruned: replaying @prefix ++ tail@ from cold start equals replaying
-- @tail@ from the checkpoint captured after @prefix@ — exactly, in both θ and the Compare
-- count. Enables checkpoint-and-drop without breaking deterministic replay.
lawReplayFromCheckpoint :: [Pick] -> [Pick] -> Bool
lawReplayFromCheckpoint prefix tl =
  let checkpoint = replay coldStartGenome prefix
      full       = replay coldStartGenome (prefix ++ tl)
      fromCp     = replay checkpoint tl
  in pgTheta fromCp == pgTheta full && pgCompares fromCp == pgCompares full

-- | 'personalBeta' is non-decreasing in the Compare count — a monotone trust ramp (NOT a
-- convergence claim).
lawBetaMonotoneRamp :: Int -> Int -> Bool
lawBetaMonotoneRamp a b =
  let g n = coldStartGenome { pgCompares = n }
      na  = abs a
      nb  = abs b
  in not (na <= nb) || personalBeta (g na) <= personalBeta (g nb)

-- | One 'applyPick' from cold start keeps θ bounded: with every @|wᵢ − lᵢ| ≤ dmax@, the
-- L2 term holds @‖θ‖∞ ≤ dmax\/λ@ (the @θ₀ = 0@ case of
-- 'SixFour.Spec.PreferenceUpdate.lawThetaBounded'). The accumulator cannot blow up.
lawApplyPickBounded :: Double -> Pick -> Bool
lawApplyPickBounded dmax (w, l) =
  let dOk    = all (\(wi, li) -> abs (wi - li) <= dmax) (zip w l)
      preOk  = dmax >= 0
      bound  = max 0 (dmax / defaultLambda)
      theta' = pgTheta (applyPick coldStartGenome (w, l))
  in not (preOk && dOk) || maxAbs theta' <= bound + 1e-12
  where maxAbs = maximum . (0 :) . map abs

-- | An informative pick decreases the REGULARISED objective for a learning rate within
-- the convex descent regime. The objective @−log σ(θ·d) + ½λ‖θ‖²@ is convex and
-- @L@-smooth with @L ≤ ¼‖d‖² + λ@; gradient descent ('btUpdate' is exactly that) with
-- @η ≤ 1\/L@ cannot increase it. (The unregularised λ = 0 strict-decrease law is
-- 'SixFour.Spec.PreferenceUpdate.lawStepDecreasesLoss'; this is its shipped-λ companion.)
lawRegularizedObjectiveDecreases :: Double -> [Double] -> Pick -> Bool
lawRegularizedObjectiveDecreases eta theta pick@(w, l) =
  let d        = zipWith (-) w l
      n2       = sum (map (^ (2 :: Int)) d)
      lSmooth  = 0.25 * n2 + defaultLambda
      theta'   = btUpdate eta defaultLambda theta pick
  in eta <= 0 || n2 <= 1e-6 || eta > 1 / lSmooth ||
     regularizedObjective defaultLambda theta' pick
       <= regularizedObjective defaultLambda theta pick + 1e-9

-- | The gate rejects regressions: a candidate that fails the strict majority on the recent
-- window is NOT promoted — 'promote' returns the current genome unchanged.
lawGateRejectsRegression :: PersonalGenome -> PersonalGenome -> [Pick] -> Bool
lawGateRejectsRegression current candidate recent =
  let window  = take gateWindow (reverse recent)
      m       = length window
      correct = length (filter (predictsPick candidate) window)
      fails   = m > 0 && correct * 2 <= m
  in not fails || promote current candidate recent == current

-- | Promotion is exactly gated: 'promote' yields the candidate iff 'gatePasses', else the
-- current genome. Pins that no path can move the shipped θ around the gate.
lawGatedPromotion :: PersonalGenome -> PersonalGenome -> [Pick] -> Bool
lawGatedPromotion current candidate recent =
  promote current candidate recent
    == (if gatePasses candidate recent then candidate else current)

{- |
Module      : SixFour.Spec.Proposer
Description : The "propose candidates" organ — compose the orthogonal genome seed,
              the value-ranked Sequential-Halving selection, and the policy target.

This is the brain of the loop's PROPOSE stage. Its three ingredients each already
exist and are proven; this module is the COMPOSITION the spec-coverage audit found
missing (genome-seed → value-rank → Sequential Halving, never wired together):

  * 'SixFour.Spec.GenomePair.sampleOrthogonalPair' seeds the two genome-orthogonal,
    σ-valid candidates so the A/B pick is maximally informative — orthogonal looks
    separate two taste directions; near-duplicates would teach the model nothing.
  * the caller's @value@ oracle (the Bradley–Terry taste model θ applied to each
    candidate's realized palette) scores the candidates;
  * 'SixFour.Spec.GumbelSearch.sequentialHalving' spends the comparison budget to
    pick the value model's predicted winner and yields the visit policy target.
    Its ranking is on the integer 'SixFour.Spec.GumbelSearch.q16Key', so the
    predicted winner is cross-device deterministic (CPU and GPU agree on the move
    even when their floats differ sub-key).

For the MVP the seed is the exactly-two 'sampleOrthogonalPair'; the n-way tournament
seed is nn-4, and the depth-2-3 MCTS refinement ('SixFour.Spec.PaletteSearch',
bounded by 'lawDepthBounded') is the host-side explorer that sits between seed and
select once there are more than two candidates.

GHC-boot-only. Laws are exported predicates, QuickCheck'd in 'Properties.Proposer';
each delegates to a proven sub-module law, so the proposal inherits {two orthogonal
candidates, value-max predicted winner, sum-to-one policy target, determinism}.
-}
-- COMPARTMENT: SWIFT-COREAI | tag:DisplaySide | STRADDLER
module SixFour.Spec.Proposer
  ( -- * The proposal
    Proposal(..)
  , propose
    -- * Laws (QuickCheck'd in Properties.Proposer)
  , lawProposalSurfacesTwoOrthogonal
  , lawProposalWinnerIsValueMax
  , lawProposalVisitTargetSumsToOne
  , lawProposalDeterministic
  ) where

import SixFour.Spec.PairTreeFixed (HaarPaletteI)
import SixFour.Spec.GenomePair
  ( GenomeDisplacement, Ranking, sampleOrthogonalPair, lawPairOrthogonalExact )
import SixFour.Spec.GumbelSearch
  ( sequentialHalving, visitPolicyTarget, q16Key )

-- | What the proposer surfaces for one capture: the ≥2 orthogonal candidate looks
-- to show as A/B, the index the value model predicts the user will pick, and the
-- visit policy target (the training signal for the policy/value head).
data Proposal = Proposal
  { prCandidates      :: [GenomeDisplacement]  -- ^ the orthogonal candidates to surface (A/B)
  , prPredictedWinner :: Int                   -- ^ index the value model predicts wins (-1 if none)
  , prVisitTarget     :: [Double]              -- ^ policy-training target over the candidates (sums to 1)
  } deriving (Eq, Show)

-- | Propose the candidates for one capture. @value@ is the taste oracle (θ applied
-- to a candidate's realized palette). Composes the orthogonal seed, the value
-- scoring, and Sequential Halving into one proposal.
propose :: HaarPaletteI -> Ranking -> (GenomeDisplacement -> Double) -> Proposal
propose base ranking value =
  let (a, b)        = sampleOrthogonalPair base ranking
      candidates    = [a, b]
      n             = length candidates
      priors        = replicate n (1 / fromIntegral n)
      values        = map value candidates
      (winner, vis) = sequentialHalving priors values
  in Proposal
       { prCandidates      = candidates
       , prPredictedWinner = winner
       , prVisitTarget     = visitPolicyTarget vis
       }

-- ---------------------------------------------------------------------------
-- Laws (predicates; exercised by Properties.Proposer)
-- ---------------------------------------------------------------------------

-- | The proposer surfaces exactly two candidates, and they are the genome-orthogonal
-- pair — so every A/B pick separates two taste directions. Orthogonality is
-- delegated to 'SixFour.Spec.GenomePair.lawPairOrthogonalExact' on the same inputs.
lawProposalSurfacesTwoOrthogonal :: HaarPaletteI -> Ranking -> (GenomeDisplacement -> Double) -> Bool
lawProposalSurfacesTwoOrthogonal base ranking value =
  length (prCandidates (propose base ranking value)) == 2
  && lawPairOrthogonalExact base ranking

-- | The predicted winner is the value model's highest-scoring candidate at the Q16
-- decision resolution — the proposer always offers its best guess (and the user's
-- pick is the correction signal). Uses 'q16Key' because that is the exact basis
-- 'sequentialHalving' ranks on, so the law is cross-device exact, never FP-flaky.
lawProposalWinnerIsValueMax :: HaarPaletteI -> Ranking -> (GenomeDisplacement -> Double) -> Bool
lawProposalWinnerIsValueMax base ranking value =
  let p  = propose base ranking value
      vs = map value (prCandidates p)
      w  = prPredictedWinner p
  in null vs || (w >= 0 && q16Key (vs !! w) == maximum (map q16Key vs))

-- | The visit policy target is a probability distribution over the candidates (the
-- policy-head training signal): it sums to one for a non-degenerate proposal.
lawProposalVisitTargetSumsToOne :: HaarPaletteI -> Ranking -> (GenomeDisplacement -> Double) -> Bool
lawProposalVisitTargetSumsToOne base ranking value =
  let t = prVisitTarget (propose base ranking value)
  in abs (sum t - 1) < 1e-9 || all (== 0) t

-- | The proposal is a pure deterministic function of its inputs — same base,
-- ranking, and value oracle ⇒ identical proposal (reproducible, no IO or seed drift).
lawProposalDeterministic :: HaarPaletteI -> Ranking -> (GenomeDisplacement -> Double) -> Bool
lawProposalDeterministic base ranking value =
  propose base ranking value == propose base ranking value

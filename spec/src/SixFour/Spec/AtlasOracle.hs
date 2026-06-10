{- |
Module      : SixFour.Spec.AtlasOracle
Description : The board-modulated Oracle — day-1 policy/value with ZERO trained
              weights, every fix at the oracle seam (never a search patch).

Design §4.1 (@docs/COLOR-ATLAS.md@). 'PaletteSearch.mctsStep' /
'childrenFromPolicy' and every existing search law stay VERBATIM; the Atlas
plugs in entirely through the abstract 'Oracle':

  * __policy__ — the 'PaletteOracle.referencePolicy' coarse-to-fine prior
    shape restricted to the 'DeltaCodebook' vocabulary, then board-modulated:
    (a) ZERO priors on moves that push leaves into killed bins (ch4);
    (b) MULTIPLY priors by @exp(weightField)@ over the moved leaves (ch3);
    (c) INJECT forced anchor-satisfaction moves while ch5 anchors are unmet
        (a user pin outranks a kill — forced moves bypass (a), so the
        kill law is stated for anchor-free boards);
    (d) top-k = 8 + renormalise — LAWS ON THE ORACLE ('lawPriorsSumOne',
        'lawWidthLeqEight'), which is exactly how the expansion-blow-up
        critique is resolved without touching 'childrenFromPolicy'.

  * __value__ — the β-blend @(1−β)·shapedReward ⊕ β·BT(linearUtility θ)@ with
    @β = n/(n+50)@ on the accumulated Compare count n (the BT-overfit guard).
    Zero weights (n = 0 or no θ) ⇒ the pure pinned 'shapedReward' — the day-1,
    golden-testable value.
-}
module SixFour.Spec.AtlasOracle
  ( -- * Weights (zero = the deterministic day-1 oracle)
    AtlasWeights(..)
  , zeroAtlasWeights
  , betaBlend
    -- * Policy pieces
  , policyWidth
  , codebookPolicy
  , topKRenorm
  , killedLeafCount
  , unmetAnchors
  , anchorMove
  , atlasPolicy
  , atlasValue
    -- * The assembled oracle
  , mkAtlasOracle
    -- * Laws (predicates; QuickCheck'd in Properties.AtlasOracle)
  , lawPriorsSumOne
  , lawWidthLeqEight
  , lawKilledNeverProposed
  , lawAnchorForcedMove
  , lawZeroWeightsIsReference
  , lawTopKIdentityWhenWide
  , lawOracleDeterministic
  ) where

import Data.List (foldl', minimumBy, sort, sortBy)
import Data.Ord  (comparing)

import SixFour.Spec.AtlasBoard    (Board16(..), binOf, channelAt, emptyBoard)
import SixFour.Spec.AtlasState    (SigmaSearchState, applyAtlasMove, atlasEmbedding,
                                   atlasLeaves, fromSearchState, shapedReward,
                                   toSearchState)
import SixFour.Spec.Color         (OKLab(..), okLabDistanceSquared)
import SixFour.Spec.DeltaCodebook (codebookSize, deltaAt)
import SixFour.Spec.PairTree      (HaarPalette(..), sigmaReflect, treeDepth)
import qualified SixFour.Spec.PairTree as PT
import SixFour.Spec.PaletteOracle (RewardWeights, defaultWeights)
import SixFour.Spec.PaletteSearch (Move(..), Oracle(..), SearchState)
import SixFour.Spec.Preference    (btProbability, linearUtility)

-- ---------------------------------------------------------------------------
-- Weights
-- ---------------------------------------------------------------------------

-- | Everything the oracle's behaviour depends on beyond the board. Zero
-- weights ⇒ the deterministic reference ('lawZeroWeightsIsReference').
data AtlasWeights = AtlasWeights
  { awReward   :: RewardWeights   -- ^ the pinned aesthetic objective's weights
  , awTheta    :: [Double]        -- ^ 770-D BT utility θ; @[]@ = none learned yet
  , awCompares :: Int             -- ^ accumulated Compare count n (drives β)
  } deriving (Eq, Show)

-- | Day 1: pinned reward weights, no θ, no Compares.
zeroAtlasWeights :: AtlasWeights
zeroAtlasWeights = AtlasWeights defaultWeights [] 0

-- | @β = n/(n+50)@ — 0 at n = 0, → 1 as preference data accumulates.
betaBlend :: Int -> Double
betaBlend n = fromIntegral (max 0 n) / (fromIntegral (max 0 n) + 50)

-- ---------------------------------------------------------------------------
-- Policy
-- ---------------------------------------------------------------------------

-- | The oracle's branching cap (top-k = 8; design §4.1 (d)).
policyWidth :: Int
policyWidth = 8

-- | The 'referencePolicy' ∩ codebook base: coarse-to-fine slots (level @lv@,
-- index 0, prior ∝ @1/(lv+1)@ — the same shape as
-- 'PaletteOracle.referencePolicy', levels 0..min 3 (d−1)) with ALL 12
-- level-scaled codebook deltas per slot. Normalised.
codebookPolicy :: SearchState -> [(Move, Double)]
codebookPolicy s =
  let d   = max 1 (treeDepth s)
      raw = [ (Move lv 0 (deltaAt lv k), 1 / fromIntegral (lv + 1))
            | lv <- [0 .. min 3 (d - 1)]
            , k  <- [0 .. codebookSize - 1] ]
      tot = sum (map snd raw)
  in [ (m, p / tot) | (m, p) <- raw ]

-- | Keep the @k@ highest-prior moves (stable: ties keep earlier entries) IN
-- INPUT ORDER, renormalised to sum to 1. @k ≥ length@ ⇒ pure renormalisation
-- ('lawTopKIdentityWhenWide' — P1's one good law, kept here, not in search).
topKRenorm :: Int -> [(Move, Double)] -> [(Move, Double)]
topKRenorm k ps =
  let ranked = sortBy (comparing (negate . snd . snd)) (zip [0 :: Int ..] ps)
      keep   = sort (map fst (take (max 0 k) ranked))
      sel    = [ ps !! i | i <- keep ]
      tot    = sum (map snd sel)
  in if null sel
       then []
       else if tot <= 0
         then [ (m, 1 / fromIntegral (length sel)) | (m, _) <- sel ]
         else [ (m, p / tot) | (m, p) <- sel ]

-- | Number of state leaves sitting in killed (ch4 ≠ 0) bins.
killedLeafCount :: Board16 -> SigmaSearchState -> Int
killedLeafCount board s =
  length [ () | c <- atlasLeaves s, channelAt bKill board (binOf c) /= 0 ]

-- | ch3 modulation: the mean weight-field value over the bins of the leaves
-- the move actually MOVED (0 for the identity move — factor @exp 0 = 1@).
regionGain :: Board16 -> SigmaSearchState -> Move -> Double
regionGain board s m =
  let l0      = atlasLeaves s
      l1      = atlasLeaves (applyAtlasMove m s)
      changed = [ c' | (c, c') <- zip l0 l1, c /= c' ]
  in case changed of
       [] -> 0
       cs -> sum [ channelAt bWeight board (binOf c) | c <- cs ]
               / fromIntegral (length cs)

-- | The board's anchors with NO state leaf in their bin yet.
unmetAnchors :: Board16 -> SigmaSearchState -> [OKLab]
unmetAnchors board s =
  let bins = map binOf (atlasLeaves s)
  in [ c | (bi, c) <- bAnchors board, bi `notElem` bins ]

-- | The deterministic anchor-satisfaction move: land the nearest generator
-- (or its σ-image — whichever leaf is closer) EXACTLY on the anchor colour,
-- via a deepest-level offset move. Adding @δ@ to the offset at level @d−1@,
-- index @i div 2@ moves generator @i@ by @±δ@ (Haar: children are @n ± δ@),
-- so @δ = ±(target − cᵢ)@ puts leaf @2i@ (or @2i+1@ = σ-image) on the anchor.
-- 'Nothing' on a degenerate (depth-0) tree.
anchorMove :: SigmaSearchState -> OKLab -> Maybe Move
anchorMove s a =
  let inner = toSearchState s
      d     = treeDepth inner
      gens  = PT.reconstruct inner
  in if d < 1 || null gens
       then Nothing
       else
         let cands = concat
               [ [ (okLabDistanceSquared g a, (i, False))
                 , (okLabDistanceSquared (sigmaReflect g) a, (i, True)) ]
               | (i, g) <- zip [0 :: Int ..] gens ]
             (_, (i, useSigma)) = minimumBy (comparing fst) cands
             target = if useSigma then sigmaReflect a else a
             gi     = gens !! i
             delta  = subOK target gi
             signed = if even i then delta else negOK delta
         in Just (Move (d - 1) (i `div` 2) signed)
  where
    subOK (OKLab l1 a1 b1) (OKLab l2 a2 b2) = OKLab (l1 - l2) (a1 - a2) (b1 - b2)
    negOK (OKLab l a' b') = OKLab (negate l) (negate a') (negate b')

-- | The full board-modulated policy (steps (a)–(d) of the module header).
-- Forced anchor moves enter with a prior STRICTLY ABOVE every kept prior
-- (1 + the kept total — the @exp(weightField)@ modulation can push kept
-- priors past 1, so a constant would not do), so they always survive the
-- top-k cut.
atlasPolicy :: Board16 -> SearchState -> [(Move, Double)]
atlasPolicy board hp =
  let s     = fromSearchState hp
      base  = codebookPolicy hp
      kill0 = killedLeafCount board s
      kept  = [ (m, p * exp (regionGain board s m))
              | (m, p) <- base
              , killedLeafCount board (applyAtlasMove m s) <= kill0 ]
      forcedPrio = 1 + sum (map snd kept)
      forced = [ (m, forcedPrio)
               | a <- unmetAnchors board s
               , Just m <- [anchorMove s a] ]
  in topKRenorm policyWidth (forced ++ kept)

-- ---------------------------------------------------------------------------
-- Value
-- ---------------------------------------------------------------------------

-- | The β-blended value (design §4.1). No θ ⇒ β forced to 0 (the tiered
-- degradation chain's bottom tier: pure 'shapedReward').
atlasValue :: AtlasWeights -> Board16 -> SearchState -> Double
atlasValue w board hp =
  let s    = fromSearchState hp
      det  = shapedReward (awReward w) board s
      beta = if null (awTheta w) then 0 else betaBlend (awCompares w)
  in if beta == 0
       then det
       else (1 - beta) * det
              + beta * btProbability (linearUtility (awTheta w) (atlasEmbedding s))

-- ---------------------------------------------------------------------------
-- The oracle
-- ---------------------------------------------------------------------------

-- | Assemble the 'Oracle' the (unchanged) search consumes:
-- @runSearch (mkAtlasOracle w board) (Hyperparams 1.4) (HaltOnVisits 512) …@.
mkAtlasOracle :: AtlasWeights -> Board16 -> Oracle
mkAtlasOracle w board = Oracle
  { oPolicy = atlasPolicy board
  , oValue  = atlasValue w board
  }

-- ---------------------------------------------------------------------------
-- Laws
-- ---------------------------------------------------------------------------

-- | Non-empty policies are normalised distributions (the law that keeps
-- 'childrenFromPolicy' honest without patching it).
lawPriorsSumOne :: Board16 -> SearchState -> Bool
lawPriorsSumOne board hp =
  let ps = map snd (atlasPolicy board hp)
  in null ps || abs (sum ps - 1) < 1e-9

-- | The policy never proposes more than 8 moves.
lawWidthLeqEight :: Board16 -> SearchState -> Bool
lawWidthLeqEight board hp = length (atlasPolicy board hp) <= policyWidth

-- | On an ANCHOR-FREE board, no proposed move pushes leaves into killed bins
-- (anchor-forced moves deliberately bypass the kill filter — a pin outranks
-- a kill — hence the anchor-free precondition).
lawKilledNeverProposed :: Board16 -> SearchState -> Bool
lawKilledNeverProposed board hp =
  not (null (bAnchors board)) ||
  let s     = fromSearchState hp
      kill0 = killedLeafCount board s
  in all (\(m, _) -> killedLeafCount board (applyAtlasMove m s) <= kill0)
         (atlasPolicy board hp)

-- | While an anchor is unmet, the policy proposes a move whose application
-- meets at least one previously-unmet anchor (the forced move lands a leaf
-- EXACTLY on the anchor colour, so its bin becomes occupied). Stated for
-- CONSISTENT pins — @bi == binOf colour@, which is how the UI constructs
-- them — and as \"meets a previously-unmet anchor\", not \"the unmet count
-- drops\": a Haar offset move displaces the target generator's σ-sibling
-- too, which may legitimately vacate some OTHER anchor's bin.
lawAnchorForcedMove :: Board16 -> SearchState -> Bool
lawAnchorForcedMove board hp =
  let s          = fromSearchState hp
      consistent = all (\(bi, c) -> bi == binOf c) (bAnchors board)
      bins0      = map binOf (atlasLeaves s)
      unmet0     = [ bi | (bi, _) <- bAnchors board, bi `notElem` bins0 ]
  in not consistent || null unmet0 ||
     any (\(m, _) ->
            let bins1 = map binOf (atlasLeaves (applyAtlasMove m s))
            in any (`elem` bins1) unmet0)
         (atlasPolicy board hp)

-- | Empty board + zero weights ⇒ EXACTLY the reference: top-8 of the
-- codebook-restricted reference policy, and the pure 'shapedReward' value.
lawZeroWeightsIsReference :: SearchState -> Bool
lawZeroWeightsIsReference hp =
  atlasPolicy emptyBoard hp == topKRenorm policyWidth (codebookPolicy hp)
    && atlasValue zeroAtlasWeights emptyBoard hp
         == shapedReward defaultWeights emptyBoard (fromSearchState hp)

-- | @k ≥ branching@ ⇒ 'topKRenorm' is pure renormalisation: same moves, same
-- order, priors scaled by the total (identity within ε when they already
-- sum to 1).
lawTopKIdentityWhenWide :: [(Move, Double)] -> Bool
lawTopKIdentityWhenWide ps =
  let qs  = [ (m, abs p) | (m, p) <- ps ]   -- priors are non-negative by contract
      tot = sum (map snd qs)
      out = topKRenorm (length qs) qs
  in tot <= 0 ||
     (map fst out == map fst qs
        && and (zipWith (\(_, p') (_, p) -> abs (p' - p / tot) < 1e-12) out qs))

-- | Pure determinism: the same board + state always yields the same policy
-- and value (no IO, no hidden state).
lawOracleDeterministic :: AtlasWeights -> Board16 -> SearchState -> Bool
lawOracleDeterministic w board hp =
  let o = mkAtlasOracle w board
  in oPolicy o hp == oPolicy o hp && oValue o hp == oValue o hp

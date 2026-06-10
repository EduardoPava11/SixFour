{- |
Module      : SixFour.Spec.AtlasState
Description : The σ-pair search state — embedding AND reward over the 256
              LEAVES, never the 128 generators (the depth-7/768 schism fix).

Design §4.0 (@docs/COLOR-ATLAS.md@) — the most-flagged judge defect, fixed in
ONE module:

  * 'PaletteSearch.paletteEmbedding' calls 'PairTree.reconstruct', which on a
    DEPTH-7 tree yields 128 leaves = 384 floats, not the documented 768.
  * The SAME bug bites the value: 'PaletteOracle.paletteReward' also calls
    'reconstruct', so on a depth-7-rooted state it scores the 128 GENERATORS,
    not the 256 σ-paired leaves. σ-reflection structurally doubles chroma
    diversity, so beauty/entropy over generators is a DIFFERENT objective
    ('lawRewardOverLeavesNotGenerators' exhibits the gap on a pinned fixture).

Both embedding and reward therefore route through
'SigmaPairHead.reconstructPaired' (256 leaves, ALWAYS — 'lawEmbedding770').
'PaletteSearch' itself stays byte-identical: the search still walks a
'HaarPalette' (the depth-7 tree inside the newtype); only the Oracle we supply
('SixFour.Spec.AtlasOracle') consumes 'atlasEmbedding' / 'shapedReward'.

'shapedReward' = the pinned deterministic 'paletteReward' objective routed
through the leaves, plus the board-shaped curation terms (anchors, weights,
kills) — the day-1, zero-weights value function (design §1, the flywheel rule).
-}
module SixFour.Spec.AtlasState
  ( -- * The σ-pair search state
    SigmaSearchState(..)
  , fromSearchState
  , toSearchState
  , applyAtlasMove
  , atlasWellFormed
    -- * Leaves and embedding (768 + 2 = 770, always)
  , atlasLeaves
  , stateCoverage
  , stateBeauty
  , atlasEmbedding
  , embeddingDim
    -- * The shaped reward (deterministic value, day 1)
  , lambdaAnchor
  , lambdaWeight
  , lambdaToggle
  , anchorHit
  , shapedReward
    -- * A pinned σ-asymmetric-chroma fixture (for the reward-gap law)
  , rewardGapFixture
    -- * Laws (predicates; QuickCheck'd in Properties.AtlasState)
  , lawEmbedding770
  , lawLeavesViaReconstructPaired
  , lawRewardOverLeavesNotGenerators
  , lawSearchPreservesDepth
  ) where

import qualified Data.Set as Set

import SixFour.Spec.AtlasBoard    (Board16(..), binOf, boardBins, channelAt, bAnchors)
import SixFour.Spec.Color         (OKLab(..))
import SixFour.Spec.Diversity     (gaussianColorEntropy)
import SixFour.Spec.Loss          (beautyLossLeaves)
import SixFour.Spec.PairTree      (HaarPalette(..), treeDepth)
import SixFour.Spec.PaletteOracle (RewardWeights(..), paletteReward)
import SixFour.Spec.PaletteSearch (Move(..), SearchState, applyMove)
import SixFour.Spec.SigmaPairHead (SigmaPairTree(..), reconstructPaired,
                                   sigmaPairDepth, sigmaPairLeaves,
                                   sigmaPairWellFormed)

-- ---------------------------------------------------------------------------
-- The state
-- ---------------------------------------------------------------------------

-- | A search state ROOTED AT THE σ-PAIR GENOME: a depth-7 tree (384 DOF)
-- whose palette is always the 256 σ-pair-interleaved leaves.
newtype SigmaSearchState = SigmaSearchState
  { searchTree :: SigmaPairTree
  } deriving (Eq, Show)

-- | Wrap the raw 'PaletteSearch.SearchState' (= 'HaarPalette') the search
-- threads — the seam through which the Atlas oracle reads σ-pair semantics
-- without touching 'PaletteSearch' itself.
fromSearchState :: SearchState -> SigmaSearchState
fromSearchState = SigmaSearchState . SigmaPairTree

-- | The inverse seam (hand the inner tree back to the search).
toSearchState :: SigmaSearchState -> SearchState
toSearchState = unSigmaPairTree . searchTree

-- | Apply a genome move at the σ-pair level (delegates to
-- 'PaletteSearch.applyMove' on the inner tree — no new move semantics).
applyAtlasMove :: Move -> SigmaSearchState -> SigmaSearchState
applyAtlasMove m = fromSearchState . applyMove m . toSearchState

-- | Well-formed = the inner tree is a well-formed depth-7 σ-pair genome.
atlasWellFormed :: SigmaSearchState -> Bool
atlasWellFormed = sigmaPairWellFormed . searchTree

-- ---------------------------------------------------------------------------
-- Leaves + embedding
-- ---------------------------------------------------------------------------

-- | THE rule of this module: leaves are always the 256 σ-paired leaves via
-- 'reconstructPaired' — never 'PairTree.reconstruct' (the 128 generators).
atlasLeaves :: SigmaSearchState -> [OKLab]
atlasLeaves = reconstructPaired . searchTree

-- | Occupied 16³ bins of the leaves / 4096 (the coverage scalar appended to
-- the embedding; same grid as ch2).
stateCoverage :: SigmaSearchState -> Double
stateCoverage s =
  fromIntegral (Set.size (Set.fromList (map binOf (atlasLeaves s))))
    / fromIntegral boardBins

-- | Ou-Luo pair beauty of the LEAVES (negated loss; higher = more beautiful).
stateBeauty :: SigmaSearchState -> Double
stateBeauty = negate . beautyLossLeaves . atlasLeaves

-- | The 770-D state embedding: 256 leaves × 3 OKLab reals (768) ++
-- @[coverage, beauty]@. Always 770 for a well-formed state
-- ('lawEmbedding770' — the law that closes the unenforced-768 risk).
atlasEmbedding :: SigmaSearchState -> [Double]
atlasEmbedding s =
  concatMap (\(OKLab l a b) -> [l, a, b]) (atlasLeaves s)
    ++ [stateCoverage s, stateBeauty s]

-- | @3·256 + 2 = 770@ (the Bradley–Terry θ dimension).
embeddingDim :: Int
embeddingDim = 3 * sigmaPairLeaves + 2

-- ---------------------------------------------------------------------------
-- The shaped reward
-- ---------------------------------------------------------------------------

-- | Shaping weight on anchor satisfaction (λa).
lambdaAnchor :: Double
lambdaAnchor = 0.5

-- | Shaping weight on the ch3 weight-field inner product (λw).
lambdaWeight :: Double
lambdaWeight = 0.25

-- | Shaping weight on the ch4 kill-mask inner product (λt, subtracted).
lambdaToggle :: Double
lambdaToggle = 1.0

-- | Fraction of the board's pinned anchors whose bin contains ≥ 1 leaf.
-- 0 when no anchors are pinned (so an empty board adds NO constant shift —
-- the empty-board shaped reward is exactly the pinned aesthetic objective
-- over the leaves, which is what 'lawRewardOverLeavesNotGenerators' isolates).
anchorHit :: Board16 -> [OKLab] -> Double
anchorHit board leaves =
  case bAnchors board of
    [] -> 0
    as ->
      let bins = Set.fromList (map binOf leaves)
          hits = length [ () | (bi, _) <- as, bi `Set.member` bins ]
      in fromIntegral hits / fromIntegral (length as)

-- | The day-1 deterministic value (design §4.0):
--
-- @
-- wb·(−beautyLossLeaves leaves) + wd·gaussianColorEntropy leaves
--   + λa·anchorHit(board, leaves)
--   + λw·⟨ch3, binned leaves⟩ − λt·⟨ch4, binned leaves⟩
-- @
--
-- where @leaves = atlasLeaves s@ — the 256 σ-paired leaves, NOT the 128
-- generators 'paletteReward' would score on a depth-7 tree.
shapedReward :: RewardWeights -> Board16 -> SigmaSearchState -> Double
shapedReward (RewardWeights wb wd) board s =
  let leaves = atlasLeaves s
      n      = length leaves
      ws     = replicate n (if n == 0 then 0 else 1 / fromIntegral n)
  in wb * negate (beautyLossLeaves leaves)
       + wd * gaussianColorEntropy leaves ws
       + lambdaAnchor * anchorHit board leaves
       + lambdaWeight * chMean bWeightF board leaves
       - lambdaToggle * chMean bKillF board leaves
  where
    chMean f b ls = case ls of
      [] -> 0
      _  -> sum [ channelAt f b (binOf c) | c <- ls ] / fromIntegral (length ls)
    bWeightF = bWeight
    bKillF   = bKill

-- ---------------------------------------------------------------------------
-- Pinned fixture
-- ---------------------------------------------------------------------------

-- | A deterministic, chroma-heavy depth-7 genome: its generators sit well off
-- the achromatic axis, so the σ-paired leaves (generators ∪ their chroma
-- reflections) have a structurally different colour distribution than the
-- generators alone — the fixture on which the generator-scored reward and the
-- leaf-scored reward must disagree.
rewardGapFixture :: SigmaSearchState
rewardGapFixture =
  fromSearchState $ HaarPalette (OKLab 0.55 0.22 0.12)
    [ [ OKLab (0.002 * fromIntegral (i + lv))
              (0.015 / fromIntegral (lv + 1))
              (negate 0.011 / fromIntegral (lv + 1))
      | i <- [0 .. 2 ^ lv - 1 :: Int] ]
    | lv <- [0 .. sigmaPairDepth - 1] ]

-- ---------------------------------------------------------------------------
-- Laws
-- ---------------------------------------------------------------------------

-- | For every well-formed σ-pair state the embedding has EXACTLY 770 entries.
lawEmbedding770 :: SigmaSearchState -> Bool
lawEmbedding770 s =
  not (atlasWellFormed s) || length (atlasEmbedding s) == embeddingDim

-- | The leaves seam: 'atlasLeaves' IS 'reconstructPaired' of the inner tree
-- (256 leaves on a well-formed state) — never the generator list.
lawLeavesViaReconstructPaired :: SigmaSearchState -> Bool
lawLeavesViaReconstructPaired s =
  atlasLeaves s == reconstructPaired (searchTree s)
    && (not (atlasWellFormed s) || length (atlasLeaves s) == sigmaPairLeaves)

-- | THE reward-gap pin (judge resolution §4.0): on the pinned σ-asymmetric-
-- chroma fixture, the empty-board 'shapedReward' (leaves) and
-- 'paletteReward' ∘ inner tree (generators) are DIFFERENT objectives.
lawRewardOverLeavesNotGenerators :: RewardWeights -> Board16 -> Bool
lawRewardOverLeavesNotGenerators w emptyB =
  abs (shapedReward w emptyB rewardGapFixture
       - paletteReward w (toSearchState rewardGapFixture)) > 1e-6

-- | Genome moves preserve the σ-pair shape: depth stays 7, well-formedness
-- survives, the palette stays 256 leaves.
lawSearchPreservesDepth :: Move -> SigmaSearchState -> Bool
lawSearchPreservesDepth m s =
  not (atlasWellFormed s) ||
  let s' = applyAtlasMove m s
  in atlasWellFormed s'
       && treeDepth (toSearchState s') == sigmaPairDepth
       && length (atlasLeaves s') == sigmaPairLeaves

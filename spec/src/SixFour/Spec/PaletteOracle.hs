{- |
Module      : SixFour.Spec.PaletteOracle
Description : A concrete 'Oracle' for 'PaletteSearch' — the value head as a
              deterministic aesthetic reward (the objective the look-NN learns).

'SixFour.Spec.PaletteSearch' is parametrized over an abstract 'Oracle' (policy +
value). This module supplies a CONCRETE one, honestly split by what the untrained
look-NN can vs cannot stand in for:

- __value head = 'paletteReward'__: a DETERMINISTIC aesthetic objective over a
  candidate palette — Ou-Luo pair harmony ('Loss.beautyLossLeaves', negated so
  higher = more beautiful) + OKLab Gaussian colour entropy ('Diversity.gaussianColorEntropy').
  This is the GROUND TRUTH the NN's value head is trained to approximate; the spec
  pins the objective, so the value is golden-testable today, before any training.
- __policy head = 'referencePolicy'__: a coarse-to-fine reference heuristic (favour
  bigger structural moves first), normalised. It is a STAND-IN; the trained look-NN
  policy head replaces it with learnt move proposals. Labelled as such — we do not
  pretend to spec an untrained policy.

'referenceOracle' assembles both into the 'Oracle' the search consumes.
-}
module SixFour.Spec.PaletteOracle
  ( RewardWeights(..)
  , defaultWeights
  , paletteReward
  , referencePolicy
  , referenceOracle
    -- * Laws (QuickCheck'd in Properties.PaletteOracle)
  , lawRewardDeterministic
  , lawRewardLinear
  , lawReferencePolicyInRange
  , lawReferencePolicyNormalized
  , lawOracleValueIsReward
  ) where

import SixFour.Spec.Color        (OKLab(..))
import SixFour.Spec.PairTree     (reconstruct, treeDepth)
import SixFour.Spec.Loss         (beautyLossLeaves)
import SixFour.Spec.Diversity    (gaussianColorEntropy)
import SixFour.Spec.PaletteSearch (Oracle(..), Move(..), SearchState)

-- | Weights on the two aesthetic terms (the NN's value head learns to match the
-- weighted objective; the weights themselves are a tuning choice).
data RewardWeights = RewardWeights
  { rwBeauty    :: Double   -- ^ weight on Ou-Luo pair harmony
  , rwDiversity :: Double   -- ^ weight on OKLab Gaussian colour entropy
  } deriving (Eq, Show)

defaultWeights :: RewardWeights
defaultWeights = RewardWeights 0.5 0.5

-- | The value head's TARGET: a deterministic reward over a candidate palette.
-- beauty = @−beautyLossLeaves@ (the sum of Ou-Luo pair harmony, higher = better);
-- diversity = the differential entropy of the Gaussian fit to the reconstructed
-- leaves. Pure + total; golden-pinnable.
paletteReward :: RewardWeights -> SearchState -> Double
paletteReward (RewardWeights wb wd) s =
  let leaves = reconstruct s
      n      = length leaves
      ws     = replicate n (if n == 0 then 0 else 1 / fromIntegral n)
  in wb * negate (beautyLossLeaves leaves) + wd * gaussianColorEntropy leaves ws

-- | A REFERENCE policy: coarse-to-fine coefficient perturbations whose priors
-- favour coarser levels (bigger structural moves first), normalised to sum to 1.
-- A heuristic stand-in for the (untrained) look-NN policy head.
referencePolicy :: SearchState -> [(Move, Double)]
referencePolicy s =
  let d     = max 1 (treeDepth s)
      raw   = [ (Move lv 0 (OKLab dl da db), 1 / fromIntegral (lv + 1))
              | lv <- [0 .. min 3 (d - 1)]
              , (dl, da, db) <- [ (0.04, 0, 0), (-0.04, 0, 0)
                                , (0, 0.04, 0), (0, 0, 0.04) ] ]
      total = sum (map snd raw)
  in [ (m, w / total) | (m, w) <- raw ]

-- | The concrete oracle the search consumes: learnt-objective value + reference policy.
referenceOracle :: RewardWeights -> Oracle
referenceOracle w = Oracle
  { oPolicy = referencePolicy
  , oValue  = paletteReward w
  }

--------------------------------------------------------------------------------
-- Laws (predicates; exercised by Properties.PaletteOracle)
--------------------------------------------------------------------------------

-- | The reward is a pure deterministic function.
lawRewardDeterministic :: RewardWeights -> SearchState -> Bool
lawRewardDeterministic w s = paletteReward w s == paletteReward w s

-- | The reward is linear in the weights: scaling both weights by k scales it by k.
lawRewardLinear :: Double -> RewardWeights -> SearchState -> Bool
lawRewardLinear k (RewardWeights wb wd) s =
  abs (paletteReward (RewardWeights (k * wb) (k * wd)) s
       - k * paletteReward (RewardWeights wb wd) s) < 1e-9

-- | Every proposed move targets an in-range (level, index) of the palette.
lawReferencePolicyInRange :: SearchState -> Bool
lawReferencePolicyInRange s =
  let d = max 1 (treeDepth s)
  in all (\(Move lv ix _, _) -> lv >= 0 && lv < d && ix >= 0 && ix < 2 ^ lv)
         (referencePolicy s)

-- | The policy priors are a normalised distribution (sum to 1).
lawReferencePolicyNormalized :: SearchState -> Bool
lawReferencePolicyNormalized s =
  let ps = map snd (referencePolicy s)
  in null ps || abs (sum ps - 1) < 1e-9

-- | The oracle's value IS the reward (no divergence between the two).
lawOracleValueIsReward :: RewardWeights -> SearchState -> Bool
lawOracleValueIsReward w s = oValue (referenceOracle w) s == paletteReward w s

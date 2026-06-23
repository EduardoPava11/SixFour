{- |
Module      : SixFour.Spec.GumbelSearch
Description : Gumbel-AlphaZero root selection + the Q16 cross-tier determinism boundary.

The shipped search (SIXFOUR-ALPHAZERO-COLLAPSE-DESIGN §5.3, §6): root-action selection is
Sequential Halving over the (≤ 8) policy candidates, NOT classic PUCT. With a branching cap of 8
this is near-exhaustive and removes PUCT's @c@/Dirichlet tuning, giving a deterministic,
policy-improving root choice whose visit distribution is a sound policy-training target.

THE determinism boundary (web-researched 2026-06-17, see §5.5 of the design doc): the value
oracle is FLOAT, and the GPU evaluates a batched frontier with reductions whose lane order Metal
does not specify (@simd_sum@ reassociates), so the CPU tree and the GPU value will NOT be bit-equal.
Yet 'SixFour.Spec.PaletteSearch.argmaxWithSeed' decides ties by EXACT @Double@ equality. The fix
here: compare values by a Q16 INTEGER KEY ('q16Key'). Two evaluators agree on the decision as long
as their values fall in the same Q16 bucket, so a sub-key float wobble (the GPU's reassociation
error) cannot flip the winner ('lawArgmaxKeyDependsOnlyOnKeys'). The GPU must therefore quantize its
value to this same key on a FIXED-order reduction; the integer key, not the float, is the contract.

This module owns the SELECTION math (pure, deterministic); it reuses 'PaletteSearch' for the
'Seed'/'stepSeed' RNG and plugs into the existing 'Oracle'.
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none | STRADDLER
module SixFour.Spec.GumbelSearch
  ( -- * The Q16 cross-tier comparison key
    q16Key
  , argmaxKeyWithSeed
    -- * Sequential Halving (Gumbel-AlphaZero root selection)
  , policyWidthCap
  , sequentialHalving
  , visitPolicyTarget
    -- * Laws (predicates; QuickCheck'd in Properties.GumbelSearch)
  , lawArgmaxKeyDependsOnlyOnKeys
  , lawSHWinnerInRange
  , lawSHPicksMaxValue
  , lawSHWinnerHasMaxVisits
  , lawVisitTargetSumsToOne
  ) where

import Data.List  (sortBy)
import Data.Ord   (comparing, Down(..))

import SixFour.Spec.PaletteSearch (Seed, stepSeed)

-- ---------------------------------------------------------------------------
-- The Q16 cross-tier comparison key
-- ---------------------------------------------------------------------------

-- | Quantize a value to a Q16 integer key (round half to even, the 'round' default). Two
-- evaluators (the CPU tree, the GPU batched value) agree on a decision iff their keys agree, so
-- the contract the GPU must meet is "produce this key", not "produce this float".
q16Key :: Double -> Int
q16Key v = round (v * 65536)

-- | Argmax over @(value, index)@ pairs comparing by 'q16Key' (NOT raw 'Double'), with a seeded
-- pick among equal-key ties. This is the determinism-safe replacement for
-- 'PaletteSearch.argmaxWithSeed' on any value the GPU also computes.
argmaxKeyWithSeed :: [(Double, Int)] -> Seed -> (Int, Seed)
argmaxKeyWithSeed scored seed =
  let keyed = [ (q16Key v, i) | (v, i) <- scored ]
      best  = maximum (map fst keyed)
      tied  = [ i | (k, i) <- keyed, k == best ]
      seed' = stepSeed seed
      pick  = tied !! (seed' `mod` max 1 (length tied))
  in (pick, seed')

-- ---------------------------------------------------------------------------
-- Sequential Halving
-- ---------------------------------------------------------------------------

-- | The branching cap (= @policyWidth@): Sequential Halving is near-exhaustive at this width.
policyWidthCap :: Int
policyWidthCap = 8

-- | Sequential Halving over root arms given their priors and (completed) values. Each round
-- keeps the top @⌈|S|/2⌉@ arms by 'q16Key' value (deterministic tie-break by prior then index)
-- and credits every surviving arm one visit. Returns @(winnerIndex, visitCounts)@; the visit
-- counts are the policy-training target. Pure and deterministic (no Dirichlet) — the Gumbel
-- exploration perturbation for gallery diversity is a seeded add-on, deferred (design §5.3).
sequentialHalving :: [Double] -> [Double] -> (Int, [Int])
sequentialHalving priors values =
  let n = length values
  in if n == 0
       then (-1, [])
       else go [0 .. n - 1] (replicate n 0)
  where
    rank i = Down (q16Key (values !! i), priors !! i, negate i)   -- total, deterministic order
    go survivors visits =
      let visits' = [ if i `elem` survivors then v + 1 else v
                    | (i, v) <- zip [0 ..] visits ]
      in case survivors of
           [w] -> (w, visits')
           _   -> let k    = (length survivors + 1) `div` 2
                      kept = take k (sortBy (comparing rank) survivors)
                  in go kept visits'

-- | Normalise visit counts to a probability distribution (the policy-training target). Sums to 1
-- for any non-empty, non-all-zero input.
visitPolicyTarget :: [Int] -> [Double]
visitPolicyTarget visits =
  let total = sum visits
  in if total == 0
       then map (const 0) visits
       else [ fromIntegral v / fromIntegral total | v <- visits ]

-- ---------------------------------------------------------------------------
-- Laws
-- ---------------------------------------------------------------------------

-- | The cross-tier determinism law: the seeded key-argmax decision depends ONLY on the Q16 keys.
-- Two value lists that share keys (and indices) at the same seed pick the same winner — so a GPU
-- whose float differs sub-key from the CPU still agrees on the move.
lawArgmaxKeyDependsOnlyOnKeys :: [(Double, Int)] -> [(Double, Int)] -> Seed -> Bool
lawArgmaxKeyDependsOnlyOnKeys a b seed =
  not sameKeys || argmaxKeyWithSeed a seed == argmaxKeyWithSeed b seed
  where
    sameKeys = map snd a == map snd b
            && map (q16Key . fst) a == map (q16Key . fst) b

-- | Sequential Halving returns a real arm index (in range) for any non-empty input.
lawSHWinnerInRange :: [Double] -> [Double] -> Bool
lawSHWinnerInRange priors values =
  let n = min (length priors) (length values)
      ps = take n priors; vs = take n values
      (w, _) = sequentialHalving ps vs
  in n == 0 || (w >= 0 && w < n)

-- | With strictly distinct Q16 value keys, Sequential Halving returns the max-value arm (the
-- max-key arm survives every halving round).
lawSHPicksMaxValue :: [Double] -> [Double] -> Bool
lawSHPicksMaxValue priors values =
  let n  = min (length priors) (length values)
      ps = take n priors; vs = take n values
      keys = map q16Key vs
  in n == 0 || length (dedup keys) /= n   -- vacuous unless keys are all distinct
     || let (w, _) = sequentialHalving ps vs
            best   = maximum keys
        in q16Key (vs !! w) == best
  where dedup = foldr (\x acc -> if x `elem` acc then acc else x : acc) []

-- | The winner accrued the maximum visit count (it survived to the final round).
lawSHWinnerHasMaxVisits :: [Double] -> [Double] -> Bool
lawSHWinnerHasMaxVisits priors values =
  let n  = min (length priors) (length values)
      ps = take n priors; vs = take n values
      (w, visits) = sequentialHalving ps vs
  in n == 0 || visits !! w == maximum visits

-- | The visit policy target is a distribution (sums to 1) for any non-empty, non-all-zero input.
lawVisitTargetSumsToOne :: [Int] -> Bool
lawVisitTargetSumsToOne visits =
  let pos = map (\v -> max 0 v) visits
  in null pos || sum pos == 0
     || abs (sum (visitPolicyTarget pos) - 1) < 1e-9

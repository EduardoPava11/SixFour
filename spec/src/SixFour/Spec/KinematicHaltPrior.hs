{- |
Module      : SixFour.Spec.KinematicHaltPrior
Description : THE WIRING — the KinematicLadder budget law becomes the PonderNet halting prior. 'certifiedOrder' is an exact Integer observable of a trajectory (the smallest k with Δ^{k+1} ≡ 0 on the window, capped); the KEYSTONE 'lawCheapestZeroLossHaltIsCertifiedOrder' proves that under the PonderNet objective (expected residual loss over the halt distribution, "SixFour.Spec.PonderHaltDistribution") the CHEAPEST zero-loss pointed halting is exactly the certified kinematic order. Halting stops being a learned hunch: "halt at depth k" is the checkable claim Δ^{k+1} ≡ 0, and a gene that halts earlier provably pays residual (in exact integers), while one that halts later provably overspends steps.

The pieces: 'residualLoss' j f = Σ_t |f(t) − NewtonPredict_j f(t)| is the EXACT
Integer per-depth loss (the S-map truncated at order j; zero iff the Mahler
tail above j vanishes); 'certifiedLambdas' builds the pointed prior (all halt
mass at step k) and it is proper with mass exactly 1 at k
('lawCertifiedPriorIsProperAndPointed'); it spends exactly k+1 expected steps
in the machinery's 1-based count ('lawCertifiedPriorSpendsExactlyK'); on a
certified trajectory it achieves exactly ZERO expected loss
('lawCertifiedPriorAchievesZeroLoss'); and halting even one step early pays
strictly positive expected loss ('lawEarlyHaltPaysResidual' — the residual is
an Integer ≥ 1, not an epsilon). Minimal sufficiency is the iff
'lawResidualZeroIffAtOrAboveOrder': L_j = 0 ⇔ j ≥ certifiedOrder — kinematic
order == halting depth == S-packets owed, now stated against the same
objective the trainer minimizes.

BUDGET/REWARD READING (design, referenced not landed): the certified order is
what a gene does NOT pay for; the MAP-Elites axes (docs/GENE-ARCHIVE-PLAN.md)
can meter meaning-per-S-packet as residual removed per step past the certified
floor. The user's painted budget ("SixFour.Spec.PonderBudget") and this
data-driven prior compose: paint biases WHERE to think, certification bounds
HOW DEEP thinking can possibly help.

HONEST BOUNDARY: certification is exact on the OBSERVED window — Δ^{k+1} ≡ 0
on 10 samples is a statement about those samples, not the future; the prior is
a floor for the learned halting, not a replacement. Losses cross into Double
only inside the PonderNet objective (products of exact integers with 0/1
masses; the zero/nonzero dichotomy survives the crossing).
-}
-- COMPARTMENT: MLX-MODEL | tag:MacTag
module SixFour.Spec.KinematicHaltPrior
  ( -- * The exact observable and its losses
    certifiedOrder
  , residualLoss
    -- * The pointed prior
  , certifiedLambdas
    -- * Laws
  , lawResidualZeroIffAtOrAboveOrder
  , lawCertifiedPriorIsProperAndPointed
  , lawCertifiedPriorSpendsExactlyK
  , lawCertifiedPriorAchievesZeroLoss
  , lawEarlyHaltPaysResidual
  , lawCheapestZeroLossHaltIsCertifiedOrder
  ) where

import SixFour.Spec.KinematicLadder (nthDiff, newtonPredict)
import SixFour.Spec.PonderHaltDistribution (haltDist, expectedLoss, expectedSteps)

-- | The certified kinematic order of a trajectory: the smallest k < cap with
-- Δ^{k+1} ≡ 0 on the window (cap if none certifies). An EXACT Integer
-- observable — computable on-device in integer arithmetic before any learning.
certifiedOrder :: Int -> [Integer] -> Int
certifiedOrder cap f =
  head ([ k | k <- [0 .. cap - 1], all (== 0) (nthDiff (k + 1) f) ] ++ [cap])

-- | The exact per-depth loss: L_j = Σ_t |f(t) − f̂_j(t)| with f̂_j the order-j
-- truncated Newton prediction. Integer — zero means byte-exact reproduction.
residualLoss :: Int -> [Integer] -> Integer
residualLoss j f =
  sum [ abs (f !! t - newtonPredict j f (fromIntegral t)) | t <- [0 .. length f - 1] ]

-- | The pointed prior: per-step halt probabilities that put ALL halt mass at
-- step k of cap+1 steps (λ_k = 1, others 0) — "halt exactly at depth k".
certifiedLambdas :: Int -> Int -> [Double]
certifiedLambdas cap k = [ if i == k then 1 else 0 | i <- [0 .. cap - 1] ]

-- A polynomial trajectory of exact degree d on a 10-tick window: the leading
-- coefficient is forced odd (2c+1) so Δ^d = d!·a_d ≠ 0 and the certified
-- order is d by construction.
trajectory :: Int -> [Integer] -> [Integer]
trajectory d coeffs =
  [ sum [ a i * t ^ i | i <- [0 .. d] ] | t <- [0 .. 9] ]
  where
    padded = take 4 (map ((`mod` 25) . abs) coeffs ++ repeat 0)
    a i = if i == d then 2 * (padded !! i) + 1 else padded !! i

cap :: Int
cap = 4

-- | LAW (minimal sufficiency, the iff): L_j == 0 ⇔ j ≥ certifiedOrder —
-- kinematic order == the minimal exactly-sufficient halting depth == the
-- S-packets owed. Both directions, exact integers.
lawResidualZeroIffAtOrAboveOrder :: Int -> [Integer] -> Bool
lawResidualZeroIffAtOrAboveOrder dRaw coeffs =
  and [ (residualLoss j f == 0) == (j >= k) | j <- [0 .. cap] ]
  where
    f = trajectory (abs dRaw `mod` 4) coeffs
    k = certifiedOrder cap f

-- | LAW: the pointed prior is a PROPER distribution with mass exactly 1 at the
-- certified step (products of exact 0/1 survive the Double crossing).
lawCertifiedPriorIsProperAndPointed :: Int -> Bool
lawCertifiedPriorIsProperAndPointed kRaw =
  sum dist == 1 && dist !! k == 1 && all (== 0) (take k dist)
  where
    k = abs kRaw `mod` cap
    dist = haltDist (certifiedLambdas cap k)

-- | LAW: the certified prior spends exactly k+1 expected steps (the
-- machinery's 1-based step count) — the compute bill equals the depth claimed.
lawCertifiedPriorSpendsExactlyK :: Int -> Bool
lawCertifiedPriorSpendsExactlyK kRaw =
  expectedSteps (haltDist (certifiedLambdas cap k)) == fromIntegral (k + 1)
  where k = abs kRaw `mod` cap

-- | LAW: on a certified trajectory, the certified prior achieves exactly ZERO
-- expected PonderNet loss — certification is optimal under the objective the
-- trainer minimizes, not merely plausible.
lawCertifiedPriorAchievesZeroLoss :: Int -> [Integer] -> Bool
lawCertifiedPriorAchievesZeroLoss dRaw coeffs =
  expectedLoss (haltDist (certifiedLambdas cap k)) losses == 0
  where
    f = trajectory (abs dRaw `mod` 4) coeffs
    k = certifiedOrder cap f
    losses = [ fromInteger (residualLoss j f) | j <- [0 .. cap] ]

-- | TEETH: halting even ONE step below the certified order pays strictly
-- positive expected loss (an Integer residual ≥ 1, not an epsilon) — an
-- early-halting gene is provably lying, by integer arithmetic.
lawEarlyHaltPaysResidual :: Int -> [Integer] -> Bool
lawEarlyHaltPaysResidual dRaw coeffs =
  k == 0 || expectedLoss (haltDist (certifiedLambdas cap (k - 1))) losses >= 1
  where
    f = trajectory (1 + abs dRaw `mod` 3) coeffs  -- degree ≥ 1 so k ≥ 1
    k = certifiedOrder cap f
    losses = [ fromInteger (residualLoss j f) | j <- [0 .. cap] ]

-- | LAW (KEYSTONE — the wiring): among all pointed haltings, the CHEAPEST one
-- with zero expected loss is exactly the certified order: zero-loss ⇔ depth ≥
-- k, and steps grow with depth, so argmin = k. Halting depth is now derived
-- from the objective, not asserted.
lawCheapestZeroLossHaltIsCertifiedOrder :: Int -> [Integer] -> Bool
lawCheapestZeroLossHaltIsCertifiedOrder dRaw coeffs =
  minimum zeroLossDepths == k
    && and [ (j `elem` zeroLossDepths) == (j >= k) | j <- [0 .. cap] ]
  where
    f = trajectory (abs dRaw `mod` 4) coeffs
    k = certifiedOrder cap f
    losses = [ fromInteger (residualLoss j f) | j <- [0 .. cap] ]
    zeroLossDepths =
      [ j | j <- [0 .. cap]
          , expectedLoss (haltDist (certifiedLambdas (cap + 1) j)) losses == 0 ]

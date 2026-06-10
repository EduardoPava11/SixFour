{- |
Module      : SixFour.Spec.PreferenceUpdate
Description : The on-device Bradley–Terry update rule 'Preference.hs'
              deliberately omits — the flywheel turns from move #1.

Design §5 (@docs/COLOR-ATLAS.md@). 'SixFour.Spec.Preference' pins the
Bradley–Terry MODEL (@P(w ≻ l) = σ(u(w) − u(l))@, 'linearUtility',
'btProbability') but no learning rule. This module supplies the per-Compare
SGD step the device runs with NO Mac round-trip:

@
θ ← θ + η·(1 − σ(θ·(w−l)))·(w−l) − η·λ·θ        η = 0.05, λ = 1e-3, dims = 770
@

(~3 KB of state at 770 float32 on device.) The loss is the negative
log-likelihood of the observed pair under the BT link; the update is exact
gradient descent on it plus L2 ('lawGradientFiniteDiff' pins the gradient
against central differences).

DOCUMENTED NON-LAW: 'btFit' (a left fold of 'btUpdate') is NOT
order-independent — SGD never is. Replay therefore stores pairs in decision
order (the SF64 DECN chunk is ordered) and the law suite does not claim fold
commutativity.
-}
module SixFour.Spec.PreferenceUpdate
  ( -- * Dimensions and default hyperparameters
    thetaDim
  , defaultEta
  , defaultLambda
    -- * Loss, gradient, update
  , btPairLoss
  , btLogLoss
  , btPairGradient
  , btUpdate
  , btFit
    -- * Laws (predicates; QuickCheck'd in Properties.PreferenceUpdate)
  , lawGradientFiniteDiff
  , lawStepDecreasesLoss
  , lawSwapAntisymmetry
  , lawThetaBounded
  ) where

import Data.List (foldl')

import SixFour.Spec.Preference (Embedding, btProbability, linearUtility)

-- | θ dimension: the 770-D 'AtlasState.atlasEmbedding'
-- (256 leaves × 3 ++ [coverage, beauty]).
thetaDim :: Int
thetaDim = 770

-- | Default learning rate η.
defaultEta :: Double
defaultEta = 0.05

-- | Default L2 weight decay λ.
defaultLambda :: Double
defaultLambda = 1.0e-3

-- ---------------------------------------------------------------------------
-- Loss / gradient / update
-- ---------------------------------------------------------------------------

-- | Negative log-likelihood of the observed pair (winner @w@, loser @l@)
-- under the Bradley–Terry link: @−log σ(θ·(w − l))@. (Unregularised — the L2
-- term lives in the update, matching the design's update rule.)
btPairLoss :: [Double] -> Embedding -> Embedding -> Double
btPairLoss theta w l =
  negate (log (btProbability (linearUtility theta (zipWith (-) w l))))

-- | The design-table name for 'btPairLoss' (COLOR-ATLAS §7 lists the export
-- as @btLogLoss@ — the BT negative log-likelihood of one ordered pair).
btLogLoss :: [Double] -> Embedding -> Embedding -> Double
btLogLoss = btPairLoss

-- | The exact gradient of 'btPairLoss' w.r.t. θ:
-- @∇ᵢ = −(1 − σ(θ·d))·dᵢ@ with @d = w − l@.
btPairGradient :: [Double] -> Embedding -> Embedding -> [Double]
btPairGradient theta w l =
  let d = zipWith (-) w l
      g = 1 - btProbability (linearUtility theta d)
  in map (negate . (g *)) d

-- | One SGD step on a Compare: gradient descent on 'btPairLoss' plus L2.
-- @θᵢ ← θᵢ + η·(1 − σ(θ·d))·dᵢ − η·λ·θᵢ@.
btUpdate :: Double -> Double -> [Double] -> (Embedding, Embedding) -> [Double]
btUpdate eta lambda theta (w, l) =
  let d = zipWith (-) w l
      g = 1 - btProbability (linearUtility theta d)
  in zipWith (\t di -> t + eta * g * di - eta * lambda * t) theta d

-- | Fold a sequence of Compare pairs (oldest first) over an initial θ.
-- ORDER-DEPENDENT by design (see the module header's documented non-law).
btFit :: Double -> Double -> [Double] -> [(Embedding, Embedding)] -> [Double]
btFit eta lambda = foldl' (btUpdate eta lambda)

-- ---------------------------------------------------------------------------
-- Laws
-- ---------------------------------------------------------------------------

-- | 'btPairGradient' matches the central finite difference of 'btPairLoss'
-- (h = 1e-5, tolerance 1e-6) componentwise.
lawGradientFiniteDiff :: [Double] -> Embedding -> Embedding -> Bool
lawGradientFiniteDiff theta w l =
  and [ abs (g - fd i) < 1e-6 | (i, g) <- zip [0 ..] (btPairGradient theta w l) ]
  where
    h = 1e-5
    fd i =
      let bump s = [ if j == i then t + s else t | (j, t) <- zip [0 ..] theta ]
      in (btPairLoss (bump h) w l - btPairLoss (bump (negate h)) w l) / (2 * h)

-- | One step with λ = 0 STRICTLY decreases the pair's loss whenever the pair
-- is informative (@‖w − l‖² > 1e-6@) and η ∈ (0, 1]. (The BT loss is strictly
-- decreasing in the utility gap, and the step strictly increases the gap by
-- @η·g·‖d‖² > 0@.)
lawStepDecreasesLoss :: Double -> [Double] -> Embedding -> Embedding -> Bool
lawStepDecreasesLoss eta theta w l =
  let d  = zipWith (-) w l
      n2 = sum (map (^ (2 :: Int)) d)
  in eta <= 0 || eta > 1 || n2 <= 1e-6 ||
     btPairLoss (btUpdate eta 0 theta (w, l)) w l < btPairLoss theta w l

-- | Swap antisymmetry of the link: the two orderings' likelihoods sum to 1 —
-- @exp(−loss(w,l)) + exp(−loss(l,w)) = 1@ (ε).
lawSwapAntisymmetry :: [Double] -> Embedding -> Embedding -> Bool
lawSwapAntisymmetry theta w l =
  abs (exp (negate (btPairLoss theta w l))
       + exp (negate (btPairLoss theta l w)) - 1) < 1e-9

-- | L2 keeps θ in a ball: with @0 < η·λ ≤ 1@ and every @|wᵢ − lᵢ| ≤ dmax@,
-- one update keeps @‖θ‖∞ ≤ max(‖θ₀‖∞, dmax/λ)@ (ε). Pins that the on-device
-- accumulator cannot blow up under any Compare stream.
lawThetaBounded :: Double -> Double -> Double -> [Double] -> Embedding -> Embedding -> Bool
lawThetaBounded eta lambda dmax theta w l =
  let dOk    = all (\(wi, li) -> abs (wi - li) <= dmax) (zip w l)
      preOk  = eta > 0 && lambda > 0 && eta * lambda <= 1 && dmax >= 0
      bound  = max (maxAbs theta) (dmax / lambda)
      theta' = btUpdate eta lambda theta (w, l)
  in not (preOk && dOk) || maxAbs theta' <= bound + 1e-12
  where maxAbs xs = maximum (0 : map abs xs)

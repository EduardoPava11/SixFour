{- |
Module      : SixFour.Spec.ValueHead
Description : The learned Bradley–Terry value head — a proven linear floor + a
              gated tanh residual, with an on-device training step (nn-6).

The forward of this head already exists and is golden-pinned
('SixFour.Spec.AtlasNetEval.atlasValue', a 24→32→1 MLP). What had no spec was its
TRAINING law — the MLP counterpart of the LINEAR 'SixFour.Spec.PreferenceUpdate'.
This module supplies it: the Bradley–Terry loss (with label smoothing for noisy
picks), the analytic gradient (pinned against central finite differences by
'lawValueGradientFiniteDiff' — the law that catches any backprop bug), and the
SGD step the device runs from one A/B Compare.

== One rule, linear is the zero-residual case

The head is a LINEAR taste floor plus a GATED nonlinear residual:

@
  u(x) = θ·x + Σⱼ w₂ⱼ · tanh(W₁ⱼ·x + b₁ⱼ)
@

With the residual gate @w₂ = 0@ the head is EXACTLY the linear Bradley–Terry head
('lawReducesToLinear'), and its training gradient collapses to
'SixFour.Spec.PreferenceUpdate.btPairGradient' ('lawReducesToLinearGradient'). So
"linear vs MLP" is a runtime switch over a SINGLE proven training rule, gated on
whether on-device replay shows the residual earning its capacity — not two code
paths. (Same residual-above-a-proven-floor motif as the 256³ super-res.)

== Why tanh + label smoothing

'tanh' is smooth, so the analytic gradient is finite-difference-checkable to ~1e-7
(a ReLU kink gives spurious ~1e-4). Label smoothing @ε@ gives the BT loss a FINITE
optimal margin @logit(1−ε)@ ('lawSmoothingHasFiniteOptimum'), so a noisy/misclick
pick cannot push the margin to ∞ — the bounded-confidence the linear head lacked.

Params are a flat vector (so the finite-difference law is a clean per-scalar bump),
laid out @θ(n) ++ W₁(h·n, row-major) ++ b₁(h) ++ w₂(h)@. GHC-boot-only; laws are
QuickCheck'd in 'Properties.ValueHead'.
-}
module SixFour.Spec.ValueHead
  ( -- * Shape
    ValueShape(..)
  , defaultValueShape
  , paramCount
    -- * Hyperparameters
  , defaultLabelSmoothing
    -- * Forward, loss, gradient, update
  , valueScore
  , marginLoss
  , smoothedBTLoss
  , valuePairGradient
  , valueUpdate
  , zeroResidual
    -- * Laws (QuickCheck'd in Properties.ValueHead)
  , lawValueGradientFiniteDiff
  , lawValueStepDecreasesLoss
  , lawReducesToLinear
  , lawReducesToLinearGradient
  , lawSmoothingHasFiniteOptimum
  ) where

import SixFour.Spec.Preference      (Embedding, btProbability, linearUtility)
import SixFour.Spec.PreferenceUpdate (btPairGradient)

-- ---------------------------------------------------------------------------
-- Shape and hyperparameters
-- ---------------------------------------------------------------------------

-- | The head's shape: @vsIn@ input features, @vsHidden@ tanh units (output is a
-- single scalar value). The deployed head is 'defaultValueShape' = 24→32→1.
data ValueShape = ValueShape
  { vsIn     :: Int   -- ^ input feature dimension
  , vsHidden :: Int   -- ^ hidden tanh units
  } deriving (Eq, Show)

-- | The deployed value head shape (mirrors 'SixFour.Spec.AtlasNetEval.atlasValue').
defaultValueShape :: ValueShape
defaultValueShape = ValueShape 24 32

-- | Number of flat parameters for a shape: @n + h·n + h + h = n + h·(n+2)@.
paramCount :: ValueShape -> Int
paramCount (ValueShape n h) = n + h * n + h + h

-- | Default label-smoothing ε (bounds the optimal margin at @logit(1−ε)@).
defaultLabelSmoothing :: Double
defaultLabelSmoothing = 0.05

-- ---------------------------------------------------------------------------
-- Parameter slicing (flat layout: theta(n) ++ W1(h*n) ++ b1(h) ++ w2(h))
-- ---------------------------------------------------------------------------

chunksOf :: Int -> [a] -> [[a]]
chunksOf _ [] = []
chunksOf k xs = take k xs : chunksOf k (drop k xs)

slice :: ValueShape -> [Double] -> ([Double], [[Double]], [Double], [Double])
slice (ValueShape n h) ps =
  let theta = take n ps
      w1    = chunksOf n (take (h * n) (drop n ps))
      b1    = take h (drop (n + h * n) ps)
      w2    = take h (drop (n + h * n + h) ps)
  in (theta, w1, b1, w2)

-- | Zero the residual gate @w₂@ (leaving the linear floor θ and hidden weights),
-- collapsing the head to its linear Bradley–Terry floor.
zeroResidual :: ValueShape -> [Double] -> [Double]
zeroResidual sh@(ValueShape n h) ps =
  take (n + h * n + h) ps ++ replicate h 0

-- ---------------------------------------------------------------------------
-- Forward / loss / gradient / update
-- ---------------------------------------------------------------------------

-- | Forward, also returning the pre-activations and tanh activations (reused by
-- the gradient). @u(x) = θ·x + Σⱼ w₂ⱼ·tanh(W₁ⱼ·x + b₁ⱼ)@.
forwardParts :: ValueShape -> [Double] -> Embedding -> (Double, [Double])
forwardParts sh ps x =
  let (theta, w1, b1, w2) = slice sh ps
      lin = sum (zipWith (*) theta x)
      as  = [ tanh (sum (zipWith (*) row x) + b) | (row, b) <- zip w1 b1 ]
      res = sum (zipWith (*) w2 as)
  in (lin + res, as)

-- | The scalar value @u(x)@ the head assigns a candidate feature vector.
valueScore :: ValueShape -> [Double] -> Embedding -> Double
valueScore sh ps x = fst (forwardParts sh ps x)

-- | The Bradley–Terry loss as a function of the utility MARGIN @Δ = u(w) − u(l)@,
-- with label smoothing @ε@: @−(1−ε)·log σ(Δ) − ε·log σ(−Δ)@. Convex in @Δ@ with a
-- finite minimum at @Δ = logit(1−ε)@.
marginLoss :: Double -> Double -> Double
marginLoss eps d =
  negate ((1 - eps) * logSig d + eps * logSig (negate d))
  where logSig z = log (btProbability z)

-- | The label-smoothed Bradley–Terry pair loss for the head on an ordered Compare
-- (winner @w@, loser @l@): 'marginLoss' of the value margin.
smoothedBTLoss :: Double -> ValueShape -> [Double] -> Embedding -> Embedding -> Double
smoothedBTLoss eps sh ps w l =
  marginLoss eps (valueScore sh ps w - valueScore sh ps l)

-- | The exact gradient of 'smoothedBTLoss' w.r.t. every flat parameter (same
-- layout), by backprop. @∂L/∂Δ = σ(Δ) − (1−ε)@, chained through the linear floor
-- and the tanh residual. Pinned against finite differences by
-- 'lawValueGradientFiniteDiff'.
valuePairGradient :: Double -> ValueShape -> [Double] -> Embedding -> Embedding -> [Double]
valuePairGradient eps sh ps w l =
  let (uw, aw) = forwardParts sh ps w
      (ul, al) = forwardParts sh ps l
      d     = uw - ul
      dLdD  = btProbability d - (1 - eps)            -- σ(Δ) − (1−ε)
      (_, _, _, w2) = slice sh ps
      -- ∂Δ/∂θ[k] = w[k] − l[k]
      gTheta = zipWith (-) w l
      -- tanh'(z) = 1 − tanh(z)^2, and aw/al are the tanh activations already.
      sw = map (\a -> 1 - a * a) aw
      sl = map (\a -> 1 - a * a) al
      -- ∂Δ/∂W1[j][k] = w2[j]·(sw[j]·w[k] − sl[j]·l[k])
      gW1 = concat [ [ w2j * (swj * wk - slj * lk) | (wk, lk) <- zip w l ]
                   | (w2j, swj, slj) <- zip3 w2 sw sl ]
      -- ∂Δ/∂b1[j] = w2[j]·(sw[j] − sl[j])
      gB1 = [ w2j * (swj - slj) | (w2j, swj, slj) <- zip3 w2 sw sl ]
      -- ∂Δ/∂w2[j] = aw[j] − al[j]
      gW2 = zipWith (-) aw al
  in map (dLdD *) (gTheta ++ gW1 ++ gB1 ++ gW2)

-- | One on-device SGD step on a Compare: gradient descent on 'smoothedBTLoss' plus
-- decoupled L2 weight decay. @p ← p − η·∂L/∂p − η·λ·p@.
valueUpdate :: Double -> Double -> Double -> ValueShape -> [Double] -> (Embedding, Embedding) -> [Double]
valueUpdate eta lambda eps sh ps (w, l) =
  let g = valuePairGradient eps sh ps w l
  in zipWith (\p gi -> p - eta * gi - eta * lambda * p) ps g

-- ---------------------------------------------------------------------------
-- Laws
-- ---------------------------------------------------------------------------

-- | The analytic 'valuePairGradient' matches the central finite difference of
-- 'smoothedBTLoss' componentwise (h = 1e-5, tol 1e-5). The correctness gate for
-- the backprop — tanh's smoothness is what keeps this sharp.
lawValueGradientFiniteDiff :: Double -> ValueShape -> [Double] -> Embedding -> Embedding -> Bool
lawValueGradientFiniteDiff eps sh ps w l =
  and [ abs (g - fd i) < 1e-5 | (i, g) <- zip [0 ..] (valuePairGradient eps sh ps w l) ]
  where
    hh = 1e-5
    fd i =
      let bump s = [ if j == i then p + s else p | (j, p) <- zip [(0 :: Int) ..] ps ]
      in (smoothedBTLoss eps sh (bump hh) w l - smoothedBTLoss eps sh (bump (negate hh)) w l)
           / (2 * hh)

-- | A small-η gradient step does not increase the (unsmoothed) pair loss — local
-- descent. Guarded to η ∈ (0, 0.05] and an informative pair (nonzero gradient);
-- the head is nonconvex, so only a small step is guaranteed to descend.
lawValueStepDecreasesLoss :: Double -> ValueShape -> [Double] -> Embedding -> Embedding -> Bool
lawValueStepDecreasesLoss eta sh ps w l =
  let g   = valuePairGradient 0 sh ps w l
      gn2 = sum (map (^ (2 :: Int)) g)
      ps' = zipWith (\p gi -> p - eta * gi) ps g
  in eta <= 0 || eta > 0.05 || gn2 <= 1e-9 ||
     smoothedBTLoss 0 sh ps' w l <= smoothedBTLoss 0 sh ps w l + 1e-9

-- | With the residual gate @w₂ = 0@ the head IS the linear Bradley–Terry floor:
-- @valueScore = θ·x@ exactly. Linear is the zero-residual special case.
lawReducesToLinear :: ValueShape -> [Double] -> Embedding -> Bool
lawReducesToLinear sh ps x =
  let (theta, _, _, _) = slice sh ps
  in valueScore sh (zeroResidual sh ps) x == linearUtility theta x

-- | With @w₂ = 0@ and no smoothing, the head's training gradient on θ collapses to
-- the proven linear 'SixFour.Spec.PreferenceUpdate.btPairGradient' (ε within FP).
-- This pins that the MLP step is continuous with the trusted linear head.
lawReducesToLinearGradient :: ValueShape -> [Double] -> Embedding -> Embedding -> Bool
lawReducesToLinearGradient sh ps w l =
  let (theta, _, _, _) = slice sh ps
      n   = vsIn sh
      gTh = take n (valuePairGradient 0 sh (zeroResidual sh ps) w l)
  in and (zipWith (\a b -> abs (a - b) < 1e-9) gTh (btPairGradient theta w l))

-- | Label smoothing gives the loss a FINITE optimal margin: 'marginLoss' is
-- minimized at @Δ = logit(1−ε)@ (for 0 < ε < ½), so a noisy pick cannot drive the
-- margin to ∞. (Convex in Δ ⇒ the stationary point is the global minimum.)
lawSmoothingHasFiniteOptimum :: Double -> Double -> Bool
lawSmoothingHasFiniteOptimum eps delta =
  eps <= 0 || eps >= 0.5 ||
  marginLoss eps (logit (1 - eps)) <= marginLoss eps delta + 1e-9
  where logit p = log (p / (1 - p))

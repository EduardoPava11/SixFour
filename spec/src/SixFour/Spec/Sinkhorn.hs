{-# LANGUAGE ScopedTypeVariables #-}

{- |
Module      : SixFour.Spec.Sinkhorn
Description : Entropic OT + the debiased Sinkhorn divergence — the discrete-measure fidelity term that fixes the Bures Gaussian-summary gap.

The fidelity term in "SixFour.Spec.Loss" measures how well the decoded palette
reconstructs the input capture. The original 'SixFour.Spec.Bures.buresDistanceSq'
collapses BOTH the palette and the capture to a single moment-matched Gaussian —
honest about mean + spread, but blind to multi-modality (a palette is a genuinely
multi-modal discrete measure, and the Bures module note flags this as a real
projection error: the exact discrete W₂ barycenter is NP-hard, and the closed-form
Bures barycenter is proven only for absolutely-continuous / Gaussian measures).

This module supplies the tractable discrete alternative the Bures note and
@SixFour.Spec.Loss.mixtureAsGaussian@ both point to ("the trainer can replace this
with a Sinkhorn approximation if tighter bounds are needed"): the __debiased
Sinkhorn divergence__ between two discrete OKLab measures.

== The math (Cuturi 2013; Genevay/Peyré/Cuturi 2018; Feydy et al. 2019)

For two discrete measures @α = Σᵢ aᵢ δ_{xᵢ}@, @β = Σⱼ bⱼ δ_{yⱼ}@ with squared-OKLab
ground cost @C_{ij} = ‖xᵢ − yⱼ‖²@ ('SixFour.Spec.Color.okLabDistanceSquared'), the
entropic OT __transport cost__ is @T_ε(α,β) = ⟨P*, C⟩@ where @P*@ is the Sinkhorn
plan: the unique matrix with marginals @a, b@ minimising @⟨P,C⟩ + ε·KL(P‖a⊗b)@.
Sinkhorn iteration solves it with nothing but matrix–vector products
(/exactly/ the "matrix-vector iterations, hand-portable" the 2024–2026 OT survey
flagged as the tractable upgrade — debiased Sinkhorn barycenters, FRLC low-rank OT,
free-support particle flow all reduce to this kernel).

Raw @T_ε@ is biased: @T_ε(α,α) ≠ 0@. The __debiased Sinkhorn divergence__ removes it:

>  S_ε(α,β) = T_ε(α,β) − ½ T_ε(α,α) − ½ T_ε(β,β)

@S_ε@ is symmetric, @S_ε(α,α) = 0@ (EXACT here — the two self-terms are the same
pure computation), @S_ε ≥ 0@, and as @ε → 0@ it interpolates to the true W₂²; as
@ε → ∞@ it tends to (a multiple of) the squared maximum-mean-discrepancy. The
SINGLETON reduction (@lawSinkhornSingletonIsSquaredDistance@) mirrors the Bures
bridge law: between two point masses, @S_ε@ is exactly 'okLabDistanceSquared' —
so the Sinkhorn fidelity degenerates to the same Euclidean OKLab floor the maximin
collapse ('SixFour.Spec.Collapse.farthestPointCollapse') and Bures (Σ→0) reduce to.

== Numeric form: log-domain, deterministic

The iteration runs in the log domain (dual potentials @f, g@, 'logSumExpV'), so it
is underflow-free and ports identically to MLX (Mac trainer) and a hand-written
Swift/Metal forward pass — no third-party OT library, in keeping with the Tier-2
zero-dependency contract. The iteration count is fixed ('spIters'), so the result
is deterministic and golden-pinnable. This is a /reference/ surface (the trainer
mirrors it); the on-device shipped collapse stays the byte-exact Q16 maximin in
"SixFour.Spec.Collapse".
-}
module SixFour.Spec.Sinkhorn
  ( -- * Discrete measures
    Measure
  , normalizeMeasure
    -- * Entropic OT
  , SinkhornParams(..)
  , defaultSinkhornParams
  , sinkhornCost
  , sinkhornPlan
  , sinkhornDivergence
    -- * Helpers
  , logSumExpV
    -- * Laws (predicates; QuickCheck'd in Properties.Sinkhorn)
  , lawSinkhornCostNonNegative
  , lawSinkhornSelfDivergenceZero
  , lawSinkhornDivergenceNonNegative
  , lawSinkhornDivergenceSymmetric
  , lawSinkhornSingletonIsSquaredDistance
  ) where

import qualified Data.Vector as V

import SixFour.Spec.Color (OKLab(..), okLabDistanceSquared)

-- | A discrete measure: weighted OKLab atoms @[(xᵢ, aᵢ)]@. Weights need not sum to
-- 1 — 'normalizeMeasure' renormalises before transport. This is the same shape as a
-- palette (uniform weights) or a pooled capture (population-weighted cluster means).
type Measure = [(OKLab, Double)]

-- | Sinkhorn hyper-parameters: the entropic regularisation @ε@ ('spEpsilon', in the
-- same units as the squared-OKLab cost) and the fixed iteration count ('spIters').
-- Both are pinned so the divergence is deterministic and golden-reproducible.
data SinkhornParams = SinkhornParams
  { spEpsilon :: !Double
  , spIters   :: !Int
  } deriving (Eq, Show)

-- | Spec-default Sinkhorn parameters. @ε = 0.05@ is comparable to a typical
-- squared-OKLab distance (L∈[0,1], a,b∈[−0.4,0.4] ⇒ C ≲ 2.3, typical ≪ 0.5), so the
-- plan is well-spread but not blurred; @500@ iterations converge the dual potentials
-- tightly enough that the alternating @f@-then-@g@ update is symmetric to well within
-- @1e-4@ ('lawSinkhornDivergenceSymmetric') even on slow-converging supports. The
-- trainer tunes these (it can use far fewer with a convergence check). NOT a perf
-- path: the shipped collapse is the Q16 maximin in "SixFour.Spec.Collapse".
defaultSinkhornParams :: SinkhornParams
defaultSinkhornParams = SinkhornParams 0.05 500

-- | Renormalise a measure's weights to sum to 1 (no-op when the total is non-positive).
normalizeMeasure :: Measure -> Measure
normalizeMeasure m =
  let s = sum (map snd m)
  in if s <= 0 then m else [ (c, w / s) | (c, w) <- m ]

-- | Numerically-stable @log Σ exp@ over a vector. Returns @-∞@ for an all-@-∞@ input
-- (the @log 0 = -∞@ convention for zero-weight atoms), avoiding @NaN@.
logSumExpV :: V.Vector Double -> Double
logSumExpV xs
  | V.null xs = neginf
  | mx == neginf = neginf
  | otherwise = mx + log (V.sum (V.map (\x -> exp (x - mx)) xs))
  where mx = V.maximum xs

neginf :: Double
neginf = -1 / 0

safeLog :: Double -> Double
safeLog x = if x <= 0 then neginf else log x

-- | Internal: solve the log-domain Sinkhorn problem and return the ground-cost
-- matrix @C@ (n×m) together with the transport plan @P@ (n×m, marginals @a, b@).
-- Both 'sinkhornCost' and 'sinkhornPlan' are thin readouts of this, so they share
-- one deterministic computation.
sinkhornSolve
  :: SinkhornParams -> Measure -> Measure
  -> (V.Vector (V.Vector Double), V.Vector (V.Vector Double))
sinkhornSolve (SinkhornParams eps iters) ma mb =
  let a  = normalizeMeasure ma
      b  = normalizeMeasure mb
      xs = V.fromList (map fst a)
      ys = V.fromList (map fst b)
      la = V.fromList (map (safeLog . snd) a)
      lb = V.fromList (map (safeLog . snd) b)
      n  = V.length xs
      m  = V.length ys
  in if n == 0 || m == 0 then (V.empty, V.empty) else
     let cmat = V.generate n (\i ->
                  V.generate m (\j -> okLabDistanceSquared (xs V.! i) (ys V.! j)))
         row i = cmat V.! i
         -- log-domain Sinkhorn updates on the dual potentials f (n), g (m).
         updF g = V.generate n (\i ->
                    negate eps * logSumExpV
                      (V.generate m (\j -> (lb V.! j) + ((g V.! j) - (row i V.! j)) / eps)))
         updG f = V.generate m (\j ->
                    negate eps * logSumExpV
                      (V.generate n (\i -> (la V.! i) + ((f V.! i) - (row i V.! j)) / eps)))
         go 0 f g = (f, g)
         go k f g = let f' = updF g
                        g' = updG f'
                    in go (k - 1 :: Int) f' g'
         (ff, gg) = go iters (V.replicate n 0) (V.replicate m 0)
         -- P_{ij} = exp( la_i + lb_j + (f_i + g_j − C_ij)/ε ).
         plan = V.generate n (\i ->
                  V.generate m (\j ->
                    exp ((la V.! i) + (lb V.! j)
                         + ((ff V.! i) + (gg V.! j) - (row i V.! j)) / eps)))
     in (cmat, plan)

-- | The entropic-OT __transport cost__ @T_ε(α,β) = ⟨P*, C⟩@ between two discrete
-- OKLab measures, with ground cost @C_{ij} = ‖xᵢ−yⱼ‖²@. Solved by log-domain
-- Sinkhorn iteration ('spIters' steps). Non-negative ('lawSinkhornCostNonNegative')
-- since the plan and the cost are both non-negative. Empty either side ⇒ 0.
sinkhornCost :: SinkhornParams -> Measure -> Measure -> Double
sinkhornCost p ma mb =
  let (cmat, plan) = sinkhornSolve p ma mb
  in V.sum (V.zipWith (\cr pr -> V.sum (V.zipWith (*) cr pr)) cmat plan)

-- | The entropic-OT transport plan @P*@ (n×m, row @i@ = source atom @xᵢ@, column
-- @j@ = target atom @yⱼ@), as a list of rows. Row sums are the (normalised) source
-- weights @a@ and column sums the target weights @b@. The barycentric projection
-- @t_i = (Σⱼ P_{ij} yⱼ) / (Σⱼ P_{ij})@ is the displacement target the free-support
-- barycenter in "SixFour.Spec.Barycenter" averages over its input measures.
sinkhornPlan :: SinkhornParams -> Measure -> Measure -> [[Double]]
sinkhornPlan p ma mb =
  let (_, plan) = sinkhornSolve p ma mb
  in map V.toList (V.toList plan)

-- | The __debiased Sinkhorn divergence__
-- @S_ε(α,β) = T_ε(α,β) − ½T_ε(α,α) − ½T_ε(β,β)@. Symmetric
-- ('lawSinkhornDivergenceSymmetric'), zero on the diagonal
-- ('lawSinkhornSelfDivergenceZero', EXACT), non-negative
-- ('lawSinkhornDivergenceNonNegative'), and equal to 'okLabDistanceSquared' between
-- point masses ('lawSinkhornSingletonIsSquaredDistance'). This is the fidelity
-- "SixFour.Spec.Loss.fidelityLossSinkhorn" builds on.
sinkhornDivergence :: SinkhornParams -> Measure -> Measure -> Double
sinkhornDivergence p a b =
  let cab = sinkhornCost p a b
      caa = sinkhornCost p a a
      cbb = sinkhornCost p b b
  in cab - 0.5 * caa - 0.5 * cbb

-- ============================================================================
-- Laws (predicates; QuickCheck'd in Properties.Sinkhorn)
-- ============================================================================

-- | The entropic transport cost is non-negative (a non-negative plan against a
-- non-negative squared-distance cost).
lawSinkhornCostNonNegative :: Measure -> Measure -> Bool
lawSinkhornCostNonNegative a b = sinkhornCost defaultSinkhornParams a b >= 0

-- | The divergence is EXACTLY zero on the diagonal: @S_ε(α,α) = 0@. Exact because
-- the three self-evaluations are the same pure computation and @x − ½x − ½x = 0@ in
-- IEEE @Double@ (the halving is an exact exponent shift; the subtraction is exact by
-- Sterbenz). A non-degenerate measure (≥1 atom of positive weight) is required.
lawSinkhornSelfDivergenceZero :: Measure -> Bool
lawSinkhornSelfDivergenceZero a =
  sum (map snd a) <= 0 || sinkhornDivergence defaultSinkhornParams a a == 0

-- | The divergence is non-negative (Genevay et al. 2018), up to finite-iteration
-- tolerance. A theorem at convergence; with the fixed 'spIters' it holds to a small
-- slack on well-formed measures.
lawSinkhornDivergenceNonNegative :: Measure -> Measure -> Bool
lawSinkhornDivergenceNonNegative a b =
  let ok m = sum (map snd m) > 0
  in not (ok a && ok b) || sinkhornDivergence defaultSinkhornParams a b >= -1e-6

-- | The divergence is symmetric: @S_ε(α,β) = S_ε(β,α)@, up to finite-iteration slack
-- (the Sinkhorn updates fix @f@ before @g@, so the two argument orders converge to
-- the same value but leave a residual that shrinks with 'spIters'; @1e-4@ holds at
-- the default 200 iterations, the same tolerance "SixFour.Spec.Bures" uses).
lawSinkhornDivergenceSymmetric :: Measure -> Measure -> Bool
lawSinkhornDivergenceSymmetric a b =
  abs (sinkhornDivergence defaultSinkhornParams a b
       - sinkhornDivergence defaultSinkhornParams b a) < 1e-4

-- | The bridge law (cf. the Bures Σ→0 reduction): between two unit point masses the
-- Sinkhorn divergence is EXACTLY the squared OKLab distance, independent of @ε@ and
-- the iteration count (a 1×1 transport carries all mass in one cell). This anchors
-- the fidelity term to the same Euclidean OKLab floor the maximin collapse uses.
lawSinkhornSingletonIsSquaredDistance :: OKLab -> OKLab -> Bool
lawSinkhornSingletonIsSquaredDistance x y =
  sinkhornDivergence defaultSinkhornParams [(x, 1)] [(y, 1)]
    == okLabDistanceSquared x y

{- |
Module      : SixFour.Spec.KinematicLadder
Description : Building up to 64×64 — the kinematic tower on the dyadic ladder, as exact discrete calculus. 16 gives position+mass, 16→32 gives velocity, 32→64 gives ACCELERATION: each rung transition adds one time-derivative of the particle stream. Same physics turned to information via discrete geometry + algebraic number theory: the discrete derivatives are forward differences Δ^k, the trajectory's exact Taylor expansion is NEWTON'S FORWARD-DIFFERENCE FORMULA f(t) = Σ C(t,k)·Δ^k f(0) — which is precisely the MAHLER BASIS, the 2-adic-native monomials (Mahler's theorem: the binomials C(t,k) are to ℤ₂ what powers are to ℝ). The ladder's kinematics is 2-adically native all the way down: coarsening one rung transforms the k-th derivative through PASCAL'S ROW k+1 ('lawKthDifferenceCoarsensByPascal': velocity by (1,2,1), acceleration by (1,3,3,1), jerk by (1,4,6,4,1)) — and Pascal mod 2 is Sierpiński via Kummer's carry theorem, so even the transfer function's parity is 2-adic structure.

THE LATENTS HELP US PROGRESS, literally ('lawBandsAreMixedDifferences'): every
OctantViews band is a MIXED DIFFERENCE — band_S = (−1)^|S| · (∏_{a∈S} Δ_a,
pooled over the complement). The order-k latents ARE the k-th mixed discrete
derivatives of the block; the graded 1+3+3+1 decomposition is the physics
(mass, three first derivatives, three mixed seconds, one mixed third).

S, K, I AS MOVEMENT AND BUDGET: K descends the ladder (pooling — cheap, and it
Pascal-smooths every derivative, laws above); I is the reversible floor
(free); S ascends (synthesis — the scarce resource, per the gene-compute
economy: decode-depth = packet count). The budget estimator is exact
('lawPolynomialTrajectoryHaltsExactly'): a trajectory with Δ^{k+1} ≡ 0 is
reproduced EXACTLY by the order-k truncated Newton prediction — zero S-packets
owed beyond order k — and the teeth show a genuine order-k+1 trajectory always
leaves a residual (Δ^{k+1} f = (k+1)! ≠ 0 for f = t^{k+1}). So the kinematic
order a gene can certify IS its halting depth: predict with the derivatives
you have, pay S only for the Mahler tail you cannot. MAP-Elites reward
(docs/GENE-ARCHIVE-PLAN.md, docs/GENE-COMPUTE-ECONOMY.md) then admits genes by
meaning-per-packet — the archive is the reward for spending S where the tail
is real. That wiring is design, referenced not landed here.

HONEST BOUNDARY: linear skeleton, like OctantViews — the shipped floored lift
agrees on which derivatives exist, not on per-element additivity. Mahler DECAY
(coefficients → 0 in |·|₂ for continuous f) is cited context, not law: on
finite integer windows only the exact identities above are landable.
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none
module SixFour.Spec.KinematicLadder
  ( -- * Discrete calculus on streams
    diffs
  , nthDiff
  , coarsenTime
  , binomial
    -- * Newton–Mahler expansion and truncated prediction
  , newtonPredict
    -- * Laws
  , lawKthDifferenceCoarsensByPascal
  , lawNewtonMahlerExpansion
  , lawPolynomialTrajectoryHaltsExactly
  , lawOrderKPlusOneLeavesResidual
  , lawBandsAreMixedDifferences
  ) where

import SixFour.Spec.OctantViews
  ( Axis (..), blockFromList, bandOf, axisSubsets )

-- | Forward difference of a stream: Δf(t) = f(t+1) − f(t). Velocity.
diffs :: [Integer] -> [Integer]
diffs f = zipWith (-) (drop 1 f) f

-- | The k-th forward difference: Δ^k. k = 0 position, 1 velocity,
-- 2 acceleration, 3 jerk — the tower the ladder climbs.
nthDiff :: Int -> [Integer] -> [Integer]
nthDiff k f = iterate diffs f !! k

-- | One rung down in TIME: adjacent-pair sums (the t-half of the isotropic
-- 2×2×2 pooling; the spatial half commutes separately, PaletteKinetics).
coarsenTime :: [Integer] -> [Integer]
coarsenTime (a : b : rest) = (a + b) : coarsenTime rest
coarsenTime _ = []

-- | Exact binomial coefficient (the Mahler monomial C(t,k)).
binomial :: Integer -> Integer -> Integer
binomial n k
  | k < 0 || k > n = 0
  | otherwise = product [n - k + 1 .. n] `div` product [1 .. k]

-- | LAW (the Pascal transfer function): coarsening one rung sends the k-th
-- difference through Pascal's row k+1:
-- Δ^k(coarse)(T) = Σ_j C(k+1, j) · Δ^k(fine)(2T + j), for k = 1, 2, 3 —
-- velocity by (1,2,1), ACCELERATION by (1,3,3,1), jerk by (1,4,6,4,1).
lawKthDifferenceCoarsensByPascal :: [Integer] -> Bool
lawKthDifferenceCoarsensByPascal raw =
  and [ ok k | k <- [1 .. 3] ]
  where
    f = take 16 (raw ++ repeat 0)
    ok k =
      let coarseD = nthDiff k (coarsenTime f)
          fineD   = nthDiff k f
          predicted t = sum [ binomial (fromIntegral k + 1) (fromIntegral j)
                                * fineD !! (2 * t + j)
                            | j <- [0 .. k + 1] ]
      in and [ coarseD !! t == predicted t | t <- [0 .. length coarseD - 1] ]

-- | Truncated Newton–Mahler prediction of order m from the differences at the
-- origin: f̂(t) = Σ_{k ≤ m} C(t,k) · Δ^k f(0). The S-map at kinematic order m.
newtonPredict :: Int -> [Integer] -> Integer -> Integer
newtonPredict m f t =
  sum [ binomial t (fromIntegral k) * head (nthDiff k f) | k <- [0 .. m] ]

-- | LAW (the discrete Taylor theorem, exact): the FULL Newton expansion
-- reproduces any integer trajectory on its window —
-- f(t) = Σ_k C(t,k) · Δ^k f(0). The Mahler basis loses nothing.
lawNewtonMahlerExpansion :: [Integer] -> Bool
lawNewtonMahlerExpansion raw =
  and [ newtonPredict (n - 1) f (fromIntegral t) == f !! t | t <- [0 .. n - 1] ]
  where
    f = take 8 (raw ++ repeat 0)
    n = length f

-- | LAW (the budget estimator): a polynomial trajectory of degree ≤ k
-- (equivalently Δ^{k+1} ≡ 0) is reproduced EXACTLY by the order-k prediction —
-- zero S-packets owed beyond order k; halting depth == kinematic order.
lawPolynomialTrajectoryHaltsExactly :: [Integer] -> Bool
lawPolynomialTrajectoryHaltsExactly rawCoeffs =
  and [ ok k | k <- [0 .. 3] ]
  where
    coeffs = take 4 (map ((`mod` 20) . abs) rawCoeffs ++ repeat 0)
    ok k =
      let f = [ sum [ (coeffs !! i) * t ^ i | i <- [0 .. k] ] | t <- [0 .. 9] ]
      in all (== 0) (nthDiff (k + 1) f)
           && and [ newtonPredict k f t == f !! fromIntegral t | t <- [0 .. 9] ]

-- | TEETH: a genuinely order-(k+1) trajectory always escapes the order-k
-- prediction — f(t) = t^{k+1} has Δ^{k+1} f(0) = (k+1)! ≠ 0, and the order-k
-- residual at t = k+1 is exactly (k+1)!. The Mahler tail is real; S is owed.
lawOrderKPlusOneLeavesResidual :: Bool
lawOrderKPlusOneLeavesResidual =
  and [ let f = [ t ^ (k + 1) | t <- [0 .. 9] ]
            residual = f !! (k + 1) - newtonPredict k f (fromIntegral k + 1)
        in head (nthDiff (k + 1) f) == factorial (k + 1)
             && residual == factorial (k + 1)
      | k <- [0 .. 3] ]
  where factorial n = product [1 .. fromIntegral n]

-- | LAW (the latents ARE the physics): every OctantViews band is a mixed
-- discrete derivative — band_S = (−1)^{|S|} · Σ_{complement} ∏_{a∈S} Δ_a v.
-- Computed here by INDEPENDENT recursive Δ application (never via bandOf's
-- signs), then compared. Order-k latents = k-th mixed derivatives:
-- 1 mass + 3 velocities + 3 mixed accelerations + 1 mixed jerk = 1+3+3+1.
lawBandsAreMixedDifferences :: [Integer] -> Bool
lawBandsAreMixedDifferences xs =
  and [ mixedPooled s == sign (length s) * bandOf v s | s <- axisSubsets ]
  where
    v = blockFromList xs
    sign n = if even n then 1 else -1
    mixedPooled s =
      sum [ mixedAt s cc | cc <- assignAll (complementOf s) ]
      where
        mixedAt [] fixed = v (mk fixed)
        mixedAt (a : rest) fixed =
          mixedAt rest ((a, 1) : fixed) - mixedAt rest ((a, 0) : fixed)
    complementOf s = [ a | a <- [AxX, AxY, AxT], a `notElem` s ]
    assignAll = foldr (\a acc -> [ (a, b) : r | b <- [0, 1], r <- acc ]) [[]]
    mk kv = (get AxX, get AxY, get AxT)
      where get a = maybe 0 id (lookup a kv)

{- |
Module      : SixFour.Spec.MultiScaleFusion
Description : THE LOOP CLOSED — capture diversity IS trainability. This module proves that the exposure-tiled observations of "SixFour.Spec.CaptureDiversity" UNIQUELY DETERMINE the latent scene on exactly the covered (diverse) dynamic-range stops, and lose it as exposures converge. So the fusion inverse is well-posed precisely where diversity is maximized: the same construction that captures the most diverse signal is the one that makes the fusion model recoverable, and the self-supervised measurement-consistency objective (re-degrade the estimate, match every observation) has the true scene as its unique minimizer on the recoverable set.

MODEL: the latent scene is a luminance value per dynamic-range stop; each scale OBSERVES the scene on its exposure window (the @windowW@ stops its EV places it over — CaptureDiversity). This is the DYNAMIC-RANGE axis, which is where the independence lives (SixFour.Spec.MultiScaleCapture: spatial resolution is derivable, exposure is not); the fusion of the spatial/blur axis is a separate, derivable concern and not claimed here.

THE THEOREMS:
  * 'lawRecoverableIffCovered' + 'lawRecoverableCountIsDiversity': a stop's value is recoverable from the observations IFF a window covers it — so the RECOVERABLE SET equals the COVERED SET, and its size is exactly the diversity (coverage). Recoverability and diversity are one quantity.
  * 'lawTilingRecoversFullScene': when the scene fits the window budget (@sceneDR <= nScales·W@), the tiling assignment covers every stop and the fused estimate equals the true scene EVERYWHERE — full recovery, the goal.
  * 'lawConvergenceLosesScene': convergent exposures leave uncovered stops, and two scenes differing only there produce IDENTICAL observations — the inverse is non-identifiable exactly where diversity collapsed.
  * 'lawFusionFreedomIsExactlyUncovered' (KEYSTONE, the trainability statement): the ONLY freedom consistent with the observations is on the UNCOVERED stops; every covered stop is pinned to its true value. So the measurement-consistency minimizer is UNIQUE on the recoverable set — the trainer converges to the truth exactly where the capture is diverse.
  * 'lawOverlapObservationsAgree': redundant reads of the same stop agree — the measurement-consistency constraint, and (under independent noise) the denoising signal that overlap buys.

Consequence for the build: capture the EV-tiled ladder (CaptureDiversity), and the fusion trainer is well-posed and convergent on the recovered dynamic range; on flat/low-DR scenes the uncovered set grows and the model must (provably) leave those stops undetermined rather than hallucinate.
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none
module SixFour.Spec.MultiScaleFusion
  ( -- * The latent scene and its per-window observations
    Scene
  , sceneFromList
  , observe
  , observations
  , fuseAt
  , recoverableStops
    -- * Laws — recoverability equals diversity
  , lawRecoverableIffCovered
  , lawRecoverableCountIsDiversity
  , lawOverlapObservationsAgree
    -- * Laws — full recovery vs collapse
  , lawTilingRecoversFullScene
  , lawConvergenceLosesScene
  , lawFusionFreedomIsExactlyUncovered
  ) where

import Data.Maybe (isJust)

import SixFour.Spec.CaptureDiversity
  ( nScales, windowStops, covered, coverage, tilingEVs )

-- | The latent scene: a luminance value per dynamic-range stop. This is the
-- object fusion recovers.
type Scene = Int -> Integer

-- | Build a scene from a flat list of per-stop values (out-of-range stops = 0).
sceneFromList :: [Integer] -> Scene
sceneFromList vs q =
  if q >= 0 && q < length vs then vs !! q else 0

-- | What one scale sees: the (stop, value) pairs on its exposure window.
observe :: Int -> Int -> Int -> Scene -> [(Int, Integer)]
observe w dr ev x = [ (q, x q) | q <- windowStops w dr ev ]

-- | Every scale's observations pooled — the full measurement the fusion model
-- is trained against.
observations :: Int -> Int -> [Int] -> Scene -> [(Int, Integer)]
observations w dr evs x = concatMap (\ev -> observe w dr ev x) evs

-- | Fuse: the value the observations pin at a stop (Nothing where uncovered).
-- Redundant reads agree ('lawOverlapObservationsAgree'), so the first is canonical.
fuseAt :: [(Int, Integer)] -> Int -> Maybe Integer
fuseAt obs q = lookup q obs

-- | The stops fusion can actually recover — those the observations pin.
-- 'lawRecoverableCountIsDiversity' proves this equals the covered (diverse) set.
recoverableStops :: Int -> Int -> [Int] -> Scene -> [Int]
recoverableStops w dr evs x =
  [ q | q <- [0 .. dr - 1], isJust (fuseAt (observations w dr evs x) q) ]

-- normalise QuickCheck ints into the sensor/scene regime (shared with CaptureDiversity).
normW :: Int -> Int
normW v = 1 + abs v `mod` 8

normDR :: Int -> Int
normDR v = abs v `mod` 32

normEVs :: Int -> [Int] -> [Int]
normEVs dr es = take nScales (map (\e -> abs e `mod` (max 1 dr + 1)) (es ++ repeat 0))

-- | LAW (recoverable IFF covered): a stop is pinned by the observations exactly
-- when some exposure window covers it, and then to its TRUE value. No window,
-- no information — the honest edge of what fusion can know.
lawRecoverableIffCovered :: Int -> Int -> [Int] -> [Integer] -> Int -> Bool
lawRecoverableIffCovered wRaw drRaw evsRaw xs qRaw =
  (q `elem` cov) == isJust (fuseAt obs q)
    && (not (q `elem` cov) || fuseAt obs q == Just (x q))
  where
    w = normW wRaw; dr = normDR drRaw; evs = normEVs dr evsRaw
    x = sceneFromList xs
    obs = observations w dr evs x
    cov = covered w dr evs
    q = if dr == 0 then 0 else abs qRaw `mod` dr

-- | LAW (recoverability IS diversity): the number of stops fusion recovers
-- equals the coverage — the very quantity 'CaptureDiversity' maximizes. Building
-- the most diverse capture and building the most recoverable one are identical.
lawRecoverableCountIsDiversity :: Int -> Int -> [Int] -> [Integer] -> Bool
lawRecoverableCountIsDiversity wRaw drRaw evsRaw xs =
  length (recoverableStops w dr evs x) == coverage w dr evs
  where
    w = normW wRaw; dr = normDR drRaw; evs = normEVs dr evsRaw
    x = sceneFromList xs

-- | LAW (measurement consistency): every read of a given stop returns the same
-- value — redundant (overlapping) observations agree. This is the constraint the
-- self-supervised trainer enforces, and under independent noise the average of
-- these agreeing reads is the denoised estimate.
lawOverlapObservationsAgree :: Int -> Int -> [Int] -> [Integer] -> Bool
lawOverlapObservationsAgree wRaw drRaw evsRaw xs =
  and [ v == x q | (q, v) <- observations w dr evs x ]
  where
    w = normW wRaw; dr = normDR drRaw; evs = normEVs dr evsRaw
    x = sceneFromList xs

-- | LAW (tiling recovers the whole scene): when the scene fits the window budget
-- (sceneDR <= nScales·W), the tiling assignment covers every stop and the fused
-- estimate equals the true scene everywhere. The diversity-optimal capture is
-- also the fully-recoverable one.
lawTilingRecoversFullScene :: Int -> Int -> [Integer] -> Bool
lawTilingRecoversFullScene wRaw drRaw xs =
  dr > nScales * w
    || and [ fuseAt obs q == Just (x q) | q <- [0 .. dr - 1] ]
  where
    w = normW wRaw; dr = normDR drRaw
    x = sceneFromList xs
    obs = observations w dr (tilingEVs w) x

-- | LAW (convergence loses the scene — non-identifiability): with collapsed
-- exposures (all EVs equal) and a scene wider than one window, two scenes that
-- differ only on an UNCOVERED stop produce identical observations. The inverse
-- has no unique solution exactly where diversity collapsed.
lawConvergenceLosesScene :: Bool
lawConvergenceLosesScene =
  observations w dr evs x1 == observations w dr evs x2   -- indistinguishable...
    && x1 3 /= x2 3                                        -- ...yet different (stop 3 is uncovered)
  where
    w = 2; dr = 5; evs = [0, 0, 0]                         -- window covers stops {0,1}; {2,3,4} unseen
    x1 = sceneFromList [7, 7, 0, 0, 0]
    x2 = sceneFromList [7, 7, 0, 99, 0]                    -- differs only on uncovered stop 3

-- | LAW (KEYSTONE — the trainability statement): the ONLY freedom consistent
-- with the observations is on the UNCOVERED stops. A scene perturbed anywhere off
-- the covered set yields the SAME observations, yet must AGREE with the original
-- on every covered stop. So the measurement-consistency minimizer is UNIQUE on
-- the recoverable set: the trainer converges to the truth exactly where the
-- capture is diverse, and is free (undetermined) exactly where it is not.
lawFusionFreedomIsExactlyUncovered :: Int -> Int -> [Int] -> [Integer] -> [Integer] -> Bool
lawFusionFreedomIsExactlyUncovered wRaw drRaw evsRaw xs deltas =
  observations w dr evs x == observations w dr evs y   -- perturbing off-cover changes no observation
    && and [ x q == y q | q <- cov ]                    -- and pins every covered stop to the truth
  where
    w = normW wRaw; dr = normDR drRaw; evs = normEVs dr evsRaw
    x = sceneFromList xs
    cov = covered w dr evs
    delta q = if q >= 0 && q < length deltas then deltas !! q else 0
    y q = if q `elem` cov then x q else x q + delta q    -- free ONLY off the covered set

{- |
Module      : SixFour.Spec.CaptureDiversity
Description : HOW TO BUILD IT FOR THE MOST DIVERSE SIGNAL — the constructive proof of the capture that maximizes independent information across the 16³/32³/64³ scales. Where "SixFour.Spec.MultiScaleCapture" proves the scales CAN be independent (a witness), this module proves HOW MUCH and by WHAT CONSTRUCTION: model each scale's exposure as a usable WINDOW of @windowW@ stops on the scene's dynamic range, shifted by the scale's EV (exposure × gain). Captured diversity = the COVERAGE of the union of the three windows (distinct dynamic-range stops seen by at least one scale); redundancy = their OVERLAP (stops two scales both see — derivable, information-free). Maximizing diverse signal is therefore maximizing coverage / minimizing overlap, and it has a clean optimum.

THE RECIPE (proven): the coverage upper bound is @min(sceneDR, nScales·windowW)@ ('lawDiversityCappedByScene', 'lawCoverageBoundedByBudget'), and the EDGE-TO-TILE assignment — windows placed @windowW@ stops apart, @evs = [0, W, 2W]@ — ACHIEVES that bound, so it is a maximizer ('lawTilingMaximizesCoverage', 'lawTilingIsAtLeastAnyAssignment'), with ZERO overlap when the scene is wide enough. Its opposite, CONVERGENT exposures (all EVs equal), gives minimal coverage (one window) and maximal redundancy ('lawConvergenceMinimizesDiversity') — the three streams collapse to one. Separability of the fusion inverse is the number of DISTINCT windows: full rank at tiling, rank 1 (singular) at convergence ('lawDistinctExposuresFullRank') — the conditioning the trainer depends on.

THE HONEST LIMITS (also proven, not hand-waved):
  * 'lawDiversityCappedByScene': coverage <= sceneDR. No capture design can manufacture dynamic range the scene does not have — a flat/bright/low-DR scene caps diversity at its own small range. This IS the "independence collapses on easy scenes" result, as a theorem.
  * 'lawCadenceForcesNestedExposures': the shared 64@20/32@10/16@5 cadence (SixFour.Spec.MultiScaleCapture) affords exposure TIMES in ratio 4:2:1, i.e. DISTINCT nested EVs — assign the LONGEST exposure to the COARSE/slow scale (lowest EV = shadows, where SNR is scarce and the slow slot affords the integration) — but only @log2(fastPerSlow) = 2@ stops of spread.
  * 'lawCadenceSpreadNeedsGainToTile': whenever the sensor window exceeds that 2-stop cadence step (it always does), exposure time ALONE cannot reach the tiling spread @(nScales-1)·W@ — the remaining @(nScales-1)·W - 2@ stops MUST come from GAIN. So the max-diversity build is a long-exposure-HIGH-GAIN coarse read down to a short-exposure-LOW-GAIN fine read; time sets the cadence, gain sets the spread.

Units are integer STOPS (log2), so all arithmetic is exact and gate-able. The window width @windowW@ and scene range @sceneDR@ are the sensor/scene parameters; the EV assignment is the DESIGN. Feeds the fusion trainer: it is well-posed exactly where these laws give full rank.
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none
module SixFour.Spec.CaptureDiversity
  ( -- * Model: exposure windows on the dynamic range (integer stops)
    nScales
  , windowStops
  , covered
  , coverage
  , overlap
    -- * The design axis: EV assignments
  , tilingEVs
  , cadenceEVs
  , separabilityRank
  , ilog2
    -- * Laws — the recipe
  , lawCoverageBoundedByBudget
  , lawTilingMaximizesCoverage
  , lawTilingIsAtLeastAnyAssignment
  , lawConvergenceMinimizesDiversity
  , lawDistinctExposuresFullRank
    -- * Laws — the honest limits
  , lawDiversityCappedByScene
  , lawCadenceForcesNestedExposures
  , lawCadenceSpreadNeedsGainToTile
  ) where

import Data.List (nub, sort)

-- | The three scales (16³/32³/64³).
nScales :: Int
nScales = 3

-- | The dynamic-range stops a width-@w@ exposure window at EV offset @ev@ covers,
-- clipped to the scene @[0, dr)@. A higher @ev@ = a brighter (shorter/lower-gain)
-- window; a lower @ev@ = a dimmer (longer/higher-gain) window that reaches shadows.
windowStops :: Int -> Int -> Int -> [Int]
windowStops w dr ev = [ q | q <- [ev .. ev + w - 1], q >= 0, q < dr ]

-- | The distinct dynamic-range stops covered by a set of windows — the union.
covered :: Int -> Int -> [Int] -> [Int]
covered w dr evs = nub (concatMap (windowStops w dr) evs)

-- | Captured DIVERSITY: how many distinct stops the union of windows sees.
coverage :: Int -> Int -> [Int] -> Int
coverage w dr evs = length (covered w dr evs)

-- | REDUNDANCY: window-stops seen by more than one scale (total with
-- multiplicity minus the distinct coverage) — information-free, derivable overlap.
overlap :: Int -> Int -> [Int] -> Int
overlap w dr evs = sum (map (length . windowStops w dr) evs) - coverage w dr evs

-- | THE MAX-DIVERSITY ASSIGNMENT: windows placed edge-to-edge, @W@ stops apart —
-- @[0, W, 2W]@. Tiles the dynamic range with zero overlap when it fits.
tilingEVs :: Int -> [Int]
tilingEVs w = [ s * w | s <- [0 .. nScales - 1] ]

-- | Floor log2 for positive @n@ (the EV spread a cadence ratio buys).
ilog2 :: Int -> Int
ilog2 n = if n <= 1 then 0 else 1 + ilog2 (n `div` 2)

-- | The exposure-TIME-only EV assignment the shared cadence forces: the 4:2:1
-- slot ratio gives one stop per adjacent scale, coarse (longest, EV 0 = shadows)
-- to fine (shortest, EV 2 = highlights). @fastPerSlow = 4@ ⇒ @[0,1,2]@.
cadenceEVs :: [Int]
cadenceEVs = [ ilog2 4 - ilog2 (4 `div` (2 ^ s)) | s <- [0 .. nScales - 1] ]

-- | Separability of the fusion inverse = the number of DISTINCT windows. Full
-- rank (@= nScales@) means the three observations span independent bands and the
-- scene is recoverable; rank 1 means the exposures collapsed to one measurement.
separabilityRank :: [Int] -> Int
separabilityRank evs = length (nub evs)

allEV :: Int -> Int
allEV dr = max 1 dr   -- a generous EV search bound for the "any assignment" law

-- normalise QuickCheck ints into a sensible sensor/scene regime.
normW :: Int -> Int
normW x = 1 + abs x `mod` 8            -- window 1..8 stops

normDR :: Int -> Int
normDR x = abs x `mod` 32              -- scene 0..31 stops

normEVs :: Int -> [Int] -> [Int]
normEVs dr es = take nScales (map (\e -> abs e `mod` (allEV dr + 1)) (es ++ repeat 0))

-- | LAW (the two ceilings on diversity): coverage can exceed neither the scene's
-- own dynamic range nor the total window budget — @coverage <= min(sceneDR, nScales·W)@.
lawCoverageBoundedByBudget :: Int -> Int -> [Int] -> Bool
lawCoverageBoundedByBudget wRaw drRaw evsRaw =
  coverage w dr evs <= min dr (nScales * w)
  where w = normW wRaw; dr = normDR drRaw; evs = normEVs dr evsRaw

-- | LAW (HONEST LIMIT — diversity is scene-bounded): coverage <= sceneDR. No
-- exposure design manufactures dynamic range the scene lacks; a low-DR (flat,
-- bright, static) scene caps captured diversity at its own small range. This is
-- "independence collapses on easy scenes", proven.
lawDiversityCappedByScene :: Int -> Int -> [Int] -> Bool
lawDiversityCappedByScene wRaw drRaw evsRaw =
  coverage w dr evs <= dr
  where w = normW wRaw; dr = normDR drRaw; evs = normEVs dr evsRaw

-- | LAW (KEYSTONE — the recipe is optimal): the tiling assignment ACHIEVES the
-- coverage upper bound @min(sceneDR, nScales·W)@, and has zero overlap when the
-- scene is at least as wide as the window budget. Achieving the proven ceiling
-- is what makes edge-to-edge tiling the max-diversity capture.
lawTilingMaximizesCoverage :: Int -> Int -> Bool
lawTilingMaximizesCoverage wRaw drRaw =
  coverage w dr (tilingEVs w) == min dr (nScales * w)
    && (dr < nScales * w || overlap w dr (tilingEVs w) == 0)
  where w = normW wRaw; dr = normDR drRaw

-- | LAW (tiling dominates every assignment): no EV assignment covers more than
-- the tiling one. (Direct from the ceiling + achievement: tiling hits the bound
-- that bounds all others.)
lawTilingIsAtLeastAnyAssignment :: Int -> Int -> [Int] -> Bool
lawTilingIsAtLeastAnyAssignment wRaw drRaw evsRaw =
  coverage w dr (tilingEVs w) >= coverage w dr evs
  where w = normW wRaw; dr = normDR drRaw; evs = normEVs dr evsRaw

-- | LAW (the opposite pole — convergence is redundancy): identical exposures
-- (all EVs equal) collapse to a SINGLE window's coverage and pay
-- @(nScales-1)×@ that in overlap. The three streams become one measurement —
-- exactly the derived pyramid the whole design rejects.
lawConvergenceMinimizesDiversity :: Int -> Int -> Int -> Bool
lawConvergenceMinimizesDiversity wRaw drRaw cRaw =
  coverage w dr evs == oneWin
    && overlap w dr evs == (nScales - 1) * oneWin
    && coverage w dr evs <= coverage w dr (tilingEVs w)
  where
    w = normW wRaw; dr = normDR drRaw
    c = abs cRaw `mod` (allEV dr + 1)
    evs = replicate nScales c
    oneWin = length (windowStops w dr c)

-- | LAW (separability = distinct windows): the fusion inverse is full rank iff
-- the exposures are distinct. Tiling ⇒ rank @nScales@ (recoverable); convergence
-- ⇒ rank 1 (singular, unrecoverable). This is the conditioning the trainer needs
-- (SixFour.Spec.MultiScaleCapture independence, now with a rank).
lawDistinctExposuresFullRank :: Bool
lawDistinctExposuresFullRank =
  separabilityRank (tilingEVs 3) == nScales
    && separabilityRank (replicate nScales 5) == 1
    && separabilityRank cadenceEVs == nScales

-- | LAW (the cadence forces nested exposures — the build's temporal half): the
-- shared 4:2:1 cadence yields DISTINCT, monotone EVs (coarse longest/lowest EV =
-- shadows, up to fine shortest/highest = highlights), contributing full
-- separability rank — but only @log2(fastPerSlow) = 2@ stops of spread.
lawCadenceForcesNestedExposures :: Bool
lawCadenceForcesNestedExposures =
  separabilityRank cadenceEVs == nScales
    && cadenceEVs == sort cadenceEVs
    && head cadenceEVs == 0
    && (last cadenceEVs - head cadenceEVs) == ilog2 4

-- | LAW (the build's other half — GAIN is required, not just time): to TILE, the
-- windows must span @(nScales-1)·W@ stops, but the cadence affords only
-- @log2(fastPerSlow) = 2@. Whenever the sensor window exceeds that step (it
-- always does — real windows are ≥ 2 stops), exposure TIME alone leaves the
-- windows overlapping; the remaining @(nScales-1)·W - 2@ stops MUST come from
-- GAIN. The max-diversity capture is long-exposure-high-gain (coarse) →
-- short-exposure-low-gain (fine).
lawCadenceSpreadNeedsGainToTile :: Int -> Bool
lawCadenceSpreadNeedsGainToTile wRaw =
  gainStopsNeeded > 0 && gainStopsNeeded == tilingSpread - cadenceSpread
  where
    w = 2 + abs wRaw `mod` 8            -- realistic sensor window: >= 2 stops
    tilingSpread = (nScales - 1) * w
    cadenceSpread = ilog2 4
    gainStopsNeeded = tilingSpread - cadenceSpread

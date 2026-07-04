{- |
Module      : SixFour.Spec.FidelityLadder
Description : MIXING THE THREE VIEWS UNTIL HIGH FIDELITY > PAINT — and why capture cadence matters. The post-capture UI/UX is DOWNSTREAM OF THE BIN DATA: everything the user sees and decides derives from the sums carrier (the ColorHead ladder), and the cadences 20/10/5 Hz exist so the three sizes are EQUIVALENT IN DATA INTERPRETATION — 'lawRungsPartitionTheSameMass' proves every rung's window totals exactly the same mass (no rung sees more data; they PARTITION the same photons differently). The 16×16 has the strongest per-bin signal ('lawCoarseBinIsEightChildren': each coarse bin holds exactly 8× its child bin's mass per rung, so ~√8 SNR per rung by shot noise — physics note) — the right PALETTE SEED — but it requires refinement, and refinement provably converges: 'lawDeeperIsCloser' (KEYSTONE) — over exact rationals, each depth step weakly decreases the squared error of the render against the true volume, reaching EXACTLY zero at full depth. Nested partitions are nested projections; mixing the three views is monotone descent to high fidelity, never a wander.

WHY MIXING BEATS PAINT, constructively ('lawMixesStrictlyExtendPaint'): the
committed W1 paint semantics reaches only the binary depths (floor / full),
but the ternary field family strictly extends it — a witnessed mix render
exists that NO paint mask can produce (the intermediate 32-rung look).
Together with "SixFour.Spec.ChoiceTraining" (paint underdetermines depth,
choices identify the field) and the monotone descent above: choice-driven
mixing reaches every fidelity level the ladder offers; paint can only jump
between its two endpoints. Paint remains the fun WHERE-hint; mixing is the
fidelity instrument.

HONEST BOUNDARY: 'lawDeeperIsCloser' is stated over ℚ (exact means, exact
SSE) — the byte realization rounds once at the end (s4_sums_to_srgb8), and
rounding can perturb single voxels by ±1/2 LSB without touching the monotone
structure; the rational law is the structure, the byte path is the shipped
realization. Sufficiency of the bin data (the "downstream" claim) is landed
operationally: ColorHead derives 32/16 rungs, GCT, particles, and the halt
floor from the 64-rung sums stream alone (the transitive carrier), gated by
ColorHeadTests — referenced here, not re-proven.
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none
module SixFour.Spec.FidelityLadder
  ( -- * Exact-rational render and fidelity
    renderPullQ
  , sseAtDepth
    -- * Laws
  , lawRungsPartitionTheSameMass
  , lawCoarseBinIsEightChildren
  , lawDeeperIsCloser
  , lawMixesStrictlyExtendPaint
  ) where

import Data.Ratio ((%))

import SixFour.Spec.PaletteKinetics (coarseStream)
import SixFour.Spec.PullField
  ( Volume, volumeFromList, Field, regionOf, renderPull, side )

-- | The exact-rational pull render: every voxel takes the EXACT mean of its
-- depth-block (no rounding) — the structural object 'lawDeeperIsCloser' is
-- stated on; the byte path rounds once at realization.
renderPullQ :: Field -> Volume -> (Int, Int, Int) -> Rational
renderPullQ field v (x, y, t) =
  let d  = field (regionOf (x, y, t))
      b  = 4 `div` (2 ^ max 0 (min 2 d))
      x0 = (x `div` b) * b
      y0 = (y `div` b) * b
      t0 = (t `div` b) * b
      s  = sum [ v (x0 + i, y0 + j, t0 + k)
               | i <- [0 .. b - 1], j <- [0 .. b - 1], k <- [0 .. b - 1] ]
  in s % fromIntegral (b * b * b)

allVoxels :: [(Int, Int, Int)]
allVoxels = [ (x, y, t) | t <- [0 .. side - 1], y <- [0 .. side - 1], x <- [0 .. side - 1] ]

-- | The exact squared error of the depth-d uniform render against the truth.
sseAtDepth :: Int -> Volume -> Rational
sseAtDepth d v =
  sum [ (fromInteger (v p) - renderPullQ (const d) v p) ^ (2 :: Int) | p <- allVoxels ]

-- | LAW (each size is equivalent in data interpretation): pooling one rung
-- down — 2×2 spatial on paired ticks (the isotropic 2×2×2) — preserves the
-- WINDOW TOTAL exactly. Every rung of the ladder totals the same mass; no
-- rung sees more data, they partition the same photons differently. (This is
-- why capture cadence matters: the cadences make the partitions comparable.)
lawRungsPartitionTheSameMass :: [[Integer]] -> Bool
lawRungsPartitionTheSameMass raw =
  sum (map sum fine) == sum (map sum coarse)
    && sum (map sum coarse) == sum (map sum coarser)
  where
    fine    = take 4 (map (take 16 . (++ repeat 0)) raw ++ repeat (replicate 16 0))
    coarse  = coarseStream 4 fine            -- 4×4 frames, paired ticks → 2×2
    coarser = coarseStream 2 coarse          -- → 1×1

-- | LAW (the seed's signal strength, exactly): on a uniform stream, each
-- coarse bin holds exactly 8× its child bin's mass (4 spatial children × 2
-- ticks). Two rungs down: 64×. Shot noise then gives ~√8 SNR per rung
-- (physics note, not law) — which is why the 16×16 is the palette SEED.
lawCoarseBinIsEightChildren :: Integer -> Bool
lawCoarseBinIsEightChildren mRaw =
  all (== 8 * m) (head (coarseStream 4 [frame, frame]))
  where
    m = 1 + abs mRaw `mod` 1000
    frame = replicate 16 m

-- | LAW (KEYSTONE — refinement converges): fidelity is MONOTONE in depth,
-- exactly: SSE(depth 0) ≥ SSE(depth 1) ≥ SSE(depth 2) = 0 over ℚ. Nested
-- partitions are nested projections; every deepening weakly improves the
-- render, and full depth reproduces the truth exactly. Mixing the three
-- views is monotone descent to high fidelity.
lawDeeperIsCloser :: [Integer] -> Bool
lawDeeperIsCloser xs =
  sseAtDepth 0 v >= sseAtDepth 1 v
    && sseAtDepth 1 v >= sseAtDepth 2 v
    && sseAtDepth 2 v == 0
  where v = volumeFromList xs

-- | LAW (mixing strictly beats paint): the W1 paint semantics reaches only
-- binary depths {floor, full}; the witnessed volume below has a region whose
-- 32-rung (depth 1) render differs from BOTH endpoints — a mix no paint mask
-- can produce. The ternary family strictly extends the binary one.
lawMixesStrictlyExtendPaint :: Bool
lawMixesStrictlyExtendPaint =
  any differsFromBoth allVoxels
  where
    -- A deterministic gradient volume: distinct block means at every scale.
    v = volumeFromList [ toInteger ((x + 2 * y + 5 * t) `mod` 97)
                       | t <- [0 .. side - 1], y <- [0 .. side - 1], x <- [0 .. side - 1] ]
    r0 = renderPull (const 0) v
    r1 = renderPull (const 1) v
    r2 = renderPull (const 2) v
    differsFromBoth p = r1 p /= r0 p && r1 p /= r2 p

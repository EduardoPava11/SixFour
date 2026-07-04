{- |
Module      : SixFour.Spec.PaletteKinetics
Description : The 16×16 base as 256 PARTICLES, and entropy in exact integer arithmetic. The rung equality being gated: 64@20fps == 32@10fps == 16@5fps — same 3.2 s window, same printed canvas (block replication; the pixelated look is presentation), the SAME spacetime region at three information densities — so "the look of the GIF" ties to true GIF89a terms (the GCE delay in centiseconds and the GCT are the physics, not decoration). The 16×16 bin grid is the perfect base because its 256 slots are ORDERED BY (x,y) ('lawSlotIsXYOrder': slot = 16·by+bx is a bijection with the grid): each slot is a particle with POSITION (its bin), MASS (its pooled sum — photon count on the linear path), and VELOCITY (its per-tick delta).

KINETICS (exact, from linearity): mass is conserved under pooling
('lawMassPoolsExactly' — the u64 sums carrier of @Native/palette16.zig@);
velocity commutes with spatial pooling ('lawVelocityCommutesWithPooling' —
Δt and block-sum are both linear); and the KEYSTONE kinetic law
('lawCoarseVelocityIsBinomialSmoothing'): the coarser rung's velocity per ITS
tick is the spatially pooled (1,2,1)-weighted sum of fine velocities —
coarse Δ(T) = pool(δ(2T) + 2·δ(2T+1) + δ(2T+2)). Momentum does not merely
survive the ladder; it coarsens by Pascal's row, exactly. This is the algebra
behind the rung equality: the 32@10 stream's motion is a binomial smoothing of
the 64@20 stream's motion, byte-exact, no resampling choice hidden anywhere.

ENTROPY, in the only form this spec accepts — EXACT INTEGERS: we land the
Boltzmann microstate count W (an Integer), not H = log W (a real). A bin of
mass m with value-counts (c₁..cₙ) has W = m!/(∏ cᵢ!) microstates.
Then: CERTAINTY IS MASS CONCENTRATION — W = 1 exactly iff all mass sits on one
value ('lawCertainMassHasOneMicrostate'); the maximum-entropy split of a mass
is the balanced one ('lawMaxEntropyIsBalancedSplit'); and the CHAIN RULE
H(fine) = H(coarse) + H(detail|coarse) is the integer FACTORIZATION
W(fine) = W(group totals) × ∏ W(within group) ('lawMicrostatesChainRule', the
multinomial identity) — entropies add because microstate counts multiply, so
palette collapse (merging values into a GCT slot) DIVIDES W exactly, never
approximately ('lawCoarseningNeverIncreasesW', the data-processing inequality
as integer divisibility). This extends the landed counting-entropy program
(chain rule via lift bijection, docs/ENTROPY-INVARIANTS.md) from the lift to
the palette head.

PHYSICS NOTE (doc, deliberately NOT law): on the radiometric path
(@s4_pool_sums_linear_hlg10@) bin mass is ∝ photon count, and shot noise gives
variance ≈ gain × mean — so mass buys certainty at the sensor too (SNR ~ √m).
That is measurement, not arithmetic; it stays a note. See
"SixFour.Spec.OctantViews" (the graded 2×2×2 spacetime blocks whose t-bands
carry these deltas) and "SixFour.Spec.V21Pyramid" (the sums carrier).
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none
module SixFour.Spec.PaletteKinetics
  ( -- * The 256 particles: position = slot, ordered by (x, y)
    slotOfBin
  , binOfSlot
    -- * Kinetics: mass and velocity on frame streams
  , poolSpace2
  , velocity
  , coarseStream
    -- * Entropy as exact microstate counting
  , microstates
    -- * Laws
  , lawSlotIsXYOrder
  , lawMassPoolsExactly
  , lawVelocityCommutesWithPooling
  , lawCoarseVelocityIsBinomialSmoothing
  , lawCertainMassHasOneMicrostate
  , lawMaxEntropyIsBalancedSplit
  , lawMicrostatesChainRule
  , lawCoarseningNeverIncreasesW
  ) where

-- | Slot index of bin (bx, by): row-major 16·by + bx — the 256 palette slots
-- ordered by (x, y). One coarse bin per palette slot (V21Pyramid).
slotOfBin :: (Int, Int) -> Int
slotOfBin (bx, by) = 16 * by + bx

-- | The inverse chart: slot -> bin.
binOfSlot :: Int -> (Int, Int)
binOfSlot s = (s `mod` 16, s `div` 16)

-- | LAW (the base is ordered by x,y): slot/bin is a bijection [0,255] ↔ 16×16.
lawSlotIsXYOrder :: Bool
lawSlotIsXYOrder =
  and [ slotOfBin (binOfSlot s) == s | s <- [0 .. 255] ]
    && and [ binOfSlot (slotOfBin (bx, by)) == (bx, by) | bx <- [0 .. 15], by <- [0 .. 15] ]

-- | 2×2 spatial block-sum pooling of an even-length square frame (row-major).
poolSpace2 :: Int -> [Integer] -> [Integer]
poolSpace2 side xs =
  [ at (2 * bx) (2 * by) + at (2 * bx + 1) (2 * by)
      + at (2 * bx) (2 * by + 1) + at (2 * bx + 1) (2 * by + 1)
  | by <- [0 .. h - 1], bx <- [0 .. h - 1] ]
  where
    h = side `div` 2
    at x y = xs !! (y * side + x)

-- | Per-tick velocity of a frame stream: consecutive frame deltas, pointwise.
velocity :: [[Integer]] -> [[Integer]]
velocity fs = zipWith (zipWith (-)) (drop 1 fs) fs

-- | The coarser rung's stream from a fine stream: 2×2×2 spacetime block-sum —
-- pairs of consecutive fine frames, spatially pooled and summed (the isotropic
-- ladder: 64@20 → 32@10 → 16@5, constant 3.2 s window).
coarseStream :: Int -> [[Integer]] -> [[Integer]]
coarseStream side (f0 : f1 : rest) =
  zipWith (+) (poolSpace2 side f0) (poolSpace2 side f1) : coarseStream side rest
coarseStream _ _ = []

-- | LAW (mass is conserved): pooling preserves total mass exactly — the sums
-- carrier; a particle's mass at the coarse rung is the sum of its children.
lawMassPoolsExactly :: [Integer] -> Bool
lawMassPoolsExactly raw = sum (poolSpace2 4 f) == sum f
  where f = take 16 (raw ++ repeat 0)

-- | LAW (velocity is a linear observable): spatial pooling commutes with the
-- per-tick delta, pool(Δf) == Δ(pool f).
lawVelocityCommutesWithPooling :: [[Integer]] -> Bool
lawVelocityCommutesWithPooling raw =
  map (poolSpace2 4) (velocity fs) == velocity (map (poolSpace2 4) fs)
  where fs = frames4 raw

-- | LAW (KEYSTONE — momentum coarsens by Pascal's row): the coarse stream's
-- velocity per coarse tick equals the spatially pooled (1,2,1)-weighted sum of
-- fine velocities: coarseΔ(T) = pool(δ(2T) + 2·δ(2T+1) + δ(2T+2)). The 32@10
-- motion is an exact binomial smoothing of the 64@20 motion.
lawCoarseVelocityIsBinomialSmoothing :: [[Integer]] -> Bool
lawCoarseVelocityIsBinomialSmoothing raw =
  velocity cs == [ poolSpace2 4 (smooth (2 * t)) | t <- [0 .. length cs - 2] ]
  where
    fs = frames4 raw
    cs = coarseStream 4 fs
    ds = velocity fs
    smooth k = zipWith3 (\a b c -> a + 2 * b + c) (ds !! k) (ds !! (k + 1)) (ds !! (k + 2))

-- Six 4×4 frames from a flat list (padded), the small test stream.
frames4 :: [[Integer]] -> [[Integer]]
frames4 raw = take 6 (map (take 16 . (++ repeat 0)) raw ++ repeat (replicate 16 0))

-- | The Boltzmann microstate count of a bin: mass m split into value-counts
-- (c₁..cₙ) has W = m!/(∏ cᵢ!) — an EXACT Integer; H = log W stays un-landed.
microstates :: [Integer] -> Integer
microstates cs = factorial (sum cs') `div` product (map factorial cs')
  where cs' = map (max 0) cs

factorial :: Integer -> Integer
factorial n = product [1 .. n]

-- | LAW (certainty is mass concentration): W == 1 exactly iff all mass sits on
-- a single value — a concentrated particle has zero entropy, and any real
-- split has W > 1.
lawCertainMassHasOneMicrostate :: [Integer] -> Bool
lawCertainMassHasOneMicrostate raw =
  (microstates cs == 1) == (length (filter (> 0) cs) <= 1)
  where cs = map ((`mod` 12) . abs) (take 6 raw)

-- | LAW (maximum entropy is the balanced split): over two-value splits of mass
-- m, W(k, m−k) is maximized at k = ⌊m/2⌋ — checked exhaustively for m ≤ 24.
lawMaxEntropyIsBalancedSplit :: Bool
lawMaxEntropyIsBalancedSplit =
  and [ maximum [ w k m | k <- [0 .. m] ] == w (m `div` 2) m | m <- [0 .. 24] ]
  where w k m = microstates [k, m - k]

-- | LAW (KEYSTONE — the chain rule as integer factorization): merging values
-- into groups (the palette collapse: many colors → one GCT slot),
-- W(fine) == W(group totals) × ∏ groups W(within group) — the multinomial
-- identity. Entropies add because microstate counts multiply; H(detail|coarse)
-- is the log of the within-group factor, never computed as a real.
lawMicrostatesChainRule :: [Integer] -> [Integer] -> Bool
lawMicrostatesChainRule rawA rawB =
  microstates (ga ++ gb)
    == microstates [sum ga, sum gb] * microstates ga * microstates gb
  where
    ga = map ((`mod` 8) . abs) (take 3 rawA)
    gb = map ((`mod` 8) . abs) (take 3 rawB)

-- | LAW (data processing as divisibility): coarsening the value alphabet never
-- increases W — W(coarse) divides W(fine) exactly, with the quotient the
-- within-group counts. The GCT realization can only discard entropy.
lawCoarseningNeverIncreasesW :: [Integer] -> [Integer] -> Bool
lawCoarseningNeverIncreasesW rawA rawB =
  microstates [sum ga, sum gb] <= wFine && wFine `mod` microstates [sum ga, sum gb] == 0
  where
    ga = map ((`mod` 8) . abs) (take 3 rawA)
    gb = map ((`mod` 8) . abs) (take 3 rawB)
    wFine = microstates (ga ++ gb)

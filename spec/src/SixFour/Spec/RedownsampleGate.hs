{- |
Module      : SixFour.Spec.RedownsampleGate
Description : The RSI verify-by-redownsample gate, scoped to the COARSE/DC band — neither vacuous nor impossible (closes audit gap H2).

The self-improvement loop wants to verify a reconstructed @256³@ by re-downsampling
it and checking it matches the given @16³@. The audit (H2) showed the naive form is
ill-posed: the net INVENTS detail above captured resolution
("SixFour.Spec.CubeLadder" 'synthBeyond' — the one non-invertible step), so a full
bit-exact "decode then re-downsample == input" gate either (a) always passes
trivially (if it only re-tests the zeroed floor) or (b) is impossible (if it demands
the invented high-frequency survive a round-trip it never could).

The fix is to scope the gate to ONLY the band the downsample preserves: the
COARSE/DC band. 'redownsample' pools a fine cube @k@ octree levels via
"SixFour.Spec.OctreeCell" 'octantDistill' and keeps the coarse plane; 'passesGate'
checks that coarse equals the given rung. The three laws make it bite without being
vacuous:

  * 'lawRedownsampleConsistency' — a FAITHFUL reconstruction (the given coarse + its
    real held detail) passes (the positive case; delegates the octant bijection).
  * 'lawGateIgnoresInventedDetail' — two cubes with the SAME coarse but DIFFERENT
    (invented) detail BOTH pass: genuine super-res is never rejected (the gate is in
    the detail's null space). This is what makes it not-impossible.
  * 'lawGateRejectsCoarseDrift' — a cube whose COARSE band drifted is REJECTED: the
    gate has teeth, so confirmation-bias collapse (coarse silently wandering) is
    structurally caught, not threshold-guarded. This is what makes it not-vacuous.

The gate runs on the INTEGER floor (@[Int]@ / Q16, after
"SixFour.Spec.ByteCarrier" 'reenterQ16'); on integers @eps = 0@ and the coarse
equality is exact. The continuous remainder never reaches the gate.

Additive: imports only proven octant ops, re-pins no golden contract, deletes nothing.
-}
-- COMPARTMENT: MLX-MODEL | tag:MacTag | STRADDLER
module SixFour.Spec.RedownsampleGate
  ( gateLevels
  , redownsample
  , passesGate
    -- * Laws (QuickCheck'd in @Properties.RedownsampleGate@)
  , lawRedownsampleConsistency
  , lawGateIgnoresInventedDetail
  , lawGateRejectsCoarseDrift
  ) where

import SixFour.Spec.OctreeCell    (octantDistill, octantSynthesize, levelsBetween, Detail)
import SixFour.Spec.OctreeGenome  (octreeLeafCount)

-- | The product gate distance: @256³ → 16³@ is @levelsBetween 256 16 == 4@ octant
-- levels (delegated; tests exercise smaller @k@).
gateLevels :: Int
gateLevels = levelsBetween 256 16

-- | Pool a fine cube @k@ octree levels and keep the COARSE/DC plane — the only band a
-- downsample preserves. (= @fst . octantDistill k@.)
redownsample :: Int -> [Int] -> [Int]
redownsample k cube = fst (octantDistill k cube)

-- | The gate: a reconstructed fine cube passes iff its coarse band, re-downsampled
-- @k@ levels, equals the @given@ rung. Scoped to the coarse band only — invented
-- high-frequency lives in the discarded detail and cannot move the verdict.
passesGate :: Int -> [Int] -> [Int] -> Bool
passesGate k given cube = redownsample k cube == given

-- ============================================================================
-- Laws (predicates; QuickCheck'd in Properties.RedownsampleGate)
-- ============================================================================

-- | POSITIVE case: a faithful reconstruction (the given coarse + its real held
-- detail, re-synthesised) passes the gate. Delegates the octant bijection
-- ("SixFour.Spec.OctreeCell" @lawOctantLadderBijective@) projected to the coarse band.
lawRedownsampleConsistency :: Int -> Int -> [Int] -> Bool
lawRedownsampleConsistency k d fine =
  not (d >= 1 && k >= 1 && k <= d && length fine == octreeLeafCount d)
    || let (coarse, detail) = octantDistill k fine
           recon            = octantSynthesize (coarse, detail)  -- = fine (bijection)
       in passesGate k coarse recon

-- | NOT-IMPOSSIBLE: invented detail is exempt. Two fine cubes with the SAME coarse
-- but DIFFERENT detail both pass for that coarse — so genuine super-res (the net
-- inventing high-frequency) is never rejected by the gate.
lawGateIgnoresInventedDetail :: Int -> Int -> [Int] -> Bool
lawGateIgnoresInventedDetail k d fine =
  not (d >= 1 && k >= 1 && k <= d && length fine == octreeLeafCount d)
    || let (coarse, detail) = octantDistill k fine
           invented         = map (map bump) detail            -- "invent" different high-freq
           fineInvented     = octantSynthesize (coarse, invented)
       in passesGate k coarse fineInvented
  where bump (a,b,c,e,f,g,h) = (a+7, b+7, c+7, e+7, f+7, g+7, h+7)

-- | NOT-VACUOUS (the teeth): a cube whose COARSE band drifted is REJECTED. Drift the
-- coarse, re-synthesise, and the gate fails — so coarse-band confirmation-bias
-- collapse is structurally caught, not merely threshold-guarded.
lawGateRejectsCoarseDrift :: Int -> Int -> [Int] -> Bool
lawGateRejectsCoarseDrift k d fine =
  not (d >= 1 && k >= 1 && k <= d && length fine == octreeLeafCount d)
    || let (coarse, detail) = octantDistill k fine
           coarse'          = map (+ 1) coarse                  -- drift the DC band
           fineDrift        = octantSynthesize (coarse', detail)
       in coarse' /= coarse                                     -- the drift is real
          && not (passesGate k coarse fineDrift)                -- ...and the gate rejects it

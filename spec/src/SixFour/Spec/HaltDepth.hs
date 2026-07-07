{- |
Module      : SixFour.Spec.HaltDepth
Description : THE HALT→DEPTH BRIDGE — the certified kinematic order ("SixFour.Spec.KinematicHaltPrior" 'certifiedOrder') of a region becomes its render DEPTH in the always-on multiscale GIF ("SixFour.Spec.RenderSelect" / "SixFour.Spec.CubeBrush"): motion earns SPATIAL fineness, stillness keeps COLOR-TIME. This is the missing piece between the halt floor the device already computes (@ColorHead.haltFloor@ → @s4_certified_order@, per-slot certified order over the 256 particle slots = the 16×16 region face) and the depth field @s4_render_select@ consumes. Pure integer, golden-mirrored by the Swift @HaltDepthBridge@.

THE ALLOCATION (form follows function, "SixFour.Spec.CubeBrush"). A region's certified order is its minimal sufficient prediction depth ('SixFour.Spec.KinematicHaltPrior.lawCheapestZeroLossHaltIsCertifiedOrder'): order 0/1 = static or constant-velocity, order 2 = acceleration, order ≥ 3 = higher motion. 'haltDepth' maps it to the three render depths:

  * order ≤ 1 → depth 0 → 16³ (a 4×4×4 spacetime block; coarsest space, MOST color-time)
  * order = 2 → depth 1 → 32³ (2×2×2 block)
  * order ≥ 3 → depth 2 → 64³ (a voxel; finest space, LEAST color-time)

An UNCERTIFIED region (device sentinel @order < 0@, window too short to falsify) is coarsest ('lawUncertifiedIsCoarsest'): you may not spend detail you cannot justify. The map is MONOTONE ('lawHaltDepthMonotone') and BOUNDED to the {0,1,2} "SixFour.Spec.RenderSelect" alphabet, and its block side is exactly what the select render reads ('lawDepthDrivesValidBlock', @blockSideAt (haltDepth o) = 4 `div` 2^depth@).

CO-DRIVEN WITH THE USER (the semilattice). The user's paint ("SixFour.Spec.CubeBrush" cube set) and the halt allocation merge by FINEST-WINS 'mergeDepth' = 'max' — a semilattice ('lawMergeSemilattice'), so the user can only ADD detail, never remove it ('lawUserCanOnlyRefine'), order-free and idempotent. Halt proposes; the brush refines.

THE COLOR-TIME TRADEOFF (the connection to "SixFour.Spec.ColorTime"). Depth is INVERSE color-time: a depth-@d@ region sits at ladder rung @k = 2 − d@, so its color-time factor is @4^(2−d)@ — a static depth-0 region integrates 16× the color-time of a moving depth-2 voxel ('lawMotionSpendsColorTime': more motion order ⇒ strictly less color-time). The multiscale render is the halt budget spending SPATIAL resolution where the scene moves and TEMPORAL color-time where it is still. When every region is high-order the field is all-depth-2 = the identity on V64 ('lawAllHighIsAllFine' → 'SixFour.Spec.RenderSelect.lawFineIsIdentity'), the safety hook for "all-fine == the uniform 64³ renderer, bit-for-bit". Pure-spec, exact @Integer@.
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none
module SixFour.Spec.HaltDepth
  ( -- * The halt → depth allocation
    haltDepth
  , depthOfCertified
    -- * Ladder / color-time relation
  , ladderRungOfDepth
  , colorTimeFactorOf
    -- * User co-drive (the finest-wins semilattice)
  , mergeDepth
    -- * Laws
  , lawHaltDepthBounded
  , lawHaltDepthMonotone
  , lawHaltDepthThresholds
  , lawUncertifiedIsCoarsest
  , lawDepthDrivesValidBlock
  , lawUserCanOnlyRefine
  , lawMergeSemilattice
  , lawAllHighIsAllFine
  , lawAllStaticIsAllCoarse
  , lawMotionSpendsColorTime
  , lawDepthOfCertifiedBounded
  ) where

import SixFour.Spec.KinematicHaltPrior (certifiedOrder)
import SixFour.Spec.RenderSelect (blockSideAt)

-- | THE ALLOCATION: certified kinematic order → render depth @{0,1,2}@. order ≤ 1 (static /
-- constant velocity, incl. the @order < 0@ uncertified sentinel) → 0 (16³); order = 2
-- (acceleration) → 1 (32³); order ≥ 3 → 2 (64³). Monotone, bounded, total.
haltDepth :: Int -> Int
haltDepth order
  | order <= 1 = 0
  | order == 2 = 1
  | otherwise  = 2

-- | The depth of a trajectory's region, composing with the real order source: @haltDepth ∘
-- certifiedOrder@. @cap@ is the halt-prior cap (the device uses 4).
depthOfCertified :: Int -> [Integer] -> Int
depthOfCertified cap f = haltDepth (certifiedOrder cap f)

-- | The isotropic-ladder rung of a render depth: @k = 2 − d@. Depth 0 (16³) is rung 2, depth 2
-- (64³) is rung 0 — depth and color-time run opposite.
ladderRungOfDepth :: Int -> Int
ladderRungOfDepth d = 2 - clampDepth d

-- | The color-time factor a region receives at a given order: @4^(2 − depth)@ = the @4^k@ of its
-- ladder rung ("SixFour.Spec.ColorTime"). Static → 16, mid → 4, moving → 1.
colorTimeFactorOf :: Int -> Integer
colorTimeFactorOf order = 4 ^ ladderRungOfDepth (haltDepth order)

-- | The user/halt co-drive: FINEST-WINS max ("SixFour.Spec.CubeBrush" depth semilattice). Both
-- arguments are clamped into the @{0,1,2}@ alphabet first.
mergeDepth :: Int -> Int -> Int
mergeDepth a b = max (clampDepth a) (clampDepth b)

-- | Clamp any integer into the render-depth alphabet @{0,1,2}@.
clampDepth :: Int -> Int
clampDepth = max 0 . min 2

-- ─────────────────────────────────────────────────────────────────────────────
-- Laws
-- ─────────────────────────────────────────────────────────────────────────────

-- | The allocation lands in the RenderSelect alphabet @{0,1,2}@.
lawHaltDepthBounded :: Int -> Bool
lawHaltDepthBounded o = let d = haltDepth o in d >= 0 && d <= 2

-- | MONOTONE: more motion order never yields a coarser region — @a ≤ b ⇒ haltDepth a ≤ haltDepth b@.
lawHaltDepthMonotone :: Int -> Int -> Bool
lawHaltDepthMonotone a b = a > b || haltDepth a <= haltDepth b

-- | The exact thresholds (spot goldens the Swift @HaltDepthBridge@ mirrors): −1/0/1 → 0, 2 → 1,
-- ≥3 → 2.
lawHaltDepthThresholds :: Bool
lawHaltDepthThresholds =
  map haltDepth [-1, 0, 1, 2, 3, 4, 99] == [0, 0, 0, 1, 2, 2, 2]

-- | UNCERTIFIED (order < 0, window too short) is coarsest — never invent detail you cannot certify.
lawUncertifiedIsCoarsest :: Int -> Bool
lawUncertifiedIsCoarsest o = o >= 0 || haltDepth o == 0

-- | The depth drives EXACTLY the RenderSelect block side @4 `div` 2^depth@ (4/2/1), so the field
-- is precisely what @s4_render_select@ consumes.
lawDepthDrivesValidBlock :: Int -> Bool
lawDepthDrivesValidBlock o =
  let d = haltDepth o in blockSideAt d == 4 `div` (2 ^ d)

-- | The brush can only REFINE the halt allocation: @mergeDepth user (haltDepth o) ≥ haltDepth o@.
lawUserCanOnlyRefine :: Int -> Int -> Bool
lawUserCanOnlyRefine userD o = mergeDepth userD (haltDepth o) >= haltDepth o

-- | 'mergeDepth' is a semilattice: idempotent, commutative, associative (order-free co-drive).
lawMergeSemilattice :: Int -> Int -> Int -> Bool
lawMergeSemilattice a b c =
  mergeDepth a a == clampDepth a
    && mergeDepth a b == mergeDepth b a
    && mergeDepth a (mergeDepth b c) == mergeDepth (mergeDepth a b) c

-- | ALL-FINE: every region high-order ⇒ the field is all-depth-2 = the identity on V64
-- ("SixFour.Spec.RenderSelect.lawFineIsIdentity") — the "all-fine == uniform 64³ renderer" safety.
lawAllHighIsAllFine :: [Int] -> Bool
lawAllHighIsAllFine orders =
  not (all (>= 3) orders) || all (\o -> haltDepth o == 2) orders

-- | ALL-STATIC: every region order ≤ 1 ⇒ the field is all-depth-0 (all 16³, maximal color-time).
lawAllStaticIsAllCoarse :: [Int] -> Bool
lawAllStaticIsAllCoarse orders =
  not (all (<= 1) orders) || all (\o -> haltDepth o == 0) orders

-- | THE TRADEOFF: more motion order spends strictly less color-time — @a ≤ b ⇒ colorTimeFactorOf
-- a ≥ colorTimeFactorOf b@. Detail on motion, color-time on stillness.
lawMotionSpendsColorTime :: Int -> Int -> Bool
lawMotionSpendsColorTime a b = a > b || colorTimeFactorOf a >= colorTimeFactorOf b

-- | Composing with the real certified-order source stays in the depth alphabet.
lawDepthOfCertifiedBounded :: Int -> [Integer] -> Bool
lawDepthOfCertifiedBounded cap f =
  let d = depthOfCertified (max 1 (abs cap)) f in d >= 0 && d <= 2

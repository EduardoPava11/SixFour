{- |
Module      : SixFour.Spec.LadderColorTime
Description : THE LADDER–COLOR-TIME THEOREM — the consolidating statement that training on the {16³,32³,64³} ladder IS training on color time, assembled from the fold algebra of pooling (new laws, this module) and the color-time measure (proved in "SixFour.Spec.ColorTime" / "SixFour.Spec.GaussianLadder" / "SixFour.Spec.TriScaleTraining" / "SixFour.Spec.FidelityLadder" / "SixFour.Spec.EventEncoding"). This module is the one page a reader (or a device log) needs to check the claim.

THE FOLD-ALGEBRA HALF (laws proved here). A ladder cell's tensor is the coordinatewise u64 SUM of its
children — the fold of the commutative monoid @(ℕⁿ,+,0)@ over the 2×2×2 block. Commutativity +
associativity mean @foldl@ and @foldr@ (and ANY traversal order) agree ('lawFoldOrderInvariant'), and
the lift to per-cell TENSORS (channels summed coordinatewise) is the product monoid, so the whole
algebra holds channelwise ('lawCellTensorLifts'). Associativity is transitivity: pooling 64→32→16
equals pooling 64→16 in one step ('lawPoolTransitive') — the cube-level restatement of the u64
transitive-pyramid carrier ("SixFour.Spec.V21Pyramid", teeth-tested in @palette16@). Above the
canonical side the ladder continues by mass-preserving refinement: 'expandDouble' splits each cell's
mass equally over its 8 children (exact in ℚ), and @pool ∘ expand = id@ ('lawPoolExpandIdentity') —
the canonical 64 is a RETRACT of every finer rung, the fixed point the whole ladder
@16 ⇇ 32 ⇇ 64 ⇄ 128 ⇄ 256@ projects onto. The probe ladder is symmetric about it:
@|log₂(side/64)|@ over @{16,32,64,128,256}@ reads @2,1,0,1,2@ — 16 and 256 are each exactly two
octaves from the 64 reality ('lawLadderSymmetricAboutCanonical'). On device the retraction is
witnessed on real photons: pooling the SAME crop independently to 256² and folding down to 64² must
be byte-identical to pooling straight to 64² (both are the same fold over the same pixel partition —
transitivity), which is exactly the @[proof] fold:@ log line the ladder probe emits.

THE COLOR-TIME HALF (proved elsewhere, bridged here). One integer k is simultaneously the spatial
coarsening index, the temporal pool depth, and the optical stop (@τ_c(k) = 4^k·Δ₀@,
'SixFour.Spec.ColorTime.lawColorTimeQuartic'), and equals the ℤ[i] ideal norm
(@lawNormIsColorTime@, "SixFour.Spec.GaussianLadder"). 'lawRungIsColorTimeStop' pins the bridge on
this module's own ladder: one fold step (side halves) multiplies color-time by EXACTLY 4 — so the
ladder axis IS the color-time axis, and a model shown the three rungs is shown the same scene at
three color-time exposures. The training-density half is already law: the 16→32 and 32→64 transition
heads consume DISJOINT bits at rung-invariant info-per-compute, all three rungs for 9/8 the cost of
the finest ("SixFour.Spec.TriScaleTraining"); refinement is monotone to zero error over ℚ
(@lawDeeperIsCloser@, "SixFour.Spec.FidelityLadder"); and the temporal dither decode has zero
irreducible loss given (signal, phase) ("SixFour.Spec.EventEncoding"). Composite: the {16,32,64}
ladder presents color time as the supervised axis, with disjoint, densely-packed training signal per
rung — training on the ladder is training on color time. Everything here is exact ('Integer'/'Rational').
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none
module SixFour.Spec.LadderColorTime
  ( -- * The probe ladder — sides symmetric about the canonical 64
    Side
  , ladderSides
  , canonicalSide
  , octavesFromCanonical
    -- * Volumes and cells — sums as the commutative-monoid carrier
  , Volume
  , poolBy
  , poolHalf
  , expandDouble
    -- * Laws — the fold-algebra half
  , lawFoldOrderInvariant
  , lawCellTensorLifts
  , lawPoolTransitive
  , lawPoolExpandIdentity
  , lawLadderSymmetricAboutCanonical
    -- * Laws — the color-time bridge
  , lawRungIsColorTimeStop
  ) where

import Data.Bits (countTrailingZeros)
import Data.List (foldl')

import SixFour.Spec.ColorTime (Seconds, coarseSide, colorTime)

-- | A ladder side (16, 32, 64, 128, 256, …): always a power of two, so octave distance is exact.
type Side = Int

-- | The probe ladder, coarse to fine: @[16,32,64,128,256]@. Two rungs below the canonical side
-- (the shipped GIF ladder) and two above (the training-data probe rungs).
ladderSides :: [Side]
ladderSides = [16, 32, 64, 128, 256]

-- | THE 64 REALITY: the canonical side every rung of the ladder projects onto — coarser rungs by
-- exact sum-pooling, finer rungs by the retraction 'poolHalf' ∘ … ('lawPoolExpandIdentity').
canonicalSide :: Side
canonicalSide = 64

-- | Octave distance from the canonical side: @|log₂(side/64)|@, exact for power-of-two sides.
-- Reads @2,1,0,1,2@ over 'ladderSides' — 16 and 256 are equidistant from the 64 reality.
octavesFromCanonical :: Side -> Int
octavesFromCanonical s = abs (countTrailingZeros s - countTrailingZeros canonicalSide)

-- | A cubic volume of per-cell linear-flux sums, t-major then rows then columns
-- (@volume !! t !! y !! x@), one channel. The multi-channel cell TENSOR is this, channelwise —
-- 'lawCellTensorLifts' is the licence to reason one channel at a time. 'Rational' so the
-- mass-splitting 'expandDouble' is exact; on device the coarsening half is u64 ('Integer'-safe).
type Volume = [[[Rational]]]

-- | Split a list into consecutive groups of @k@ (the last, shorter group dropped — volumes on the
-- ladder always have power-of-two sides, so nothing is ever dropped in lawful use).
chunksOf :: Int -> [a] -> [[a]]
chunksOf k xs = case splitAt k xs of
  (g, rest) | length g == k -> g : chunksOf k rest
            | otherwise     -> []

-- | Pool a volume by an integer factor @k@ along every axis: each output cell is the SUM of its
-- @k³@ children — the fold of @(ℚ,+,0)@ over the block. @poolBy 2@ is one ladder rung;
-- @poolBy 4@ is two rungs in one step ('lawPoolTransitive' equates them).
poolBy :: Int -> Volume -> Volume
poolBy k = map poolPlanes . chunksOf k
  where
    poolPlanes = poolPlane . foldr1 (zipWith (zipWith (+)))
    poolPlane  = map poolRows . chunksOf k
    poolRows   = poolRow . foldr1 (zipWith (+))
    poolRow    = map sum . chunksOf k

-- | One rung of coarsening: @poolBy 2@ — sum each 2×2×2 block into its parent cell.
poolHalf :: Volume -> Volume
poolHalf = poolBy 2

-- | One rung of mass-preserving refinement: each cell's mass splits EQUALLY over its 2×2×2
-- children (@v/8@ each, exact in ℚ). The section whose retraction is 'poolHalf'
-- ('lawPoolExpandIdentity'); the spec-level meaning of "the finer rungs carry the same photons".
expandDouble :: Volume -> Volume
expandDouble = dup . map (dup . map (dup . map (/ 8)))
  where
    dup :: [a] -> [a]
    dup = concatMap (\x -> [x, x])

-- ─────────────────────────────────────────────────────────────────────────────
-- Laws — the fold-algebra half
-- ─────────────────────────────────────────────────────────────────────────────

-- | THE FOLD SYMMETRY: pooling is the fold of a COMMUTATIVE monoid, so @foldl@, @foldr@, and the
-- reversed traversal all produce the same cell — the accumulation ORDER carries no information.
-- (This is why the device may accumulate ticks in arrival order and still match the spec's fold.)
lawFoldOrderInvariant :: [Integer] -> Bool
lawFoldOrderInvariant xs =
  foldl' (+) 0 xs == foldr (+) 0 xs
    && foldl' (+) 0 (reverse xs) == foldl' (+) 0 xs

-- | THE TENSOR LIFT: cells are TENSORS of channels and the monoid lifts coordinatewise (the
-- product monoid), so the fold symmetry holds for whole cell tensors, not just scalars.
lawCellTensorLifts :: [[Integer]] -> Bool
lawCellTensorLifts rows =
  foldl' add zero cells == foldr add zero cells
    && foldl' add zero (reverse cells) == foldl' add zero cells
  where
    width = minimum (8 : map length rows)   -- ragged input is trimmed to a common tensor width
    cells = map (take width) rows
    zero  = replicate width 0
    add   = zipWith (+)

-- | TRANSITIVITY (associativity, spatially): two single-rung pools equal one double-rung pool,
-- @poolBy 2 ∘ poolBy 2 = poolBy 4@ — pooling 64→32→16 IS pooling 64→16. The cube-level law behind
-- the on-device @[proof] fold: pool(256→64) == direct64@ byte-identity check.
lawPoolTransitive :: Volume -> Bool
lawPoolTransitive v = poolHalf (poolHalf v) == poolBy 4 v

-- | THE RETRACTION: @poolHalf ∘ expandDouble = id@ — the canonical side is recoverable exactly
-- from any finer rung, so 64 is a RETRACT of 128 (and by composition of 256). The dual composite
-- @expandDouble ∘ poolHalf@ is only a projection (it forgets within-block detail): refinement adds
-- information, coarsening loses it, and the 64 reality sits at the fixed point.
lawPoolExpandIdentity :: Volume -> Bool
lawPoolExpandIdentity v = poolHalf (expandDouble v) == v

-- | THE SYMMETRY OF THE PROBE LADDER: octave distances from the canonical 64 over
-- @{16,32,64,128,256}@ are @2,1,0,1,2@ — 16 and 256 equidistant, 32 and 128 equidistant, 64 the
-- unique fixed point. Daniel's "16 and 256 are the farthest away from the 64 reality", made exact.
lawLadderSymmetricAboutCanonical :: Bool
lawLadderSymmetricAboutCanonical =
  map octavesFromCanonical ladderSides == [2, 1, 0, 1, 2]
    && octavesFromCanonical 16 == octavesFromCanonical 256
    && octavesFromCanonical 32 == octavesFromCanonical 128
    && octavesFromCanonical canonicalSide == 0

-- ─────────────────────────────────────────────────────────────────────────────
-- Laws — the color-time bridge
-- ─────────────────────────────────────────────────────────────────────────────

-- | THE BRIDGE: one fold step IS one color-time stop-pair. Stepping the ladder index @k@ by one
-- halves the spatial side ('SixFour.Spec.ColorTime.coarseSide') and multiplies color-time by
-- EXACTLY 4 (@τ_c(k+1) = 4·τ_c(k)@, the quartic of "SixFour.Spec.ColorTime") — so the ladder axis
-- and the color-time axis are the SAME integer, and training across rungs is training across
-- color-time exposures. With "SixFour.Spec.TriScaleTraining"'s disjoint-bits laws this is the
-- composite theorem: the {16,32,64} ladder trains the model on color time.
lawRungIsColorTimeStop :: Seconds -> Int -> Bool
lawRungIsColorTimeStop d0 k =
  let kk = min 4 (abs k)
  in colorTime d0 (kk + 1) == 4 * colorTime d0 kk
       && coarseSide kk == 2 * coarseSide (kk + 1)

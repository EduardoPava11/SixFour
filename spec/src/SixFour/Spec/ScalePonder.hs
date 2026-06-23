{- |
Module      : SixFour.Spec.ScalePonder
Description : Per-scale structured halting — the replacement for LookNetR's scalar PonderNet halt.

The octree canon replaces the scalar PonderNet halt (one @λ_ℓ@ per level collapsed
to a single stop-depth) with a STRUCTURED per-scale decision: a transformer ponders
WHICH octree scales to refine. The spec fixes the CONTRACT that decision must obey
(the transformer producing it is downstream, off-spec) — a per-level refine mask
over the octant ladder's ("SixFour.Spec.OctreeCell") detail bands.

  * 'lawRefineAllIsLossless' — refining every scale keeps all detail = the exact
    reversible floor (full compute ⇒ identity).
  * 'lawScalarHaltIsContiguous' — the retired scalar halt is a CONTIGUOUS cutoff
    (refine a prefix of scales, halt the rest).
  * 'lawPonderExceedsScalarHalt' — a non-contiguous ponder is unreachable by any
    scalar cutoff, so per-scale pondering is strictly more expressive (the
    adaptive-basis canon: keep fine detail HERE, drop it THERE).

GHC-boot-only. Laws are exported predicates, QuickCheck'd in @Properties.ScalePonder@.
-}
-- COMPARTMENT: MLX-MODEL | tag:MacTag | STRADDLER
module SixFour.Spec.ScalePonder
  ( -- * The per-scale ponder mask
    Ponder
  , refineAll
  , scalarHalt
  , applyPonder
    -- * Laws (QuickCheck'd in @Properties.ScalePonder@)
  , lawRefineAllIsLossless
  , lawScalarHaltIsContiguous
  , lawPonderExceedsScalarHalt
  ) where

import SixFour.Spec.OctreeCell (Detail, octantDistill, octantSynthesize)

-- | A per-octree-level refine decision (finest-first, matching 'octantDistill').
-- @True@ = refine this scale (keep its detail); @False@ = halt it (drop to floor).
type Ponder = [Bool]

-- | Refine every scale — full compute, all detail kept (the lossless extreme).
refineAll :: Int -> Ponder
refineAll n = replicate n True

-- | The retired scalar-PonderNet halt: refine a contiguous prefix of @k@ scales,
-- halt the rest (a single stop-depth).
scalarHalt :: Int -> Int -> Ponder
scalarHalt n k = replicate m True ++ replicate (n - m) False
  where m = max 0 (min k n)

-- | Apply a ponder to a distilled cube: keep detail where refined, zero it where
-- halted (halting a scale truncates it to its coarse floor). Coarse/DC untouched.
applyPonder :: Ponder -> ([Int], [[Detail]]) -> ([Int], [[Detail]])
applyPonder ps (coarse, dets) = (coarse, zipWith keep ps dets)
  where
    keep True  d = d
    keep False d = map (const zero7) d
    zero7 = (0,0,0,0,0,0,0)

-- | Refining every scale is the exact reversible floor (full compute ⇒ identity).
lawRefineAllIsLossless :: Int -> [Int] -> Bool
lawRefineAllIsLossless d xs =
  not (d >= 0 && length xs == 8 ^ d)
    || let dist      = octantDistill d (take (8 ^ d) xs)
           (_, dets) = dist
       in octantSynthesize (applyPonder (refineAll (length dets)) dist) == take (8 ^ d) xs

-- | The scalar halt is a contiguous prefix of refined scales (no gaps).
lawScalarHaltIsContiguous :: Int -> Int -> Bool
lawScalarHaltIsContiguous n k =
  n < 0 || bs == takeWhile id bs ++ replicate (length bs - length (takeWhile id bs)) False
  where bs = scalarHalt n k

-- | A non-contiguous ponder is unreachable by any scalar cutoff — per-scale
-- pondering is strictly more expressive than a single stop-depth.
lawPonderExceedsScalarHalt :: Bool
lawPonderExceedsScalarHalt =
  let p = [True, False, True]            -- keep finest + coarsest, drop the middle
  in all (\k -> scalarHalt 3 k /= p) [0 .. 3]

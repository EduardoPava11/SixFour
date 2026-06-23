{- |
Module      : SixFour.Spec.PerScaleWeights
Description : Per-scale (distinct) octree weights — the replacement for LookNetR's ONE weight-tied block.

The octree canon mandates __PER-SCALE weights__: each rung of the octant ladder
("SixFour.Spec.OctreeCell" 'octantDistill') carries its OWN learned gain on its
detail bands, not a single block reused at every depth (the retired
@LookNetR.sharedBlockCount = 1@ Mixture-of-Recursions design).

A weighting is a depth-indexed list applied to the detail levels of a distilled
cube. Two properties pin the canon:

  * 'lawNeutralIsFloor' — the neutral (all-@1@) weighting is the exact reversible
    floor (the "bounded addition above a frozen Q16 floor" rule: zero learned
    change ⇒ identity), reusing 'octantSynthesize' \/ 'octantDistill'.
  * 'lawPerScaleExceedsTied' — a genuinely per-scale weighting (different gains at
    different rungs) is unreachable by any single tied weight, so per-scale is
    __strictly more expressive__ than the tied block it replaces; 'lawTiedSubsumed'
    shows the tied design is the degenerate all-equal special case.

GHC-boot-only. Laws are exported predicates, QuickCheck'd in @Properties.PerScaleWeights@.
-}
-- COMPARTMENT: MLX-MODEL | tag:MacTag | STRADDLER
module SixFour.Spec.PerScaleWeights
  ( -- * Per-scale weights
    ScaleWeights
  , neutral
  , tied
  , applyPerScale
    -- * Laws (QuickCheck'd in @Properties.PerScaleWeights@)
  , lawNeutralIsFloor
  , lawTiedSubsumed
  , lawPerScaleExceedsTied
  ) where

import SixFour.Spec.OctreeCell (Detail, octantDistill, octantSynthesize)

-- | One integer gain per octree level (depth-indexed, finest-first to match
-- 'octantDistill'). Distinct entries = the per-scale canon; all-equal = the
-- retired tied block.
type ScaleWeights = [Int]

-- | The neutral weighting for @n@ levels: gain @1@ everywhere = the reversible floor.
neutral :: Int -> ScaleWeights
neutral n = replicate n 1

-- | The retired tied design as a special case: one weight @k@ reused at every
-- one of @n@ levels.
tied :: Int -> Int -> ScaleWeights
tied n k = replicate n k

-- | Scale each detail level by its per-scale gain (the coarse value is untouched —
-- the balance/DC axis is preserved; only the search/detail bands are weighted).
applyPerScale :: ScaleWeights -> ([Int], [[Detail]]) -> ([Int], [[Detail]])
applyPerScale ws (coarse, dets) = (coarse, zipWith scaleLevel ws dets)
  where
    scaleLevel s = map (scale7 s)
    scale7 s (a,b,c,d,e,f,g) = (a*s, b*s, c*s, d*s, e*s, f*s, g*s)

-- | The neutral weighting is the exact reversible floor: weighting a distilled
-- cube by all-@1@ then synthesizing recovers the input (bounded addition above
-- the frozen floor — zero learned change ⇒ identity).
lawNeutralIsFloor :: Int -> [Int] -> Bool
lawNeutralIsFloor d xs =
  not (d >= 0 && length xs == 8 ^ d)
    || let dist      = octantDistill d (take (8 ^ d) xs)
           (_, dets) = dist
       in octantSynthesize (applyPerScale (neutral (length dets)) dist) == take (8 ^ d) xs

-- | The tied design is the all-equal special case of a per-scale weighting (so
-- per-scale weights SUBSUME and supersede @LookNetR@'s single shared block).
lawTiedSubsumed :: Int -> Int -> Bool
lawTiedSubsumed n k = n < 0 || (tied n k == replicate n k && all (== k) (tied n k))

-- | A genuinely per-scale weighting (@[1,3]@: different gains at the two rungs of a
-- non-constant cube) is unreachable by either tied weight that agrees on one rung
-- (@[1,1]@ or @[3,3]@) — per-scale is strictly more expressive than tied.
lawPerScaleExceedsTied :: Bool
lawPerScaleExceedsTied =
  let dist = octantDistill 2 [0 .. 63]
  in applyPerScale [1,3] dist /= applyPerScale [1,1] dist
  && applyPerScale [1,3] dist /= applyPerScale [3,3] dist

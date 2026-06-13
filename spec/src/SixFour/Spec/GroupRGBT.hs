{- |
Module      : SixFour.Spec.GroupRGBT
Description : 64 frames = 16 RGBT groups of 4; GROUP-SELECT drives the global collapse.

The capture is 64 frames; the user reads them as **16 groups of 4** (each group of 4 = one
R/G/B/T quartet, @docs/SIXFOUR-LAB-CHOICES.md@). The load-bearing LAB choice (group-select,
the 8.5-ranked one) is: **which groups feed the one global palette.** Today
'SixFour.Spec.Collapse.globalCollapseQ16' pools ALL 64 frames, so the picks change nothing —
this module makes them real.

== Why SELECT, not weight ==

The merge is a maximin (farthest-point, Gonzalez 1985) collapse, driven by /distance/, not
/frequency/. Replicating a group's candidates (the "weight = copy-count" idea) adds points at
distance 0, which extend no coverage — so replication is ~a no-op for maximin (it only nudges
the mean used for the first seed). The honest, maximin-correct lever is therefore a BINARY
include/exclude per group: pooling only the selected groups changes the candidate /set/, which
genuinely changes the 256 surviving leaves. (Continuous per-group weighting waits for the
k-means / coverage↔fidelity path, where multiplicity actually moves centroids.)

Laws (QuickCheck'd in @Properties.GroupRGBT@, EXACT — no tolerance):
  * selecting ALL groups is byte-identical to today's 'globalCollapseQ16' (backward-compat);
  * the selected candidate pool is a SUBSET of the full pool (selection only removes);
  * deselecting a group removes exactly that group's frames from the pool (scoped);
  * an empty selection yields an empty pool (and an empty collapse).
-}
module SixFour.Spec.GroupRGBT
  ( -- * The 16×4 grouping
    groupSize
  , numGroups
  , groupsOf4
    -- * Group-select
  , GroupMask
  , allSelected
  , selectedFrames
  , groupCollapseQ16
    -- * Laws (QuickCheck'd in Properties.GroupRGBT)
  , lawAllSelectedEqualsToday
  , lawSelectedPoolIsSubset
  , lawDeselectExcludesGroupFrames
  , lawEmptySelectionEmptyPool
  ) where

import Data.List (isSubsequenceOf)

import SixFour.Spec.Collapse (PxQ16, pooledCandidatesQ16, globalCollapseQ16)

-- | Frames per RGBT group (R, G, B, T).
groupSize :: Int
groupSize = 4

-- | Groups in a full 64-frame burst (64 / 4).
numGroups :: Int
numGroups = 16

-- | Chunk a frame list into consecutive groups of 'groupSize'. @concat . groupsOf4 = id@
-- for any list, so it never loses or reorders frames.
groupsOf4 :: [a] -> [[a]]
groupsOf4 [] = []
groupsOf4 xs = take groupSize xs : groupsOf4 (drop groupSize xs)

-- | A per-group include/exclude mask (one 'Bool' per group). Shorter than the group count
-- excludes the unmasked tail; longer ignores the extra (via 'zip').
type GroupMask = [Bool]

-- | The all-true mask for a given frame list (selects every group).
allSelected :: [[PxQ16]] -> GroupMask
allSelected frames = replicate (length (groupsOf4 frames)) True

-- | Keep only the frames belonging to SELECTED groups, in original order.
selectedFrames :: GroupMask -> [[PxQ16]] -> [[PxQ16]]
selectedFrames mask frames =
  concat [ grp | (keep, grp) <- zip mask (groupsOf4 frames), keep ]

-- | The group-aware global collapse: pool only the selected groups, then the EXISTING
-- maximin ('globalCollapseQ16'). This is the byte-exact seam the picks drive.
groupCollapseQ16 :: Int -> GroupMask -> [[PxQ16]] -> [PxQ16]
groupCollapseQ16 k mask = globalCollapseQ16 k . selectedFrames mask

-- ---------------------------------------------------------------------------
-- Laws
-- ---------------------------------------------------------------------------

-- | Selecting ALL groups is byte-identical to today's pooled 'globalCollapseQ16' — the
-- backward-compatibility golden (weight-1-everywhere ≡ today). @selectedFrames allSelected =
-- concat . groupsOf4 = id@, so nothing changes when every group is in.
lawAllSelectedEqualsToday :: Int -> [[PxQ16]] -> Bool
lawAllSelectedEqualsToday k frames =
  groupCollapseQ16 k (allSelected frames) frames == globalCollapseQ16 k frames

-- | Selection can only REMOVE: the selected candidate pool is a subsequence of the full
-- pool (so every leaf still comes from a real captured colour, gamut-closure preserved).
lawSelectedPoolIsSubset :: GroupMask -> [[PxQ16]] -> Bool
lawSelectedPoolIsSubset mask frames =
  pooledCandidatesQ16 (selectedFrames mask frames)
    `isSubsequenceOf` pooledCandidatesQ16 frames

-- | Deselecting a single group removes EXACTLY that group's frames from the pool and leaves
-- every other group's frames intact (scoped editing — the brush-pick rule).
lawDeselectExcludesGroupFrames :: Int -> [[PxQ16]] -> Bool
lawDeselectExcludesGroupFrames g frames =
  let groups = groupsOf4 frames
      n      = length groups
  in n == 0 ||
     let j        = abs g `mod` n
         mask     = [ i /= j | i <- [0 .. n - 1] ]
         kept     = selectedFrames mask frames
         expected = concat [ grp | (i, grp) <- zip [0 ..] groups, i /= j ]
     in kept == expected

-- | An empty selection yields an empty pool (and hence an empty collapse for any k).
lawEmptySelectionEmptyPool :: [[PxQ16]] -> Bool
lawEmptySelectionEmptyPool frames =
  let mask = replicate (length (groupsOf4 frames)) False
  in null (pooledCandidatesQ16 (selectedFrames mask frames))

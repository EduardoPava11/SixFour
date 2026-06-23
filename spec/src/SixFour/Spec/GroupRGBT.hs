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

== The circular RGBT buffer (the SIMT sliding window) ==

'circularWindows' is the stride-1, width-4 CIRCULAR sliding window: @n@ overlapping windows, one
per frame, wrapping through @[frame n-1, frame 0, …]@ — keeping the per-frame structure intact
while giving each frame its 4-frame RGBT neighbourhood, and respecting the GIF loop. This is the
SIMT buffer: @n@ window-threads, each a width-4 (R/G/B/T) SIMD lane group. The staggering is the
elegant part — across the four windows a frame belongs to, it occupies each of the R, G, B, T lanes
EXACTLY ONCE ('lawRoleOrbitComplete'), so the role assignment is balanced and @C_n@-gauge-consistent
('lawWindowsRotationEquivariant', tying the buffer to "SixFour.Spec.CanonicalPhase"). See
@docs/SIXFOUR-RGBT4D-BUFFER-HARDENING-WORKFLOW.md@ Phase 1.

Laws (QuickCheck'd in @Properties.GroupRGBT@, EXACT — no tolerance):
  * selecting ALL groups is byte-identical to today's 'globalCollapseQ16' (backward-compat);
  * the selected candidate pool is a SUBSET of the full pool (selection only removes);
  * deselecting a group removes exactly that group's frames from the pool (scoped);
  * an empty selection yields an empty pool (and an empty collapse).
-}
-- COMPARTMENT: ZIG-FLOOR | tag:CommitSide
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
    -- * The circular RGBT buffer (stride-1 sliding window)
  , circularWindows
  , rgbtWindows
    -- * Laws (QuickCheck'd in Properties.GroupRGBT)
  , lawAllSelectedEqualsToday
  , lawSelectedPoolIsSubset
  , lawDeselectExcludesGroupFrames
  , lawEmptySelectionEmptyPool
  , lawWindowCount
  , lawWindowWidth
  , lawEachFrameInWindowCount
  , lawRoleOrbitComplete
  , lawWindowsCoverCycle
  , lawCircularWrap
  , lawWindowsRotationEquivariant
  ) where

import Data.List (isSubsequenceOf, sort)

import SixFour.Spec.GlobalCollapseQ16      (PxQ16, pooledCandidatesQ16, globalCollapseQ16)
import SixFour.Spec.CanonicalPhase (rotateBy)

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

-- ---------------------------------------------------------------------------
-- The circular RGBT buffer (stride-1 sliding window) — Phase 1
-- ---------------------------------------------------------------------------

-- | Stride-1, width-@w@ CIRCULAR sliding windows over a cyclic sequence: window @i@ is
-- @[xs!!i, xs!!(i+1), …, xs!!(i+w-1)]@ taken mod @n@, so the loop wraps. Produces exactly
-- @n@ windows (one per frame) — the per-frame structure is preserved. Content-independent
-- index structure: works over any element type.
circularWindows :: Int -> [a] -> [[a]]
circularWindows w xs
  | w <= 0 || null xs = []
  | otherwise =
      let n = length xs
      in [ [ xs !! ((i + j) `mod` n) | j <- [0 .. w - 1] ] | i <- [0 .. n - 1] ]

-- | The RGBT circular buffer: width-'groupSize' (= 4) 'circularWindows'. Each window's
-- four cells are the @R, G, B, T@ lanes; the staggering gives every frame all four roles
-- exactly once ('lawRoleOrbitComplete').
rgbtWindows :: [a] -> [[a]]
rgbtWindows = circularWindows groupSize

-- | One window per frame: @|circularWindows w xs| = |xs|@.
lawWindowCount :: Int -> [a] -> Bool
lawWindowCount w xs =
  w <= 0 || null xs || length (circularWindows w xs) == length xs

-- | Every window is a full width-@w@ quartet — no partial windows (the wrap fills them).
lawWindowWidth :: Int -> [a] -> Bool
lawWindowWidth w xs =
  w <= 0 || null xs || all ((== w) . length) (circularWindows w xs)

-- | Each frame appears in EXACTLY @w@ windows (when @w ≤ n@) — it is the lane-@j@ entry of
-- window @(k−j) mod n@ for each @j@. Counted over the position structure.
lawEachFrameInWindowCount :: Int -> Int -> Bool
lawEachFrameInWindowCount w n =
  w <= 0 || n <= 0 || w > n ||
  let wins = circularWindows w [0 .. n - 1]
  in all (\k -> length (filter (k `elem`) wins) == w) [0 .. n - 1]

-- | THE role-orbit law: across the @w@ windows it belongs to, each frame occupies each
-- lane position @0..w-1@ EXACTLY ONCE. For RGBT (@w=4@) every frame is R, then G, then B,
-- then T across its windows — the balanced, @C_n@-gauge-symmetric staggering.
lawRoleOrbitComplete :: Int -> Int -> Bool
lawRoleOrbitComplete w n =
  w <= 0 || n <= 0 || w > n ||
  let wins        = circularWindows w [0 .. n - 1]
      positionsOf k = [ j | win <- wins, (j, e) <- zip [0 ..] win, e == k ]
  in all (\k -> sort (positionsOf k) == [0 .. w - 1]) [0 .. n - 1]

-- | The windows tile the cycle in order: the head of each window recovers the source
-- sequence (@map head (circularWindows w xs) = xs@) — one window per frame, starting there.
lawWindowsCoverCycle :: Eq a => Int -> [a] -> Bool
lawWindowsCoverCycle w xs =
  w <= 0 || null xs || map head (circularWindows w xs) == xs

-- | The loop closes: the last window wraps to include frame 0
-- (@last win = [xs!!(n-1), xs!!0, …]@), for width ≥ 2 and @n ≥ 2@.
lawCircularWrap :: Eq a => [a] -> Bool
lawCircularWrap xs =
  null xs || length xs < 2 ||
  let n       = length xs
      lastWin = last (circularWindows groupSize xs)
  in head lastWin == xs !! (n - 1) && (lastWin !! 1) == head xs

-- | Rotation-equivariance — the buffer respects the loop gauge:
-- @circularWindows w (rotateBy k xs) = rotateBy k (circularWindows w xs)@. So canonicalising
-- the frame phase ("SixFour.Spec.CanonicalPhase") canonicalises the whole buffer.
lawWindowsRotationEquivariant :: Eq a => Int -> Int -> [a] -> Bool
lawWindowsRotationEquivariant w k xs =
  w <= 0 || null xs ||
  circularWindows w (rotateBy k xs) == rotateBy k (circularWindows w xs)

{- |
Module      : SixFour.Spec.SignificanceFixed
Description : Deterministic FIXED-POINT (Q16) significance split-fill — the
              bit-exact source of truth for the Zig @s4_significance_fill@.

This mirrors the app's @SignificantSplitFill.rescue@ (the operation that runs in
the GIF path, AFTER dithering, on already-assigned indices) — NOT the Haskell
@Significance.splitFillFrame@ producer (which seeds + Voronoi-assigns from
scratch). The contract:

  * for each palette slot @k@ with population @< minPopulation@, in slot order,
    pull the pixel NEAREST to @centroids[k]@ (the fixed centroid, in Q16 OKLab)
    out of some donor slot that can spare one (@count > minPopulation@), until
    @k@ reaches @minPopulation@;
  * distances are squared Q16 OKLab (i64), tie-break STRICT @<@ ⇒ the lowest
    pixel index wins — identical to the Swift @d < bestD@ loop;
  * mass is conserved (a move re-labels one pixel, never drops one), so the
    result stays a length-@P@ surjective assignment with every slot @≥ n_min@.

The cell statistics (@cellsQ16@) are a fresh Q16 definition: population mean
(@Σx \`quot\` n@) and per-axis std (@isqrt(Σ(x-μ)² \`quot\` n)@, an exact integer
floor sqrt). They never enter the GIF bytes; they back the
'SignificantVoxelVolume' brand (σ ≥ 0, μ within range).
-}
-- COMPARTMENT: ZIG-FLOOR | tag:DeviceTag
module SixFour.Spec.SignificanceFixed
  ( rescueQ16
  , cellsQ16
  , isqrtInt
  , distSqQ16
  , CellQ16
  ) where

import           Data.List       (foldl')
import qualified Data.Vector     as V

import SixFour.Spec.Significance (minPopulation)

-- | Squared Q16 OKLab distance (i64 fits: each Δ ≤ ~131072, Δ² ≤ ~1.7e10, ×3).
distSqQ16 :: (Int, Int, Int) -> (Int, Int, Int) -> Int
distSqQ16 (l1, a1, b1) (l2, a2, b2) =
  let dl = l1 - l2; da = a1 - a2; db = b1 - b2
  in dl * dl + da * da + db * db

-- | Significance rescue in Q16. Returns the rebalanced index assignment.
-- @centroids@ has @k@ Q16 OKLab triples; @indices@/@pixels@ have length @P@.
rescueQ16
  :: Int                       -- ^ k (palette slots)
  -> [(Int, Int, Int)]         -- ^ centroids, length k
  -> [Int]                     -- ^ initial indices, length P (each in [0,k))
  -> [(Int, Int, Int)]         -- ^ pixels, length P (Q16 OKLab)
  -> [Int]
rescueQ16 k centroids indices pixels
  | V.all (>= nMin) counts0 = indices          -- fast path: already significant
  | otherwise               = V.toList (fst (foldl' fillSlot (idx0, counts0) [0 .. k - 1]))
  where
    nMin   = minPopulation
    pv     = V.fromList pixels
    cv     = V.fromList centroids
    idx0   = V.fromList indices
    p      = V.length idx0
    counts0 = V.accum (+) (V.replicate k 0) [ (s, 1) | s <- indices ]

    fillSlot (idx, counts) slot
      | counts V.! slot >= nMin = (idx, counts)
      | otherwise               = loop (idx, counts)
      where
        target = cv V.! slot
        loop (ix, cnt)
          | cnt V.! slot >= nMin = (ix, cnt)
          | otherwise =
              case bestDonor ix cnt of
                Nothing -> (ix, cnt)            -- infeasible shape: leave as-is
                Just bi ->
                  let s   = ix V.! bi
                      ix' = ix V.// [(bi, slot)]
                      cnt' = cnt V.// [ (s, cnt V.! s - 1), (slot, cnt V.! slot + 1) ]
                  in loop (ix', cnt')
        -- nearest-to-target donor pixel; strict < ⇒ lowest index on ties.
        bestDonor ix cnt = fmap snd (go Nothing 0)
          where
            go best i
              | i >= p = best
              | otherwise =
                  let s = ix V.! i
                  in if s == slot || cnt V.! s <= nMin
                       then go best (i + 1)
                       else
                         let d = distSqQ16 (pv V.! i) target
                         in case best of
                              Just (bd, _) | d >= bd -> go best (i + 1)
                              _                       -> go (Just (d, i)) (i + 1)

-- | One slot's Q16 cell: (μL, μa, μb, σL, σa, σb, count).
type CellQ16 = (Int, Int, Int, Int, Int, Int, Int)

-- | Per-slot Q16 cell statistics from the final assignment. Empty slots
-- (unreachable post-rescue on a feasible shape) fall back to the centroid with
-- σ = 0, count 0 — honest accounting, matching the Swift degenerate fallback.
cellsQ16
  :: Int                       -- ^ k
  -> [(Int, Int, Int)]         -- ^ centroids, length k
  -> [Int]                     -- ^ indices, length P
  -> [(Int, Int, Int)]         -- ^ pixels, length P
  -> [CellQ16]
cellsQ16 k centroids indices pixels =
  [ cell slot | slot <- [0 .. k - 1] ]
  where
    cv = V.fromList centroids
    members slot = [ px | (s, px) <- zip indices pixels, s == slot ]
    cell slot =
      case members slot of
        [] -> let (cl, ca, cb) = cv V.! slot in (cl, ca, cb, 0, 0, 0, 0)
        ms ->
          let n = length ms
              (sl, sa, sb) =
                foldl' (\(al, aa, ab) (l, a, b) -> (al + l, aa + a, ab + b)) (0, 0, 0) ms
              ml = sl `quot` n; ma = sa `quot` n; mb = sb `quot` n
              (vl, va, vb) =
                foldl' (\(al, aa, ab) (l, a, b) ->
                          let dl = l - ml; da = a - ma; db = b - mb
                          in (al + dl * dl, aa + da * da, ab + db * db))
                       (0, 0, 0) ms
          in ( ml, ma, mb
             , isqrtInt (vl `quot` n), isqrtInt (va `quot` n), isqrtInt (vb `quot` n)
             , n )

-- | Exact integer floor square root (binary search). @isqrtInt n = floor(√n)@
-- for @n ≥ 0@; 0 for @n ≤ 0@. Bit-for-bit reproducible in Zig (i64).
isqrtInt :: Int -> Int
isqrtInt n
  | n <= 0    = 0
  | otherwise = go 0 1048576   -- hi = 2^20 (mid³≤2^40 stays in i64; covers our vars)
  where
    go lo hi
      | lo >= hi  = lo
      | otherwise =
          let mid = (lo + hi + 1) `quot` 2
          in if mid * mid <= n then go mid hi else go lo (mid - 1)

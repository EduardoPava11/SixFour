{- |
Module      : SixFour.Spec.QuantFixed
Description : Deterministic FIXED-POINT (Q16) per-frame quantizer — the bit-exact
              source of truth for the Zig @s4_quantize_frame@.

The per-frame palette's objective is gamut COVERAGE / LAB diversity, not MSE
(see 'SixFour.Spec.Coverage', 'SixFour.Spec.Significance.lawSigMaximinVariety').
The diversity-optimal seeder is therefore **maximin / farthest-first traversal**
(Gonzalez 1985 — the k-center 2-approximation), the SAME rule
'SixFour.Spec.Significance.farthestPointSeeds' uses — ported here to exact Q16
integer distances. Lloyd refinement (which minimises within-cluster variance, i.e.
pulls toward density and AWAY from diversity) is offered as an OPTIONAL step
(@iters@; @0@ = pure maximin), with the StageA convention: @\@divTrunc@ means,
empty cluster keeps its old centroid. Nearest-centroid ties resolve to the lowest
index (strict @<@), as everywhere in the core.
-}
module SixFour.Spec.QuantFixed
  ( quantizeFrameQ16
  , farthestPointSeedsQ16
  , farthestPointSeedIndicesQ16
  , lloydStepQ16
  , nearestCentroidQ16
  , distSqQ16
  ) where

import           Data.List           (foldl')
import qualified Data.Vector         as V

type Px = (Int, Int, Int)

-- | Squared Q16 OKLab distance (i64).
distSqQ16 :: Px -> Px -> Int
distSqQ16 (l1, a1, b1) (l2, a2, b2) =
  let dl = l1 - l2; da = a1 - a2; db = b1 - b2 in dl * dl + da * da + db * db

-- | Nearest centroid index; strict @<@ ⇒ lowest index on ties (StageA.nearest).
nearestCentroidQ16 :: V.Vector Px -> Px -> Int
nearestCentroidQ16 cs x =
  fst $ V.foldl'
    (\acc@(_, bd) (i, c) -> let d = distSqQ16 x c in if d < bd then (i, d) else acc)
    (0, maxBound :: Int)
    (V.indexed cs)

-- | The maximin (farthest-first) seed order as INDICES into @pixels@ — the exact
-- chosen-index sequence. First index = the pixel farthest from the (integer) cloud
-- mean; each subsequent pick maximises the minimum distance to the chosen set.
-- Strict @>@ ⇒ lowest index on ties. When @k@ exceeds the distinct-colour count
-- the maximin distance hits 0 and indices repeat (deterministically). Exposed so
-- the global-collapse golden ('SixFour.Spec.Collapse') can pin the index sequence;
-- 'farthestPointSeedsQ16' is exactly @map (pv !) . farthestPointSeedIndicesQ16@.
farthestPointSeedIndicesQ16 :: Int -> [Px] -> [Int]
farthestPointSeedIndicesQ16 k pixels
  | k <= 0 || null pixels = []
  | otherwise =
      let pv = V.fromList pixels
          n  = V.length pv
          (sl, sa, sb) =
            V.foldl' (\(al, aa, ab) (l, a, b) -> (al + l, aa + a, ab + b)) (0, 0, 0) pv
          mean = (sl `quot` n, sa `quot` n, sb `quot` n)
          first = fst $ V.ifoldl'
                    (\(bi, bd) i c -> let d = distSqQ16 c mean in if d > bd then (i, d) else (bi, bd))
                    (0, -1) pv
          mind0 = V.map (\c -> distSqQ16 c (pv V.! first)) pv
          go chosen _    | length chosen >= k = reverse chosen
          go chosen mind =
            let nextI = fst $ V.ifoldl'
                          (\(bi, bd) i d -> if d > bd then (i, d) else (bi, bd))
                          (0, -1) mind
                c     = pv V.! nextI
                mind' = V.imap (\i d -> min d (distSqQ16 (pv V.! i) c)) mind
            in go (nextI : chosen) mind'
      in go [first] mind0

-- | @k@ maximin (farthest-first) seed colours over the pixel cloud, in Q16
-- (= the colours at 'farthestPointSeedIndicesQ16'). Ports
-- 'SixFour.Spec.Significance.farthestPointSeeds' to exact integers.
farthestPointSeedsQ16 :: Int -> [Px] -> [Px]
farthestPointSeedsQ16 k pixels =
  let pv = V.fromList pixels in map (pv V.!) (farthestPointSeedIndicesQ16 k pixels)

-- | One Lloyd step (Q16): assign nearest, replace each centroid by the integer
-- mean (@\@divTrunc@) of its members; an empty cluster keeps its old centroid.
-- Mirrors 'SixFour.Spec.StageA.lloydStep' (Double → Int).
lloydStepQ16 :: V.Vector Px -> V.Vector Px -> V.Vector Px
lloydStepQ16 pv cs =
  let nk = V.length cs
      assignment = V.map (nearestCentroidQ16 cs) pv
      acc :: V.Vector (Int, Int, Int, Int)
      acc = V.accumulate
              (\(aL, aA, aB, n) (l, a, b) -> (aL + l, aA + a, aB + b, n + 1))
              (V.replicate nk (0, 0, 0, 0))
              (V.zip assignment pv)
      avg (_, _, _, 0)   old = old
      avg (aL, aA, aB, n) _  = (aL `quot` n, aA `quot` n, aB `quot` n)
  in V.zipWith avg acc cs

-- | Quantize one frame → (@k@ centroids, length-@P@ assignment). Maximin seed,
-- @iters@ Lloyd refinements (0 = pure maximin), final nearest-centroid assignment.
quantizeFrameQ16 :: Int -> Int -> [Px] -> ([Px], [Int])
quantizeFrameQ16 k iters pixels
  | k <= 0       = ([], [])
  | null pixels  = (replicate k (0, 0, 0), [])
  | otherwise    =
      let pv        = V.fromList pixels
          seeds     = V.fromList (farthestPointSeedsQ16 k pixels)
          centroids = foldl' (\cs _ -> lloydStepQ16 pv cs) seeds [1 .. max 0 iters]
          assigns   = V.toList (V.map (nearestCentroidQ16 centroids) pv)
      in (V.toList centroids, assigns)

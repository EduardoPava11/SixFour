{- |
Module      : SixFour.Spec.SuccessiveRefinement
Description : The "surface one 16³, keep the remainder in the net" split — successive refinement (Equitz–Cover) over the octant ladder.

The information-theoretic frame for the reframed direction: the NN surfaces ONE
coarse cube (the SHOWN GIF) and HOLDS the finer detail as the remainder. This is a
successive-refinement code (Equitz–Cover 1991) realised by the octant ladder
("SixFour.Spec.OctreeCell"): 'split' collapses the @k@ finest octree levels into the
surfaced coarse cube and keeps their detail bands as the held remainder; 'refine'
replays the held detail to recover the full cube exactly.

Because the octant coarse value is a DETERMINISTIC POOL of its eight children, the
chain @X → fine → coarse@ is Markov — the Equitz–Cover no-rate-penalty condition —
so the split is refinable BY CONSTRUCTION ('lawMarkovByPooling'). 'remainderRate'
is the information BUDGET the net holds (the held detail-coefficient count); it is
exactly @total − surfaced@ dims ('lawRemainderRateIsHeld'), i.e. the conditional
@I(X; fine | coarse)@ skeleton (a rate budget, not a preference claim).

GHC-boot-only. Laws are exported predicates, QuickCheck'd in @Properties.SuccessiveRefinement@.
-}
module SixFour.Spec.SuccessiveRefinement
  ( -- * The surfaced / held split
    SurfacedSplit(..)
  , split
  , refine
  , remainderRate
    -- * Laws (QuickCheck'd in @Properties.SuccessiveRefinement@)
  , lawRefineRoundTrip
  , lawMarkovByPooling
  , lawRemainderRateIsHeld
  , lawFullSurfaceZeroRemainder
  ) where

import SixFour.Spec.OctreeCell   (Detail, octantDistill, octantSynthesize)
import SixFour.Spec.OctreeGenome (octreeLeafCount)

-- | A successive-refinement split: the surfaced coarse cube (the SHOWN @16³@) plus
-- the held detail bands (the net's latent remainder), finest-first.
data SurfacedSplit = SurfacedSplit
  { surfaced :: [Int]      -- ^ the coarse @8^(d-k)@ cube that is shown
  , held     :: [[Detail]] -- ^ the @k@ finest detail bands kept in the net
  } deriving (Eq, Show)

zero7 :: Detail
zero7 = (0,0,0,0,0,0,0)

-- | A cut of @k@ levels on a depth-@d@ cube is valid when @0 ≤ k ≤ d@ and the cube
-- is the right size.
validCut :: Int -> Int -> [Int] -> Bool
validCut k d cube = d >= 0 && k >= 0 && k <= d && length cube == octreeLeafCount d

-- | @split k d@: collapse the @k@ FINEST octree levels into the surfaced coarse
-- cube; hold their detail bands as the remainder.
split :: Int -> Int -> [Int] -> SurfacedSplit
split k d cube =
  let (c, dets)              = octantDistill d cube
      (heldDets, coarseDets) = splitAt k dets
      surf                   = octantSynthesize (c, coarseDets)
  in SurfacedSplit surf heldDets

-- | @refine d@: re-distill the surfaced cube and replay the held detail to recover
-- the full cube — the inverse of 'split'.
refine :: Int -> SurfacedSplit -> [Int]
refine _ (SurfacedSplit surf heldDets) =
  let depthOfSurfaced = surfacedDepth (length surf)
      (c, coarseDets) = octantDistill depthOfSurfaced surf
  in octantSynthesize (c, heldDets ++ coarseDets)
  where
    surfacedDepth n = length (takeWhile (< n) (map (8 ^) [0 :: Int ..]))

-- | The information budget the net holds: the held detail-coefficient count
-- (7 sub-bands per node).
remainderRate :: SurfacedSplit -> Int
remainderRate s = sum [ 7 * length b | b <- held s ]

-- | The SR code loses nothing: @refine . split = id@ (reuses the octant-ladder bijection).
lawRefineRoundTrip :: Int -> Int -> [Int] -> Bool
lawRefineRoundTrip k d cube =
  not (validCut k d cube) || refine d (split k d cube) == take (octreeLeafCount d) cube

-- | Markov-by-pooling (Equitz–Cover no-penalty): the surfaced depends ONLY on the
-- coarse, never on the held detail — zeroing the held bands then re-deriving the
-- surfaced yields the same surfaced. This is the refinable-by-construction guarantee.
lawMarkovByPooling :: Int -> Int -> [Int] -> Bool
lawMarkovByPooling k d cube =
  not (validCut k d cube) ||
    let s      = split k d cube
        zeroed = s { held = map (map (const zero7)) (held s) }
        cube0  = refine d zeroed
    in surfaced (split k d cube0) == surfaced s

-- | The held budget equals total dims minus surfaced dims (the @I(X;fine|coarse)@
-- skeleton, as a dimension count).
lawRemainderRateIsHeld :: Int -> Int -> [Int] -> Bool
lawRemainderRateIsHeld k d cube =
  not (validCut k d cube) ||
    let s = split k d cube
    in remainderRate s == octreeLeafCount d - length (surfaced s)

-- | Surfacing everything (cut 0) holds nothing.
lawFullSurfaceZeroRemainder :: Int -> [Int] -> Bool
lawFullSurfaceZeroRemainder d cube =
  not (d >= 0 && length cube == octreeLeafCount d) ||
    remainderRate (split 0 d cube) == 0

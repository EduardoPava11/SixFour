{- |
Module      : SixFour.Spec.TwoMoveOctave
Description : The two-move (GLOBAL coarse-octave then LOCAL fine-octave) @(a,b)@ chroma navigation: axis-aware @+/-1@ moves, the 12 ordered magnitude-2 paths over 8 endpoints, with one composed @d6@ as the per-two-move SIGNAL and the intermediate 16³ kept as the "mid funnel".

The user's next build step: let the user make TWO MOVES, GLOBAL then LOCAL, by @+/-1@ in
the @(a,b)@ chroma directions; each move re-projects a fresh 16³ and the @d6@ distance is
the SIGNAL that drives the GIF update.

OCTAVE (resolved): there are TWO orthogonal distances. The VALUE distance @d6@
("SixFour.Spec.RelationalResidual") is LINEAR (Q16 L1; a @+/-1@ nudge is distance 1 at every
level). The SCALE/LEVEL distance is OCTAVE (log2): one octree level = one octave
("SixFour.Spec.OctreeCell" @octreeDepth = log2 side@; a rung = @levelsPerStep == 2@ octaves).
So GLOBAL = a move organised at the COARSER octave, LOCAL = a move at the FINER octave; the
move VALUE-signal stays the proven linear @d6@ (deterministic, undo-by-history). The learned
octave SCALE @s_h@ lives in "SixFour.Spec.LargeJepaHead" (the attention bias), NOT here.

AXIS-AWARE (the load-bearing requirement): the move applies to the DISTINCT @DimA@/@DimB@
axes via @RelationalResidual.nudge@ (already per-axis), so @(+2,0)@ /= @(+1,+1)@ and a
diagonal's two orderings @+1a+1b@ vs @+1b+1a@ transit a DIFFERENT intermediate 16³ (the "mid
funnel") while landing on the SAME endpoint. (Contrast "SixFour.Spec.NudgeStep" @nudge@, a
scalar @(da+db)/65536@ shift that cannot distinguish either; left untouched, this is additive.)

The KEYSTONE 'lawDiagonalOrderingsDifferAtIntermediate' proves the global-then-local structure
carries signal a single magnitude-2 jump does not.

GHC-boot-only. Additive; re-pins nothing. Reuses @RelationalResidual@ (@P6@, @d6@, @nudge@),
@Dim6@, and delegates the octave fact to @OctreeCell@ / @SelfSimilarReconstruct@. Laws
QuickCheck'd in "Properties.TwoMoveOctave".
-}
module SixFour.Spec.TwoMoveOctave
  ( -- * Octave-tagged axis-aware moves
    Octave(..)
  , octaveDepth
  , AbMove(..)
  , applyMove
    -- * The two-move set + the signal + the mid funnel
  , twoMovePaths
  , twoMoveEndpoints
  , midFunnel
  , finalPoint
  , moveSignal
    -- * Laws (QuickCheck'd in @Properties.TwoMoveOctave@)
  , lawDiagonalOrderingsDifferAtIntermediate
  , lawGlobalIsCoarserOctave
  , lawValueDistanceIsLinear
  , lawScaleDistanceIsOctave
  , lawTwoMoveEndpointsAreEight
  , lawSignalIsComposedD6
  , lawMidFunnelIsOneGlobalStep
  ) where

import Data.List (nub)

import SixFour.Spec.Dim6 (Dim6(..))
import SixFour.Spec.RelationalResidual (P6(..), d6, nudge)
import SixFour.Spec.OctreeCell (octreeDepth, levelsBetween)
import SixFour.Spec.SelfSimilarReconstruct (levelsPerStep)

-- | Which octave a move is organised at: the GLOBAL move at the COARSER octave, the LOCAL
-- move at the FINER octave. (One octree level apart — the @64³@-pivot rung structure.)
data Octave = CoarseGlobal | FineLocal deriving (Eq, Show)

-- | The relative octree level (lower = coarser). @CoarseGlobal@ sits one octave BELOW
-- @FineLocal@; the unit is one octree level (one octave, @octreeDepth@).
octaveDepth :: Octave -> Int
octaveDepth CoarseGlobal = 0
octaveDepth FineLocal    = 1

-- | An axis-aware @+/-1@ chroma move: the search axis (@DimA@ or @DimB@), the @+/-1@ delta,
-- and the octave it is organised at.
data AbMove = AbMove
  { mvAxis   :: !Dim6      -- ^ @DimA@ or @DimB@ (the search-colour axis).
  , mvDelta  :: !Int       -- ^ @+1@ or @-1@ (the unit quantum).
  , mvOctave :: !Octave    -- ^ @CoarseGlobal@ (the GLOBAL step) or @FineLocal@ (the LOCAL step).
  } deriving (Eq, Show)

-- | Apply a move to the coordinate's 6D point — axis-aware (the gap "SixFour.Spec.NudgeStep"
-- has): a @DimA@ move and a @DimB@ move change DIFFERENT coordinates. Delegates
-- @RelationalResidual.nudge@.
applyMove :: AbMove -> P6 -> P6
applyMove (AbMove ax d _) = nudge ax d

-- | The 12 ordered GLOBAL-then-LOCAL magnitude-2 paths over the 8 endpoints: 4 axial (one
-- ordering: two same-axis steps) + 4 diagonal (two orderings each, because the global step
-- makes a distinct intermediate). The GLOBAL move is @CoarseGlobal@, the LOCAL is @FineLocal@.
twoMovePaths :: [(AbMove, AbMove)]
twoMovePaths =
  -- 4 axial (single ordering)
  [ (AbMove DimA d CoarseGlobal, AbMove DimA d FineLocal) | d <- [1, -1] ] ++
  [ (AbMove DimB d CoarseGlobal, AbMove DimB d FineLocal) | d <- [1, -1] ] ++
  -- 4 diagonals, each with BOTH orderings (global-a/local-b and global-b/local-a)
  [ p
  | da <- [1, -1], db <- [1, -1]
  , p  <- [ (AbMove DimA da CoarseGlobal, AbMove DimB db FineLocal)
          , (AbMove DimB db CoarseGlobal, AbMove DimA da FineLocal) ]
  ]

-- | The endpoint @(a,b)@ displacement of a two-move path (applied to the origin point).
endpointOf :: (AbMove, AbMove) -> (Int, Int)
endpointOf (g, l) =
  let p = applyMove l (applyMove g originP6)
  in (p6A p, p6B p)

originP6 :: P6
originP6 = P6 0 0 0 0 0 0

-- | The 8 distinct magnitude-2 endpoint displacements the two-move set reaches.
twoMoveEndpoints :: [(Int, Int)]
twoMoveEndpoints = nub (map endpointOf twoMovePaths)

-- | The "MID FUNNEL": the intermediate point AFTER the global step (before the local). This
-- is the waypoint the user keeps known; the local move is taken relative to it.
midFunnel :: (AbMove, AbMove) -> P6 -> P6
midFunnel (g, _) = applyMove g

-- | The final point after both moves.
finalPoint :: (AbMove, AbMove) -> P6 -> P6
finalPoint (g, l) p = applyMove l (applyMove g p)

-- | THE per-two-move SIGNAL: one composed @d6@ between the start and the final 16³-coordinate
-- (the net signal that drives the GIF update). Linear, integer, Zig-floor, octave-invariant.
moveSignal :: (AbMove, AbMove) -> P6 -> Int
moveSignal path p = d6 p (finalPoint path p)

-- ============================================================================
-- Laws (predicates; QuickCheck'd in Properties.TwoMoveOctave)
-- ============================================================================

-- | KEYSTONE: a diagonal's two orderings (global @+1a@/local @+1b@ vs global @+1b@/local
-- @+1a@) transit a DIFFERENT intermediate 16³ (the mid funnel) yet land on the SAME endpoint.
-- So the global-then-local structure carries signal a single magnitude-2 jump does not. Teeth:
-- a scalar (axis-blind) move would collapse the two intermediates and fail the first conjunct.
lawDiagonalOrderingsDifferAtIntermediate :: P6 -> Bool
lawDiagonalOrderingsDifferAtIntermediate p =
  let ab = (AbMove DimA 1 CoarseGlobal, AbMove DimB 1 FineLocal)  -- global +1a, local +1b
      ba = (AbMove DimB 1 CoarseGlobal, AbMove DimA 1 FineLocal)  -- global +1b, local +1a
  in midFunnel ab p /= midFunnel ba p          -- DIFFERENT mid funnel (axis-aware)
     && finalPoint ab p == finalPoint ba p      -- SAME endpoint (addition commutes)
     && d6 p (midFunnel ab p) == 1              -- each global step is a unit move
     && d6 p (midFunnel ba p) == 1

-- | In every two-move path the GLOBAL step is at the COARSER octave and the LOCAL step at the
-- FINER octave (one octave apart). Teeth: a path with global=fine or both-same-octave fails.
lawGlobalIsCoarserOctave :: Bool
lawGlobalIsCoarserOctave =
  all (\(g, l) -> mvOctave g == CoarseGlobal
               && mvOctave l == FineLocal
               && octaveDepth (mvOctave g) < octaveDepth (mvOctave l)) twoMovePaths

-- | The VALUE distance is LINEAR: a @+/-1@ move on either search axis is @d6 == 1@, the same
-- at every octave (it does NOT auto-scale by level). Delegates @RelationalResidual@. Teeth: an
-- octave-scaled value metric (@d6@ of a unit step @/= 1@) fails.
lawValueDistanceIsLinear :: P6 -> Bool
lawValueDistanceIsLinear p =
     d6 p (applyMove (AbMove DimA 1 CoarseGlobal) p) == 1
  && d6 p (applyMove (AbMove DimB 1 FineLocal)    p) == 1
  && d6 p (applyMove (AbMove DimA 1 FineLocal)    p) == 1   -- same unit at the finer octave

-- | The SCALE distance is OCTAVE (log2), distinct from the linear value metric: the octree
-- level difference is the octave count (@levelsBetween 64 16 == 2 == levelsPerStep@), and one
-- level = one @octreeDepth@ step (a global/local pair is exactly one octave apart). Delegates
-- @OctreeCell@ / @SelfSimilarReconstruct@.
lawScaleDistanceIsOctave :: Bool
lawScaleDistanceIsOctave =
     levelsBetween 64 16 == 2
  && levelsBetween 256 64 == 2
  && levelsPerStep == 2
  && octreeDepth 64 - octreeDepth 32 == 1                    -- one octave = one level
  && octaveDepth FineLocal - octaveDepth CoarseGlobal == 1   -- the global/local pair = one octave

-- | The two-move set reaches exactly 8 distinct magnitude-2 endpoints (@d6 == 2@ from the
-- origin): the 4 axial @(+-2,0),(0,+-2)@ and the 4 diagonal @(+-1,+-1)@. Teeth: a set that
-- conflated @(+2,0)@ with @(+1,+1)@ (axis-blind) would have fewer than 8.
lawTwoMoveEndpointsAreEight :: Bool
lawTwoMoveEndpointsAreEight =
     length twoMoveEndpoints == 8
  && all (\(da, db) -> abs da + abs db == 2) twoMoveEndpoints

-- | The reported SIGNAL is one composed @d6@ between the start and the final coordinate.
-- Teeth: any other readout (e.g. summing the two step distances, which over-counts a
-- back-and-forth) fails against the net @d6@.
lawSignalIsComposedD6 :: P6 -> Bool
lawSignalIsComposedD6 p =
  all (\path -> moveSignal path p == d6 p (finalPoint path p)) twoMovePaths

-- | The mid funnel is exactly one GLOBAL step from the start (@d6 == 1@): the waypoint the
-- user keeps known is a single unit move away, and the local move proceeds from it. Teeth: a
-- mid funnel that jumped two steps fails.
lawMidFunnelIsOneGlobalStep :: P6 -> Bool
lawMidFunnelIsOneGlobalStep p =
  all (\path -> d6 p (midFunnel path p) == 1) twoMovePaths

{- |
Module      : SixFour.Spec.TwoMoveOctave
Description : The two-move (GLOBAL coarse-octave then LOCAL fine-octave) @(a,b)@ chroma navigation: axis-aware @+/-1@ moves, the 12 ordered magnitude-2 paths over 8 endpoints, the composed @d6@ MOVE COST (a constant 2), and the intermediate 16³ kept as the "mid funnel". DOMAIN-respecting (refuses past @+/-B@).

The user's next build step: let the user make TWO MOVES, GLOBAL then LOCAL, by @+/-1@ in
the @(a,b)@ chroma directions; each move re-projects a fresh 16³. The composed @d6@ is the
move's abstract lattice COST (a constant @== 2@, 'moveMagnitude'), NOT a content signal:
a uniform-translation move is content-blind, so the CONTENT-RESPONSIVE signal (how much the
rendered 16³ actually changes) is a separate NEXT step that couples the move to the
content-conditioned octant detail bands. This module pins the move ALGEBRA + INVARIANTS
(geodesic, reversible, commuting, domain-respecting), the substrate the signal rides on.

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
-- COMPARTMENT: SWIFT-COREAI | tag:DisplaySide
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
  , moveMagnitude
  , inverseMove
  , safeApplyMove
    -- * Laws (QuickCheck'd in @Properties.TwoMoveOctave@)
  , lawDiagonalOrderingsDifferAtIntermediate
  , lawGlobalIsCoarserOctave
  , lawValueDistanceIsLinear
  , lawScaleDistanceIsOctave
  , lawTwoMoveEndpointsAreEight
  , lawMoveCostIsTwo
  , lawMoveMagnitudeIsConstant
  , lawMidFunnelIsOneGlobalStep
  , lawTwoMoveIsGeodesic
  , lawEveryPathIsMagnitudeTwo
  , lawMoveIsReversible
  , lawMovesCommute
  , lawTwoMoveRespectsDomain
  ) where

import Data.List (nub)

import SixFour.Spec.Dim6 (Dim6(..))
import SixFour.Spec.RelationalResidual (P6(..), nudge, safeNudge, p6Coords)
import SixFour.Spec.RelationalMemory (d6)
import SixFour.Spec.SubstrateDomain (inDomain)
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

-- | The abstract MOVE MAGNITUDE: the composed @d6@ between the start and the final
-- coordinate. This is a CONSTANT @== 2@ for every magnitude-2 path (two unit axis steps add
-- in L1), so it is the move's lattice COST, NOT a content signal. The CONTENT-RESPONSIVE
-- signal (how much the rendered 16³ actually changes, which depends on local texture) is the
-- NEXT build step and requires coupling the move to the content-conditioned octant detail
-- bands ("SixFour.Spec.MaskedBandPrediction"): a uniform-translation move is content-blind, so
-- no @d6@-on-the-coordinate (nor a uniform-nudge render readout) can vary with the picture.
-- (Renamed from @moveSignal@; the old "drives the GIF update" claim was false — it is a
-- constant, proven by 'lawMoveMagnitudeIsConstant'.)
moveMagnitude :: (AbMove, AbMove) -> P6 -> Int
moveMagnitude path p = d6 p (finalPoint path p)

-- | The inverse of a move: same axis and octave, NEGATED delta. Undo-by-history applies the
-- inverse (the move group has inverses).
inverseMove :: AbMove -> AbMove
inverseMove (AbMove ax d oct) = AbMove ax (negate d) oct

-- | A DOMAIN-RESPECTING apply: @Just@ the moved point iff it stays in the substrate domain,
-- @Nothing@ (the @RC_OUT_OF_RANGE@ sibling) otherwise. Routes through
-- "SixFour.Spec.RelationalResidual" 'safeNudge' so the navigation cannot emit a P6 the shipped
-- Zig kernel refuses. (Raw 'applyMove' stays for the in-domain laws.)
safeApplyMove :: AbMove -> P6 -> Maybe P6
safeApplyMove (AbMove ax d _) = safeNudge ax d

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

-- | The move COST is the composed @d6@ between start and final (was @lawSignalIsComposedD6@;
-- the cost is a lattice fact, NOT a content signal). Teeth: a readout that summed step
-- distances (over-counting a back-and-forth) fails against the net @d6@.
lawMoveCostIsTwo :: P6 -> Bool
lawMoveCostIsTwo p =
  all (\path -> moveMagnitude path p == d6 p (finalPoint path p)) twoMovePaths

-- | HONESTY: 'moveMagnitude' is a CONSTANT @== 2@ for EVERY path at EVERY start — it is the
-- move's abstract lattice cost, blind to the picture. This law exists to STOP the canon
-- calling it "the signal that drives the GIF update": the content-responsive signal is a
-- separate (next-step) object on the rendered 16³, not this constant. Teeth: a claim that
-- @moveMagnitude@ varies (the old "signal" reading) fails.
lawMoveMagnitudeIsConstant :: P6 -> Bool
lawMoveMagnitudeIsConstant p =
  all (\path -> moveMagnitude path p == 2) twoMovePaths

-- | The mid funnel is exactly one GLOBAL step from the start (@d6 == 1@): the waypoint the
-- user keeps known is a single unit move away, and the local move proceeds from it. Teeth: a
-- mid funnel that jumped two steps fails.
lawMidFunnelIsOneGlobalStep :: P6 -> Bool
lawMidFunnelIsOneGlobalStep p =
  all (\path -> d6 p (midFunnel path p) == 1) twoMovePaths

-- | GEODESIC: every two-move's legs ADD with NO cancellation —
-- @d6(start,mid) + d6(mid,final) == d6(start,final)@, with each leg exactly 1. So the mid
-- funnel lies ON the shortest path and the move set contains no canceling pair (e.g. a
-- @(+1a,-1a)@ would give legs @1+1@ but net @0@ and fail). Teeth: a canceling or off-geodesic
-- path fails.
lawTwoMoveIsGeodesic :: P6 -> Bool
lawTwoMoveIsGeodesic p =
  all (\path ->
        let leg1 = d6 p (midFunnel path p)
            leg2 = d6 (midFunnel path p) (finalPoint path p)
        in leg1 == 1 && leg2 == 1 && leg1 + leg2 == d6 p (finalPoint path p)) twoMovePaths

-- | SOUNDNESS: every path in the set is magnitude 2 (no magnitude-1 or canceling path leaked
-- in). Teeth: injecting a @(+1a,-1a)@ (net 0) or a single-step path flips this False.
lawEveryPathIsMagnitudeTwo :: P6 -> Bool
lawEveryPathIsMagnitudeTwo p = all (\path -> moveMagnitude path p == 2) twoMovePaths

-- | REVERSIBILITY (undo-by-history is well-formed): applying a move's 'inverseMove' restores
-- the start, AND the inverse keeps the axis + octave and only flips the delta (an
-- octave-changing "inverse" would still round-trip the coordinate, so the structural conjuncts
-- are load-bearing). Teeth: a malformed inverse fails the structural conjuncts.
lawMoveIsReversible :: Dim6 -> Int -> Octave -> P6 -> Bool
lawMoveIsReversible ax d oct p =
  let m  = AbMove ax d oct
      im = inverseMove m
  in applyMove im (applyMove m p) == p          -- round-trips
     && mvAxis im == mvAxis m                    -- same axis
     && mvOctave im == mvOctave m                -- same octave
     && mvDelta im == negate (mvDelta m)         -- delta flipped

-- | The single moves COMMUTE (the abelian backbone the keystone's "same endpoint" leans on):
-- two integer axis-adds in either order land identically. Teeth: an order-dependent
-- (gamut-clamping) move fails.
lawMovesCommute :: Dim6 -> Int -> Dim6 -> Int -> P6 -> Bool
lawMovesCommute ax1 d1 ax2 d2 p =
  applyMove (AbMove ax1 d1 CoarseGlobal) (applyMove (AbMove ax2 d2 FineLocal) p)
  == applyMove (AbMove ax2 d2 FineLocal) (applyMove (AbMove ax1 d1 CoarseGlobal) p)

-- | DOMAIN: a two-move taken near the substrate edge REFUSES (via 'safeApplyMove') exactly
-- when a step would leave the domain @|v| <= B@, matching the shipped Zig kernel. Teeth: the
-- raw 'applyMove' would silently emit an out-of-domain point where the law demands @Nothing@.
-- (Non-vacuous only at the edge — QuickCheck'd with @genP6Edge@.)
lawTwoMoveRespectsDomain :: P6 -> Bool
lawTwoMoveRespectsDomain p =
  all (\(g, l) ->
        case safeApplyMove g p of
          Nothing  -> True                                   -- global step refused: fine
          Just mid -> case safeApplyMove l mid of
                        Nothing  -> True                      -- local step refused: fine
                        Just fin -> all inDomain (p6Coords fin)  -- both accepted => in-domain
      ) twoMovePaths

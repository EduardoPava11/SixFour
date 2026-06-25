-- COMPARTMENT: MLX-MODEL | tag:MacTag
{- |
Module      : SixFour.Spec.DeltaGesture
Description : Binds a UI drag to the two delta carriers so their ALGEBRA is the hand-feel: stacking colour drags ADDS (the abelian ℤ-module), chaining index drags COMPOSES (the transport group, order-sensitive). The spec contract under the design language's "SwatchVector vs TransportRibbon" two-verb grammar.

The L,a,b nudge design language gives the user two movable deltas with two DIFFERENT hand-feels,
and the difference is exactly the math: a 'SixFour.Spec.HierarchicalDelta' @ColourDelta@ is an
abelian ℤ-module (recolours ADD, commutatively) while an @IndexDelta@ is a transport group (motions
COMPOSE, order matters, never add). This module pins that binding so the UI's "stack" and "chain"
verbs are provably the carriers' @<>@:

  * 'stackColourDrags' \/ 'chainIndexDrags' — the two drag-combine verbs (both are @<>@ on their
    carrier, but the laws prove they behave like ADD vs COMPOSE).
  * 'lawColourDragAdds' — stacking two colour drags equals applying their sum (the ℤ-module add).
  * 'lawColourDragCommutes' — colour drags STACK order-free (abelian) — why the SwatchVector feels
    like a rubber band.
  * 'lawIndexDragComposes' — chaining two index drags equals applying them in sequence (the monoid
    action / transport composition).
  * 'lawIndexDragOrderMatters' — index drags do NOT commute (5↦7 then 7↦2 ≠ the other order) — why
    the TransportRibbon feels like routing a wire, and why it has no "stack" verb.

Additive: imports "SixFour.Spec.HierarchicalDelta" (today imported by little) and
"SixFour.Spec.ConstructionEncoder". Re-pins nothing. GHC-boot-only. Laws QuickCheck'd in
"Properties.DeltaGesture".
-}
module SixFour.Spec.DeltaGesture
  ( stackColourDrags
  , chainIndexDrags
    -- * Laws (QuickCheck'd in @Properties.DeltaGesture@)
  , lawColourDragAdds
  , lawColourDragCommutes
  , lawIndexDragComposes
  , lawIndexDragOrderMatters
  ) where

import SixFour.Spec.ConstructionEncoder (Construction(..), QColour)
import SixFour.Spec.HierarchicalDelta
  ( ColourDelta(..), IndexDelta, applyValueDelta, applyDelta, deltaBetween )

-- | STACK two colour drags — the additive combine (drops fuse tip-to-tail). It is @<>@ on the
-- abelian 'ColourDelta', but 'lawColourDragAdds' \/ 'lawColourDragCommutes' prove it is genuine
-- commutative addition.
stackColourDrags :: ColourDelta -> ColourDelta -> ColourDelta
stackColourDrags = (<>)

-- | CHAIN two index drags — the transport combine (drops snap end-to-start). It is @<>@ on the
-- 'IndexDelta' transport group; 'lawIndexDragComposes' \/ 'lawIndexDragOrderMatters' prove it is
-- order-sensitive composition, NOT addition.
chainIndexDrags :: IndexDelta -> IndexDelta -> IndexDelta
chainIndexDrags = (<>)

-- ============================================================================
-- Laws (predicates; QuickCheck'd in Properties.DeltaGesture)
-- ============================================================================

-- | STACKING two colour drags equals applying their SUM: a SwatchVector dropped on another is the
-- ℤ-module add of the two displacements. Compared on the resulting palette (the only field a value
-- delta touches). Teeth: a "stack" that overwrote instead of adding (or truncated the ragged tail)
-- would disagree.
lawColourDragAdds :: [QColour] -> [QColour] -> [QColour] -> Bool
lawColourDragAdds pal d1 d2 =
  let c   = Construction 0 pal [0]
      cd1 = ColourDelta d1
      cd2 = ColourDelta d2
  in cPalette (applyValueDelta cd2 (applyValueDelta cd1 c))
       == cPalette (applyValueDelta (stackColourDrags cd1 cd2) c)

-- | Colour drags STACK order-free (the carrier is abelian): @d1 <> d2 == d2 <> d1@. This is why the
-- SwatchVector can be dropped in any order and feels elastic, not path-dependent. Teeth: a
-- non-commutative combine fails on any two differing drags.
lawColourDragCommutes :: [QColour] -> [QColour] -> Bool
lawColourDragCommutes d1 d2 =
  stackColourDrags (ColourDelta d1) (ColourDelta d2)
    == stackColourDrags (ColourDelta d2) (ColourDelta d1)

-- | CHAINING two index drags equals applying them in sequence (the monoid action): drag @b@ then
-- @a@ on the Morton map equals @applyDelta (a <> b)@. Teeth: a "chain" that unioned without chaining
-- provenance would apply the right slots but break composition downstream.
lawIndexDragComposes :: [Int] -> [Int] -> [Int] -> Bool
lawIndexDragComposes base mid top =
  let n  = minimum [length base, length mid, length top]
      b  = take n base
      d1 = deltaBetween b (take n mid)
      d2 = deltaBetween (take n mid) (take n top)
  in applyDelta (chainIndexDrags d2 d1) b == applyDelta d2 (applyDelta d1 b)

-- | Index drags do NOT commute (the transport group is non-abelian): on one voxel, @5↦7@ then @7↦2@
-- composes to @5↦2@, while the opposite order is @1↦1@ — different transports. This is WHY the
-- TransportRibbon feels directional and has no commutative "stack" verb. Closed witness.
lawIndexDragOrderMatters :: Bool
lawIndexDragOrderMatters =
  let da = deltaBetween [0] [1]    -- voxel 0: 0 -> 1
      db = deltaBetween [1] [2]    -- voxel 0: 1 -> 2
  in chainIndexDrags db da /= chainIndexDrags da db

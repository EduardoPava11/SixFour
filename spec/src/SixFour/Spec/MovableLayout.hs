{- |
Module      : SixFour.Spec.MovableLayout
Description : Movable color widgets — the closed alphabet + the proven move operator.

A __ColorWidget__ is a widget whose cells are a __projection of the ONE color cube__
(the 64³ index cube + palette). __Movability is a property of being a ColorWidget__,
not a runtime flag: chrome (the build stamp, gear, action row, the heartbeat checker
ground, the determinism badge) is simply NOT in the 'ColorIdentity' type, so it has no
placement state and is __immovable by construction__ ('lawClassExhaustive').

There are exactly THREE color identities — the closed, movable set:

  * 'Field64'       — 64×64 cells (256 pt). The preview (live, quantized) ≡ the
                      gif-render (review): ONE identity, ONE shared position.
  * 'Palette16'     — 16×16 cells (64 pt). The 256-colour palette ≡ the capture shutter.
  * 'DiversityRing' — 20×20 cells (80 pt). The per-frame diversity gauge (re-introduced).

== Reuse, not reinvention

This module does NOT reinvent geometry. The footprint/default/interactivity/id/priority
of each identity are sourced from "SixFour.Spec.Lattice" (never free literals); a
'Placement' is turned into a "SixFour.Spec.GridLayout" 'LRegion'/'Scene', and 'move'
is closed over 'lawSceneDisjoint' (the SAME disjoint algebra 'captureScene' is proven
with). The Swift mirror ('MoveContract') reuses @GridLayoutContract.isDisjoint@ — Swift
adds no geometry authority.

== The one-shared-layout model

The WHOLE movable state is ONE 'Placement' = @Map ColorIdentity (col,row)@: three
positions, global and phase-independent. There is no per-phase position — each phase's Π
reads the SAME three entries, so 'Field64'\'s single position serves preview, gif-render,
AND review.

== The move operator (the proof)

'move' (1) clamps the candidate so the footprint stays in-bounds (clamp-first = slide
along the edge), (2) ACCEPTS iff the induced 'Scene' is disjoint, (3) else returns the
input 'Placement' unchanged (exact snap-back). It is total; an accepted move is always
BOTH in-bounds AND disjoint. The eight laws below are golden-pinned in
"Properties.MovableLayout" and the operator is cross-language bit-pinned via
'goldenAfter' (re-folded by the generated Swift @move@ in @Surface.assertSpecParity@).

GHC-boot-only: base, containers, plus "SixFour.Spec.GridLayout" / ".Lattice".
-}
module SixFour.Spec.MovableLayout
  ( -- * The closed color-identity alphabet (the ONLY movable widgets)
    ColorIdentity(..)
  , allIdentities
    -- * The ColorWidget typeclass + instance (all sourced from Spec.Lattice)
  , ColorWidget(..)
    -- * The one-shared-layout model
  , Placement
  , defaultPlacement
  , placedRegion
  , placementScene
    -- * The move algebra
  , snapToAtom
  , clampInBounds
  , move
    -- * The golden cross-language trace
  , GoldenStep
  , goldenScript
  , goldenAfter
    -- * Laws (predicates; QuickCheck'd / golden'd in Properties.MovableLayout)
  , lawClassExhaustive
  , lawMovePreservesDisjoint
  , lawMoveInBounds
  , lawSnapIdempotent
  , lawMoveAtomAligned
  , lawDefaultsDisjoint
  , lawRejectIsIdentity
  , lawMoveOnlyTouchesTarget
  ) where

import           Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map

import SixFour.Spec.GridLayout
  ( LRegion(..), Scene
  , regionCells, regionsOverlap
  , lawSceneDisjoint, lawSceneInBounds, lawInteractiveTouchFloor
  , lawSafeAreaClearance, lawPriorityDistinct, lawDisjointMatchesRects )
import SixFour.Spec.Lattice
  ( cols, rows, gifPx, touchFloorCells
  , previewCells, shutterCells, ringCells )

-- The closed alphabet -------------------------------------------------------

-- | The closed alphabet of color identities — the ONLY movable widgets. Chrome is
-- not in this type, so chrome is immovable BY CONSTRUCTION ('lawClassExhaustive').
data ColorIdentity = Field64 | Palette16 | DiversityRing
  deriving (Eq, Ord, Enum, Bounded, Show)

-- | Every identity, the universe @[minBound .. maxBound]@.
allIdentities :: [ColorIdentity]
allIdentities = [minBound .. maxBound]

-- The thin typeclass --------------------------------------------------------

-- | A ColorWidget IS a projection of the one cube with a fixed cell footprint. Every
-- member supplies its footprint, default dock, interactivity, owner id, and priority —
-- all sourced from "SixFour.Spec.Lattice", never free literals. The class is THIN: it
-- supplies only classification; the move algebra is one total operator over all members.
class ColorWidget w where
  cwFootprint   :: w -> (Int, Int)   -- ^ (side, side) in cells.
  cwDefaultCol  :: w -> Int          -- ^ default dock column (atoms).
  cwDefaultRow  :: w -> Int          -- ^ default dock row (atoms).
  cwInteractive :: w -> Bool         -- ^ touch target? (must clear the floor).
  cwWidgetId    :: w -> Int          -- ^ owner id (distinct per widget).
  cwPriority    :: w -> Int          -- ^ deterministic contest tiebreak (distinct).

instance ColorWidget ColorIdentity where
  cwFootprint   Field64       = (previewCells, previewCells)   -- (64,64)
  cwFootprint   Palette16     = (shutterCells, shutterCells)   -- (16,16)
  cwFootprint   DiversityRing = (ringCells,    ringCells)      -- (20,20)
  cwDefaultCol  Field64       = 18   -- == GridLayout preview dock
  cwDefaultCol  Palette16     = 42   -- == GridLayout palette dock
  cwDefaultCol  DiversityRing = 40   -- thumb band, disjoint from preview+palette
  cwDefaultRow  Field64       = 22
  cwDefaultRow  Palette16     = 145
  cwDefaultRow  DiversityRing = 170  -- 170·4=680 ≥ 62 top; (170+20)·4=760 ≤ 840 bottom
  cwInteractive Palette16     = True
  cwInteractive _             = False
  cwWidgetId                  = fromEnum
  cwPriority                  = fromEnum

-- The one-shared-layout model -----------------------------------------------

-- | The WHOLE movable state: three positions, global, phase-independent.
type Placement = Map ColorIdentity (Int, Int)   -- identity -> (col,row) in atoms

-- | The shipped seed: every identity at its 'cwDefaultCol' / 'cwDefaultRow' dock.
-- 'lawDefaultsDisjoint' proves this seed re-passes every "SixFour.Spec.GridLayout" law.
defaultPlacement :: Placement
defaultPlacement = Map.fromList
  [ (i, (cwDefaultCol i, cwDefaultRow i)) | i <- allIdentities ]

-- | Turn one placement entry into a "SixFour.Spec.GridLayout" 'LRegion' (REUSE: the
-- proven struct, not a new rectangle type).
placedRegion :: ColorIdentity -> (Int, Int) -> LRegion
placedRegion i (c, r) =
  let (w, h) = cwFootprint i
  in LRegion { lrCol = c, lrRow = r, lrW = w, lrH = h
             , lrWidget = cwWidgetId i, lrPriority = cwPriority i
             , lrInteractive = cwInteractive i }

-- | The 'Scene' a placement induces — fed straight into "SixFour.Spec.GridLayout"\'s
-- disjoint algebra. (@Map.toList@ keys it deterministically by 'ColorIdentity' 'Ord'.)
placementScene :: Placement -> Scene
placementScene p =
  [ (show i, placedRegion i pos) | (i, pos) <- Map.toList p ]

-- The move algebra ----------------------------------------------------------

-- | Snap a signed atom-count delta to whole atoms (truncate toward origin). Idempotent
-- on multiples of @atom@ ('lawSnapIdempotent'); pins crisp, sub-atom-free placement
-- ('lawMoveAtomAligned'). The Swift mirror calls the generated @snapToAtom@ so no
-- hand-rolled rounding can drift.
snapToAtom :: Int -> Int -> Int
snapToAtom atom px = (px `quot` atom) * atom

-- | Clamp a placement so the WHOLE footprint stays inside the @cols × rows@ lattice
-- (slide along the edge rather than reject). Runs BEFORE the disjoint test, so an
-- accepted move is in-bounds AND a rejected move returns an already-in-bounds @p@.
clampInBounds :: ColorIdentity -> (Int, Int) -> (Int, Int)
clampInBounds i (c, r) =
  let (w, h) = cwFootprint i
  in ( max 0 (min c (cols - w)), max 0 (min r (rows - h)) )

-- | THE MOVE OPERATOR. Move identity @i@ by a CELL delta @(dc,dr)@:
--
--   1. clamp the result so the footprint is fully in-bounds (clamp-first);
--   2. ACCEPT iff the resulting 'Scene' is disjoint (reuse 'lawSceneDisjoint');
--   3. else SNAP BACK (return the input 'Placement' unchanged).
--
-- Total; the in-bounds clamp happens BEFORE the disjoint test, so an accepted move is
-- always BOTH in-bounds AND disjoint, and a rejected move returns the prior (already
-- valid) placement verbatim ('lawRejectIsIdentity').
move :: Placement -> ColorIdentity -> (Int, Int) -> Placement
move p i (dc, dr) =
  case Map.lookup i p of
    Nothing        -> p
    Just (c0, r0)  ->
      let cand = clampInBounds i (c0 + dc, r0 + dr)
          p'   = Map.insert i cand p
      in if lawSceneDisjoint (placementScene p') then p' else p

-- The golden cross-language trace -------------------------------------------

-- | One step of the golden move script: which identity, and the cell delta.
type GoldenStep = (ColorIdentity, (Int, Int))

-- | A fixed script folded by 'move' from 'defaultPlacement'. Exercises an ACCEPT, a
-- REJECT→snap-back (driving 'Palette16' onto 'Field64'), and a clamped accept:
--
--   1. @DiversityRing +(10,0)@  — accept (slides right, no collision).
--   2. @Palette16     +(-24,-123)@ — would land Palette16 (16²) on Field64
--      (col 18 row 22); rejected, snaps back ('lawRejectIsIdentity' witness).
--   3. @Field64       +(20,0)@   — clamp-along-edge: 18+20=38 but @cols-64 = 36@,
--      so it clamps to 36 (accept), proving 'lawMoveInBounds' + 'lawMoveAtomAligned'.
goldenScript :: [GoldenStep]
goldenScript =
  [ (DiversityRing, ( 10,    0))
  , (Palette16,     (-24, -123))
  , (Field64,       ( 20,    0))
  ]

-- | The 'Placement' after folding 'move' over 'goldenScript' from 'defaultPlacement'.
-- Emitted to Swift as @MoveContract.goldenAfter@ and re-folded by the generated Swift
-- @move@ in @Surface.assertSpecParity@ (DEBUG) — the cross-language bit-pin.
goldenAfter :: Placement
goldenAfter = foldl (\p (i, d) -> move p i d) defaultPlacement goldenScript

-- Laws ----------------------------------------------------------------------

-- | Every 'ColorIdentity' in @[minBound..maxBound]@ has an in-bounds default footprint
-- and (if interactive) clears the 11-cell touch floor; the three defaults form a
-- disjoint 'placementScene'. Pins "movability = being a ColorWidget" (chrome, absent
-- from the type, has no placement and so is immovable by construction).
lawClassExhaustive :: Bool
lawClassExhaustive =
     all defaultInBounds allIdentities
  && all touchFloorOK    allIdentities
  && lawSceneDisjoint (placementScene defaultPlacement)
  where
    defaultInBounds i =
      let (w, h) = cwFootprint i
          c      = cwDefaultCol i
          r      = cwDefaultRow i
      in c >= 0 && c + w <= cols && r >= 0 && r + h <= rows
    touchFloorOK i
      | cwInteractive i = let (w, h) = cwFootprint i
                          in w >= touchFloorCells && h >= touchFloorCells
      | otherwise       = True

-- | KEYSTONE — disjoint-preservation: @∀ p i d.@ a disjoint placement stays disjoint
-- under 'move'. Accept keeps it disjoint by the guard; reject returns @p@ unchanged.
lawMovePreservesDisjoint :: Placement -> ColorIdentity -> (Int, Int) -> Bool
lawMovePreservesDisjoint p i d =
  lawSceneDisjoint (placementScene p)
    `implies` lawSceneDisjoint (placementScene (move p i d))
  where implies a b = not a || b

-- | Every region of @move p i d@ is fully inside the @cols × rows@ lattice (clamp runs
-- before the accept test; reject returns the already-in-bounds @p@). Stated requiring
-- the input already in-bounds (the invariant 'defaultPlacement' seeds and every accept
-- preserves).
lawMoveInBounds :: Placement -> ColorIdentity -> (Int, Int) -> Bool
lawMoveInBounds p i d =
  lawSceneInBounds (placementScene p)
    `implies` lawSceneInBounds (placementScene (move p i d))
  where implies a b = not a || b

-- | 'snapToAtom' and 'clampInBounds' are both idempotent:
-- @snapToAtom a (snapToAtom a px) == snapToAtom a px@ (for @a > 0@), and
-- @clampInBounds i . clampInBounds i == clampInBounds i@.
lawSnapIdempotent :: Int -> Int -> ColorIdentity -> Int -> Int -> Bool
lawSnapIdempotent atom px i c r =
     (atom <= 0 || snapToAtom atom (snapToAtom atom px) == snapToAtom atom px)
  && (clampInBounds i (clampInBounds i (c, r)) == clampInBounds i (c, r))

-- | The result col/row of any move is an exact integer atom (no sub-atom drift) ⇒ crisp
-- cell rendering. Every position in @move p i d@ equals @snapToAtom 1@ of itself (i.e.
-- it is already a whole atom — the lattice unit is 1 cell), and the placed region's
-- pt origin is a whole multiple of 'gifPx'.
lawMoveAtomAligned :: Placement -> ColorIdentity -> (Int, Int) -> Bool
lawMoveAtomAligned p i d =
  all aligned (Map.toList (move p i d))
  where
    aligned (_, (c, r)) =
         snapToAtom 1 c == c && snapToAtom 1 r == r        -- whole atoms (1-cell lattice)
      && (c * gifPx) `mod` gifPx == 0                       -- pt origin is a whole atom
      && (r * gifPx) `mod` gifPx == 0

-- | 'placementScene' 'defaultPlacement' re-passes ALL the existing
-- "SixFour.Spec.GridLayout" laws (disjoint, in-bounds, interactive touch-floor, safe
-- area, distinct priorities, the AABB bridge). Proves the new 3-widget seed ships valid
-- and that 'DiversityRing'\'s dock does not collide.
lawDefaultsDisjoint :: Bool
lawDefaultsDisjoint =
     lawSceneDisjoint          s
  && lawSceneInBounds          s
  && lawInteractiveTouchFloor  s
  && lawSafeAreaClearance      s
  && lawPriorityDistinct       s
  && lawDisjointMatchesRects   s
  where s = placementScene defaultPlacement

-- | A contested clamped move returns the LITERAL prior 'Placement' (@move p i d == p@);
-- snap-back is exact, never a partial move. Golden-pinned with a witness delta driving
-- 'Palette16' onto 'Field64'.
lawRejectIsIdentity :: Placement -> ColorIdentity -> (Int, Int) -> Bool
lawRejectIsIdentity p i d =
  let p' = move p i d
  in p' == p || lawSceneDisjoint (placementScene p')   -- either unchanged, or it was accepted (disjoint)

-- | @move p i d@ agrees with @p@ on every identity @≠ i@ — a move never perturbs the
-- other two widgets.
lawMoveOnlyTouchesTarget :: Placement -> ColorIdentity -> (Int, Int) -> Bool
lawMoveOnlyTouchesTarget p i d =
  all (\j -> Map.lookup j (move p i d) == Map.lookup j p)
      [ j | j <- allIdentities, j /= i ]

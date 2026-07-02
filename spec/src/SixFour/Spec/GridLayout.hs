{- |
Module      : SixFour.Spec.GridLayout
Description : The capture-scene LAYOUT as a contention-free claim set (the keystone).

The GRID design language says every widget is a rectangular block of cells on the
ONE 4 pt lattice ('SixFour.Spec.Lattice'). This module makes the WHOLE SCENE — not
just one widget — a proven object: a 'Scene' is a list of named 'LRegion's, and the
laws below prove they are pairwise DISJOINT (no two widgets claim the same cell),
in-bounds, touch-floor-legal, and safe-area-clearing. So "operations follow the
grid" is not a convention — it is a theorem @cabal test@ re-checks.

== Reuse, not reinvention (the F-4 factoring)

Contention is detected with the SAME no-blend algebra the palette uses
('SixFour.Spec.CellFiber.join' / 'isContested') — but keyed by SCREEN cells
@(col,row)@, NOT the 64×64 GIF field ('SixFour.Spec.CellGrid.Place' is GIF-sized,
4096 cells; the screen is @cols × rows = 100 × 218@, a different base, so its
@allPlaces@/@contestedPlaces@ cannot be reused). Each region claims a distinct
per-widget 'Color'; folding the claims with 'join' makes a contested cell a
2-element 'Set' ('isContested'), exactly as a double-claimed palette cell would be.
'lawDisjointMatchesRects' bridges this algebraic view to the plain AABB rectangle
test, so the two notions of "overlap" are provably identical.

== The capture scene is the AS-BUILT WIP layout

'captureScene' encodes the actual shipped capture screen: a 64×64 (256 pt) preview
hero riding high, and the 16×16 (64 pt) live palette that IS the capture button in
the thumb zone. (This is why the v2.0 golden-split anchor was removed from
'SixFour.Spec.Lattice' — the real layout is not a golden section; it is this, and it
is proven here.) Emitted to @SixFour/Generated/GridLayoutContract.swift@; the Swift
@place(_:)@ modifier consumes each region so @CaptureView@ hand-places nothing.

GHC-boot-only: base, containers, plus 'SixFour.Spec.CellFiber' / '.Lattice'.
-}
-- COMPARTMENT: SWIFT-COREAI | tag:DisplaySide
module SixFour.Spec.GridLayout
  ( -- * The region + the scene
    LRegion(..)
  , Scene
  , captureScene
  , decisionScene
    -- * Helpers
  , regionCells
  , regionsOverlap
  , sceneContested
  , sceneInteractive
  , screenCells
  , coverComplement
    -- * Laws (predicates; QuickCheck'd in Properties.GridLayout)
  , lawSceneDisjoint
  , lawSceneInBounds
  , lawInteractiveTouchFloor
  , lawSafeAreaClearance
  , lawPriorityDistinct
  , lawDisjointMatchesRects
  , lawCoverPartitions
  , lawWidgetsClearCorners
  ) where

import           Data.List       (nub)
import           Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Data.Set        as Set

import SixFour.Spec.CellFiber (Color(..), Cell, singletonCell, join, isContested)
import SixFour.Spec.Lattice
  ( cols, rows, gifPx, touchFloorCells, screenHeightPt, safeTopPt, safeBottomPt
  , cellOnScreen )

-- | A widget's rectangular claim on the screen lattice (top-left origin, atoms).
-- @lrWidget@ is the owner id (distinct per widget); @lrPriority@ is the deterministic
-- tiebreak surfaced if a (proven-impossible) collision occurs; @lrInteractive@ marks
-- touch targets (which must clear the floor).
data LRegion = LRegion
  { lrCol        :: !Int
  , lrRow        :: !Int
  , lrW          :: !Int
  , lrH          :: !Int
  , lrWidget     :: !Int
  , lrPriority   :: !Int
  , lrInteractive :: !Bool
  } deriving (Eq, Show)

-- | A named set of widget regions composing one screen.
type Scene = [(String, LRegion)]

-- | THE capture scene — the as-built WIP layout in 4 pt cells (100 × 218 field):
--
--   * @preview@ : 64×64 (256 pt) hero, centered (@(100-64)/2 = 18@), top row 22
--     (88 pt — clears the 62 pt Dynamic Island). Non-interactive.
--   * @palette@ : 16×16 (64 pt) live palette = the capture button, centered
--     (@(100-16)/2 = 42@), top row 145 (thumb zone). Interactive (64 ≥ 44 floor).
--
-- Disjoint (preview rows 22–85, palette rows 145–160), in-bounds, and safe-area
-- clearing — all proven below.
captureScene :: Scene
captureScene =
  [ ("preview", LRegion { lrCol = 18, lrRow = 22,  lrW = 64, lrH = 64
                        , lrWidget = 0, lrPriority = 0, lrInteractive = False })
  , ("palette", LRegion { lrCol = 42, lrRow = 145, lrW = 16, lrH = 16
                        , lrWidget = 1, lrPriority = 1, lrInteractive = True })
  ]

-- | THE V3.0 DECISION SCENE — the post-capture surface where the user iterates the
-- 16³ proposal until they like it. Every widget is a user-CHANGEABLE model-boundary
-- knob (grounded in "SixFour.Spec.ModelIO" @ModelInput@ + the V3 somatic gene), on
-- the same proven lattice as 'captureScene':
--
--   * @preview@  : 64×64 hero — the rendered result (@renderFrame@, palette[index]).
--     INTERACTIVE: horizontal drag scrubs the frame (and derives the paint layer).
--   * @paint@    : 64×64 — the 16³ control grid at 4 atoms per control cell (16 pt,
--     paintable): the @miNudge@ 'CellBudget' surface (one cell → 4096-leaf subtree).
--   * @channels@ : 64×12 strip — the 9 ChannelProduct colour×space pairs (which
--     channel the brush paints).
--   * @gauge@    : 20×12 — the φ6 toggle (@miGauge@: colour-by-space vs the dual).
--   * @gene@     : 20×12 — the SOMATIC θ_up toggle (learned invention vs the
--     deterministic floor; zero-gene == floor makes OFF always safe).
--   * @again@    : 20×12 — reject: recapture / re-propose (the decision stream).
--   * @accept@   : 32×16 thumb hero — commit this 16³ (ends the loop).
--
-- Geometry: rows 16–193 (top 64 pt clears the 62 pt island; bottom 772 pt clears
-- 874−34=840); centre columns 18–81 stay clear of the 14-cell corner arcs. All
-- eight laws below are @once@-tested over this scene in @Properties.GridLayout@.
decisionScene :: Scene
decisionScene =
  [ ("preview",  LRegion { lrCol = 18, lrRow = 16,  lrW = 64, lrH = 64
                         , lrWidget = 0, lrPriority = 0, lrInteractive = True })
  , ("paint",    LRegion { lrCol = 18, lrRow = 82,  lrW = 64, lrH = 64
                         , lrWidget = 1, lrPriority = 1, lrInteractive = True })
  , ("channels", LRegion { lrCol = 18, lrRow = 148, lrW = 64, lrH = 12
                         , lrWidget = 2, lrPriority = 2, lrInteractive = True })
  , ("gauge",    LRegion { lrCol = 18, lrRow = 162, lrW = 20, lrH = 12
                         , lrWidget = 3, lrPriority = 3, lrInteractive = True })
  , ("gene",     LRegion { lrCol = 40, lrRow = 162, lrW = 20, lrH = 12
                         , lrWidget = 4, lrPriority = 4, lrInteractive = True })
  , ("again",    LRegion { lrCol = 62, lrRow = 162, lrW = 20, lrH = 12
                         , lrWidget = 5, lrPriority = 5, lrInteractive = True })
  , ("accept",   LRegion { lrCol = 34, lrRow = 178, lrW = 32, lrH = 16
                         , lrWidget = 6, lrPriority = 6, lrInteractive = True })
  ]

-- | The screen cells @(col,row)@ a region claims.
regionCells :: LRegion -> [(Int, Int)]
regionCells r =
  [ (c, rr) | c  <- [lrCol r .. lrCol r + lrW r - 1]
            , rr <- [lrRow r .. lrRow r + lrH r - 1] ]

-- | AABB overlap: two regions share at least one cell iff their col ranges AND row
-- ranges both overlap (the standard separating-axis test).
regionsOverlap :: LRegion -> LRegion -> Bool
regionsOverlap a b =
     lrCol a < lrCol b + lrW b && lrCol b < lrCol a + lrW a
  && lrRow a < lrRow b + lrH b && lrRow b < lrRow a + lrH a

-- | Fold every region's claim into a screen-cell grid using the fiber 'join'
-- (REUSE: the same no-blend algebra as the palette). A cell claimed by two widgets
-- holds both distinct per-widget 'Color's, so it is 'isContested'.
sceneGrid :: Scene -> Map (Int, Int) Cell
sceneGrid scene = Map.fromListWith join
  [ (cell, singletonCell (Color (lrWidget r, 0, 0)))
  | (_, r) <- scene, cell <- regionCells r ]

-- | Every screen cell where two+ widgets collided (the total "I want to know"
-- report; empty for a well-formed scene). Mirrors 'CellGrid.contestedPlaces' but
-- over the screen base.
sceneContested :: Scene -> [(Int, Int)]
sceneContested = Map.keys . Map.filter isContested . sceneGrid

-- | The interactive (touch-target) regions of a scene.
sceneInteractive :: Scene -> [LRegion]
sceneInteractive scene = [ r | (_, r) <- scene, lrInteractive r ]

-- LAWS ----------------------------------------------------------------------

-- | DISJOINT: no two widgets claim the same cell — @sceneContested@ is empty. This
-- is the keystone: the scene blends nothing and surfaces no sentinel. Discharge:
-- reuse 'CellFiber.isContested' over the folded screen grid.
lawSceneDisjoint :: Scene -> Bool
lawSceneDisjoint = null . sceneContested

-- | Every claimed cell lies inside the @100 × 218@ screen lattice.
lawSceneInBounds :: Scene -> Bool
lawSceneInBounds scene =
  all inb [ cell | (_, r) <- scene, cell <- regionCells r ]
  where inb (c, rr) = c >= 0 && c < cols && rr >= 0 && rr < rows

-- | Every interactive region clears the HIG touch floor in BOTH dimensions
-- (@≥ touchFloorCells = 11@ atoms = 44 pt).
lawInteractiveTouchFloor :: Scene -> Bool
lawInteractiveTouchFloor scene =
  all (\r -> lrW r >= touchFloorCells && lrH r >= touchFloorCells)
      (sceneInteractive scene)

-- | Every region clears BOTH OS safe areas: its top ≥ the Dynamic Island inset and
-- its bottom ≤ the screen minus the home-indicator inset.
lawSafeAreaClearance :: Scene -> Bool
lawSafeAreaClearance scene = all clears [ r | (_, r) <- scene ]
  where
    clears r =  lrRow r * gifPx >= safeTopPt
             && (lrRow r + lrH r) * gifPx <= screenHeightPt - safeBottomPt

-- | Priorities are pairwise distinct ⇒ a (proven-impossible) collision still has a
-- single deterministic winner; never an ambiguous tie.
lawPriorityDistinct :: Scene -> Bool
lawPriorityDistinct scene =
  let ps = map (lrPriority . snd) scene in length (nub ps) == length ps

-- | BRIDGE: the algebraic "no contested cell" view agrees exactly with the geometric
-- AABB "no rectangles overlap" view — so the fiber proof and the rectangle test are
-- the same theorem.
lawDisjointMatchesRects :: Scene -> Bool
lawDisjointMatchesRects scene =
  null (sceneContested scene) == not (any (uncurry regionsOverlap) (distinctPairs (map snd scene)))
  where
    distinctPairs xs = [ (a, b) | (a : rest) <- tails1 xs, b <- rest ]
    tails1 []          = []
    tails1 l@(_ : t)   = l : tails1 t

-- TOTALITY (the cover groundwork SixFour.Spec.Ownership composes) --------------

-- | Every cell on the @100 × 218@ screen lattice — the full domain a TOTAL cover
-- must account for. (The capture scene's foreground widgets claim only a few
-- thousand of these 21800 cells; the rest are the 'coverComplement'.)
screenCells :: [(Int, Int)]
screenCells = [ (c, r) | r <- [0 .. rows - 1], c <- [0 .. cols - 1] ]

-- | The cells NO foreground region claims — the COMPLEMENT a background owner
-- (Ownership's @Field@) absorbs to make the cover TOTAL. By construction it is
-- disjoint from every claim and is kept OUTSIDE the disjoint claim set: the
-- complement never enters 'sceneGrid', so it can never contest a foreground widget.
-- The ground is a separate layer — exactly as the Swift @TintedCheckerField@ already
-- is — so totality needs no priority resolver and no grafted full-screen rectangle.
coverComplement :: Scene -> [(Int, Int)]
coverComplement scene =
  [ cell | cell <- screenCells, not (cell `Set.member` claimed) ]
  where claimed = Set.fromList [ cell | (_, r) <- scene, cell <- regionCells r ]

-- | TOTAL COVER: for a well-formed (disjoint) scene, the foreground claims plus the
-- 'coverComplement' PARTITION the @100 × 218@ lattice — every cell is covered exactly
-- once. Stated as: the scene is disjoint, its claimed cells carry no duplicate, the
-- claims and the complement are disjoint, and their union is the whole lattice. So a
-- background @Field@ owner that takes the complement makes the cover total WITHOUT
-- ever joining the disjoint claim set. The complement-side companion of
-- 'lawSceneDisjoint': disjointness says "no cell claimed twice"; this says "and none
-- left unaccounted-for."
lawCoverPartitions :: Scene -> Bool
lawCoverPartitions scene =
     lawSceneDisjoint scene                                  -- foreground claims disjoint…
  && length claimed == Set.size claimedSet                   -- …so no cell is claimed twice
  && Set.null (Set.intersection claimedSet complementSet)    -- claims ∩ complement = ∅ (by construction)
  && Set.union claimedSet complementSet == Set.fromList screenCells  -- claims ⊎ complement = whole lattice
  where
    claimed       = [ cell | (_, r) <- scene, cell <- regionCells r ]
    claimedSet    = Set.fromList claimed
    complementSet = Set.fromList (coverComplement scene)

-- | WIDGET SIZING vs the rounded display: every cell every widget claims lies on
-- the physical (rounded) screen, no widget pokes into a clipped corner. This is
-- the first-alignment law that ties widget SIZE and PLACEMENT to the rounded
-- iPhone 17 Pro display ('SixFour.Spec.Lattice.cellOnScreen'): a region sized or
-- moved so a corner cell falls off the arc fails the build here, before any port.
lawWidgetsClearCorners :: Scene -> Bool
lawWidgetsClearCorners scene =
  all cellOnScreen [ cell | (_, r) <- scene, cell <- regionCells r ]

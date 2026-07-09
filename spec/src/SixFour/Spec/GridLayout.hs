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
  , curateScene
  , liveScene
  , scrollScene
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
--   * @preview@ : 64×64 (256 pt) hero, centered (@(100-64)/2 = 18@), top row 16
--     (64 pt — clears the 62 pt Dynamic Island). Non-interactive. This was the
--     LOCKED SCENE ANCHOR across capture → captured → decide; the D3 Decide
--     rebuild moved 'decisionScene''s hero to its own judged placement, so the
--     anchor now pins capture ↔ the review field only.
--   * @palette@ : RETIRED (THE DESIGN E10, 2026-07-08). The 16² live-palette
--     widget's last render site was demolished — the pyramid vertex IS the
--     realized palette and the shutter ('liveScene' @field16@ + the D1 BRACKETS)
--     — so the region leaves the proven scene with it.
--
-- In-bounds and safe-area clearing — all proven below (a one-region scene is
-- trivially disjoint).
captureScene :: Scene
captureScene =
  [ ("preview", LRegion { lrCol = 18, lrRow = 16,  lrW = 64, lrH = 64
                        , lrWidget = 0, lrPriority = 0, lrInteractive = False })
  ]

-- | THE DECISION SCENE — rebuilt around the TWO VERBS (THE DESIGN D3, 2026-07-08,
-- @docs/UI-FORM-FOLLOWS-FUNCTION.md@). The scene shows a DECISION, not machinery:
-- the judgment view is the hero, ACCEPT and AGAIN are the two clearest controls in
-- the app, and the W1 paint\/channel\/gauge\/gene world is DEMOTED behind one fold
-- (fully functional, just no longer first-class):
--
--   * @hero@     : 64×64 at (14,30) — the 64³ reconstruction (floor or gene): what
--     accepting would ship. INTERACTIVE: horizontal drag scrubs the frame (and
--     derives the paint layer). Wears the D1 BRACKETS in its own gutter (cols
--     12–13\/78–79, rows 28–29\/94–95 — cells no region claims, by construction).
--   * @coarse@   : 16×16 at (82,30), beside the hero — the RAW 16³ coarse tier at
--     the scrubbed layer: the 64-vs-16 judgment read at a glance. Display-only.
--   * @tally@    : 16×2 at (82,26), above the coarse — the STATIC intake-tally
--     idiom (4 slots of 3 cells + 1-cell gaps, the exact 'liveScene' @intake16@
--     geometry) naming the 4-cells-per-frame ledger structure, so the
--     pour-equivalence language crosses scenes. Display-only.
--   * @fold@     : 12×12 at (44,98), centred between hero and verbs — THE advanced
--     fold chevron (FRAME face). Opening reveals @advanced@ top-down as a
--     cell-row reveal; closing removes it.
--   * @advanced@ : 64×76 at (18,112) — the demoted W1 bench (9-channel strip, the
--     16³ paint grid at 3 atoms per control cell, φ6 gauge, somatic-gene toggle)
--     INSIDE one proven region. Rendered only while the fold is open — the region
--     is static so the reveal can never contend; the fold state is render state.
--   * @again@ \/ @accept@ : the bottom verb band, rows 188–203 — 44×16 each
--     (176×64 pt, 4× the touch floor), 4-cell gaps (4+44+4+44+4 = 100 cols).
--     AGAIN = hollow FRAME + retake glyph; ACCEPT = filled control-ink face +
--     seal glyph. The clearest controls on any scene.
--
-- Geometry: rows 26–203 (top 104 pt clears the 62 pt island; bottom 812 pt clears
-- 874−34 = 840; rows ≤ 203 sit fully above the 14-cell bottom corner arcs, so even
-- the col-4\/col-95 verb corners are on-screen). All eight laws below are
-- @once@-tested over this scene in @Properties.GridLayout@.
decisionScene :: Scene
decisionScene =
  [ ("hero",     LRegion { lrCol = 14, lrRow = 30,  lrW = 64, lrH = 64
                         , lrWidget = 0, lrPriority = 0, lrInteractive = True })
  , ("coarse",   LRegion { lrCol = 82, lrRow = 30,  lrW = 16, lrH = 16
                         , lrWidget = 1, lrPriority = 1, lrInteractive = False })
  , ("tally",    LRegion { lrCol = 82, lrRow = 26,  lrW = 16, lrH = 2
                         , lrWidget = 2, lrPriority = 2, lrInteractive = False })
  , ("fold",     LRegion { lrCol = 44, lrRow = 98,  lrW = 12, lrH = 12
                         , lrWidget = 3, lrPriority = 3, lrInteractive = True })
  , ("advanced", LRegion { lrCol = 18, lrRow = 112, lrW = 64, lrH = 76
                         , lrWidget = 4, lrPriority = 4, lrInteractive = True })
  , ("again",    LRegion { lrCol = 4,  lrRow = 188, lrW = 44, lrH = 16
                         , lrWidget = 5, lrPriority = 5, lrInteractive = True })
  , ("accept",   LRegion { lrCol = 52, lrRow = 188, lrW = 44, lrH = 16
                         , lrWidget = 6, lrPriority = 6, lrInteractive = True })
  ]

-- | THE LAUNCH CURATE SCENE (L1.3) — the 256³ curation loop: the Curating phase's
-- surface (a Picked self-excursion, "SixFour.Spec.ABSurface" @Curating@), where the
-- user inspects and iterates the TRUE export volume the octant ladder built
-- ("SixFour.Spec.SelfSimilarReconstruct" @expandRungVolume@ →
-- "SixFour.Spec.CurateRealize"). Same proven lattice, same centre band:
--
--   * @hero@    : 64×128 — the real 256³ render (the biggest widget any scene
--     carries: inspection IS the job). INTERACTIVE: horizontal drag scrubs t
--     through the 256 frames.
--   * @slabs@   : 64×12 strip — the t-slab rail: build progress per slab (the
--     frame-local/block-local streaming, made visible) + tap-to-jump.
--   * @source@  : 20×12 — the detail source: floor \/ my gene \/ adopted (the
--     three-arm switch; zero-gene == floor keeps FLOOR always safe).
--   * @repaint@ : 20×12 — reopen the 16³ paint bench to condition the next build.
--   * @rebuild@ : 20×12 — re-run the ladder with the current knobs (the iterate
--     verb of the curate loop).
--   * @accept@  : 32×16 thumb hero — commit the curated 256³ (fires @CurateDone@,
--     back to Picked: export-eligible).
--
-- Geometry: rows 16–191 (island + home-indicator clear), centre columns 18–81
-- (the 14-cell corner arcs cleared). All eight laws below are @once@-tested over
-- this scene in @Properties.GridLayout@.
curateScene :: Scene
curateScene =
  [ ("hero",    LRegion { lrCol = 18, lrRow = 16,  lrW = 64, lrH = 128
                        , lrWidget = 0, lrPriority = 0, lrInteractive = True })
  , ("slabs",   LRegion { lrCol = 18, lrRow = 146, lrW = 64, lrH = 12
                        , lrWidget = 1, lrPriority = 1, lrInteractive = True })
  , ("source",  LRegion { lrCol = 18, lrRow = 160, lrW = 20, lrH = 12
                        , lrWidget = 2, lrPriority = 2, lrInteractive = True })
  , ("repaint", LRegion { lrCol = 40, lrRow = 160, lrW = 20, lrH = 12
                        , lrWidget = 3, lrPriority = 3, lrInteractive = True })
  , ("rebuild", LRegion { lrCol = 62, lrRow = 160, lrW = 20, lrH = 12
                        , lrWidget = 4, lrPriority = 4, lrInteractive = True })
  , ("accept",  LRegion { lrCol = 34, lrRow = 176, lrW = 32, lrH = 16
                        , lrWidget = 5, lrPriority = 5, lrInteractive = True })
  ]

-- | THE LIVE TELEMETRY SCENE — the rung-ladder instrument regions shown WHILE the
-- burst runs (the LivePhaseField surface). The GRID mirrors the ladder: the
-- self-centered inverted pyramid renders its 64\/32\/16 bands at rows 49–112 \/
-- 117–148 \/ 153–168 (columns 18–81, derived from the 480 pt centered VStack), and
-- each rung's telemetry block rides the RIGHT FLANK beside its own band — same row
-- span, columns 84–97 — so a rung's arrival pulse, exposure state (optical stops
-- when the 'SixFour.Spec.MultiScaleCapture' ladder is on; pooling-equivalent stops
-- when derived), significance (√N per 'SixFour.Spec.ColorTime' N(k) = 8^k·N₀), and
-- independence health land AT the rung they describe, at the rung's native cadence:
--
--   * @rung64@ : 14×64 flank, rows 49–112 — the 20 Hz fine rung's meters.
--   * @rung32@ : 14×32 flank, rows 117–148 — the 10 Hz mid rung's meters.
--   * @rung16@ : 14×16 flank, rows 153–168 — the 5 Hz coarse rung's meters
--     (kept clear of the 16² shutter vertex at columns 42–57).
--   * @system@ : 64×24 machine ring below the pyramid, rows 178–201, columns
--     18–81 — tick CPU vs the 50 ms budget, the 384 MiB v21 hist-buffer
--     lifecycle (allocated\/held\/freed), and thermal pressure.
--   * @field64@\/@field32@\/@field16@ : the PYRAMID BANDS THEMSELVES as proven
--     regions — 64×64 at (18,49), 32×32 centered at (34,117), 16×16 centered
--     at (42,153), exactly the cells the self-centered VStack renders. Pinned
--     so the influence ground anchors its radiating sources to the REAL
--     pyramid (retiring the stale movable field64\/palette16 anchors) and any
--     future per-band placement reads the contract, not view geometry.
--
-- THE POUR instruments (THE DESIGN D2, 2026-07-08) ride the same lattice —
-- display-only overlays whose QUANTITIES live in "SixFour.Spec.ColorTimeDisplay"
-- (slot counts = @unitsOf@ by @lawTallyEqualsUnits@; only geometry is proven here):
--
--   * @intake32@ : 32×2 tally rail at (34,114) — 2 slots of 15 cells + a 2-cell
--     gap, in the rows-113–116 gutter between the 64² and 32² bands.
--   * @intake16@ : 16×2 tally rail at (42,149) — 4 slots of 3 cells + 1-cell
--     gaps, in the rows-149–152 gutter; clear of the shutter-bracket top row 151
--     by construction (the brackets live at the field16 gutter, cols 40–59).
--   * @fluxBar@  : 16×1 at (42,172), directly under the shutter brackets — the
--     paletteW1 wave meter (log₂ fill, 5 Hz).
--   * @evRail@   : 2×26 at (2,120), cols 2–3 — 13 detent blocks of 2×2 (⅓ stops,
--     ±2 EV), vertically centered on field32 (117 + (32−26)\/2 = 120); the LEFT
--     edge because the right flank belongs to the rung meters. Materializes only
--     while the EV drag is live; the region pins where.
--   * @lookStrip@: 64×4 at (18,44), the gutter above the 64² band — one 4×4
--     graded swatch per LOOK; materializes only while the LOOK swipe is live.
--
-- ALL are non-interactive at the REGION level (meters, anchors, and display-only
-- gesture rails — the pyramid's tap gestures live on its views; the LOOK\/EV
-- gestures stay on the clear ground layer): they must never intercept the ground
-- LOOK-swipe\/EV-drag layer, so the 11-cell touch floor does not bind and the
-- slim 14-cell flank \/ 2-cell rail are legal. The flank columns 84–97 sit clear
-- of the pyramid columns 18–81; the pour instruments sit in the pyramid's real
-- VStack gutters (rows 44–47 \/ 114–115 \/ 149–150 \/ 172) and the left margin
-- (cols 2–3); rows ≥ 44 and ≤ 201 clear both corner arcs and both OS safe
-- areas — all re-proven by the eight laws below over this scene in
-- @Properties.GridLayout@.
liveScene :: Scene
liveScene =
  [ ("rung64", LRegion { lrCol = 84, lrRow = 49,  lrW = 14, lrH = 64
                       , lrWidget = 0, lrPriority = 0, lrInteractive = False })
  , ("rung32", LRegion { lrCol = 84, lrRow = 117, lrW = 14, lrH = 32
                       , lrWidget = 1, lrPriority = 1, lrInteractive = False })
  , ("rung16", LRegion { lrCol = 84, lrRow = 153, lrW = 14, lrH = 16
                       , lrWidget = 2, lrPriority = 2, lrInteractive = False })
  , ("system", LRegion { lrCol = 18, lrRow = 178, lrW = 64, lrH = 24
                       , lrWidget = 3, lrPriority = 3, lrInteractive = False })
  , ("field64", LRegion { lrCol = 18, lrRow = 49,  lrW = 64, lrH = 64
                        , lrWidget = 4, lrPriority = 4, lrInteractive = False })
  , ("field32", LRegion { lrCol = 34, lrRow = 117, lrW = 32, lrH = 32
                        , lrWidget = 5, lrPriority = 5, lrInteractive = False })
  , ("field16", LRegion { lrCol = 42, lrRow = 153, lrW = 16, lrH = 16
                        , lrWidget = 6, lrPriority = 6, lrInteractive = False })
  , ("intake32", LRegion { lrCol = 34, lrRow = 114, lrW = 32, lrH = 2
                         , lrWidget = 7, lrPriority = 7, lrInteractive = False })
  , ("intake16", LRegion { lrCol = 42, lrRow = 149, lrW = 16, lrH = 2
                         , lrWidget = 8, lrPriority = 8, lrInteractive = False })
  , ("fluxBar", LRegion { lrCol = 42, lrRow = 172, lrW = 16, lrH = 1
                        , lrWidget = 9, lrPriority = 9, lrInteractive = False })
  , ("evRail", LRegion { lrCol = 2, lrRow = 120, lrW = 2, lrH = 26
                       , lrWidget = 10, lrPriority = 10, lrInteractive = False })
  , ("lookStrip", LRegion { lrCol = 18, lrRow = 44, lrW = 64, lrH = 4
                          , lrWidget = 11, lrPriority = 11, lrInteractive = False })
  ]

-- | THE SCROLL SCENE — the infinite-tube viewport (a @.live@ self-excursion, render
-- state only: the FSM is untouched, exactly as lock\/burst are internal to @.live@).
-- The tube is the Jeandel–Rao aperiodic weave ("SixFour.Spec.WangTiling"): 64² pour
-- groups of 4 frames ('SixFour.Spec.WangTiling.sliceRows'), scrolled vertically,
-- coarse-first with refine-on-linger on the SAME reveal ladder as boot
-- ('SixFour.Spec.WangTiling.revealAt' — trust is EARNED per slice, never animated):
--
--   * @hero@   : 64×64 at (18,49) — the tube viewport, on EXACTLY the 'liveScene'
--     @field64@ band (the scroll takes over the pyramid's fine band, so entering\/
--     leaving the tube never moves the eye). INTERACTIVE: vertical drag scrolls the
--     tube (16 cells = one slice). Wears the D1 BRACKETS in its own gutter (cols
--     16–17\/82–83, rows 47–48\/113–114 — cells no region claims, by construction;
--     the @pour@ rail at row 114 sits between the bottom bracket arms, cols 42–57).
--   * @pour@   : 16×2 at (42,114) — the intake-tally idiom (4 slots of 3 cells +
--     1-cell gaps, the exact 'liveScene' @intake16@ geometry) counting the 4-frame
--     pour group the viewport loops at 20 Hz. Display-only.
--   * @rail@   : 2×128 at (84,49) — the tube-position rail on the right flank: a
--     ±32-slice ruler ticked at pour-group pitch scrolling under a fixed centre
--     cursor, materialized slices marked. Display-only (the scroll gesture lives on
--     the hero), so the 2-cell width is legal.
--   * @exit@   \/ @reseed@ : 20×12 verb pair at (18,184) \/ (62,184) — leave the
--     tube (back to the live pyramid) \/ jump to a fresh tube seed. FRAME faces
--     ('SixFour.Spec.CellMechanics.controlFaces'), both over the touch floor.
--
-- Geometry: rows 47–196 (island + home-indicator + corner arcs cleared — the same
-- envelope 'liveScene' proves for rows 44–201), hero centre columns 18–81, rail
-- columns 84–85 (inside the proven rung-flank columns 84–97). All eight laws below
-- are @once@-tested over this scene in @Properties.GridLayout@.
scrollScene :: Scene
scrollScene =
  [ ("hero",   LRegion { lrCol = 18, lrRow = 49,  lrW = 64, lrH = 64
                       , lrWidget = 0, lrPriority = 0, lrInteractive = True })
  , ("pour",   LRegion { lrCol = 42, lrRow = 114, lrW = 16, lrH = 2
                       , lrWidget = 1, lrPriority = 1, lrInteractive = False })
  , ("rail",   LRegion { lrCol = 84, lrRow = 49,  lrW = 2,  lrH = 128
                       , lrWidget = 2, lrPriority = 2, lrInteractive = False })
  , ("exit",   LRegion { lrCol = 18, lrRow = 184, lrW = 20, lrH = 12
                       , lrWidget = 3, lrPriority = 3, lrInteractive = True })
  , ("reseed", LRegion { lrCol = 62, lrRow = 184, lrW = 20, lrH = 12
                       , lrWidget = 4, lrPriority = 4, lrInteractive = True })
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

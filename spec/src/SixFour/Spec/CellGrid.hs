{- |
Module      : SixFour.Spec.CellGrid
Description : The WHERE axis — the spatial BASE and the pointwise-lifted grid join.

This is the BASE half of the base/fiber cell algebra ('SixFour.Spec.CellFiber' is
the fiber). A 'Place' is a lattice coordinate (from 'SixFour.Spec.Lattice'); a
'Grid' is a total function @Place -> Cell@; 'gridJoin' is the POINTWISE LIFT of the
fiber 'SixFour.Spec.CellFiber.join'. Because the fiber join is a total bounded
join-semilattice and the 'Place' base is FINITE and total, the lifted 'gridJoin'
is total-by-inheritance (the 'inheritedTotality' lemma, registered as law T9 —
the spatial sibling of Display-FSM T5 δ-totality).

== Provenance on the base (critic hole #1, the WHERE/WHAT factoring)

@binding :: Place -> Source@ records WHO last claimed each Place, drawn from the
FIXED enum 'Source' = {Zig, Swift, Cursor}. Provenance is therefore a BASE
attribute, NOT a value attribute: the fiber carrier ('Cell') stays a source-free
@Set Color@ bounded by @K = 256@. A claim is the embedding @section@ of one
(Place, Color) into a 'Grid' that is ⊥ everywhere else.

== Alignment with the Display FSM (SIXFOUR-DISPLAY-FSM.md)

'Place' ranges over the GIF field @Fin H × Fin W@ (H = W = 64). A 'Grid' is the
spatial face of the FSM state Σ observed up to the S_K gauge; 'gridJoin' totality
(T9) is the spatial companion of T5 (\"every cell is I/O at 20 fps\" =
@touched(δ) = fullLattice@). The render of @grid p@ is the per-cell observation λ.

GHC-boot-only: base, containers, plus 'SixFour.Spec.Lattice' / '.CellFiber'.
-}
-- COMPARTMENT: SWIFT-COREAI | tag:DisplaySide
module SixFour.Spec.CellGrid
  ( -- * The base
    Place(..)
  , placesH, placesW, allPlaces
  , inField
    -- * Provenance (on the BASE, fixed enum)
  , Source(..)
  , Binding
    -- * Widget OWNERSHIP (the partition that makes overlap the exception)
  , Widget(..)
  , Owner             -- ^ Place -> Maybe Widget : who owns each cell (⊥ = unowned)
  , EffectZone        -- ^ Place -> Bool : Places where overlap is an opt-in EFFECT
    -- * The grid as Place -> Cell
  , Grid
  , emptyGrid         -- ^ ⊥ everywhere
  , gridAt            -- ^ apply the total function
    -- * The pointwise-lifted join
  , gridJoin          -- ^ T9: pointwise lift of CellFiber.join
  , gridJoinAll       -- ^ fold gridJoin over a list
    -- * Claim embedding (section)
  , section           -- ^ (Place, Color) -> Grid : a single in-place claim
  , claimWith         -- ^ section + binding update
    -- * Contention — you always KNOW (never an error, never a silent blend)
  , contestedPlaces   -- ^ every Place where two+ widgets collided
    -- * Observation
  , renderGrid        -- ^ Place -> Color : the static LOUD observer (contested ↦ sentinel)
  , renderGridAt      -- ^ Int -> EffectZone -> Place -> Color : option-c (loud OR shimmer-in-zone)
    -- * Laws (predicates; QuickCheck'd in Properties.CellGrid)
  , lawGridJoinAssoc
  , lawGridJoinComm
  , lawGridJoinIdem
  , lawEmptyGridIdentity
  , lawInheritedTotality      -- ^ T9
  , lawSectionEmbeds
  , lawBindingFixedEnum
  , lawRenderGridTotal
  , lawDisjointNoContest      -- ^ disjoint widget ownership ⇒ no overlap ever
  , lawContestedShows         -- ^ every collision is visibly the loud sentinel
  , lawNoSilentMerge          -- ^ no observer ever invents a colour (base-level no-blend)
  ) where

import           Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map

import SixFour.Spec.CellFiber
  ( Cell, Color, bottom, join, render, inGamut, singletonCell
  , isContested, contestedSentinel, shimmerAt, neutralColor, claims )
import SixFour.Spec.Lattice   (previewCells)   -- 64 (the GIF field side)

-- | A lattice coordinate in the 64×64 GIF field (Spec.Lattice's @previewCells@).
data Place = Place { placeRow :: !Int, placeCol :: !Int }
  deriving (Eq, Ord, Show)

-- | Field side (rows) = @previewCells@ = 64.
placesH :: Int
placesH = previewCells

-- | Field side (cols) = @previewCells@ = 64.
placesW :: Int
placesW = previewCells

-- | The FINITE, total base: all @H·W = 4096@ places. (This finiteness is the
-- hypothesis of the inherited-totality lemma T9.)
allPlaces :: [Place]
allPlaces = [ Place r c | r <- [0 .. placesH - 1], c <- [0 .. placesW - 1] ]

-- | Field-membership predicate.
inField :: Place -> Bool
inField (Place r c) = r >= 0 && r < placesH && c >= 0 && c < placesW

-- | Provenance enum on the BASE (fixed; not extensible). Zig = deterministic
-- core kernel, Swift = UI/host, Cursor = user gesture. This is where #1 is paid.
data Source = Zig | Swift | Cursor
  deriving (Eq, Ord, Show, Enum, Bounded)

-- | @binding :: Place -> Source@ as a total map with a Zig default.
type Binding = Place -> Source

-- | A UI widget — the UNIT OF OWNERSHIP. Each cell is owned by at most one widget
-- (the shutter, the palette strip, a slider, the cursor brush, …). Kept abstract
-- as an id in the spec; the app supplies the concrete widget set.
newtype Widget = Widget Int
  deriving (Eq, Ord, Show)

-- | Ownership of the base: which widget owns each Place (@Nothing@ = unowned ⇒ ⊥).
-- A WELL-FORMED layout is one whose owned regions are DISJOINT — then every cell
-- is ⊥ or a singleton and overlap NEVER occurs ('lawDisjointNoContest'). Overlap is
-- the exception, surfaced loudly, not the rule.
type Owner = Place -> Maybe Widget

-- | The Places where overlap is an INTENTIONAL effect: a contested cell here
-- 'shimmer's its claimants on the 20 fps clock instead of showing the loud
-- sentinel. Everywhere else, a collision is a bug and shows the sentinel.
type EffectZone = Place -> Bool

-- | A grid: total @Place -> Cell@, carried sparsely (default ⊥) for finiteness.
newtype Grid = Grid (Map Place Cell)

-- | ⊥ everywhere.
emptyGrid :: Grid
emptyGrid = Grid Map.empty

-- | The total function: places with no claim are ⊥ ('CellFiber.bottom').
gridAt :: Grid -> Place -> Cell
gridAt (Grid m) p = Map.findWithDefault bottom p m

-- | T9 — the POINTWISE LIFT of 'CellFiber.join'. @(g ⊔ h) p = (g p) ⊕ (h p)@.
-- Carried as a key-union with per-key fiber join (⊥ is the map default, so
-- absent keys lift correctly).
gridJoin :: Grid -> Grid -> Grid
gridJoin (Grid a) (Grid b) = Grid (Map.unionWith join a b)

-- | Fold 'gridJoin' over a list (⊥ identity = 'emptyGrid').
gridJoinAll :: [Grid] -> Grid
gridJoinAll = foldr gridJoin emptyGrid

-- | The section/claim embedding: one (Place, Color) into a grid that is ⊥
-- everywhere else. This is the unit that 'gridJoin' accumulates.
section :: Place -> Color -> Grid
section p col = Grid (Map.singleton p (singletonCell col))

-- | Claim a colour AND record provenance on the base (returns the updated
-- binding alongside the section). Provenance never touches the value.
claimWith :: Binding -> Source -> Place -> Color -> (Grid, Binding)
claimWith bnd src p col = (section p col, \q -> if q == p then src else bnd q)

-- | The contested set: every Place where two+ widgets collided. This is the
-- total "I want to know" report — a layout is well-formed iff this is empty
-- (outside its declared effect-zones). Never throws.
contestedPlaces :: Grid -> [Place]
contestedPlaces g = filter (isContested . gridAt g) allPlaces

-- | Per-cell observation λ — the STATIC loud observer: render the cell, so a
-- contested Place shows the unmistakable 'contestedSentinel'. (Tick/effect-zone
-- aware rendering is 'renderGridAt'.)
renderGrid :: Grid -> Place -> Color
renderGrid g p = render (gridAt g p)

-- | The option-c observer λ_τ: at clock tick @t@, a contested Place that is
-- flagged as an 'EffectZone' SHIMMERS its claimants ('shimmerAt' — a real
-- claimant per tick, the "cool effect"); a contested Place OUTSIDE any effect-zone
-- shows the loud 'contestedSentinel' (a bug you must see); a clean Place renders
-- verbatim. NO blend on any path ('lawNoSilentMerge'). Reuses the FSM 20 fps clock.
renderGridAt :: Int -> EffectZone -> Grid -> Place -> Color
renderGridAt t zone g p =
  let cell = gridAt g p
  in if isContested cell
       then if zone p then shimmerAt t cell else contestedSentinel
       else render cell

-- LAWS ----------------------------------------------------------------------

-- | Pointwise join is associative. Discharge: REUSE 'CellFiber.lawJoinAssoc'
-- pointwise (Map.unionWith of an associative op is associative).
lawGridJoinAssoc :: Grid -> Grid -> Grid -> [Place] -> Bool
lawGridJoinAssoc x y z ps =
  all (\p -> gridAt (gridJoin (gridJoin x y) z) p
          == gridAt (gridJoin x (gridJoin y z)) p) ps

-- | Pointwise join is commutative. Discharge: REUSE 'CellFiber.lawJoinComm'.
lawGridJoinComm :: Grid -> Grid -> [Place] -> Bool
lawGridJoinComm x y ps =
  all (\p -> gridAt (gridJoin x y) p == gridAt (gridJoin y x) p) ps

-- | Pointwise join is idempotent. Discharge: REUSE 'CellFiber.lawJoinIdem'.
lawGridJoinIdem :: Grid -> [Place] -> Bool
lawGridJoinIdem x ps = all (\p -> gridAt (gridJoin x x) p == gridAt x p) ps

-- | 'emptyGrid' is the pointwise identity. Discharge: REUSE 'CellFiber.lawBottomIdentity'.
lawEmptyGridIdentity :: Grid -> [Place] -> Bool
lawEmptyGridIdentity x ps =
  all (\p -> gridAt (gridJoin emptyGrid x) p == gridAt x p) ps

-- | T9 — INHERITED TOTALITY: the pointwise lift of the total fiber join over the
-- finite total base is total. Discharge: NOT re-proved — cited from the fiber
-- ('CellFiber.lawRenderTotal' + total 'join') lifted over finite 'allPlaces'.
lawInheritedTotality :: Grid -> Bool
lawInheritedTotality g = all (inGamut . renderGrid g) allPlaces

-- | The section embedding places exactly one claim and is ⊥ elsewhere.
lawSectionEmbeds :: Place -> Color -> Place -> Bool
lawSectionEmbeds p col q =
  gridAt (section p col) q == (if q == p then singletonCell col else bottom)

-- | Source is the fixed 3-element enum (no provenance in the value carrier).
lawBindingFixedEnum :: Bool
lawBindingFixedEnum = [minBound .. maxBound] == [Zig, Swift, Cursor]

-- | The per-cell observation is total over the whole field (spatial sibling of T5).
lawRenderGridTotal :: Grid -> Bool
lawRenderGridTotal g = all (\p -> inField p ==> inGamut (renderGrid g p)) allPlaces
  where p ==> q = not p || q

-- | DISJOINT OWNERSHIP ⇒ NO OVERLAP. A grid assembled from claims at pairwise-
-- distinct Places has zero contested cells — so a well-formed (partitioned) layout
-- never blends and never shows a sentinel. Discharge: distinct Places ⇒ every cell
-- is ⊥ or a singleton ⇒ 'isContested' is false everywhere.
lawDisjointNoContest :: [(Place, Color)] -> Bool
lawDisjointNoContest cl = null (contestedPlaces g)
  where
    g = gridJoinAll [ section p c | (p, c) <- dedup [] cl ]
    dedup _    []            = []
    dedup seen ((p, c) : xs)
      | p `elem` seen = dedup seen xs
      | otherwise     = (p, c) : dedup (p : seen) xs

-- | Every collision is VISIBLE: under the static observer, each contested Place
-- shows the loud sentinel — you cannot miss it. Discharge: 'CellFiber.lawRenderContested'
-- lifted over 'contestedPlaces'.
lawContestedShows :: Grid -> Bool
lawContestedShows g = all (\p -> renderGrid g p == contestedSentinel) (contestedPlaces g)

-- | NO SILENT MERGE: for any tick and any effect-zone, 'renderGridAt' returns the
-- neutral anchor, the sentinel, or a REAL claimant — never a synthesised mixture.
-- This is the base-level statement of "I do not blend". Discharge: reuse
-- 'CellFiber.lawNoSynthesis' (clean / loud paths) + 'CellFiber.lawShimmerIsClaimant'
-- (effect path).
lawNoSilentMerge :: Int -> EffectZone -> Grid -> Place -> Bool
lawNoSilentMerge t zone g p =
  renderGridAt t zone g p `elem` (neutralColor : contestedSentinel : claims (gridAt g p))

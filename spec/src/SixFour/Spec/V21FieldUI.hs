{- |
Module      : SixFour.Spec.V21FieldUI
Description : V2.1 UI as FUNCTIONS over the probability field: the deterministic CELL-COUNT layer. A cell budget is apportioned over a Morton-aligned quadtree/octree by region uncertainty (Hamilton largest-remainder), and a set of widgets is forced onto DISTINCT counts (the opposition / repulsion law), so two widgets never claim the same number of cells.

Form follows function, and the function is probability. The UI for "SixFour.Spec.V21Field" is not a
view, it is a family of pure functions over the @[T,Y,X,3,256]@ energy field. This module promotes the
COUNT layer (the integer skeleton that ships hand-written in Swift, golden-gated, byte-exact); the
render\/bleed layer (where splats may overlap) is a separate METAL-GPU module built on top of this one.

Two ideas, kept apart on purpose:

  * __Bleed can interact.__ The visual splat of a cell may spread past its nominal bounds and overlap
    a neighbour. That is the render layer and is deliberately NOT exclusive. It is not in this module.
  * __Widgets oppose equal counts.__ The number of cells each widget owns must be pairwise DISTINCT.
    'allocateWidgets' enforces this with a staircase repulsion: rank by saliency (Morton tie-break),
    reserve a strictly-decreasing @k-1, k-2, .., 0@ floor, then Hamilton-distribute the surplus in a
    rank-monotone way so the per-widget totals stay strictly ordered, hence distinct. Distinct
    non-negative counts summing to @N@ across @k@ widgets exist iff @N >= k(k-1)\/2@
    ('oppositionFeasible'), and that feasibility floor is itself a law ('lawWidgetOppositionFloor').

The single statistic the budget chases is 'disagree': the non-mode observation mass of a captured
histogram (@total - max count@). It is @0@ on a unanimous bin (ties "SixFour.Spec.V21Field"
@lawHistUniformIsSpike@), so cells flow to where the distribution is uncertain, which is exactly where
the model has something to learn and the user has something to nudge.

== Relationship to the field laws

Each UI law is the twin of a field law: 'lawBudgetConserves' (no cell created or dropped) mirrors
@lawHistTotalPreserved@; 'lawWidgetBudgetPartitions' mirrors it across widgets; 'disagree' rests on
the same mode/argmin as @collapseQ16@. GHC-boot-only, all-integer (the Hamilton remainder is computed
on exact @Int@ numerators, no @Double@, so the Swift port is byte-exact). Laws QuickCheck'd in
"Properties.V21FieldUI".
-}
-- COMPARTMENT: ZIG-FLOOR | tag:DeviceTag
module SixFour.Spec.V21FieldUI
  ( -- * Grid geometry (the base lattice the UI is aligned to)
    Region(..)
  , Cells
  , loCorner
  , regionVolume
  , aligned
  , subRegionOf
  , regionVoxels
  , mortonKey
    -- * The saliency statistic the budget chases
  , disagree
  , regionWeight
    -- * The cell-budget function (one widget over its region)
  , Plot(..)
  , Layout
  , apportion
  , budgetCells
    -- * The opposition allocator (distinct counts across widgets)
  , oppositionFeasible
  , allocateWidgets
    -- * Laws (QuickCheck'd in @Properties.V21FieldUI@)
  , lawApportionConserves
  , lawBudgetConserves
  , lawBudgetGridAligned
  , lawDisagreeZeroOnSpike
  , lawWidgetBudgetPartitions
  , lawWidgetsOpposeEqualCounts
  , lawWidgetOppositionFloor
  , lawWidgetSalienceOrders
  ) where

import Data.Bits (shiftL, shiftR, (.|.), (.&.))
import Data.List (sortBy)
import Data.Ord  (comparing, Down(..))

import SixFour.Spec.V21Field (Voxel)

-- | A cell count: the integer budget unit the UI apportions. Cells are budget units, not voxels; one
--   base voxel may hold many cells (a confident region) or a region of many voxels may hold one cell.
type Cells = Int

-- | A half-open axis-aligned box @[lo,hi)@ per axis in the @64×64×64@ base lattice. The UI never lands
--   between voxels: every region boundary is an integer, so the grid is the only coordinate system.
data Region = Region
  { rX :: !(Int, Int)   -- ^ x interval @[lo,hi)@
  , rY :: !(Int, Int)   -- ^ y interval @[lo,hi)@
  , rT :: !(Int, Int)   -- ^ t interval @[lo,hi)@
  } deriving (Eq, Show)

-- | The low corner voxel of a region (its Morton key seed).
loCorner :: Region -> Voxel
loCorner r = (fst (rX r), fst (rY r), fst (rT r))

-- | The number of base voxels a region covers (its spatial-temporal volume).
regionVolume :: Region -> Int
regionVolume r = sp (rX r) * sp (rY r) * sp (rT r)
  where sp (lo, hi) = max 0 (hi - lo)

-- | Whether a region is grid-aligned and non-empty inside the @[0,64)@ box on every axis.
aligned :: Region -> Bool
aligned r = ok (rX r) && ok (rY r) && ok (rT r)
  where ok (lo, hi) = 0 <= lo && lo < hi && hi <= 64

-- | Whether the first region sits entirely inside the second (a plot inside its parent widget).
subRegionOf :: Region -> Region -> Bool
subRegionOf a b = ins (rX a) (rX b) && ins (rY a) (rY b) && ins (rT a) (rT b)
  where ins (alo, ahi) (blo, bhi) = alo >= blo && ahi <= bhi

-- | The base voxels of a region (used by 'regionWeight'; small regions only).
regionVoxels :: Region -> [Voxel]
regionVoxels r =
  [ (xx, yy, tt)
  | tt <- [fst (rT r) .. snd (rT r) - 1]
  , yy <- [fst (rY r) .. snd (rY r) - 1]
  , xx <- [fst (rX r) .. snd (rX r) - 1] ]

-- | The Morton (Z-order) key of a voxel: interleave the 6 bits of each coordinate so that nearby
--   voxels get nearby keys. This is the deterministic tie-break for every apportionment and ranking,
--   the project's "SixFour.Spec.PonderBudget" Morton idiom, so the UI is a pure function of the field
--   and never of arrival order.
mortonKey :: Voxel -> Int
mortonKey (x, y, t) = spread x .|. (spread y `shiftL` 1) .|. (spread t `shiftL` 2)
  where spread b = foldr (\i acc -> acc .|. (((b `shiftR` i) .&. 1) `shiftL` (3 * i))) 0 [0 .. 5]

-- | THE SALIENCY: the non-mode observation mass of a captured histogram, @total − max count@. It is
--   @0@ exactly when every observation agrees (a spike, the confident byte), and grows with spread, so
--   it is the integer "how uncertain is this bin" the budget chases. Same mode notion as @collapseQ16@.
disagree :: [Int] -> Int
disagree [] = 0
disagree cs = sum cs - maximum cs

-- | The weight of a region: the total 'disagree' over its voxels, given a per-voxel count-histogram
--   accessor. A flat region weighs @0@ (no cells pulled); a churny region weighs more. This is the
--   field-grounded instantiation of the abstract weight 'budgetCells' takes.
regionWeight :: (Voxel -> [Int]) -> Region -> Int
regionWeight field r = sum [ disagree (field v) | v <- regionVoxels r ]

-- | A leaf of a 'Layout': an aligned sub-region, its Morton key, and the cells it owns.
data Plot = Plot
  { plotRegion :: !Region   -- ^ the aligned grid cell this plot covers
  , plotMorton :: !Int      -- ^ its Morton key (stable draw order)
  , plotCells  :: !Int      -- ^ the number of cells budgeted to it
  } deriving (Eq, Show)

-- | A cell layout: the plots a budget resolves to, each owning a positive number of cells.
type Layout = [Plot]

-- | EXACT integer Hamilton largest-remainder apportionment: split @total@ cells across non-negative
--   integer weights, summing to EXACTLY @total@. Floor the ideal counts @total·w_i \/ Σw@ (computed on
--   integer numerators, so no @Double@ rounding), then hand the @total − Σfloor@ leftover cells to the
--   largest remainders, ties broken by lowest index (which the callers keep in Morton order). A
--   zero\/empty weight vector splits evenly. Mirrors "SixFour.Spec.EncoderWidthAlloc" @largestRemainder@
--   but all-integer for the byte-exact device port.
apportion :: Int -> [Int] -> [Int]
apportion total ws
  | n == 0          = []
  | total <= 0      = replicate n 0
  | s <= 0          = let q = total `div` n; r = total `mod` n
                      in [ q + (if i < r then 1 else 0) | i <- [0 .. n - 1] ]
  | otherwise       =
      let floors  = [ (total * w) `div` s | w <- ws ]
          fracs   = [ (total * w) `mod` s | w <- ws ]
          deficit = total - sum floors
          order   = sortBy (comparing (\i -> (Down (fracs !! i), i))) [0 .. n - 1]
          winners = take deficit order
      in [ (floors !! i) + (if i `elem` winners then 1 else 0) | i <- [0 .. n - 1] ]
  where
    n = length ws
    s = sum ws

-- | THE CELL-BUDGET FUNCTION: distribute @n@ cells over a region by recursively splitting it into
--   Morton-ordered quadtree (single frame) or octree children and Hamilton-apportioning the budget by
--   each child's weight, until a child holds a single cell or a single voxel. Every cell is placed
--   exactly once ('lawBudgetConserves') and every plot is grid-aligned ('lawBudgetGridAligned'). The
--   @w@ argument is the region weight (use 'regionWeight' for the field-grounded saliency).
budgetCells :: (Region -> Int) -> Region -> Cells -> Layout
budgetCells w region n
  | n <= 0           = []
  | n == 1 || single = [ Plot region (mortonKey (loCorner region)) n ]
  | otherwise        =
      let shares = apportion n (map w kids)
      in concat [ budgetCells w k s | (k, s) <- zip kids shares ]
  where
    kids   = sortBy (comparing (mortonKey . loCorner)) (children region)
    single = length kids <= 1

-- | Split a region into its (up to 8) aligned octant children, halving each axis whose span exceeds 1.
--   A single-voxel region returns itself (the recursion floor).
children :: Region -> [Region]
children r =
  [ Region xx yy tt
  | tt <- splitAxis (rT r)
  , yy <- splitAxis (rY r)
  , xx <- splitAxis (rX r) ]
  where
    splitAxis (lo, hi)
      | hi - lo <= 1 = [(lo, hi)]
      | otherwise    = let mid = lo + (hi - lo) `div` 2 in [(lo, mid), (mid, hi)]

-- | Whether @k@ widgets can take pairwise DISTINCT non-negative cell counts summing to @total@: true
--   iff @total >= k(k-1)\/2@ (the minimal staircase @0+1+..+(k-1)@). Below the floor, equal counts are
--   unavoidable and the opposition law is waived.
oppositionFeasible :: Cells -> Int -> Bool
oppositionFeasible total k = total >= k * (k - 1) `div` 2

-- | THE OPPOSITION ALLOCATOR: distribute @total@ cells across widgets so their counts are pairwise
--   DISTINCT (no two widgets take the same number of cells), in INPUT order. Each widget is a
--   @(saliency, mortonKey)@ pair. Rank by @(saliency desc, morton asc, index)@; reserve the
--   strictly-decreasing staircase @k-1, .., 0@ (already distinct); then split the surplus as an even
--   base plus a rank-monotone @+1@ remainder, so the per-rank totals stay strictly decreasing, hence
--   distinct and conserved ('lawWidgetBudgetPartitions', 'lawWidgetsOpposeEqualCounts'). When the
--   budget is below 'oppositionFeasible', falls back to plain 'apportion' (counts may tie, by necessity).
allocateWidgets :: Cells -> [(Int, Int)] -> [Cells]
allocateWidgets total ws
  | k == 0                          = []
  | not (oppositionFeasible total k) = apportion total (map fst ws)
  | otherwise                        =
      let ranked = sortBy
                     (comparing (\(i, (sal, mort)) -> (Down sal, mort, i)))
                     (zip [0 :: Int ..] ws)
          floorNeeded = k * (k - 1) `div` 2
          base = (total - floorNeeded) `div` k
          rem' = (total - floorNeeded) `mod` k
          countAtRank r = base + (k - 1 - r) + (if r < rem' then 1 else 0)
          assigned = [ (origIdx, countAtRank r)
                     | (r, (origIdx, _)) <- zip [0 :: Int ..] ranked ]
      in map snd (sortBy (comparing fst) assigned)
  where k = length ws

-- =============================================================================
-- Laws
-- =============================================================================

-- | APPORTION CONSERVES: the cell shares sum to exactly the budget, for any non-negative budget and
--   weights. No cell is created or dropped at a single split.
lawApportionConserves :: Int -> [Int] -> Bool
lawApportionConserves total ws =
  let t = abs total; vs = map abs ws
  in null vs || sum (apportion t vs) == t

-- | THE BUDGET CONSERVES (the UI twin of @lawHistTotalPreserved@): every cell of @n@ lands in exactly
--   one plot, so the plot cells sum to @n@. Demonstrated over a Morton-varying weight so the
--   apportionment is non-uniform.
lawBudgetConserves :: Region -> Int -> Bool
lawBudgetConserves r n =
  let m = abs n
  in sum (map plotCells (budgetCells demoWeight (sane r) m)) == m

-- | THE BUDGET IS GRID-ALIGNED: every plot is an aligned box inside the requested region, so the UI
--   only ever lands on whole base voxels.
lawBudgetGridAligned :: Region -> Int -> Bool
lawBudgetGridAligned r n =
  let reg = sane r
      ps  = budgetCells demoWeight reg (abs n)
  in all (\p -> aligned (plotRegion p) && plotRegion p `subRegionOf` reg && plotCells p > 0) ps

-- | DISAGREE IS ZERO ON A SPIKE AND POSITIVE ON SPREAD: a unanimous bin pulls no cells; any split bin
--   pulls some. This is the saliency twin of @lawHistUniformIsSpike@.
lawDisagreeZeroOnSpike :: [Int] -> Bool
lawDisagreeZeroOnSpike cs =
     disagree [0, 0, 7, 0] == 0     -- a spike pulls no cells
  && disagree (spikeOf cs) == 0     -- any single-level histogram is a spike
  && disagree [3, 4, 0]    == 3     -- non-mode mass = 3 + 0
  && disagree (spreadOf cs) > 0     -- two equal positives always disagree
  where
    spikeOf xs  = let m = 1 + sum (map abs xs) in [0, m, 0]
    spreadOf xs = let m = 1 + sum (map abs xs) in [m, m]

-- | THE WIDGET BUDGET PARTITIONS: the per-widget counts sum to exactly the total (across the whole
--   widget set), feasible or not, so the screen budget is conserved. The cross-widget twin of
--   'lawBudgetConserves'.
lawWidgetBudgetPartitions :: Int -> [(Int, Int)] -> Bool
lawWidgetBudgetPartitions total ws =
  let t = abs total
  in null ws || sum (allocateWidgets t (map norm ws)) == t
  where norm (s, m) = (abs s, abs m)

-- | WIDGETS OPPOSE EQUAL COUNTS: when the budget is feasible, the per-widget counts are pairwise
--   DISTINCT, even if their saliencies tie (the Morton\/index tie-break makes the ranks distinct, and
--   the staircase makes the counts distinct). This is the cell-count repulsion the owner asked for.
lawWidgetsOpposeEqualCounts :: Int -> [(Int, Int)] -> Bool
lawWidgetsOpposeEqualCounts total ws =
  let t  = abs total
      vs = map (\(s, m) -> (abs s, abs m)) ws
      k  = length vs
      cs = allocateWidgets t vs
  in not (oppositionFeasible t k) || allDistinct cs

-- | THE OPPOSITION FLOOR: @k@ widgets admit distinct counts iff @total >= k(k-1)\/2@; at exactly the
--   floor the counts are the permutation @{0,1,..,k-1}@ (the tight staircase), and one cell below it
--   distinctness is impossible.
lawWidgetOppositionFloor :: Bool
lawWidgetOppositionFloor =
     oppositionFeasible 6 4 && not (oppositionFeasible 5 4)   -- 4*3/2 = 6
  && sortAsc (allocateWidgets 6 [(10, 0), (20, 1), (30, 2), (40, 3)]) == [0, 1, 2, 3]
  && not (allDistinct (allocateWidgets 5 [(10, 0), (10, 1), (10, 2), (10, 3)]))

-- | SALIENCY ORDERS THE BUDGET: a strictly more salient widget owns strictly more cells (the staircase
--   rides the saliency rank), so the biggest budget lands on the most uncertain widget.
lawWidgetSalienceOrders :: Bool
lawWidgetSalienceOrders =
  let cs = allocateWidgets 30 [(30, 0), (10, 1), (20, 2)]   -- saliencies 30 > 20 > 10
  in cs !! 0 > cs !! 2 && cs !! 2 > cs !! 1                 -- widget0 > widget2 > widget1

-- =============================================================================
-- Internal helpers (laws only)
-- =============================================================================

-- | Whether a list has no repeated element (the opposition predicate).
allDistinct :: Eq a => [a] -> Bool
allDistinct []       = True
allDistinct (x : xs) = x `notElem` xs && allDistinct xs

-- | Ascending sort (small law inputs only).
sortAsc :: Ord a => [a] -> [a]
sortAsc = sortBy compare

-- | Map any region into a valid aligned non-empty region inside @[0,64)@ (law sanitiser).
sane :: Region -> Region
sane (Region a b c) = Region (iv a) (iv b) (iv c)
  where
    iv (p, q) = let lo = ((min p q) `mod` 64 + 64) `mod` 64
                    hi = lo + 1 + (abs (q - p) `mod` (64 - lo))
                in (lo, hi)

-- | A deterministic Morton-varying region weight, so 'budgetCells' laws exercise a non-uniform split.
demoWeight :: Region -> Int
demoWeight r = 1 + (mortonKey (loCorner r) `mod` 7)

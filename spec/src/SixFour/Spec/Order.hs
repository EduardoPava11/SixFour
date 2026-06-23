{- |
Module      : SixFour.Spec.Order
Description : The centralized location-order authority — slot ↦ screen rank.

Every grid view places palette slots into screen cells. Historically each did its
own thing (row-major in @PixelGrid@, 2-axis sort in @GridAxis@, tree in-order in
the address picker). This module is the single authority that answers "where does
slot @i@ go?" as one lawful algebraic object.

== The algebra

An 'Order' is a finite permutation: a bijection on @[0..n-1]@ that assigns each
palette SLOT a screen RANK (the linear cell position 0,1,2,…). Permutations form a
group under composition, captured by the 'FinitePerm' type class — the ORDER role
of the GridScript @Stage@ spine ('SixFour.Spec.Pipeline'). This is HKT-free and
GHC-boot-only (lists + @Data.List.sort@); every carrier is finite, so the group
laws are checked as ordinary properties, not encoded in types.

== Where the orders come from

  * 'rowMajor' — the identity permutation (rank = slot); the default @PixelGrid@ fill.
  * 'axisOrder' — DERIVED from the already-proven 'GridAxis.gridLayout' two-axis
    sort, so the bijection guarantee is inherited, not re-litigated
    ('GridAxis.lawLayoutIsBijection').

Separation of concerns: ORDER answers slot→rank only. The geometric placement
rank→rect is 'SixFour.Spec.Lattice' (EMBEDDING); colour rank→sRGB8 is
'SixFour.Spec.CellFiber' (COLOR). The three compose as @EMBEDDING :> COLOR :> ORDER@.
-}
-- COMPARTMENT: SWIFT-COREAI | tag:DisplaySide
module SixFour.Spec.Order
  ( -- * The permutation algebra
    FinitePerm(..)
  , Order(..)
    -- * Queries
  , rankOf
  , slotAt
    -- * Canonical orders
  , rowMajor
  , serpentine
  , fromGrid
  , axisOrder
    -- * Laws
  , lawPermBijection
  , lawSerpentineBijection
  , lawIdentityLeft
  , lawIdentityRight
  , lawComposeAssoc
  , lawInverseLeft
  , lawInverseRight
  , lawRowMajorIsIdentity
  , lawAxisOrderBijection
  ) where

import Data.List (sort)

import SixFour.Spec.GridAxis (GridAxis, IndexedColor, gridLayout)

-- | The finite-permutation algebra: the group of bijections on @[0..n-1]@ under
-- composition. Instances must satisfy the group laws (identity, associativity,
-- inverse) stated below over the carrier.
class FinitePerm p where
  -- | The identity permutation on @n@ elements.
  identity :: Int -> p
  -- | @compose g f@ is "@f@ then @g@": @apply (compose g f) i = apply g (apply f i)@.
  compose  :: p -> p -> p
  -- | The group inverse.
  invert   :: p -> p
  -- | Where element @i@ maps to.
  apply    :: p -> Int -> Int
  -- | The carrier size @n@.
  size     :: p -> Int

-- | The canonical ORDER carrier. @Order rs@ holds @rs !! slot = rank@: the screen
-- rank each palette slot occupies. A bijection on @[0..n-1]@. The single source of
-- truth for "slot → screen rank".
newtype Order = Order { rankList :: [Int] }
  deriving (Eq, Show)

instance FinitePerm Order where
  identity n             = Order [0 .. n - 1]
  apply (Order rs) i     = rs !! i
  size  (Order rs)       = length rs
  compose (Order g) (Order f) = Order [ g !! (f !! i) | i <- [0 .. length f - 1] ]
  -- Inverse: @zip rs [0..]@ is @[(rank, slot)]@; sorting by rank then taking the
  -- slots yields the rank→slot list, which is exactly the inverse permutation.
  invert (Order rs)      = Order (map snd (sort (zip rs [0 ..])))

-- | The screen rank a palette slot occupies (= 'apply').
rankOf :: Order -> Int -> Int
rankOf = apply

-- | The palette slot living at a given screen rank (= 'apply' of the inverse).
slotAt :: Order -> Int -> Int
slotAt o = apply (invert o)

-- | Row-major order: rank = slot. Identical to @identity n@ (see
-- 'lawRowMajorIsIdentity'); named for the call site that wants the default fill.
rowMajor :: Int -> Order
rowMajor = identity

-- | The serpentine (boustrophedon) order over a @side×side@ grid: row 0 sweeps
-- left→right, row 1 right→left, alternating. The GIFA "resolve sweep" fill order —
-- so the loading state reads as ONE continuous wipe across the cell grid (no
-- carriage-return jump between rows). @rankOf slot@ is the sweep position of the
-- row-major @slot@; a bijection (each row is a contiguous block, merely reversed on
-- odd rows), so 'lawPermBijection' holds.
serpentine :: Int -> Order
serpentine side =
  Order [ serpRank (i `div` side) (i `mod` side) | i <- [0 .. side * side - 1] ]
  where
    serpRank row col
      | even row  = row * side + col
      | otherwise = row * side + (side - 1 - col)

-- | Build an 'Order' from a 'GridAxis.gridLayout' result. @grid !! row !! col@ is
-- the slot at screen cell @(row,col)@, whose row-major rank is @row*side + col@.
-- So the flattened grid is @rank → slot@; inverting gives @slot → rank@ = the
-- 'Order'. An empty grid (wrong-size palette) yields the empty 'Order'.
fromGrid :: [[Int]] -> Order
fromGrid grid = Order (map snd (sort (zip flat [0 ..])))
  where flat = concat grid          -- flat !! rank = slot

-- | The 2-axis order: the user-assignable @(x,y)@ layout, derived from the proven
-- 'GridAxis.gridLayout'. Its bijection property is inherited (see
-- 'lawAxisOrderBijection').
axisOrder :: GridAxis -> GridAxis -> [IndexedColor] -> Order
axisOrder x y colors = fromGrid (gridLayout x y colors)

-- * Laws

-- | An 'Order' is a permutation: its ranks are exactly @[0..n-1]@ (no hole, no dup).
lawPermBijection :: Order -> Bool
lawPermBijection (Order rs) = sort rs == [0 .. length rs - 1]

-- | Left identity: @compose (identity n) p == p@.
lawIdentityLeft :: Order -> Bool
lawIdentityLeft p = compose (identity (size p)) p == p

-- | Right identity: @compose p (identity n) == p@.
lawIdentityRight :: Order -> Bool
lawIdentityRight p = compose p (identity (size p)) == p

-- | Associativity: @compose (compose h g) f == compose h (compose g f)@ (same size).
lawComposeAssoc :: Order -> Order -> Order -> Bool
lawComposeAssoc f g h =
  compose (compose h g) f == compose h (compose g f)

-- | Left inverse: @compose (invert p) p == identity n@.
lawInverseLeft :: Order -> Bool
lawInverseLeft p = compose (invert p) p == identity (size p)

-- | Right inverse: @compose p (invert p) == identity n@.
lawInverseRight :: Order -> Bool
lawInverseRight p = compose p (invert p) == identity (size p)

-- | Row-major is the identity permutation.
lawRowMajorIsIdentity :: Int -> Bool
lawRowMajorIsIdentity n = rowMajor n == identity n

-- | The serpentine order is a permutation (no cell visited twice or skipped).
lawSerpentineBijection :: Int -> Bool
lawSerpentineBijection side = lawPermBijection (serpentine side)

-- | The 2-axis order inherits the 'GridAxis.gridLayout' bijection guarantee.
lawAxisOrderBijection :: GridAxis -> GridAxis -> [IndexedColor] -> Bool
lawAxisOrderBijection x y colors = lawPermBijection (axisOrder x y colors)

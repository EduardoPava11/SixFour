{- |
Module      : SixFour.Spec.LBalanceOperator
Description : L = the universal balance operator — the coarse/DC value of an octant, made first-class.

Makes "L is the universal balance" ("SixFour.Spec.XYTLabDuality") a concrete spec
entity: 'lBalance' is the coarse/DC value an octant collapses to
("SixFour.Spec.OctreeCell" 'liftOct'), the balance point across the eight children
at every scale. It is the @t≅L@ universal factor of the @Balance ⊣ Search@ split —
the value the L white-balance + dynamic-range operator drives, /below/ the A/B
chroma search.

Two properties pin it as a true balance:

  * 'lawBalanceInRange' — the balance is GAMUT-CLOSED: it lies within the range of
    its eight children, so balancing can never invent an out-of-gamut white (cf.
    @RGBTLift.lawCoarseInBlockRange@ / @CubeLadder.lawDistillCoarseGamutClosed@).
  * 'lawBalanceFixedOnConstant' — a uniform (already-balanced) octant is its own
    balance: @lBalance (V8 v…v) = v@. This is the floor fixpoint (the
    @zero-genome == floor@ identity at a single cell).

Intent (not yet cross-proved here): this operator unifies the maximin floor
("SixFour.Spec.Collapse"), the lightness-sum beauty term ("SixFour.Spec.Loss"),
and the σ-pair midpoint ("SixFour.Spec.SigmaPairHead") under one balance map — to
be wired as those modules are refactored onto the octree.

GHC-boot-only. Laws are exported predicates, QuickCheck'd in @Properties.LBalanceOperator@.
-}
-- COMPARTMENT: ZIG-FLOOR | tag:DeviceTag
module SixFour.Spec.LBalanceOperator
  ( -- * The balance operator
    lBalance
    -- * Laws (QuickCheck'd in @Properties.LBalanceOperator@)
  , lawBalanceInRange
  , lawBalanceFixedOnConstant
  , lawBalanceGolden
  ) where

import SixFour.Spec.OctreeCell (V8(..), liftOct, ocCoarse)

-- | The L balance: the coarse/DC value an octant collapses to (the @LLL@ band).
lBalance :: V8 Int -> Int
lBalance = ocCoarse . liftOct

-- | The balance is gamut-closed: it lies within the range of the eight children.
lawBalanceInRange :: V8 Int -> Bool
lawBalanceInRange v =
  let V8 a b c d e f g h = v
      xs = [a, b, c, d, e, f, g, h]
  in minimum xs <= lBalance v && lBalance v <= maximum xs

-- | A uniform (already-balanced) octant is its own balance — the floor fixpoint.
lawBalanceFixedOnConstant :: Int -> Bool
lawBalanceFixedOnConstant x = lBalance (V8 x x x x x x x x) == x

-- | Golden pin (matches the @OctreeCell@ coarse golden): cross-language reproducible.
lawBalanceGolden :: Bool
lawBalanceGolden = lBalance (V8 10 20 30 44 10 20 30 44) == 26

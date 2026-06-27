module Properties.CellNudge (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.CellNudge

tests :: TestTree
tests = testGroup "CellNudge (corrected nudge: 9-at-cell over a 6-DOF voxel basis, gauge-explicit)"
  [ testProperty "a cell exposes 9 channels (the ChannelProduct pairs)" lawNineChannelsAtCell
  , testProperty "the 9 are honest at the cell (rank-3 aggregate), 6 at the voxel" lawNineHonestAtCell
  , testProperty "zero budget = the byte-exact floor" $ forAll (choose (0, 99)) lawZeroCellBudgetIsFloor
  , testProperty "painting one channel in one cell is local" lawPaintOnePairIsLocal
  , testProperty "one 16^3 cell governs a 4096-leaf 256^3 subtree (two twiceness rungs)"
      lawCellGovernsSuperResSubtree
  , testProperty "the training loss is the cell-aggregate, not per-voxel" lawLossIsCellAggregate
  , testProperty "which 9 (colour-by-space vs phi6 dual) is an explicit gauge" lawGaugeExplicit
  ]

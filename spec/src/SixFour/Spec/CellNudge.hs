{- |
Module      : SixFour.Spec.CellNudge
Description : The CORRECTED nudge (Option C, theorem-grounded): a per-cell NINE-channel paint over the 16³ COARSE captured grid, honest at the cell because the cell-aggregate comparison is full rank 3 ("SixFour.Spec.NudgeRankTheorem"), while the intrinsic per-voxel basis stays the 6-D P6 generator. Supersedes "SixFour.Spec.PonderBudget"'s single-scalar / 256³-surface guess on the two axes the code proved wrong: the SURFACE is the 16³ control grid the user actually paints (not the 256³ they cannot see), and the per-cell budget is a 9-VECTOR over the "SixFour.Spec.ChannelProduct" pairs (not one scalar).

What the theorems fixed (all proven in "SixFour.Spec.NudgeRankTheorem"):
  * 9 honest AT THE CELL: 'lawNineHonestAtCell' = @lawCellAggregateReachesRank3@ (the cell-aggregate
    @A = Σ colour ⊗ space@ reaches rank 3, 9 independent entries) AND @lawNineIndependentAtCellNotVoxel@
    (rank 1 / 6 DOF per voxel, so the 9 surface is legitimate ONLY bound to the cell).
  * The LOSS is the cell-aggregate: 'lawLossIsCellAggregate' = @lawHeldOutLossIsCellAggregateNotPerVoxel@
    (a mispaired-chroma prediction is invisible per-voxel but errs on the aggregate). "SixFour.Spec.MatrixTarget"
    must score the aggregate, not per voxel.
  * The 9 are GAUGE-EXPLICIT: 'lawGaugeExplicit' = @lawValueSplitIsPhi6Gauge@ (which 9 — colour-by-space
    or the φ6 dual — is a gauge choice, carried as a toggle, never silently privileging colour).

The BRUSH is unchanged (the octant twiceness of "SixFour.Spec.PonderBudget"): one painted 16³ cell governs
its @(256/16)³ = twicenessSpan² = 4096@-leaf subtree of the 256³ output (two twiceness rungs 16→64→256),
'lawCellGovernsSuperResSubtree'. The zero field is the byte-exact floor; painting is local and clamped.
Pure-spec, emits no golden.
-}
-- COMPARTMENT: MLX-MODEL | tag:MacTag
module SixFour.Spec.CellNudge
  ( -- * The 9-channel per-cell budget over the 16^3 control grid
    CellBudget
  , nPairs
  , controlGridSide
  , superResSide
  , cellSubtreeLeaves
  , emptyCellBudget
  , paintCellPair
    -- * Laws
  , lawNineChannelsAtCell
  , lawNineHonestAtCell
  , lawZeroCellBudgetIsFloor
  , lawPaintOnePairIsLocal
  , lawCellGovernsSuperResSubtree
  , lawLossIsCellAggregate
  , lawGaugeExplicit
  ) where

import SixFour.Spec.ChannelProduct   (pairings)
import SixFour.Spec.PonderBudget      (twicenessSpan)
import SixFour.Spec.NudgeRankTheorem
  ( lawCellAggregateReachesRank3, lawNineIndependentAtCellNotVoxel
  , lawHeldOutLossIsCellAggregateNotPerVoxel, lawValueSplitIsPhi6Gauge )

-- | The paint field: one budget VECTOR per coarse cell. Outer = cells (the 16³ control grid,
-- flattened Morton-order); inner = a budget per "SixFour.Spec.ChannelProduct" channel-pair.
type CellBudget = [[Int]]

-- | The number of independently-paintable channels per cell: the nine colour-by-space pairs.
nPairs :: Int
nPairs = length pairings

-- | The coarse control grid side (the captured 64³ analysed down two octant levels to 16³, the scale
-- the user paints on).
controlGridSide :: Int
controlGridSide = 16

-- | The invented output side (two twiceness rungs above the control grid: 16 → 64 → 256).
superResSide :: Int
superResSide = 256

-- | The number of 256³ output leaves one painted 16³ cell governs: @(256/16)³ = 4096 = twicenessSpan²@
-- (two octant-twiceness rungs).
cellSubtreeLeaves :: Int
cellSubtreeLeaves = (superResSide `div` controlGridSide) ^ (3 :: Int)

-- | An empty budget over @nCells@ cells: every channel zero everywhere (the byte-exact floor).
emptyCellBudget :: Int -> CellBudget
emptyCellBudget nCells = replicate nCells (replicate nPairs 0)

-- | Paint cell @c@, channel-pair @p@ (0..8), to budget value @v@ (clamped non-negative). Only that
-- one (cell, pair) entry moves: the user nudges ONE chroma-by-space channel in ONE region.
paintCellPair :: CellBudget -> Int -> Int -> Int -> CellBudget
paintCellPair b c p v =
  [ if ci == c
      then [ if pj == p then max 0 v else bp | (pj, bp) <- zip [0 ..] row ]
      else row
  | (ci, row) <- zip [0 ..] b ]

-- ---------------------------------------------------------------------------
-- Laws
-- ---------------------------------------------------------------------------

-- | A cell exposes exactly NINE paint channels, the "SixFour.Spec.ChannelProduct" pairs
-- (@L:t,L:x,L:y,a:x,a:y,a:t,b:x,b:y,b:t@).
lawNineChannelsAtCell :: Bool
lawNineChannelsAtCell = nPairs == 9 && nPairs == length pairings

-- | The nine channels are HONEST at the cell: the cell-aggregate reaches rank 3 (nine independent
-- entries) while a single voxel is rank 1 (six DOF), so the 9-surface is legitimate exactly because
-- it is bound to the cell. Delegates the "SixFour.Spec.NudgeRankTheorem" proofs.
lawNineHonestAtCell :: Bool
lawNineHonestAtCell = lawCellAggregateReachesRank3 && lawNineIndependentAtCellNotVoxel

-- | The zero field is the byte-exact FLOOR: an empty budget paints no channel in any cell.
lawZeroCellBudgetIsFloor :: Int -> Bool
lawZeroCellBudgetIsFloor n0 =
  let n = abs n0 `mod` 100
  in all (all (== 0)) (emptyCellBudget n)

-- | Painting one channel in one cell is LOCAL: exactly that (cell, pair) entry changes, nothing else.
lawPaintOnePairIsLocal :: Bool
lawPaintOnePairIsLocal =
  let b = paintCellPair (emptyCellBudget 4) 1 3 7
  in (b !! 1) !! 3 == 7 && sum (map sum b) == 7

-- | One painted 16³ control cell governs a @4096@-leaf subtree of the 256³ output: @(256/16)³ ==
-- twicenessSpan² == 4096@, the two octant-twiceness rungs (16 → 64 → 256). Ties the paint scale to the
-- self-similar reconstruct, not an arbitrary mapping.
--
-- HONEST LABEL: this is a DIMENSIONAL IDENTITY (the self-similar scale @(256/16)³ = 8² = 4096@), not a
-- behavioural theorem — every operand is a compile-time constant. It is kept (not retired) because it is
-- a real, load-bearing consistency check: "SixFour.Spec.ModelIO" consumes it (@lawNudgeGovernsSuperRes@)
-- to pin the paint→subtree mapping, so a wrong control-grid or output side would break it. See
-- @SIXFOUR-MODEL.md@ for its place in the load-bearing-vs-contract taxonomy.
lawCellGovernsSuperResSubtree :: Bool
lawCellGovernsSuperResSubtree =
  cellSubtreeLeaves == twicenessSpan * twicenessSpan
  && cellSubtreeLeaves == 4096
  && controlGridSide * 16 == superResSide

-- | The training loss the nudge is honest against is the cell-AGGREGATE, not per-voxel: a
-- chroma-by-space mispairing is invisible per voxel but errs on the aggregate. Delegates
-- "SixFour.Spec.NudgeRankTheorem".
lawLossIsCellAggregate :: Bool
lawLossIsCellAggregate = lawHeldOutLossIsCellAggregateNotPerVoxel

-- | Which nine channels (colour-by-space vs the φ6 dual) is a GAUGE choice, carried explicitly so the
-- surface names a fixed carrier rather than silently privileging colour. Delegates
-- "SixFour.Spec.NudgeRankTheorem" @lawValueSplitIsPhi6Gauge@.
lawGaugeExplicit :: Bool
lawGaugeExplicit = lawValueSplitIsPhi6Gauge

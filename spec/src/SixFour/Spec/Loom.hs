{- |
Module      : SixFour.Spec.Loom
Description : the user AUTHORING verb — hand-folding the 256-cell palette (FUNCTION-DESIGN §5, the 2⁸ form).

The look-NN's AUTHORING function (`docs/L-NN-FUNCTION-DESIGN.md` §5): the user authors the
global 256-colour look by **hand-folding** the grid one binary @2→1@ merge at a time, to
whatever posterization N they choose, then emits the GIF. This module formalises that verb.

Unlike 'SixFour.Spec.PairTree' (the FIXED balanced depth-8 Haar tree), the loom is an
**unbalanced, user-driven merge forest**: the user folds *any* two active cells, in *any*
order, to *any* active count. A 'Loom' is the list of currently-active cells (forest roots);
each merge is a 'Branch' that KEEPS both children, so 'split' is exactly lossless — the
formal content of "colour is banked, not deleted; undo is free."

  * 'fold'  i j  — merge active cells i,j into their Haar midpoint @m = ½(cᵢ+cⱼ)@ (the
    shown colour), banking the detail @d = ½(cᵢ−cⱼ)@ implicitly (the children are retained).
    This is the @Ω@-at-@t=0@ obfuscation of 'SixFour.Spec.Obfuscation' lifted to the loom.
  * 'split' i    — pull a 'Branch' back into its two exact children (lossless undo).
  * A 'FoldProgram' is the recorded sequence of folds; 'replay' rebuilds the loom from the
    initial palette + the program ALONE — the anti-automation contract (the authored palette
    is reachable ONLY via a recorded fold sequence; there is no "set the palette directly").

No forced depth, no forced fold-count: 'activeCount' can be any N ∈ [1, |palette|].

Laws live in @Properties.Loom@. All laws are exact (no float tolerance): split keeps the
children verbatim, and midpoint/conservation move OKLab values without recomputation.
-}
-- COMPARTMENT: SWIFT-COREAI | tag:DisplaySide | STRADDLER
module SixFour.Spec.Loom
  ( -- * The merge forest
    Node(..)
  , Loom
  , nodeColor
  , nodeDetail
  , leavesOf
    -- * Loom state
  , initLoom
  , loomColors
  , activeCount
    -- * The authoring verbs
  , fold
  , split
    -- * Recorded programs (the anti-automation contract)
  , FoldProgram
  , replay
    -- * Haar primitives (shared with Obfuscation/PairTree)
  , midpoint
  , haarDetail
  ) where

import SixFour.Spec.Color (OKLab(..))

-- =============================================================================
-- The merge forest
-- =============================================================================

-- | An active loom cell: either an original palette 'Leaf', or a 'Branch' that fused
-- two cells (KEEPING both children, so the fold is losslessly reversible).
data Node = Leaf !OKLab | Branch !Node !Node
  deriving (Eq, Show)

-- | The Haar low-pass midpoint @m = ½(c₀+c₁)@ — the colour a fold SHOWS.
midpoint :: OKLab -> OKLab -> OKLab
midpoint (OKLab l1 a1 b1) (OKLab l2 a2 b2) =
  OKLab ((l1 + l2) / 2) ((a1 + a2) / 2) ((b1 + b2) / 2)

-- | The Haar high-pass detail @d = ½(c₀−c₁)@ — the "banked" half-difference. (Here it is
-- recoverable from the retained children; exposed for the bleed/reveal tie and the port.)
haarDetail :: OKLab -> OKLab -> OKLab
haarDetail (OKLab l1 a1 b1) (OKLab l2 a2 b2) =
  OKLab ((l1 - l2) / 2) ((a1 - a2) / 2) ((b1 - b2) / 2)

-- | The colour an active cell SHOWS: a leaf shows itself; a branch shows the midpoint of
-- its two children's shown colours (the Haar parent).
nodeColor :: Node -> OKLab
nodeColor (Leaf c)     = c
nodeColor (Branch l r) = midpoint (nodeColor l) (nodeColor r)

-- | The banked detail of a cell — 'Nothing' for a leaf (nothing fused), the Haar detail
-- of its two children for a branch.
nodeDetail :: Node -> Maybe OKLab
nodeDetail (Leaf _)     = Nothing
nodeDetail (Branch l r) = Just (haarDetail (nodeColor l) (nodeColor r))

-- | The original palette leaves under a cell (the conserved quantity).
leavesOf :: Node -> [OKLab]
leavesOf (Leaf c)     = [c]
leavesOf (Branch l r) = leavesOf l ++ leavesOf r

-- =============================================================================
-- Loom state
-- =============================================================================

-- | The currently-active cells (the roots of the merge forest). Its length is the user's
-- current posterization (how many distinct colours the look has right now).
type Loom = [Node]

-- | Start: every palette colour is its own active leaf (256 cells, no folds yet).
initLoom :: [OKLab] -> Loom
initLoom = map Leaf

-- | The current shown palette — one colour per active cell.
loomColors :: Loom -> [OKLab]
loomColors = map nodeColor

-- | How many distinct colours the look currently has (the posterization N).
activeCount :: Loom -> Int
activeCount = length

inRange :: Int -> Loom -> Bool
inRange i loom = i >= 0 && i < length loom

-- =============================================================================
-- The authoring verbs
-- =============================================================================

-- | FOLD: merge the active cells at indices @i@ and @j@ into one 'Branch' (their Haar
-- midpoint is the new shown colour). Total: out-of-range or @i==j@ is a no-op. The merged
-- cell is appended at the end; 'activeCount' drops by one.
fold :: Int -> Int -> Loom -> Loom
fold i j loom
  | not (inRange i loom) || not (inRange j loom) || i == j = loom
  | otherwise =
      let lo   = min i j
          hi   = max i j
          ni   = loom !! lo
          nj   = loom !! hi
          rest = [ n | (k, n) <- zip [0 ..] loom, k /= lo, k /= hi ]
      in rest ++ [Branch ni nj]

-- | SPLIT: pull the 'Branch' at index @i@ back into its two exact children (lossless undo).
-- A 'Leaf' (or out-of-range index) is a no-op — there is nothing banked to un-fold.
split :: Int -> Loom -> Loom
split i loom
  | not (inRange i loom) = loom
  | otherwise = case loom !! i of
      Leaf _     -> loom
      Branch l r ->
        let (pre, rest) = splitAt i loom
        in pre ++ [l, r] ++ drop 1 rest

-- =============================================================================
-- Recorded programs — the anti-automation contract
-- =============================================================================

-- | A recorded fold sequence (each entry the @(i,j)@ chosen at that step).
type FoldProgram = [(Int, Int)]

-- | Rebuild a loom from the initial palette and a recorded program ALONE. The authored
-- palette is therefore a pure function of (palette, program) — the only path to a loom
-- state is a recorded sequence of user folds (no "set the palette directly" exists).
replay :: [OKLab] -> FoldProgram -> Loom
replay pal = foldl (\lm (i, j) -> fold i j lm) (initLoom pal)

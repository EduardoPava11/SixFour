-- | Laws for 'SixFour.Spec.Loom': the user AUTHORING verb (FUNCTION-DESIGN §5, the 2⁸ fold).
-- The user hand-folds the 256-cell palette one binary 2→1 merge at a time; folds are
-- lossless (split is exact undo), colour is conserved (banked, not deleted), and the
-- authored palette is reachable only via a recorded fold sequence. All laws are EXACT.
module Properties.Loom (tests) where

import Data.List (sortOn)

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.Color (OKLab(..))
import SixFour.Spec.Loom

genOKLab :: Gen OKLab
genOKLab = OKLab <$> choose (0, 1) <*> choose (-0.4, 0.4) <*> choose (-0.4, 0.4)

-- Small palettes keep the forests cheap; ≥2 leaves so a fold is always possible.
genLeaves :: Gen [OKLab]
genLeaves = do
  n  <- choose (2, 16)
  vectorOf n genOKLab

key :: OKLab -> (Double, Double, Double)
key (OKLab l a b) = (l, a, b)

-- multiset equality on OKLab (order-independent)
sameColors :: [OKLab] -> [OKLab] -> Bool
sameColors xs ys = sortOn key xs == sortOn key ys

eqLab :: OKLab -> OKLab -> Bool
eqLab (OKLab l1 a1 b1) (OKLab l2 a2 b2) = l1 == l2 && a1 == a2 && b1 == b2

-- fold the first two active cells repeatedly (always valid while ≥2 remain)
foldFront :: Int -> Loom -> Loom
foldFront k loom = iterate (fold 0 1) loom !! k

tests :: TestTree
tests = testGroup "Loom (the AUTHORING fold/split verb)"
  [ -- INIT: the loom starts as the palette, one active leaf per colour.
    testProperty "INIT: loomColors (initLoom pal) ≡ pal ∧ activeCount ≡ |pal|" $
      forAll genLeaves $ \pal ->
        loomColors (initLoom pal) == pal && activeCount (initLoom pal) == length pal

    -- FOLD-COUNT: one fold removes one active cell.
  , testProperty "FOLD-COUNT: a valid fold drops activeCount by 1" $
      forAll genLeaves $ \pal ->
        activeCount (fold 0 1 (initLoom pal)) == length pal - 1

    -- MIDPOINT: the folded cell SHOWS the Haar midpoint of the two it merged.
  , testProperty "MIDPOINT: folded cell colour ≡ ½(c₀+c₁)" $
      forAll genLeaves $ \pal ->
        let folded = fold 0 1 (initLoom pal)
        in eqLab (nodeColor (last folded)) (midpoint (pal !! 0) (pal !! 1))

    -- LOSSLESS: fold then split the merged cell restores the WHOLE palette exactly.
  , testProperty "LOSSLESS: split ∘ fold restores every colour (exact undo)" $
      forAll genLeaves $ \pal ->
        let lm     = initLoom pal
            folded = fold 0 1 lm
            back   = split (activeCount folded - 1) folded
        in sameColors (loomColors back) pal

    -- RETENTION: the split returns the EXACT child nodes (chroma banked, not recomputed).
  , testProperty "RETENTION: split returns the exact banked children" $
      forAll genLeaves $ \pal ->
        let folded = fold 0 1 (initLoom pal)
            back   = split (activeCount folded - 1) folded
        in Leaf (pal !! 0) `elem` back && Leaf (pal !! 1) `elem` back

    -- CONSERVATION: folding never loses or invents a leaf (the look is reshaped, not lost).
  , testProperty "CONSERVATION: folds preserve the leaf multiset" $
      forAll genLeaves $ \pal ->
        let lm = foldFront 1 (initLoom pal)
        in sameColors (concatMap leavesOf lm) pal

    -- NO-FORCED-DEPTH: the user can fold to ANY posterization N ∈ [1, |pal|].
  , testProperty "NO-FORCED-DEPTH: k folds reach activeCount |pal|−k for any k" $
      forAll genLeaves $ \pal ->
        forAll (choose (0, length pal - 1)) $ \k ->
          activeCount (foldFront k (initLoom pal)) == length pal - k

    -- SPLIT-LEAF-NOOP: nothing is banked behind a leaf, so splitting it does nothing.
  , testProperty "SPLIT-LEAF-NOOP: splitting an all-leaf loom is identity" $
      forAll genLeaves $ \pal ->
        forAll (choose (0, length pal - 1)) $ \i ->
          loomColors (split i (initLoom pal)) == pal

    -- ANTI-AUTOMATION: the authored palette is a pure function of (palette, program).
  , testProperty "REPLAY: the look is determined by (palette, recorded folds) alone" $
      forAll genLeaves $ \pal ->
        forAll (choose (0, length pal - 1)) $ \k ->
          let prog = replicate k (0, 1)            -- a recorded fold program
          in loomColors (replay pal prog) == loomColors (foldFront k (initLoom pal))
             && activeCount (replay pal prog) == length pal - k

    -- REPLAY-EMPTY: an empty program leaves the palette untouched.
  , testProperty "REPLAY: the empty program is the untouched palette" $
      forAll genLeaves $ \pal -> loomColors (replay pal []) == pal
  ]

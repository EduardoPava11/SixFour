module Properties.SignificanceFixed (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.Significance      (minPopulation)
import SixFour.Spec.SignificanceFixed (rescueQ16, cellsQ16, isqrtInt, distSqQ16)

-- A small feasible scenario: K slots, P pixels, an imbalanced initial labelling
-- that leaves most slots empty. Deterministic, generated from a seed so the
-- properties are reproducible.
mkScenario :: Int -> Int -> Int -> ([(Int,Int,Int)], [Int], [(Int,Int,Int)])
mkScenario k p seed =
  let pixel i = let x = (i * 2654435761 + seed) `mod` 65536
                    y = (i * 40503     + seed) `mod` 65536
                    z = (i * 1000003   + seed) `mod` 65536
                in (x, y, z)
      pixels    = [ pixel i | i <- [0 .. p - 1] ]
      centroids = [ pixel (i * 7 + 1) | i <- [0 .. k - 1] ]
      -- imbalanced: only the first 3 slots are used initially → 3..k-1 deficient
      indices   = [ i `mod` 3 | i <- [0 .. p - 1] ]
  in (centroids, indices, pixels)

countSlots :: Int -> [Int] -> [Int]
countSlots k ixs = [ length (filter (== s) ixs) | s <- [0 .. k - 1] ]

tests :: TestTree
tests = testGroup "SignificanceFixed"
  [ testProperty "isqrtInt is the exact floor sqrt (r² ≤ n < (r+1)²)" $
      \(NonNegative n') ->
        let n = n' `mod` 1000000000
            r = isqrtInt n
        in r * r <= n && (r + 1) * (r + 1) > n

  , testProperty "rescueQ16 makes every slot ≥ minPopulation (feasible shape)" $
      \(Positive s) ->
        let k = 16; p = 64
            (cs, ix, px) = mkScenario k p (s `mod` 9973)
            out = rescueQ16 k cs ix px
        in all (>= minPopulation) (countSlots k out)

  , testProperty "rescueQ16 conserves mass (length P, every label in [0,k))" $
      \(Positive s) ->
        let k = 16; p = 64
            (cs, ix, px) = mkScenario k p (s `mod` 9973)
            out = rescueQ16 k cs ix px
        in length out == p && all (\v -> v >= 0 && v < k) out

  , testProperty "rescueQ16 is idempotent (a significant assignment is untouched)" $
      \(Positive s) ->
        let k = 16; p = 64
            (cs, _, px) = mkScenario k p (s `mod` 9973)
            once = rescueQ16 k cs [ i `mod` k | i <- [0 .. p - 1] ] px  -- 4 each ⇒ all ≥ 2
        in rescueQ16 k cs once px == once

  , testProperty "cellsQ16: counts sum to P and equal the assignment histogram" $
      \(Positive s) ->
        let k = 16; p = 64
            (cs, ix, px) = mkScenario k p (s `mod` 9973)
            out   = rescueQ16 k cs ix px
            cells = cellsQ16 k cs out px
            cnts  = [ c | (_,_,_,_,_,_,c) <- cells ]
        in sum cnts == p && cnts == countSlots k out

  , testProperty "distSqQ16 is symmetric and zero on the diagonal" $
      \(a, b, c) (d, e, f) ->
        let x = (a `mod` 65536, b `mod` 65536, c `mod` 65536)
            y = (d `mod` 65536, e `mod` 65536, f `mod` 65536)
        in distSqQ16 x y == distSqQ16 y x && distSqQ16 x x == 0
  ]

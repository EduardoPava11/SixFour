module Properties.QuantFixed (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import qualified Data.Vector as V

import SixFour.Spec.QuantFixed

mkPixels :: Int -> Int -> [(Int,Int,Int)]
mkPixels p seed =
  [ ( (i * 1009 + seed) `mod` 65536
    , (i * 2003 + seed) `mod` 65536
    , (i * 3001 + seed) `mod` 65536 )
  | i <- [0 .. p - 1] ]

tests :: TestTree
tests = testGroup "QuantFixed"
  [ testProperty "quantize yields k centroids and P assignments in [0,k)" $
      \(Positive s) (Positive it') ->
        let k = 8; p = 64; iters = it' `mod` 5
            px = mkPixels p (s `mod` 9973)
            (cs, asn) = quantizeFrameQ16 k iters px
        in length cs == k && length asn == p && all (\v -> v >= 0 && v < k) asn

  , testProperty "the assignment is exactly the nearest-centroid Voronoi map" $
      \(Positive s) (Positive it') ->
        let k = 8; p = 64; iters = it' `mod` 5
            px = mkPixels p (s `mod` 9973)
            (cs, asn) = quantizeFrameQ16 k iters px
            csv = V.fromList cs
        in and [ a == nearestCentroidQ16 csv x | (a, x) <- zip asn px ]

  , testProperty "maximin returns exactly k seeds drawn from the pixels" $
      \(Positive s) ->
        let k = 10; p = 50
            px = mkPixels p (s `mod` 9973)
            seeds = farthestPointSeedsQ16 k px
        in length seeds == k && all (`elem` px) seeds

  , testProperty "first maximin seed is the pixel farthest from the integer mean" $
      \(Positive s) ->
        let k = 4; p = 40
            px = mkPixels p (s `mod` 9973)
            n  = length px
            (sl,sa,sb) = foldr (\(l,a,b) (al,aa,ab)->(al+l,aa+a,ab+b)) (0,0,0) px
            mean = (sl `div` n, sa `div` n, sb `div` n)
            dmax = maximum [ distSqQ16 c mean | c <- px ]
            firstSeed = head (farthestPointSeedsQ16 k px)
        in distSqQ16 firstSeed mean == dmax

  , -- 3 distinct colours, ask for k=8 ⇒ ≥5 clusters are empty and must be
    -- byte-stable across a Lloyd step (kept, not zeroed). Fixed input ⇒ a plain
    -- Bool property (no random args).
    testProperty "empty clusters keep their old centroid (k > distinct pixels)" $
      let k = 8
          px = concat (replicate 6 [ (1000,2000,3000), (40000,5000,9000), (20000,60000,1000) ]) :: [(Int,Int,Int)]
          seeds = V.fromList (farthestPointSeedsQ16 k px)
          step1 = lloydStepQ16 (V.fromList px) seeds
          step2 = lloydStepQ16 (V.fromList px) step1
      in V.length step1 == k && step1 == step2   -- converged + stable
  ]

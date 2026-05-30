module Properties.SpatialDither (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.SpatialDither

-- Deterministic small frame: side×side pixels, k centroids, a threshold slice.
mkFrame :: Int -> Int -> Int -> ([(Int,Int,Int)], [Int], [(Int,Int,Int)])
mkFrame side k seed =
  let p = side * side
      px i = ( (i * 2654435761 + seed) `mod` 65536
             , (i * 40503     + seed) `mod` 65536
             , (i * 1000003   + seed) `mod` 65536 )
      pixels    = [ px i | i <- [0 .. p - 1] ]
      centroids = [ px (i * 13 + 1) | i <- [0 .. k - 1] ]
      thr       = [ (i * 97 + seed) `mod` 256 | i <- [0 .. p - 1] ]
  in (centroids, thr, pixels)

tests :: TestTree
tests = testGroup "SpatialDither"
  [ testProperty "every dither mode yields one valid index per pixel, in [0,k)" $
      \(Positive s) ->
        let side = 8; k = 8; p = side * side
            (cs, thr, px) = mkFrame side k (s `mod` 9973)
            modes = [ ditherFrameQ16 FloydSteinberg side False cs thr px
                    , ditherFrameQ16 FloydSteinberg side True  cs thr px
                    , ditherFrameQ16 Atkinson       side False cs thr px
                    , ditherFrameQ16 BlueNoise      side False cs thr px ]
        in all (\out -> length out == p && all (\v -> v >= 0 && v < k) out) modes

  , testProperty "nearestQ16 is the true argmin with lowest-index tie-break" $
      \(Positive s) ->
        let (cs, _, px) = mkFrame 4 6 (s `mod` 7919)
            ok x = let i = nearestQ16 cs x
                       di = distSqQ16 x (cs !! i)
                   in all (\(j, c) -> let dj = distSqQ16 x c
                                      in dj > di || (dj == di && j >= i)) (zip [0..] cs)
        in all ok px

  , testProperty "blue-noise picks one of the two nearest centroids" $
      \(Positive s) ->
        let side = 6; k = 5
            (cs, thr, px) = mkFrame side k (s `mod` 7919)
            out = ditherFrameQ16 BlueNoise side False cs thr px
        in and [ let (i0, i1) = nearest2Q16 cs x in o == i0 || o == i1
               | (o, x) <- zip out px ]

  , testProperty "blue-noise is permutation-stable under pixel order (independence)" $
      \(Positive s) ->
        let side = 4; k = 5
            (cs, thr, px) = mkFrame side k (s `mod` 7919)
            out  = ditherFrameQ16 BlueNoise side False cs thr px
            -- reversing pixels+thresholds reverses the output (no inter-pixel state)
            outR = ditherFrameQ16 BlueNoise side False cs (reverse thr) (reverse px)
        in out == reverse outR
  ]

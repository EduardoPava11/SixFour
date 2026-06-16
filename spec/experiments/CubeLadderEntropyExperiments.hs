{-# OPTIONS_GHC -Wno-type-defaults -Wno-missing-home-modules #-}
-- Cube-ladder entropy experiments — answers Q2 (RGBT pool weights + strategy) and
-- Q3 (per-frame vs global scope per tier) with DATA, using SixFour.Spec.Entropy.
--
-- Reproduce:
--   cd spec && cabal repl sixfour-spec --repl-options="-v0" <<'RUN'
--   :l experiments/CubeLadderEntropyExperiments.hs
--   main
--   RUN
--
-- A parametric synthetic battery (8 captures × 8 frames × 10-colour palettes) spanning the
-- capture regimes the real spec-gen battery covers. Small palettes + reduced Sinkhorn
-- iterations keep it tractable in GHCi; the full 256-colour×64-frame Gen run is the scale-up.

import SixFour.Spec.Color      (OKLab(..), okLabDistanceSquared)
import SixFour.Spec.Entropy
import SixFour.Spec.Sinkhorn    (SinkhornParams(..), Measure, sinkhornDivergence)
import SixFour.Spec.Barycenter  (BarycenterParams(..), freeSupportBarycenter)
import Data.List (maximumBy, minimumBy, foldl')
import Data.Ord  (comparing)

-- ---- light params (relative comparisons don't need 1e-4 convergence) ----
lite :: SinkhornParams
lite = SinkhornParams 0.05 60

bcParams :: BarycenterParams
bcParams = BarycenterParams lite 6

kColors :: Int
kColors = 10

-- ---- helpers ----
meanOK :: [OKLab] -> OKLab
meanOK [] = OKLab 0 0 0
meanOK cs = let n = fromIntegral (length cs)
                (l,a,b) = foldl' (\(x,y,z) (OKLab l' a' b') -> (x+l',y+a',z+b')) (0,0,0) cs
            in OKLab (l/n) (a/n) (b/n)

maximin :: Int -> [OKLab] -> [OKLab]
maximin k cloud
  | null cloud || k <= 0 = []
  | otherwise = go [head cloud] (k-1)
  where go chosen 0 = chosen
        go chosen n = let c = maximumBy (comparing (\p -> minimum [okLabDistanceSquared p x | x <- chosen])) cloud
                      in go (chosen ++ [c]) (n-1)

centroidPool :: Int -> [OKLab] -> [OKLab]    -- maximin seed + one Lloyd step
centroidPool k cloud =
  let seeds = maximin k cloud
      assign p = snd (minimumBy (comparing fst) [ (okLabDistanceSquared p s, i) | (i,s) <- zip [0..] seeds ])
      grp i = [ p | p <- cloud, assign p == i ]
  in [ let g = grp i in if null g then seeds!!i else meanOK g | i <- [0..k-1] ]

barycenterPool :: Int -> [[OKLab]] -> [OKLab]
barycenterPool k quartet =
  freeSupportBarycenter bcParams [ [(c,1)|c<-f] | f<-quartet ] (maximin k (concat quartet))

quartetsOf4 :: [a] -> [[a]]
quartetsOf4 [] = []
quartetsOf4 xs = take 4 xs : quartetsOf4 (drop 4 xs)

asMeasure :: [OKLab] -> Measure
asMeasure f = [ (c,1) | c <- f ]

-- temporal reconstruction cost: how well a pooled frame represents the 4 sources
reconCost :: [OKLab] -> [[OKLab]] -> Double
reconCost pooled quartet = sum [ sinkhornDivergence lite (asMeasure pooled) (asMeasure f) | f <- quartet ]

scopeCostLite :: [OKLab] -> [[OKLab]] -> Double
scopeCostLite = scopeCostWith lite

-- ================= the battery =================
hues :: [(Double,Double)]
hues = [ (0.3*cos th, 0.3*sin th) | i<-[0..9::Int], let th = 2*pi*fromIntegral i/10 ]

capture :: String -> (Int -> [OKLab]) -> (String,[[OKLab]])
capture nm frameAt = (nm, [ frameAt t | t <- [0..7] ])

battery :: [(String,[[OKLab]])]
battery =
  [ capture "static"        (\_ -> [ OKLab 0.5 a b | (a,b)<-hues ])
  , capture "slow-pan"      (\t -> [ OKLab 0.5 (a+0.015*fromIntegral t) (b+0.015*fromIntegral t) | (a,b)<-hues ])
  , capture "fast-motion"   (\t -> let s = 1 + 0.12*fromIntegral t in [ OKLab (0.3+0.05*fromIntegral t) (a*s) (b*s) | (a,b)<-hues ])
  , capture "color-burst"   (\t -> let r = if t==3||t==4 then 1.3 else 0.15 in [ OKLab 0.5 (a*r) (b*r) | (a,b)<-hues ])
  , capture "achromatic"    (\_ -> [ OKLab (0.15+0.07*fromIntegral i) (a*0.06) (b*0.06) | (i,(a,b))<-zip [0..] hues ])
  , capture "chromatic-rich"(\_ -> [ OKLab 0.5 (a*1.3) (b*1.3) | (a,b)<-hues ])
  , capture "high-flicker"  (\t -> let s = if even t then 1 else (-1) in [ OKLab 0.5 (a*s) (b*s) | (a,b)<-hues ])
  , capture "gamut-expand"  (\t -> [ if i <= t+2 then OKLab 0.5 a b else OKLab 0.5 0 0 | (i,(a,b))<-zip [0..] hues ])
  ]

-- ================= experiments =================
pct :: Double -> Double
pct x = fromIntegral (round (x*1000)) / 10

r3 :: Double -> Double
r3 x = fromIntegral (round (x*1000)) / 1000

main :: IO ()
main = do
  putStrLn "===== EXPERIMENT A — RGBT pool weights (Q2) ====="
  putStrLn "capture            wL%   wa%   wb%   wT%"
  mapM_ (\(nm,fs) -> let RGBTWeights l a b t = rgbtWeights fs
                     in putStrLn (pad 16 nm ++ row [pct l,pct a,pct b,pct t])) battery

  putStrLn "\n===== EXPERIMENT B — pool-strategy bake-off (Q2): temporal recon cost, lower=better ====="
  putStrLn "capture           maximin  centroid  barycenter   winner"
  mapM_ (\(nm,fs) ->
            let qs = quartetsOf4 fs
                cost strat = sum [ reconCost (strat q) q | q <- qs ]
                cMax = cost (\q -> maximin kColors (concat q))
                cCen = cost (\q -> centroidPool kColors (concat q))
                cBar = cost (\q -> barycenterPool kColors q)
                win  = fst (minimumBy (comparing snd) [("maximin",cMax),("centroid",cCen),("barycenter",cBar)])
            in putStrLn (pad 16 nm ++ row3 [r3 cMax, r3 cCen, r3 cBar] ++ "  " ++ win)) battery

  putStrLn "\n===== EXPERIMENT C — scope per tier (Q3): scopeCost + verdict ====="
  putStrLn "capture           64^3 cost  -> verdict     16^3 cost  -> verdict"
  mapM_ (\(nm,fs) ->
            let g64   = maximin kColors (concat fs)
                c64   = scopeCostLite g64 fs
                pooled = [ barycenterPool kColors q | q <- quartetsOf4 fs ]   -- winning-ish pool
                g16   = maximin kColors (concat pooled)
                c16   = scopeCostLite g16 pooled
                v c   = show (scopeVerdict defaultScopeTau c)
            in putStrLn (pad 16 nm ++ pad 10 (show (r3 c64)) ++ pad 12 (v c64)
                                    ++ pad 10 (show (r3 c16)) ++ v c16)) battery
  where
    pad n s = take (max (n) (length s + 1)) (s ++ repeat ' ')
    row xs  = concatMap (pad 6 . show) xs
    row3 xs = concatMap (pad 9 . show) xs

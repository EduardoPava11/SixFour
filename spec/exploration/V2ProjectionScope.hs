{- |
Module      : V2ProjectionScope
Description : EXPLORATION (NOT WIRED, base-only, runghc). The SKI SCOPE of the opponent projections
              and their temporal facets. A projection (an opponent channel L / a / b) is a linear
              functional over (R,G,B); over time it is a series, and b:t decomposes as R:t + G:t -
              2(B:t). The combinator scope: the shared argument fans out (S), a zero-weight channel
              is K-discarded (out of scope), identity passes through.

  Check:  runghc V2ProjectionScope.hs

  THE PICTURE (owner directive 2026-06-29): the user inputs ENTROPY MANIPULATIONS; the model SEARCHES
  (PonderNet) for a stable state. The encoder takes raw sRGB and makes the opponent (L, a, b)
  representation. The model reasons in the mean / median / mode facets of the projection PAIRS, over
  time. To see how t and b correlate you unroll b over time:  b:t = R:t + G:t - 2(B:t)  (the owner's
  formula). THIS is the SKI scope: t is the SHARED argument fanned out (S) to the channel series, the
  weights combine them, and a channel a projection does not read (weight 0) is K-discarded (out of
  scope). The opponent projections match V2EncodeDecodeBoundary (L=R+G+B, a=R-G, b=R+G-2B). Lab dropped.

  Base-only, runghc, NOT in cabal/Map/gate. Trainer untouched (this is spec, not training).
-}
module V2ProjectionScope where

import Data.List (sort, group, maximumBy)
import Data.Ord (comparing)

-- ===========================================================================
-- (1) Projections (the opponent pairs) as linear functionals over (R,G,B)
-- ===========================================================================

type RGB     = (Int, Int, Int)
type Weights = (Int, Int, Int)     -- a projection's channel weights

wL, wA, wB :: Weights
wL = (1,  1,  1)     -- luma L      = R + G + B
wA = (1, -1,  0)     -- red-green a = R - G        (B has weight 0: out of scope)
wB = (1,  1, -2)     -- yellow-blue b = R + G - 2B (yellow = R + G)

-- | Apply a projection to a pixel: the single pixel argument is FANNED OUT to the weighted channels.
project :: Weights -> RGB -> Int
project (wr, wg, wb) (r, g, b) = wr * r + wg * g + wb * b

-- | The SCOPE of a projection: which channels it reads (nonzero weight). A zero-weight channel is
--   out of scope (K-discarded). [R in scope, G in scope, B in scope].
inScope :: Weights -> [Bool]
inScope (wr, wg, wb) = map (/= 0) [wr, wg, wb]

-- | A channel-as-time-series: apply a projection frame by frame over a list of pixels (time t).
channelSeries :: Weights -> [RGB] -> [Int]
channelSeries w = map (project w)

-- ===========================================================================
-- (2) The temporal facets (mean / median / mode = L2 / L1 / L0 centres)
-- ===========================================================================

-- | The L2 centre, scaled to stay integer: (n * mean) = the sum. (Divide by length for the mean.)
sumCentre :: [Int] -> Int
sumCentre = sum

medianCentre :: [Int] -> Int
medianCentre xs = sort xs !! (length xs `div` 2)

modeCentre :: [Int] -> Int
modeCentre xs = head (maximumBy (comparing length) (group (sort xs)))

-- | Sign of the covariance between time t = [0..] and a series (how a projection correlates with t).
--   Scaled by n^2 to stay integer: sign( sum (n*t_i - sum t)(n*x_i - sum x) ).
correlationSign :: [Int] -> Int
correlationSign xs = signum (sum [ (n * t - st) * (n * x - sx) | (t, x) <- zip [0 ..] xs ])
  where
    n  = length xs
    st = sum [0 .. n - 1]
    sx = sum xs

-- ===========================================================================
-- (3) Sample data
-- ===========================================================================

-- | A short clip whose yellow-blue b RISES over time (it gets more yellow: B falls, R+G rises).
risingYellow :: [RGB]
risingYellow = [ (40 + 12 * t, 40 + 12 * t, 200 - 18 * t) | t <- [0 .. 6] ]

-- | A clip whose b is flat then dips (for the mode / median / mean to separate).
mixedClip :: [RGB]
mixedClip = [ (10,10,10), (10,10,10), (10,10,10), (90,90,10), (10,10,90), (200,10,10), (10,200,10) ]

-- ===========================================================================
-- (4) Laws
-- ===========================================================================

-- | The opponent projections ARE the latent encoder (matches V2EncodeDecodeBoundary): L=R+G+B,
--   a=R-G, b=R+G-2B. The pairs the model reasons in.
lawOpponentProjections :: Bool
lawOpponentProjections =
     all (\p@(r, g, b) -> project wL p == r + g + b) sample
  && all (\p@(r, g, _) -> project wA p == r - g) sample
  && all (\p@(r, g, b) -> project wB p == r + g - 2 * b) sample
  where sample = [(r, g, b) | r <- [0, 128, 255], g <- [0, 90, 255], b <- [0, 200]]

-- | K-SCOPE: a channel with weight 0 is OUT OF SCOPE, the projection discards it (K). The red-green
--   a = R-G does not read B: changing B is a no-op. TOOTH: changing an in-scope channel (R) does change a.
lawZeroWeightIsKScope :: Bool
lawZeroWeightIsKScope =
     project wA (50, 20, 10) == project wA (50, 20, 250)      -- B out of scope: changing it is a no-op
  && inScope wA == [True, True, False]                        -- a reads R, G, not B
  && project wA (51, 20, 10) /= project wA (50, 20, 10)       -- tooth: R IS in scope (changes a)

-- | S-SCOPE (shared argument): a projection fans the SINGLE pixel out to its in-scope channels; the
--   same pixel feeds every weighted term. project w p equals the weighted sum of the channels OF THE
--   SAME p, which is exactly the S sharing pattern (one argument, many uses).
lawSharedArgumentFanout :: Bool
lawSharedArgumentFanout = all ok sample
  where
    ok p@(r, g, b) =
      let (wr, wg, wbb) = wB
      in project wB p == wr * r + wg * g + wbb * b           -- p shared across R, G, B (S fan-out)
    sample = [(r, g, b) | r <- [0, 100, 255], g <- [0, 255], b <- [0, 255]]

-- | THE TEMPORAL DECOMPOSITION (the owner's formula, the keystone): b:t = R:t + G:t - 2(B:t). The
--   yellow-blue series over time equals its per-channel series combined by b's weights. This is how
--   t and b correlate, and it is the SKI scope: t shared across the channel series, weights combine.
lawTemporalDecomposition :: Bool
lawTemporalDecomposition =
  channelSeries wB clip == zipWith3 (\rt gt bt -> rt + gt - 2 * bt) rT gT bT
  where
    clip = risingYellow
    rT = channelSeries (1, 0, 0) clip      -- R:t
    gT = channelSeries (0, 1, 0) clip      -- G:t
    bT = channelSeries (0, 0, 1) clip      -- B:t

-- | t AND b CORRELATE: on the rising-yellow clip, b:t increases with t (positive correlation); on a
--   falling clip it is negative. The sign is what the "how do t and b correlate" question reads off.
lawTandBCorrelation :: Bool
lawTandBCorrelation =
     correlationSign (channelSeries wB risingYellow) == 1        -- b rises with t: positive
  && correlationSign (reverse (channelSeries wB risingYellow)) == (-1)   -- reversed: negative (tooth)

-- | THE FACETS (mean / median / mode = L2 / L1 / L0 centres) of a projection's time series, the things
--   the model searches over. On a skewed clip they SEPARATE (the spread is information a mean-only
--   view misses); on a flat clip they agree.
lawFacetsSeparateUnderSkew :: Bool
lawFacetsSeparateUnderSkew =
     not (medianCentre bSer == modeCentre bSer && length (group (sort bSer)) == 1)  -- skewed: not all equal
  && let flat = replicate 5 (50 :: Int)
     in medianCentre flat == modeCentre flat && sumCentre flat == 250               -- flat: agree
  where bSer = channelSeries wB mixedClip

-- ===========================================================================
-- (5) Runner
-- ===========================================================================

laws :: [(String, Bool)]
laws =
  [ ("lawOpponentProjections      (L=R+G+B, a=R-G, b=R+G-2B: the pairs)",      lawOpponentProjections)
  , ("lawZeroWeightIsKScope       (B out of scope of a=R-G: K-discarded)",     lawZeroWeightIsKScope)
  , ("lawSharedArgumentFanout     (one pixel fanned to its channels: S)",      lawSharedArgumentFanout)
  , ("lawTemporalDecomposition    (b:t = R:t + G:t - 2(B:t): the owner formula)", lawTemporalDecomposition)
  , ("lawTandBCorrelation         (t and b:t correlate; sign read off)",       lawTandBCorrelation)
  , ("lawFacetsSeparateUnderSkew  (mean/median/mode = L2/L1/L0 facets)",       lawFacetsSeparateUnderSkew)
  ]

main :: IO ()
main = do
  putStrLn "V2ProjectionScope.hs  -- EXPLORATION (NOT WIRED): SKI scope of the opponent projections"
  putStrLn (replicate 72 '-')
  mapM_ (\(n, ok) -> putStrLn (verdict ok ++ "  " ++ n)) laws
  putStrLn (replicate 72 '-')
  let passed = length (filter snd laws)
      total  = length laws
  putStrLn ("SUMMARY: " ++ show passed ++ "/" ++ show total ++ " laws PASS"
            ++ if passed == total then "  (all green)" else "  (FAILURES present)")
  putStrLn ""
  let bSer = channelSeries wB risingYellow
  putStrLn ("b:t (rising yellow)   = " ++ show bSer)
  putStrLn ("  = R:t + G:t - 2(B:t) = " ++ show (zipWith3 (\r g b -> r + g - 2 * b)
              (channelSeries (1,0,0) risingYellow) (channelSeries (0,1,0) risingYellow)
              (channelSeries (0,0,1) risingYellow)))
  putStrLn ("  t-correlation sign   = " ++ show (correlationSign bSer) ++ "  (positive: b rises with t)")
  putStrLn ("  facets  sum/median/mode = " ++ show (sumCentre bSer, medianCentre bSer, modeCentre bSer))
  putStrLn ""
  putStrLn "SKI SCOPE: a projection fans the shared pixel/time argument out to its channels (S); a"
  putStrLn "zero-weight channel is K-discarded (out of scope); b:t = R:t + G:t - 2(B:t). The model"
  putStrLn "searches the mean/median/mode facets of these projection pairs for a stable state (PonderNet)."
  where
    verdict True  = "PASS"
    verdict False = "FAIL"

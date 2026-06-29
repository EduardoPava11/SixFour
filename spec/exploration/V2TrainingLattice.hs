{- |
Module      : V2TrainingLattice
Description : EXPLORATION (NOT WIRED, base-only, runghc). Discrete geometry + algebraic
              number theory IN THE TRAINING of the V2 model. The training loss, target
              quantization, and inductive bias are grounded in the Eisenstein integers
              Z[w] (the hexagonal A2 lattice), NOT in Euclidean RGB or Lab.

  Check:  runghc V2TrainingLattice.hs

  THE POINT (owner directive 2026-06-29): "Discrete geometry + algebraic number theory in
  the training of the model." V2 is raw sRGB 8-bit (Lab DROPPED). The colour structure that
  drives training is the A2 lattice:
    * LOSS = squared-Euclidean in the (luma) (+) (A2 chroma) embedding: squared luma residual +
      the Eisenstein NORM a^2-ab+b^2 of the chroma residual (the true hex length, sheared away
      from the naive square-coordinate L2). Positive-definite, so sqrt is a genuine metric.
    * TARGET is snapped to the index-3 sublattice L = {l == ca+cb (mod 3)} via the TRUE
      closest-point 'trainingTarget' (= closestLambda), so the data-manufactured target is
      BYTE-EXACT invertible (the /3 guard; collapse-safe). snapToLambda is the older luma-only version.
    * INDUCTIVE BIAS: the 6 units of Z[w] are 60-degree hue rotations that act as
      ISOMETRIES of the loss (a global hue spin cannot lower the loss).

  Mirrors the Eisenstein arithmetic of spec/exploration/V2RgbEisenstein.hs and the index-3
  sublattice from V2-SKI-PONDER-DIGEST.md. Base-only, runghc-checkable, NOT wired.
-}
module V2TrainingLattice where

import Data.List (minimumBy)
import Data.Ord (comparing)

-- ===========================================================================
-- (1) Eisenstein integers Z[w], w^2 = -1 - w  (the A2 chroma lattice)
-- ===========================================================================

data Eisen = Eisen Int Int deriving (Eq, Show)

eadd, esub, emul :: Eisen -> Eisen -> Eisen
eadd (Eisen a b) (Eisen c d) = Eisen (a + c) (b + d)
esub (Eisen a b) (Eisen c d) = Eisen (a - c) (b - d)
emul (Eisen a b) (Eisen c d) = Eisen (a * c - b * d) (a * d + b * c - b * d)

-- | The algebraic norm = the squared hexagonal (A2) chroma length.
enorm :: Eisen -> Int
enorm (Eisen a b) = a * a - a * b + b * b

-- | The 6 units = norm-1 elements = the six 60-degree hue rotations.
units :: [Eisen]
units = [Eisen 1 0, Eisen 0 1, Eisen (-1) (-1), Eisen (-1) 0, Eisen 0 (-1), Eisen 1 1]

-- ===========================================================================
-- (2) sRGB 8-bit <-> (luma, Eisenstein chroma), and the index-3 sublattice L
-- ===========================================================================

type RGB = (Int, Int, Int)

-- | Luma on the (1,1,1) balance axis.
luma :: RGB -> Int
luma (r, g, b) = r + g + b

-- | Chroma via R->1, G->w, B->w^2; gray collapses to the kernel Eisen 0 0.
chroma :: RGB -> Eisen
chroma (r, g, b) = Eisen (r - b) (g - b)

-- | Invert (luma, chroma) back to RGB. Integer ONLY on the index-3 sublattice
--   L = {l == ca + cb (mod 3)}. An invert-OR-REFUSE total function (the /3 byte-exactness guard).
lumaChromaToRgb :: Int -> Eisen -> Maybe RGB
lumaChromaToRgb l (Eisen ca cb)
  | (l - ca - cb) `mod` 3 == 0 = let bb = (l - ca - cb) `div` 3 in Just (bb + ca, bb + cb, bb)
  | otherwise                  = Nothing

-- | Snap LUMA into the congruence class so the inverse is byte-exact. Subtracts the residual
--   r in {0,1,2}, so luma moves by 0..2; this is NOT minimized (r=2 could move +1 instead) and
--   NOT a true nearest-lattice point. The genuine closest-point is V2A2ClosestPoint.closestLambda.
snapToLambda :: Int -> Eisen -> (Int, Eisen)
snapToLambda l c@(Eisen ca cb) = (l - ((l - ca - cb) `mod` 3), c)

-- ===========================================================================
-- (3) The training loss in discrete geometry
-- ===========================================================================

-- | TRAINING LOSS = the SQUARED-EUCLIDEAN distance in the (luma) (+) (A2 chroma) embedding:
--   the squared luma residual + the Eisenstein (hexagonal A2) squared-norm of the chroma residual.
--   This is a positive-definite quadratic form in the residual (so sqrt . trainLoss is a genuine
--   metric); the standard L2 loss shape, NOT plain RGB Euclidean, NOT Lab.
trainLoss :: RGB -> RGB -> Int
trainLoss p t = (luma p - luma t) ^ (2 :: Int) + enorm (esub (chroma p) (chroma t))

-- ===========================================================================
-- (3b) The byte-exact training-target snapper: true A2 closest-point onto Lambda
-- ===========================================================================

-- | A (luma, chroma) lattice point, the coordinate the trainer snaps targets in.
type Pt = (Int, Eisen)

-- | The snapping cost: the SAME squared-Euclidean geometry as 'trainLoss', in (luma, chroma) coords.
metricCost :: Pt -> Pt -> Int
metricCost (l0, c0) (l1, c1) = (l1 - l0) ^ (2 :: Int) + enorm (esub c1 c0)

-- | Is a (luma, chroma) point ON the index-3 sublattice Lambda (does it invert to integer sRGB)?
inLambda :: Pt -> Bool
inLambda (l, c) = maybe False (const True) (lumaChromaToRgb l c)

-- | Candidate destinations: luma moves |dl| <= 2 (covering snapToLambda's down-by-2) and the 6 unit
--   chroma shifts. This finite set CONTAINS the global minimum: the true minimal cost is <= 1 (a
--   single luma +-1 step always re-enters Lambda when the residual /= 0), and every cost-<=1 move is here.
candidatesFor :: Pt -> [Pt]
candidatesFor (l, c) =
     [ (l + dl, c)   | dl <- [-2 .. 2] ]
  ++ [ (l, eadd c u) | u  <- units ]

-- | THE CANONICAL byte-exact target snapper (supersedes 'snapToLambda'): the true nearest Lambda
--   point under the training geometry. Deterministic tie-break prefers smaller luma displacement,
--   then smaller chroma L1, so equal-cost chroma moves are preferred over a same-cost luma move.
closestLambda :: Pt -> Pt
closestLambda tgt = minimumBy (comparing rank) (filter inLambda (candidatesFor tgt))
  where
    rank cand = (metricCost tgt cand, abs (fst cand - fst tgt), normL1 (snd cand))
    normL1 (Eisen a b) = abs a + abs b

-- | The byte-exact (collapse-safe) training-target projection onto Lambda: the closest-point.
--   This is the wired snapper; 'snapToLambda' is the older luma-only version it supersedes.
trainingTarget :: Pt -> Pt
trainingTarget = closestLambda

-- ===========================================================================
-- (4) Laws
-- ===========================================================================

-- | N(xy) = N(x)N(y): the multiplicative norm, the ANT backbone of the metric.
lawNormMultiplicative :: Bool
lawNormMultiplicative =
  and [ enorm (emul x y) == enorm x * enorm y | x <- sample, y <- sample ]
  where sample = [Eisen a b | a <- [-3 .. 3], b <- [-3 .. 3]]

-- | N >= 0 and N = 0 IFF gray (the chroma kernel). N is a positive-definite quadratic form, so
--   the chroma part of the loss is non-negative and vanishes exactly on the luma axis. (The full
--   trainLoss mixes L1 luma with this squared chroma, so it is a training SCORE, not a metric.)
lawNormPositiveDefinite :: Bool
lawNormPositiveDefinite =
     all (\x -> enorm x >= 0) sample
  && all (\x -> (enorm x == 0) == (x == Eisen 0 0)) sample
  && chroma (7, 7, 7) == Eisen 0 0          -- gray -> kernel
  && enorm (chroma (7, 7, 8)) > 0           -- one step off gray has positive chroma (tooth)
  where sample = [Eisen a b | a <- [-4 .. 4], b <- [-4 .. 4]]

-- | The 6 units have norm 1 and act as 60-degree HUE ROTATIONS preserving chroma length
--   (isometries of the A2 metric). A non-unit scales the length (tooth).
lawUnitsAreSixHueRotations :: Bool
lawUnitsAreSixHueRotations =
     length units == 6
  && all (\u -> enorm u == 1) units
  && and [ enorm (emul u x) == enorm x | u <- units, x <- sample ]
  && enorm (emul (Eisen 2 0) (Eisen 1 1)) /= enorm (Eisen 1 1)    -- tooth: non-unit (norm 4) scales
  where sample = [Eisen a b | a <- [-3 .. 3], b <- [-3 .. 3]]

-- | Any training target snapped to L inverts to INTEGER sRGB (byte-exact, collapse-safe),
--   preserving its chroma and snapped luma. A non-L target REFUSES (the /3 guard, tooth).
lawSnapToLambdaByteExact :: Bool
lawSnapToLambdaByteExact =
     all ok [ (l, Eisen a b) | l <- [-5 .. 10], a <- [-4 .. 4], b <- [-4 .. 4] ]
  && lumaChromaToRgb 1 (Eisen 0 0) == Nothing                      -- tooth: 1 /= 0 (mod 3), refuses
  where
    ok (l, c) =
      let (l', _) = snapToLambda l c
      in case lumaChromaToRgb l' c of
           Just rgb -> chroma rgb == c && luma rgb == l'            -- integer RGB, chroma + luma exact
           Nothing  -> False

-- | The WIRED snapper 'trainingTarget' (= closestLambda) always produces a byte-exact (collapse-safe)
--   target and is idempotent on Lambda. Optimality vs snapToLambda is proven in V2A2ClosestPoint;
--   here we pin the wiring. Tooth: it does NOT make snapToLambda's suboptimal down-by-2 move.
lawTrainingTargetByteExact :: Bool
lawTrainingTargetByteExact =
     all (inLambda . trainingTarget) targets                       -- always byte-exact
  && all (\t -> trainingTarget t == t) (filter inLambda targets)   -- idempotent on Lambda
  && trainingTarget (2, Eisen 0 0) /= (0, Eisen 0 0)               -- tooth: differs from snapToLambda's (0,0)
  where targets = [ (l, Eisen a b) | l <- [-3 .. 6], a <- [-2 .. 2], b <- [-2 .. 2] ]

-- | The loss IS squared luma + the hexagonal A2 norm. N(a,b)=a^2-ab+b^2 is the TRUE squared
--   Euclidean length in the hex embedding, and is SHEARED away from the naive square-coordinate L2
--   (a^2+b^2): chroma deltas (2,1) and (2,-1) have equal naive L2 (5) but A2 norms 3 and 7. So the
--   discrete geometry does real work in the loss; it is positive-definite (zero only on equality).
lawTrainingLossIsLatticeNorm :: Bool
lawTrainingLossIsLatticeNorm =
     trainLoss c c == 0                                                       -- zero on equality
  && all (\(p, t) -> trainLoss p t >= 0) pairs                               -- non-negative
  && all (\(p, t) -> (trainLoss p t == 0) == (p == t)) pairs                 -- positive-definite (zero iff equal)
  && trainLoss (3, 1, 0) (0, 0, 0) == (luma (3, 1, 0)) ^ (2 :: Int) + enorm (chroma (3, 1, 0))
  && enorm (Eisen 2 1) == 3 && enorm (Eisen 2 (-1)) == 7                     -- hexagonal: sheared
  && ((2 * 2 + 1 * 1) :: Int) == (2 * 2 + (-1) * (-1))                       -- naive square-coord L2: equal (tooth)
  where
    c     = (4, 2, 1)
    pairs = [((r, g, b), (0, 0, 0)) | r <- [0 .. 3], g <- [0 .. 3], b <- [0 .. 3]]

-- | Simultaneously HUE-ROTATING prediction and target (multiply both chroma by a unit) leaves
--   the chroma loss INVARIANT: the units are isometries, a real inductive bias for training
--   (no global hue spin can lower the loss). Tooth: a non-unit scales the loss.
lawHueRotationInvariantLoss :: Bool
lawHueRotationInvariantLoss =
     and [ enorm (esub (emul u cp) (emul u ct)) == enorm (esub cp ct)
         | u <- units, cp <- sample, ct <- sample ]
  && enorm (esub (emul (Eisen 2 0) cp0) (emul (Eisen 2 0) ct0)) /= enorm (esub cp0 ct0)
  where
    sample = [Eisen a b | a <- [-2 .. 2], b <- [-2 .. 2]]
    cp0    = Eisen 1 0
    ct0    = Eisen 0 1

-- ===========================================================================
-- (5) Runner
-- ===========================================================================

laws :: [(String, Bool)]
laws =
  [ ("lawNormMultiplicative       (N(xy) = N(x)N(y) : ANT backbone)",          lawNormMultiplicative)
  , ("lawNormPositiveDefinite     (N>=0, =0 iff gray : loss vanishes on luma)", lawNormPositiveDefinite)
  , ("lawUnitsAreSixHueRotations  (6 units = 60deg isometries)",               lawUnitsAreSixHueRotations)
  , ("lawSnapToLambdaByteExact    (L target inverts to integer sRGB)",         lawSnapToLambdaByteExact)
  , ("lawTrainingTargetByteExact  (wired closestLambda snapper is byte-exact)", lawTrainingTargetByteExact)
  , ("lawTrainingLossIsLatticeNorm(luma^2 + hexnorm, sheared, pos-definite)",  lawTrainingLossIsLatticeNorm)
  , ("lawHueRotationInvariantLoss (units are loss isometries : bias)",         lawHueRotationInvariantLoss)
  ]

main :: IO ()
main = do
  putStrLn "V2TrainingLattice.hs  -- EXPLORATION (NOT WIRED): discrete geometry + ANT in training"
  putStrLn (replicate 72 '-')
  mapM_ (\(n, ok) -> putStrLn (verdict ok ++ "  " ++ n)) laws
  putStrLn (replicate 72 '-')
  let passed = length (filter snd laws)
      total  = length laws
  putStrLn ("SUMMARY: " ++ show passed ++ "/" ++ show total ++ " laws PASS"
            ++ if passed == total then "  (all green)" else "  (FAILURES present)")
  putStrLn ""
  putStrLn ("hex norm  (2, 1) = " ++ show (enorm (Eisen 2 1))
            ++ "   hex norm (2,-1) = " ++ show (enorm (Eisen 2 (-1)))
            ++ "   (naive square-coord L2 of both = 5: the A2 norm is sheared)")
  putStrLn ("snapToLambda 7 (Eisen 1 1) = " ++ show (snapToLambda 7 (Eisen 1 1))
            ++ "   inverts to " ++ show (uncurry lumaChromaToRgb (snapToLambda 7 (Eisen 1 1))))
  putStrLn ""
  putStrLn "HONEST NOTE: training in discrete geometry = the loss is the A2 hexagonal norm"
  putStrLn "(sheared away from Euclidean, proven), the target snaps to the index-3 sublattice L"
  putStrLn "so it stays byte-exact (the /3 guard), and the 6 units are hue-rotation isometries"
  putStrLn "of the loss. The wired snapper trainingTarget = closestLambda is the TRUE nearest"
  putStrLn "Lambda point (snapToLambda, luma-only by 0..2, is the superseded version)."
  where
    verdict True  = "PASS"
    verdict False = "FAIL"

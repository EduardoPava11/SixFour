{- |
Module      : SixFour.Spec.GLRM
Description : The preference-training KILL-SWITCH — refuse to learn from noise.

Epistemic hygiene for the A/B (Bradley-Terry) reward (SIXFOUR-ALPHAZERO-COLLAPSE-DESIGN §5.4,
§6 RLHF-hygiene). Before any preference net is trained, regress the logged BT outcomes on the
deterministic, golden-computable features @[coverage, beauty, ‖chroma‖²]@ via ordinary least
squares. If the data carries no stable linear signal (singular design, or @R²@ below a floor), the
preference data is noise and training is BLOCKED. This is the reward-model-calibration discipline
that prevents the policy/value net from chasing a phantom utility (the "did not train well" failure
the supervised look-net hit). COLOR-ATLAS referenced this as shipped, it did not exist, this is it.

Two guards:

  * The OLS kill-switch ('shouldTrain'): a stable fit with @R² ≥ 'r2Floor'@ and finite coefficients,
    else STOP. The OLS is built here (a small Gauss-Jordan solve), not borrowed.
  * Pair informativeness ('pairWeight', 'lawGalleryPairInformative'): a gallery pair whose two
    candidate embeddings are too close carries ~no BT gradient, so it gets ZERO weight. Gating
    informative pairs at the source keeps @lawStepDecreasesLoss@'s precondition non-vacuous.
-}
-- COMPARTMENT: SWIFT-COREAI | tag:none
module SixFour.Spec.GLRM
  ( -- * Features + samples
    Features
  , designRow
  , nParams
    -- * OLS fit + the kill-switch
  , GLRMFit(..)
  , solveLinear
  , fitGLRM
  , r2Floor
  , shouldTrain
    -- * Gallery-pair informativeness
  , embDistSq
  , informativeThreshold
  , pairWeight
    -- * Laws (predicates; QuickCheck'd in Properties.GLRM)
  , lawR2InUnitInterval
  , lawOLSRecoversLinear
  , lawNoSignalBlocks
  , lawKillSwitchConsistent
  , lawDegeneratePairZeroWeight
  , lawGalleryPairInformative
  ) where

import Data.List (foldl')

-- ---------------------------------------------------------------------------
-- Features + samples
-- ---------------------------------------------------------------------------

-- | The three deterministic, golden-computable regressors: (coverage, beauty, ‖chroma‖²).
type Features = (Double, Double, Double)

-- | The OLS design row WITH intercept: @[1, coverage, beauty, ‖chroma‖²]@.
designRow :: Features -> [Double]
designRow (c, b, ch) = [1, c, b, ch]

-- | Number of fitted parameters (intercept + 3 features).
nParams :: Int
nParams = 4

-- ---------------------------------------------------------------------------
-- Linear solve (Gauss-Jordan with partial pivoting; Nothing iff singular)
-- ---------------------------------------------------------------------------

-- | Solve @A x = b@ for a square @A@ by Gauss-Jordan elimination with partial pivoting.
-- 'Nothing' iff @A@ is singular (a pivot magnitude falls below 'pivotEps') — which is exactly
-- the "no information in the design" case the kill-switch must catch.
solveLinear :: [[Double]] -> [Double] -> Maybe [Double]
solveLinear a b = go 0 (zipWith (\row y -> row ++ [y]) a b)
  where
    n = length b
    go k m
      | k == n    = Just (map last m)
      | otherwise =
          let (pr, pv) = pivot k m
          in if abs pv < pivotEps
               then Nothing
               else let m'  = swap k pr m
                        pivRow = map (/ (m' !! k !! k)) (m' !! k)
                        m'' = [ if i == k then pivRow else eliminate (m' !! i) pivRow k
                              | i <- [0 .. n - 1] ]
                    in go (k + 1) m''
    pivot k m = foldl' (\(bi, bv) i -> let v = abs (m !! i !! k)
                                       in if v > bv then (i, v) else (bi, bv))
                       (k, abs (m !! k !! k)) [k + 1 .. n - 1]
    swap i j m
      | i == j    = m
      | otherwise = [ if r == i then m !! j else if r == j then m !! i else m !! r
                    | r <- [0 .. length m - 1] ]
    eliminate row pivRow k =
      let f = row !! k in zipWith (\x p -> x - f * p) row pivRow

-- | The singular-pivot threshold.
pivotEps :: Double
pivotEps = 1e-12

-- ---------------------------------------------------------------------------
-- OLS fit + kill-switch
-- ---------------------------------------------------------------------------

-- | An OLS fit: the coefficient vector ('designRow' order) and the coefficient of
-- determination @R²@.
data GLRMFit = GLRMFit
  { glmCoeffs :: ![Double]
  , glmR2     :: !Double
  } deriving (Eq, Show)

finiteD :: Double -> Bool
finiteD x = not (isNaN x) && not (isInfinite x)

dot :: [Double] -> [Double] -> Double
dot xs ys = sum (zipWith (*) xs ys)

-- | Fit @y ~ [1, coverage, beauty, ‖chroma‖²]@ by OLS. 'Nothing' when the fit is
-- meaningless: fewer than 'nParams' samples, no variance in @y@ (R² undefined), a singular
-- normal-equation system, or non-finite coefficients. A 'Just' carries finite coefficients
-- and @R² ∈ [0,1]@.
fitGLRM :: [(Features, Double)] -> Maybe GLRMFit
fitGLRM samples
  | length samples < nParams = Nothing
  | sstot <= 0               = Nothing
  | otherwise =
      case solveLinear xtx xty of
        Nothing   -> Nothing
        Just beta
          | not (all finiteD beta) -> Nothing
          | otherwise ->
              let preds = [ dot beta row | row <- xs ]
                  ssres = sum [ (y - p) ^ (2 :: Int) | (y, p) <- zip ys preds ]
                  r2    = 1 - ssres / sstot
              in if finiteD r2 then Just (GLRMFit beta r2) else Nothing
  where
    xs    = map (designRow . fst) samples
    ys    = map snd samples
    ybar  = sum ys / fromIntegral (length ys)
    sstot = sum [ (y - ybar) ^ (2 :: Int) | y <- ys ]
    xtx   = [ [ sum [ row !! i * row !! j | row <- xs ] | j <- [0 .. nParams - 1] ]
            | i <- [0 .. nParams - 1] ]
    xty   = [ sum [ row !! i * y | (row, y) <- zip xs ys ] | i <- [0 .. nParams - 1] ]

-- | The minimum explained variance for training to proceed.
r2Floor :: Double
r2Floor = 0.1

-- | The kill-switch: train ONLY if there is a stable fit clearing 'r2Floor'. Otherwise STOP
-- (the preference data is noise).
shouldTrain :: [(Features, Double)] -> Bool
shouldTrain samples =
  case fitGLRM samples of
    Just f  -> glmR2 f >= r2Floor && all finiteD (glmCoeffs f)
    Nothing -> False

-- ---------------------------------------------------------------------------
-- Gallery-pair informativeness
-- ---------------------------------------------------------------------------

-- | Squared L2 distance between two candidate embeddings.
embDistSq :: [Double] -> [Double] -> Double
embDistSq a b = sum (zipWith (\x y -> (x - y) ^ (2 :: Int)) a b)

-- | Below this embedding separation, a BT pair carries ~no gradient.
informativeThreshold :: Double
informativeThreshold = 1e-6

-- | The training weight of a gallery pair: 0 for a degenerate (too-close) pair, else 1.
pairWeight :: [Double] -> [Double] -> Double
pairWeight a b = if embDistSq a b < informativeThreshold then 0 else 1

-- ---------------------------------------------------------------------------
-- Laws
-- ---------------------------------------------------------------------------

-- | A successful fit has @R² ∈ [0,1]@ (OLS with intercept cannot do worse than the mean).
lawR2InUnitInterval :: [(Features, Double)] -> Bool
lawR2InUnitInterval samples =
  case fitGLRM samples of
    Nothing -> True
    Just f  -> glmR2 f >= -1e-9 && glmR2 f <= 1 + 1e-9

-- | OLS recovers an exactly-linear signal: if @y = β·x@ for the design rows, the fit (when it
-- exists) explains all variance (@R² ≈ 1@). Pins the solver's correctness.
lawOLSRecoversLinear :: [Features] -> (Double, Double, Double, Double) -> Bool
lawOLSRecoversLinear feats (b0, b1, b2, b3) =
  let beta     = [b0, b1, b2, b3]
      samples  = [ (f, dot beta (designRow f)) | f <- feats ]
  in case fitGLRM samples of
       Nothing -> True                       -- vacuous: degenerate design
       Just fit -> glmR2 fit >= 1 - 1e-6

-- | No signal blocks: identical feature rows (a rank-1 design) are singular, so 'fitGLRM' is
-- 'Nothing' and 'shouldTrain' is 'False' however the outcomes vary.
lawNoSignalBlocks :: Features -> [Double] -> Bool
lawNoSignalBlocks f ys =
  let samples = [ (f, y) | y <- ys ]
  in not (shouldTrain samples) && fitGLRM samples == Nothing

-- | 'shouldTrain' is exactly "a stable fit clears the floor" (the kill-switch contract).
lawKillSwitchConsistent :: [(Features, Double)] -> Bool
lawKillSwitchConsistent samples =
  shouldTrain samples ==
    (case fitGLRM samples of
       Just f  -> glmR2 f >= r2Floor && all finiteD (glmCoeffs f)
       Nothing -> False)

-- | A degenerate pair (identical embeddings) carries zero training weight.
lawDegeneratePairZeroWeight :: [Double] -> Bool
lawDegeneratePairZeroWeight a = pairWeight a a == 0

-- | Positive weight implies an informative (well-separated) pair.
lawGalleryPairInformative :: [Double] -> [Double] -> Bool
lawGalleryPairInformative a b =
  (pairWeight a b > 0) == (embDistSq a b >= informativeThreshold)

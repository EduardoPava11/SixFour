{- |
Module      : SixFour.Spec.Preference
Description : Continuous personalization — latent-utility preference + DPP-diverse gallery.

The pivot's personalization contract. The old design discretised taste into a
@hue × variety@ MAP-Elites grid keyed by the 11 Berlin–Kay categories ('Competition',
now deleted). MAP-Elites needs a discrete coordinate system; the categories were that
coordinate system, and they carried the same fidelity category-error as the substrate.

The continuous replacement has two research-grounded pieces, both **category-free**:

  * **Taste = a latent utility** @u : Embedding → ℝ@ over a continuous palette
    embedding (the 768 Haar coefficients, or any fixed feature vector). Learned from
    **pairwise** signals (pin / swipe / keep) under the Bradley–Terry link
    @P(A ≻ B) = σ(u(A) − u(B))@ (Chu & Ghahramani 2005, *Preference Learning with
    Gaussian Processes*; Preferential Bayesian Optimization). 'linearUtility' is the
    reference (GP-mean / BT-linear) inhabitant; a trained net is another.

  * **Diversity = a determinantal point process** (Kulesza–Taskar 2012). The gallery
    is a DPP-diverse, utility-weighted subset — the continuous, unstructured-archive
    analogue of "one elite per niche" (AURORA / Novelty Search lineage). Diversity is
    the log-determinant of an RBF kernel over embeddings; the gallery is built by
    greedy MAP selection of the quality-weighted L-ensemble
    @L = diag(√q) K diag(√q)@, @q = exp(α·u)@.

Contract-first, no stubs: every function is a total reference; the GP / trained
utility is one inhabitant of the utility contract. Laws in @Properties.Preference@.
-}
module SixFour.Spec.Preference
  ( -- * Embeddings and utility
    Embedding
  , Utility
  , linearUtility
  , btProbability
  , prefers
    -- * Similarity, diversity (DPP)
  , rbfKernel
  , gram
  , choleskyLogDet
  , dppLogDet
    -- * The gallery (continuous MAP-Elites replacement)
  , qualityGram
  , greedyGallery
  ) where

import Data.List (foldl', maximumBy)
import Data.Ord  (comparing)

-- | A palette's continuous feature vector (e.g. the 768 Haar coefficients, or the
-- encoder latent). The personalization layer is representation-agnostic over it.
type Embedding = [Double]

-- | A user's taste as a real-valued utility over embeddings (higher = more preferred).
type Utility = Embedding -> Double

-- | Reference utility inhabitant: a linear functional @u(x) = θ·x@ (the Bradley–Terry
-- linear model / the GP posterior mean under a linear kernel). A trained net is the
-- other inhabitant; both satisfy the preference laws.
linearUtility :: [Double] -> Utility
linearUtility theta x = sum (zipWith (*) theta x)

-- | Bradley–Terry / logistic link: probability that A (utility gap @g = u(A) − u(B)@)
-- is preferred to B. Monotone in @g@, @σ(0) = ½@, @σ(g) + σ(−g) = 1@.
btProbability :: Double -> Double
btProbability g = 1 / (1 + exp (negate g))

-- | A strict preference under a utility: A ≻ B iff @u(A) > u(B)@.
prefers :: Utility -> Embedding -> Embedding -> Bool
prefers u a b = u a > u b

-- ----------------------------------------------------------------------------
-- Diversity: RBF kernel + DPP log-determinant
-- ----------------------------------------------------------------------------

-- | Gaussian (RBF) similarity @K(x,y) = exp(−‖x−y‖² / ℓ²)@ ∈ (0,1]; @K(x,x) = 1@.
rbfKernel :: Double -> Embedding -> Embedding -> Double
rbfKernel ell x y =
  let d2 = sum (zipWith (\xi yi -> (xi - yi) * (xi - yi)) x y)
  in exp (negate d2 / (ell * ell))

-- | The symmetric Gram matrix of a similarity over a list of items.
gram :: (a -> a -> Double) -> [a] -> [[Double]]
gram k xs = [ [ k xi xj | xj <- xs ] | xi <- xs ]

-- | Cholesky log-determinant of a symmetric matrix: @2·Σ log Lᵢᵢ@. Returns 'Nothing'
-- if the matrix is not positive-definite (a singular Gram = a repeated/duplicate item
-- ⇒ zero-volume ⇒ no log-det), which is exactly how the DPP penalises duplicates.
choleskyLogDet :: [[Double]] -> Maybe Double
choleskyLogDet a =
  let n = length a
      idx i j = (a !! i) !! j
      -- build lower-triangular L row by row; bail on a non-positive pivot.
      go i ls
        | i == n    = Just ls
        | otherwise =
            -- accumulate row i left→right so each L[i][j] sees L[i][0..j-1].
            let lowerRow = foldl'
                  (\acc j ->
                     let prior = [ (ls !! j) !! p | p <- [0 .. j - 1] ]  -- L[j][0..j-1]
                         s     = sum (zipWith (*) acc prior)             -- Σ_{p<j} L[i][p]·L[j][p]
                         lij   = (idx i j - s) / ((ls !! j) !! j)
                     in acc ++ [lij])
                  [] [0 .. i - 1]
                diagSq = idx i i - sum [ x * x | x <- lowerRow ]
            in if diagSq <= 0
                 then Nothing
                 else go (i + 1) (ls ++ [ lowerRow ++ [sqrt diagSq] ++ replicate (n - i - 1) 0 ])
  in if n == 0
       then Just 0
       else fmap (\ls -> 2 * sum [ log ((ls !! i) !! i) | i <- [0 .. n - 1] ]) (go 0 [])

-- | DPP log-volume (diversity) of an embedding set under the RBF kernel: the
-- log-determinant of its Gram matrix. Large ⇒ the set spans a large volume (diverse);
-- a near-duplicate collapses it toward 'Nothing' (singular).
dppLogDet :: Double -> [Embedding] -> Maybe Double
dppLogDet ell = choleskyLogDet . gram (rbfKernel ell)

-- ----------------------------------------------------------------------------
-- The gallery (continuous MAP-Elites replacement)
-- ----------------------------------------------------------------------------

-- | The quality-weighted DPP L-ensemble Gram: @Lᵢⱼ = √(qᵢ qⱼ)·K(xᵢ,xⱼ)@ with
-- @qᵢ = exp(α·uᵢ)@ (Kulesza–Taskar §5). Higher-utility items get more mass; the RBF
-- still enforces diversity. @α = 0@ recovers the pure-diversity DPP.
qualityGram :: Double -> Double -> [(Double, Embedding)] -> [[Double]]
qualityGram alpha ell items =
  let q u = exp (alpha * u)
      k (uA, xA) (uB, xB) = sqrt (q uA * q uB) * rbfKernel ell xA xB
  in gram k items

-- | Greedy MAP inference for the quality-weighted DPP — the **gallery**. Repeatedly
-- adds the item that maximises the marginal log-det gain of the L-ensemble, stopping
-- at @k@ items or when no remaining item adds positive volume (a near-duplicate of the
-- selection). Returns the chosen indices in selection order. This is the continuous,
-- unstructured-archive replacement for MAP-Elites' "one elite per cell": diverse,
-- preference-weighted, and category-free.
greedyGallery :: Int -> Double -> Double -> [(Double, Embedding)] -> [Int]
greedyGallery k alpha ell items =
  let n  = length items
      ll = qualityGram alpha ell items                 -- the L-ensemble Gram
      sub idxs = [ [ (ll !! i) !! j | j <- idxs ] | i <- idxs ]
      logDetOf idxs = maybe (-1/0) id (choleskyLogDet (sub idxs))
      step chosen
        | length chosen >= k || length chosen >= n = reverse chosen
        | otherwise =
            let remaining = [ i | i <- [0 .. n - 1], i `notElem` chosen ]
                base      = logDetOf chosen
                gain i    = logDetOf (chosen ++ [i]) - base
                (bestI, bestG) = maximumBy (comparing snd) [ (i, gain i) | i <- remaining ]
            -- Stop only when every remaining item is an exact duplicate of the
            -- selection (gain = −∞ ⇒ singular). With a unit-diagonal RBF kernel the
            -- marginal gains are naturally ≤ 0, so a "gain > 0" stop would wrongly
            -- reject even the first pick — we want the top-k by marginal volume.
            in if isInfinite bestG then reverse chosen else step (bestI : chosen)
  in step []

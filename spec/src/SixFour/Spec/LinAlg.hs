{- |
Module      : SixFour.Spec.LinAlg
Description : Minimal dense linear algebra for tensor-level look-NN reasoning.

A row-major dense matrix on @Vector Double@, plus the small set of operations
needed to compute orthogonal projections onto column spaces of decoder design
matrices (Quad4, PairTree). Specifically:

  * 'matVecMul' for the forward decoder action.
  * 'transpose', 'matMatMul' for setup.
  * 'modifiedGramSchmidt' for an orthonormal basis of @im(B)@ with numerical
    rank reporting (via tolerance-rejected columns).
  * 'projectOntoColumns' = @Q (Qᵀ p)@ for the projection of @p@ onto the column
    span of @Q@ (assuming @Q@ has orthonormal columns).
  * 'residualFraction' = @1 − ‖Qᵀp‖² / ‖p‖²@ — the relative residual after
    projecting @p@ onto @im(Q)@.

This is /minimal/ — no LAPACK, no BLAS, no external deps. The dimensions we
care about (768 × 511 for Quad4, 768 × 768 for PairTree) are small enough that
pure-Haskell @Vector Double@ runs in a few seconds for the one-shot QR setup,
and per-palette residual computations are then O(m·n) ≈ 400 k float ops.

Numerical caveats: Modified Gram-Schmidt is reasonably stable for the
non-ill-conditioned matrices we have here, but it is not the gold standard
(QR via Householder would be more stable, SVD would be best). For our purpose
of /measuring/ rank and residual rather than /solving/ ill-conditioned
systems, MGS is sufficient.

Laws (see @Properties.LinAlg@): @matVecMul@ is linear; @transpose . transpose
= id@; columns of @modifiedGramSchmidt@'s output are orthonormal; projecting
a vector in @im(Q)@ onto @Q@ recovers the vector; @residualFraction@ ∈ [0, 1].
-}
module SixFour.Spec.LinAlg
  ( -- * The matrix type
    Matrix
  , mkMatrix
  , matRows
  , matCols
  , matIndex
  , matCol
  , matRow
  , fromColumns
  , matToList
    -- * Vector ops
  , vecDot
  , vecNormSq
    -- * Matrix ops
  , matVecMul
  , transpose
    -- * Orthogonalisation
  , modifiedGramSchmidt
    -- * Projection onto a column-orthonormal matrix
  , projectOntoColumns
  , residualFraction
    -- * Rank reporting
  , numericalRank
  ) where

import qualified Data.Vector.Unboxed as U
import           Data.Vector.Unboxed (Vector)

-- | Row-major dense matrix.
data Matrix = Matrix
  { matRows :: !Int
  , matCols :: !Int
  , matData :: !(Vector Double)
  } deriving (Eq, Show)

-- | Build a matrix from row-major flat data. Returns 'Nothing' on a length
-- mismatch.
mkMatrix :: Int -> Int -> Vector Double -> Maybe Matrix
mkMatrix r c v
  | r >= 0 && c >= 0 && U.length v == r * c = Just (Matrix r c v)
  | otherwise = Nothing

-- | @matIndex m i j@ = the @(i, j)@ entry.
matIndex :: Matrix -> Int -> Int -> Double
matIndex (Matrix _ c v) i j = v U.! (i * c + j)

-- | The @j@-th column as a length-@matRows m@ vector.
matCol :: Matrix -> Int -> Vector Double
matCol (Matrix r c v) j = U.generate r (\i -> v U.! (i * c + j))

-- | The @i@-th row as a length-@matCols m@ vector.
matRow :: Matrix -> Int -> Vector Double
matRow (Matrix _ c v) i = U.slice (i * c) c v

-- | Build a matrix from a list of column vectors (each of length @r@). Returns
-- 'Nothing' if any column has the wrong length.
fromColumns :: Int -> [Vector Double] -> Maybe Matrix
fromColumns r cs
  | not (all (\v -> U.length v == r) cs) = Nothing
  | otherwise =
      let c    = length cs
          arr  = U.generate (r * c) $ \idx ->
                   let (i, j) = idx `divMod` c
                   in (cs !! j) U.! i
      in Just (Matrix r c arr)

-- | Inverse of 'fromColumns' for inspection: list of rows.
matToList :: Matrix -> [[Double]]
matToList (Matrix r c v) =
  [ [ v U.! (i * c + j) | j <- [0 .. c - 1] ] | i <- [0 .. r - 1] ]

-- | Dot product of two equal-length vectors.
vecDot :: Vector Double -> Vector Double -> Double
vecDot u v = U.sum (U.zipWith (*) u v)

-- | Squared L² norm of a vector.
vecNormSq :: Vector Double -> Double
vecNormSq v = U.sum (U.map (\x -> x * x) v)

-- | @matVecMul A x = A · x@. @A@ is @r × c@; @x@ has length @c@; result has
-- length @r@.
matVecMul :: Matrix -> Vector Double -> Vector Double
matVecMul m@(Matrix r c _) x
  | U.length x /= c = error "matVecMul: dimension mismatch"
  | otherwise = U.generate r (\i -> vecDot (matRow m i) x)

-- | Matrix transpose.
transpose :: Matrix -> Matrix
transpose (Matrix r c v) =
  Matrix c r $ U.generate (r * c) $ \idx ->
    let (j, i) = idx `divMod` r
    in v U.! (i * c + j)

-- | Modified Gram-Schmidt orthogonalisation of the columns of @A@.
--
-- Returns @(Q, acceptedIdx)@ where @Q@ has orthonormal columns spanning
-- @im(A)@, and @acceptedIdx@ is the indices (in the original column ordering)
-- of the columns that contributed independently. Linearly dependent columns
-- (whose residual after subtracting projections has @norm² < tol@) are
-- discarded; the number kept is the /numerical rank/ of @A@ at this tolerance.
modifiedGramSchmidt
  :: Double      -- ^ residual @norm²@ rejection threshold (e.g. 1e-12)
  -> Matrix      -- ^ input matrix (columns are vectors to orthogonalise)
  -> (Matrix, [Int])
modifiedGramSchmidt tol m@(Matrix r c _) =
  let (qsRev, idxRev) = go 0 [] []
      qs              = reverse qsRev
      idx             = reverse idxRev
      qMat = case fromColumns r qs of
               Just mt -> mt
               Nothing -> Matrix r 0 U.empty
  in (qMat, idx)
  where
    go :: Int -> [Vector Double] -> [Int] -> ([Vector Double], [Int])
    go j accQ accIdx
      | j >= c = (accQ, accIdx)
      | otherwise =
          let col0    = matCol m j
              reduced = foldl reduceAgainst col0 (reverse accQ)
              n2      = vecNormSq reduced
          in if n2 < tol
               then go (j + 1) accQ accIdx
               else
                 let qj = U.map (/ sqrt n2) reduced
                 in go (j + 1) (qj : accQ) (j : accIdx)

    reduceAgainst v qi =
      let r_iv = vecDot qi v
      in U.zipWith (\x y -> x - r_iv * y) v qi

-- | @projectOntoColumns Q p = Q · (Qᵀ · p)@ — the orthogonal projection of @p@
-- onto the column space of @Q@. Assumes @Q@'s columns are orthonormal (i.e.
-- the output of 'modifiedGramSchmidt').
projectOntoColumns :: Matrix -> Vector Double -> Vector Double
projectOntoColumns q p =
  let qt     = transpose q
      coords = matVecMul qt p     -- length = matCols q
  in matVecMul q coords

-- | Relative residual of @p@ projected onto the column space of orthonormal
-- @Q@: @(‖p‖² − ‖Qᵀp‖²) / ‖p‖²@ ∈ [0, 1]. Returns 0 for the zero vector.
residualFraction :: Matrix -> Vector Double -> Double
residualFraction q p =
  let nP   = vecNormSq p
      qt   = transpose q
      coords = matVecMul qt p
      nPro = vecNormSq coords
  in if nP <= 1e-30 then 0.0 else max 0.0 ((nP - nPro) / nP)

-- | Numerical rank: number of columns 'modifiedGramSchmidt' kept.
numericalRank :: Double -> Matrix -> Int
numericalRank tol = length . snd . modifiedGramSchmidt tol

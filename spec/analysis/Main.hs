module Main (main) where

-- De-risk: confirm hmatrix links LAPACK (macOS Accelerate) before building the
-- real analysis on top of it.
import Numeric.LinearAlgebra (Matrix, R, fromLists, singularValues)

main :: IO ()
main = do
  let m = fromLists [[2, 0, 0], [0, 3, 0], [0, 0, 1]] :: Matrix R
  putStrLn ("hmatrix OK — singular values: " ++ show (singularValues m))

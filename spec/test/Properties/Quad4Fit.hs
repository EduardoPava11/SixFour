module Properties.Quad4Fit (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Test.QuickCheck

import           Data.List           (sort)

import SixFour.Spec.Color    (OKLab(..))
import SixFour.Spec.LinAlg   (matRows, matCols)
import SixFour.Spec.PairTree (sigmaReflect)
import SixFour.Spec.Quad4    (Quad4Palette(..), quad4Depth, reconstruct)
import SixFour.Spec.Quad4Fit

-- =============================================================================
-- Generators
-- =============================================================================

genBoundedOKLab :: Gen OKLab
genBoundedOKLab = OKLab <$> choose (0.2, 0.8)
                        <*> choose (-0.2, 0.2)
                        <*> choose (-0.2, 0.2)

genQuad4 :: Gen Quad4Palette
genQuad4 = do
  rt <- genBoundedOKLab
  lvls <- mapM (\l -> vectorOf (4 ^ l) ((,) <$> genOff <*> genOff))
                [0 .. quad4Depth - 1]
  pure (Quad4Palette rt lvls)
  where
    genOff = OKLab <$> choose (-0.02, 0.02)
                   <*> choose (-0.02, 0.02)
                   <*> choose (-0.02, 0.02)

-- 256 random OKLab leaves — the kind of palette real captures produce.
genRandomPalette :: Gen [OKLab]
genRandomPalette = vectorOf 256 genBoundedOKLab

-- 256 leaves that form 128 σ-pairs: pick 128 random points and interleave
-- with their σ-reflections.
genSigmaSymmetricPalette :: Gen [OKLab]
genSigmaSymmetricPalette = do
  half <- vectorOf 128 genBoundedOKLab
  pure (interleavePairs half (map sigmaReflect half))
  where
    interleavePairs []     []     = []
    interleavePairs (x:xs) (y:ys) = x : y : interleavePairs xs ys
    interleavePairs _      _      = []

-- =============================================================================
-- Reporting helpers
-- =============================================================================

medianOf :: [Double] -> Double
medianOf xs = let s = sort xs in s !! (length xs `div` 2)

percentileOf :: Int -> [Double] -> Double
percentileOf p xs =
  let n = length xs
      s = sort xs
      i = max 0 (min (n - 1) ((p * (n - 1)) `div` 100))
  in s !! i

-- =============================================================================
-- Tests
-- =============================================================================

tests :: TestTree
tests = testGroup "Quad4Fit (Quad4 as a linear map — tensor-level measurement)"
  [ -- ---------------- design matrix shape ----------------
    testProperty "design matrix shape: 768 × 513" $
      once $ matRows quad4DesignMatrix == 768
          && matCols quad4DesignMatrix == 513

  , testProperty "achromatic design matrix shape: 768 × 511" $
      once $ matRows quad4DesignMatrixAchromatic == 768
          && matCols quad4DesignMatrixAchromatic == 511

    -- ---------------- EMPIRICAL: rank reports ----------------
    -- The whole point of building the tensor: see the actual numbers.
  , testProperty "EMPIRICAL: Quad4 image rank" $
      once $
        let r = quad4ImageRank
        in counterexample
             ("Quad4 numerical rank (MGS tol 1e-9) = " ++ show r ++ " / 513")
             (r > 0 && r <= 513)

  , testProperty "EMPIRICAL: achromatic Quad4 image rank" $
      once $
        let r = quad4AchromaticImageRank
        in counterexample
             ("Achromatic Quad4 numerical rank = " ++ show r ++ " / 511")
             (r > 0 && r <= 511)

    -- ---------------- round-trip ----------------
  , testProperty "round-trip: Quad4-generated palette has residual ≈ 0" $
      forAll genQuad4 $ \qp ->
        let r = quad4Residual (reconstruct qp)
        in counterexample ("residual = " ++ show r) (r < 1e-9)

    -- ---------------- per-trial residuals ----------------
    -- Each trial PRINTS the residual via counterexample; the QuickCheck
    -- harness aggregates and shows the value.
  , testProperty "EMPIRICAL: residual on σ-symmetric palettes (per trial)" $
      withMaxSuccess 20 $
      forAll genSigmaSymmetricPalette $ \pal ->
        let r = quad4ResidualAchromatic pal
        in counterexample
             ("σ-symmetric residual = " ++ show r)
             (r >= 0 && r <= 1)

  , testProperty "EMPIRICAL: residual on random palettes (per trial)" $
      withMaxSuccess 20 $
      forAll genRandomPalette $ \pal ->
        let r = quad4ResidualAchromatic pal
        in counterexample
             ("random residual = " ++ show r)
             (r >= 0 && r <= 1)

    -- ---------------- summary report ----------------
    -- Aggregate stats. Prints to stdout via 'putStrLn' so the numbers appear
    -- whether the property passes or fails. The §A.4 decision rule yields a
    -- verdict directly from the median residual.
  , testProperty "REPORT: σ-symmetric vs random residual distribution (n=20)" $
      ioProperty $ do
        let n = 20
        pSig <- generate (vectorOf n genSigmaSymmetricPalette)
        pRnd <- generate (vectorOf n genRandomPalette)
        let rSig = map quad4ResidualAchromatic pSig
            rRnd = map quad4ResidualAchromatic pRnd
            mSig = medianOf rSig
            pSig90 = percentileOf 90 rSig
            mRnd = medianOf rRnd
            pRnd90 = percentileOf 90 rRnd
            verdict
              | mSig < 0.05 = "TRUSTED  (fits σ-symmetric well)"
              | mSig > 0.15 = "REJECTED (cannot fit σ-symmetric)"
              | otherwise   = "MARGINAL (needs more data)"
        mapM_ putStrLn
          [ ""
          , "  ============================================================"
          , "  Quad4 tensor-level measurement report  (n = " ++ show n ++ ")"
          , "  ============================================================"
          , "  Design matrix:               768 × 513   (full)"
          , "                               768 × 511   (achromatic root)"
          , "  Empirical rank (full):       " ++ show quad4ImageRank
          , "  Empirical rank (achromatic): " ++ show quad4AchromaticImageRank
          , "  σ-pair palette subspace dim: 384         (theoretical upper)"
          , "  ------------------------------------------------------------"
          , "  Quad4Residual on σ-symmetric synthetic palettes:"
          , "    median  = " ++ show mSig
          , "    90th    = " ++ show pSig90
          , "  Quad4Residual on random palettes:"
          , "    median  = " ++ show mRnd
          , "    90th    = " ++ show pRnd90
          , "  ------------------------------------------------------------"
          , "  §A.4 verdict (Quad4 trust gate): " ++ verdict
          , "  ============================================================"
          , ""
          ]
        pure (property (mSig >= 0 && mSig <= 1))
  ]

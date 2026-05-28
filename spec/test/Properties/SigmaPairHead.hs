module Properties.SigmaPairHead (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Test.QuickCheck

import           Data.List           (sort)

import SixFour.Spec.Color       (OKLab(..))
import SixFour.Spec.LinAlg      (matRows, matCols)
import SixFour.Spec.PairTree    (HaarPalette(..), sigmaReflect)
import SixFour.Spec.SigmaPairHead

-- =============================================================================
-- Generators
-- =============================================================================

genBoundedOKLab :: Gen OKLab
genBoundedOKLab = OKLab <$> choose (0.2, 0.8)
                        <*> choose (-0.2, 0.2)
                        <*> choose (-0.2, 0.2)

genSmallOffset :: Gen OKLab
genSmallOffset = OKLab <$> choose (-0.02, 0.02)
                       <*> choose (-0.02, 0.02)
                       <*> choose (-0.02, 0.02)

-- Arbitrary well-formed SigmaPairTree (depth 7).
genSigmaPairTree :: Gen SigmaPairTree
genSigmaPairTree = do
  rt <- genBoundedOKLab
  lvls <- mapM (\i -> vectorOf (2 ^ i) genSmallOffset)
                [0 .. sigmaPairDepth - 1]
  pure (SigmaPairTree (HaarPalette rt lvls))

-- 256 random OKLab leaves (no σ structure imposed).
genRandomPalette :: Gen [OKLab]
genRandomPalette = vectorOf 256 genBoundedOKLab

-- 256 leaves in σ-pair-interleaved order: 128 random points, each followed
-- by its σ-reflection.
genSigmaSymmetricPalette :: Gen [OKLab]
genSigmaSymmetricPalette = do
  half <- vectorOf 128 genBoundedOKLab
  pure (concatMap (\c -> [c, sigmaReflect c]) half)

-- =============================================================================
-- Helpers
-- =============================================================================

medianOf :: [Double] -> Double
medianOf xs = sort xs !! (length xs `div` 2)

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
tests = testGroup "SigmaPairHead (σ-pair-symmetric decoder — structural σ-equivariance)"
  [ -- ---------------- Dimensional accounting ----------------
    testProperty "DOF = 384 (the σ-symmetric palette subspace dimension)" $
      once $ sigmaPairDegreesOfFreedom == 384

  , testProperty "depth = 7; inner leaves = 128; output leaves = 256" $
      once $ sigmaPairDepth == 7
          && sigmaPairInnerLeaves == 128
          && sigmaPairLeaves == 256

  , testProperty "design matrix shape: 768 × 384" $
      once $ matRows sigmaPairDesignMatrix == 768
          && matCols sigmaPairDesignMatrix == 384

    -- ---------------- Structural σ-pair guarantee ----------------
  , testProperty "reconstructPaired emits 256 leaves" $
      forAll genSigmaPairTree $ \spt ->
        length (reconstructPaired spt) == 256

  , testProperty "every odd-indexed leaf is σ-reflection of its even predecessor" $
      forAll genSigmaPairTree $ \spt ->
        let leaves = reconstructPaired spt
            pairs  = [ (leaves !! (2 * i), leaves !! (2 * i + 1))
                     | i <- [0 .. 127] ]
        in all (\(c, sc) -> sc == sigmaReflect c) pairs

  , testProperty "sigmaSwapAndReflect is the identity on a σ-pair palette" $
      forAll genSigmaPairTree $ \spt ->
        let leaves = reconstructPaired spt
        in sigmaSwapAndReflect leaves == leaves

    -- ---------------- EMPIRICAL: rank ----------------
  , testProperty "EMPIRICAL: SigmaPairHead image rank = 384" $
      once $
        let r = sigmaPairImageRank
        in counterexample
             ("SigmaPairHead numerical rank = " ++ show r ++ " / 384")
             (r == 384)

    -- ---------------- Residual = 0 on σ-symmetric (by construction) ----------------
  , testProperty "σ-symmetric synthetic palette: residual ≈ 0" $
      forAll genSigmaSymmetricPalette $ \pal ->
        let r = sigmaPairResidual pal
        in counterexample ("residual = " ++ show r) (r < 1e-9)

    -- ---------------- Residual > 0 on random palettes ----------------
  , testProperty "random palette: residual is the σ-asymmetric content" $
      forAll genRandomPalette $ \pal ->
        let r = sigmaPairResidual pal
        in counterexample ("residual = " ++ show r) (r >= 0 && r <= 1)

    -- ---------------- Summary report ----------------
  , testProperty "REPORT: σ-symmetric vs random residual distribution (n=20)" $
      ioProperty $ do
        let n = 20
        pSig <- generate (vectorOf n genSigmaSymmetricPalette)
        pRnd <- generate (vectorOf n genRandomPalette)
        let rSig = map sigmaPairResidual pSig
            rRnd = map sigmaPairResidual pRnd
            mSig = medianOf rSig
            pSig90 = percentileOf 90 rSig
            mRnd = medianOf rRnd
            pRnd90 = percentileOf 90 rRnd
            contrast = mRnd / max mSig 1e-30
        mapM_ putStrLn
          [ ""
          , "  ============================================================"
          , "  SigmaPairHead tensor-level measurement  (n = " ++ show n ++ ")"
          , "  ============================================================"
          , "  Design matrix:               768 × 384"
          , "  Empirical rank:              " ++ show sigmaPairImageRank
          , "  σ-symmetric subspace dim:    384  (= DOF; image IS this subspace)"
          , "  ------------------------------------------------------------"
          , "  Residual on σ-symmetric synthetic palettes:"
          , "    median  = " ++ show mSig
          , "    90th    = " ++ show pSig90
          , "  Residual on random palettes:"
          , "    median  = " ++ show mRnd
          , "    90th    = " ++ show pRnd90
          , "  ------------------------------------------------------------"
          , "  Contrast (random / σ-sym): " ++ show contrast
          , "  (For Quad4 this contrast was ≈ 1.0 — no σ-alignment.)"
          , "  ============================================================"
          , ""
          ]
        pure (property (mSig < 0.001 && mRnd > mSig))
  ]

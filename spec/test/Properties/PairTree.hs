module Properties.PairTree (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Test.QuickCheck

import SixFour.Spec.Color    (OKLab(..))
import SixFour.Spec.PairTree

genOKLab :: Gen OKLab
genOKLab = OKLab <$> choose (0, 1) <*> choose (-0.4, 0.4) <*> choose (-0.4, 0.4)

genDepth :: Gen Int
genDepth = choose (0, 5)

-- Arbitrary (well-formed) tree: level i carries exactly 2^i offsets.
genHaar :: Gen HaarPalette
genHaar = do
  d   <- genDepth
  rt  <- genOKLab
  lvs <- mapM (\i -> vectorOf (2 ^ i) genOKLab) [0 .. d - 1]
  pure (HaarPalette rt lvs)

-- Bounded tree: small root + tiny offsets so every leaf stays in gamut.
genBoundedHaar :: Gen HaarPalette
genBoundedHaar = do
  d  <- genDepth
  rt <- OKLab <$> choose (0.4, 0.6) <*> choose (-0.05, 0.05) <*> choose (-0.05, 0.05)
  lvs <- mapM (\i -> vectorOf (2 ^ i)
                 (OKLab <$> choose (-0.02, 0.02) <*> choose (-0.01, 0.01) <*> choose (-0.01, 0.01)))
              [0 .. d - 1]
  pure (HaarPalette rt lvs)

genLeaves :: Gen [OKLab]
genLeaves = do
  d <- genDepth
  vectorOf (2 ^ d) genOKLab

tests :: TestTree
tests = testGroup "PairTree (Haar pairing pyramid — the NN's dimensional space)"
  [ testProperty "Haar round-trip: reconstruct ∘ analyze = id on the leaves" $
      forAll genLeaves (lawReconstructAnalyzeRoundTrip 1e-9)

  , testProperty "balance: mean(leaves) = root (the offsets cancel)" $
      forAll genHaar (lawBalancedMean 1e-9)

  , testProperty "leaf count = 2^depth" $
      forAll genHaar lawLeafCount

  , testProperty "bounded offsets ⇒ gamut closure" $
      forAll genBoundedHaar lawGamutClosure

  , -- The dimensional-space accounting, pinned.
    testProperty "DOF accounting: 768 = 3·256 = 3 + 3·255; leaves = K" $
      once lawDegreesOfFreedom

  , testProperty "SixFour shape: depth 8, 256 leaves, 255 offsets, 768 DOF, 8 levels" $
      once $
           paletteDepth == 8
        && numLeaves == 256
        && numInternal == 255
        && degreesOfFreedom == 768
        && levelDof == [3, 6, 12, 24, 48, 96, 192, 384]

  , -- The chroma reflection σ — the exact, continuous OKLab complement (replaces
    -- the deleted 11-category complement map + [4,2,1] metric).
    testProperty "σ is an involution: σ(σ x) = x" $
      forAll genOKLab lawSigmaInvolution

  , testProperty "σ is a Euclidean OKLab isometry: ‖σx−σy‖² = ‖x−y‖²" $
      forAll genOKLab $ \x -> forAll genOKLab $ \y -> lawSigmaEuclideanIsometry x y

  , -- φ self-similarity: golden decay shrinks detail by 1/φ ≈ 0.618 per level.
    testProperty "golden decay ratio between levels is 1/φ" $
      once $ abs (goldenDecay 1 1 / goldenDecay 1 0 - 1 / phi) < 1e-12

  , testProperty "golden decay is self-similar across all paletteDepth levels (ratio 1/φ)" $
      forAll (choose (0.01, 10) :: Gen Double) (lawGoldenDecayRatio 1e-9)

  , testProperty "golden decay = halting prior: per-level ponder budget strictly decreasing (signal→noise)" $
      forAll (choose (0.01, 10) :: Gen Double) lawGoldenDecayHaltPriorMonotone

  , -- Knowledge: a φ-decaying tree's measured per-level magnitudes ratio to 1/φ.
    testProperty "a golden-decaying tree has level-magnitude ratios ≈ 1/φ" $
      once $
        let mags  = [ OKLab (goldenDecay 1.0 i) 0 0 | i <- [0 .. 4] ]
            tree  = HaarPalette (OKLab 0.5 0 0) [ replicate (2 ^ i) (mags !! i) | i <- [0 .. 4] ]
            lvm   = levelMeanMagnitude tree
            ratios = zipWith (/) (drop 1 lvm) lvm
        in all (\r -> abs (r - 1 / phi) < 1e-9) ratios
  ]

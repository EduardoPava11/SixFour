module Properties.Diversity (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Test.QuickCheck

import SixFour.Spec.Color     (OKLab(..))
import SixFour.Spec.Diversity

genOKLab :: Gen OKLab
genOKLab = OKLab <$> choose (0, 1) <*> choose (-0.4, 0.4) <*> choose (-0.4, 0.4)

genCands :: Gen [(OKLab, Double)]
genCands = do
  n <- choose (4, 24)
  vectorOf n ((,) <$> genOKLab <*> choose (0.1, 5))

-- A fixed 4-colour palette + weights (1,2,3,4), matching the Rust golden dump.
goldenPalette :: [OKLab]
goldenPalette =
  [ OKLab 0.20 0.05 (-0.10), OKLab 0.80 (-0.10) 0.10
  , OKLab 0.50 0.00 0.00,    OKLab 0.30 0.15 0.05 ]

goldenWeights :: [Double]
goldenWeights = [1, 2, 3, 4]

tests :: TestTree
tests = testGroup "Diversity (variety: Gaussian entropy + effective dim)"
  [ -- Golden cross-checks vs the Rust oracle (analysis-core dump).
    testProperty "golden: gaussianColorEntropy matches the Rust oracle" $
      once $
        abs (gaussianColorEntropy goldenPalette goldenWeights - (-5.107467162247)) < 1e-9

  , testProperty "golden: effectiveDim matches the Rust oracle (trace identity)" $
      once $
        abs (effectiveDim (zip goldenPalette goldenWeights) - 1.154985618198) < 1e-9

  , testProperty "effectiveDim ∈ [0,3] for any candidate cloud" $
      forAll genCands $ \cs ->
        let d = effectiveDim cs in d >= -1e-9 && d <= 3 + 1e-9

  , -- Knowledge: collinear colours ≈ 1D, a filled volume ≈ 3D.
    testProperty "effectiveDim: a colinear cloud is ~1D, an axis-spread cloud is ~3D" $
      once $
        let line = [ (OKLab t 0 0, 1) | t <- [0.0, 0.1 .. 0.9] ]
            vol  = [ (OKLab l a b, 1) | l <- [0.2,0.8], a <- [-0.2,0.2], b <- [-0.2,0.2] ]
        in effectiveDim line < 1.2 && effectiveDim vol > 2.5

  , -- Knowledge: widening the spread of a palette raises its Gaussian entropy
    -- (more variety = more differential entropy = more "complexity"). Uses a
    -- full-rank cube fixture: cov = diag(s²,s²,s²), det = s⁶ > 0, so entropy
    -- = ½ ln((2πe)³ s⁶) is strictly increasing in s (a coplanar fixture would
    -- floor det at 1e-12 and break monotonicity — that itself is a finding).
    testProperty "gaussianColorEntropy increases with spread (full-rank cube)" $
      forAll (choose (0.02, 0.05)) $ \narrow ->
        forAll (choose (0.15, 0.30)) $ \wide ->
          let cube s = [ OKLab (0.5 + sl) sa sb
                       | sl <- [-s, s], sa <- [-s, s], sb <- [-s, s] ]
              w = replicate 8 1
          in gaussianColorEntropy (cube wide) w > gaussianColorEntropy (cube narrow) w
  ]

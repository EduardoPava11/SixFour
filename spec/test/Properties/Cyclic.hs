module Properties.Cyclic (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Test.QuickCheck

import qualified Data.Vector as V
import           Data.Maybe  (fromJust)

import SixFour.Spec.Color   (OKLab(..))
import SixFour.Spec.Palette (Palette, mkPalette)
import SixFour.Spec.Gauge   (Permutation, mkPermutation)
import SixFour.Spec.StageB  (SinkhornParams(..), sharedSinkhornParams)
import SixFour.Spec.Cyclic
  ( Weights, CyclicStack, mkCyclicStack, descriptor, descriptorDim
  , spectralEntropy )
import SixFour.Spec.Laws
  ( lawCyclicClosedness
  , lawDescriptorGaugeInvariant
  , lawDescriptorCyclicShiftInvariant
  , lawPaletteEntropyBounds
  , lawSpectralEntropyBounds )

-- Tiny shapes for speed: T = 8 frames, K = 8 colours.
type T = 8
type K = 8

-- | Smoother, well-conditioned OT for stable invariance equality.
testParams :: SinkhornParams
testParams = sharedSinkhornParams { spEpsilon = 0.2, spIterCount = 30 }

-- Generators --------------------------------------------------------------

genOKLab :: Gen OKLab
genOKLab = OKLab <$> choose (0, 1) <*> choose (-0.4, 0.4) <*> choose (-0.4, 0.4)

genFrame :: Gen (Palette K, Weights)
genFrame = do
  cs <- vectorOf 8 genOKLab
  ws <- vectorOf 8 (choose (0.01, 1.0))
  pure (fromJust (mkPalette @K cs), V.fromList ws)

genStack :: Gen (CyclicStack T K)
genStack = fromJust . mkCyclicStack @T <$> vectorOf 8 genFrame

genPerm :: Gen (Permutation K)
genPerm = fromJust . mkPermutation @K <$> shuffle [0 .. 7]

-- Tests -------------------------------------------------------------------

tests :: TestTree
tests = testGroup "Cyclic palette environment (MATH.md §8)"
  [ testProperty "Thm 4: cyclic deltas telescope to zero" $
      forAll genStack $ \stk -> lawCyclicClosedness 1e-9 stk

  , testProperty "Thm 5: descriptor is S_K gauge-invariant" $
      forAll ((,) <$> genStack <*> genPerm) $ \(stk, sigma) ->
        lawDescriptorGaugeInvariant testParams 1e-6 sigma stk

  , testProperty "Thm 5: descriptor is Z_T cyclic-shift-invariant" $
      forAll genStack $ \stk ->
        lawDescriptorCyclicShiftInvariant testParams 1e-6 stk

  , testProperty "Def 15: palette entropy within [0, log K]" $
      forAll (vectorOf 8 (choose (0, 1))) $ \ws ->
        lawPaletteEntropyBounds 8 (V.fromList ws)

  , testProperty "Def 18: spectral entropy within [0, log (N-1)]" $
      forAll (vectorOf 8 (choose (-5, 5))) $ \xs ->
        lawSpectralEntropyBounds xs

  , testProperty "Def 18: a constant (still) loop has zero spectral entropy" $
      once $ spectralEntropy (replicate 8 3.0) <= 1e-12

  , testProperty "Def 18: a single-frequency loop has spectral entropy = log 2" $
      once $
        let xs = [ cos (2 * pi * fromIntegral n / 8) | n <- [0 .. 7 :: Int] ]
        in abs (spectralEntropy xs - log 2) < 1e-6

  , testProperty "Def 20: descriptor has fixed dimension" $
      forAll genStack $ \stk ->
        V.length (descriptor testParams stk) == descriptorDim
  ]

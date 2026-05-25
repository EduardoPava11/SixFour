module Properties.Look (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Test.QuickCheck

import qualified Data.Vector as V
import           Data.Maybe  (fromJust)

import SixFour.Spec.Color   (OKLab(..))
import SixFour.Spec.Palette (Palette(..))
import SixFour.Spec.Look

genOKLab :: Gen OKLab
genOKLab = OKLab <$> choose (0, 1) <*> choose (-0.4, 0.4) <*> choose (-0.4, 0.4)

genPalette :: Gen (Palette 8)
genPalette = (Palette . V.fromList) <$> vectorOf 8 genOKLab

genCode :: Gen LookCode
genCode = (fromJust . mkLookCode) <$> vectorOf lookDim (choose (-1, 1))

tests :: TestTree
tests = testGroup "Look contract (MATH.md §9)"
  [ testProperty "neutral code is identity (reset recovers the baseline)" $
      forAll genPalette $ \p -> lawLookNeutralIdentity 1e-9 affineLook p
  , testProperty "gamut closure (no invalid colours for any code)" $
      forAll ((,) <$> genCode <*> genPalette) $ \(s, p) -> lawLookGamutClosure affineLook s p
  , testProperty "bounded effect (a bounded knob moves colours boundedly)" $
      forAll ((,) <$> genCode <*> genPalette) $ \(s, p) -> lawLookBounded affineLook s p
  , testProperty "continuity (small code change ⇒ small look change)" $
      forAll ((,,) <$> genCode <*> genCode <*> genPalette) $ \(s, s', p) ->
        lawLookContinuity affineLook s s' p
  ]

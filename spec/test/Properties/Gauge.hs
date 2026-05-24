module Properties.Gauge (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Test.QuickCheck

import qualified Data.List as List
import           Data.Maybe (fromJust)
import           GHC.TypeLits (KnownNat)
import           Data.Proxy (Proxy(..))

import SixFour.Spec.Color    (OKLab(..))
import SixFour.Spec.Palette  (Palette, mkPalette)
import SixFour.Spec.Indices  (IndexTensor, mkIndexTensor)
import SixFour.Spec.Gauge    (Permutation, mkPermutation, gaugeAction, gather)
import SixFour.Spec.Laws     (lawGaugeIdentity)

-- We test on a tiny @K = 4@, @T = H = W = 2@ tensor so QuickCheck can
-- generate cheaply. The proof is independent of size.

type K = 4
type T = 2
type H = 2
type W = 2

genOKLab :: Gen OKLab
genOKLab = OKLab <$> choose (0, 1) <*> choose (-0.4, 0.4) <*> choose (-0.4, 0.4)

genPalette :: Gen (Palette K)
genPalette = do
  xs <- vectorOf 4 genOKLab
  pure (fromJust (mkPalette xs))

genIndices :: Gen (IndexTensor T H W K)
genIndices = do
  xs <- vectorOf (2 * 2 * 2) (choose (0, 3))   -- T*H*W = 8 indices in [0,3]
  pure (fromJust (mkIndexTensor xs))

genPermutation :: Gen (Permutation K)
genPermutation = do
  let n = 4 :: Int
  perm <- shuffle [0 .. n - 1]
  pure (fromJust (mkPermutation perm))

tests :: TestTree
tests = testGroup "Gauge"
  [ testProperty "gauge invariance: decode (σ·P, σ⁻¹·I) ≡ decode (P, I)" $
      forAll genPermutation $ \sigma ->
        forAll genPalette   $ \p ->
        forAll genIndices   $ \i ->
          lawGaugeIdentity sigma p i
  , testProperty "identity permutation is a no-op" $
      forAll genPalette $ \p ->
      forAll genIndices $ \i ->
        let idPerm = fromJust (mkPermutation @K [0, 1, 2, 3])
            (p', i') = gaugeAction idPerm p i
            v1 = gather p  i
            v2 = gather p' i'
        in v1 == v2
  ]

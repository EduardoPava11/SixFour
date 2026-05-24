module Properties.Surjectivity (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Test.QuickCheck

import qualified Data.Set as Set
import           Data.Maybe (fromJust, isJust, isNothing)

import SixFour.Spec.Indices (mkIndexTensor, mkSurjective256)

-- Tiny @K = 4@, @T*H*W = 12@ case so the witness is meaningful.

type K = 4
type T = 3
type H = 2
type W = 2

tests :: TestTree
tests = testGroup "Surjectivity"
  [ testProperty "Surjective256 accepts a tensor that uses every index 0..K-1" $
      once $
        let v = [0,1,2,3, 0,1,2,3, 0,1,2,3]   -- length 12, covers {0,1,2,3}
            it = fromJust (mkIndexTensor @T @H @W @K v)
        in isJust (mkSurjective256 @T @H @W @K it)
  , testProperty "Surjective256 rejects a tensor missing index 3" $
      once $
        let v = [0,1,2,0, 0,1,2,0, 0,1,2,0]   -- never uses 3
            it = fromJust (mkIndexTensor @T @H @W @K v)
        in isNothing (mkSurjective256 @T @H @W @K it)
  , testProperty "out-of-range indices fail mkIndexTensor" $
      once $
        isNothing (mkIndexTensor @T @H @W @K [0,1,2,4, 0,0,0,0, 0,0,0,0])
  , testProperty "wrong-length indices fail mkIndexTensor" $
      once $
        isNothing (mkIndexTensor @T @H @W @K [0,1,2,3])
  ]

module Properties.MoveSignal (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.Dim6 (Dim6(..))
import SixFour.Spec.OctreeCell (Detail)
import SixFour.Spec.TwoMoveOctave (AbMove(..), Octave(..))
import SixFour.Spec.MoveSignal

genMove :: Gen AbMove
genMove = AbMove
  <$> elements [DimA, DimB]
  <*> elements [-1, 1]
  <*> elements [CoarseGlobal, FineLocal]

genDetail :: Gen Detail
genDetail = (,,,,,,) <$> b <*> b <*> b <*> b <*> b <*> b <*> b
  where b = choose (-32768, 32768)

tests :: TestTree
tests = testGroup "MoveSignal (the content-responsive move signal v1: texture energy x sensitivity)"
  [ testProperty "a FLAT octant carries zero signal" $
      forAll genMove lawFlatOctantZeroSignal
  , testProperty "KEYSTONE: a textured move strictly exceeds a flat one (what moveMagnitude cannot)" $
      forAll genMove $ \m -> forAll genDetail $ \d -> lawTexturedMoveStrictlyExceedsFlat m d
  , testProperty "the signal is a deterministic, finite, non-negative float" $
      forAll genMove $ \m -> forAll genDetail $ \d -> lawSignalIsDeterministicFiniteFloat m d
  , testProperty "the signal is quarantined from the commit (cannot move bytes)" $
      once lawSignalQuarantinedFromCommit
  ]

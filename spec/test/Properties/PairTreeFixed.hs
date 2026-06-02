module Properties.PairTreeFixed (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.PairTreeFixed

-- A Q16 OKLab triple: L ∈ [0, 2^16], a,b ∈ [±0.4·2^16].
genPxI :: Gen OKLabI
genPxI = (,,) <$> choose (0, 65536) <*> choose (-26214, 26214) <*> choose (-26214, 26214)

-- A power-of-two leaf list (depth 0..6 → 1..64 leaves), so analyze/reconstruct align.
genPow2Leaves :: Gen [OKLabI]
genPow2Leaves = do
  d <- choose (0, 6) :: Gen Int
  vectorOf (2 ^ d) genPxI

-- A well-formed integer Haar palette of depth 0..6.
genHaarI :: Gen HaarPaletteI
genHaarI = analyzeFixed <$> genPow2Leaves

genMoveI :: Gen MoveI
genMoveI = MoveI <$> choose (0, 6) <*> choose (0, 63) <*> genPxI

tests :: TestTree
tests = testGroup "PairTreeFixed (owned integer Haar — reversible lifting)"
  [ testProperty "atomic lift inverts EXACTLY for any integer pair" $
      forAll genPxI $ \x -> forAll genPxI $ \y -> lawLiftPairInvertsExactly x y

  , testProperty "reconstruct ∘ analyze = id EXACTLY (no tolerance) on 2^D leaves" $
      forAll genPow2Leaves lawReconstructAnalyzeRoundTripExact

  , testProperty "analyze/reconstruct preserve tree structure (2^D leaves, depth)" $
      forAll genHaarI lawAnalyzeReconstructStructure

  , testProperty "move ∘ inverse-move = id EXACTLY (integer reversibility)" $
      forAll genMoveI $ \m -> forAll genHaarI $ \s -> lawMoveRoundTripExact m s

  , testProperty "a move preserves well-formedness (structure unchanged)" $
      forAll genMoveI $ \m -> forAll genHaarI $ \s -> lawMovePreservesWellFormed m s
  ]

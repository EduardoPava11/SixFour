module Properties.Quad4Fixed (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.PairTreeFixed (OKLabI)
import SixFour.Spec.Quad4Fixed

genPxI :: Gen OKLabI
genPxI = (,,) <$> choose (-20000, 20000) <*> choose (-20000, 20000) <*> choose (-20000, 20000)

-- A well-formed depth-4 integer Quad4 tree (levels of 1, 4, 16, 64 offset pairs).
genQuad4I :: Gen Quad4PaletteI
genQuad4I = do
  rt   <- genPxI
  lvls <- mapM (\l -> vectorOf (4 ^ l) ((,) <$> genPxI <*> genPxI)) [0 .. quad4FixedDepth - 1]
  pure (Quad4PaletteI rt lvls)

tests :: TestTree
tests = testGroup "Quad4Fixed (owned integer 4⁴ genome — exact on subspace, no tolerance)"
  [ testProperty "analyze ∘ reconstruct = id EXACTLY on the Quad4 subspace" $
      forAll genQuad4I lawQuad4FixedAnalyzeReconstructExact

  , testProperty "reconstruct emits the balance constraint c₀−c₁−c₂+c₃ = 0 exactly" $
      forAll genQuad4I lawQuad4FixedReconstructBalanced
  ]

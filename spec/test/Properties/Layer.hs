module Properties.Layer (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Test.QuickCheck

import qualified Data.Vector as V
import           Data.Maybe  (fromJust, isJust)

import SixFour.Spec.Color    (OKLab(..))
import SixFour.Spec.Palette  (Palette, mkPalette)
import SixFour.Spec.Cyclic   (CyclicStack(..), Weights)
import SixFour.Spec.Indices  (IndexTensor(..), mkIndexTensor, indexTensorLength)
import SixFour.Spec.PairTree (reconstruct)
import SixFour.Spec.LookNet
  (LayerKind(..), LookInput(..), LookOutput(..), runLookNet, baselinePalette)
import SixFour.Spec.Layer

-- Tiny shapes for the worked example: T=2 frames, 2×2 pixels, K=4 colours
-- (the same family Properties.LookNet uses).
type T = 2
type H = 2
type W = 2
type K = 4

genOKLab :: Gen OKLab
genOKLab = OKLab <$> choose (0, 1) <*> choose (-0.4, 0.4) <*> choose (-0.4, 0.4)

-- A frame: a K-colour palette + strictly positive population weights (so the
-- pooled mixture has positive mass and renormalises to 1).
genFrame :: Gen (Palette K, Weights)
genFrame = do
  cs <- vectorOf 4 genOKLab
  ws <- vectorOf 4 (choose (0.1, 5.0))
  pure (fromJust (mkPalette @K cs), V.fromList ws)

genStack :: Gen (CyclicStack T K)
genStack = do
  f1 <- genFrame
  f2 <- genFrame
  pure (CyclicStack (V.fromList [f1, f2]))

-- A look-input's Show-able ingredients: a stack plus a local index list (T·H·W
-- = 8 voxels in [0, K)). Built into a 'LookInput' inside the property (LookInput
-- itself has no Show instance, which 'forAll' would require).
genInputParts :: Gen (CyclicStack T K, [Int])
genInputParts = (,) <$> genStack <*> vectorOf 8 (choose (0, 3))

tests :: TestTree
tests = testGroup "Layer (typeclass layers; type-checked composition + bound laws)"
  [ -- runPipe threads the typed layers exactly as the hand composition does.
    testProperty "typed pipe == manual composition (reconstruct . lookFloor)" $
      forAll genStack lawPipeMatchesManual

    -- The collapse target: the palette path yields exactly K colours.
  , testProperty "palette path reconstructs to K leaves" $
      forAll genStack lawPaletteHasKLeaves

    -- The floor palette is σ-balanced (offsets cancel ⇒ mean of leaves = root).
  , testProperty "floor palette is balanced (mean leaves = root)" $
      forAll genStack (lawFloorBalanced 1e-9)

    -- L1–L2 pools to a probability measure (total weight 1).
  , testProperty "pool renormalises mixture to total weight 1" $
      forAll genStack (lawPoolWeightNormalised 1e-9)

    -- The learnable layer's neutral code (zero residual) is the floor (reset).
  , testProperty "LookCore neutral residual == floor (reset)" $
      forAll genStack lawLayerNeutralResidualIsFloor

    -- The typed composition, surfaced: names + kinds, in order. This is the
    -- inspectable counterpart of the value-level lookNetLayers table — but the
    -- ORDER and the type-fit were enforced by the compiler, not asserted here.
  , testProperty "palettePipe layer spec = [LookCore(Learnable), Reconstruct(Det)]" $
      once $
        map snd (pipeSpec (palettePipe @T @K)) == [Learnable, Deterministic]
        && length (pipeSpec (palettePipe @T @K)) == 2

    -- The whole-net Layer instance agrees with the reference runLookNet, and its
    -- output is well-formed: K-leaf palette + full T·H·W index tensor + witness.
  , testProperty "WholeLookNet layer == runLookNet (baselinePalette ·) and is well-formed" $
      forAll genInputParts $ \(stk, ixs) ->
        let inp      = LookInput stk (fromJust (mkIndexTensor @T @H @W @K ixs))
            viaLayer = runWholeLookNet inp
            viaRef   = runLookNet (baselinePalette (liStack inp)) inp
        in loPalette viaLayer == loPalette viaRef
           && loIndices viaLayer == loIndices viaRef
           && isJust (loGlobalComplete viaLayer) == isJust (loGlobalComplete viaRef)
           && length (reconstruct (loPalette viaLayer)) == 4
           && indexTensorLength (loIndices viaLayer) == 2 * 2 * 2
  ]

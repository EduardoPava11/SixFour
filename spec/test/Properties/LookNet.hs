module Properties.LookNet (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Test.QuickCheck
import Text.Printf (printf)

import qualified Data.Vector         as V
import qualified Data.Vector.Unboxed as U
import           Data.Maybe (fromJust, isJust, isNothing)

import SixFour.Spec.Color    (OKLab(..))
import SixFour.Spec.Palette  (mkPalette)
import SixFour.Spec.Cyclic   (CyclicStack(..), Weights)
import SixFour.Spec.Indices
import SixFour.Spec.PairTree (HaarPalette(..), reconstruct, degreesOfFreedom)
import SixFour.Spec.Net      (NetIO(..))
import SixFour.Spec.GMM      (gaussianToken)
import SixFour.Spec.LookNet

-- Tiny shapes for the worked example: T=2 frames, 2×2 pixels, K=4 colours.
type T = 2
type H = 2
type W = 2
type K = 4

genOKLab :: Gen OKLab
genOKLab = OKLab <$> choose (0, 1) <*> choose (-0.4, 0.4) <*> choose (-0.4, 0.4)

-- A fixed depth-2 (K=4) Haar palette with four distinct leaves, so the
-- local→global remap is the identity (each colour is its own nearest).
fixedHaar :: HaarPalette
fixedHaar = HaarPalette (OKLab 0.5 0 0)
              [ [OKLab 0.2 0 0]
              , [OKLab 0 0.1 0, OKLab 0 0 0.1] ]

-- The look-input where the two frames share the global palette but each uses only
-- HALF the indices: frame0 → {0,1}, frame1 → {2,3}. Union = all 4 (global
-- surjective) yet no frame is per-frame complete.
fixedInput :: LookInput T H W K
fixedInput =
  let global = reconstruct fixedHaar                       -- 4 distinct OKLab
      pal    = fromJust (mkPalette @K global)
      w      = V.fromList [1, 1, 1, 1] :: Weights
      stack  = CyclicStack (V.fromList [(pal, w), (pal, w)]) :: CyclicStack T K
      locIx  = fromJust (mkIndexTensor @T @H @W @K [0,0,1,1, 2,2,3,3])
  in LookInput stack locIx

chainComposes :: [LayerSpec] -> Bool
chainComposes xs = and (zipWith (\a b -> lsOutDim a == lsInDim b) xs (drop 1 xs))

tests :: TestTree
tests = testGroup "LookNet (typed layer dataflow input → palette → GIF)"
  [ testProperty "palette path L1–L6 composes (outDim → inDim)" $
      once (chainComposes paletteChain)

  , testProperty "index path L8–L9 composes" $
      once (chainComposes indexChain)

  , testProperty "dimensional facts: 10 GMM token, dM context, 768 decoder = tree DOF, depth 8" $
      once $
           gmmTokenDim == 10
        && netInputDim encoderIO == gmmTokenDim
        && netOutputDim encoderIO == modelDim
        && netOutputDim decoderIO == 768
        && netOutputDim decoderIO == degreesOfFreedom
        && netInputDim coreIO == netOutputDim encoderIO
        && netInputDim decoderIO == netOutputDim coreIO
        && modelDim > 0
        && maxPonderDepth == 8

  , testProperty "L1 pool = T·K candidates; L2 GMM substrate = T·K tokens of width 10" $
      once $
        let cands = poolCandidates (liStack fixedInput)
            gmm   = poolToGMM (liStack fixedInput)
        in length cands == 2 * 4
           && length gmm == 2 * 4
           && all ((== gmmTokenDim) . length . gaussianToken) gmm

  , -- HEADLINE: the look-NN output is GLOBALLY surjective yet NOT per-frame
    -- complete — the L7 → global-surjectivity change, made observable.
    testProperty "output is global-surjective but per-frame INcomplete (L7 change)" $
      once $
        let out = runLookNet fixedHaar fixedInput
        in isJust (loGlobalComplete out)                              -- ⋃ₜ used = K
           && isNothing (mkCompleteVoxelVolume (loIndices out))       -- no frame complete
           && unIndices (loIndices out) == U.fromList [0,0,1,1,2,2,3,3] -- identity remap

  , testProperty "remap lands in [0, |global|) for any palettes" $
      forAll (choose (1, 8)) $ \ng ->
        forAll (vectorOf ng genOKLab) $ \global ->
          forAll (listOf genOKLab) $ \loc ->
            all (\i -> i >= 0 && i < ng) (remapFrame global loc)

  , -- The dimensional table, surfaced as the knowledge artifact.
    testProperty "look-net layer table snapshot" $
      once $
        tabulate "layer"
          [ printf "%-30s %6d -> %6d  %s" (lsName l) (lsInDim l) (lsOutDim l) (show (lsKind l))
          | l <- lookNetLayers ]
          True
  ]

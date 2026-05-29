{- |
Module      : SixFour.Spec.LookNet
Description : The look-NN's typed dimensional structure — input → palette → GIF.

The ordered layers the look-NN must compute to turn a capture into the **global
palette AND the index mapping** (the whole @T×H×W@ GIF). This is a *dimensional
contract*, not a stub network (the no-stubs rule): the **deterministic** layers are
total reference functions; the **learnable** layers (encoder @E@, core @R@, decoder
@D@) are pinned by 'NetIO' shape contracts only — their weights live in the Phase-C
trainer. The typed-Stage extensions for L3/L4/L5 live in @SixFour.Spec.LookNetE/R/D@.

The substrate is the **continuous OKLab Gaussian mixture** ("SixFour.Spec.GMM"), not
the discrete 11-category code: each palette is a set of @(μ,Σ,w)@ components, fed to a
permutation-invariant set encoder. (The old Berlin–Kay @categorize@ layer was a
fidelity category-error — see @spec/LOOK_NN.md@ §2, redesigned.) Palette-path dims
below are **per component** (the set is processed elementwise then pooled in L3); the
set carries @≤ T·K@ components. The index path (L8–L9) is flat per voxel.

The layer table ('lookNetLayers'):

>  L1 Pool        CyclicStack T K          → ≤T·K Gaussian tokens     det
>  L2 GMM token   Gaussian (μ,Σ,w)         → 10 (continuous substrate) det
>  L3 Encoder E   10 (per component)       → dM (set-pooled)          learn
>  L4 Core R      dM                       → dM  (depth ≤ N)          learn
>  L5 Decoder D   dM                       → 768 (root + 255 offsets) learn
>  L6 Reconstruct 768                      → 256·3 (balanced)        det
>  L7 Remap       global 256 + local T·K   → T·(K→K)                 det
>  L8 GlobalIndex localIndices T·H·W + remap→ T·H·W ∈ [0,256)        det
>  L9 Dither      T·H·W + STBN3D           → T·H·W (the GIF)         learn/det

@dM@ ('modelDim') and @N@ ('maxPonderDepth') are the only free structural dims;
everything else is pinned by @T,H,W,K@ and the Haar tree (@768@). See
@spec/LOOKNET_LAYERS.md@ and @spec/NN_SPACE_NOTES.md@.
-}
module SixFour.Spec.LookNet
  ( -- * The dimensional table
    LayerKind(..)
  , LayerSpec(..)
  , lookNetLayers
  , paletteChain
  , indexChain
    -- * Free structural dimensions
  , modelDim
  , maxPonderDepth
  , gmmTokenDim
    -- * Learnable-layer shape contracts (weights are Phase C)
  , encoderIO
  , coreIO
  , decoderIO
    -- * Input / output
  , LookInput(..)
  , LookOutput(..)
  , runLookNet
  , baselinePalette
    -- * Deterministic reference layers
  , poolCandidates
  , poolToGMM
  , perFramePalettes
  , remapFrame
  , globalIndexTensor
  ) where

import qualified Data.Vector as V
import qualified Data.Vector.Unboxed as U
import           Data.List   (foldl', minimumBy)
import           Data.Ord    (comparing)
import           GHC.TypeLits (Nat, KnownNat, natVal)
import           Data.Proxy   (Proxy(..))

import SixFour.Spec.Color     (OKLab(..), okLabDistanceSquared)
import SixFour.Spec.Palette   (Palette, paletteToList)
import SixFour.Spec.Cyclic    (CyclicStack(..), Weights)
import SixFour.Spec.Collapse  (farthestPointCollapse)
import SixFour.Spec.Indices   (IndexTensor(..), GlobalSurjective, mkGlobalSurjective)
import SixFour.Spec.GMM       (GMM, Gaussian, gmmTokenDim, pointMassGMM, poolGMM)
import SixFour.Spec.PairTree  (HaarPalette, reconstruct, analyze, degreesOfFreedom, paletteDepth)
import SixFour.Spec.SigmaPairHead (sigmaPairDegreesOfFreedom)
import SixFour.Spec.Net       (NetIO(..))
import SixFour.Spec.Shape     (tVal, hVal, wVal, kVal, pixelsPerGIF)

-- | A layer is either a total deterministic reference function, or a learnable
-- block specified by its shape contract only (no weights in the spec).
data LayerKind = Deterministic | Learnable
  deriving (Eq, Show)

-- | One layer of the dataflow: its name and the flat element-count of its primary
-- input and output tensors. (Join layers carry side inputs documented in the name.)
data LayerSpec = LayerSpec
  { lsName   :: !String
  , lsInDim  :: !Int
  , lsOutDim :: !Int
  , lsKind   :: !LayerKind
  } deriving (Eq, Show)

-- | Model width @dM@ — a free hyperparameter (default 64). The encoder/core run
-- at this width; larger trades capacity for on-device cost.
modelDim :: Int
modelDim = 64

-- | Max adaptive recursion/ponder depth @N@. Tied to the 8 Haar levels: one
-- recursion per pairing level is the natural ceiling.
maxPonderDepth :: Int
maxPonderDepth = paletteDepth

-- @gmmTokenDim@ (the per-component substrate width @μ3+Σ6+w1 = 10@) is re-exported
-- from "SixFour.Spec.GMM"; it replaces the old @categoryCodeDim = 88@.

-- | L3 encoder shape contract (Deep Sets / Set-Transformer; permutation-invariant).
-- Applies a per-component map @φ : 10 → dM@ then sum-pools the set to one @dM@
-- context. Equivariant to the OKLab reflection σ (an exact a/b sign-flip).
encoderIO :: NetIO
encoderIO = NetIO
  { netInputDim    = gmmTokenDim
  , netOutputDim   = modelDim
  , netDescription = "L3 set encoder E: per-component (mu,Sigma,w)=10 -> dM context (perm-invariant, set-pooled)"
  }

-- | L4 recursive core shape contract (depth-recurrent; ponder/barycenter-iteration
-- depth ≤ N). Amortizes the Wasserstein-2 / Bures barycenter of the pooled measure.
coreIO :: NetIO
coreIO = NetIO
  { netInputDim    = modelDim
  , netOutputDim   = modelDim
  , netDescription = "L4 core R: dM -> dM context; ONE weight-shared block reused over 8 Haar levels (Mixture-of-Recursions), σ-invariant per-level halting (ponder <= N)"
  }

-- | L5 σ-pair tree decoder shape contract: context → the 384 SigmaPairTree
-- coefficients (root + 127 offsets, a depth-7 generator pyramid); per-level
-- heads correspond to @SixFour.Spec.LookNetD.decoderLevelDims@. The 384 DOF is
-- exactly the σ-symmetric palette subspace dimension; L6 σ-pair-interleaves the
-- 128 generators into the 256-leaf palette (SigmaPairHead pivot, NOTES 2026-05-28).
decoderIO :: NetIO
decoderIO = NetIO
  { netInputDim    = modelDim
  , netOutputDim   = sigmaPairDegreesOfFreedom
  , netDescription = "L5 sigma-pair tree decoder D: dM -> 384 SigmaPairTree coefficients (root + 127 sigma-balanced generator offsets)"
  }

-- | The full nine-layer dimensional table (for display / inspection).
lookNetLayers :: [LayerSpec]
lookNetLayers = paletteChain ++ [remapLayer] ++ indexChain
  where remapLayer = LayerSpec "L7 Remap (join: +global palette)" (tVal * kVal * 3) (tVal * kVal) Deterministic

-- | The palette path L1–L6 (a linear chain; 'lawChainComposes' checks it).
paletteChain :: [LayerSpec]
paletteChain =
  [ LayerSpec "L1 Pool"        gmmTokenDim     gmmTokenDim     Deterministic
  , LayerSpec "L2 GMM token"   gmmTokenDim     gmmTokenDim     Deterministic
  , LayerSpec "L3 Encoder E"   (netInputDim encoderIO) (netOutputDim encoderIO) Learnable
  , LayerSpec "L4 Core R"      (netInputDim coreIO)    (netOutputDim coreIO)    Learnable
  , LayerSpec "L5 Decoder D"   (netInputDim decoderIO) (netOutputDim decoderIO) Learnable
  , LayerSpec "L6 Reconstruct" (netOutputDim decoderIO) (kVal * 3) Deterministic
  ]

-- | The index path L8–L9 (a linear chain over the @T·H·W@ voxel tensor).
indexChain :: [LayerSpec]
indexChain =
  [ LayerSpec "L8 GlobalIndex (join: +remap)" pixelsPerGIF pixelsPerGIF Deterministic
  , LayerSpec "L9 Dither (+STBN3D)"           pixelsPerGIF pixelsPerGIF Learnable
  ]

-- ----------------------------------------------------------------------------
-- Input / output
-- ----------------------------------------------------------------------------

-- | What the look-NN consumes: the per-frame palettes + weights (synthesizable
-- via @analysis-core::synth@) and the per-frame Stage-A local index tensor.
data LookInput (t :: Nat) (h :: Nat) (w :: Nat) (k :: Nat) = LookInput
  { liStack        :: !(CyclicStack t k)
  , liLocalIndices :: !(IndexTensor t h w k)
  }

-- | What it produces: the global palette (as the Haar tree — 256 = 128 balanced
-- pairs by construction), the global index mapping (the GIF), and the
-- 'GlobalSurjective' witness (a 'Nothing' forces a documented fallback).
data LookOutput (t :: Nat) (h :: Nat) (w :: Nat) (k :: Nat) = LookOutput
  { loPalette        :: !HaarPalette
  , loIndices        :: !(IndexTensor t h w k)
  , loGlobalComplete :: !(Maybe (GlobalSurjective t h w k))
  }

-- | The deterministic scaffold (L6–L8): given the decoded Haar palette (the NN's
-- output, or a 'baselinePalette'), reconstruct the global palette, remap each
-- frame's local palette to nearest global, lift the local index tensor to the
-- global one, and compute the surjectivity witness. The learnable L3–L5 produce
-- the 'HaarPalette' argument; they are not run here (no weights in the spec).
runLookNet
  :: forall t h w k. (KnownNat t, KnownNat h, KnownNat w, KnownNat k)
  => HaarPalette
  -> LookInput t h w k
  -> LookOutput t h w k
runLookNet hp (LookInput stack localIx) =
  let global   = reconstruct hp                         -- L6: 256 OKLab leaves
      locals   = perFramePalettes stack                 -- per-frame local palettes
      remaps   = map (remapFrame global) locals         -- L7: T × (K→K)
      globalIx = globalIndexTensor remaps localIx        -- L8: T·H·W into [0,K)
  in LookOutput
       { loPalette        = hp
       , loIndices        = globalIx
       , loGlobalComplete = mkGlobalSurjective globalIx
       }

-- | A deterministic baseline palette: collapse the per-frame palettes by
-- farthest-point (the fidelity floor) and read it back as a Haar tree via
-- 'analyze'. This farthest-point/k-means collapse IS the free-support
-- Wasserstein-2 barycenter (@LOOK_NN.md@ Thm 9); 'SixFour.Spec.Bures.buresBarycenter'
-- is its parametric (Gaussian) companion. Lets the scaffold run end-to-end without the
-- learnable net; the trained decoder is the controlled deviation from this floor.
baselinePalette
  :: forall t k. KnownNat k
  => CyclicStack t k -> HaarPalette
baselinePalette (CyclicStack frames) =
  analyze (paletteToList (farthestPointCollapse [ pal | (pal, _) <- V.toList frames ]))

-- ----------------------------------------------------------------------------
-- Deterministic reference layers
-- ----------------------------------------------------------------------------

-- | L1 Pool: flatten the cyclic stack into the @T·K@ weighted candidate cloud.
poolCandidates :: CyclicStack t k -> [(OKLab, Double)]
poolCandidates (CyclicStack frames) =
  concat [ zip (paletteToList pal) (V.toList w) | (pal, w) <- V.toList frames ]

-- | L1–L2 substrate: pool the per-frame palettes+weights into one renormalised
-- **Gaussian mixture** ('SixFour.Spec.GMM') — the continuous, category-free input the
-- set encoder consumes. The spec's 'CyclicStack' carries means+weights only, so each
-- component is a point mass; on device the per-component covariance Σ comes from
-- @ClusterStatistics@ (the only enrichment). No 11-bucket binning, no metric weights.
poolToGMM :: CyclicStack t k -> GMM
poolToGMM stack = poolGMM [ pointMassGMM frame | frame <- framesAsCandidates stack ]

-- | Each frame's @(colour, weight)@ candidate list (the per-frame palette + weights).
framesAsCandidates :: CyclicStack t k -> [[(OKLab, Double)]]
framesAsCandidates (CyclicStack frames) =
  [ zip (paletteToList pal) (V.toList w) | (pal, w) <- V.toList frames ]

-- | Per-frame local palettes (the colours each frame's Stage-A palette holds).
perFramePalettes :: CyclicStack t k -> [[OKLab]]
perFramePalettes (CyclicStack frames) = [ paletteToList pal | (pal, _) <- V.toList frames ]

-- | L7 Remap: each local palette entry → index of the nearest global colour.
remapFrame :: [OKLab] -> [OKLab] -> [Int]
remapFrame global localPal = map (nearestIdx global) localPal

nearestIdx :: [OKLab] -> OKLab -> Int
nearestIdx pal c =
  snd (minimumBy (comparing fst) [ (okLabDistanceSquared c g, i) | (i, g) <- zip [0 ..] pal ])

-- | L8 GlobalIndex: lift the per-frame local index tensor to the global palette,
-- @global(t,y,x) = remapₜ(local(t,y,x))@.
globalIndexTensor
  :: forall t h w k. (KnownNat t, KnownNat h, KnownNat w, KnownNat k)
  => [[Int]]                  -- ^ per-frame remap tables (length @t@, each length @k@)
  -> IndexTensor t h w k
  -> IndexTensor t h w k
globalIndexTensor remaps (IndexTensor v) =
  let nh       = fromIntegral (natVal (Proxy :: Proxy h)) :: Int
      nw       = fromIntegral (natVal (Proxy :: Proxy w)) :: Int
      perFrame = nh * nw
      remapVec = V.fromList (map U.fromList remaps)
      v'       = U.imap (\p localIdx -> (remapVec V.! (p `div` perFrame)) U.! localIdx) v
  in IndexTensor v'

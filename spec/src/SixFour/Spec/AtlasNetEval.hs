{-# LANGUAGE ScopedTypeVariables #-}

{- |
Module      : SixFour.Spec.AtlasNetEval
Description : Concrete numeric forward for the Atlas policy/value heads — the golden-vector oracle.

This is the AlphaZero-reframe companion to "SixFour.Spec.LookNetEval". Where
LookNetEval computes the look-NN backbone forward (E->R->D -> 384 genome), this
module computes the /Atlas head/ forward on top of that backbone: board tokens +
genome -> fused context -> (factored policy logits over the 1,524-move vocab,
scalar value). It is a faithful Haskell port of @trainer\/atlas_net_mlx.py@ (the
ONLY existing forward definition of these heads), captured here so the spec is the
bit-exact ordinal oracle for the hand-written Metal forward (build phase M3).

Provenance / pivot note (2026-06-17): the supervised MLX look-net was abandoned;
its trained weights were deleted. We port the IDEAS (the sigma-masked head
algebra), NOT the weights. 'deterministicAtlasWeights' is a fixed bounded fill,
the gate verifies the COMPUTATION, any weights work as long as every port
reproduces this output. Two known follow-ups, deliberately NOT applied here so this
oracle pins TODAY's forward exactly:

  * v1 deployment REPLACES the nonlinear value head ('atlasValue', a 24->32->1 MLP)
    with a LINEAR utility over the 770-D atlasEmbedding (== @btUpdate@,
    "SixFour.Spec.PreferenceUpdate"), see design doc section 4.1. We keep the MLP
    here because it is what @atlas_net_mlx.py@ actually computes.
  * The delta head's sigma-row-swap uses the prototype's uniform @[w, w*ctxSign]@
    interleave. Design section 4.3 corrects the involution (L-pair fixed pointwise,
    only chroma pairs swap), which is a future law (build phase L1); this oracle
    mirrors the prototype, not the correction.

The numeric contract is fp32 ORDINAL-only (the value/logits guide search; the
cross-device invariant is the argmax and @sign(V_w - V_l)@, not the float). Weights
are stored RAW (pre-mask); 'atlasForward' applies the sigma-masks at call time,
exactly as the on-device module will.
-}
-- COMPARTMENT: METAL-GPU | tag:MacTag | STRADDLER
module SixFour.Spec.AtlasNetEval
  ( AtlasNetWeights(..)
  , deterministicAtlasWeights
  , AtlasForwardTrace(..)
  , atlasForward
  , atlasTestCases
    -- * dimensions (mirror atlas_net_mlx.py)
  , atlasTokenDim, tokenExtDim, ctxDim, invProjDim, nSlots, nDeltas, nVocab
    -- * the head sigma-masks as 0/1 Double vectors (raw -> effective)
  , extMask, gencMask, ctxSign
  ) where

import qualified Data.Vector.Unboxed as U

import SixFour.Spec.Tensor   (Tensor1(..), sigma64Mask, hiddenAchromaticDim)
import SixFour.Spec.LookNetE (HiddenContext(..))
import SixFour.Spec.LookNetR
  ( SharedBlock(..), runRecursion, sigmaInvariantFeatures, coreDepth )
import SixFour.Spec.LookNetD (sigmaDecoderMask)
import SixFour.Spec.LookNetEval
  ( LookNetWeights(..), deterministicTestWeights, phiMask, sigma64MaskD )

-- =============================================================================
-- Pinned dimensions (atlas_net_mlx.py §"Pinned dimensions")
-- =============================================================================

-- | Atlas token width: 10 base GMM dims ++ 3 σ-invariant curation scalars.
atlasTokenDim :: Int
atlasTokenDim = 13

-- | The φ′ extension columns (σ-invariant), fed only to achromatic hidden dims.
tokenExtDim :: Int
tokenExtDim = 3

-- | Fused context width: @2 * modelDim = 128@ (64 board ‖ 64 genome).
ctxDim :: Int
ctxDim = 2 * modelDim

-- | σ-invariant projection width: @22 achromatic ++ ‖rg‖² ++ ‖by‖² = 24@.
invProjDim :: Int
invProjDim = hiddenAchromaticDim + 2

-- | Addressable Haar slots (root is unaddressable).
nSlots :: Int
nSlots = 127

-- | DeltaCodebook rows.
nDeltas :: Int
nDeltas = 12

-- | Factored move vocabulary: @nSlots * nDeltas = 1,524@.
nVocab :: Int
nVocab = nSlots * nDeltas

-- Local backbone constants (mirror look_net_mlx; modelDim = hiddenDim = 64).
modelDim :: Int
modelDim = 64

sigmaPairDof :: Int
sigmaPairDof = 384

-- | First chromatic index (= end of the achromatic block).
aDim :: Int
aDim = hiddenAchromaticDim                 -- 22

-- | End of the red-green block (start of blue-yellow). @22 + 21 = 43@.
rgEnd :: Int
rgEnd = aDim + 21

-- =============================================================================
-- Head σ-masks (0/1 Double, row-major (out × in), applied to RAW weights)
-- =============================================================================

-- | φ′ extension mask (64×3): a σ-invariant input may feed ONLY the σ-fixed
-- (achromatic) hidden dims, so free iff @not (sigma64Mask[o])@. Mirrors
-- @_block_diagonal_mask([False]*3, SIGMA64_MASK)@.
extMask :: U.Vector Double
extMask = U.generate (modelDim * tokenExtDim) $ \k ->
  let o = k `div` tokenExtDim
  in if not (sigma64Mask !! o) then 1 else 0

-- | Genome-encoder mask (64×384): free iff @sigma64Mask[o] == sigmaDecoderMask[i]@.
-- Mirrors @_block_diagonal_mask(SIGMA_DECODER_MASK, SIGMA64_MASK)@ (transposed).
gencMask :: U.Vector Double
gencMask = U.generate (modelDim * sigmaPairDof) $ \k ->
  let o = k `div` sigmaPairDof; i = k `mod` sigmaPairDof
  in if (sigma64Mask !! o) == (sigmaDecoderMask !! i) then 1 else 0

-- | Sign of each fused-ctx dim under σ: @+1@ achromatic, @-1@ chromatic, repeated
-- across the board and genome halves (length 128). Used by the delta-head row tie.
ctxSign :: U.Vector Double
ctxSign =
  let half = [ if j < aDim then 1 else (-1) | j <- [0 .. modelDim - 1] ]
  in U.fromList (half ++ half)

-- =============================================================================
-- Weights (RAW, pre-mask; row-major (out × in), nn.Linear layout)
-- =============================================================================

-- | The Atlas head weights, ON TOP of the look-NN backbone ('LookNetWeights'
-- supplies @wPhi@/@wW1@/@wW2@/@wHaltW@/@wHaltB@). Flat row-major @(out, in)@.
data AtlasNetWeights = AtlasNetWeights
  { aBackbone  :: !LookNetWeights     -- ^ phi + L4 recursion (+ halt), reused
  , aPhiExt    :: !(U.Vector Double)  -- ^ φ′ extension: 64×3
  , aGenomeEnc :: !(U.Vector Double)  -- ^ genome encoder: 64×384
  , aNodeHead  :: !(U.Vector Double)  -- ^ node head: 127×24
  , aDeltaHalf :: !(U.Vector Double)  -- ^ delta head stored half: 6×128
  , aV1        :: !(U.Vector Double)  -- ^ value MLP W1: 32×24
  , aV1b       :: !(U.Vector Double)  -- ^ value MLP b1: 32
  , aV2        :: !(U.Vector Double)  -- ^ value MLP W2: 1×32
  , aV2b       :: !Double             -- ^ value MLP b2: 1
  } deriving (Eq, Show)

-- | A fixed bounded fill @w_k = 0.1·sin(seed + k)@ (distinct seed per matrix);
-- bounded ⇒ no NaN/Inf. Identical convention to 'LookNetEval'.
genFill :: Double -> Int -> U.Vector Double
genFill seed n = U.generate n (\k -> 0.1 * sin (seed + fromIntegral k))

-- | A fixed, reproducible Atlas weight set — the controlled input the golden
-- vectors are computed from (NOT trained; the MLX weights are abandoned).
deterministicAtlasWeights :: AtlasNetWeights
deterministicAtlasWeights = AtlasNetWeights
  { aBackbone  = deterministicTestWeights
  , aPhiExt    = genFill 20 (modelDim * tokenExtDim)
  , aGenomeEnc = genFill 21 (modelDim * sigmaPairDof)
  , aNodeHead  = genFill 22 (nSlots * invProjDim)
  , aDeltaHalf = genFill 23 ((nDeltas `div` 2) * ctxDim)
  , aV1        = genFill 24 (32 * invProjDim)
  , aV1b       = genFill 25 32
  , aV2        = genFill 26 (1 * 32)
  , aV2b       = 0.05
  }

-- =============================================================================
-- Forward pass (mirrors atlas_net_mlx.py exactly)
-- =============================================================================

-- | Masked-Linear product @y[o] = Σ_i W[o,i]·x[i]@, @W@ flat row-major (out × inn).
linear :: Int -> Int -> U.Vector Double -> U.Vector Double -> U.Vector Double
linear outN innN w x =
  U.generate outN $ \o ->
    let base = o * innN
    in U.sum (U.generate innN (\i -> (w U.! (base + i)) * (x U.! i)))

-- | Full Atlas forward trace: the fused 128-D context, the 1,524 policy logits,
-- and the scalar value.
data AtlasForwardTrace = AtlasForwardTrace
  { atfContext :: ![Double]   -- ^ 128 (board ‖ genome)
  , atfPolicy  :: ![Double]   -- ^ 1524 factored logits, slot-major
  , atfValue   :: !Double     -- ^ scalar (prototype MLP head; see module note)
  } deriving (Eq, Show)

-- | The board pathway: φ over base(10) + φ′ over ext(3), weighted sum-pool, then
-- the L4 recursion; returns the deepest (last) recursion context (64-D).
boardContext :: AtlasNetWeights -> [U.Vector Double] -> [Double] -> U.Vector Double
boardContext w tokens weights =
  let bb     = aBackbone w
      phiM   = U.zipWith (*) (wPhi bb) phiMask
      extM   = U.zipWith (*) (aPhiExt w) extMask
      w1M    = U.zipWith (*) (wW1 bb) sigma64MaskD
      w2M    = U.zipWith (*) (wW2 bb) sigma64MaskD

      placeTok tok =
        let base = U.take 10 tok
            ext  = U.drop 10 tok
        in U.zipWith (+) (linear modelDim 10 phiM base)
                         (linear modelDim tokenExtDim extM ext)
      -- weighted sum-pool over tokens (Σ weights = 1 by construction)
      pooled = case zip tokens weights of
        [] -> U.replicate modelDim 0
        ps -> foldr1 (U.zipWith (+))
                [ U.map (* wt) (placeTok tok) | (tok, wt) <- ps ]

      refine (HiddenContext (Tensor1 x)) =
        let pre = U.map tanh (linear modelDim modelDim w1M x)
            dx  = linear modelDim modelDim w2M pre
        in HiddenContext (Tensor1 (U.zipWith (+) x dx))
      halt ctx =
        let (a, c) = sigmaInvariantFeatures ctx
        in (wHaltW bb U.! 0) * a + (wHaltW bb U.! 1) * c + wHaltB bb
      block    = SharedBlock { sbRefine = refine, sbHalt = halt }
      contexts = runRecursion block (HiddenContext (Tensor1 pooled))
      HiddenContext (Tensor1 deepest) = contexts !! coreDepth
  in deepest

-- | The σ-invariant 24-D projection: summed achromatic halves ++ ‖rg‖² ++ ‖by‖²
-- (squares kill the chroma sign flip exactly).
invProj :: U.Vector Double -> U.Vector Double
invProj ctx =
  let b = U.take modelDim ctx
      g = U.drop modelDim ctx
      achro = U.zipWith (+) (U.take aDim b) (U.take aDim g)
      rg = U.slice aDim (rgEnd - aDim) b U.++ U.slice aDim (rgEnd - aDim) g
      by = U.slice rgEnd (modelDim - rgEnd) b U.++ U.slice rgEnd (modelDim - rgEnd) g
      sq v = U.sum (U.map (\z -> z * z) v)
  in U.snoc (U.snoc achro (sq rg)) (sq by)

-- | The full Atlas forward: (tokens 13-D, weights, genome 384-D) -> trace.
atlasForward :: AtlasNetWeights -> ([U.Vector Double], [Double], U.Vector Double) -> AtlasForwardTrace
atlasForward w (tokens, weights, genome) =
  let board = boardContext w tokens weights
      gencM = U.zipWith (*) (aGenomeEnc w) gencMask
      genc  = U.map tanh (linear modelDim sigmaPairDof gencM genome)
      ctx   = board U.++ genc                           -- 128

      proj  = invProj ctx                               -- 24
      node  = linear nSlots invProjDim (aNodeHead w) proj      -- 127
      -- delta head: interleave [w_i, w_i⊙ctxSign] -> 12×128
      half  = aDeltaHalf w
      fullDelta = U.generate (nDeltas * ctxDim) $ \k ->
        let r = k `div` ctxDim; i = k `mod` ctxDim
            r2 = r `div` 2; isOdd = odd r
            raw = half U.! (r2 * ctxDim + i)
        in if isOdd then raw * (ctxSign U.! i) else raw
      delta = linear nDeltas ctxDim fullDelta ctx          -- 12

      policy = [ (node U.! slot) + (delta U.! d)
               | slot <- [0 .. nSlots - 1], d <- [0 .. nDeltas - 1] ]

      v1out = U.imap (\o z -> tanh (z + (aV1b w U.! o)))
                     (linear 32 invProjDim (aV1 w) proj)
      value = (linear 1 32 (aV2 w) v1out U.! 0) + aV2b w
  in AtlasForwardTrace
       { atfContext = U.toList ctx
       , atfPolicy  = policy
       , atfValue   = value
       }

-- =============================================================================
-- Golden input fixtures
-- =============================================================================

-- | A deterministic 13-D Atlas token: 10 base GMM dims (as in 'LookNetEval')
-- ++ 3 σ-invariant curation scalars. @s@ varies per token.
mkAtlasToken :: Double -> U.Vector Double
mkAtlasToken s = U.fromList
  [ 0.5 + 0.1 * sin s, 0.1 * cos s, 0.1 * sin (2*s)
  , 0.02 + 0.005 * abs (sin s), 0.001 * cos s, 0.001 * sin s
  , 0.02 + 0.005 * abs (cos s), 0.001 * cos (2*s), 0.02 + 0.005 * abs (sin (2*s))
  , 0.5 + 0.4 * abs (sin (3*s))
  , 0.3 * sin s, 0.2 * cos s, 0.1 + 0.05 * abs (sin s)   -- 3 curation scalars
  ]

-- | A deterministic 384-D genome (bounded sin fill).
mkGenome :: Double -> U.Vector Double
mkGenome seed = genFill seed sigmaPairDof

-- | Normalize a weight list to sum 1 (the pooling weights are a distribution).
normW :: [Double] -> [Double]
normW xs = let s = sum xs in if s == 0 then xs else map (/ s) xs

-- | The fixed golden cases: @(name, (tokens, weights, genome))@ — 1, 3, 8 tokens.
atlasTestCases :: [(String, ([U.Vector Double], [Double], U.Vector Double))]
atlasTestCases =
  [ ( "single", ( [ mkAtlasToken 1 ], normW [1], mkGenome 30 ) )
  , ( "triple", ( ts 3, normW [0.5, 0.3, 0.2], mkGenome 31 ) )
  , ( "octet",  ( ts 8, normW [ fromIntegral i | i <- [1 .. 8 :: Int] ], mkGenome 32 ) )
  ]
  where ts n = [ mkAtlasToken (0.5 * fromIntegral i) | i <- [1 .. n :: Int] ]

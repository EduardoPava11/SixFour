{-# LANGUAGE ScopedTypeVariables #-}

{- |
Module      : SixFour.Spec.LookNetEval
Description : The spec's first CONCRETE numeric forward — the golden-vector oracle.

Everywhere else the look-NN spec is a /contract/ (reference = identity/zero, no
weights). This module is the one place that actually COMPUTES a forward pass on
explicit @Double@ weights, so the Haskell spec can serve as the bit-exact oracle
for the golden vectors ("SixFour.Codegen.Golden"): the MLX trainer, the PyTorch
fallback, and the future hand-written Swift forward must all reproduce 'forward'
(to a tolerance — cross-language summation order differs at the ULP level).

The computation mirrors the emitted modules EXACTLY (same masked-Linear layout,
same @x + W2·tanh(W1·x)@ refine, same per-context decode), and reuses the spec's
own recursion ('SixFour.Spec.LookNetR.runRecursion') and σ-invariant halt
('SixFour.Spec.LookNetR.sigmaInvariantFeatures') so there is one structural
source of truth. Weights are stored RAW (pre-mask); 'forward' applies the
σ-masks, exactly as the on-device modules apply them at call time — so a port
that loads the raw weights and masks in its forward agrees with this oracle.

'deterministicTestWeights' is a fixed, bounded (@∈[-0.1,0.1]@) fill — NOT trained.
The gate verifies the COMPUTATION, not a particular model: any weights work as
long as every port reproduces this output given them. Bounded ⇒ no NaN/Inf
(which JSON cannot represent).
-}
-- COMPARTMENT: MLX-MODEL | tag:MacTag
module SixFour.Spec.LookNetEval
  ( LookNetWeights(..)
  , deterministicTestWeights
  , ForwardTrace(..)
  , forward
  , testCases
    -- * weight-shape constants (mirror the emitted nn.Linear shapes)
  , phiShape, w64Shape, haltWShape, headShapes
    -- * the σ-masks as 0/1 Double vectors (raw→effective)
  , phiMask, sigma64MaskD, headMask
  ) where

import qualified Data.Vector.Unboxed as U

import SixFour.Spec.Tensor   (Tensor1(..), sigma64Mask, gmmTokenSigmaMask, hiddenAchromaticDim)
import SixFour.Spec.LookNetE (HiddenContext(..))
import SixFour.Spec.LookNetR
  ( SharedBlock(..), runRecursion, sigmaInvariantFeatures
  , sigmaBlockDiagonalMask, coreDepth )
import SixFour.Spec.LookNetD (sigmaDecoderMask, decoderLevelDims)

-- =============================================================================
-- Weight container (RAW, pre-mask; row-major (out × in), matching nn.Linear)
-- =============================================================================

-- | All learnable weights, flat row-major in @(out, in)@ order (the PyTorch /
-- MLX @nn.Linear.weight@ layout, so a port can @reshape@ directly).
data LookNetWeights = LookNetWeights
  { wPhi    :: !(U.Vector Double)   -- ^ L3 phi: 64×10
  , wW1     :: !(U.Vector Double)   -- ^ L4 shared refine W1: 64×64
  , wW2     :: !(U.Vector Double)   -- ^ L4 shared refine W2: 64×64
  , wHaltW  :: !(U.Vector Double)   -- ^ halt MLP weight: 1×2
  , wHaltB  :: !Double              -- ^ halt MLP bias: 1
  , wHeads  :: ![U.Vector Double]   -- ^ L5 heads: 8 of (decoderLevelDims!!k)×64
  } deriving (Eq, Show)

-- | Shape of the encoder projection weight @φ@: @(64, 10)@ (hidden ← 10-D GMM token).
phiShape :: (Int, Int)
phiShape = (64, 10)

-- | Shape of the core recursion weight: @(64, 64)@ (hidden ← hidden).
w64Shape :: (Int, Int)
w64Shape = (64, 64)

-- | Shape of the PonderNet halting head weight: @(1, 2)@.
haltWShape :: (Int, Int)
haltWShape = (1, 2)

-- | @(out, 64)@ per L5 head, one per 'decoderLevelDims' entry (8 heads).
headShapes :: [(Int, Int)]
headShapes = [ (d, 64) | d <- decoderLevelDims ]

-- =============================================================================
-- σ-masks as 0/1 Double vectors (the effective-weight projection)
-- =============================================================================

-- | L3 phi mask (64×10): free iff @sigma64Mask[o] == gmmTokenSigmaMask[i]@.
phiMask :: U.Vector Double
phiMask = U.generate (64 * 10) $ \k ->
  let o = k `div` 10; i = k `mod` 10
  in if (sigma64Mask !! o) == (gmmTokenSigmaMask !! i) then 1 else 0

-- | The 64×64 σ-block-diagonal mask as Doubles (from 'sigmaBlockDiagonalMask').
sigma64MaskD :: U.Vector Double
sigma64MaskD = U.map fromIntegral sigmaBlockDiagonalMask

-- | L5 head @k@ mask (@d_k × 64@): free iff the output triple's σ-class
-- ('sigmaDecoderMask' at the head's global slice) matches @sigma64Mask[i]@.
headMask :: Int -> U.Vector Double
headMask k =
  let (dk, _) = headShapes !! k
      off     = sum (take k decoderLevelDims)   -- global offset into the 384 vector
  in U.generate (dk * 64) $ \idx ->
       let r = idx `div` 64; i = idx `mod` 64
       in if (sigmaDecoderMask !! (off + r)) == (sigma64Mask !! i) then 1 else 0

-- =============================================================================
-- Deterministic test weights (bounded, reproducible)
-- =============================================================================

-- | A fixed bounded fill: @w_k = 0.1·sin(seed + k)@. Distinct @seed@ per matrix.
genFill :: Double -> Int -> U.Vector Double
genFill seed n = U.generate n (\k -> 0.1 * sin (seed + fromIntegral k))

-- | A fixed, reproducible weight set (each matrix a distinct @0.1·sin@ fill) — the controlled,
-- non-trivial input the forward-pass golden vectors are computed from.
deterministicTestWeights :: LookNetWeights
deterministicTestWeights = LookNetWeights
  { wPhi   = genFill 1 (64 * 10)
  , wW1    = genFill 2 (64 * 64)
  , wW2    = genFill 3 (64 * 64)
  , wHaltW = genFill 4 (1 * 2)
  , wHaltB = 0.05
  , wHeads = [ genFill (10 + fromIntegral k) (dk * 64)
             | (k, (dk, _)) <- zip [0 :: Int ..] headShapes ]
  }

-- =============================================================================
-- The forward pass (mirrors the emitted modules exactly)
-- =============================================================================

-- | @linear out inn W x@ = the masked-Linear product @y[o] = Σ_i W[o,i]·x[i]@,
-- @W@ flat row-major @(out × inn)@. (Matches @F.linear@ / @x @ W.T@.)
linear :: Int -> Int -> U.Vector Double -> U.Vector Double -> U.Vector Double
linear outN innN w x =
  U.generate outN $ \o ->
    let base = o * innN
    in U.sum (U.generate innN (\i -> (w U.! (base + i)) * (x U.! i)))

sigmoid :: Double -> Double
sigmoid z = 1 / (1 + exp (negate z))

-- | The full forward trace: the pooled context, the per-step halt λ's, and the
-- 384-D SigmaPairTree output (concatenated per-level head outputs).
data ForwardTrace = ForwardTrace
  { ftContext :: ![Double]   -- ^ 64
  , ftHalts   :: ![Double]   -- ^ coreDepth (8)
  , ftOutput  :: ![Double]   -- ^ 384
  } deriving (Eq, Show)

-- | The full look-NN forward pass E→R→D on a token set: pooled context, per-step halt λ's, and the
-- 384-D SigmaPairTree output. Mirrors the emitted Swift/MLX modules exactly (golden-pinned).
forward :: LookNetWeights -> [Tensor1 10 Double] -> ForwardTrace
forward w tokens =
  let phiM   = U.zipWith (*) (wPhi w) phiMask           -- effective (masked) phi
      w1M    = U.zipWith (*) (wW1 w)  sigma64MaskD
      w2M    = U.zipWith (*) (wW2 w)  sigma64MaskD

      -- L3: per-token phi (10→64), then sum-pool over tokens.
      placed = [ linear 64 10 phiM t | Tensor1 t <- tokens ]
      ctx0V  = case placed of
                 [] -> U.replicate 64 0
                 _  -> foldr1 (U.zipWith (+)) placed
      ctx0   = HiddenContext (Tensor1 ctx0V)

      -- The concrete shared block: refine x ↦ x + W2·tanh(W1·x); σ-invariant halt.
      refine (HiddenContext (Tensor1 x)) =
        let pre = U.map tanh (linear 64 64 w1M x)
            dx  = linear 64 64 w2M pre
        in HiddenContext (Tensor1 (U.zipWith (+) x dx))
      halt ctx =
        let (a, c) = sigmaInvariantFeatures ctx
        in sigmoid ((wHaltW w U.! 0) * a + (wHaltW w U.! 1) * c + wHaltB w)
      block    = SharedBlock { sbRefine = refine, sbHalt = halt }

      contexts = runRecursion block ctx0                 -- coreDepth+1 contexts
      halts    = [ sbHalt block (contexts !! l) | l <- [0 .. coreDepth - 1] ]

      -- L5: head k reads contexts[k] (root=ctx0, level ℓ = ctx_{ℓ+1}); concat.
      headOut k =
        let (dk, _)        = headShapes !! k
            HiddenContext (Tensor1 cv) = contexts !! k
            wm = U.zipWith (*) (wHeads w !! k) (headMask k)
        in U.toList (linear dk 64 wm cv)
      output   = concatMap headOut [0 .. length decoderLevelDims - 1]

  in ForwardTrace
       { ftContext = U.toList ctx0V
       , ftHalts   = halts
       , ftOutput  = output
       }

-- =============================================================================
-- Golden input fixtures: a few fixed GmmTokenSets of differing token counts
-- =============================================================================

-- | One deterministic 10-D GMM token @[μL,μa,μb, ΣLL,ΣLa,ΣLb,Σaa,Σab,Σbb, w]@,
-- in-gamut-ish μ, positive diagonal Σ, positive weight. @s@ varies per token.
mkToken :: Double -> Tensor1 10 Double
mkToken s = Tensor1 (U.fromList
  [ 0.5 + 0.1 * sin s          -- μL
  , 0.1 * cos s                -- μa
  , 0.1 * sin (2 * s)          -- μb
  , 0.02 + 0.005 * abs (sin s) -- ΣLL
  , 0.001 * cos s              -- ΣLa
  , 0.001 * sin s              -- ΣLb
  , 0.02 + 0.005 * abs (cos s) -- Σaa
  , 0.001 * cos (2 * s)        -- Σab
  , 0.02 + 0.005 * abs (sin (2*s)) -- Σbb
  , 0.5 + 0.4 * abs (sin (3*s))    -- w (>0)
  ])

-- | The fixed golden cases: @(name, tokens)@ — 1, 3, and 8 tokens.
testCases :: [(String, [Tensor1 10 Double])]
testCases =
  [ ("single",  [ mkToken 1 ])
  , ("triple",  [ mkToken (fromIntegral i) | i <- [1 .. 3 :: Int] ])
  , ("octet",   [ mkToken (0.5 * fromIntegral i) | i <- [1 .. 8 :: Int] ])
  ]

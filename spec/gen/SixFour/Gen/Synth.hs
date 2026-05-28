{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{- |
Module      : SixFour.Gen.Synth
Description : Calibrated synthetic 'CyclicStack' generator — a bit-exact port
              of @studio/analysis-core/src/synth.rs@.

Produces a @T@-frame, @K@-colour 'CyclicStack' (per-frame OKLab palettes +
per-slot pixel populations) whose geometry and dynamics are set by interpretable
knobs, so the statistical "latent trajectory" of the resulting GIF — the §8
descriptor ("SixFour.Spec.Cyclic") and LAB gamut coverage — can be controlled.

The pseudo-random draw sequence is a __verbatim__ port of the Rust @Lcg@
(same multiplier/increment, same @(state>>11)/2^53@ mantissa, same triangular
@gauss@, same seed init), consumed in the __same order__. So @synthStack@ here
and @synth_stack@ in Rust produce bit-identical stacks for the same
'SynthParams' — which is what lets a single golden test cross-check both the
synthesis and the entropy math (see the @spec-tests@ golden).

Knob → statistic map:

  * @concSkew@   → palette (Shannon) entropy @H(w_t)@ (population concentration);
  * @popDrift@   → temporal variation of @H(P_t)@ / spectral entropy;
  * @drift@      → cyclic transport cost (palettes orbit the cube);
  * @gamut@      → LAB gamut coverage;
  * @spread@     → Gaussian colour entropy @H_g@ (intra-cluster spread);
  * @nClusters@  → number of colour modes (competing collapse hypotheses).
-}
module SixFour.Gen.Synth
  ( SynthParams (..)
  , defaultSynthParams
  , synthStack
    -- * PRNG (exposed for the cross-language golden)
  , lcgStream
  , seedInit
  ) where

import           Data.Word           (Word64)
import           Data.Bits           (shiftR)
import           Data.List           (unfoldr)
import           Data.Maybe          (fromMaybe)
import           Data.Proxy          (Proxy (..))
import           GHC.TypeLits        (Nat, KnownNat, natVal)
import qualified Data.Vector         as V

import SixFour.Spec.Color   (OKLab, SRGB (..), srgbToOKLab)
import SixFour.Spec.Palette (Palette, mkPalette)
import SixFour.Spec.Cyclic  (Weights, CyclicStack, mkCyclicStack)

-- | The synthesis knobs. Field names and defaults mirror @synth.rs@.
data SynthParams = SynthParams
  { nClusters :: !Int     -- ^ number of distinct colour clusters (≥1)
  , spread    :: !Double  -- ^ intra-cluster sRGB stddev (~0..0.2) → drives H_g
  , drift     :: !Double  -- ^ temporal cluster motion amplitude (~0..0.4) → transport
  , gamut     :: !Double  -- ^ overall RGB coverage (0..1) → LAB coverage
  , concSkew  :: !Double  -- ^ population skew (0 ≈ uniform usage) → H(w)
  , popDrift  :: !Double  -- ^ temporal population oscillation (0..1) → H(P_t) spectrum
  , seed      :: !Word64
  } deriving (Eq, Show)

-- | The @synth.rs@ defaults.
defaultSynthParams :: SynthParams
defaultSynthParams = SynthParams
  { nClusters = 6
  , spread    = 0.06
  , drift     = 0.18
  , gamut     = 0.8
  , concSkew  = 1.0
  , popDrift  = 0.5
  , seed      = 1
  }

-- ---------------------------------------------------------------------------
-- LCG (verbatim port of synth.rs `Lcg`)
-- ---------------------------------------------------------------------------

lcgMul, lcgAdd :: Word64
lcgMul = 6364136223846793005
lcgAdd = 1442695040888963407

-- | Seed initialisation: @Lcg(seed * 2654435761 + 11)@ (wrapping).
seedInit :: Word64 -> Word64
seedInit s = s * 2654435761 + 11

-- | One LCG step → a @Double@ in [0,1): advance state, then @(state>>11)/2^53@.
lcgF64 :: Word64 -> (Double, Word64)
lcgF64 s =
  let s' = s * lcgMul + lcgAdd
  in (fromIntegral (s' `shiftR` 11) / 9007199254740992.0, s')

-- | Infinite stream of @Double@ draws from an initial (already-init'd) state.
lcgStream :: Word64 -> [Double]
lcgStream = unfoldr (Just . lcgF64)

-- ---------------------------------------------------------------------------
-- Synthesis
-- ---------------------------------------------------------------------------

-- | Build a controlled synthetic stack of @T@ frames × @K@ colours.
synthStack :: forall t k. (KnownNat t, KnownNat k) => SynthParams -> CyclicStack t k
synthStack p =
  fromMaybe (error "synthStack: frame count mismatch (impossible)")
            (mkCyclicStack frames)
  where
    tc = fromIntegral (natVal (Proxy :: Proxy t)) :: Int
    k  = fromIntegral (natVal (Proxy :: Proxy k)) :: Int
    nc = max 1 (nClusters p)

    -- The draw stream, consumed in synth.rs order:
    --   1) per (c,ch): base draw, phase draw         (nc*3 pairs)
    --   2) per (s,ch): 3 draws for gauss             (k*3 triples)
    --   3) per s:      base_w draw, wphase draw       (k pairs)
    ds0 = lcgStream (seedInit (seed p))
    (basePhaseD, ds1) = splitAt (nc * 3 * 2) ds0
    (offsetD,    ds2) = splitAt (k * 3 * 3)  ds1
    (bwWpD,      _)   = splitAt (k * 2)       ds2
    basePhaseV = V.fromList basePhaseD
    offsetV    = V.fromList offsetD
    bwWpV      = V.fromList bwWpD

    -- cluster bases / drift phases, indexed [c][ch]
    baseAt  c ch = 0.5 + (basePhaseV V.! (2 * (c * 3 + ch))     - 0.5) * gamut p
    phaseAt c ch = 6.283 * (basePhaseV V.! (2 * (c * 3 + ch) + 1))

    -- per-slot fixed intra-cluster offset, indexed [s][ch]; gauss = d0+d1+d2-1.5
    offsetAt s ch =
      let i  = 3 * (s * 3 + ch)
          g  = (offsetV V.! i) + (offsetV V.! (i + 1)) + (offsetV V.! (i + 2)) - 1.5
      in g * spread p

    -- per-slot base population (skewed) + temporal phase
    expo       = 1.0 + concSkew p * 4.0
    baseWAt s  = (bwWpV V.! (2 * s)) ** expo + 1e-3
    wphaseAt s = 6.283 * (bwWpV V.! (2 * s + 1))

    slotCluster s = s `mod` nc

    frames = [ frameAt t | t <- [0 .. tc - 1] ]

    frameAt :: Int -> (Palette k, Weights)
    frameAt t =
      let pal  = [ colorAt t s | s <- [0 .. k - 1] ]
          ws   = rawWeights t
          wsum = sum ws
          wsN  = V.fromList [ w / wsum * 4096.0 | w <- ws ]
      in ( fromMaybe (error "synthStack: palette size") (mkPalette pal), wsN )

    colorAt :: Int -> Int -> OKLab
    colorAt t s =
      let c = slotCluster s
          u = 2 * pi * fromIntegral t / fromIntegral tc
          chan ch =
            let center = clamp01 (baseAt c ch + drift p * sin (u + phaseAt c ch))
            in clamp01 (center + offsetAt s ch)
      in srgbToOKLab (SRGB (chan 0) (chan 1) (chan 2))

    rawWeights :: Int -> [Double]
    rawWeights t =
      let u = 2 * pi * fromIntegral t / fromIntegral tc
      in [ max 1e-4 (baseWAt s * (1.0 + popDrift p * sin (u + wphaseAt s)))
         | s <- [0 .. k - 1] ]

clamp01 :: Double -> Double
clamp01 = max 0.0 . min 1.0

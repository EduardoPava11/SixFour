{-# LANGUAGE TypeApplications #-}
{- |
Module      : SixFour.Gen.Sweep
Description : A seeded sweep of statistically-controlled stacks spanning the
              §8 descriptor space — the look-NN training/eval corpus.

Two families:

  * __Knob sweeps__ vary one 'SynthParams' knob at a time around the default,
    so each axis of the descriptor moves in isolation: @nClusters@ (colour
    modes / competing collapse hypotheses), @concSkew@ (palette entropy
    @H(w)@), @popDrift@ (temporal @H(P_t)@ spectrum), @drift@ (transport cost),
    @gamut@ (LAB coverage), @spread@ (@H_g@), plus two combined extremes.
  * __Exact-entropy targets__ pin @H(w)@ to chosen values
    (via 'populationsForEntropySixFour') while leaving the palette colours
    moving — isolating palette entropy from colour motion.

Every case is deterministic in the base seed. The result feeds the @--sweep@
mode of @spec-gen@, which realizes, encodes, measures and labels each one.
-}
module SixFour.Gen.Sweep
  ( SweepCase (..)
  , sweep
  ) where

import           Data.Word    (Word64)
import qualified Data.Vector  as V

import SixFour.Spec.Shape  (T, K)
import SixFour.Spec.Cyclic (CyclicStack (..))

import SixFour.Gen.Synth (SynthParams (..), defaultSynthParams, synthStack)
import SixFour.Gen.Stats (weightsForEntropySixFour)

-- | One sweep entry: a name, the controlled stack, and the knobs that built it.
data SweepCase = SweepCase
  { scName   :: String
  , scStack  :: CyclicStack T K
  , scParams :: Maybe SynthParams
  }

-- | The full corpus for a base seed.
sweep :: Word64 -> [SweepCase]
sweep base = knobCases ++ targetCases
  where
    def = defaultSynthParams

    -- one-axis-at-a-time knob specs (name, params-modifier)
    knobSpecs :: [(String, SynthParams)]
    knobSpecs =
         [ ("clusters-" ++ pad n,       def { nClusters = n }) | n <- [1, 2, 4, 8, 16] ]
      ++ [ ("concSkew-" ++ sh v,        def { concSkew  = v }) | v <- [0.0, 1.0, 3.0] ]
      ++ [ ("popDrift-" ++ sh v,        def { popDrift  = v }) | v <- [0.0, 0.5, 1.0] ]
      ++ [ ("drift-"    ++ sh v,        def { drift     = v }) | v <- [0.0, 0.18, 0.4] ]
      ++ [ ("gamut-"    ++ sh v,        def { gamut     = v }) | v <- [0.2, 0.5, 0.9] ]
      ++ [ ("spread-"   ++ sh v,        def { spread    = v }) | v <- [0.02, 0.06, 0.15] ]
      ++ [ ("extreme-low",  def { nClusters = 1,  concSkew = 3, popDrift = 0
                                , drift = 0,    gamut = 0.2,  spread = 0.02 })
         , ("extreme-high", def { nClusters = 16, concSkew = 0, popDrift = 1
                                , drift = 0.4,  gamut = 0.95, spread = 0.15 }) ]

    knobCases =
      [ let p' = p { seed = base + fromIntegral i }
        in SweepCase nm (synthStack @T @K p') (Just p')
      | (i, (nm, p)) <- zip [0 :: Int ..] knobSpecs ]

    -- exact palette-entropy targets (log 256 ≈ 5.545 is the ceiling)
    targetCases =
      [ let p   = def { seed = base + 1000 + fromIntegral i }
            st0 = synthStack @T @K p
            w   = weightsForEntropySixFour h     -- continuous; realize quantizes once
            st  = CyclicStack (V.map (\(pal, _) -> (pal, w)) (unStack st0))
        in SweepCase ("targetH-" ++ sh h) st (Just p)
      | (i, h) <- zip [0 :: Int ..] [1.0, 2.5, 4.0, 5.4] ]

-- name helpers
pad :: Int -> String
pad n = let s = show n in if length s < 2 then '0' : s else s

sh :: Double -> String
sh x = show (fromIntegral (round (x * 100) :: Integer) / 100 :: Double)

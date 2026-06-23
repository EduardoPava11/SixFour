{- |
Module      : SixFour.Spec.Q16
Description : The Q16 fixed-point quantiser — the single point where a float scene value becomes a byte-exact, replayable integer. The foundational primitive of the byte-exact floor, extracted so the JEPA-EBM core does not depend on any A/B-game module.

@quantizeQ16@ is round-half-to-even (@round@) on the 16.16 grid; @toQ16@ is its
integer→Double inverse view. This is the arithmetic that "SixFour.Spec.ByteCarrier"
@reenterQ16@ wraps in the typed @Latent → Q16@ crossing. It carries no learned
parameters and no game state — it is pure substrate.
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:DeviceTag
module SixFour.Spec.Q16
  ( quantizeQ16
  , toQ16
  , lawTerminalQuantizationIdempotent
  ) where

-- | Round a scene value to the Q16 fixed-point grid (16.16) — the single float→integer
-- crossing that makes a value byte-exact and replayable. Round-half-to-even (Haskell @round@).
quantizeQ16 :: Double -> Int
quantizeQ16 x = round (x * 65536)

-- | The inverse view of a Q16 integer as a Double.
toQ16 :: Int -> Double
toQ16 q = fromIntegral q / 65536

-- | Quantisation is idempotent on the grid: re-quantising an already-Q16 value is identity —
-- which is why cross-device determinism is anchored at this terminal crossing.
lawTerminalQuantizationIdempotent :: Int -> Bool
lawTerminalQuantizationIdempotent q = quantizeQ16 (toQ16 q) == q

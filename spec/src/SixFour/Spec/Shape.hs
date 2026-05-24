{- |
Module      : SixFour.Spec.Shape
Description : Type-level shape constants for the SixFour pipeline.

The four magic numbers of SixFour live at the type level so a malformed
tensor literally fails to compile.

  * 'T'  = 64   — frames per burst
  * 'H'  = 64   — frame height
  * 'W'  = 64   — frame width
  * 'K'  = 256  — global palette size (8-bit indices)

Stage B's surjectivity obligation is "all 'K' palette entries are used"
— see "SixFour.Spec.Indices".
-}
module SixFour.Spec.Shape
  ( T, H, W, K
  , PixelsPerFrame, PixelsPerGIF
  , CandidatesAfterStageA
  , tVal, hVal, wVal, kVal
  , pixelsPerFrame, pixelsPerGIF, candidatesAfterStageA
  ) where

import GHC.TypeLits (Nat, KnownNat, natVal)
import Data.Proxy   (Proxy(..))

-- | Frames per capture burst.
type T = 64

-- | Frame height in pixels.
type H = 64

-- | Frame width in pixels.
type W = 64

-- | Global palette size (8-bit indices, 0..255).
type K = 256

-- | Pixels per single frame: 'H' * 'W' = 4096.
type PixelsPerFrame = 4096

-- | Pixels per full GIF: 'T' * 'H' * 'W' = 262144.
type PixelsPerGIF = 262144

-- | Candidate OKLab colors entering Stage B: 'T' * 'K' = 16384.
type CandidatesAfterStageA = 16384

-- | Runtime reflection helpers (used by codegen and tests).

tVal :: Int
tVal = fromIntegral (natVal (Proxy :: Proxy T))

hVal :: Int
hVal = fromIntegral (natVal (Proxy :: Proxy H))

wVal :: Int
wVal = fromIntegral (natVal (Proxy :: Proxy W))

kVal :: Int
kVal = fromIntegral (natVal (Proxy :: Proxy K))

pixelsPerFrame :: Int
pixelsPerFrame = fromIntegral (natVal (Proxy :: Proxy PixelsPerFrame))

pixelsPerGIF :: Int
pixelsPerGIF = fromIntegral (natVal (Proxy :: Proxy PixelsPerGIF))

candidatesAfterStageA :: Int
candidatesAfterStageA = fromIntegral (natVal (Proxy :: Proxy CandidatesAfterStageA))

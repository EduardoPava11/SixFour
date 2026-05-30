{- |
Module      : SixFour.Gen.AxisInput
Description : Bridge a DECODED GIF into the look-NN's GMM-token input.

Closes the "a GIF is the NN input" path: a per-frame-palette GIF, decoded by
'SixFour.Gen.GifDecode' (the inverse of the encoder, mirrored byte-for-byte by the
Zig @s4_gif_decode@), becomes the pooled 'GmmTokenSet' the look-NN consumes.

Each decoded frame is a 256-slot palette (RGB8 LCT) + per-pixel indices. We turn it
into a Gaussian mixture: one component per palette slot, mean = the slot colour in
OKLab ('srgbToOKLab'), weight = the slot's pixel population. The per-frame mixtures
are pooled ('poolGMM') and renormalised into one capture mixture, then flattened to
the 10-float tokens ('gmmTokens').

CAVEAT (the lossy / degenerate-token contract): a GIF stores only RGB8 + indices, so
each component is a POINT MASS — zero covariance (the @ClusterStatistics@ Σ the device
computes is NOT in the bytes). The token's Σ columns are therefore 0. Synthetic-only
training must inject covariance if the encoder needs it; goldens pin the DECODED OKLab
(RGB8→OKLab is lossy), never the original capture.
-}
module SixFour.Gen.AxisInput
  ( rgb8ToOKLab
  , frameToGMM
  , decodedGifToTokenSet
  ) where

import           Data.Word          (Word8)
import qualified Data.IntMap.Strict as IM

import SixFour.Spec.Color    (OKLab, SRGB(..), srgbToOKLab)
import SixFour.Spec.GMM      (GMM, pointMass, poolGMM, gmmTokens)
import SixFour.Spec.LookNetE (GmmTokenSet, mkGmmTokenSet)
import SixFour.Gen.GifDecode (DecodedGif(..), DecodedFrame(..))

-- | One decoded LCT colour (RGB8) → OKLab, through the same 'srgbToOKLab' the
-- forward encoder inverts. Lossy: the byte already lost OKLab precision.
rgb8ToOKLab :: (Word8, Word8, Word8) -> OKLab
rgb8ToOKLab (r, g, b) = srgbToOKLab (SRGB (f r) (f g) (f b))
  where f x = fromIntegral x / 255

-- | A decoded frame → its Gaussian mixture: one POINT-MASS component per palette
-- slot, weight = that slot's pixel population (0 for unused slots). Covariance is
-- 0 (not in the GIF bytes) — see the module caveat.
frameToGMM :: DecodedFrame -> GMM
frameToGMM (DecodedFrame pal idxs) =
  let counts = IM.fromListWith (+) [ (i, 1 :: Int) | i <- idxs ]
      pop k  = IM.findWithDefault 0 k counts
  in [ pointMass (rgb8ToOKLab c) (fromIntegral (pop k)) | (k, c) <- zip [0 ..] pal ]

-- | A decoded GIF → the pooled, renormalised 'GmmTokenSet' the look-NN encoder
-- consumes. @Nothing@ only if a token row isn't 10 wide (it always is here).
decodedGifToTokenSet :: DecodedGif -> Maybe GmmTokenSet
decodedGifToTokenSet g =
  mkGmmTokenSet (gmmTokens (poolGMM (map frameToGMM (dgFrames g))))

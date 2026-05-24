{- |
Module      : SixFour.Spec.Hybrid.Delta
Description : Per-frame delta palettes (each length @KDelta@).

A 'DeltaPalette' carries the @kD@ colors that one frame is allowed to
introduce on top of the shared trunk. The deltas occupy GIF slots
@[KTrunk, K)@ in each frame's LCT; the encoder writes the trunk into
the first @kT@ slots and the per-frame delta into the remaining @kD@.

We keep deltas as **absolute** OKLab colors (not offsets from a trunk
projection): the dithering kernel needs an absolute color for nearest-
neighbour search, and storing offsets would force a reconstruction
step on every pixel. Delta fitting nevertheless *uses* the residual
(@source − π_trunk(source)@) to choose the kD centroids, then adds
@π_trunk(source)@ back in. See 'SixFour.Spec.Hybrid.StageB2'.

'PerFrameDeltas' bundles all @t@ deltas for a single burst. The
@(S_kD)^t@ gauge group acts on it by permuting delta slots within each
frame independently.
-}
module SixFour.Spec.Hybrid.Delta
  ( DeltaPalette(..)
  , mkDeltaPalette
  , deltaToList
  , deltaLength
  , deltaIndex
  , PerFrameDeltas(..)
  , mkPerFrameDeltas
  , perFrameDeltasLength
  , perFrameDeltaAt
  ) where

import qualified Data.Vector as V
import           Data.Vector (Vector)
import           GHC.TypeLits (Nat, KnownNat, natVal)
import           Data.Proxy   (Proxy(..))

import SixFour.Spec.Color (OKLab)

-- | A length-@kD@ delta palette for a single frame.
newtype DeltaPalette (kD :: Nat) = DeltaPalette { unDelta :: Vector OKLab }
  deriving (Eq, Show)

mkDeltaPalette :: forall kD. KnownNat kD => [OKLab] -> Maybe (DeltaPalette kD)
mkDeltaPalette xs =
  let n = fromIntegral (natVal (Proxy :: Proxy kD)) :: Int
      v = V.fromList xs
  in if V.length v == n
       then Just (DeltaPalette v)
       else Nothing

deltaToList :: DeltaPalette kD -> [OKLab]
deltaToList (DeltaPalette v) = V.toList v

deltaLength :: forall kD. KnownNat kD => DeltaPalette kD -> Int
deltaLength _ = fromIntegral (natVal (Proxy :: Proxy kD))

deltaIndex :: DeltaPalette kD -> Int -> Maybe OKLab
deltaIndex (DeltaPalette v) i = v V.!? i

-- | The @t@ delta palettes for a single burst, indexed by frame.
-- By construction, @V.length (unPerFrameDeltas …) == t@.
newtype PerFrameDeltas (t :: Nat) (kD :: Nat) =
  PerFrameDeltas { unPerFrameDeltas :: Vector (DeltaPalette kD) }
  deriving (Eq, Show)

mkPerFrameDeltas
  :: forall t kD. (KnownNat t, KnownNat kD)
  => [DeltaPalette kD] -> Maybe (PerFrameDeltas t kD)
mkPerFrameDeltas xs =
  let n = fromIntegral (natVal (Proxy :: Proxy t)) :: Int
      v = V.fromList xs
  in if V.length v == n
       then Just (PerFrameDeltas v)
       else Nothing

perFrameDeltasLength :: forall t kD. (KnownNat t) => PerFrameDeltas t kD -> Int
perFrameDeltasLength _ = fromIntegral (natVal (Proxy :: Proxy t))

perFrameDeltaAt :: PerFrameDeltas t kD -> Int -> Maybe (DeltaPalette kD)
perFrameDeltaAt (PerFrameDeltas v) i = v V.!? i

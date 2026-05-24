{- |
Module      : SixFour.Spec.Hybrid.Trunk
Description : The globally-stable trunk palette (length @KTrunk@).

A 'TrunkPalette' is a length-@kT@ flat vector of OKLab colors. It is
written into the GIF's Global Color Table (GCT) once and referenced by
every frame's LCT, so the slots @[0, kT)@ of the on-disk palette are
identical across all frames. This is what makes 3D spatio-temporal
blue-noise dithering safe: the Voronoi grid the dither pattern was
designed against is stable in time.

The @S_kT@ gauge group (permutations of trunk slots) acts on
'TrunkPalette' in the same way the @S_K@ group acts on the flat
'Palette' — see 'SixFour.Spec.Gauge'. Trunk gauge perms must be
applied jointly to every frame's delta indices to preserve decoded
identity.
-}
module SixFour.Spec.Hybrid.Trunk
  ( TrunkPalette(..)
  , mkTrunkPalette
  , trunkToList
  , trunkLength
  , trunkIndex
  ) where

import qualified Data.Vector as V
import           Data.Vector (Vector)
import           GHC.TypeLits (Nat, KnownNat, natVal)
import           Data.Proxy   (Proxy(..))

import SixFour.Spec.Color (OKLab)

-- | A length-@kT@ trunk palette. By construction the wrapped 'Vector'
-- has exactly @kT@ entries; the smart constructor 'mkTrunkPalette'
-- enforces that on input.
newtype TrunkPalette (kT :: Nat) = TrunkPalette { unTrunk :: Vector OKLab }
  deriving (Eq, Show)

-- | Build a 'TrunkPalette'. Returns 'Nothing' if the input length
-- differs from @kT@.
mkTrunkPalette :: forall kT. KnownNat kT => [OKLab] -> Maybe (TrunkPalette kT)
mkTrunkPalette xs =
  let n = fromIntegral (natVal (Proxy :: Proxy kT)) :: Int
      v = V.fromList xs
  in if V.length v == n
       then Just (TrunkPalette v)
       else Nothing

trunkToList :: TrunkPalette kT -> [OKLab]
trunkToList (TrunkPalette v) = V.toList v

trunkLength :: forall kT. KnownNat kT => TrunkPalette kT -> Int
trunkLength _ = fromIntegral (natVal (Proxy :: Proxy kT))

trunkIndex :: TrunkPalette kT -> Int -> Maybe OKLab
trunkIndex (TrunkPalette v) i = v V.!? i

{- |
Module      : SixFour.Spec.Palette
Description : A length-'K' palette of OKLab colors.

The palette is a flat vector of length 'K' = 256 (compile-time). The 'S_K'
gauge group acts on palettes by permuting entries — see 'SixFour.Spec.Gauge'.
-}
module SixFour.Spec.Palette
  ( Palette(..)
  , mkPalette
  , paletteToList
  , paletteFromList
  , paletteLength
  , paletteIndex
  ) where

import qualified Data.Vector as V
import           Data.Vector (Vector)
import           GHC.TypeLits (Nat, KnownNat, natVal)
import           Data.Proxy   (Proxy(..))

import SixFour.Spec.Color (OKLab)

-- | Palette parameterised by its size at the type level.
-- @Palette K@ has exactly @K@ entries by construction.
newtype Palette (k :: Nat) = Palette { unPalette :: Vector OKLab }
  deriving (Eq, Show)

-- | Build a palette from a list. Returns 'Nothing' if the length differs from @K@.
mkPalette :: forall k. KnownNat k => [OKLab] -> Maybe (Palette k)
mkPalette xs =
  let n = fromIntegral (natVal (Proxy :: Proxy k)) :: Int
      v = V.fromList xs
  in if V.length v == n
       then Just (Palette v)
       else Nothing

paletteFromList :: forall k. KnownNat k => [OKLab] -> Maybe (Palette k)
paletteFromList = mkPalette

paletteToList :: Palette k -> [OKLab]
paletteToList (Palette v) = V.toList v

paletteLength :: forall k. KnownNat k => Palette k -> Int
paletteLength _ = fromIntegral (natVal (Proxy :: Proxy k))

paletteIndex :: Palette k -> Int -> Maybe OKLab
paletteIndex (Palette v) i = v V.!? i

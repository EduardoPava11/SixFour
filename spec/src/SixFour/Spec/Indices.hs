{- |
Module      : SixFour.Spec.Indices
Description : The @T × H × W@ index tensor and the 'Surjective256' witness.

The index tensor is a flat 'Vector' of @T*H*W@ 'Int's, each in
@[0, K-1]@. Smart constructors enforce both the value range and (when
asked) the @Surjective256@ invariant — that every palette entry is
referenced by at least one pixel.
-}
module SixFour.Spec.Indices
  ( IndexTensor(..)
  , Surjective256
  , mkIndexTensor
  , mkSurjective256
  , withSurjective256
  , indexTensorLength
  ) where

import qualified Data.Vector         as V
import qualified Data.Vector.Unboxed as U
import qualified Data.Set            as Set
import           Data.Vector.Unboxed (Unbox)
import           GHC.TypeLits        (Nat, KnownNat, natVal)
import           Data.Proxy          (Proxy(..))

-- | Index tensor of shape @(t, h, w)@ over alphabet @[0, k-1]@.
-- Stored row-major: @idx(f, y, x) = (f * h + y) * w + x@.
newtype IndexTensor (t :: Nat) (h :: Nat) (w :: Nat) (k :: Nat) =
  IndexTensor { unIndices :: U.Vector Int }
  deriving (Eq, Show)

-- | A proof that every value in @[0, K-1]@ appears in the tensor at
-- least once. Constructed only by 'mkSurjective256', which performs
-- the @O(K)@ scan. The constructor is unexported, so values of this
-- type cannot be forged.
--
-- This is the runtime soundness mechanism for Stage B — the
-- Sinkhorn-balanced merger does **not** mathematically guarantee
-- surjectivity after nearest-neighbour hardening (only equal soft
-- column mass), so the witness must be checked.
data Surjective256 (t :: Nat) (h :: Nat) (w :: Nat) (k :: Nat) =
  Surjective256 !(IndexTensor t h w k)

-- | Build an 'IndexTensor'. Checks length and value range.
mkIndexTensor
  :: forall t h w k. (KnownNat t, KnownNat h, KnownNat w, KnownNat k)
  => [Int] -> Maybe (IndexTensor t h w k)
mkIndexTensor xs =
  let nt = fromIntegral (natVal (Proxy :: Proxy t)) :: Int
      nh = fromIntegral (natVal (Proxy :: Proxy h)) :: Int
      nw = fromIntegral (natVal (Proxy :: Proxy w)) :: Int
      nk = fromIntegral (natVal (Proxy :: Proxy k)) :: Int
      n  = nt * nh * nw
      v  = U.fromList xs
      okLen   = U.length v == n
      okRange = U.all (\i -> i >= 0 && i < nk) v
  in if okLen && okRange then Just (IndexTensor v) else Nothing

-- | Promote an 'IndexTensor' to 'Surjective256' if it uses every index in @[0, K-1]@.
mkSurjective256
  :: forall t h w k. (KnownNat k)
  => IndexTensor t h w k -> Maybe (Surjective256 t h w k)
mkSurjective256 it@(IndexTensor v) =
  let nk = fromIntegral (natVal (Proxy :: Proxy k)) :: Int
      seen = Set.fromList (U.toList v)
  in if Set.size seen == nk
       && Set.findMin seen == 0
       && Set.findMax seen == nk - 1
       then Just (Surjective256 it)
       else Nothing

-- | Pattern-match-like elimination of a 'Surjective256' witness.
withSurjective256
  :: Surjective256 t h w k
  -> (IndexTensor t h w k -> r)
  -> r
withSurjective256 (Surjective256 it) k = k it

indexTensorLength :: IndexTensor t h w k -> Int
indexTensorLength (IndexTensor v) = U.length v

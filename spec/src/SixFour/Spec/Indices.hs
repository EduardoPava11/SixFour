{- |
Module      : SixFour.Spec.Indices
Description : The @T × H × W@ index tensor and the 'CompleteVoxelVolume'
              completeness brand.

The index tensor is a flat 'Vector' of @T*H*W@ 'Int's, each in
@[0, K-1]@. The smart constructor enforces the value range.

'CompleteVoxelVolume' is the /per-frame/ completeness obligation the GIF
encoder demands: the tensor has the full @T*H*W@ length AND each of the
@T@ frame-slices independently uses every index in @[0, K-1]@. This is
"no empty slots" in the voxel sense — all @T*H*W@ voxels are defined and
every frame exercises the whole @K@-colour alphabet. It is the sole
completeness contract now that the cube ships one per-frame palette per
frame (the old global 'Surjective256' witness, used only by the removed
Sinkhorn Stage B merger, is gone).
-}
-- COMPARTMENT: ZIG-FLOOR | tag:DeviceTag
module SixFour.Spec.Indices
  ( IndexTensor(..)
  , CompleteVoxelVolume
  , mkIndexTensor
  , mkCompleteVoxelVolume
  , withCompleteVoxelVolume
  , indexTensorLength
    -- * Global surjectivity (the look-NN's completeness contract)
  , GlobalSurjective
  , mkGlobalSurjective
  , withGlobalSurjective
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

-- | A proof that an index tensor is a /complete voxel volume/:
--
--   1. it has the full @T*H*W@ length (every voxel defined), and
--   2. /each/ of the @T@ frame-slices (length @H*W@) independently uses
--      every index in @[0, K-1]@ — strict per-frame surjectivity.
--
-- This is strict per-frame surjectivity: it is not enough for the
-- alphabet to be covered somewhere across the whole cube — every single
-- frame must exercise all @K@ colours. The GIF
-- encoder accepts only a 'CompleteVoxelVolume', so a GIF with a dropped
-- frame, a short frame, or a frame that fails to exercise all @K@
-- colours is unrepresentable at the call site. The constructor is
-- unexported; values cannot be forged.
data CompleteVoxelVolume (t :: Nat) (h :: Nat) (w :: Nat) (k :: Nat) =
  CompleteVoxelVolume !(IndexTensor t h w k)

-- | Promote an 'IndexTensor' to a 'CompleteVoxelVolume' if it has the
-- full length and every frame-slice is surjective onto @[0, K-1]@.
-- @O(T*H*W)@: one scan, bucketed per frame.
mkCompleteVoxelVolume
  :: forall t h w k. (KnownNat t, KnownNat h, KnownNat w, KnownNat k)
  => IndexTensor t h w k -> Maybe (CompleteVoxelVolume t h w k)
mkCompleteVoxelVolume it@(IndexTensor v) =
  let nt       = fromIntegral (natVal (Proxy :: Proxy t)) :: Int
      nh       = fromIntegral (natVal (Proxy :: Proxy h)) :: Int
      nw       = fromIntegral (natVal (Proxy :: Proxy w)) :: Int
      nk       = fromIntegral (natVal (Proxy :: Proxy k)) :: Int
      perFrame = nh * nw
      frameSurjective f =
        let slice = U.slice (f * perFrame) perFrame v
        in Set.size (Set.fromList (U.toList slice)) == nk
  in if U.length v == nt * perFrame && all frameSurjective [0 .. nt - 1]
       then Just (CompleteVoxelVolume it)
       else Nothing

-- | Pattern-match-like elimination of a 'CompleteVoxelVolume' witness.
withCompleteVoxelVolume
  :: CompleteVoxelVolume t h w k
  -> (IndexTensor t h w k -> r)
  -> r
withCompleteVoxelVolume (CompleteVoxelVolume it) k = k it

-- | Number of cells in the index tensor (@t·h·w@).
indexTensorLength :: IndexTensor t h w k -> Int
indexTensorLength (IndexTensor v) = U.length v

-- | A proof that an index tensor is /globally surjective/:
--
--   1. it has the full @T*H*W@ length (every voxel defined), and
--   2. the union of indices /across the whole loop/ uses every colour in
--      @[0, K-1]@ — @⋃ₜ usedₜ = [0, K)@.
--
-- This is the look-NN's completeness contract and the deliberate /opposite/
-- of 'CompleteVoxelVolume': a single frame may use only a __subset__ of the
-- global palette (so a colour can live on a balanced pair dithered across
-- frames), as long as the 64-frame loop as a whole exercises all @K@ colours.
-- The constructor is unexported; values cannot be forged.
data GlobalSurjective (t :: Nat) (h :: Nat) (w :: Nat) (k :: Nat) =
  GlobalSurjective !(IndexTensor t h w k)

-- | Promote an 'IndexTensor' to a 'GlobalSurjective' if it has the full
-- length and the union of all voxel indices is exactly @[0, K-1]@. The value
-- range is already guaranteed by 'mkIndexTensor', so a full union is
-- equivalent to the distinct-index count equalling @K@. @O(T*H*W)@: one scan.
mkGlobalSurjective
  :: forall t h w k. (KnownNat t, KnownNat h, KnownNat w, KnownNat k)
  => IndexTensor t h w k -> Maybe (GlobalSurjective t h w k)
mkGlobalSurjective it@(IndexTensor v) =
  let nt   = fromIntegral (natVal (Proxy :: Proxy t)) :: Int
      nh   = fromIntegral (natVal (Proxy :: Proxy h)) :: Int
      nw   = fromIntegral (natVal (Proxy :: Proxy w)) :: Int
      nk   = fromIntegral (natVal (Proxy :: Proxy k)) :: Int
      used = Set.fromList (U.toList v)
  in if U.length v == nt * nh * nw && Set.size used == nk
       then Just (GlobalSurjective it)
       else Nothing

-- | Pattern-match-like elimination of a 'GlobalSurjective' witness.
withGlobalSurjective
  :: GlobalSurjective t h w k
  -> (IndexTensor t h w k -> r)
  -> r
withGlobalSurjective (GlobalSurjective it) k = k it

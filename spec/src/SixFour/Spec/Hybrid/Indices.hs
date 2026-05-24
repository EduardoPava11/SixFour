{- |
Module      : SixFour.Spec.Hybrid.Indices
Description : Tagged @T × H × W@ index tensor over a hybrid palette, plus three witnesses.

A 'HybridIndexTensor' stores one 'Word8' per voxel in @[0, K)@:

  * @i < kT@   → 'Trunk' (i)        — slot @i@ of the trunk palette.
  * @i ≥ kT@   → 'Delta' (i - kT)   — slot @(i - kT)@ of frame @f@'s delta palette.

Three unforgeable witnesses live here. Each can only be constructed
by a smart-constructor that performs an @O(T·H·W)@ scan; downstream
code may then trust the invariant for free:

  * 'SurjectiveTrunk'        — every trunk slot is used somewhere in the cube.
  * 'SurjectiveDeltaPerFrame' — every delta slot is used in its own frame.
  * 'TemporalStable'         — voxels whose source RGB varies by less than
    a threshold across @t@ are quantized to a constant trunk index — i.e.
    no static-background voxel flickers into the delta range.

The encoder's smart constructor demands all three, so flicker /
dead-slot bugs become compile-time obligations rather than runtime QA
findings.
-}
module SixFour.Spec.Hybrid.Indices
  ( -- * Tagged index tensor
    Slot(..)
  , HybridIndexTensor(..)
  , mkHybridIndexTensor
  , hybridIndexTensorLength
  , decodeSlot
    -- * Witnesses
  , SurjectiveTrunk
  , mkSurjectiveTrunk
  , withSurjectiveTrunk
  , SurjectiveDeltaPerFrame
  , mkSurjectiveDeltaPerFrame
  , withSurjectiveDeltaPerFrame
  , TemporalStable
  , mkTemporalStable
  , withTemporalStable
  ) where

import qualified Data.Vector.Unboxed as U
import qualified Data.Set            as Set
import           Data.Word           (Word8)
import           GHC.TypeLits        (Nat, KnownNat, natVal)
import           Data.Proxy          (Proxy(..))

import SixFour.Spec.Hybrid.Shape (HybridK)

-- | Provenance tag carried by every voxel's resolved 'Word8'.
--
-- 'Trunk' indices live in @[0, kT)@ and reference the shared trunk
-- palette; 'Delta' indices live in @[0, kD)@ and reference frame-@f@'s
-- delta palette. The on-disk byte is @kT + d@ for 'Delta' d.
data Slot = Trunk !Int | Delta !Int
  deriving (Eq, Show)

-- | Indices stored as packed 'Word8'. Row-major:
-- @idx(f, y, x) = (f * h + y) * w + x@.
newtype HybridIndexTensor
  (t :: Nat) (h :: Nat) (w :: Nat) (kT :: Nat) (kD :: Nat) =
  HybridIndexTensor { unHybridIx :: U.Vector Word8 }
  deriving (Eq, Show)

-- | Build a 'HybridIndexTensor'. Checks length and the type-level
-- constraint @kT + kD ~ K@ via 'HybridK'.
mkHybridIndexTensor
  :: forall t h w kT kD.
     ( KnownNat t, KnownNat h, KnownNat w, HybridK kT kD )
  => [Word8] -> Maybe (HybridIndexTensor t h w kT kD)
mkHybridIndexTensor xs =
  let nt = fromIntegral (natVal (Proxy :: Proxy t))  :: Int
      nh = fromIntegral (natVal (Proxy :: Proxy h))  :: Int
      nw = fromIntegral (natVal (Proxy :: Proxy w))  :: Int
      n  = nt * nh * nw
      v  = U.fromList xs
  in if U.length v == n then Just (HybridIndexTensor v) else Nothing

hybridIndexTensorLength :: HybridIndexTensor t h w kT kD -> Int
hybridIndexTensorLength (HybridIndexTensor v) = U.length v

-- | Decode a byte under a given @kT@ into its 'Slot'.
decodeSlot :: Int -> Word8 -> Slot
decodeSlot kT b
  | fromIntegral b < kT = Trunk (fromIntegral b)
  | otherwise           = Delta (fromIntegral b - kT)

-- ── Witness 1: every trunk slot is referenced somewhere in the cube ──

-- | Proof that @{0, 1, …, kT-1}@ all appear in the wrapped tensor.
data SurjectiveTrunk t h w kT kD =
  SurjectiveTrunk !(HybridIndexTensor t h w kT kD)

mkSurjectiveTrunk
  :: forall t h w kT kD. (HybridK kT kD)
  => HybridIndexTensor t h w kT kD
  -> Maybe (SurjectiveTrunk t h w kT kD)
mkSurjectiveTrunk it@(HybridIndexTensor v) =
  let kT  = fromIntegral (natVal (Proxy :: Proxy kT)) :: Int
      trunkBytes = U.filter (\b -> fromIntegral b < kT) v
      seen = Set.fromList (map fromIntegral (U.toList trunkBytes) :: [Int])
  in if Set.size seen == kT
       && Set.findMin seen == 0
       && Set.findMax seen == kT - 1
       then Just (SurjectiveTrunk it)
       else Nothing

withSurjectiveTrunk
  :: SurjectiveTrunk t h w kT kD
  -> (HybridIndexTensor t h w kT kD -> r)
  -> r
withSurjectiveTrunk (SurjectiveTrunk it) k = k it

-- ── Witness 2: each frame uses every delta slot 0..kD-1 ──

data SurjectiveDeltaPerFrame t h w kT kD =
  SurjectiveDeltaPerFrame !(HybridIndexTensor t h w kT kD)

mkSurjectiveDeltaPerFrame
  :: forall t h w kT kD.
     ( KnownNat t, KnownNat h, KnownNat w, HybridK kT kD )
  => HybridIndexTensor t h w kT kD
  -> Maybe (SurjectiveDeltaPerFrame t h w kT kD)
mkSurjectiveDeltaPerFrame it@(HybridIndexTensor v) =
  let nt = fromIntegral (natVal (Proxy :: Proxy t))  :: Int
      nh = fromIntegral (natVal (Proxy :: Proxy h))  :: Int
      nw = fromIntegral (natVal (Proxy :: Proxy w))  :: Int
      kT = fromIntegral (natVal (Proxy :: Proxy kT)) :: Int
      kD = fromIntegral (natVal (Proxy :: Proxy kD)) :: Int
      perFrameLen = nh * nw
      framesOk = all (frameUsesAllDeltas kT kD v perFrameLen) [0 .. nt - 1]
  in if framesOk then Just (SurjectiveDeltaPerFrame it) else Nothing
  where
    frameUsesAllDeltas kT kD vec perFrameLen f =
      let start = f * perFrameLen
          chunk = U.slice start perFrameLen vec
          deltas = U.filter (\b -> fromIntegral b >= kT) chunk
          seen   = Set.fromList (map (\b -> fromIntegral b - kT) (U.toList deltas) :: [Int])
      in Set.size seen == kD
         && Set.findMin seen == 0
         && Set.findMax seen == kD - 1

withSurjectiveDeltaPerFrame
  :: SurjectiveDeltaPerFrame t h w kT kD
  -> (HybridIndexTensor t h w kT kD -> r)
  -> r
withSurjectiveDeltaPerFrame (SurjectiveDeltaPerFrame it) k = k it

-- ── Witness 3: voxels with constant source stay in trunk range ──

-- | Proof that for every spatial site @(y, x)@, if the *source* RGB
-- sequence across @t@ is constant (or varies less than the witness's
-- caller-chosen threshold), then the *quantized* sequence at the
-- same site references only trunk slots.
--
-- The smart constructor takes a "static-site predicate" supplied by
-- the caller. The most common predicate is "every channel's range
-- across @t@ at this site is below @ε@" but the predicate is left
-- abstract so the witness type can serve other definitions of
-- "static" (e.g. tile-mean equality, optical-flow zero) without
-- multiplying types.
data TemporalStable t h w kT kD =
  TemporalStable !(HybridIndexTensor t h w kT kD)

mkTemporalStable
  :: forall t h w kT kD.
     ( KnownNat t, KnownNat h, KnownNat w, HybridK kT kD )
  => HybridIndexTensor t h w kT kD
  -> ((Int, Int) -> Bool)        -- ^ Static-site predicate: @(y, x) → "source constant here?"@
  -> Maybe (TemporalStable t h w kT kD)
mkTemporalStable it@(HybridIndexTensor v) isStatic =
  let nt = fromIntegral (natVal (Proxy :: Proxy t))  :: Int
      nh = fromIntegral (natVal (Proxy :: Proxy h))  :: Int
      nw = fromIntegral (natVal (Proxy :: Proxy w))  :: Int
      kT = fromIntegral (natVal (Proxy :: Proxy kT)) :: Int
      perFrameLen = nh * nw
      siteOK (y, x) =
        let sequenceBytes =
              [ v U.! ((f * nh + y) * nw + x) | f <- [0 .. nt - 1] ]
        in all (\b -> fromIntegral b < kT) sequenceBytes
      sites = [(y, x) | y <- [0 .. nh - 1], x <- [0 .. nw - 1], isStatic (y, x)]
      ok = all siteOK sites
      -- 'perFrameLen' is unused at runtime here but keeps the local
      -- name parallel to 'mkSurjectiveDeltaPerFrame' for readability.
      _unused = perFrameLen
  in if ok then Just (TemporalStable it) else Nothing

withTemporalStable
  :: TemporalStable t h w kT kD
  -> (HybridIndexTensor t h w kT kD -> r)
  -> r
withTemporalStable (TemporalStable it) k = k it

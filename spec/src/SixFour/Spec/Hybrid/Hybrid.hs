{- |
Module      : SixFour.Spec.Hybrid.Hybrid
Description : Composite trunk + per-frame deltas type.

A 'HybridPalette' is the spec-level analogue of one GIF written in
trunk/delta mode: one 'TrunkPalette' shared across the whole burst,
plus @t@ 'DeltaPalette's (one per frame). The encoder stitches the
two into each frame's LCT as @trunk ++ deltas[f]@.

The combined gauge group is

  @S_{kT} × (S_{kD})^t@

acting on @(HybridPalette, HybridIndexTensor)@ by permuting trunk
slots once globally and delta slots independently per frame. The
decoded image is invariant — see 'SixFour.Spec.Hybrid.Indices' for
the matching gauge action on indices.
-}
module SixFour.Spec.Hybrid.Hybrid
  ( HybridPalette(..)
  , mkHybridPalette
  , hpTrunkLength
  , hpDeltaCount
  , hpTotalEntries
  ) where

import GHC.TypeLits (Nat, KnownNat, natVal)
import Data.Proxy   (Proxy(..))

import SixFour.Spec.Hybrid.Shape (HybridK)
import SixFour.Spec.Hybrid.Trunk (TrunkPalette, trunkLength)
import SixFour.Spec.Hybrid.Delta (PerFrameDeltas, perFrameDeltasLength)

-- | A trunk plus @t@ per-frame deltas. Together they cover all 256
-- on-disk palette slots when @kT + kD ~ K@.
data HybridPalette (t :: Nat) (kT :: Nat) (kD :: Nat) = HybridPalette
  { hpTrunk  :: !(TrunkPalette kT)
  , hpDeltas :: !(PerFrameDeltas t kD)
  } deriving (Eq, Show)

-- | Smart constructor. Given the type-level constraint @HybridK kT kD@,
-- this is total — the underlying components carry their own length
-- invariants. Exposed for symmetry with the per-component @mk*@s.
mkHybridPalette
  :: forall t kT kD. (KnownNat t, HybridK kT kD)
  => TrunkPalette kT -> PerFrameDeltas t kD -> HybridPalette t kT kD
mkHybridPalette = HybridPalette

hpTrunkLength :: forall t kT kD. (KnownNat kT) => HybridPalette t kT kD -> Int
hpTrunkLength _ = fromIntegral (natVal (Proxy :: Proxy kT))

hpDeltaCount :: forall t kT kD. (KnownNat t) => HybridPalette t kT kD -> Int
hpDeltaCount _ = fromIntegral (natVal (Proxy :: Proxy t))

-- | Total OKLab entries stored across the trunk + all per-frame deltas.
-- For the default (t=64, kT=192, kD=64) this is @192 + 64·64 = 4288@.
hpTotalEntries
  :: forall t kT kD. (KnownNat t, KnownNat kT, KnownNat kD)
  => HybridPalette t kT kD -> Int
hpTotalEntries _ =
  let nt = fromIntegral (natVal (Proxy :: Proxy t))  :: Int
      kT = fromIntegral (natVal (Proxy :: Proxy kT)) :: Int
      kD = fromIntegral (natVal (Proxy :: Proxy kD)) :: Int
  in kT + nt * kD

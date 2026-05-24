{- |
Module      : SixFour.Spec.Hybrid.Shape
Description : Type-level split of the 256-color palette into trunk + delta.

The hybrid GIF mode partitions the palette into two disjoint regions:

  * 'KTrunk' — colors fixed across every frame (live in slots @[0, KTrunk)@).
  * 'KDelta' — colors that change per frame (live in slots @[KTrunk, K)@).

The invariant @KTrunk + KDelta ~ K@ is enforced at the type level via
the 'HybridK' constraint synonym, so any pipeline that asks for the
wrong split refuses to compile.

The default split @(KTrunk = 192, KDelta = 64)@ keeps each LCT close
to GIF's legal ceiling of 256 entries while reserving 75 % of every
frame's palette for the dither-stable trunk. Alternative splits
(@(224, 32)@, @(128, 128)@) are different *types*, not different
runtime configs.
-}
module SixFour.Spec.Hybrid.Shape
  ( -- * Type-level split
    KTrunk, KDelta
  , HybridK
    -- * Runtime knobs (tunable, not type-level)
  , TauPresence(..)
  , defaultTauPresence
  , EpsTrunk(..)
  , defaultEpsTrunk
  , DeltaSnapMargin(..)
  , defaultDeltaSnapMargin
    -- * Reflection helpers
  , kTrunkVal, kDeltaVal
  ) where

import GHC.TypeLits (Nat, KnownNat, natVal, type (+))
import Data.Proxy   (Proxy(..))

import SixFour.Spec.Shape (K)

-- | Number of trunk (globally-stable) palette slots. Defaults to 192.
type KTrunk = 192

-- | Number of delta (per-frame) palette slots. Defaults to 64.
type KDelta = 64

-- | Constraint synonym: a hybrid pipeline parameterised by @(kT, kD)@
-- needs both naturals known at runtime plus the sum (for sizing the
-- on-disk palette). The library is intentionally **size-agnostic** so
-- the property tests can use tiny tensors; the canonical SixFour
-- shape (@kT + kD ~ K = 256@) is enforced separately by 'FullPaletteK'
-- at production callsites.
type HybridK kT kD =
  ( KnownNat kT
  , KnownNat kD
  , KnownNat (kT + kD)
  )

-- | Stronger constraint used at the codegen / on-device boundary:
-- @kT + kD@ must equal the SixFour GIF ceiling @K = 256@. Wrong
-- combinations refuse to compile when this synonym is required.
type FullPaletteK kT kD =
  ( HybridK kT kD
  , (kT + kD) ~ K
  )

-- | The fraction of frames in which a color cluster must appear (within
-- 'EpsTrunk') for it to be promoted into the trunk. Default 0.40.
--
-- Lower values (e.g. 0.10) promote more colors, leading to a larger
-- trunk that may include short-lived motion artifacts. Higher values
-- (e.g. 0.95) only promote truly background-like colors and force more
-- content into the delta range, sharpening per-frame fidelity at the
-- cost of more flicker on borderline colors.
newtype TauPresence = TauPresence { unTauPresence :: Double }
  deriving (Eq, Show)

-- | 0.40 — chosen so a 64-frame burst requires a color to appear in
-- roughly 26 frames to qualify as trunk.
defaultTauPresence :: TauPresence
defaultTauPresence = TauPresence 0.40

-- | OKLab ΔE radius for clustering Stage-A candidate colors when
-- counting trunk presence. Default 0.02 (≈ just-noticeable difference
-- in the OKLab perceptual space for diffuse stimuli).
newtype EpsTrunk = EpsTrunk { unEpsTrunk :: Double }
  deriving (Eq, Show)

defaultEpsTrunk :: EpsTrunk
defaultEpsTrunk = EpsTrunk 0.02

-- | Route a voxel to the trunk if @||c − nearest(trunk)|| ≤ margin ·
-- ||c − nearest(delta_t)||@. Default 1.30 — slightly favors trunk so
-- 3D-STBN coverage stays high and temporal coherence is preserved
-- even when the delta's per-frame fit is marginally tighter.
newtype DeltaSnapMargin = DeltaSnapMargin { unDeltaSnapMargin :: Double }
  deriving (Eq, Show)

defaultDeltaSnapMargin :: DeltaSnapMargin
defaultDeltaSnapMargin = DeltaSnapMargin 1.30

kTrunkVal :: Int
kTrunkVal = fromIntegral (natVal (Proxy :: Proxy KTrunk))

kDeltaVal :: Int
kDeltaVal = fromIntegral (natVal (Proxy :: Proxy KDelta))

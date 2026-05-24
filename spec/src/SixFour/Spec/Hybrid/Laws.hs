{- |
Module      : SixFour.Spec.Hybrid.Laws
Description : Algebraic obligations on a 'HybridPipelineOutput'.

These are pure predicates the property test suite calls. Each
corresponds to a numbered law in the plan file
('/Users/daniel/.claude/plans/misty-gliding-lark.md'). The codegen
mentions each law by name in the emitted Swift doc-comments so on-
device implementations cannot drift from the spec.
-}
module SixFour.Spec.Hybrid.Laws
  ( -- * Law predicates
    lawHybridLegal
  , lawOverheadBound
  , lawTotalEntries
  ) where

import qualified Data.Vector         as V
import qualified Data.Vector.Unboxed as U
import           Data.Word           (Word8)
import           GHC.TypeLits        (KnownNat, natVal)
import           Data.Proxy          (Proxy(..))

import SixFour.Spec.Hybrid.Hybrid  (HybridPalette, hpTotalEntries)
import SixFour.Spec.Hybrid.Indices (HybridIndexTensor(..))

-- | Law 1 (HybridLegal): every emitted byte is in @[0, 255]@. This
-- is trivially true at the 'Word8' type level — the predicate exists
-- so the test suite can assert it explicitly and the codegen can
-- mention it in the emitted Swift contract.
lawHybridLegal :: HybridIndexTensor t h w kT kD -> Bool
lawHybridLegal (HybridIndexTensor v) = U.all (\b -> b <= (255 :: Word8)) v

-- | Law 7 (OverheadBound): the on-disk palette overhead is bounded by
-- @768 + t · 3 · kD@ bytes (the GCT plus one LCT per frame's delta
-- portion at 3 bytes/colour, the trunk piece of the LCT being
-- duplicated from the GCT).
--
-- We do not encode the GIF here, so this predicate computes the
-- *theoretical* upper bound and the property test checks the actual
-- emitted overhead is within that envelope.
lawOverheadBound
  :: forall t kT kD. (KnownNat t, KnownNat kT, KnownNat kD)
  => Proxy t -> Proxy kT -> Proxy kD -> Int -> Bool
lawOverheadBound _ _ pkD actualBytes =
  let nt = fromIntegral (natVal (Proxy :: Proxy t))  :: Int
      kD = fromIntegral (natVal pkD)                  :: Int
      ceiling_ = 768 + nt * 3 * kD
  in actualBytes <= ceiling_

-- | Sanity: a 'HybridPalette' really does store @kT + t·kD@ OKLab
-- triples. This is a structural identity; if it ever fails one of
-- the underlying smart constructors is broken.
lawTotalEntries
  :: forall t kT kD. (KnownNat t, KnownNat kT, KnownNat kD)
  => HybridPalette t kT kD -> Bool
lawTotalEntries hp =
  let nt = fromIntegral (natVal (Proxy :: Proxy t))  :: Int
      kT = fromIntegral (natVal (Proxy :: Proxy kT)) :: Int
      kD = fromIntegral (natVal (Proxy :: Proxy kD)) :: Int
  in hpTotalEntries hp == kT + nt * kD

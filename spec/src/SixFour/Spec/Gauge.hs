{- |
Module      : SixFour.Spec.Gauge
Description : @S_K@ gauge group action on @(palette, indices)@.

Any permutation @σ ∈ S_K@ acts on the pair @(P, I)@ by

  (σ · P)[i] = P[σ^(-1)(i)]
  (σ · I)[p] = σ(I[p])

The resulting GIF is **identical** after decode — the index identities
are unobservable. The 'gaugeAction' function performs both at once;
the 'gather' function (the canonical input to the NN) absorbs the
group entirely by replacing indices with their palette lookups.
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none
module SixFour.Spec.Gauge
  ( Permutation
  , mkPermutation
  , inversePermutation
  , identityPermutation
  , gaugeAction
  , gather
  , permuteVector
  ) where

import qualified Data.Vector         as V
import qualified Data.Vector.Unboxed as U
import           Data.Vector         (Vector)
import qualified Data.Set            as Set
import           GHC.TypeLits        (Nat, KnownNat, natVal)
import           Data.Proxy          (Proxy(..))

import SixFour.Spec.Color   (OKLab)
import SixFour.Spec.Palette (Palette(..))
import SixFour.Spec.Indices (IndexTensor(..))

-- | A permutation of @[0, K-1]@. Stored as a length-@K@ vector where
-- @perm[i] = σ(i)@.
newtype Permutation (k :: Nat) = Permutation { unPerm :: U.Vector Int }
  deriving (Eq, Show)

-- | Build a permutation. Returns 'Nothing' unless the input is a true
-- bijection of @[0, K-1]@.
mkPermutation
  :: forall k. KnownNat k => [Int] -> Maybe (Permutation k)
mkPermutation xs =
  let nk = fromIntegral (natVal (Proxy :: Proxy k)) :: Int
      v  = U.fromList xs
      ok = U.length v == nk
        && Set.fromList xs == Set.fromList [0 .. nk - 1]
  in if ok then Just (Permutation v) else Nothing

-- | The identity permutation on @k@ elements (slot @i@ ↦ @i@).
identityPermutation :: forall k. KnownNat k => Permutation k
identityPermutation =
  let nk = fromIntegral (natVal (Proxy :: Proxy k)) :: Int
  in Permutation (U.generate nk id)

-- | Compute σ⁻¹.
inversePermutation :: forall k. KnownNat k => Permutation k -> Permutation k
inversePermutation (Permutation v) =
  Permutation (inverseRaw v (U.length v))

-- | Apply @σ@ to both palette and indices. The combined action is the
-- identity on the decoded image (Law: Gauge invariance).
gaugeAction
  :: forall t h w k. (KnownNat k)
  => Permutation k
  -> Palette k
  -> IndexTensor t h w k
  -> (Palette k, IndexTensor t h w k)
gaugeAction (Permutation sigma) (Palette ps) (IndexTensor ix) =
  let nk   = U.length sigma
      sInv = inverseRaw sigma nk
      -- (σ · P)[i] = P[σ^{-1}(i)]
      ps'  = V.generate nk (\i -> ps V.! (sInv U.! i))
      -- (σ · I)[p] = σ(I[p])
      ix'  = U.map (sigma U.!) ix
  in (Palette ps', IndexTensor ix')

-- | Replace each index with its palette colour. This is the canonical
-- @NN@ input: the @S_K@ gauge is absorbed because the index identities
-- disappear, leaving only OKLab values.
gather :: Palette k -> IndexTensor t h w k -> V.Vector OKLab
gather (Palette ps) (IndexTensor ix) =
  V.generate (U.length ix) (\p -> ps V.! (ix U.! p))

-- | Apply @σ@ to an arbitrary length-@K@ vector with the palette
-- convention @(σ · v)[i] = v[σ⁻¹(i)]@ — the same reindexing 'gaugeAction'
-- uses on the palette. Lets callers permute weights (or any per-slot
-- attribute) in lock-step with the palette so the (colour, weight)
-- pairing is preserved.
permuteVector :: Permutation k -> V.Vector a -> V.Vector a
permuteVector (Permutation sigma) v =
  let n    = U.length sigma
      sInv = inverseRaw sigma n
  in V.generate n (\i -> v V.! (sInv U.! i))

-- Internal: raw inverse over an unboxed vector.
inverseRaw :: U.Vector Int -> Int -> U.Vector Int
inverseRaw sigma n =
  U.replicate n 0 U.// [ (sigma U.! i, i) | i <- [0 .. n - 1] ]

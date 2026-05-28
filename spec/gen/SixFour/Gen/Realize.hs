{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{- |
Module      : SixFour.Gen.Realize
Description : Realize a 'CyclicStack' (palettes + target populations) as a
              significance-floored 'CompleteVoxelVolume' (the GIF pixels).

A 'CyclicStack' carries, per frame, a palette and a /weight/ distribution over
the @K@ slots — the per-colour pixel population we want. This module turns that
into actual pixels: an integer histogram per frame (every slot floored at
@minPopulation = 2@, summing to @H*W = 4096@), laid out as an index map, then
promoted to a 'CompleteVoxelVolume'.

Two invariants the generator relies on:

  * __Significance by construction.__ Each realized slot is a /point mass/ of
    its own palette colour with count @≥ 2@, so @isSignificant@ holds and
    'proveSignificant' promotes the volume to a 'SignificantVoxelVolume'
    (no donated outliers — the app's contract).
  * __Labels match the bytes.__ The returned 'rzStack' carries the /integer/
    counts as weights, which is exactly what a decoder recovers from the GIF's
    per-frame index histogram. So a §8 descriptor measured on 'rzStack' equals
    the descriptor a consumer computes from the decoded GIF (the statistical
    round-trip).
-}
module SixFour.Gen.Realize
  ( Realized (..)
  , realize
  , quantizeWeights
  , proveSignificant
  ) where

import           Data.List           (sortBy)
import           Data.Ord            (comparing, Down (..))
import           Data.Maybe          (fromMaybe)
import           Data.Proxy          (Proxy (..))
import           GHC.TypeLits        (Nat, KnownNat, natVal)
import qualified Data.IntSet         as IS
import qualified Data.Vector         as V

import SixFour.Spec.Color        (OKLab)
import SixFour.Spec.Palette      (Palette, paletteToList)
import SixFour.Spec.Cyclic       (Weights, CyclicStack (..))
import SixFour.Spec.Indices      ( IndexTensor, CompleteVoxelVolume
                                 , mkIndexTensor, mkCompleteVoxelVolume )
import SixFour.Spec.Significance ( FrameCells (..), classifyCell, minPopulation
                                 , SignificantVoxelVolume, mkSignificantVoxelVolume )

-- | The realized artifacts of a stack, all consistent with one another.
data Realized (t :: Nat) (h :: Nat) (w :: Nat) (k :: Nat) = Realized
  { rzVolume :: !(CompleteVoxelVolume t h w k)   -- ^ what the encoder consumes
  , rzTensor :: !(IndexTensor t h w k)           -- ^ the raw indices (for the brand)
  , rzStack  :: !(CyclicStack t k)               -- ^ palettes + integer-count weights
  , rzCells  :: !(V.Vector (FrameCells k))       -- ^ per-frame significance cells
  }

-- | Quantize a weight distribution to integer pixel counts over a fixed
-- @budget@, with every slot floored at @floorN@ and the counts summing
-- __exactly__ to @budget@ (largest-remainder apportionment of the surplus).
-- Feasible iff @floorN * K ≤ budget@ (the SixFour shape: @2*256 = 512 ≤ 4096@).
quantizeWeights :: Int -> Int -> Weights -> [Int]
quantizeWeights budget floorN ws =
  let k         = V.length ws
      remaining = budget - floorN * k
      s         = V.sum ws
      ps        = if s <= 0 then V.replicate k (1 / fromIntegral (max 1 k))
                            else V.map (/ s) ws
      idealV    = V.map (* fromIntegral remaining) ps
      baseV     = V.map (floor :: Double -> Int) idealV
      assigned  = V.sum baseV
      leftover  = remaining - assigned
      -- bump the `leftover` slots with the largest fractional remainder
      fracs     = [ (idealV V.! i - fromIntegral (baseV V.! i), i) | i <- [0 .. k - 1] ]
      bumpSet   = IS.fromList (map snd (take leftover (sortBy (comparing (Down . fst)) fracs)))
  in [ floorN + (baseV V.! i) + (if i `IS.member` bumpSet then 1 else 0) | i <- [0 .. k - 1] ]

-- | Realize a stack into a 'CompleteVoxelVolume' plus the consistent label
-- artifacts. 'Nothing' only on an infeasible shape (never on @64³@/K=256).
realize
  :: forall t h w k. (KnownNat t, KnownNat h, KnownNat w, KnownNat k)
  => CyclicStack t k -> Maybe (Realized t h w k)
realize (CyclicStack frames) = do
  let budget        = natI (Proxy :: Proxy h) * natI (Proxy :: Proxy w)
      floorN        = minPopulation
      perFrame      = [ frameRealize budget floorN pal ws | (pal, ws) <- V.toList frames ]
      flat          = concatMap (\(idx, _, _) -> idx) perFrame
      countWeights  = [ V.fromList (map fromIntegral cs) | (_, cs, _) <- perFrame ]
      cells         = V.fromList [ fc | (_, _, fc) <- perFrame ]
  it  <- mkIndexTensor @t @h @w @k flat
  cvv <- mkCompleteVoxelVolume it
  let stack' = CyclicStack (V.fromList (zipWith (\(pal, _) w -> (pal, w))
                                                (V.toList frames) countWeights))
  pure (Realized cvv it stack' cells)

-- | One frame: integer histogram → (row-major index list, counts, cells).
-- Layout is block (all of slot 0, then slot 1, …); order within a frame does
-- not affect the histogram-based §8 descriptor or the palette.
frameRealize :: Int -> Int -> Palette k -> Weights -> ([Int], [Int], FrameCells k)
frameRealize budget floorN pal ws =
  let counts = quantizeWeights budget floorN ws
      cols   = V.fromList (paletteToList pal)
      idx    = concat [ replicate (counts !! s) s | s <- [0 .. V.length cols - 1] ]
      cell s = classifyCell (replicate (counts !! s) (cols V.! s))
      fc     = FrameCells (V.generate (V.length cols) cell)
  in (idx, counts, fc)

-- | Promote a realized volume to the 'SignificantVoxelVolume' brand — proof
-- that every slot in every frame is population-backed (@≥ minPopulation@), not
-- a donated outlier. Total on the SixFour shape; 'Nothing' would signal a bug.
proveSignificant
  :: forall t h w k. (KnownNat t, KnownNat h, KnownNat w, KnownNat k)
  => Realized t h w k -> Maybe (SignificantVoxelVolume t h w k)
proveSignificant rz = mkSignificantVoxelVolume (rzTensor rz) (rzCells rz)

natI :: KnownNat n => Proxy n -> Int
natI = fromIntegral . natVal

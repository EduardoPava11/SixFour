{- |
Module      : SixFour.Spec.StageA
Description : Stage A — variance-cut seed + Lloyd refinement (pinned, deterministic).

Stage A maps a single frame (@H × W@ OKLab pixels) to a per-frame palette
of @K@ OKLab centroids plus the index tensor that reconstructs the frame
under nearest-OKLab.

This module specifies the **interface** and the **algebraic obligations**
that any conforming implementation (Haskell ref, Swift on-device,
Python in the trainer) must satisfy. A reference implementation lives
inline so QuickCheck can compare any other implementation against it.

The on-device implementation in @SixFour/Palette/VarianceCutSeeder.swift@
is NOT Xiaolin Wu's algorithm — it is the closely-related "variance-cut"
of Bloomberg et al. (1994), which iteratively splits the highest-variance
box at the mean of its longest axis. Wu's original (1991/1992) builds a
3D histogram with cumulative-moment sum tables and splits to maximise
@ΔSSE@; variance-cut is faster and produces near-identical seeds on the
natural-image regime SixFour captures. We commit to the variance-cut
name to avoid the documentation lie.

References:

  * Bloomberg, D. S., 1994. /An Improved Median-Cut Algorithm of Color
    Image Quantization/.
  * X. Wu, /Color Quantization by Dynamic Programming and Principal
    Analysis/, ACM Transactions on Graphics, 1992
    (the original "Wu" algorithm, not what is implemented here).
-}
module SixFour.Spec.StageA
  ( Frame(..)
  , StageA(..)
  , runStageA
  , varianceCutReference
  ) where

import qualified Data.Vector         as V
import qualified Data.Vector.Unboxed as U
import           Data.List           (foldl', sortOn)
import           GHC.TypeLits        (Nat, KnownNat, natVal)
import           Data.Proxy          (Proxy(..))

import SixFour.Spec.Color   (OKLab(..), okLabDistanceSquared)
import SixFour.Spec.Palette (Palette(..))
import SixFour.Spec.Indices (IndexTensor(..))

-- | A single frame: @H × W@ OKLab pixels, stored row-major.
newtype Frame (h :: Nat) (w :: Nat) =
  Frame { unFrame :: V.Vector OKLab }
  deriving (Eq, Show)

-- | Stage A is the contract; any value of this type is a candidate
-- implementation. @runStageA wuReference@ is the pinned reference.
newtype StageA (h :: Nat) (w :: Nat) (k :: Nat) =
  StageA { runStage :: Frame h w -> (Palette k, IndexTensor 1 h w k) }

runStageA
  :: StageA h w k
  -> Frame h w
  -> (Palette k, IndexTensor 1 h w k)
runStageA = runStage

-- | A simple variance-cut-flavoured reference quantizer:
--
-- 1. Initialise @K@ seeds by uniform sampling of the input pixels
--    (variance-cut produces near-identical seeds for natural images;
--     the property test compares centroid quality, not seed identity).
-- 2. Run 3 Lloyd iterations in OKLab.
-- 3. Assign every pixel to its nearest centroid.
--
-- This is deliberately the **simplest** thing that satisfies the
-- Stage A obligations below. The actual on-device implementation
-- uses @SixFour/Palette/VarianceCutSeeder.swift@ and the QuickCheck
-- @Properties.Wu@ suite asserts equivalence of the *contracts*, not
-- the *internals*.
varianceCutReference
  :: forall h w k. (KnownNat h, KnownNat w, KnownNat k)
  => StageA h w k
varianceCutReference = StageA $ \(Frame pixels) ->
  let nk        = fromIntegral (natVal (Proxy :: Proxy k)) :: Int
      n         = V.length pixels
      -- Step 1: stride-sampled seeds.
      stride    = max 1 (n `div` nk)
      seeds0    = V.fromList
                    [ pixels V.! (i * stride `mod` n) | i <- [0 .. nk - 1] ]
      -- Steps 2-3: 3 Lloyd iterations.
      centroids = lloyd 3 seeds0 pixels
      -- Final assignments.
      assigns   = V.toList (V.map (nearest centroids) pixels)
      ix        = IndexTensor (U.fromList assigns)
      pal       = Palette centroids
  in (pal, ix)

-- | Single Lloyd step: assign + average.
lloydStep :: V.Vector OKLab -> V.Vector OKLab -> V.Vector OKLab
lloydStep centroids pixels =
  let nk         = V.length centroids
      assignment = V.map (nearest centroids) pixels
      -- Accumulate sums per cluster.
      acc :: V.Vector (Double, Double, Double, Int)
      acc = V.accumulate
              (\(sL, sA, sB, n) (OKLab l a b) -> (sL + l, sA + a, sB + b, n + 1))
              (V.replicate nk (0, 0, 0, 0))
              (V.zip assignment pixels)
      avg (_, _, _, 0)         old = old   -- empty cluster — keep old centroid
      avg (sL, sA, sB, n)      _   =
        let nd = fromIntegral n :: Double
        in OKLab (sL / nd) (sA / nd) (sB / nd)
  in V.zipWith avg acc centroids

-- | @n@ Lloyd iterations.
lloyd :: Int -> V.Vector OKLab -> V.Vector OKLab -> V.Vector OKLab
lloyd n cs xs = foldl' (\c _ -> lloydStep c xs) cs [1 .. n]

-- | Index of nearest centroid by OKLab squared distance.
nearest :: V.Vector OKLab -> OKLab -> Int
nearest cs x =
  fst $ V.foldl'
    (\acc@(_, bestD) (i, c) ->
       let d = okLabDistanceSquared x c
       in if d < bestD then (i, d) else acc)
    (0, 1/0 :: Double)
    (V.indexed cs)

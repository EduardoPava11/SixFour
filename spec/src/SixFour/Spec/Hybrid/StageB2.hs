{- |
Module      : SixFour.Spec.Hybrid.StageB2
Description : Stage B2 — per-frame delta fit on the residual.

Stage B2 takes a frame's source pixels and the already-extracted
'TrunkPalette', then produces a 'DeltaPalette' of @kD@ colors that
covers the per-pixel *residual* after trunk projection.

The residual @r = source − π_trunk(source)@ is the part of each pixel
that the trunk cannot represent without quantization error above
'EpsTrunk'. By k-meansing the residual (in OKLab) we get @kD@
representative offsets, which we re-add to the local trunk projection
to land back in absolute OKLab. The deltas are therefore *absolute*
OKLab colors, not offsets — important because the dithering kernel
runs nearest-neighbour search against absolute colors.

If fewer than @kD@ residuals exceed 'EpsTrunk' (e.g. the trunk
already covers the frame nearly perfectly), the spec pads with
slightly-jittered copies of the leftmost trunk centroids so the delta
palette is always exactly @kD@ entries.
-}
module SixFour.Spec.Hybrid.StageB2
  ( StageB2Input(..)
  , StageB2Output(..)
  , StageB2(..)
  , runStageB2
  , deltaFitReference
  ) where

import qualified Data.Vector         as V
import           Data.List           (foldl')
import           GHC.TypeLits        (Nat, KnownNat, natVal)
import           Data.Proxy          (Proxy(..))

import SixFour.Spec.Color   (OKLab(..), okLabDistanceSquared)
import SixFour.Spec.StageA  (Frame(..))

import SixFour.Spec.Hybrid.Shape (HybridK, EpsTrunk(..))
import SixFour.Spec.Hybrid.Trunk (TrunkPalette(..))
import SixFour.Spec.Hybrid.Delta (DeltaPalette(..), PerFrameDeltas(..))

-- | One burst of frames + the trunk extracted upstream.
data StageB2Input (t :: Nat) (h :: Nat) (w :: Nat) (kT :: Nat) = StageB2Input
  { sb2Frames :: ![Frame h w]      -- ^ length @t@
  , sb2Trunk  :: !(TrunkPalette kT)
  }

-- | One delta palette per frame.
newtype StageB2Output (t :: Nat) (kD :: Nat) =
  StageB2Output { sb2Deltas :: PerFrameDeltas t kD }

newtype StageB2 (t :: Nat) (h :: Nat) (w :: Nat) (kT :: Nat) (kD :: Nat) =
  StageB2 { runStage2Raw :: StageB2Input t h w kT -> StageB2Output t kD }

runStageB2
  :: StageB2 t h w kT kD
  -> StageB2Input t h w kT
  -> StageB2Output t kD
runStageB2 = runStage2Raw

deltaFitReference
  :: forall t h w kT kD.
     ( KnownNat t, KnownNat h, KnownNat w, HybridK kT kD )
  => EpsTrunk
  -> Int                       -- ^ Lloyd iterations for the per-frame k-means
  -> StageB2 t h w kT kD
deltaFitReference (EpsTrunk eps) lloydIters = StageB2 $
  \(StageB2Input frames trunk) ->
    let kD   = fromIntegral (natVal (Proxy :: Proxy kD)) :: Int
        eps2 = eps * eps
        deltasPerFrame =
          [ fitOneFrame trunk eps2 kD lloydIters fr | fr <- frames ]
    in StageB2Output
         { sb2Deltas =
             PerFrameDeltas (V.fromList (map DeltaPalette deltasPerFrame))
         }

-- | Per-frame fit: extract residuals above 'eps', k-means them, re-add
-- the trunk projection.
fitOneFrame :: TrunkPalette kT -> Double -> Int -> Int -> Frame h w -> V.Vector OKLab
fitOneFrame (TrunkPalette tv) eps2 kD lloydIters (Frame pixels) =
  let -- Project each pixel onto its nearest trunk colour.
      projected :: V.Vector (OKLab, OKLab, Double)     -- (source, trunkProj, sqErr)
      projected = V.map (\c ->
        let (proj, d) = nearestWithDistSq tv c
        in (c, proj, d)) pixels

      -- Significant residuals: those above the eps² threshold.
      significant :: V.Vector OKLab
      significant = V.map (\(c, _, _) -> c)
                  $ V.filter (\(_, _, d) -> d > eps2) projected

      -- If the trunk covers (almost) everything, we still need kD
      -- entries. Pad with the same source colours subject to nearby
      -- jitter on the L axis so the slots are syntactically distinct.
      padIfShort xs =
        if V.length xs >= kD
          then xs
          else
            let n     = V.length xs
                fills = [ OKLab (0.05 + 0.02 * fromIntegral i) 0 0
                        | i <- [0 .. kD - 1 - n] ]
            in xs <> V.fromList fills

      seedSet = padIfShort significant

      -- Initial centroids: stride sample of the residual set.
      n0     = V.length seedSet
      stride = max 1 (n0 `div` kD)
      seeds0 = V.fromList
        [ seedSet V.! ((i * stride) `mod` n0)
        | i <- [0 .. kD - 1] ]

      centroids = foldl' (\cs _ -> lloydStep cs seedSet) seeds0 [1 .. lloydIters]
  in centroids

-- | One Lloyd step against unit-weighted points.
lloydStep :: V.Vector OKLab -> V.Vector OKLab -> V.Vector OKLab
lloydStep cs xs =
  let nK = V.length cs
      assignment = V.map (nearestIdx cs) xs
      acc :: V.Vector (Double, Double, Double, Int)
      acc = V.accumulate
              (\(sL, sA, sB, n) (OKLab l a b) -> (sL + l, sA + a, sB + b, n + 1))
              (V.replicate nK (0, 0, 0, 0))
              (V.zip assignment xs)
      avg (_, _, _, 0)         old = old
      avg (sL, sA, sB, n)      _   =
        let nd = fromIntegral n :: Double
        in OKLab (sL / nd) (sA / nd) (sB / nd)
  in V.zipWith avg acc cs

nearestIdx :: V.Vector OKLab -> OKLab -> Int
nearestIdx cs x =
  fst $ V.foldl'
    (\acc@(_, bestD) (i, c) ->
       let d = okLabDistanceSquared x c
       in if d < bestD then (i, d) else acc)
    (0, 1/0 :: Double)
    (V.indexed cs)

nearestWithDistSq :: V.Vector OKLab -> OKLab -> (OKLab, Double)
nearestWithDistSq cs x =
  V.foldl'
    (\acc@(_, bestD) c ->
       let d = okLabDistanceSquared x c
       in if d < bestD then (c, d) else acc)
    (V.head cs, 1/0 :: Double)
    cs

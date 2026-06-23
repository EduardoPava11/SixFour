{- |
Module      : SixFour.Spec.Collapse
Description : The per-frame-palette → single-palette collapse contract.

The capture produces 64 per-frame palettes that deliberately VARY (each is a
diverse sample of the scene's true gamut). A NN collapses them into one palette
— this is, classically, a **Wasserstein barycenter** of the 64 palettes
(Agueh–Carlier; entropic Sinkhorn). The removed Stage B Sinkhorn was the
hand-coded balanced version; @SixFour.Spec.Cyclic@ still holds the entropic-OT
transition machinery. The NN learns that barycenter.

This module pins the CONTRACT + a diversity-preserving classical baseline:
@farthestPointCollapse@ pools the colours of all input palettes and maximin-
selects @K@ representatives — the collapse that RETAINS the most gamut coverage
(it picks actual input colours, so it never invents colour and never exceeds
the inputs' gamut). It is deterministic, gauge/order-invariant, and idempotent
on identical inputs — the laws (see @Properties.Collapse@) any valid collapse,
learned or classical, must satisfy. It reuses the same maximin idea as the
Swift `KMeansPalettePipeline.farthestPointSeedCentroids` and the Coverage metric
that scores it.
-}
-- COMPARTMENT: METAL-GPU | tag:none
module SixFour.Spec.Collapse
  ( pooledCandidates
  , farthestPointCollapse
  ) where

import qualified Data.Vector as V
import           Data.List   (foldl')
import           GHC.TypeLits (Nat, KnownNat, natVal)
import           Data.Proxy   (Proxy(..))

import SixFour.Spec.Color   (OKLab(..), okLabDistanceSquared)
import SixFour.Spec.Palette (Palette(..))

-- | Union of every entry across the per-frame palettes — the candidate cloud a
-- barycenter collapses. (Diversity collapse selects by spread, so weights are
-- not needed here; an OT/mass-balanced collapse would also carry counts.)
pooledCandidates :: [Palette k] -> [OKLab]
pooledCandidates pals = concat [ V.toList v | Palette v <- pals ]

-- | Diversity-preserving classical collapse: farthest-point (maximin) selection
-- of @K@ representatives from the pooled candidates. First seed = the candidate
-- farthest from the cloud mean (a deterministic extreme); each subsequent pick
-- maximizes the minimum distance to those already chosen. Output is exactly @K@
-- entries (candidates are reused if fewer than @K@ distinct exist), every one an
-- actual input colour — so the collapse never exceeds the inputs' gamut.
farthestPointCollapse :: forall k. KnownNat k => [Palette k] -> Palette k
farthestPointCollapse pals =
  let k     = fromIntegral (natVal (Proxy :: Proxy k)) :: Int
      cands = V.fromList (pooledCandidates pals)
      n     = V.length cands
  in if n == 0 || k == 0
       then Palette (V.replicate k (OKLab 0 0 0))
       else
         let -- First seed: candidate farthest from the cloud mean.
             m       = scaleOK (1 / fromIntegral n) (V.foldl' addOK (OKLab 0 0 0) cands)
             first   = V.maxIndexBy (\x y -> compare (d2 x m) (d2 y m)) cands
             -- Greedy maximin: maintain min-distance to chosen set, pick argmax.
             step (chosen, minD) _ =
               let c        = cands V.! last chosen
                   minD'    = V.zipWith min minD (V.map (d2 c) cands)
                   nextIdx  = V.maxIndex minD'
               in (chosen ++ [nextIdx], minD')
             minD0   = V.map (d2 (cands V.! first)) cands
             (idxs, _) = foldl' step ([first], minD0) [2 .. k]
         in Palette (V.fromList [ cands V.! i | i <- idxs ])
  where
    d2 = okLabDistanceSquared
    addOK (OKLab l a b) (OKLab l' a' b') = OKLab (l + l') (a + a') (b + b')
    scaleOK s (OKLab l a b) = OKLab (s * l) (s * a) (s * b)


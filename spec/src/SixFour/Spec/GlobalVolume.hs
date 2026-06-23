{- |
Module      : SixFour.Spec.GlobalVolume
Description : The WHOLE-GIF index-volume contract for a single global palette (GIFB).

The per-frame 'CompleteVoxelVolume' (Spec.Shape / StageContract.swift) requires
EACH frame to be surjective onto all K palette slots. That is correct for the
per-frame-palette GIF, but WRONG for a single global palette: with one shared
256-colour table a given frame need not exercise every colour. The guarantee is
RESTATED at the whole GIF, not weakened:

  * 'globalComplete' — exactly T frames, each @pixelsPerFrame@ long, and the UNION
    of indices over all frames is surjective onto all K global slots (every global
    colour is used SOMEWHERE in the GIF).
  * 'globalSignificant' — every global slot is backed by ≥ 'minPopulation' POOLED
    pixels (summed over the whole GIF), and the total mass is exactly
    @T·pixelsPerFrame@. So "no empty / donated-outlier slot ships" survives at GIF
    scale (guaranteed by the whole-GIF significance rescue in DeterministicRenderer).

The cores are parameterised (@…N t p k@) for cheap QuickCheck; the Shape-bound
aliases are what 'Codegen.Swift.emitGlobalVolumeContract' mirrors into
@GlobalVolumeContract.swift@.
-}
-- COMPARTMENT: ZIG-FLOOR | tag:DeviceTag
module SixFour.Spec.GlobalVolume
  ( globalCompleteN
  , globalSignificantN
  , globalComplete
  , globalSignificant
    -- * Laws (QuickCheck'd in Properties.GlobalVolume)
  , lawCompleteRejectsMissingSlot
  , lawCompleteWeakerThanPerFrame
  , lawSignificantTotalMass
  , lawSignificantBacksEverySlot
  ) where

import qualified Data.Set as Set

import SixFour.Spec.Shape         (tVal, kVal, pixelsPerFrame)
import SixFour.Spec.Significance  (minPopulation)

-- | Whole-GIF completeness, parameterised by @t@ frames × @p@ pixels onto @k@
-- slots: exactly @t@ frames each of length @p@; every index in @[0,k)@; and the
-- union of all indices covers all @k@ slots.
globalCompleteN :: Int -> Int -> Int -> [[Int]] -> Bool
globalCompleteN t p k frames =
     length frames == t
  && all ((== p) . length) frames
  && all (\i -> i >= 0 && i < k) (concat frames)
  && Set.size (Set.fromList (concat frames)) == k

-- | Whole-GIF significance, parameterised: @counts@ has @k@ entries, each
-- ≥ 'minPopulation', summing to exactly @t·p@ (total pixel mass).
globalSignificantN :: Int -> Int -> Int -> [Int] -> Bool
globalSignificantN t p k counts =
     length counts == k
  && all (>= minPopulation) counts
  && sum counts == t * p

-- | The shipped SixFour shape (T frames × pixelsPerFrame onto K slots).
globalComplete :: [[Int]] -> Bool
globalComplete = globalCompleteN tVal pixelsPerFrame kVal

-- | Does this global index assignment meet the significance floor (every slot ≥ min population)?
globalSignificant :: [Int] -> Bool
globalSignificant = globalSignificantN tVal pixelsPerFrame kVal

-- ---------------------------------------------------------------------------
-- Laws
-- ---------------------------------------------------------------------------

-- | Dropping any used slot from the union breaks completeness (surjectivity is
-- load-bearing). For @k ≥ 1@: a volume that uses only slots @[0,k-1)@ is NOT complete.
lawCompleteRejectsMissingSlot :: Int -> Int -> Bool
lawCompleteRejectsMissingSlot tRaw kRaw =
  let t = 1 + (abs tRaw `mod` 4)
      k = 2 + (abs kRaw `mod` 6)
      p = k                       -- each frame = one of every slot except the last
      frame = [0 .. k - 2] ++ [0] -- length k, misses slot (k-1)
      frames = replicate t frame
  in not (globalCompleteN t p k frames)

-- | Whole-GIF completeness is WEAKER than per-frame: frames that each use a
-- DISJOINT proper subset are still complete iff their union covers @k@. Here @k@
-- frames, frame @i@ constant-@i@, union = all @k@ — complete, though no single
-- frame is surjective.
lawCompleteWeakerThanPerFrame :: Int -> Bool
lawCompleteWeakerThanPerFrame kRaw =
  let k = 2 + (abs kRaw `mod` 6)
      p = 3
      frames = [ replicate p i | i <- [0 .. k - 1] ]   -- t = k frames
  in globalCompleteN k p k frames

-- | A significant volume's pooled counts sum to the exact total mass @t·p@.
lawSignificantTotalMass :: Int -> Int -> Int -> Bool
lawSignificantTotalMass tRaw pRaw kRaw =
  let t = 1 + (abs tRaw `mod` 4)
      k = 1 + (abs kRaw `mod` 6)
      -- distribute t*p as evenly as possible, each ≥ minPopulation when feasible
      total = t * max (k * minPopulation) (abs pRaw `mod` 50 + k * minPopulation)
      base = total `div` k
      counts = replicate (k - 1) base ++ [total - base * (k - 1)]
  in globalSignificantN t (total `div` t) k counts
       == (length counts == k && all (>= minPopulation) counts && sum counts == t * (total `div` t))

-- | Significance implies every slot is backed (≥ minPopulation ⇒ ≥ 1 ⇒ used).
lawSignificantBacksEverySlot :: [Int] -> Bool
lawSignificantBacksEverySlot countsRaw =
  let k = max 1 (length countsRaw)
      counts = map (\c -> minPopulation + abs c `mod` 7) countsRaw
      t = 1
      p = sum counts
  in null countsRaw
     || (globalSignificantN t p k counts && all (>= minPopulation) counts)

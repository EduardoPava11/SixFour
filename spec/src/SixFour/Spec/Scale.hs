{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeApplications #-}
{- |
Module      : SixFour.Spec.Scale
Description : Instantiate the look-NN at the REAL 64×64×64×256 shape and verify every layer.

The property suite ("Properties.*") runs the laws on tiny stubs (T=2, H=2, W=2, K=4) for
QuickCheck speed. But the spec must hold at the __real__ @T·H·W·K = 64·64·64·256@ — and
generating a genuine 64³ GIF __is__ that test. This module is the single source of truth:

  * 'synthLookInput' — a full 64³ synthetic capture (256-colour per-frame palettes on the
    golden-angle chroma spiral + a per-voxel index field). Fills the long-flagged
    "synth is palette-level only" gap; pure (no JuicyPixels), so both the test-suite and the
    @spec-gif@ executable share it.

  * 'layerLawReport' — runs the whole pipeline at 64³ and returns, per layer L1–L9 (+ the
    typed-'SixFour.Spec.Layer' composition), the contract and whether it holds. The
    test-suite asserts @all snd@; @spec-gif@ prints it and refuses to render on any failure.

The index field @localIndex t y x = (4·(x+y)+t) mod 256@ makes each frame use one
residue-class of slots (per-frame __incomplete__) while the loop-union is all 256 (globally
__surjective__) — so the L8 contract is exhibited by the synth itself.
-}
module SixFour.Spec.Scale
  ( -- * The real shape
    scaleT, scaleH, scaleW, scaleK
    -- * Synthetic 64³ capture
  , paletteColor
  , localIndex
  , synthLookInput
  , randomResidual
    -- * The all-layers verification at 64³
  , layerLawReport
  , failingLayers
  , allLayersHold
  ) where

import           Data.Bits           (shiftR)
import           Data.Maybe          (fromJust, isJust, isNothing)
import           Data.Word           (Word64)
import qualified Data.Vector         as V

import SixFour.Spec.Color    (OKLab(..))
import SixFour.Spec.Palette  (mkPalette)
import SixFour.Spec.Cyclic   (CyclicStack(..), Weights)
import SixFour.Spec.Indices
  (mkIndexTensor, indexTensorLength, mkGlobalSurjective, mkCompleteVoxelVolume)
import SixFour.Spec.GMM      (gaussianToken, totalWeight)
import SixFour.Spec.PairTree
  (HaarPalette(..), reconstruct, lawBalancedMean, lawReconstructAnalyzeRoundTrip)
import SixFour.Spec.LookCore (lawNeutralIsFloor, lawBoundedLeaves, lawSigmaEquivariant)
import SixFour.Spec.Dither   (lawDitherMeanRecoversP)
import SixFour.Spec.LookNet
  ( LookInput(..), LookOutput(..), runLookNet, baselinePalette
  , poolToGMM, poolCandidates, perFramePalettes, remapFrame )
import SixFour.Spec.Layer    (lawPipeMatchesManual, runWholeLookNet)

-- | The real SixFour shape (T·H·W·K = 64·64·64·256).
scaleT, scaleH, scaleW, scaleK :: Int
scaleT = 64
scaleH = 64
scaleW = 64
scaleK = 256

goldenAngle :: Double
goldenAngle = 2.39996322972865332  -- 2π(2−φ) ≈ 137.5°

-- | Colour of palette slot @k@ in frame @t@ (seeded): golden-angle chroma spread, a
-- lightness ramp, and a slow per-frame hue drift.
paletteColor :: Word64 -> Int -> Int -> OKLab
paletteColor seed t k =
  let kf     = fromIntegral k
      phase  = fromIntegral (seed `mod` 360) * (pi / 180)
      theta  = kf * goldenAngle + fromIntegral t * 0.06 + phase
      radius = 0.05 + 0.16 * sqrt (kf / fromIntegral (scaleK - 1))
      l      = 0.15 + 0.70 * (kf / fromIntegral (scaleK - 1))
  in OKLab l (radius * cos theta) (radius * sin theta)

-- | Local palette index at voxel @(t,y,x)@: per-frame residue-class subset (incomplete),
-- loop-union all 256 (globally surjective).
localIndex :: Int -> Int -> Int -> Int
localIndex t y x = (4 * (x + y) + t) `mod` scaleK

-- | A full 64×64×64 look-input. The 'fromJust's are total: a 256-colour palette and
-- 262144 indices in @[0,256)@, fixed by construction.
synthLookInput :: Word64 -> LookInput 64 64 64 256
synthLookInput seed =
  let frame t = ( fromJust (mkPalette @256 [ paletteColor seed t k | k <- [0 .. scaleK - 1] ])
                , V.replicate scaleK 1.0 :: Weights )
      stack   = CyclicStack (V.fromList [ frame t | t <- [0 .. scaleT - 1] ])
      idxs    = [ localIndex t y x | t <- [0 .. scaleT - 1], y <- [0 .. scaleH - 1], x <- [0 .. scaleW - 1] ]
      indices = fromJust (mkIndexTensor @64 @64 @64 @256 idxs)
  in LookInput stack indices

-- | A random look-residual shaped like the floor (one point of the engineered per-user
-- variance space). Pre-tanh values in @[-2,2]@ exercise the bound.
randomResidual :: Word64 -> HaarPalette -> HaarPalette
randomResidual seed (HaarPalette _ lvls) =
  case randomOKLabs seed of           -- the stream is infinite, so the [] arm is unreachable
    []         -> HaarPalette (OKLab 0 0 0) []
    (r : rest) -> HaarPalette r (consume lvls rest)
  where consume []         _  = []
        consume (lv : lvs) xs = let (hd, tl) = splitAt (length lv) xs in hd : consume lvs tl

randomOKLabs :: Word64 -> [OKLab]
randomOKLabs = go
  where go s = let (a, s1) = u s; (b, s2) = u s1; (c, s3) = u s2
               in OKLab (4 * a - 2) (4 * b - 2) (4 * c - 2) : go s3
        u s = let s' = s * 6364136223846793005 + 1442695040888963407
              in (fromIntegral (s' `shiftR` 11) / 9007199254740992, s')  -- [0,1)

-- | Run the whole pipeline at 64³ and report, per layer, whether its contract holds.
-- Each entry @(layer, holds)@; the test asserts @all snd@, the GIF tool gates on it.
layerLawReport :: Word64 -> [(String, Bool)]
layerLawReport seed =
  let inp    = synthLookInput seed
      stack  = liStack inp
      floor' = baselinePalette stack
      out    = runLookNet floor' inp
      global = reconstruct (loPalette out)
      locals = perFramePalettes stack
      looks  = [ randomResidual (seed * 131 + fromIntegral i) floor' | i <- [0 .. 7 :: Int] ]
      whole  = runWholeLookNet inp
  in [ ("L1 Pool: T*K candidates",            length (poolCandidates stack) == scaleT * scaleK)
     , ("L1 Pool: mixture normalised",        abs (totalWeight (poolToGMM stack) - 1) < 1e-9)
     , ("L2 GMM: token width 10",             all ((== 10) . length . gaussianToken) (poolToGMM stack))
     , ("L3-L5 LookCore: neutral = floor",    lawNeutralIsFloor floor')
     , ("L3-L5 LookCore: bounded (forall look)",       all (lawBoundedLeaves   1e-9 floor') looks)
     , ("L3-L5 LookCore: sigma-equivariant (forall look)", all (lawSigmaEquivariant 1e-9 floor') looks)
     , ("L6 Reconstruct: K=256 leaves",       length global == scaleK)
     , ("L6 Reconstruct: balanced mean",      lawBalancedMean 1e-9 floor')
     , ("L6 Reconstruct: Haar round-trip",    lawReconstructAnalyzeRoundTrip 1e-9 global)
     , ("L7 Remap: indices in [0,K)",         all (all (\i -> i >= 0 && i < scaleK) . remapFrame global) locals)
     , ("L8 GlobalIndex: full T*H*W length",  indexTensorLength (loIndices out) == scaleT * scaleH * scaleW)
     , ("L8 GlobalIndex: globally surjective",isJust    (mkGlobalSurjective   (loIndices out)))
     , ("L8 GlobalIndex: per-frame incomplete", isNothing (mkCompleteVoxelVolume (loIndices out)))
     , ("L9 Dither: temporal mean recovers p",and [ lawDitherMeanRecoversP 0.02 scaleT p | p <- [0.25, 0.382, 0.5, 0.75] ])
     , ("Typed pipe == manual composition",   lawPipeMatchesManual stack)
     , ("WholeLookNet == runLookNet",         loPalette whole == loPalette out && loIndices whole == loIndices out)
     ]

-- | The layers (by name) whose contract FAILED at 64³ — empty when the spec holds.
failingLayers :: Word64 -> [String]
failingLayers seed = [ n | (n, ok) <- layerLawReport seed, not ok ]

-- | Does the whole spec hold at 64³ for this seed?
allLayersHold :: Word64 -> Bool
allLayersHold = null . failingLayers

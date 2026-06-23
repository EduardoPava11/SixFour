{- |
Module      : SixFour.Spec.HalfwayLatent
Description : The encoder FUSE is the never-surfaced 32³ midpoint — a theorem. The architecture-map waist (where Encoder A and Encoder B combine: @N = 64@ tokens × @d_model = 512@ = the ViT working memory) and the spine's Down-rung intermediate (@32³ = 32768@ voxels, "SixFour.Spec.JepaMemory") are PROVABLY the same object.

The H-JEPA spine names a never-surfaced organisable level — the @32³@/@128³@ intermediate
("SixFour.Spec.RungPivot") — as the one level the net is free to organise. The architecture
map, arriving from the OTHER direction (the ViT), names a token waist @N × d_model@ where the
per-modality encoders fuse. This module proves those two INDEPENDENTLY-defined quantities are
the SAME number:

  * 'lawFuseIsMidpoint' (KEYSTONE) — @vitTokens · vitDModel == latentWorkingMemoryVoxels Down@,
    i.e. @64 · 512 == 32768 == 32³@. The fuse IS the midpoint. Teeth: any other @(N, d)@
    factorisation (e.g. @d=256@) breaks it, so the ViT width is PINNED by the spine, not chosen.
  * 'lawHalfwayDimIsGeometricMean' — @32³ = √(16³·64³)@ (squared to stay integer:
    @(32³)² == 16³·64³@), AND the waist equals that geometric midpoint — so "halfway" is the
    halfway DIMENSIONALITY, the channel width is what is freed from the cube.
  * 'lawWaistTokensAreOctantLeaves' — the token axis @N=64@ is the depth-2 octant lattice
    (@8² = 64@), not an arbitrary sequence length.
  * 'lawWaistTokensMatchSynthesis' — the same @N@ the policy/value synthesis uses
    ("SixFour.Spec.SynthesisPolicyValue" @nTokens@), so the two scope-outs agree.

GHC-boot-only; re-pins nothing. Laws QuickCheck'd in "Properties.HalfwayLatent".
-}
-- COMPARTMENT: MLX-MODEL | tag:MacTag
module SixFour.Spec.HalfwayLatent
  ( -- * The ViT waist dimensions
    vitTokens
  , vitDModel
  , halfwayLatentDim
    -- * Laws (QuickCheck'd in @Properties.HalfwayLatent@)
  , lawFuseIsMidpoint
  , lawHalfwayDimIsGeometricMean
  , lawWaistTokensAreOctantLeaves
  , lawWaistTokensMatchSynthesis
  ) where

import SixFour.Spec.JepaMemory   (latentWorkingMemoryVoxels)
import SixFour.Spec.RungPivot    (RungDir(..))
import SixFour.Spec.OctreeGenome (octreeLeafCount)
import qualified SixFour.Spec.SynthesisPolicyValue as SPV

-- | The ViT sequence length (the fused-token axis) = the depth-2 octant lattice @8² = 64@.
vitTokens :: Int
vitTokens = 64

-- | The ViT model dimension (the per-token channel width). Pinned by the spine, not chosen
-- (see 'lawFuseIsMidpoint').
vitDModel :: Int
vitDModel = 512

-- | The dimensionality of the fused latent / waist: @vitTokens · vitDModel@.
halfwayLatentDim :: Int
halfwayLatentDim = vitTokens * vitDModel

-- | KEYSTONE: the encoder FUSE (the @N × d_model@ token waist where Encoder A and Encoder B
-- combine) IS the never-surfaced @32³@ midpoint of the Down rung — the same object. The waist
-- dimensionality equals the spine's working-memory voxel count: @64 · 512 == 32768 == 32³@.
-- Teeth: this binds the ViT width (chosen from the encoder side) to @latentWorkingMemoryVoxels
-- Down@ (defined from the octant spine); a different @d_model@ falsifies it.
lawFuseIsMidpoint :: Bool
lawFuseIsMidpoint = vitTokens * vitDModel == latentWorkingMemoryVoxels Down

-- | The midpoint dimensionality is the GEOMETRIC MEAN of its two surfaced neighbours
-- (@16³@ and @64³@): @32³ = √(16³·64³)@. Squared to stay integer-exact: @(32³)² == 16³·64³@.
-- And the fused waist equals that geometric midpoint — "halfway = the halfway dimensionality".
lawHalfwayDimIsGeometricMean :: Bool
lawHalfwayDimIsGeometricMean =
  let mid = octreeLeafCount 5   -- 32³ = 8^5 = 32768
      lo  = octreeLeafCount 4   -- 16³ = 8^4 = 4096
      hi  = octreeLeafCount 6   -- 64³ = 8^6 = 262144
  in mid * mid == lo * hi
     && halfwayLatentDim == mid

-- | The token axis is the depth-2 octant lattice (@8² = 64@), not an arbitrary length —
-- so the waist is octree-structured, the channel width (not the token axis) is what is freed.
lawWaistTokensAreOctantLeaves :: Bool
lawWaistTokensAreOctantLeaves = vitTokens == octreeLeafCount 2

-- | The waist token count agrees with the policy/value synthesis @nTokens@ — the two
-- scope-outs (the ViT and the synthesis heads) describe the same 64-token waist.
lawWaistTokensMatchSynthesis :: Bool
lawWaistTokensMatchSynthesis = vitTokens == SPV.nTokens

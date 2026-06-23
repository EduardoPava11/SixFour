-- COMPARTMENT: MLX-MODEL | tag:MacTag
{- |
Module      : SixFour.Spec.JepaMemory
Description : THE I-JEPA MEMORY BUDGET, pinned as ONE tested accounting fact — the memory-preservation insurance for the DESTRUCTIVE compartment restructure. Imports the existing constants (adds ZERO new numbers) and asserts the five memory capacities the asymmetric I-JEPA design requires are CARRIED: the latent working memory (32³/128³), the 14-int relational residual unit tied to its 77-param trained carrier, the 7 detail bands, the 64-512 token capacity, and the {L,t}-carrier / {a,b,x,y}-search partition.

WHY THIS EXISTS FIRST (the destructive-pivot discipline): additive work is safe by
construction; destructive work can LOSE things. The user's constraint is that the restructure
must "carry the memory requirements to express the I-JEPA design." Three of the five budgets
are currently prose-only or split across compartments (latent CAPACITY, token CAPACITY, and
the residual-unit-vs-trained-carrier link span two walls). This module converts the budget from
"a thing to remember to preserve" into "a thing the gate refuses to let a split break": the
conservation law 'lawCarrierSearchPartition' and the no-drift law 'lawResidualIsFourteenAndCarried'
fire the moment a later destructive split drops a band, shrinks the latent, or lets the 14-int
unit and its trained head drift apart. Pin the memory, THEN destroy.

It re-exports nothing's value (only delegating laws), so it re-pins NO golden vector. It is the
cohesive MLX-MODEL memory wall the restructured I-JEPA compartment forms around.

GHC-boot-only. Laws QuickCheck'd in "Properties.JepaMemory".
-}
module SixFour.Spec.JepaMemory
  ( -- * The five I-JEPA memory budgets (derived from the existing constants)
    latentWorkingMemoryVoxels
  , detailBandsPerOctant
  , contextTokenCapacity
  , jepaTokenMin
  , jepaTokenMax
  , carrierAxes
  , searchAxes
    -- * The budget-carried laws (QuickCheck'd in @Properties.JepaMemory@)
  , lawLatentCapacityMatchesPivotCube
  , lawResidualIsFourteenAndCarried
  , lawSevenDetailBands
  , lawTokenCapacityAreOctants
  , lawCarrierSearchPartition
  ) where

import SixFour.Spec.Dim6 (Dim6(..), isUniversal)
import SixFour.Spec.RungPivot
  (RungDir(..), intermediateSide, lawIntermediateIsMidLevel, lawIntermediateNeverSurfaces)
import SixFour.Spec.RelationalResidual
  (relationalResidualLen, residualBands, searchPositionChannels
  , lawResidualIsFourteen, lawCarriersAreLandT)
import SixFour.Spec.MaskedBandPrediction
  (numBands, featureCountB, paramCountBPos)
import SixFour.Spec.OctreeGenome (octreeLeafCount)
import SixFour.Spec.JepaTarget (lawNoTargetEncoderNoEma)

-- | 1. LATENT WORKING MEMORY: the voxel capacity of the never-surfaced intermediate the head
-- computes in (the cube of the "SixFour.Spec.RungPivot" mid-level side): @Down = 32³ = 32768@,
-- @Up = 128³ = 2097152@. Today the spec pins only the SIDE; this pins the CAPACITY.
latentWorkingMemoryVoxels :: RungDir -> Int
latentWorkingMemoryVoxels d = intermediateSide d ^ (3 :: Int)

-- | 3. DETAIL-BAND MEMORY: the predictable bands a voxel carries (@liftOct@ = 1 coarse + 7
-- detail; reversibility FORCES the 7). The single source of @residualBands@ and @numBands@.
detailBandsPerOctant :: Int
detailBandsPerOctant = numBands

-- | 4. TOKEN / CONTEXT CAPACITY: the head's tokens are octants — @8^d@ leaves at cut depth @d@
-- ("SixFour.Spec.OctreeGenome" @octreeLeafCount@). 64 at @d=2@ (the @16³@ rung), 512 at @d=3@.
contextTokenCapacity :: Int -> Int
contextTokenCapacity = octreeLeafCount

-- | The minimum token capacity (the @16³@ working level, @d=2@): @8^2 = 64@.
jepaTokenMin :: Int
jepaTokenMin = octreeLeafCount 2

-- | The maximum token capacity (@d=3@): @8^3 = 512@.
jepaTokenMax :: Int
jepaTokenMax = octreeLeafCount 3

-- | 5a. The held-out CARRIER axes @{L,t}@ (count 2).
carrierAxes :: Int
carrierAxes = 2

-- | 5b. The SEARCH axes @{a,b,x,y}@ (count 4).
searchAxes :: Int
searchAxes = 4

-- ============================================================================
-- Laws (predicates; QuickCheck'd in Properties.JepaMemory)
-- ============================================================================

-- | The latent working-memory capacity is the cube of the pivot mid-level side, on BOTH rungs,
-- and the mid-level structure + never-surfaces keystone are carried. Teeth: a split that
-- shrank the latent (or surfaced it as @[Int]@) breaks the cube identity or the keystone.
lawLatentCapacityMatchesPivotCube :: Bool
lawLatentCapacityMatchesPivotCube =
     latentWorkingMemoryVoxels Down == 32768
  && latentWorkingMemoryVoxels Up   == 2097152
  && latentWorkingMemoryVoxels Down == intermediateSide Down ^ (3 :: Int)
  && latentWorkingMemoryVoxels Up   == intermediateSide Up   ^ (3 :: Int)
  && lawIntermediateIsMidLevel        -- 32*128 == 64^2 (the geometric symmetry)
  && lawIntermediateNeverSurfaces     -- the keystone keeps its teeth

-- | THE NO-DRIFT LAW: the 14-int relational residual UNIT and its 77-param trained CARRIER are
-- bound in one statement, so a destructive split cannot move them apart. @relationalResidualLen
-- == residualBands * searchPositionChannels == 14@ AND @paramCountBPos == numBands * (featureCountB
-- + searchPositionChannels) == 77@, with @residualBands == numBands@. Teeth: changing either the
-- residual budget or the head width without the other fails.
lawResidualIsFourteenAndCarried :: Bool
lawResidualIsFourteenAndCarried =
     lawResidualIsFourteen
  && relationalResidualLen == residualBands * searchPositionChannels
  && relationalResidualLen == 14
  && paramCountBPos == numBands * (featureCountB + searchPositionChannels)
  && residualBands == numBands

-- | The detail-band memory is exactly 7, and the WHOLE chain agrees:
-- @detailBandsPerOctant == residualBands == numBands@. Teeth: a split that let the octree, the
-- residual, and the trained head disagree on the band count fails.
lawSevenDetailBands :: Bool
lawSevenDetailBands =
     detailBandsPerOctant == 7
  && detailBandsPerOctant == residualBands
  && detailBandsPerOctant == numBands

-- | The token capacity is the octant leaf count (@64@ at @d=2@, @512@ at @d=3@), and the target
-- side stays zero-learnable (asymmetric I-JEPA, no EMA). Teeth: a token budget decoupled from
-- the octree, or a learned target encoder, fails.
lawTokenCapacityAreOctants :: Int -> Bool
lawTokenCapacityAreOctants d =
     contextTokenCapacity d == octreeLeafCount d
  && jepaTokenMin == 64
  && jepaTokenMax == 512
  && lawNoTargetEncoderNoEma

-- | THE CONSERVATION ALARM (run after every destructive split): the 6 axes partition into 2
-- carriers + 4 searches, @{L,t}@ are the universals, and the residual length is exactly the held
-- search-position axes @|{x,y}|=2@ times the 7 bands. (Dimension conservation @surfaced+held==input@
-- is delegated to "SixFour.Spec.Dimensions" @lawDimConserved@, tested there.) Teeth: a dropped
-- band, a mis-partitioned axis, or a lost carrier fires immediately.
lawCarrierSearchPartition :: Bool
lawCarrierSearchPartition =
     carrierAxes + searchAxes == 6
  && relationalResidualLen == searchPositionChannels * detailBandsPerOctant
  && isUniversal DimL && isUniversal DimT          -- {L,t} are the carriers
  && not (isUniversal DimA) && not (isUniversal DimX)
  && lawCarriersAreLandT

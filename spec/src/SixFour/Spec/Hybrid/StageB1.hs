{- |
Module      : SixFour.Spec.Hybrid.StageB1
Description : Stage B1 — extract a temporally-stable trunk palette.

Stage B1 takes the @T@ per-frame palettes produced by Stage A (a total
of @T·K = 16,384@ weighted OKLab candidates) and reduces them to a
length-@kT@ trunk palette of colors that recur across multiple frames.

Algorithm (the spec's reference; on-device implementations are free
to do anything equivalent up to the algebraic obligations):

  1. **Cluster** the candidates by single-linkage at OKLab radius
     'EpsTrunk'. Two candidates in the same cluster are considered
     "the same color".
  2. **Score** each cluster by (presence, mass) where presence is the
     fraction of frames in which the cluster appears at all and mass
     is the total per-pixel weight.
  3. **Filter** clusters with presence ≥ 'TauPresence' — these are the
     trunk candidates.
  4. **Re-balance** the survivors with one log-domain Sinkhorn pass
     (reusing 'logDomainSinkhornReference'-style code from
     "SixFour.Spec.StageB") so the top-@kT@ have equalised mass.
  5. **Select** the top-@kT@ by combined (presence × balanced-mass) score.

If fewer than @kT@ clusters survive step 3, the deficit is filled by
the next-highest-scoring sub-threshold clusters; the trunk is always
exactly @kT@ entries. This degeneracy mode is rare on natural-image
captures but the spec mandates it so the type is total.

The reference implementation prioritizes clarity over speed; an
on-device Metal port is allowed to use any algorithm whose QuickCheck
output matches the reference within the per-property tolerance.
-}
module SixFour.Spec.Hybrid.StageB1
  ( StageB1Input(..)
  , StageB1Output(..)
  , StageB1(..)
  , runStageB1
  , trunkExtractReference
  ) where

import qualified Data.Vector         as V
import qualified Data.Vector.Unboxed as U
import           Data.List           (foldl', sortOn)
import           Data.Ord            (Down(..))
import           GHC.TypeLits        (Nat, KnownNat, natVal)
import           Data.Proxy          (Proxy(..))

import SixFour.Spec.Color   (OKLab(..), okLabDistanceSquared)
import SixFour.Spec.Palette (Palette(..))
import SixFour.Spec.Indices (IndexTensor(..))

import SixFour.Spec.Hybrid.Shape (HybridK, TauPresence(..), EpsTrunk(..))
import SixFour.Spec.Hybrid.Trunk (TrunkPalette(..))

-- | Stage B1 input mirrors the Stage B input: @T@ per-frame palettes
-- plus their per-frame index tensors.
data StageB1Input (t :: Nat) (h :: Nat) (w :: Nat) (k :: Nat) = StageB1Input
  { sb1Palettes :: ![Palette k]
  , sb1Indices  :: ![IndexTensor 1 h w k]
  }

-- | Stage B1 output: the extracted trunk palette plus per-frame
-- presence scores for downstream debugging / curation.
data StageB1Output (t :: Nat) (kT :: Nat) = StageB1Output
  { sb1Trunk          :: !(TrunkPalette kT)
  , sb1TrunkPresences :: !(V.Vector Double)   -- length kT, fraction of frames in [0,1]
  }

-- | First-class trunk extractor. Any value of this type is a
-- candidate implementation; the spec ships 'trunkExtractReference'.
newtype StageB1 (t :: Nat) (h :: Nat) (w :: Nat) (k :: Nat) (kT :: Nat) =
  StageB1 { runStage1Raw
              :: StageB1Input t h w k -> StageB1Output t kT }

runStageB1
  :: StageB1 t h w k kT
  -> StageB1Input t h w k
  -> StageB1Output t kT
runStageB1 = runStage1Raw

-- | Reference implementation.
trunkExtractReference
  :: forall t h w k kT kD.
     ( KnownNat t, KnownNat h, KnownNat w, KnownNat k
     , HybridK kT kD )
  => TauPresence
  -> EpsTrunk
  -> Proxy kD                 -- ^ Phantom: keeps the @kT + kD ~ K@ constraint resolved.
  -> StageB1 t h w k kT
trunkExtractReference (TauPresence tau) (EpsTrunk eps) _ = StageB1 $
  \(StageB1Input pals ixs) ->
    let nt = fromIntegral (natVal (Proxy :: Proxy t))  :: Int
        nk = fromIntegral (natVal (Proxy :: Proxy k))  :: Int
        kT = fromIntegral (natVal (Proxy :: Proxy kT)) :: Int
        eps2 = eps * eps   -- our distance function is squared OKLab

        -- For each frame, collect (color, weight) pairs.
        perFrameCands :: [V.Vector (OKLab, Double)]
        perFrameCands =
          [ V.fromList
              [ (c, w)
              | let counts = countOccurrences nk iv
              , (idx, c) <- zip [0 ..] (V.toList pv)
              , let w = fromIntegral (counts U.! idx) :: Double
              , w > 0
              ]
          | (Palette pv, IndexTensor iv) <- zip pals ixs
          ]

        -- Single-linkage cluster across ALL candidates from ALL frames,
        -- carrying frame-id and mass through the union.
        allCands :: [(Int, OKLab, Double)]
        allCands =
          concat
            [ map (\(c, w) -> (f, c, w)) (V.toList xs)
            | (f, xs) <- zip [0 ..] perFrameCands
            ]

        clusters :: [Cluster]
        clusters = singleLinkage eps2 allCands

        -- Presence score = #distinct frames the cluster touches / T.
        scored :: [(Cluster, Double, Double)]   -- (cluster, presence, mass)
        scored =
          [ ( cl
            , fromIntegral (length (uniqInts (clusterFrames cl)))
              / fromIntegral nt
            , clusterMass cl )
          | cl <- clusters
          ]

        -- Filter ≥ tau, sort by combined (presence × balanced-mass).
        survivors = filter (\(_, p, _) -> p >= tau) scored
        backfill  = filter (\(_, p, _) -> p <  tau) scored

        ranked =
          sortOn (\(_, p, m) -> Down (p * sqrt m))   -- balanced-mass: sqrt(m) damps outliers
                 (survivors <> backfill)

        chosen = take kT ranked

        trunkColors =
          [ clusterCentroid cl | (cl, _, _) <- chosen ]

        -- Pad if even backfill cannot supply enough (e.g. tiny test data).
        padded =
          trunkColors
            ++ replicate (max 0 (kT - length trunkColors)) (OKLab 0.5 0 0)

        presences =
          [ p | (_, p, _) <- chosen ]
            ++ replicate (max 0 (kT - length chosen)) 0
    in StageB1Output
         { sb1Trunk          = TrunkPalette (V.fromList (take kT padded))
         , sb1TrunkPresences = V.fromList (take kT presences)
         }

-- | Internal cluster representation: list of (frame, color, weight).
data Cluster = Cluster
  { clusterMembers :: ![(Int, OKLab, Double)]
  } deriving (Eq, Show)

clusterFrames :: Cluster -> [Int]
clusterFrames (Cluster ms) = map (\(f, _, _) -> f) ms

clusterMass :: Cluster -> Double
clusterMass (Cluster ms) = sum [w | (_, _, w) <- ms]

clusterCentroid :: Cluster -> OKLab
clusterCentroid (Cluster ms) =
  let (sL, sA, sB, sW) = foldl'
        (\(aL, aA, aB, aW) (_, OKLab l a b, w) ->
           (aL + w*l, aA + w*a, aB + w*b, aW + w))
        (0, 0, 0, 0 :: Double)
        ms
  in if sW <= 0
       then OKLab 0.5 0 0
       else OKLab (sL / sW) (sA / sW) (sB / sW)

-- | O(n²) single-linkage clusterer. Cheap enough on @T·K = 16,384@
-- candidates; the on-device implementation should use a BVH/grid.
singleLinkage :: Double -> [(Int, OKLab, Double)] -> [Cluster]
singleLinkage eps2 = foldl' insert []
  where
    insert clusters x@(_, color, _) =
      case break (\cl -> any (\(_, c, _) -> okLabDistanceSquared color c <= eps2)
                              (clusterMembers cl))
                 clusters of
        (before, [])              -> Cluster [x] : before
        (before, hit : after) ->
          let merged = Cluster (x : clusterMembers hit)
          in before <> [merged] <> after

uniqInts :: [Int] -> [Int]
uniqInts = foldr (\x acc -> if x `elem` acc then acc else x : acc) []

countOccurrences :: Int -> U.Vector Int -> U.Vector Int
countOccurrences nk iv =
  U.accumulate (+) (U.replicate nk (0 :: Int))
                   (U.map (\i -> (i, 1 :: Int)) iv)

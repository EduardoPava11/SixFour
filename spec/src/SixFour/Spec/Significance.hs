{- |
Module      : SixFour.Spec.Significance
Description : Per-frame palette significance — the 'SignificantVoxelVolume'
              brand and its laws (MATH.md §10).

The per-frame palette must do two things at once:

  1. use all @K@ colours (strict per-frame surjectivity — already pinned by
     'SixFour.Spec.Indices.CompleteVoxelVolume'), and
  2. make every one of those @K@ colours /statistically significant/ — a
     palette entry backed by a real population of pixels, NOT a single
     donated outlier.

The old surjectivity rescue filled empty slots by donating the single
worst-fit pixel from a surplus slot — a slot with population 1, sitting on
a reconstruction-error extremum. That is the textbook outlier. Significance
here is therefore defined by **population**: a slot is significant iff it is
backed by at least 'minPopulation' pixels. A donated-outlier slot has count
@1 < n_min@, so it is precisely the configuration this contract forbids.
Each significant slot owns an OKLab **range** — the per-axis α-confidence box
@μ ± z_α·σ@ (see 'cellRangeBox') — derived from the covariance of its own
member population. That is the "range for each bin".

== Why this cannot fail on the SixFour shape ==

A frame has @P = H*W = 4096@ pixels and @K = 256@ slots, so
@P = 16·K ≥ minPopulation·K@ (with @n_min = 2@, @4096 ≥ 512@). Hence a
surjective partition in which /every/ slot holds @≥ n_min@ pixels always
exists, and 'splitFillFrame' constructs one. The 'Degenerate' provenance —
a slot that could not be backed — is therefore unreachable on this shape;
it exists in the type only to keep the accounting total (and honest) on a
hypothetical @P < n_min·K@ shape. See 'significanceFeasible' and
'lawSigAllSignificant'.

== Relationship to the diversity objective ==

Seeds are chosen by farthest-point (maximin) selection — the same
diversity-maximising rule as 'SixFour.Spec.Collapse.farthestPointCollapse'
and the Swift @KMeansPalettePipeline.farthestPointSeedCentroids@ — so the
significant palette also maximises gamut coverage ('lawSigMaximinVariety',
tying to 'SixFour.Spec.Coverage').
-}
-- COMPARTMENT: METAL-GPU | tag:none | STRADDLER
module SixFour.Spec.Significance
  ( -- * Codegen-pinned constants
    confidenceZ
  , minPopulation
  , chiSquare3Critical
  , significanceFeasible
    -- * Cell model
  , Provenance(..)
  , Sigma6(..)
  , Cell(..)
  , FrameCells(..)
  , zeroSigma
  , sigmaDiag
  , cellRangeBox
  , isSignificant
    -- * Statistics over a pixel population
  , accumulateCell
  , classifyCell
  , mahalanobisSquared
  , nearestCentroid
  , distinctColorCount
    -- * Producer (total on a feasible shape) and brand (validator)
  , SignificantVoxelVolume
  , svvComplete
  , svvCells
  , farthestPointSeeds
  , splitFillFrame
  , buildSignificantVolume
  , mkSignificantVoxelVolume
  , withSignificantVoxelVolume
    -- * Laws (MATH.md §10: Def 21–24, Thm 6–7, Thm 9)
  , lawSigRangeWellFormed       -- Def 21
  , lawSigMassConservation      -- Def 22
  , lawSigAllSignificant        -- Def 23 (headline: "cannot fail")
  , lawSigSignificanceIsPopulation -- Thm 7 (no-outlier ⇔ count ≥ n_min)
  , lawSigAdmissionAtMeanRejected  -- Thm 6 (χ² distinctness)
  , lawSigGaugeInvariant        -- Thm 9
  , lawSigMaximinVariety        -- Def 24
  ) where

import qualified Data.Vector as V
import qualified Data.Set    as Set
import           Data.List   (foldl')
import           Control.Monad (guard)
import           GHC.TypeLits  (Nat, KnownNat, natVal)
import           Data.Proxy    (Proxy(..))

import SixFour.Spec.Color    (OKLab(..), okLabDistanceSquared)
import SixFour.Spec.Palette  (Palette(..))
import SixFour.Spec.Indices  (IndexTensor(..), CompleteVoxelVolume
                             , mkIndexTensor, mkCompleteVoxelVolume)
import SixFour.Spec.Gauge    (Permutation, permuteVector)
import SixFour.Spec.Coverage (occupiedBins)

-- ---------------------------------------------------------------------------
-- Constants (mirrored to Swift + Python by the codegen)
-- ---------------------------------------------------------------------------

-- | Two-sided 95% normal-quantile multiplier @z_{0.975}@ for the per-axis
-- confidence range @μ ± z·σ@. Emitted to Swift/Python so all three score the
-- "range for each bin" identically.
confidenceZ :: Double
confidenceZ = 1.959963984540054

-- | Minimum pixel population for a palette slot to count as /significant/
-- (not an outlier). The whole contract turns on @P ≥ minPopulation · K@.
minPopulation :: Int
minPopulation = 2

-- | χ²₃ right-tail critical values: @P(χ²₃ > v) = α@. Single source of
-- truth for the hand-written Swift @ClusterStatisticsOps.ChiSquare3@ table,
-- so the two cannot drift. Used by the (secondary) distinctness test
-- 'mahalanobisSquared' / 'lawSigAdmissionAtMeanRejected'.
chiSquare3Critical :: Double -> Double
chiSquare3Critical a
  | a == 0.001 = 16.266
  | a == 0.01  = 11.345
  | a == 0.025 = 9.348
  | a == 0.05  = 7.815
  | a == 0.10  = 6.251
  | otherwise  = 7.815          -- safe default = α = 0.05

-- | Can a frame of @p@ pixels be partitioned into @k@ all-significant slots?
-- True iff @p ≥ minPopulation · k@. The SixFour shape (4096, 256) satisfies
-- this with a factor of 8 to spare.
significanceFeasible :: Int -> Int -> Bool
significanceFeasible p k = p >= minPopulation * k

-- ---------------------------------------------------------------------------
-- Cell model
-- ---------------------------------------------------------------------------

-- | Where a palette slot's population came from.
data Provenance
  = Extracted    -- ^ A genuine cluster mode found by the quantizer (count ≥ n_min).
  | Split        -- ^ A sub-mode created by splitting a populous cell to reach K
                 --   (count ≥ n_min). Produced by the Swift PCA fill; the
                 --   Haskell oracle reaches K by maximin seeding + rebalance.
  | Degenerate   -- ^ Could not be backed by n_min pixels. Unreachable when
                 --   'significanceFeasible' holds (i.e. on the SixFour shape).
  deriving (Eq, Show, Enum, Bounded)

-- | Upper triangle of the symmetric 3×3 OKLab covariance, in the same
-- (LL, La, Lb, aa, ab, bb) order the GPU finalize-stats pass and
-- @ClusterStatistics.Cluster@ use.
data Sigma6 = Sigma6 !Double !Double !Double !Double !Double !Double
  deriving (Eq, Show)

-- | The zero second-moment accumulator — all six 'Sigma6' entries 0 (an empty cell's stats).
zeroSigma :: Sigma6
zeroSigma = Sigma6 0 0 0 0 0 0

-- | The diagonal variances @(σ²_L, σ²_a, σ²_b)@.
sigmaDiag :: Sigma6 -> (Double, Double, Double)
sigmaDiag (Sigma6 ll _ _ aa _ bb) = (ll, aa, bb)

-- | One palette slot as a statistical /cell/: representative colour, the
-- covariance of its member pixels, its population, and where it came from.
data Cell = Cell
  { cMu    :: !OKLab
  , cSigma :: !Sigma6
  , cCount :: !Int
  , cProv  :: !Provenance
  } deriving (Eq, Show)

-- | The @K@ cells of one frame, in palette-slot order.
newtype FrameCells (k :: Nat) = FrameCells { unFrameCells :: V.Vector Cell }
  deriving (Eq, Show)

-- | Def 21 range: the per-axis α-confidence box @μ ± z·√diag(Σ)@. This is the
-- statistically-valid OKLab range the slot owns — a point box when σ = 0
-- (a sharp, certain colour), widening with the population's spread.
cellRangeBox :: Cell -> (OKLab, OKLab)   -- ^ @(lo, hi)@
cellRangeBox (Cell (OKLab l a b) sig _ _) =
  let (vL, vA, vB) = sigmaDiag sig
      half v = confidenceZ * sqrt (max 0 v)
      (dl, da, db) = (half vL, half vA, half vB)
  in (OKLab (l - dl) (a - da) (b - db), OKLab (l + dl) (a + da) (b + db))

-- | A slot is significant iff backed by @≥ minPopulation@ pixels. This is the
-- anti-outlier predicate: a donated single-pixel slot (count 1) is rejected.
isSignificant :: Cell -> Bool
isSignificant c = cCount c >= minPopulation

-- ---------------------------------------------------------------------------
-- Statistics over a pixel population
-- ---------------------------------------------------------------------------

-- | Population mean, covariance (upper triangle), and count of a pixel set.
-- Mirrors the GPU @kmeansFinalizeStats@ math (@Σ = E[xxᵀ] − μμᵀ@, population
-- normalisation by @n@).
accumulateCell :: [OKLab] -> (OKLab, Sigma6, Int)
accumulateCell [] = (OKLab 0 0 0, zeroSigma, 0)
accumulateCell ps =
  let n  = length ps
      nd = fromIntegral n :: Double
      (sL, sA, sB) =
        foldl' (\(aL, aA, aB) (OKLab l a b) -> (aL + l, aA + a, aB + b)) (0, 0, 0) ps
      (mL, mA, mB) = (sL / nd, sA / nd, sB / nd)
      (cLL, cLa, cLb, caa, cab, cbb) =
        foldl' (\(ll, la, lb, aa, ab, bb) (OKLab l a b) ->
                  let dl = l - mL; da = a - mA; db = b - mB
                  in ( ll + dl*dl, la + dl*da, lb + dl*db
                     , aa + da*da, ab + da*db, bb + db*db ))
               (0, 0, 0, 0, 0, 0) ps
  in ( OKLab mL mA mB
     , Sigma6 (cLL/nd) (cLa/nd) (cLb/nd) (caa/nd) (cab/nd) (cbb/nd)
     , n )

-- | Build a 'Cell' from its member pixels, deriving provenance from the
-- population (honest: provenance is computed, never asserted).
classifyCell :: [OKLab] -> Cell
classifyCell ms =
  let (mu, sig, n) = accumulateCell ms
      prov | n >= minPopulation = Extracted
           | otherwise          = Degenerate   -- 0 ≤ n < n_min: an outlier slot
  in Cell mu sig n prov

-- | Squared Mahalanobis distance of @x@ from @μ@ under metric @Σ@,
-- @ (x−μ)ᵀ Σ⁻¹ (x−μ) @. @+∞@ when Σ is numerically singular. Mirrors
-- @ClusterStatisticsOps.mahalanobisSquared@; the closed-form symmetric 3×3
-- inverse avoids any linear-algebra dependency.
mahalanobisSquared :: OKLab -> OKLab -> Sigma6 -> Double
mahalanobisSquared (OKLab l a b) (OKLab ml ma mb) (Sigma6 sLL sLa sLb saa sab sbb) =
  let dl = l - ml; da = a - ma; db = b - mb
      det = sLL*(saa*sbb - sab*sab)
          - sLa*(sLa*sbb - sab*sLb)
          + sLb*(sLa*sab - saa*sLb)
  in if abs det < 1e-12
       then 1 / 0
       else
         let i00 = (saa*sbb - sab*sab) / det
             i01 = (sLb*sab - sLa*sbb) / det
             i02 = (sLa*sab - sLb*saa) / det
             i11 = (sLL*sbb - sLb*sLb) / det
             i12 = (sLa*sLb - sLL*sab) / det
             i22 = (sLL*saa - sLa*sLa) / det
         in   dl*(i00*dl + i01*da + i02*db)
            + da*(i01*dl + i11*da + i12*db)
            + db*(i02*dl + i12*da + i22*db)

-- | Index of the nearest centroid by squared OKLab distance. Deterministic:
-- ties resolve to the lowest index (strict @<@). Precondition: non-empty.
nearestCentroid :: V.Vector OKLab -> OKLab -> Int
nearestCentroid cs x =
  let d0 = okLabDistanceSquared x (cs V.! 0)
      step (bi, bd) i =
        let d = okLabDistanceSquared x (cs V.! i)
        in if d < bd then (i, d) else (bi, bd)
  in fst (foldl' step (0, d0) [1 .. V.length cs - 1])

-- | Number of distinct OKLab colours in a pixel set (exact equality — the
-- frames the property tests build use replicated colours, so this is exact).
distinctColorCount :: [OKLab] -> Int
distinctColorCount = Set.size . Set.fromList . map triple
  where triple (OKLab l a b) = (l, a, b)

-- ---------------------------------------------------------------------------
-- Producer: maximin seeds → Voronoi → min-capacity rebalance
-- ---------------------------------------------------------------------------

-- | @k@ farthest-point (maximin) seed colours over the pixel cloud. First
-- seed = the pixel farthest from the cloud mean (a deterministic extreme);
-- each subsequent pick maximises the minimum distance to the chosen set.
-- When @k@ exceeds the number of distinct colours the maximin distance hits
-- zero and duplicate colours are returned — the rebalance below still backs
-- every slot. Precondition: non-empty pixel vector, @k ≥ 1@.
farthestPointSeeds :: Int -> V.Vector OKLab -> V.Vector OKLab
farthestPointSeeds k pv
  | k <= 0 || V.null pv = V.empty
  | otherwise =
      let n  = V.length pv
          nd = fromIntegral n :: Double
          (sL, sA, sB) =
            V.foldl' (\(aL, aA, aB) (OKLab l a b) -> (aL + l, aA + a, aB + b)) (0, 0, 0) pv
          mean = OKLab (sL/nd) (sA/nd) (sB/nd)
          first = fst $ V.ifoldl'
                    (\(bi, bd) i c -> let d = okLabDistanceSquared c mean
                                      in if d > bd then (i, d) else (bi, bd))
                    (0, -1) pv
          mind0 = V.map (\c -> okLabDistanceSquared c (pv V.! first)) pv
          go chosen _    | length chosen >= k = reverse chosen
          go chosen mind =
            let nextI = fst $ V.ifoldl'
                          (\(bi, bd) i d -> if d > bd then (i, d) else (bi, bd))
                          (0, -1) mind
                c     = pv V.! nextI
                mind' = V.imap (\i d -> min d (okLabDistanceSquared (pv V.! i) c)) mind
            in go (nextI : chosen) mind'
          idxs = go [first] mind0
      in V.fromList (map (pv V.!) idxs)

-- | Single-frame producer. Given @k@ and a frame's pixel colours, returns
-- @k@ cells (palette-slot order) and the length-@P@ index assignment, with
-- the guarantees: every slot used (surjective), every slot population
-- @≥ minPopulation@ when 'significanceFeasible' (so no 'Degenerate'),
-- and @Σ count = P@ (mass conservation).
--
-- Method: maximin seeds (variety) → nearest-centroid Voronoi → min-capacity
-- rebalance (move, from a surplus slot, the pixel closest to a deficient
-- slot's seed, until every slot has @≥ n_min@). Significance here is
-- population, so rebalancing is sound — it never manufactures an outlier.
splitFillFrame :: Int -> [OKLab] -> ([Cell], [Int])
splitFillFrame k pixels
  | k <= 0       = ([], [])
  | null pixels  = (replicate k (Cell (OKLab 0 0 0) zeroSigma 0 Degenerate), [])
  | otherwise    =
      let pv   = V.fromList pixels
          p    = V.length pv
          seeds = farthestPointSeeds k pv
          base  = V.generate p (\i -> nearestCentroid seeds (pv V.! i))
          idx   = rebalance k pv base
          membersOf j = [ pv V.! i | i <- [0 .. p - 1], idx V.! i == j ]
          cells = [ classifyCell (membersOf j) | j <- [0 .. k - 1] ]
      in (cells, V.toList idx)

-- | Move pixels from surplus slots into deficient slots until every slot has
-- @≥ minPopulation@ members. Each move takes, from some slot with surplus,
-- the pixel geometrically closest to the deficient slot's current mean — so
-- the moved pixel is a genuine near-member, not an outlier. Terminates when
-- 'significanceFeasible': total surplus @≥@ total deficit, and each move
-- strictly lowers the deficit without creating a new one.
rebalance :: Int -> V.Vector OKLab -> V.Vector Int -> V.Vector Int
rebalance k pv start = go start
  where
    p = V.length pv
    counts a = V.foldl' (\acc j -> acc V.// [(j, acc V.! j + 1)]) (V.replicate k 0) a
    go a =
      let cs = counts a
      in case [ j | j <- [0 .. k - 1], cs V.! j < minPopulation ] of
           []      -> a
           (j : _) ->
             let target = meanOfSlot a j
                 -- candidate donors: pixels in slots with surplus, ranked by
                 -- closeness to the deficient slot's target colour.
                 donors = [ (okLabDistanceSquared (pv V.! i) target, i)
                          | i <- [0 .. p - 1]
                          , let s = a V.! i
                          , s /= j
                          , cs V.! s > minPopulation ]
             in case donors of
                  [] -> a   -- infeasible shape (P < n_min·K): leave as-is, honestly Degenerate
                  _  -> let (_, bestI) = minimumPair donors
                        in go (a V.// [(bestI, j)])
    meanOfSlot a j =
      let ms = [ pv V.! i | i <- [0 .. p - 1], a V.! i == j ]
      in case ms of
           [] -> case farthestPointSeeds (j + 1) pv V.!? j of
                   Just c  -> c
                   Nothing -> pv V.! 0
           _  -> let (mu, _, _) = accumulateCell ms in mu
    minimumPair = foldr1 (\x y -> if fst x <= fst y then x else y)

-- ---------------------------------------------------------------------------
-- The brand: SignificantVoxelVolume
-- ---------------------------------------------------------------------------

-- | A proof that a @T×H×W@ index volume is not merely a 'CompleteVoxelVolume'
-- (every frame surjective onto @[0,K-1]@) but additionally that every palette
-- slot in every frame is /statistically significant/: backed by
-- @≥ minPopulation@ pixels, with a well-formed OKLab range, and exact mass
-- conservation. The GIF encoder/NN consume the inner 'CompleteVoxelVolume';
-- the cells travel alongside as the per-slot ranges. The constructor is
-- unexported — values cannot be forged.
data SignificantVoxelVolume (t :: Nat) (h :: Nat) (w :: Nat) (k :: Nat) =
  SignificantVoxelVolume
    { svvComplete :: !(CompleteVoxelVolume t h w k)   -- ^ the underlying complete (surjective) volume
    , svvCells    :: !(V.Vector (FrameCells k))   -- ^ length @T@, palette-slot order
    }

-- | Validate a candidate into the brand. 'Nothing' unless: the indices form a
-- 'CompleteVoxelVolume' (surjective per frame), there are exactly @T@
-- frames of @K@ cells each, every cell is significant
-- (@count ≥ minPopulation@), each cell's range box is well-formed, and per
-- frame @Σ count = H*W@. This is the unforgeable gate the encoder relies on;
-- it cannot pass a donated-outlier slot.
mkSignificantVoxelVolume
  :: forall t h w k. (KnownNat t, KnownNat h, KnownNat w, KnownNat k)
  => IndexTensor t h w k
  -> V.Vector (FrameCells k)
  -> Maybe (SignificantVoxelVolume t h w k)
mkSignificantVoxelVolume it cells = do
  cvv <- mkCompleteVoxelVolume it
  let nt       = natInt (Proxy :: Proxy t)
      nk       = natInt (Proxy :: Proxy k)
      perFrame = natInt (Proxy :: Proxy h) * natInt (Proxy :: Proxy w)
  guard (V.length cells == nt)
  guard (all (frameValid nk perFrame) (V.toList cells))
  pure (SignificantVoxelVolume cvv cells)
  where
    frameValid nk perFrame fc@(FrameCells cs) =
      V.length cs == nk
      && lawSigMassConservation perFrame fc
      && lawSigAllSignificant fc
      && all lawSigRangeWellFormed (V.toList cs)

-- | Eliminator: hand the inner pieces to a continuation.
withSignificantVoxelVolume
  :: SignificantVoxelVolume t h w k
  -> (CompleteVoxelVolume t h w k -> V.Vector (FrameCells k) -> r)
  -> r
withSignificantVoxelVolume (SignificantVoxelVolume cvv cells) f = f cvv cells

-- | Total producer (on a feasible shape): per-frame OKLab pixels →
-- 'SignificantVoxelVolume'. 'Nothing' only for a malformed shape (wrong frame
-- count / frame length) or an infeasible @P < n_min·K@ geometry. For the
-- SixFour shape (T=64, H=W=64, K=256) it always returns 'Just' — that
-- totality is 'lawSigProducerTotal'-style and is checked in the property
-- suite.
buildSignificantVolume
  :: forall t h w k. (KnownNat t, KnownNat h, KnownNat w, KnownNat k)
  => V.Vector (V.Vector OKLab)        -- ^ @T@ frames, each @H*W@ OKLab pixels
  -> Maybe (SignificantVoxelVolume t h w k)
buildSignificantVolume frames = do
  let nt       = natInt (Proxy :: Proxy t)
      nk       = natInt (Proxy :: Proxy k)
      perFrame = natInt (Proxy :: Proxy h) * natInt (Proxy :: Proxy w)
  guard (V.length frames == nt)
  guard (all ((== perFrame) . V.length) (V.toList frames))
  let results = V.map (\fr -> splitFillFrame nk (V.toList fr)) frames
      allIdx  = concatMap snd (V.toList results)
      cellsV  = V.map (FrameCells . V.fromList . fst) results
  it <- mkIndexTensor allIdx
  mkSignificantVoxelVolume it cellsV

-- | Reflect a type-level 'KnownNat' to its 'Int' value (via a 'Proxy').
natInt :: KnownNat n => Proxy n -> Int
natInt = fromIntegral . natVal

-- ---------------------------------------------------------------------------
-- Laws (MATH.md §10)
-- ---------------------------------------------------------------------------

-- | Def 21. The α-confidence range box contains its centroid component-wise
-- (and has non-negative extent, since @σ ≥ 0@).
lawSigRangeWellFormed :: Cell -> Bool
lawSigRangeWellFormed c =
  let (OKLab lL lA lB, OKLab hL hA hB) = cellRangeBox c
      OKLab mL mA mB                   = cMu c
  in lL <= mL && mL <= hL
  && lA <= mA && mA <= hA
  && lB <= mB && mB <= hB

-- | Def 22. The cells of a frame partition all @P@ pixels: @Σ count = P@.
lawSigMassConservation :: Int -> FrameCells k -> Bool
lawSigMassConservation p (FrameCells cs) =
  sum (map cCount (V.toList cs)) == p

-- | Def 23 (the headline). Every slot is significant — backed by
-- @≥ minPopulation@ pixels, so none is an outlier. This is the guarantee
-- that "cannot fail" whenever 'significanceFeasible' holds, which the
-- SixFour shape satisfies.
lawSigAllSignificant :: FrameCells k -> Bool
lawSigAllSignificant (FrameCells cs) = all isSignificant (V.toList cs)

-- | Thm 7 (no-outlier ⇔ population). Significance is exactly "population
-- @≥ n_min@". The old donation produced count-1 slots; this predicate is
-- 'False' for any such slot and 'True' for a population-backed one — the
-- formal line between split-fill and outlier donation.
lawSigSignificanceIsPopulation :: Cell -> Bool
lawSigSignificanceIsPopulation c = isSignificant c == (cCount c >= minPopulation)

-- | Thm 6 (χ² distinctness). A cell whose centroid sits exactly at the
-- population's pooled mean has Mahalanobis² @= 0@, below every χ²₃ critical
-- value, so it is /not/ admitted as a distinct colour at any level @α@.
-- (Secondary significance score; ties to the Swift χ² admission.)
lawSigAdmissionAtMeanRejected :: OKLab -> Sigma6 -> Double -> Bool
lawSigAdmissionAtMeanRejected mu sig alpha =
  mahalanobisSquared mu mu sig <= chiSquare3Critical alpha

-- | Thm 9 (@S_K@ gauge invariance). Permuting the cells of a frame by any
-- @σ ∈ S_K@ leaves the headline verdict (all-significant), the mass total,
-- and the gamut coverage of the cell means unchanged — palette-slot identity
-- is unobservable.
lawSigGaugeInvariant :: KnownNat k => Permutation k -> FrameCells k -> Bool
lawSigGaugeInvariant sigma fc@(FrameCells cs) =
  let permuted = FrameCells (permuteVector sigma cs)
  in lawSigAllSignificant fc == lawSigAllSignificant permuted
  && sum (map cCount (V.toList cs)) == sum (map cCount (V.toList (unFrameCells permuted)))
  && coverageOf fc == coverageOf permuted
  where coverageOf (FrameCells v) = occupiedBins [Palette (V.map cMu v) :: Palette k]

-- | Def 24 (maximin variety, floor). On any non-empty frame the producer's
-- significant palette occupies @≥ 1@ OKLab gamut bin — it is never collapsed
-- to nothing. Seeds are chosen by farthest-point (maximin), the same
-- diversity-maximising rule as 'SixFour.Spec.Collapse.farthestPointCollapse';
-- the property suite additionally demonstrates that on well-separated input
-- the coverage reaches @min(k, distinct bins)@ (full spread). Ties the
-- significance construction to the diversity objective
-- ('SixFour.Spec.Coverage').
lawSigMaximinVariety :: forall k. KnownNat k => Proxy k -> [OKLab] -> Bool
lawSigMaximinVariety _ pixels =
  let k            = natInt (Proxy :: Proxy k)
      (cells, _)   = splitFillFrame k pixels
      paletteMeans = Palette (V.fromList (map cMu cells)) :: Palette k
      cover        = occupiedBins [paletteMeans]
  in null pixels || (k >= 1 && cover >= 1)

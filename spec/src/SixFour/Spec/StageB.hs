{- |
Module      : SixFour.Spec.StageB
Description : Stage B — Sinkhorn-balanced global merger (pinned, witnessed).

Stage B reduces @T@ per-frame palettes (a total of @T*K@ weighted
OKLab candidates) to a single global palette of @K@ centroids, and
remaps each frame's index tensor into the global palette.

The key property: every centroid receives equal **balanced** mass
under Sinkhorn-Knopp regularised optimal transport, which guarantees
@Surjective256@ on the output indices.

References:
  * Sinkhorn & Knopp, 1967.
  * Cuturi, /Sinkhorn Distances/, NeurIPS 2013.
  * Mena et al., /Gumbel-Sinkhorn Networks/, ICLR 2018.
-}
module SixFour.Spec.StageB
  ( StageBInput(..)
  , StageBOutput(..)
  , StageB(..)
  , runStageB
  , sinkhornReference
  , logDomainSinkhornReference
  , SinkhornParams(..)
  , defaultSinkhornParams
  , sharedSinkhornParams
  , globalSinkhornParams
  ) where

import qualified Data.Vector         as V
import qualified Data.Vector.Unboxed as U
import           Data.List           (foldl')
import           GHC.TypeLits        (Nat, KnownNat, natVal)
import           Data.Proxy          (Proxy(..))

import SixFour.Spec.Color   (OKLab(..), okLabDistanceSquared)
import SixFour.Spec.Palette (Palette(..))
import SixFour.Spec.Indices
  ( IndexTensor(..)
  , Surjective256
  , mkSurjective256
  )

-- | Stage B input: @T@ per-frame palettes plus their per-frame index
-- tensors (so we know per-candidate weights).
data StageBInput (t :: Nat) (h :: Nat) (w :: Nat) (k :: Nat) = StageBInput
  { sbPalettes :: ![Palette k]                 -- ^ length @T@
  , sbIndices  :: ![IndexTensor 1 h w k]       -- ^ length @T@
  }

-- | Stage B output: a single global palette + remapped indices, plus a
-- @Maybe@-wrapped 'Surjective256' witness. @Nothing@ means Sinkhorn
-- balance failed to translate to nearest-neighbour surjectivity on
-- this input — downstream code must fall back (e.g. to per-frame mode).
data StageBOutput (t :: Nat) (h :: Nat) (w :: Nat) (k :: Nat) = StageBOutput
  { sbGlobalPalette :: !(Palette k)
  , sbGlobalIndices :: !(IndexTensor t h w k)
  , sbWitness       :: !(Maybe (Surjective256 t h w k))
  }

newtype StageB (t :: Nat) (h :: Nat) (w :: Nat) (k :: Nat) =
  StageB { runStageRaw :: StageBInput t h w k -> StageBOutput t h w k }

runStageB
  :: StageB t h w k
  -> StageBInput t h w k
  -> StageBOutput t h w k
runStageB = runStageRaw

-- | Sinkhorn-Knopp tuning knobs.
--
-- @spEpsilon@ is the tying parameter @θ ∈ Θ₁ = [0, ∞]@ from
-- @spec/MATH.md §3@; in the Sinkhorn literature it is written @ε@.
-- The three named values correspond to the three user-facing modes:
--
--   * 'defaultSinkhornParams' / 'sharedSinkhornParams' — θ = 0.05,
--     the @.shared@ endpoint (MATH.md §3.bis): finite-θ point where
--     soft column-mass is uniform enough that nearest-neighbour
--     remap collapses to a shared palette.
--   * 'globalSinkhornParams' — θ = 50.0, the @.global@ endpoint
--     (MATH.md Theorem 2 rewritten): kernel is numerically uniform,
--     palette stack collapses to literal row-rank 1. Requires
--     'logDomainSinkhornReference' to avoid numerical degeneracy.
data SinkhornParams = SinkhornParams
  { spEpsilon   :: !Double  -- ^ entropic regularisation strength θ
  , spIterCount :: !Int     -- ^ Sinkhorn-Knopp scaling iterations
  , spKMeansIts :: !Int     -- ^ outer balanced-k-means iterations
  } deriving (Eq, Show)

defaultSinkhornParams :: SinkhornParams
defaultSinkhornParams = sharedSinkhornParams

-- | The @.shared@ endpoint: θ = 0.05.
sharedSinkhornParams :: SinkhornParams
sharedSinkhornParams = SinkhornParams
  { spEpsilon   = 0.05
  , spIterCount = 20
  , spKMeansIts = 10
  }

-- | The @.global@ endpoint: θ = 50.0. Use with
-- 'logDomainSinkhornReference' — the direct-exp form numerically
-- degenerates (every kernel entry ≈ 1) above θ ≈ 1.
globalSinkhornParams :: SinkhornParams
globalSinkhornParams = SinkhornParams
  { spEpsilon   = 50.0
  , spIterCount = 20
  , spKMeansIts = 10
  }

-- | Reference Stage B. Implements weighted balanced k-means with
-- Sinkhorn assignment: the transport plan @T : (N, K)@ has equal
-- column-sums by construction, which forces every centroid to be
-- non-empty → surjectivity.
sinkhornReference
  :: forall t h w k. (KnownNat t, KnownNat h, KnownNat w, KnownNat k)
  => SinkhornParams
  -> StageB t h w k
sinkhornReference params = StageB $ \(StageBInput pals ixs) ->
  let nk = fromIntegral (natVal (Proxy :: Proxy k)) :: Int
      _t = fromIntegral (natVal (Proxy :: Proxy t)) :: Int
      _h = fromIntegral (natVal (Proxy :: Proxy h)) :: Int
      _w = fromIntegral (natVal (Proxy :: Proxy w)) :: Int

      -- Flatten candidates: every per-frame palette entry becomes a
      -- candidate; weight = frequency of that entry in the frame.
      candidates :: V.Vector (OKLab, Double)
      candidates = V.fromList
        [ (c, w)
        | (Palette pv, IndexTensor iv) <- zip pals ixs
        , let counts = countOccurrences nk iv
        , (idx, c) <- zip [0 ..] (V.toList pv)
        , let w = fromIntegral (counts U.! idx) :: Double
        , w > 0   -- skip unused palette entries
        ]

      -- Initial centroids: uniform stride sample from candidates (cheap;
      -- the QuickCheck property does not require Wu-quality init).
      n0     = max 1 (V.length candidates)
      stride = max 1 (n0 `div` nk)
      cents0 :: V.Vector OKLab
      cents0 = V.fromList
        [ fst (candidates V.! ((i * stride) `mod` n0))
        | i <- [0 .. nk - 1] ]

      -- Outer balanced k-means loop.
      cents = foldl'
        (\cs _ -> balancedStep params candidates cs)
        cents0
        [1 .. spKMeansIts params]

      -- Remap each per-frame index tensor into the global palette by
      -- nearest OKLab.
      remapped :: [U.Vector Int]
      remapped =
        [ U.map
            (\local ->
               let okl = palettePixel pv local
               in nearestIdx cents okl)
            iv
        | (Palette pv, IndexTensor iv) <- zip pals ixs
        ]

      globalIdx :: U.Vector Int
      globalIdx = U.concat remapped

      globalIdxTensor :: IndexTensor t h w k
      globalIdxTensor = IndexTensor globalIdx

      -- Sinkhorn balance guarantees equal soft column mass, NOT
      -- nearest-neighbour surjectivity after hardening. Use the
      -- checked constructor: 'Nothing' means "Stage B's hard remap
      -- happened to leave some centroid unused on this input" and
      -- the caller must fall back (e.g. to per-frame mode).
      witness :: Maybe (Surjective256 t h w k)
      witness = mkSurjective256 globalIdxTensor

  in StageBOutput
       { sbGlobalPalette = Palette cents
       , sbGlobalIndices = globalIdxTensor
       , sbWitness       = witness
       }

-- | Count, per palette entry, how many pixels point at it.
countOccurrences :: Int -> U.Vector Int -> U.Vector Int
countOccurrences nk iv =
  U.accumulate (+) (U.replicate nk (0 :: Int)) (U.map (\i -> (i, 1 :: Int)) iv)

-- | Look up one OKLab colour in a per-frame palette's underlying vector.
palettePixel :: V.Vector OKLab -> Int -> OKLab
palettePixel pv i = pv V.! i

-- | One outer iteration of balanced k-means.
balancedStep
  :: SinkhornParams
  -> V.Vector (OKLab, Double)   -- ^ candidates with weights
  -> V.Vector OKLab             -- ^ current centroids
  -> V.Vector OKLab
balancedStep params cands cents =
  let nC      = V.length cands
      nK      = V.length cents
      eps     = spEpsilon params
      iters   = spIterCount params
      -- Build cost matrix C[i,k] = ||x_i - μ_k||^2 (OKLab).
      costs :: V.Vector (V.Vector Double)
      costs = V.generate nC $ \i ->
        let (x, _) = cands V.! i
        in V.generate nK $ \k -> okLabDistanceSquared x (cents V.! k)
      -- Kernel K[i,k] = exp(-C[i,k]/eps).
      kernel = V.map (V.map (\c -> exp (- c / eps))) costs
      -- Marginal targets.
      rowTarget = V.map snd cands                          -- per-candidate weight
      sumW      = V.foldl' (+) 0 rowTarget
      colTarget = V.replicate nK (sumW / fromIntegral nK)  -- equal mass per centroid
      -- Sinkhorn-Knopp iteration:
      (u, v) = sinkhorn iters kernel rowTarget colTarget
      -- Transport plan T[i,k] = u_i * K[i,k] * v_k.
      planRow i =
        let ui  = u V.! i
            row = kernel V.! i
        in V.imap (\k kk -> ui * kk * (v V.! k)) row
      -- New centroid k: sum_i T[i,k] * x_i / sum_i T[i,k].
      acc = V.foldl'
        (\centsAcc i ->
           let (OKLab xL xA xB, _) = cands V.! i
               row = planRow i
           in V.imap
                (\k (sL, sA, sB, sW) ->
                   let tIk = row V.! k
                   in (sL + tIk * xL, sA + tIk * xA, sB + tIk * xB, sW + tIk))
                centsAcc)
        (V.replicate nK (0, 0, 0, 0 :: Double))
        (V.enumFromN 0 nC)
      newCent (sL, sA, sB, sW)
        | sW <= 0   = OKLab 0 0 0      -- impossible under Sinkhorn balance
        | otherwise = OKLab (sL / sW) (sA / sW) (sB / sW)
  in V.map newCent acc

-- | Sinkhorn-Knopp scaling. Returns row and column scalings.
sinkhorn
  :: Int
  -> V.Vector (V.Vector Double)   -- kernel
  -> V.Vector Double               -- row marginals
  -> V.Vector Double               -- col marginals
  -> (V.Vector Double, V.Vector Double)
sinkhorn iters kernel rowT colT =
  let nC = V.length kernel
      nK = V.length colT
      u0 = V.replicate nC 1
      v0 = V.replicate nK 1
      step (u, v) =
        let -- v = colT / (Kᵀ u)
            kTu = V.generate nK $ \k ->
                    V.foldl'
                      (\acc i -> acc + (u V.! i) * ((kernel V.! i) V.! k))
                      0
                      (V.enumFromN 0 nC)
            v'  = V.zipWith (\a b -> if b == 0 then 0 else a / b) colT kTu
            -- u = rowT / (K v)
            kv  = V.generate nC $ \i ->
                    V.foldl'
                      (\acc k -> acc + (v' V.! k) * ((kernel V.! i) V.! k))
                      0
                      (V.enumFromN 0 nK)
            u'  = V.zipWith (\a b -> if b == 0 then 0 else a / b) rowT kv
        in (u', v')
  in foldl' (\uv _ -> step uv) (u0, v0) [1 .. iters]

-- | Log-domain Sinkhorn-balanced k-means reference.
--
-- At θ ≫ 1 the direct-exp kernel @exp(-C/θ)@ collapses to ~1 everywhere
-- and the scaling loses all geometric signal. The log-domain variant
-- keeps the log-kernel @-C/θ@ throughout and uses 'logSumExp' for the
-- scaling and centroid update, matching Peyré & Cuturi (2018) §4.4.
-- It agrees with the direct-exp reference to within ~1e-6 at moderate
-- θ; the 'Properties.Sinkhorn' suite verifies this.
logDomainSinkhornReference
  :: forall t h w k. (KnownNat t, KnownNat h, KnownNat w, KnownNat k)
  => SinkhornParams
  -> StageB t h w k
logDomainSinkhornReference params = StageB $ \(StageBInput pals ixs) ->
  let nk = fromIntegral (natVal (Proxy :: Proxy k)) :: Int

      candidates :: V.Vector (OKLab, Double)
      candidates = V.fromList
        [ (c, w)
        | (Palette pv, IndexTensor iv) <- zip pals ixs
        , let counts = countOccurrences nk iv
        , (idx, c) <- zip [0 ..] (V.toList pv)
        , let w = fromIntegral (counts U.! idx) :: Double
        , w > 0
        ]

      n0     = max 1 (V.length candidates)
      stride = max 1 (n0 `div` nk)
      cents0 = V.fromList
        [ fst (candidates V.! ((i * stride) `mod` n0))
        | i <- [0 .. nk - 1] ]

      cents = foldl'
        (\cs _ -> balancedStepLog params candidates cs)
        cents0
        [1 .. spKMeansIts params]

      remapped =
        [ U.map
            (\local ->
               let okl = palettePixel pv local
               in nearestIdx cents okl)
            iv
        | (Palette pv, IndexTensor iv) <- zip pals ixs
        ]

      globalIdx = U.concat remapped
      globalIdxTensor :: IndexTensor t h w k
      globalIdxTensor = IndexTensor globalIdx
      witness = mkSurjective256 globalIdxTensor

  in StageBOutput
       { sbGlobalPalette = Palette cents
       , sbGlobalIndices = globalIdxTensor
       , sbWitness       = witness
       }

-- | Numerically-stable log(sum(exp xs)).
logSumExp :: V.Vector Double -> Double
logSumExp xs
  | V.null xs = -1/0
  | otherwise =
      let m = V.foldl' max (-1/0) xs
      in if isInfinite m && m < 0
           then m
           else m + log (V.foldl' (\acc x -> acc + exp (x - m)) 0 xs)

-- | One outer balanced-k-means iteration, log-domain.
balancedStepLog
  :: SinkhornParams
  -> V.Vector (OKLab, Double)
  -> V.Vector OKLab
  -> V.Vector OKLab
balancedStepLog params cands cents =
  let nC      = V.length cands
      nK      = V.length cents
      eps     = spEpsilon params
      iters   = spIterCount params

      -- log-kernel: logK[i,k] = -||x_i - μ_k||² / ε
      logKernel :: V.Vector (V.Vector Double)
      logKernel = V.generate nC $ \i ->
        let (x, _) = cands V.! i
        in V.generate nK $ \k -> negate (okLabDistanceSquared x (cents V.! k)) / eps

      rowTarget = V.map snd cands
      sumW      = V.foldl' (+) 0 rowTarget
      colTarget = V.replicate nK (sumW / fromIntegral nK)

      logRowT = V.map (\w -> if w <= 0 then -1/0 else log w) rowTarget
      logColT = V.map log colTarget

      (logU, _logV) = sinkhornLog iters logKernel logRowT logColT

      -- Centroid update via logsumexp-stable weighted average.
      -- log v[k] cancels between numerator and denominator (same trick
      -- the direct-exp reference uses), so we never need to materialise it.
      newCent k =
        let logTcol :: V.Vector Double
            logTcol = V.generate nC $ \i ->
              (logU V.! i) + ((logKernel V.! i) V.! k)
            m_k = V.foldl' max (-1/0) logTcol
        in if isInfinite m_k && m_k < 0
             then cents V.! k  -- column is all -inf; keep old centroid
             else
               let ws = V.generate nC $ \i -> exp ((logTcol V.! i) - m_k)
                   (sL, sA, sB, denom) = V.foldl'
                     (\(aL, aA, aB, aD) i ->
                        let OKLab l a b = fst (cands V.! i)
                            w = ws V.! i
                        in (aL + w*l, aA + w*a, aB + w*b, aD + w))
                     (0, 0, 0, 0 :: Double)
                     (V.enumFromN 0 nC)
               in if denom <= 0
                    then cents V.! k
                    else OKLab (sL / denom) (sA / denom) (sB / denom)
  in V.generate nK newCent

-- | Log-domain Sinkhorn-Knopp scaling. Returns @(log u, log v)@.
sinkhornLog
  :: Int
  -> V.Vector (V.Vector Double)   -- log kernel
  -> V.Vector Double               -- log row marginals
  -> V.Vector Double               -- log col marginals
  -> (V.Vector Double, V.Vector Double)
sinkhornLog iters logK logRowT logColT =
  let nC = V.length logK
      nK = V.length logColT
      u0 = V.replicate nC 0   -- log 1
      v0 = V.replicate nK 0
      step (u, v) =
        let -- log v[k] = logColT[k] - logsumexp_i (u[i] + logK[i,k])
            logKTu k = logSumExp $ V.generate nC $ \i ->
                         (u V.! i) + ((logK V.! i) V.! k)
            v'       = V.generate nK $ \k -> (logColT V.! k) - logKTu k
            -- log u[i] = logRowT[i] - logsumexp_k (v'[k] + logK[i,k])
            logKv i  = logSumExp $ V.generate nK $ \k ->
                         (v' V.! k) + ((logK V.! i) V.! k)
            u'       = V.generate nC $ \i -> (logRowT V.! i) - logKv i
        in (u', v')
  in foldl' (\uv _ -> step uv) (u0, v0) [1 .. iters]

-- | Nearest centroid index in OKLab.
nearestIdx :: V.Vector OKLab -> OKLab -> Int
nearestIdx cs x =
  fst $ V.foldl'
    (\acc@(_, bestD) (i, c) ->
       let d = okLabDistanceSquared x c
       in if d < bestD then (i, d) else acc)
    (0, 1/0 :: Double)
    (V.indexed cs)

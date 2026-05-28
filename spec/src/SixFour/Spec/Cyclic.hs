{- |
Module      : SixFour.Spec.Cyclic
Description : The cyclic palette environment and its entropy (MATH.md §8).

A looping SixFour GIF is a /cyclic/ sequence of @T@ palettes — frame
@T-1@ transitions back to frame @0@. This module views the palette stack
'SixFour.Spec.MATH §Def 4' as a process on the quotient @Z_T × S_K@
(no canonical start frame; no canonical colour order) and characterises
it through the @256@ per-colour deltas and a suite of entropy functionals.

The whole module is a /reference oracle/ in the Fahmy (2017) idiom of
@MATH.md@: it follows the statistical-modelling backbone (covariance
stationarity §9; the difference operator @ΔX_t@; the multivariate-normal
covariance of App C) and imports Shannon entropy / KL as named tools, the
same way @MATH.md@ Remark 2 already imports transport entropy.

Two design commitments (see @MATH.md §8@):

  * The transition transport plan 'transitionPlan' is entropic optimal
    transport between consecutive weighted palettes — gauge-invariant,
    mirroring the internal Sinkhorn scaling of "SixFour.Spec.StageB"
    (whose scaling helper is not exported, so a focused copy lives here).
  * Every scalar feeding 'descriptor' is invariant under the cyclic shift
    @Z_T@ and the palette gauge @S_K@. In particular the holonomy is
    measured by @K − tr(M)@ (a trace, hence conjugation- i.e.
    cyclic-shift-invariant), never a Frobenius norm.
-}
module SixFour.Spec.Cyclic
  ( -- * Types
    Weights
  , SinkhornParams(..)
  , sharedSinkhornParams
  , CyclicStack(..)
  , mkCyclicStack
  , descriptorDim
    -- * Per-frame entropy (Def 15, 16)
  , paletteEntropy
  , gaussianColorEntropy
    -- * Transitions and deltas (Def 13, 14; Thm 4)
  , costMatrix
  , transitionPlan
  , transportCost
  , transportEntropy
  , alignedDelta
  , holonomyDefect
    -- * Spectral functionals (Def 18, 19)
  , dftPower
  , spectralEntropy
  , entropyRate
    -- * The invariant descriptor (Def 20)
  , Descriptor
  , descriptor
  ) where

import qualified Data.Vector         as V
import           Data.Vector         (Vector)
import           Data.Complex        (Complex(..), magnitude)
import           Data.List           (foldl')
import           GHC.TypeLits        (Nat, KnownNat, natVal)
import           Data.Proxy          (Proxy(..))

import SixFour.Spec.Color   (OKLab(..), okLabDistanceSquared)
import SixFour.Spec.Palette (Palette(..))

-- | Per-frame population weights over the @K@ palette slots (Fahmy
-- Def 6 pmf). Normalised internally; need not sum to 1 on input.
type Weights = Vector Double

-- | Entropic-OT tuning knobs for the cyclic transition transport
-- ('transitionPlan'). @spEpsilon@ is the entropic regularisation θ
-- (smaller = sharper transport); @spIterCount@ is the Sinkhorn-Knopp
-- scaling iteration count. @spKMeansIts@ is carried for source
-- compatibility (the cyclic oracle does not run a k-means outer loop).
--
-- These used to live in the now-removed @SixFour.Spec.StageB@; the
-- cyclic descriptor (the deferred-NN feature seam) is the only
-- remaining consumer, so the record lives here.
data SinkhornParams = SinkhornParams
  { spEpsilon   :: !Double  -- ^ entropic regularisation strength θ
  , spIterCount :: !Int     -- ^ Sinkhorn-Knopp scaling iterations
  , spKMeansIts :: !Int     -- ^ retained for compatibility; unused here
  } deriving (Eq, Show)

-- | A well-conditioned default (θ = 0.05). Named for the historical
-- @.shared@ endpoint; callers tune @spEpsilon@/@spIterCount@ as needed.
sharedSinkhornParams :: SinkhornParams
sharedSinkhornParams = SinkhornParams
  { spEpsilon   = 0.05
  , spIterCount = 20
  , spKMeansIts = 10
  }

-- | A cyclic palette stack: @T@ frames, each a palette plus its weights.
-- The @t@ index lives in @Z_T@ (frame @T-1@ → frame @0@). Constructed
-- only by 'mkCyclicStack', which checks the frame count.
newtype CyclicStack (t :: Nat) (k :: Nat) =
  CyclicStack { unStack :: Vector (Palette k, Weights) }
  deriving (Eq, Show)

-- | Build a cyclic stack of exactly @T@ frames.
mkCyclicStack
  :: forall t k. KnownNat t
  => [(Palette k, Weights)] -> Maybe (CyclicStack t k)
mkCyclicStack xs =
  let nt = fromIntegral (natVal (Proxy :: Proxy t)) :: Int
      v  = V.fromList xs
  in if V.length v == nt then Just (CyclicStack v) else Nothing

-- | Dimension of the invariant 'Descriptor' (Def 20).
descriptorDim :: Int
descriptorDim = 16

-- ---------------------------------------------------------------------
-- Per-frame entropy
-- ---------------------------------------------------------------------

-- | Def 15. Shannon entropy of the palette's weight distribution,
-- @H(P_t) = −Σ_k w_k log w_k@ (natural log). @S_K@-invariant;
-- @0 ≤ H ≤ log K@.
paletteEntropy :: Weights -> Double
paletteEntropy ws =
  let s  = V.sum ws
      ps = if s <= 0 then ws else V.map (/ s) ws
  in negate $ V.foldl' (\acc p -> if p > 0 then acc + p * log p else acc) 0 ps

-- | Def 16. Differential entropy of the Gaussian fit to the weighted
-- palette colours: @H_g = ½ log((2πe)³ |Σ|)@ with @Σ@ the weighted 3×3
-- OKLab covariance (Fahmy App C eq C.8). @S_K@-invariant; @|Σ|@ is the
-- closed-form 3×3 determinant (no linear-algebra dependency).
gaussianColorEntropy :: Palette k -> Weights -> Double
gaussianColorEntropy (Palette cs) ws =
  let n   = V.length cs
      s   = V.sum ws
      ps  = if s <= 0 then V.replicate n (1 / fromIntegral (max 1 n))
                      else V.map (/ s) ws
      -- weighted mean
      (mL, mA, mB) = V.foldl'
        (\(aL, aA, aB) i ->
           let OKLab l a b = cs V.! i
               p           = ps V.! i
           in (aL + p*l, aA + p*a, aB + p*b))
        (0, 0, 0) (V.enumFromN 0 n)
      -- weighted central second moments (covariance)
      (sLL, sLa, sLb, saa, sab, sbb) = V.foldl'
        (\(cLL, cLa, cLb, caa, cab, cbb) i ->
           let OKLab l a b = cs V.! i
               p  = ps V.! i
               dL = l - mL; dA = a - mA; dB = b - mB
           in ( cLL + p*dL*dL, cLa + p*dL*dA, cLb + p*dL*dB
              , caa + p*dA*dA, cab + p*dA*dB, cbb + p*dB*dB ))
        (0, 0, 0, 0, 0, 0) (V.enumFromN 0 n)
      det = sLL*(saa*sbb - sab*sab)
          - sLa*(sLa*sbb - sab*sLb)
          + sLb*(sLa*sab - saa*sLb)
      twoPiE = 2 * pi * exp 1
  in 0.5 * log ((twoPiE ** 3) * max det 1e-12)

-- ---------------------------------------------------------------------
-- Transitions, transport and deltas
-- ---------------------------------------------------------------------

-- | OKLab squared-distance cost matrix @C[i,j] = ‖P_a[i] − P_b[j]‖²@.
costMatrix :: Palette k -> Palette k -> Vector (Vector Double)
costMatrix (Palette a) (Palette b) =
  V.generate (V.length a) $ \i ->
    V.generate (V.length b) $ \j ->
      okLabDistanceSquared (a V.! i) (b V.! j)

-- | Def 13. Entropic-OT transition plan @Γ_t@ between two weighted
-- palettes, with regularisation @θ = spEpsilon@. Mirrors the internal
-- Sinkhorn-Knopp scaling of "SixFour.Spec.StageB" (not exported there).
-- Marginals are the (normalised) weights; the plan @Γ[i,j] = u_i K_{ij} v_j@.
transitionPlan
  :: SinkhornParams
  -> Vector (Vector Double)   -- ^ cost matrix @C@
  -> Weights                  -- ^ row marginal (source weights)
  -> Weights                  -- ^ column marginal (target weights)
  -> Vector (Vector Double)
transitionPlan params cost wa wb =
  let eps    = spEpsilon params
      iters  = spIterCount params
      a      = normalise wa
      b      = normalise wb
      kernel = V.map (V.map (\c -> exp (negate c / eps))) cost
      (u, v) = sinkhornScale iters kernel a b
  in V.imap (\i row -> V.imap (\j kk -> (u V.! i) * kk * (v V.! j)) row) kernel

-- | Sinkhorn-Knopp scaling to row/col marginals; returns @(u, v)@.
-- Structural copy of @StageB.sinkhorn@ (which is module-private there).
sinkhornScale
  :: Int
  -> Vector (Vector Double)   -- kernel
  -> Vector Double            -- row marginals
  -> Vector Double            -- col marginals
  -> (Vector Double, Vector Double)
sinkhornScale iters kernel rowT colT =
  let nC = V.length kernel
      nK = V.length colT
      u0 = V.replicate nC 1
      v0 = V.replicate nK 1
      step (u, _) =
        let kTu = V.generate nK $ \k ->
                    V.foldl' (\acc i -> acc + (u V.! i) * ((kernel V.! i) V.! k)) 0
                             (V.enumFromN 0 nC)
            v'  = V.zipWith (\x y -> if y == 0 then 0 else x / y) colT kTu
            kv  = V.generate nC $ \i ->
                    V.foldl' (\acc k -> acc + (v' V.! k) * ((kernel V.! i) V.! k)) 0
                             (V.enumFromN 0 nK)
            u'  = V.zipWith (\x y -> if y == 0 then 0 else x / y) rowT kv
        in (u', v')
  in foldl' (\uv _ -> step uv) (u0, v0) [1 .. iters]

-- | Def 17. Transport cost @C_t = Σ_{i,j} Γ[i,j] · cost[i,j]@.
transportCost :: Vector (Vector Double) -> Vector (Vector Double) -> Double
transportCost plan cost =
  V.sum $ V.zipWith (\pr cr -> V.sum (V.zipWith (*) pr cr)) plan cost

-- | Def 17. Transport entropy @H(Γ_t) = −Σ Γ[i,j] log Γ[i,j]@.
transportEntropy :: Vector (Vector Double) -> Double
transportEntropy plan =
  negate $ V.foldl'
    (\acc row -> acc + V.foldl' (\a p -> if p > 0 then a + p * log p else a) 0 row)
    0 plan

-- | Def 14 (aligned special case). Cyclic first difference under the
-- identity correspondence: @Δ[t,k] = P_{t+1 mod T}[k] − P_t[k]@. Returns
-- a @T × K@ array. Used by the closedness law (Thm 4): under a consistent
-- correspondence the per-colour sum telescopes to zero around the loop.
alignedDelta
  :: forall t k. KnownNat t
  => CyclicStack t k -> Vector (Vector OKLab)
alignedDelta (CyclicStack frames) =
  let nt = V.length frames
  in V.generate nt $ \t ->
       let Palette pa = fst (frames V.! t)
           Palette pb = fst (frames V.! ((t + 1) `mod` nt))
       in V.zipWith okSub pb pa

-- | Thm 4. Holonomy defect @(K − tr(M)) / K@ where @M@ is the product of
-- the per-transition row-stochastic transport maps around the loop. Zero
-- iff the loop closes (M = I); @≥ 0@; conjugation-invariant (a trace), so
-- it does not depend on the chosen start frame — i.e. it is @Z_T@-invariant.
holonomyDefect
  :: forall t k. (KnownNat t, KnownNat k)
  => SinkhornParams -> CyclicStack t k -> Double
holonomyDefect params (CyclicStack frames) =
  let nt   = V.length frames
      nk   = fromIntegral (natVal (Proxy :: Proxy k)) :: Int
      maps = [ rowStochastic (transitionPlan params cost wa wb)
             | t <- [0 .. nt - 1]
             , let (pa, wa) = frames V.! t
                   (pb, wb) = frames V.! ((t + 1) `mod` nt)
                   cost     = costMatrix pa pb ]
      m    = foldl' matMul (identityMat nk) maps
      tr   = sum [ (m V.! i) V.! i | i <- [0 .. nk - 1] ]
  in (fromIntegral nk - tr) / fromIntegral nk

-- ---------------------------------------------------------------------
-- Spectral functionals (cyclic-aware)
-- ---------------------------------------------------------------------

-- | Power spectrum of a length-@N@ trajectory via the naive DFT.
-- @power[k] = |Σ_n x[n] e^{-2πi k n / N}|²@.
dftPower :: [Double] -> [Double]
dftPower xs =
  let n  = length xs
      nD = fromIntegral n :: Double
      bin k = let s = foldl'
                        (\acc (idx, x) ->
                           let ang = -2 * pi * fromIntegral k * fromIntegral idx / nD
                           in acc + (x :+ 0) * (cos ang :+ sin ang))
                        (0 :+ 0) (zip [0 :: Int ..] xs)
              in magnitude s ** 2
  in [ bin k | k <- [0 .. n - 1] ]

-- | Def 18. Spectral entropy over the AC bins (DC dropped): normalise the
-- power spectrum to a distribution and take its Shannon entropy. A constant
-- (still) trajectory has zero AC power and returns 0. @Z_T@-invariant
-- (cyclic shift = phase rotation, leaves power unchanged).
spectralEntropy :: [Double] -> Double
spectralEntropy xs =
  let ac  = drop 1 (dftPower xs)
      tot = sum ac
  in if tot <= 1e-12
       then 0
       else negate $ sum [ let p = a / tot in if p > 0 then p * log p else 0 | a <- ac ]

-- | Def 19. Kolmogorov–Szegő-style entropy-rate estimate from the AC
-- periodogram. Approximate; 0 on a constant trajectory.
entropyRate :: [Double] -> Double
entropyRate xs =
  let ac  = drop 1 (dftPower xs)
      tot = sum ac
      n   = fromIntegral (length ac) :: Double
  in if tot <= 1e-12 || n <= 0
       then 0
       else 0.5 * log (2 * pi * exp 1)
          + (1 / (2 * n)) * sum [ log (max a 1e-12) | a <- ac ]

-- ---------------------------------------------------------------------
-- The invariant descriptor
-- ---------------------------------------------------------------------

-- | The Def-20 invariant feature vector (length 'descriptorDim'). The NN
-- feature seam — input to the deferred categorisation estimator (Def 10).
type Descriptor = Vector Double

-- | Def 20. Assemble the @Z_T × S_K@-invariant descriptor from a cyclic
-- stack. Every component is built from @S_K@-invariant per-frame scalars
-- and @Z_T@-invariant aggregate/spectral functionals (Thm 5).
descriptor
  :: forall t k. (KnownNat t, KnownNat k)
  => SinkhornParams -> CyclicStack t k -> Descriptor
descriptor params stk@(CyclicStack frames) =
  let nt = V.length frames
      -- per-frame scalars
      hW  = [ paletteEntropy w           | (_, w) <- V.toList frames ]
      hG  = [ gaussianColorEntropy p w   | (p, w) <- V.toList frames ]
      -- per-transition scalars (cyclic: T transitions)
      transitions =
        [ (transportCost plan cost, transportEntropy plan)
        | t <- [0 .. nt - 1]
        , let (pa, wa) = frames V.! t
              (pb, wb) = frames V.! ((t + 1) `mod` nt)
              cost     = costMatrix pa pb
              plan     = transitionPlan params cost wa wb ]
      costs   = map fst transitions
      tpEnts  = map snd transitions
      acPow   = let ac = drop 1 (dftPower hW)
                    tot = sum ac
                -- finite zero list (NOT `repeat 0`) on a constant trajectory,
                -- so `length acPow` below terminates; matches the Rust oracle's
                -- `vec![0.0; ac.len()]`. A constant H(P_t) loop has no AC power.
                in if tot <= 1e-12 then map (const 0) ac else map (/ tot) ac
      coeff i = if i < length acPow then acPow !! i else 0
  in V.fromList
       [ meanL hW                 -- 0  mean palette entropy
       , sdL   hW                 -- 1  sd   palette entropy
       , meanL hG                 -- 2  mean Gaussian colour entropy
       , sdL   hG                 -- 3  sd   Gaussian colour entropy
       , sum   costs              -- 4  total cyclic transport cost
       , meanL costs              -- 5  mean transport cost
       , meanL tpEnts             -- 6  mean transport entropy
       , spectralEntropy hW       -- 7  spectral entropy of H(P_t)
       , spectralEntropy hG       -- 8  spectral entropy of H_g(P_t)
       , spectralEntropy costs    -- 9  spectral entropy of C_t
       , entropyRate hW           -- 10 entropy rate of H(P_t)
       , holonomyDefect params stk -- 11 holonomy defect (loop closure)
       , coeff 0, coeff 1, coeff 2, coeff 3  -- 12..15 AC power of H(P_t), k=1..4
       ]

-- ---------------------------------------------------------------------
-- Small local helpers
-- ---------------------------------------------------------------------

normalise :: Weights -> Weights
normalise w = let s = V.sum w in if s <= 0 then w else V.map (/ s) w

okSub :: OKLab -> OKLab -> OKLab
okSub (OKLab l1 a1 b1) (OKLab l2 a2 b2) = OKLab (l1 - l2) (a1 - a2) (b1 - b2)

-- | Row-normalise a transport plan into a row-stochastic map.
rowStochastic :: Vector (Vector Double) -> Vector (Vector Double)
rowStochastic = V.map (\row -> let s = V.sum row
                               in if s <= 0 then row else V.map (/ s) row)

identityMat :: Int -> Vector (Vector Double)
identityMat n = V.generate n $ \i -> V.generate n $ \j -> if i == j then 1 else 0

-- | Dense matrix product (small @K@; the oracle runs at test scale).
matMul :: Vector (Vector Double) -> Vector (Vector Double) -> Vector (Vector Double)
matMul a b =
  let nK = V.length b
      nJ = if nK == 0 then 0 else V.length (b V.! 0)
  in V.map (\arow ->
       V.generate nJ $ \j ->
         V.foldl' (\acc k -> acc + (arow V.! k) * ((b V.! k) V.! j)) 0 (V.enumFromN 0 nK)
     ) a

meanL :: [Double] -> Double
meanL [] = 0
meanL xs = sum xs / fromIntegral (length xs)

sdL :: [Double] -> Double
sdL [] = 0
sdL xs = let m = meanL xs
         in sqrt (meanL [ (x - m) ** 2 | x <- xs ])

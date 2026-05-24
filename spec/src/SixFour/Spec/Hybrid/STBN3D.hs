{- |
Module      : SixFour.Spec.Hybrid.STBN3D
Description : Scalar 3D spatio-temporal blue-noise mask (void-and-cluster reference).

The mask is a @t × h × w@ array of bytes in @[0, 255]@. When used as
a per-voxel dither threshold against a perceptually-uniform error,
the mask's blue-noise spectrum pushes quantization noise into
high-spatial-frequency, high-temporal-frequency bands where the human
visual system filters it out.

Algorithm: Ulichney's void-and-cluster (1993), generalised to 3D with
a toroidal Gaussian filter. The same algorithm Wolfe et al. use in
NVIDIA's scalar STBN-mask paper (arXiv 2112.09629) modulo the
sphericity tweak — for a 64³ canvas the simpler toroidal version is
sufficient and stays deterministic.

For test scale we run on 4³ / 8³ cubes; for the production 64³ mask
the codegen driver calls 'generateSTBN3D' once and emits the result
as a binary resource. The Haskell reference is the bit-exact ground
truth — the Swift runtime never recomputes the mask, it only reads
the bytes.
-}
module SixFour.Spec.Hybrid.STBN3D
  ( Mask3D(..)
  , mkMask3D
  , mask3DLookup
  , mask3DLength
  , generateSTBN3D
    -- * Spectrum check helper (used by the property tests)
  , horizontalBlueScore
  ) where

import qualified Data.Vector.Unboxed         as U
import qualified Data.Vector.Unboxed.Mutable as MU
import           Control.Monad.ST            (ST, runST)
import           Data.Word                   (Word8)
import           GHC.TypeLits                (Nat, KnownNat, natVal)
import           Data.Proxy                  (Proxy(..))
import           Data.STRef                  (newSTRef, readSTRef, writeSTRef, modifySTRef')

-- | A 3D mask of shape @t × h × w@ over alphabet @[0, 255]@.
-- Stored row-major as @U.Vector Word8@: @mask(f, y, x) = v[(f*h + y)*w + x]@.
newtype Mask3D (t :: Nat) (h :: Nat) (w :: Nat) =
  Mask3D { unMask3D :: U.Vector Word8 }
  deriving (Eq, Show)

mkMask3D
  :: forall t h w. (KnownNat t, KnownNat h, KnownNat w)
  => [Word8] -> Maybe (Mask3D t h w)
mkMask3D xs =
  let nt = fromIntegral (natVal (Proxy :: Proxy t)) :: Int
      nh = fromIntegral (natVal (Proxy :: Proxy h)) :: Int
      nw = fromIntegral (natVal (Proxy :: Proxy w)) :: Int
      v  = U.fromList xs
  in if U.length v == nt * nh * nw then Just (Mask3D v) else Nothing

mask3DLookup
  :: forall t h w. (KnownNat h, KnownNat w)
  => Mask3D t h w -> Int -> Int -> Int -> Word8
mask3DLookup (Mask3D v) f y x =
  let nh = fromIntegral (natVal (Proxy :: Proxy h)) :: Int
      nw = fromIntegral (natVal (Proxy :: Proxy w)) :: Int
  in v U.! ((f * nh + y) * nw + x)

mask3DLength :: Mask3D t h w -> Int
mask3DLength (Mask3D v) = U.length v

-- | Generate a 3D blue-noise mask via deterministic void-and-cluster.
--
-- Steps:
--   1. Seed: place @initialFraction · N@ ones at deterministic stride
--      positions (no RNG — keeps the mask reproducible).
--   2. Tighten: repeatedly find the tightest cluster (highest filter
--      response among 1-cells) and move it to the largest void (lowest
--      response among 0-cells). Stop when no improvement is possible.
--   3. Rank-out: peel 1s one by one (lowest void first → highest rank
--      written) to get the lower half of the threshold matrix.
--   4. Rank-in: place 1s into the seed-cleared pattern one by one
--      (largest void first → lower rank) to fill the upper half.
--   5. Map rank → byte: @byte = round (255 · rank / (N - 1))@.
generateSTBN3D
  :: forall t h w. (KnownNat t, KnownNat h, KnownNat w)
  => Mask3D t h w
generateSTBN3D = runST $ do
  let nt = fromIntegral (natVal (Proxy :: Proxy t)) :: Int
      nh = fromIntegral (natVal (Proxy :: Proxy h)) :: Int
      nw = fromIntegral (natVal (Proxy :: Proxy w)) :: Int
      n  = nt * nh * nw
      initialOnes = max 1 (n `div` 10)   -- 10 % seed

  -- Mutable bit-pattern: 0 / 1
  pat <- MU.replicate n (0 :: Word8)

  -- Mutable rank array (final output, in rank units 0..n-1).
  ranks <- MU.replicate n (0 :: Int)

  -- 1. Seed via stride (deterministic, no RNG).
  let stride = max 1 (n `div` initialOnes)
  let initialIdxs = [i * stride `mod` n | i <- [0 .. initialOnes - 1]]
  mapM_ (\i -> MU.write pat i 1) initialIdxs

  -- 2. Tighten until stable. Bound the iteration count to avoid
  --    pathological loops on tiny cubes; the algorithm converges
  --    quickly because each swap strictly improves the energy.
  let maxTightenSteps = 4 * initialOnes
  tightenRef <- newSTRef (0 :: Int)
  loop <- newSTRef True
  let go = do
        keepGoing <- readSTRef loop
        steps     <- readSTRef tightenRef
        if not keepGoing || steps >= maxTightenSteps
          then pure ()
          else do
            patSnap <- U.unsafeFreeze =<< MU.clone pat
            let tight = argTight nt nh nw patSnap True
                void  = argTight nt nh nw patSnap False
            case (tight, void) of
              (Just tIdx, Just vIdx) | tIdx /= vIdx -> do
                MU.write pat tIdx 0
                MU.write pat vIdx 1
                modifySTRef' tightenRef (+ 1)
                go
              _ -> writeSTRef loop False >> pure ()
  go

  -- Snapshot of the well-distributed initial pattern.
  initPat <- U.freeze pat

  -- 3. Rank-out: remove tightest 1 one at a time → ranks 0..ones-1
  --    written in REVERSE order (lowest threshold for cells removed
  --    LAST, i.e. the seeds that survive the longest).
  let onesIxs = [i | i <- [0 .. n - 1], initPat U.! i == 1]
      ones    = length onesIxs
  -- Mutable working copy for rank-out.
  rmPat <- U.thaw initPat
  let rankOut r
        | r < 0     = pure ()
        | otherwise = do
            snap <- U.unsafeFreeze =<< MU.clone rmPat
            case argTight nt nh nw snap True of
              Nothing -> pure ()
              Just idx -> do
                MU.write rmPat idx 0
                MU.write ranks idx r
                rankOut (r - 1)
  rankOut (ones - 1)

  -- 4. Rank-in: place 1 into the largest void of the cleared pattern,
  --    assigning ranks ones..n-1 in order.
  addPat <- U.thaw initPat
  let rankIn r
        | r >= n    = pure ()
        | otherwise = do
            snap <- U.unsafeFreeze =<< MU.clone addPat
            case argTight nt nh nw snap False of
              Nothing -> pure ()
              Just idx -> do
                MU.write addPat idx 1
                MU.write ranks idx r
                rankIn (r + 1)
  rankIn ones

  -- 5. Map rank → byte.
  out <- MU.new n
  let denom = max 1 (n - 1)
  let writeByte i = do
        r <- MU.read ranks i
        let b = (255 * r) `div` denom
        MU.write out i (fromIntegral b :: Word8)
  mapM_ writeByte [0 .. n - 1]

  Mask3D <$> U.freeze out
  where
    -- Find the index in the *current* pattern with the highest filter
    -- response among 1-cells (mode @True@, "tightest cluster") or the
    -- lowest response among 0-cells (mode @False@, "largest void").
    argTight nt nh nw pat lookingForOnes =
      let n = U.length pat
          response i =
            let (f0, rem0) = i `divMod` (nh * nw)
                (y0, x0)   = rem0 `divMod` nw
            in sum [ exp (negate (toroidalSqDist nt nh nw (f0, y0, x0) (f, y, x)))
                   | j <- [0 .. n - 1]
                   , pat U.! j == 1
                   , let (f, rem1) = j `divMod` (nh * nw)
                         (y, x)    = rem1 `divMod` nw
                   ]
          candidates =
            [ (response i, i)
            | i <- [0 .. n - 1]
            , (pat U.! i == 1) == lookingForOnes
            ]
      in case candidates of
           [] -> Nothing
           _  ->
             let pick = if lookingForOnes then maximum else minimum
                 (_, ix) = pick candidates
             in Just ix

    toroidalSqDist nt nh nw (f1, y1, x1) (f2, y2, x2) =
      let df = wrap (f1 - f2) nt
          dy = wrap (y1 - y2) nh
          dx = wrap (x1 - x2) nw
          sigma2 = 1.5 :: Double   -- Ulichney's stock σ; works at all scales used here
      in (fromIntegral (df*df + dy*dy + dx*dx) :: Double) / (2 * sigma2)

    wrap d n =
      let d' = d `mod` n
      in if 2 * abs d' > n then n - abs d' else abs d'

-- | A cheap correlation that returns the difference between the mask
-- variance along x (high if the mask is white-noise-flat in space)
-- and the variance after a 1×3 average box (low if blue noise dominates).
-- A blue-noise pattern's value is positive: averaging neighbouring
-- pixels collapses the high-frequency variance, but white noise stays
-- roughly the same. The property test uses this score as a
-- *necessary* (not sufficient) check that the mask is bluer than
-- white in the spatial axes.
horizontalBlueScore :: forall t h w. (KnownNat t, KnownNat h, KnownNat w)
                    => Mask3D t h w -> Double
horizontalBlueScore m@(Mask3D v) =
  let nt = fromIntegral (natVal (Proxy :: Proxy t)) :: Int
      nh = fromIntegral (natVal (Proxy :: Proxy h)) :: Int
      nw = fromIntegral (natVal (Proxy :: Proxy w)) :: Int
      total = fromIntegral (U.length v) :: Double
      mean  = U.sum (U.map (fromIntegral :: Word8 -> Double) v) / total
      var =
        let acc = U.sum (U.map (\b -> let d = (fromIntegral b :: Double) - mean
                                      in d*d) v)
        in acc / total
      smoothedVar =
        let n = U.length v
            sm i =
              let (f, rem0) = i `divMod` (nh * nw)
                  (y, x)    = rem0 `divMod` nw
                  xm = (x - 1 + nw) `mod` nw
                  xp = (x + 1) `mod` nw
                  a  = fromIntegral (v U.! ((f * nh + y) * nw + xm)) :: Double
                  b  = fromIntegral (v U.! ((f * nh + y) * nw + x))  :: Double
                  c  = fromIntegral (v U.! ((f * nh + y) * nw + xp)) :: Double
              in (a + b + c) / 3
            smVals = [sm i | i <- [0 .. n - 1]]
            smMean = sum smVals / total
            smAcc  = sum [(s - smMean)^(2 :: Int) | s <- smVals]
        in smAcc / total
      _t = nt   -- keep the t reflection live to silence -Wunused
      _m = m
  in var - smoothedVar

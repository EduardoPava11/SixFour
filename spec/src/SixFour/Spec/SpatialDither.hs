{- |
Module      : SixFour.Spec.SpatialDither
Description : Deterministic FIXED-POINT (Q16) SPATIAL dither — the bit-exact
              source of truth for the Zig @s4_dither_frame@.

NOTE: distinct from 'SixFour.Spec.Dither', which is the /temporal/ Bernoulli
dither (per-frame golden-ratio thresholds). This module is the /spatial/ dither
the app runs in the GIF path — a Q16 port of @Dither.swift@:

  * error diffusion — Floyd–Steinberg (7/3/5/1 ÷ 16) or Atkinson (6 × 1/8),
    raster or serpentine; each tap diffuses @⌊err·num/den⌋@ (truncating, so it
    is deterministic — NOT trying to match the old float path bit-for-bit);
  * ordered blue-noise — for each pixel, blend between its two nearest centroids
    by where it sits on the line between them (@s ∈ [0,1]@, Q16) versus the
    per-pixel STBN3D threshold @t = (thr+½)/256@ (exact in Q16 as
    @(2·thr+1)·128@).

Nearest-centroid ties resolve to the lowest index (strict @<@), matching
@Dither.swift@'s @d < bestD@ and the Zig kernel.
-}
-- COMPARTMENT: ZIG-FLOOR | tag:DeviceTag
module SixFour.Spec.SpatialDither
  ( DitherMode(..)
  , ditherFrameQ16
  , nearestQ16
  , nearest2Q16
  , distSqQ16
  ) where

import           Control.Monad               (forM_, when)
import           Control.Monad.ST            (runST)
import           Data.List                   (foldl')
import qualified Data.Vector.Unboxed         as U
import qualified Data.Vector.Unboxed.Mutable as MU

-- | Kernel-level dither mode. (The app's @frozen@ vs @spatiotemporal@ blue-noise
-- distinction is which mask SLICE the caller passes, not a kernel difference.)
data DitherMode = FloydSteinberg | Atkinson | BlueNoise
  deriving (Eq, Show, Enum, Bounded)

type Px = (Int, Int, Int)

-- | Squared Q16 OKLab distance (i64).
distSqQ16 :: Px -> Px -> Int
distSqQ16 (l1, a1, b1) (l2, a2, b2) =
  let dl = l1 - l2; da = a1 - a2; db = b1 - b2 in dl * dl + da * da + db * db

-- | Index of the nearest centroid; strict @<@ ⇒ lowest index on ties.
nearestQ16 :: [Px] -> Px -> Int
nearestQ16 [] _ = 0
nearestQ16 (c0 : cs) x =
  fst (foldl' step (0, distSqQ16 x c0) (zip [1 ..] cs))
  where step (bi, bd) (i, c) = let d = distSqQ16 x c in if d < bd then (i, d) else (bi, bd)

-- | The two nearest centroid indices @(i0, i1)@, @i0@ closest. @i1 == i0@ only
-- when there is a single centroid. Each chosen by strict @<@ (lowest index).
nearest2Q16 :: [Px] -> Px -> (Int, Int)
nearest2Q16 cs x =
  let i0 = nearestQ16 cs x
      cand = [ (i, c) | (i, c) <- zip [0 ..] cs, i /= i0 ]
      i1 = case cand of
             []                -> i0
             ((j0, c0) : rest) ->
               fst (foldl' (\(bi, bd) (i, c) ->
                              let d = distSqQ16 x c in if d < bd then (i, d) else (bi, bd))
                           (j0, distSqQ16 x c0) rest)
  in (i0, i1)

-- (dx, dy, num, den) taps. Floyd–Steinberg (÷16) and Atkinson (÷8).
fsTaps, atkTaps :: [(Int, Int, Int, Int)]
fsTaps  = [ (1, 0, 7, 16), (-1, 1, 3, 16), (0, 1, 5, 16), (1, 1, 1, 16) ]
atkTaps = [ (1, 0, 1, 8), (2, 0, 1, 8), (-1, 1, 1, 8), (0, 1, 1, 8), (1, 1, 1, 8), (0, 2, 1, 8) ]

-- | Dither one frame → per-pixel palette indices. @thresholds@ is used only by
-- 'BlueNoise' (one byte 0..255 per pixel); @serpentine@ only by error diffusion.
ditherFrameQ16
  :: DitherMode
  -> Int            -- ^ side (frame is side×side)
  -> Bool           -- ^ serpentine (error diffusion only)
  -> [Px]           -- ^ centroids (k of them)
  -> [Int]          -- ^ thresholds (blue-noise only), length side²
  -> [Px]           -- ^ pixels, length side²
  -> [Int]
ditherFrameQ16 BlueNoise _ _ cs thresholds pixels =
  zipWith (bluePick cs) thresholds pixels
ditherFrameQ16 mode side serpentine cs _ pixels =
  errorDiffuse side serpentine (taps mode) cs pixels
  where taps FloydSteinberg = fsTaps
        taps Atkinson       = atkTaps
        taps BlueNoise      = fsTaps   -- unreachable (handled above)

-- | One blue-noise pixel decision (Q16, exact).
bluePick :: [Px] -> Int -> Px -> Int
bluePick cs thr x@(pl, pa, pb) =
  let (i0, i1) = nearest2Q16 cs x
  in if i0 == i1 then i0
     else
       let (c0l, c0a, c0b) = cs !! i0
           (c1l, c1a, c1b) = cs !! i1
           (axl, axa, axb) = (c1l - c0l, c1a - c0a, c1b - c0b)
           denom = axl * axl + axa * axa + axb * axb
           num   = (pl - c0l) * axl + (pa - c0a) * axa + (pb - c0b) * axb
           sQ16  = if denom <= 0 then 0
                   else max 0 (min 65536 ((num * 65536) `quot` denom))
           tQ16  = (2 * thr + 1) * 128
       in if sQ16 > tQ16 then i1 else i0

-- | Sequential error diffusion in Q16, mutating a working copy in scan order
-- (raster, or serpentine where odd rows scan right→left and tap dx mirrors).
errorDiffuse :: Int -> Bool -> [(Int, Int, Int, Int)] -> [Px] -> [Px] -> [Int]
errorDiffuse side serpentine taps cs pixels = runST $ do
  let p = side * side
  bl <- U.thaw (U.fromList [ l | (l, _, _) <- pixels ])
  ba <- U.thaw (U.fromList [ a | (_, a, _) <- pixels ])
  bb <- U.thaw (U.fromList [ b | (_, _, b) <- pixels ])
  out <- MU.replicate p (0 :: Int)
  forM_ [0 .. side - 1] $ \y -> do
    let l2r = not serpentine || even y
        xs  = if l2r then [0 .. side - 1] else reverse [0 .. side - 1]
    forM_ xs $ \x -> do
      let idx = y * side + x
      hl <- MU.read bl idx; ha <- MU.read ba idx; hb <- MU.read bb idx
      let bestK = nearestQ16 cs (hl, ha, hb)
      MU.write out idx bestK
      let (cl, ca, cb) = cs !! bestK
          el = hl - cl; ea = ha - ca; eb = hb - cb
      forM_ taps $ \(dx0, dy, num, den) -> do
        let dx = if l2r then dx0 else negate dx0
            nx = x + dx; ny = y + dy
        when (nx >= 0 && nx < side && ny >= 0 && ny < side) $ do
          let nidx = ny * side + nx
          MU.modify bl (\v -> v + (el * num `quot` den)) nidx
          MU.modify ba (\v -> v + (ea * num `quot` den)) nidx
          MU.modify bb (\v -> v + (eb * num `quot` den)) nidx
  out' <- U.freeze out
  pure (U.toList out')

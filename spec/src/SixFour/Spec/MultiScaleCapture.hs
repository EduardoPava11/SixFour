{- |
Module      : SixFour.Spec.MultiScaleCapture
Description : THE INDEPENDENCE CONTRACT — the 16³/32³/64³ scales are INDEPENDENT measurements of the outside world, never derived by pooling one source. A derived pyramid (16³ = pool 64³) carries ZERO new world-information (H(coarse | fine) = 0 — it is a lens, not evidence); "The Loom" requires each scale to be its own sensor read so H(16³,32³,64³) > H(64³) and there is real cross-scale signal to fuse and to teach. The scales SHARE ONE CLOCK (64@20fps / 32@10 / 16@5 — the GIF89a centisecond cadence, @Native/palette16.zig@ s4_ladder_delay_cs) with nested, commensurate windows ('lawSharedTimeIsNested'); the independence lives one level down, in the EXPOSURE: each scale integrates a different temporal window (the fast read is short with readout dead-time; the slow read is a long continuous exposure), so the slow read exceeds the pooled fast read by EXACTLY the dead-time photons ('lawSlowMinusPoolIsDeadTime', the keystone) and cannot be reconstructed from it ('lawScalesAreNotDerivable', 'lawIndependentScalesAddInformation').

HONEST BOUNDARY — where independence comes from: spatial downsampling is DERIVABLE (an analog 4×4 bin equals the digital pool of the fine read in the noiseless model), so multi-RESOLUTION binning alone would NOT satisfy the contract. Independence is a property of the TEMPORAL integration (different exposure windows, readout dead-time) and of SATURATION (a long exposure clips a highlight the summed short frames do not) — physical, deterministic, and exactly what the exposure/cadence ladder buys. This module models the temporal source; spatial binning is the straightforward block-sum extension and is deliberately not where the independence is claimed.

TEN-BIT × 3, ABSORBED: the sensor delivers 10-bit per channel × 3 channels (0..1023 per R,G,B). The carrier accumulates the full precision exactly — no 8-bit truncation, three channels kept independent ('lawTenBitAbsorbed') — and the Zig floor's u64 block-sums have ample headroom for the widest integration ('lawCarrierWidthSuffices', the width contract the kernel must honor).

This is the keystone the current derived 'ColorHead' would FAIL (it derives 32/16 rungs from the 64-rung sums stream — the derived pyramid in code); turning the requirement into a red gate is the point.
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none
module SixFour.Spec.MultiScaleCapture
  ( -- * The 10-bit × 3 world and its shared-clock reads
    chans
  , tenBitMax
  , slowFrames
  , fastPerSlow
  , midPerSlow
  , subPerFast
  , fastFrames
  , midFrames
  , World
  , worldFromList
    -- * The three independent reads (short / medium / long exposure)
  , readFast
  , readMid
  , readSlow
  , poolFastToSlow
  , deadTime
    -- * Shared-clock window structure
  , fastSubs
  , midSubs
  , slowSubs
    -- * Laws
  , lawSharedTimeIsNested
  , lawSlowMinusPoolIsDeadTime
  , lawScalesAreNotDerivable
  , lawIndependentScalesAddInformation
  , lawTenBitAbsorbed
  , lawCarrierWidthSuffices
  ) where

-- | Colour channels: R,G,B (the "×3" of 10-bit × 3).
chans :: Int
chans = 3

-- | The 10-bit ceiling: every channel sample is in @0 .. tenBitMax@ (1023).
tenBitMax :: Integer
tenBitMax = 1023

-- | Frames in the coarse 16³ stream (5 fps cadence) in the miniature model.
slowFrames :: Int
slowFrames = 2

-- | Cadence ratio 64:16 — a slow (16³) frame spans this many fast (64³) frames.
fastPerSlow :: Int
fastPerSlow = 4

-- | Cadence ratio 32:16 — a slow frame spans this many mid (32³) frames.
midPerSlow :: Int
midPerSlow = 2

-- | Temporal sub-slices per fast frame: index 0 is the EXPOSED (ON) slice the
-- short read integrates; the rest are readout DEAD-TIME the long exposure still
-- collects. @>= 2@ is what makes the fast read short (a gap exists).
subPerFast :: Int
subPerFast = 2

-- | Frames in the fine 64³ stream (20 fps).
fastFrames :: Int
fastFrames = slowFrames * fastPerSlow

-- | Frames in the mid 32³ stream (10 fps).
midFrames :: Int
midFrames = slowFrames * midPerSlow

-- | Total sub-slices on the finest temporal grid (fast frames × sub-slices).
subslices :: Int
subslices = fastFrames * subPerFast

-- | THE WORLD: photons emitted per @channel@ (0..'chans'-1) per temporal
-- sub-slice (0..'subslices'-1). Values are 10-bit samples (0..'tenBitMax').
-- This is the outside-world ground truth the three reads independently sample.
type World = Int -> Int -> Integer

-- | Build a world from a flat @channel-major@ list (chans × subslices),
-- clamped to @0 .. tenBitMax@; short lists pad with 0. The QuickCheck ctor.
worldFromList :: [Integer] -> World
worldFromList xs ch s
  | ch < 0 || ch >= chans || s < 0 || s >= subslices = 0
  | otherwise = clamp (padded !! (ch * subslices + s))
  where
    padded = take (chans * subslices) (xs ++ repeat 0)
    clamp v = max 0 (min tenBitMax v)

-- | The sub-slices a fast (64³) frame covers: its whole @subPerFast@ window.
fastSubs :: Int -> [Int]
fastSubs f = let w0 = subPerFast * f in [w0 .. w0 + subPerFast - 1]

-- | The sub-slices a mid (32³) frame covers (2 fast slots' worth).
midSubs :: Int -> [Int]
midSubs k = let w0 = subPerFast * midPerSlow * k in [w0 .. w0 + subPerFast * midPerSlow - 1]

-- | The sub-slices a slow (16³) frame covers (4 fast slots' worth).
slowSubs :: Int -> [Int]
slowSubs j = let w0 = subPerFast * fastPerSlow * j in [w0 .. w0 + subPerFast * fastPerSlow - 1]

-- | The ON (exposed) sub-slice of fast frame @f@ — index 0 of its window.
onSub :: Int -> Int
onSub f = subPerFast * f

-- | THE SHORT read (64³, fast): each fast frame integrates only its ON slice —
-- a short exposure, so the readout dead-time is unseen.
readFast :: World -> Int -> Int -> Integer
readFast w ch f = w ch (onSub f)

-- | THE MEDIUM read (32³): a continuous integration over the mid frame's window.
readMid :: World -> Int -> Int -> Integer
readMid w ch k = sum [ w ch s | s <- midSubs k ]

-- | THE LONG read (16³, slow): a continuous integration over the whole slow
-- window — ON slices AND the dead-time gaps the fast read misses.
readSlow :: World -> Int -> Int -> Integer
readSlow w ch j = sum [ w ch s | s <- slowSubs j ]

-- | The DERIVED estimate of the slow read: pool the fast read over its window.
-- This is what the old derived pyramid computes; the laws show it is NOT the
-- slow read.
poolFastToSlow :: World -> Int -> Int -> Integer
poolFastToSlow w ch j =
  sum [ readFast w ch f | f <- [fastPerSlow * j .. fastPerSlow * j + fastPerSlow - 1] ]

-- | The dead-time photons in a slow window: the sub-slices that are NOT any
-- fast frame's ON slice (the readout gaps the short exposure could not see).
deadTime :: World -> Int -> Int -> Integer
deadTime w ch j = sum [ w ch s | s <- slowSubs j, s `mod` subPerFast /= 0 ]

allChans :: [Int]
allChans = [0 .. chans - 1]

-- | LAW (SHARED TIME AXIS): the 4:2:1 cadence is ONE clock with commensurate,
-- nested windows — every slow (16³) window is exactly the union of its 4 fast
-- (64³) windows and of its 2 mid (32³) windows. This is what makes
-- renderSelect / fusion a nested temporal lookup rather than a resample.
lawSharedTimeIsNested :: Bool
lawSharedTimeIsNested =
  and [ slowSubs j == concatMap fastSubs [fastPerSlow * j .. fastPerSlow * j + fastPerSlow - 1]
          && slowSubs j == concatMap midSubs [midPerSlow * j .. midPerSlow * j + midPerSlow - 1]
      | j <- [0 .. slowFrames - 1] ]

-- | LAW (KEYSTONE — the coarse read is NOT the pooled fine read): the long
-- exposure exceeds the pooled short exposures by EXACTLY the dead-time photons,
-- which are @>= 0@ and strictly positive whenever the world emits during a gap.
-- The difference is structural, not noise: @readSlow - poolFastToSlow == deadTime@.
lawSlowMinusPoolIsDeadTime :: [Integer] -> Bool
lawSlowMinusPoolIsDeadTime xs =
  and [ readSlow w ch j - poolFastToSlow w ch j == deadTime w ch j && deadTime w ch j >= 0
      | ch <- allChans, j <- [0 .. slowFrames - 1] ]
  where w = worldFromList xs

-- | LAW (independence realized): a world that emits during a readout gap makes
-- the slow read differ from any pooling of the fast read — the coarse scale is
-- a genuinely different measurement. (The witness photon sits in sub-slice 1,
-- a dead-time gap the fast read never integrates.)
lawScalesAreNotDerivable :: Bool
lawScalesAreNotDerivable =
  readSlow w 0 0 /= poolFastToSlow w 0 0
  where w ch s = if ch == 0 && s == 1 then 500 else 0

-- | LAW (independent scales ADD information): two worlds agreeing on every ON
-- slice give the IDENTICAL fast read yet DIFFERENT slow reads — so the fine
-- read does not determine the coarse one (H(coarse | fine) > 0). The coarse
-- scale carries world-information the fine scale provably lacks; a derived
-- pyramid could never exhibit this.
lawIndependentScalesAddInformation :: Bool
lawIndependentScalesAddInformation =
  and [ readFast w1 ch f == readFast w2 ch f | ch <- allChans, f <- [0 .. fastFrames - 1] ]
    && readSlow w1 0 0 /= readSlow w2 0 0
  where
    w1 _ _ = 0
    w2 ch s = if ch == 0 && s == 1 then 500 else 0

-- | LAW (full 10-bit × 3 absorbed): a world at the 10-bit ceiling on every
-- channel round-trips through every read as the EXACT integer sum — no
-- truncation, and the three channels stay independent. The fast read of a
-- ceiling world is exactly 'tenBitMax'; the medium/long reads are exactly the
-- integration count times 'tenBitMax'.
lawTenBitAbsorbed :: Bool
lawTenBitAbsorbed =
  and [ readFast wCeil ch f == tenBitMax | ch <- allChans, f <- [0 .. fastFrames - 1] ]
    && and [ readMid wCeil ch k == fromIntegral (subPerFast * midPerSlow) * tenBitMax
           | ch <- allChans, k <- [0 .. midFrames - 1] ]
    && and [ readSlow wCeil ch j == fromIntegral (subPerFast * fastPerSlow) * tenBitMax
           | ch <- allChans, j <- [0 .. slowFrames - 1] ]
  where wCeil _ _ = tenBitMax

-- | LAW (the carrier-width contract for Zig): the widest per-channel
-- accumulation on the real device — the coarsest 4×4 spatial bin over the full
-- 64-frame integration at the 10-bit ceiling — fits with vast headroom in the
-- u64 block-sum carrier (@Native/palette16.zig@). This is the bound the kernel
-- must honor so no 10-bit precision is lost to overflow.
lawCarrierWidthSuffices :: Bool
lawCarrierWidthSuffices = deviceMaxPerChannel < 2 ^ (63 :: Int)
  where
    coarseSpatialBin = 4 * 4 :: Int   -- the 16³ scale pools a 4×4 pixel block
    deviceFrames     = 64 :: Int      -- the full burst depth
    deviceMaxPerChannel =
      fromIntegral (coarseSpatialBin * deviceFrames) * tenBitMax

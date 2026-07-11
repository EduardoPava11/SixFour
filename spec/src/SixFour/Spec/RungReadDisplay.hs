{- |
Module      : SixFour.Spec.RungReadDisplay
Description : THE READS ON SCREEN — the exact display algebra for showing a MERGE region from ITS OWN independent read (the "SixFour.Spec.MultiScaleCapture" ladder cubes) instead of a pool of the one reconstruction. Three problems, three exact answers. TIME: a rung's owned slices are SPARSE in burst time (the weave scatters them), so the display holds CAUSALLY — 'sliceForTick' shows the LAST owned slice at or before the playhead tick, slice 0 before the first arrival ('lawOwnedTickShowsOwnSlice', 'lawHoldIsCausal'); naive @frame\/2@ indexing is exactly the bug this kills. RADIOMETRY: realizing a u64 sum slice to display bytes divides by the TRUE pixel base 'sliceRealizeCount' = fine-bin area × spatial pool × ticks-per-slice, where ticks-per-slice is 1 for a ladder cube slice ('ladderTicksPerSlice' — one owned tick each) and 'SixFour.Spec.MultiScaleCapture.fastPerSlow' = 4 for the derived c16 cube ('derivedTicksPerSlice' — ColorHead's 4-tick sums); reusing the derived multiplier on a ladder slice over-counts ×4 = a 2-stop shift, or trips the realize kernel's refusal ('lawSliceCountMatchesProvenance'). PROVENANCE: a record claims independent reads iff all three cubes are present ('independentReads'); the c16-only shape is the derived signature ('derivedSignature') and NEVER claims reads ('lawDerivedNeverClaimsReads') — pooled display stays the honest fallback. The per-display-frame sampler 'frameSample' is "SixFour.Spec.RenderSelect"'s index math restricted to ONE frame ('temporalQuantize' on the shared 4:2:1 clock, whose block sides ARE the capture cadence ratios); it is gated against the whole-volume authority by 'lawSamplerMatchesRenderSelectWhenDense', so a display-only sampler can never drift from the golden kernel @s4_render_select@. GHC-boot-only.
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none
module SixFour.Spec.RungReadDisplay
  ( -- * Causal slice lookup (owned slices are sparse in burst time)
    sliceForTick
    -- * The realize pixel base (sums → bytes divides by THIS)
  , ladderTicksPerSlice
  , derivedTicksPerSlice
  , sliceRealizeCount
    -- * Provenance (who may claim the reads)
  , independentReads
  , derivedSignature
    -- * The per-display-frame sampler (RenderSelect, one frame at a time)
  , temporalQuantize
  , frameSample
    -- * Laws
  , lawOwnedTickShowsOwnSlice
  , lawHoldIsCausal
  , lawSliceCountMatchesProvenance
  , lawTemporalQuantizeOnSharedClock
  , lawSamplerMatchesRenderSelectWhenDense
  , lawDerivedNeverClaimsReads
  ) where

import Data.List (sort)

import SixFour.Spec.CaptureRecord
  ( CaptureRecord (..), goldenRecord, goldenRecordV2 )
import SixFour.Spec.MultiScaleCapture (fastPerSlow, midPerSlow)
import SixFour.Spec.PullField (Field, regionOf)
import SixFour.Spec.RenderSelect (blockSideAt, outSide, renderSelect, volN)

-- ─────────────────────────────────────────────────────────────────────────────
-- Causal slice lookup
-- ─────────────────────────────────────────────────────────────────────────────

-- | The cube slice to SHOW at playhead tick @t@, given the rung's owned ticks
-- in ascending owned order: the index of the LAST owned tick @≤ t@ — a causal
-- hold (never show evidence from the future), holding slice 0 before the
-- first arrival (and on an empty rung, which callers gate out via
-- 'independentReads' first). Slices sit in the cube in owned order, so this
-- index IS the t-major slice index.
sliceForTick :: [Int] -> Int -> Int
sliceForTick owned t = max 0 (length (takeWhile (<= t) owned) - 1)

-- ─────────────────────────────────────────────────────────────────────────────
-- The realize pixel base
-- ─────────────────────────────────────────────────────────────────────────────

-- | Ticks summed into one LADDER cube slice: 1 — each owned frame lands as a
-- single-tick slice ('SixFour.Spec.MultiScaleIntegrate' ownership; no
-- accumulation across ticks inside a slice).
ladderTicksPerSlice :: Int
ladderTicksPerSlice = 1

-- | Ticks summed into one DERIVED c16 cube slice:
-- 'SixFour.Spec.MultiScaleCapture.fastPerSlow' = 4 — ColorHead's cube16
-- appends 4-tick temporal sums, and that ×4 is part of the slice's pixel
-- base, not of a ladder slice's.
derivedTicksPerSlice :: Int
derivedTicksPerSlice = fastPerSlow

-- | The EXACT per-bin sample count a sum slice divides by at realize:
-- @fineBinArea · (64 \/ side)² · ticksPerSlice@ — fine-bin pixels × the
-- spatial pool from the 64-lattice down to the slice's side × the temporal
-- ticks the slice summed. This is the @count@ argument of the realize kernel
-- (@s4_sums_bt2020_to_srgb8@); a wrong count is a constant stop-shift or a
-- kernel refusal. Non-positive or non-dividing sides answer 0 (totality; the
-- ladder's sides are 16\/32\/64).
sliceRealizeCount :: Int -> Int -> Int -> Int
sliceRealizeCount side fineBinArea ticksPerSlice
  | side <= 0 || fineSide `mod` side /= 0 = 0
  | otherwise = fineBinArea * q * q * ticksPerSlice
  where
    q = fineSide `div` side

-- the fine plane side (the 64-rung lattice the fine bin area is quoted on).
fineSide :: Int
fineSide = 64

-- ─────────────────────────────────────────────────────────────────────────────
-- Provenance
-- ─────────────────────────────────────────────────────────────────────────────

-- | A record may claim INDEPENDENT reads iff all three rung cubes are present
-- (ladder mode wrote c64 AND c32 AND c16). This is the data gate for
-- rendering a region from its own read.
independentReads :: CaptureRecord -> Bool
independentReads cr =
  not (null (crCube64 cr)) && not (null (crCube32 cr)) && not (null (crCube16 cr))

-- | The DERIVED provenance signature: c16 present, c64 and c32 absent — the
-- shape ColorHead's derived mode writes by construction. An all-empty (v1)
-- record is NEITHER: absent evidence is not derived provenance.
derivedSignature :: CaptureRecord -> Bool
derivedSignature cr =
  null (crCube64 cr) && null (crCube32 cr) && not (null (crCube16 cr))

-- ─────────────────────────────────────────────────────────────────────────────
-- The per-display-frame sampler
-- ─────────────────────────────────────────────────────────────────────────────

-- | Quantize a display frame @t@ to its depth-@d@ window start on the shared
-- 4:2:1 clock: @(t \`div\` b) · b@ with @b@ = 'blockSideAt' @d@ — the frame a
-- depth-@d@ region's content is constant from
-- ('SixFour.Spec.RenderSelect.lawTemporalReplicateOnSharedClock', one frame
-- at a time).
temporalQuantize :: Int -> Int -> Int
temporalQuantize d t = (t `div` b) * b
  where b = blockSideAt (min 2 (max 0 d))

-- | The per-display-frame per-region sampler: 'SixFour.Spec.RenderSelect''s
-- index math restricted to ONE frame — clamp the region's depth, quantize @t@
-- on the shared clock, read the chosen scale's own volume at
-- @(x\/b, y\/b, tq\/b)@. Implemented independently of
-- 'SixFour.Spec.RenderSelect.renderSelect' and gated against it by
-- 'lawSamplerMatchesRenderSelectWhenDense' — the cheap display path can never
-- drift from the golden kernel authority.
frameSample :: Field
            -> ((Int, Int, Int) -> Integer)   -- ^ V16 (side 2)
            -> ((Int, Int, Int) -> Integer)   -- ^ V32 (side 4)
            -> ((Int, Int, Int) -> Integer)   -- ^ V64 (side 8)
            -> Int -> (Int, Int) -> Integer
frameSample fld v16 v32 v64 t (x, y) =
  let d  = min 2 (max 0 (fld (regionOf (x, y, t))))
      b  = blockSideAt d
      tq = temporalQuantize d t
      src = case d of
              0 -> v16
              1 -> v32
              _ -> v64
  in src (x `div` b, y `div` b, tq `div` b)

-- ─────────────────────────────────────────────────────────────────────────────
-- Laws
-- ─────────────────────────────────────────────────────────────────────────────

-- strictly ascending owned ticks from arbitrary QuickCheck input.
normOwned :: [Int] -> [Int]
normOwned = dedupe . sort . map abs
  where
    dedupe (a : b : rest) | a == b    = dedupe (b : rest)
                          | otherwise = a : dedupe (b : rest)
    dedupe xs = xs

-- | An OWNED tick shows its OWN slice: at the i-th owned tick the lookup
-- answers exactly i — arrival ticks are never held over, the fresh read wins
-- the instant it lands.
lawOwnedTickShowsOwnSlice :: [Int] -> Int -> Bool
lawOwnedTickShowsOwnSlice xs iRaw =
  let o = normOwned xs
  in null o
     || (let i = abs iRaw `mod` length o
         in sliceForTick o (o !! i) == i)

-- | The hold is CAUSAL and MONOTONE: the shown slice's owned tick is the last
-- one @≤ t@ (never the future), before the first arrival the hold is slice 0,
-- the index is in range, and advancing the playhead never rewinds the slice.
lawHoldIsCausal :: [Int] -> Int -> Bool
lawHoldIsCausal xs tRaw =
  let o = normOwned xs
      t = abs tRaw
      s = sliceForTick o t
  in s >= 0
     && (null o || s <= length o - 1)
     && (case takeWhile (<= t) o of
           []  -> s == 0
           pre -> o !! s == last pre)
     && sliceForTick o t <= sliceForTick o (t + 1)

-- | THE PIXEL BASE MATCHES PROVENANCE: a ladder slice's ticks-per-slice is 1,
-- the derived c16's is 4 — at fine-bin area @a@ the ladder bases are
-- @a@ \/ @4a@ \/ @16a@ (64\/32\/16) and the derived c16 base is @64a@ — and
-- the ×4 bug is named: reusing the derived multiplier on a ladder 32-slice
-- over-counts by exactly 4 (a 2-stop shift). At the device's fine-bin area 64
-- the ladder 32-slice base is 256 and the derived c16 base is 4096.
lawSliceCountMatchesProvenance :: Int -> Bool
lawSliceCountMatchesProvenance aRaw =
  let a = 1 + abs aRaw
  in sliceRealizeCount 64 a ladderTicksPerSlice == a
     && sliceRealizeCount 32 a ladderTicksPerSlice == 4 * a
     && sliceRealizeCount 16 a ladderTicksPerSlice == 16 * a
     && sliceRealizeCount 16 a derivedTicksPerSlice == 64 * a
     && sliceRealizeCount 32 a derivedTicksPerSlice
          == 4 * sliceRealizeCount 32 a ladderTicksPerSlice
     && sliceRealizeCount 32 64 ladderTicksPerSlice == 256
     && sliceRealizeCount 16 64 derivedTicksPerSlice == 4096

-- | The quantizer rides the SHARED clock: @tq@ is a multiple of the depth's
-- block side, never ahead of @t@, within one block of it, index-equivalent to
-- @t@ under the block division — and the block sides ARE the capture cadence
-- ratios ('blockSideAt' 0\/1 = 'fastPerSlow'\/'midPerSlow': render replication
-- and capture nesting are one clock).
lawTemporalQuantizeOnSharedClock :: Int -> Int -> Bool
lawTemporalQuantizeOnSharedClock dRaw tRaw =
  let d  = abs dRaw `mod` 3
      b  = blockSideAt d
      t  = abs tRaw
      tq = temporalQuantize d t
  in tq `mod` b == 0
     && tq <= t && t < tq + b
     && tq `div` b == t `div` b
     && blockSideAt 0 == fastPerSlow
     && blockSideAt 1 == midPerSlow

-- | THE SAMPLER GATE: on dense (padded) cubes the per-frame sampler agrees
-- with 'renderSelect' — the whole-volume golden authority — at EVERY voxel of
-- the miniature cube, for any depth field. A display sampler that drifted
-- from @s4_render_select@'s index math would fail here first.
lawSamplerMatchesRenderSelectWhenDense :: [Int] -> [Integer] -> [Integer] -> [Integer] -> Bool
lawSamplerMatchesRenderSelectWhenDense fldRaw xs16 xs32 xs64 =
  and [ frameSample fld v16 v32 v64 t (x, y)
          == renderSelect fld v16 v32 v64 (x, y, t)
      | t <- [0 .. outSide - 1], y <- [0 .. outSide - 1], x <- [0 .. outSide - 1] ]
  where
    fld r = let padded = take 8 (fldRaw ++ repeat 0) in padded !! (abs r `mod` 8)
    v16 = volN 2 xs16
    v32 = volN 4 xs32
    v64 = volN 8 xs64

-- | DERIVED NEVER CLAIMS THE READS: the c16-only shape is recognized as the
-- derived signature and refused by 'independentReads'; the v2 golden (all
-- three cubes) claims reads and is not derived; the all-empty v1 golden is
-- neither (absent evidence is not derived provenance). Pooled display is the
-- honest fallback everywhere reads are not claimed.
lawDerivedNeverClaimsReads :: [Integer] -> Bool
lawDerivedNeverClaimsReads c16Extra =
  let derived = goldenRecordV2 { crCube64 = [], crCube32 = []
                               , crCube16 = 1 : c16Extra }
  in derivedSignature derived
     && not (independentReads derived)
     && independentReads goldenRecordV2
     && not (derivedSignature goldenRecordV2)
     && not (independentReads goldenRecord)
     && not (derivedSignature goldenRecord)

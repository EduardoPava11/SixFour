{- |
Module      : SixFour.Spec.AtlasCascade
Description : The two-cube cascade ExitState — QUAD-literal carry/reset for
              the 64³ → 256³ warm start.

Design §6 (@docs/COLOR-ATLAS.md@). The 64³ render pass folds per-pixel
statistics into an 'ExitState' ('deriveExit'); 'exitInit' then prepares it as
the PRIOR of the 256³ re-render — the @cascadeInit@ pattern copied from
@/Users/daniel/QUAD-Spec/src/Quad/Cascade.hs@: the MASS plane is scale-
dependent (∝ N²) and resets to zero; the dimensionless RATES carry unchanged;
the session counter increments.

Layout — 256 slots × __16 B__ = 4096 B, no pad (judge resolution §2: the
fields sum to 16 by construction, 4+6+4+2, pinned by 'lawLayoutSum4096' and
mirrored byte-for-byte in Swift):

@
  mass   u32              -- assigned-pixel count (resets)
  dL,da,db  3×i16         -- mean OKLab residual ×128, TRUNCATED div (carries)
  dx,dy     2×i16  Q8.8   -- spatial drift (carries)
  dt        1×i16  Q8.8   -- temporal occupancy drift (carries)
@

The ×128 truncated division is the QUAD \"Q15\" convention at
@/Users/daniel/QUAD-Codec/src/bias.zig:248@ — @divTrunc(sum * 128, mass)@ —
copied VERBATIM, never \"fixed\" ('lawQ15TruncDivMatchesQuad' pins golden
vectors including the toward-zero negative case). The Q8.8 means likewise
mirror bias.zig's flux: @divTrunc(sum * 256, mass)@.

The consumption side ('SixFour.Spec.Upscale256.quantizePrior') ships in the
SAME milestone — the anti-latent-carry rule all three judges demanded.
-}
-- COMPARTMENT: ZIG-FLOOR | tag:DeviceTag
module SixFour.Spec.AtlasCascade
  ( -- * Layout constants (compile-time sums)
    exitSlotCount
  , exitBytesPerSlot
  , exitStateBytes
    -- * The per-slot record
  , SlotExit(..)
  , zeroSlot
    -- * The exit state
  , ExitState(..)
  , emptyExit
    -- * Deriving it from the 64³ pass
  , PixelStat(..)
  , clampI16
  , meanRateQ15
  , meanRateQ88
  , deriveExit
    -- * The carry/reset rule
  , exitInit
    -- * Byte layout (LE, byte-pinned Haskell↔Swift)
  , encodeSlot
  , carrySlotBytes
  , encodeExit
  , carryBytes
    -- * Laws (predicates; QuickCheck'd in Properties.AtlasCascade)
  , lawLayoutSum4096
  , lawInitZeroesMassOnly
  , lawCarriedBytesIdentical
  , lawInitIdempotentOnCarry
  , lawQ15TruncDivMatchesQuad
  , lawCounterMonotone
  ) where

import           Data.Bits   (shiftR)
import           Data.Int    (Int16, Int64)
import           Data.Word   (Word8, Word32)
import qualified Data.Vector as V

-- ---------------------------------------------------------------------------
-- Layout constants
-- ---------------------------------------------------------------------------

-- | One slot per global palette leaf.
exitSlotCount :: Int
exitSlotCount = 256

-- | @mass 4 + dL,da,db 6 + dx,dy 4 + dt 2 = 16@ — no pad.
exitBytesPerSlot :: Int
exitBytesPerSlot = 4 + 6 + 4 + 2

-- | @256 × 16 = 4096@.
exitStateBytes :: Int
exitStateBytes = exitSlotCount * exitBytesPerSlot

-- ---------------------------------------------------------------------------
-- Records
-- ---------------------------------------------------------------------------

-- | One global slot's exit statistics.
data SlotExit = SlotExit
  { seMass :: Word32   -- ^ assigned-pixel count (scale-DEPENDENT — resets)
  , seDL   :: Int16    -- ^ mean L residual, ×128 truncated div (carries)
  , seDA   :: Int16    -- ^ mean a residual, ×128 truncated div (carries)
  , seDB   :: Int16    -- ^ mean b residual, ×128 truncated div (carries)
  , seDX   :: Int16    -- ^ mean spatial drift x, Q8.8 (carries)
  , seDY   :: Int16    -- ^ mean spatial drift y, Q8.8 (carries)
  , seDT   :: Int16    -- ^ mean temporal occupancy drift, Q8.8 (carries)
  } deriving (Eq, Show)

-- | All-zero slot.
zeroSlot :: SlotExit
zeroSlot = SlotExit 0 0 0 0 0 0 0

-- | The exit state: the 4096-byte slot plane plus the session counter (the
-- counter lives BESIDE the plane — the 16 B/slot sum covers the plane only).
data ExitState = ExitState
  { exitSlots   :: V.Vector SlotExit   -- ^ exactly 'exitSlotCount' slots
  , exitCounter :: Word32              -- ^ cascade session counter
  } deriving (Eq, Show)

-- | Session zero, everything empty.
emptyExit :: ExitState
emptyExit = ExitState (V.replicate exitSlotCount zeroSlot) 0

-- ---------------------------------------------------------------------------
-- Deriving from the 64³ pass
-- ---------------------------------------------------------------------------

-- | One rendered pixel's contribution: its global slot plus integer residual/
-- drift samples (the units the render fold accumulates in).
data PixelStat = PixelStat
  { psSlot :: Int   -- ^ global slot @[0, 256)@ (out-of-range stats are dropped)
  , psDL   :: Int   -- ^ OKLab L residual vs the leaf (level units)
  , psDA   :: Int   -- ^ a residual
  , psDB   :: Int   -- ^ b residual
  , psDX   :: Int   -- ^ spatial drift x
  , psDY   :: Int   -- ^ spatial drift y
  , psDT   :: Int   -- ^ temporal occupancy drift
  } deriving (Eq, Show)

-- | Saturating i16 clamp (bias.zig's @clampI16@).
clampI16 :: Int64 -> Int16
clampI16 v = fromIntegral (max (-32768) (min 32767 v))

-- | The QUAD \"Q15\" mean: @divTrunc(sum × 128, mass)@, clamped to i16.
-- TRUNCATED division (toward zero) — 'quot', never 'div' — copied verbatim
-- from @bias.zig:248@ (@dlv_q15 = @divTrunc(sum_dlv * 128, mass)@).
meanRateQ15 :: Int64 -> Int64 -> Int16
meanRateQ15 _ 0 = 0
meanRateQ15 s n = clampI16 ((s * 128) `quot` n)

-- | The Q8.8 mean: @divTrunc(sum × 256, mass)@, clamped to i16 (bias.zig's
-- flux emission).
meanRateQ88 :: Int64 -> Int64 -> Int16
meanRateQ88 _ 0 = 0
meanRateQ88 s n = clampI16 ((s * 256) `quot` n)

-- | Fold a 64³ pass's pixel statistics into an exit state (mass = count,
-- saturating at @u32@; rates = the truncated-div means above).
deriveExit :: Word32 -> [PixelStat] -> ExitState
deriveExit counter stats = ExitState (V.generate exitSlotCount slot) counter
  where
    slot j =
      let ss = [ p | p <- stats, psSlot p == j ]
          n  = fromIntegral (length ss) :: Int64
          tot f = sum [ fromIntegral (f p) :: Int64 | p <- ss ]
      in SlotExit
           { seMass = fromIntegral (min n (fromIntegral (maxBound :: Word32)))
           , seDL   = meanRateQ15 (tot psDL) n
           , seDA   = meanRateQ15 (tot psDA) n
           , seDB   = meanRateQ15 (tot psDB) n
           , seDX   = meanRateQ88 (tot psDX) n
           , seDY   = meanRateQ88 (tot psDY) n
           , seDT   = meanRateQ88 (tot psDT) n
           }

-- ---------------------------------------------------------------------------
-- The carry/reset rule
-- ---------------------------------------------------------------------------

-- | @cascadeInit@-literal: zero the mass plane (one memset, in-place safe),
-- carry every rate unchanged, increment the session counter.
exitInit :: ExitState -> ExitState
exitInit (ExitState slots c) =
  ExitState (V.map (\s -> s { seMass = 0 }) slots) (c + 1)

-- ---------------------------------------------------------------------------
-- Byte layout
-- ---------------------------------------------------------------------------

u32le :: Word32 -> [Word8]
u32le v = [ fromIntegral (v `shiftR` s) | s <- [0, 8, 16, 24] ]

i16le :: Int16 -> [Word8]
i16le v = let w = fromIntegral v :: Word32
          in [ fromIntegral w, fromIntegral (w `shiftR` 8) ]

-- | The 16-byte LE wire image of one slot:
-- @mass | dL | da | db | dx | dy | dt@.
encodeSlot :: SlotExit -> [Word8]
encodeSlot s =
  u32le (seMass s)
    ++ concatMap i16le [seDL s, seDA s, seDB s, seDX s, seDY s, seDT s]

-- | Just the CARRIED 12 bytes of a slot (everything but the mass).
carrySlotBytes :: SlotExit -> [Word8]
carrySlotBytes = drop 4 . encodeSlot

-- | The full 4096-byte slot plane.
encodeExit :: ExitState -> [Word8]
encodeExit = concatMap encodeSlot . V.toList . exitSlots

-- | The carried bytes of the whole plane (the part 'exitInit' must preserve
-- BYTE-IDENTICALLY).
carryBytes :: ExitState -> [Word8]
carryBytes = concatMap carrySlotBytes . V.toList . exitSlots

-- ---------------------------------------------------------------------------
-- Laws
-- ---------------------------------------------------------------------------

-- | The compile-time sums (16 B/slot by construction, 256 × 16 = 4096) AND
-- the encoded sizes agree with them on every state.
lawLayoutSum4096 :: ExitState -> Bool
lawLayoutSum4096 e =
  exitBytesPerSlot == 16
    && exitStateBytes == 4096
    && all ((== exitBytesPerSlot) . length . encodeSlot) (V.toList (exitSlots e))
    && length (encodeExit e) == exitStateBytes

-- | After 'exitInit' every mass is zero — and NOTHING else changed in the
-- slot plane.
lawInitZeroesMassOnly :: ExitState -> Bool
lawInitZeroesMassOnly e =
  let e' = exitInit e
  in all ((== 0) . seMass) (V.toList (exitSlots e'))
       && carryBytes e' == carryBytes e

-- | The carried 12 B/slot are byte-identical across 'exitInit' (the
-- @prop_CASCADE_haskell_zig_agree@ pattern: this list IS what Swift memcmps).
lawCarriedBytesIdentical :: ExitState -> Bool
lawCarriedBytesIdentical e = carryBytes (exitInit e) == carryBytes e

-- | 'exitInit' is idempotent ON THE PLANE: a second init changes only the
-- counter.
lawInitIdempotentOnCarry :: ExitState -> Bool
lawInitIdempotentOnCarry e =
  exitSlots (exitInit (exitInit e)) == exitSlots (exitInit e)

-- | Golden vectors for the truncated-div means — bias.zig semantics verbatim.
-- The load-bearing case is negative-toward-zero: @divTrunc(−128, 3) = −42@
-- where floor division would give −43.
lawQ15TruncDivMatchesQuad :: Bool
lawQ15TruncDivMatchesQuad =
  and
    [ meanRateQ15 5 2          == 320      -- (5·128)/2
    , meanRateQ15 (-5) 2       == -320     -- symmetric
    , meanRateQ15 1 3          == 42       -- trunc(128/3)
    , meanRateQ15 (-1) 3       == -42      -- toward ZERO (floor would be −43)
    , meanRateQ15 0 7           == 0
    , meanRateQ15 1000000 1     == 32767   -- clamps high
    , meanRateQ15 (-1000000) 1  == -32768  -- clamps low
    , meanRateQ15 9 0           == 0       -- mass 0 stays zero (bias.zig else-branch)
    , meanRateQ88 (-1) 2        == -128    -- (−1·256)/2
    , meanRateQ88 (-1) 3        == -85     -- trunc(−256/3), toward zero
    , meanRateQ88 3 4           == 192
    , meanRateQ88 5 0           == 0
    ]

-- | Each 'exitInit' advances the session counter by exactly one.
lawCounterMonotone :: ExitState -> Bool
lawCounterMonotone e = exitCounter (exitInit e) == exitCounter e + 1

{- |
Module      : SixFour.Spec.ColorFixed
Description : Deterministic FIXED-POINT (Q16) linear-sRGB → OKLab, the bit-exact
              source of truth for the Zig core's @s4_linear_to_oklab_q16@.

Where 'SixFour.Spec.Color' is a @Double@ oracle (perceptual reference, checked to
a tolerance), THIS module is the integer contract: every operation is expressible
identically in Zig (i64 products, truncating-toward-zero division 'quot' ==
@\@divTrunc@, an exact integer floor cube root), so the Haskell golden and the
Zig kernel agree BYTE-FOR-BYTE — that is what makes the GIF deterministic across
devices (the GPU's float @cbrt@ is the non-determinism we are removing).

== Q16
OKLab and linear-sRGB are carried as @i32@ in Q16 (scale 2^16): the real value
@v@ is the integer @round(v * 65536)@. Matches the production Metal scale.

== cbrt without floats
@cbrt(x)@ in Q16 is @icbrtQ16 x = floor((x \<\< 32) ** (1/3))@ — an exact integer
floor cube root (binary search). No Newton iteration, no convergence tolerance,
no libm: trivially identical in Haskell 'Int' (64-bit) and Zig 'i64'.

Constants below are the Ottosson M1/M2 matrices rounded to Q16; the SAME integer
literals are hard-coded in @Native/src/kernels.zig@. Do not "simplify" either copy
independently.
-}
module SixFour.Spec.ColorFixed
  ( q16One
  , icbrtQ16
  , linearToOklabQ16
    -- * inverse path (OKLab → sRGB8) + the shared gamma LUT
  , oklabToSrgb8Q16
  , gammaLut
    -- * exposed for the cross-language golden emitter
  , goldenLinearInputsQ16
  ) where

import           Data.Bits           (shiftL)
import           Data.Word           (Word8)
import qualified Data.Vector.Unboxed as U

import SixFour.Spec.Color (linearToSRGB)

-- | Q16 unit: @1.0@ encoded.
q16One :: Int
q16One = 65536

-- M1 (linear sRGB → LMS), Q16, row-major. round(coeff * 65536).
m1_00, m1_01, m1_02, m1_10, m1_11, m1_12, m1_20, m1_21, m1_22 :: Int
m1_00 = 27015; m1_01 = 35149; m1_02 = 3372
m1_10 = 13887; m1_11 = 44610; m1_12 = 7038
m1_20 = 5787;  m1_21 = 18463; m1_22 = 41286

-- M2 (LMS' → OKLab), Q16, row-major.
m2_00, m2_01, m2_02, m2_10, m2_11, m2_12, m2_20, m2_21, m2_22 :: Int
m2_00 = 13792;  m2_01 = 52011;   m2_02 = -267
m2_10 = 129630; m2_11 = -159160; m2_12 = 29530
m2_20 = 1698;   m2_21 = 51300;   m2_22 = -52997

-- | Exact integer floor cube root in Q16: returns @floor(cbrt(x/2^16) * 2^16)@.
--
-- Derivation: want @Y@ with @(Y/2^16)^3 = x/2^16@, i.e. @Y^3 = x * 2^32@, so
-- @Y = floor((x \<\< 32) ** (1/3))@. Found by binary search; @x@ is clamped to
-- @[0, 131072]@ (linear ≤ 2.0) so @x \<\< 32 ≤ 2^49@ and every @mid^3 ≤ 2^51@
-- stays inside @i64@ — the SAME bound the Zig port uses (ReleaseSafe traps on
-- overflow, so the bound is load-bearing, not cosmetic).
icbrtQ16 :: Int -> Int
icbrtQ16 x0
  | x <= 0    = 0
  | otherwise = go 0 (1 `shiftL` 17)
  where
    x = min 131072 x0
    n = x `shiftL` 32
    go lo hi
      | lo >= hi  = lo
      | otherwise =
          let mid = (lo + hi + 1) `quot` 2
          in if mid * mid * mid <= n then go mid hi else go lo (mid - 1)

-- | Q16 linear-sRGB triple → Q16 OKLab triple. Integer-only; truncating division.
linearToOklabQ16 :: (Int, Int, Int) -> (Int, Int, Int)
linearToOklabQ16 (r0, g0, b0) =
  let r = max 0 r0
      g = max 0 g0
      b = max 0 b0
      l = clampPos ((m1_00 * r + m1_01 * g + m1_02 * b) `quot` q16One)
      m = clampPos ((m1_10 * r + m1_11 * g + m1_12 * b) `quot` q16One)
      s = clampPos ((m1_20 * r + m1_21 * g + m1_22 * b) `quot` q16One)
      lc = icbrtQ16 l
      mc = icbrtQ16 m
      sc = icbrtQ16 s
      bigL = (m2_00 * lc + m2_01 * mc + m2_02 * sc) `quot` q16One
      aOut = (m2_10 * lc + m2_11 * mc + m2_12 * sc) `quot` q16One
      bOut = (m2_20 * lc + m2_21 * mc + m2_22 * sc) `quot` q16One
  in (bigL, aOut, bOut)
  where clampPos v = min 131072 (max 0 v)

-- M2⁻¹ (OKLab → l'm's'): the a,b coefficients added to L, Q16.
m2i_la, m2i_lb, m2i_ma, m2i_mb, m2i_sa, m2i_sb :: Int
m2i_la = 25974;  m2i_lb = 14143
m2i_ma = -6918;  m2i_mb = -4185
m2i_sa = -5864;  m2i_sb = -84639

-- M1⁻¹ (LMS → linear sRGB), Q16, row-major.
m1i_00, m1i_01, m1i_02, m1i_10, m1i_11, m1i_12, m1i_20, m1i_21, m1i_22 :: Int
m1i_00 = 267173; m1i_01 = -216774; m1i_02 = 15137
m1i_10 = -83128; m1i_11 = 171033;  m1i_12 = -22369
m1i_20 = -275;   m1i_21 = -46099;  m1i_22 = 111910

-- | The shared inverse-gamma lookup table: index @i ∈ [0, 65536]@ is a Q16
-- linear-sRGB channel; the entry is @round(255 · linearToSRGB(i/65536))@. The
-- Zig core @\@embedFile@s the byte-identical table (gamma_lut.bin), so the
-- transcendental @x^(1/2.4)@ is evaluated ONCE here and never at runtime — the
-- palette sRGB conversion is then a pure table lookup, deterministic on every
-- device. 65537 entries (one per Q16 linear level, inclusive of 1.0).
gammaLut :: U.Vector Word8
gammaLut = U.generate 65537 entry
  where
    entry i =
      let lin  = fromIntegral i / 65536 :: Double
          srgb = linearToSRGB lin
          v    = round (clamp01 srgb * 255) :: Int
      in fromIntegral (max 0 (min 255 v))
    clamp01 x = max 0 (min 1 x)

-- | Q16 OKLab triple → sRGB8 triple in @[0,255]@. Integer-only (M2⁻¹ matmul,
-- exact integer cube, M1⁻¹ matmul, clamp) then a 'gammaLut' lookup. Mirrors the
-- Zig @s4_palette_oklab_to_srgb8@ byte-for-byte.
oklabToSrgb8Q16 :: (Int, Int, Int) -> (Int, Int, Int)
oklabToSrgb8Q16 (bigL, a, b) =
  let l_ = (q16One * bigL + m2i_la * a + m2i_lb * b) `quot` q16One
      m_ = (q16One * bigL + m2i_ma * a + m2i_mb * b) `quot` q16One
      s_ = (q16One * bigL + m2i_sa * a + m2i_sb * b) `quot` q16One
      l  = cubeQ16 l_
      m  = cubeQ16 m_
      s  = cubeQ16 s_
      r  = (m1i_00 * l + m1i_01 * m + m1i_02 * s) `quot` q16One
      g  = (m1i_10 * l + m1i_11 * m + m1i_12 * s) `quot` q16One
      bl = (m1i_20 * l + m1i_21 * m + m1i_22 * s) `quot` q16One
  in (gammaByte r, gammaByte g, gammaByte bl)
  where
    -- (v/2^16)^3 in Q16 = v^3 / 2^32, truncating toward zero (sign-correct).
    cubeQ16 v = (v * v * v) `quot` 4294967296
    gammaByte lin = fromIntegral (gammaLut U.! clampIdx lin)
    clampIdx v = max 0 (min 65536 v)

-- | A deterministic, structured set of Q16 linear-sRGB inputs for the
-- cross-language golden: corners (black/white/primaries/secondaries), the grey
-- ramp, and a deterministic pseudo-random spread (an LCG, so Haskell and any
-- consumer regenerate the identical list). Used by @app/Fixtures.hs@.
goldenLinearInputsQ16 :: [(Int, Int, Int)]
goldenLinearInputsQ16 = corners ++ greys ++ randoms
  where
    full = q16One
    corners =
      [ (0,0,0), (full,full,full)
      , (full,0,0), (0,full,0), (0,0,full)
      , (full,full,0), (full,0,full), (0,full,full) ]
    greys = [ (v,v,v) | i <- [1..14 :: Int], let v = (i * full) `quot` 15 ]
    randoms = take 42 (lcg 0x6d2b79f5)
    -- A tiny LCG producing Q16 values in [0, full]; channels from successive draws.
    lcg seed =
      let s1 = step seed
          s2 = step s1
          s3 = step s2
          q v = v `mod` (full + 1)
      in (q s1, q s2, q s3) : lcg s3
    step s = (s * 1103515245 + 12345) `mod` 2147483648

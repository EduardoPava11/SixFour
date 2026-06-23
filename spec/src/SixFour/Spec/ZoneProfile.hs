{- |
Module      : SixFour.Spec.ZoneProfile
Description : The look's LUMINANCE-ZONE chroma profile — the data-driven source of
              a look, extracted from a captured 256-colour OKLab palette.

A "look" in SixFour is /not/ a canned recipe: it is derived from the captured
palette's own colour statistics. This module is the analysis half (the python
@analyze_gif_palette@ in @~/lut-generator/src/python/gif_palette_lut.py@, ported
to OKLab + Q16): bucket the palette by lightness @L@ into 'zpNumZones' uniform
zones over @[0, q16One]@ and record, per zone, the mean @a@, mean @b@, and mean
chroma. 'SixFour.Spec.LookTransfer' then uses 'sampleZoneTargetQ16' to pull an
input colour's chrominance toward the zone target at its lightness.

== Why OKLab, not CIELAB
The python analyses in CIELAB (@L* ∈ [0,100]@). We analyse in OKLab (@L ∈ [0,1]@,
Q16) because SixFour's whole colour core is already byte-exact OKLab Q16
('SixFour.Spec.ColorFixed'). Every zone edge / threshold is therefore in OKLab
units — do NOT copy the python's @L*@-scaled constants.

== Determinism
Means are computed SUM-then-DIVIDE (not a running mean), so the profile is
permutation-invariant under integer truncation — the same gauge-invariance ethos
as "SixFour.Spec.Collapse". All arithmetic is @Int@ (i64 in the Zig port).
-}
-- COMPARTMENT: SWIFT-COREAI | tag:DisplaySide | STRADDLER
module SixFour.Spec.ZoneProfile
  ( ZoneProfileQ16(..)
  , numZonesDefault
  , minZonePop
  , chromaQ16
  , analyzeZoneProfileQ16
  , sampleZoneTargetQ16
  ) where

import qualified Data.Vector.Unboxed as U

import SixFour.Spec.ColorFixed (q16One, isqrtFloor)

-- | A luminance-zone chroma profile in Q16 OKLab units. The three per-zone
-- vectors each have 'zpNumZones' entries; under-populated zones carry the global
-- mean (so the profile is always total over @[0, q16One]@).
data ZoneProfileQ16 = ZoneProfileQ16
  { zpNumZones :: !Int          -- ^ number of luminance zones (= 'numZonesDefault')
  , zpMeanA    :: !(U.Vector Int)  -- ^ per-zone mean @a@, Q16
  , zpMeanB    :: !(U.Vector Int)  -- ^ per-zone mean @b@, Q16
  , zpMeanC    :: !(U.Vector Int)  -- ^ per-zone mean chroma @√(a²+b²)@, Q16
  , zpGlobalA  :: !Int          -- ^ global mean @a@ (the empty-zone fallback), Q16
  , zpGlobalB  :: !Int          -- ^ global mean @b@, Q16
  , zpGlobalC  :: !Int          -- ^ global mean chroma, Q16
  } deriving (Eq, Show)

-- | Default zone count (the python @NUM_ZONES@). Eight zones over OKLab @L@.
numZonesDefault :: Int
numZonesDefault = 8

-- | Minimum population for a zone to use its OWN mean rather than the global
-- fallback. The python uses an absolute @>10@ against millions of GIF pixels;
-- that does NOT transfer to a 256-entry palette, so we require merely @≥ 1@ —
-- every representative palette colour in a zone is signal, not noise.
minZonePop :: Int
minZonePop = 1

-- | OKLab chroma magnitude in Q16 from Q16 @a@,@b@ components: @√(a²+b²)@. The
-- Q16 scale cancels (see 'isqrtFloor'), so this is a plain integer floor sqrt of
-- the sum of squares — byte-identical to the Zig helper.
chromaQ16 :: Int -> Int -> Int
chromaQ16 a b = isqrtFloor (a * a + b * b)

-- | Zone index (@0 .. nz-1@) for a Q16 lightness @L ∈ [0, q16One]@.
zoneOfL :: Int -> Int -> Int
zoneOfL nz l = min (nz - 1) (max 0 ((l * nz) `quot` q16One))

-- | The Q16 lightness at the CENTER of zone @z@: @((2z+1)/(2·nz))·q16One@.
zoneCenterL :: Int -> Int -> Int
zoneCenterL nz z = ((2 * z + 1) * q16One) `quot` (2 * nz)

-- | Build the zone profile from a palette of Q16 OKLab triples. Per-zone means
-- are sum-then-divide; zones with fewer than 'minZonePop' entries fall back to
-- the global mean. An empty palette yields an all-zero profile.
analyzeZoneProfileQ16 :: [(Int, Int, Int)] -> ZoneProfileQ16
analyzeZoneProfileQ16 px =
  let nz = numZonesDefault
      -- per-zone accumulators (sumA, sumB, sumC, count) and global accumulators
      zero = U.replicate nz 0 :: U.Vector Int
      step (sa, sb, sc, cnt, ga, gb, gc, gn) (l, a, b) =
        let z = zoneOfL nz l
            c = chromaQ16 a b
        in ( sa U.// [(z, sa U.! z + a)]
           , sb U.// [(z, sb U.! z + b)]
           , sc U.// [(z, sc U.! z + c)]
           , cnt U.// [(z, cnt U.! z + 1)]
           , ga + a, gb + b, gc + c, gn + 1 )
      (sumA, sumB, sumC, count, gA, gB, gC, gN) =
        foldl step (zero, zero, zero, zero, 0, 0, 0, 0 :: Int) px
      meanGlobal s = if gN > 0 then s `quot` gN else 0
      globalA = meanGlobal gA
      globalB = meanGlobal gB
      globalC = meanGlobal gC
      zoneMean s g = U.generate nz $ \z ->
        let n = count U.! z
        in if n >= minZonePop then (s U.! z) `quot` n else g
  in ZoneProfileQ16
       { zpNumZones = nz
       , zpMeanA    = zoneMean sumA globalA
       , zpMeanB    = zoneMean sumB globalB
       , zpMeanC    = zoneMean sumC globalC
       , zpGlobalA  = globalA
       , zpGlobalB  = globalB
       , zpGlobalC  = globalC
       }

-- | Sample the target @(a, b, chroma)@ at a Q16 lightness @L@ by piecewise-linear
-- interpolation through the zone CENTERS. Below the first center / above the last
-- center the value CLAMPS to the end zone (no extrapolation). Returns Q16.
sampleZoneTargetQ16 :: ZoneProfileQ16 -> Int -> (Int, Int, Int)
sampleZoneTargetQ16 zp l =
  let nz  = zpNumZones zp
      mA  = zpMeanA zp
      mB  = zpMeanB zp
      mC  = zpMeanC zp
      at z = (mA U.! z, mB U.! z, mC U.! z)
      c0    = zoneCenterL nz 0
      cLast = zoneCenterL nz (nz - 1)
  in if nz <= 1 || l <= c0
       then at 0
       else if l >= cLast
              then at (nz - 1)
              else
                let z   = segIndex nz l 0
                    lo  = zoneCenterL nz z
                    hi  = zoneCenterL nz (z + 1)
                    frac = if hi > lo then ((l - lo) * q16One) `quot` (hi - lo) else 0
                    (a0, b0, c0') = at z
                    (a1, b1, c1)  = at (z + 1)
                    lerp v0 v1 = v0 + ((v1 - v0) * frac) `quot` q16One
                in (lerp a0 a1, lerp b0 b1, lerp c0' c1)

-- | Index of the segment @[center z, center (z+1))@ containing @l@ (assumes
-- @center 0 < l < center (nz-1)@). Linear scan — @nz@ is tiny (8).
segIndex :: Int -> Int -> Int -> Int
segIndex nz l z
  | z >= nz - 2                  = z
  | l < zoneCenterL nz (z + 1)   = z
  | otherwise                    = segIndex nz l (z + 1)

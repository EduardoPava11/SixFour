{- |
Module      : V2RgbEisenstein
Description : V2 EXPLORATION — NOT WIRED, NOT THE PRODUCTION SPEC (apart from spec/src).

  This file is a STANDALONE exploration of the "V2" model: drop OKLab entirely and
  work directly on GIF89a basic 8-bit R,G,B, keeping V1's two mathematical lenses:

    * DISCRETE GEOMETRY — the reversible integer Haar lift ('sLift') and the
      "1 coarse + 7 detail" octant ('liftOct') = root lattice A_7. These are
      COLOUR-AGNOSTIC (operate on Ints), so they port to RGB UNCHANGED.

    * ALGEBRAIC NUMBER THEORY — RGB's 3 symmetric primaries sit at 120 degrees in the
      plane orthogonal to the gray axis (1,1,1). That hexagonal (A_2) symmetry is the
      EISENSTEIN integers Z[w], w = exp(2*pi*i/3) (replacing V1's Gaussian Z[i], which
      is the 4-fold square lattice for OKLab's (a,b) chroma).

  HONESTY NOTES (the project rejects forced jargon; only claim a structure if its
  axioms actually check):
    * Multiplication by w is a 120-degree hue rotation of ORDER 3 (w^3 = 1), NOT order 6.
      The order-6 structure is the UNIT GROUP {+-1, +-w, +-w^2}; its generator is the
      60-degree unit -w^2 = (1 + w) = 'u60' = exp(i*pi/3). Both facts are encoded below.
    * The (R,G,B) <-> (luma, chroma) round trip is INTEGER-EXACT (the /3 numerators are
      always divisible by 3 for any real RGB), but the inverse on an ARBITRARY (L,a,b)
      lattice point needs a divisibility check — V2 is NOT a pure dyadic Z[1/2] substrate
      like V1, so byte-exact mid-computation flooring is an OPEN design question.

  This module imports BASE ONLY. It copies the handful of primitives it needs from the
  spec (it does NOT import sixfour-spec). Run with:  runghc V2RgbEisenstein.hs
-}
module V2RgbEisenstein where

-- ===========================================================================
-- (a) Discrete geometry: reversible integer Haar lift (ported from OctreeCell.hs)
-- ===========================================================================

-- | The 1-D reversible S-transform. @d = x - y@; coarse keeps the floor average.
-- @div@ rounds toward -inf, which is what makes this an exact bijection.
sLift :: Int -> Int -> (Int, Int)
sLift x y = let d = x - y in (y + (d `div` 2), d)

-- | Exact inverse of 'sLift'.
sUnlift :: Int -> Int -> (Int, Int)
sUnlift lo hi = let y = lo - (hi `div` 2) in (y + hi, y)

-- | Eight scalar voxels (one channel of a 2x2x2 octant), Morton-ordered.
data V8 = V8 Int Int Int Int Int Int Int Int deriving (Eq, Show)

-- | The lifted octant: ONE coarse sub-band + SEVEN detail sub-bands (A_7 shape).
-- Built as a binary Haar tree of 'sLift's — fully reversible on any Int channel.
data OctBand = OctBand Int (Int,Int,Int,Int,Int,Int,Int) deriving (Eq, Show)

-- | @2x2x2 -> (coarse, 7 detail)@, an exact integer bijection. Colour-agnostic.
liftOct :: V8 -> OctBand
liftOct (V8 a b c d e f g h) =
  let (c0,d0) = sLift a b
      (c1,d1) = sLift c d
      (c2,d2) = sLift e f
      (c3,d3) = sLift g h
      (cc0,dd0) = sLift c0 c1
      (cc1,dd1) = sLift c2 c3
      (coarse,ddd) = sLift cc0 cc1
  in OctBand coarse (d0,d1,d2,d3,dd0,dd1,ddd)

-- | Exact inverse of 'liftOct'.
unliftOct :: OctBand -> V8
unliftOct (OctBand coarse (d0,d1,d2,d3,dd0,dd1,ddd)) =
  let (cc0,cc1) = sUnlift coarse ddd
      (c0,c1)   = sUnlift cc0 dd0
      (c2,c3)   = sUnlift cc1 dd1
      (a,b)     = sUnlift c0 d0
      (c,d)     = sUnlift c1 d1
      (e,f)     = sUnlift c2 d2
      (g,h)     = sUnlift c3 d3
  in V8 a b c d e f g h

-- | An RGB octant lifts per channel (the A_7 detail shape is identical on each of R,G,B,
-- exactly as V1 lifts each of L,a,b). 8 RGB voxels -> 3 OctBands.
liftOctRGB :: [(Int,Int,Int)] -> (OctBand, OctBand, OctBand)
liftOctRGB vs =
  ( liftOct (chan (\(r,_,_) -> r))
  , liftOct (chan (\(_,g,_) -> g))
  , liftOct (chan (\(_,_,b) -> b)) )
  where chan sel = let [a,b,c,d,e,f,g,h] = map sel vs in V8 a b c d e f g h

-- ===========================================================================
-- (c) Eisenstein integers Z[w], w = exp(2*pi*i/3), w^2 = -1 - w (so 1+w+w^2 = 0)
-- ===========================================================================

-- | An Eisenstein integer @a + b*w@.
data Eisen = Eisen Int Int deriving (Eq, Show)

eadd :: Eisen -> Eisen -> Eisen
eadd (Eisen a b) (Eisen c d) = Eisen (a + c) (b + d)

-- | Multiplication using @w^2 = -1 - w@:
-- @(a+bw)(c+dw) = (ac - bd) + (ad + bc - bd)w@.
emul :: Eisen -> Eisen -> Eisen
emul (Eisen a b) (Eisen c d) = Eisen (a*c - b*d) (a*d + b*c - b*d)

-- | The Eisenstein norm @N(a+bw) = a^2 - a*b + b^2@ (integer-exact, multiplicative).
norm :: Eisen -> Int
norm (Eisen a b) = a*a - a*b + b*b

-- The six units {+-1, +-w, +-w^2} = the 6 sixth-roots of unity, 60 degrees apart.
eOne, omega, omega2, negOne, negOmega, negOmega2 :: Eisen
eOne      = Eisen 1 0       -- 1     (0 deg)
omega     = Eisen 0 1       -- w     (120 deg) -- order 3
omega2    = Eisen (-1) (-1) -- w^2   (240 deg)
negOne    = Eisen (-1) 0    -- -1    (180 deg)
negOmega  = Eisen 0 (-1)    -- -w    (300 deg)
negOmega2 = Eisen 1 1       -- -w^2  (60 deg)  -- order 6 generator

-- | All six units.
units :: [Eisen]
units = [eOne, omega, omega2, negOne, negOmega, negOmega2]

-- | The 60-degree generator of the unit group: @-w^2 = 1 + w = exp(i*pi/3)@, ORDER 6.
u60 :: Eisen
u60 = negOmega2

-- | Hue rotation by 120 degrees = multiply by @w@. This has ORDER 3 (w^3 = 1), not 6;
-- the order-6 element is 'u60'. (Honest naming: see the header.)
hueRotate :: Eisen -> Eisen
hueRotate = emul omega

-- ===========================================================================
-- (b) The RGB <-> (luma, chroma) embedding (no OKLab, no cbrt, no matrices)
-- ===========================================================================

-- | luma = balance on (1,1,1) = R+G+B; chroma = (R-B) + (G-B)*w in Z[w].
-- The gray axis (1,1,1) is only APPROXIMATE perceptual luma (true Rec.709 weights
-- 0.2126/0.7152/0.0722 sit ~39.8 deg off the (1,1,1) direction) — a documented GIVE-UP.
rgbToLumaChroma :: (Int,Int,Int) -> (Int, Eisen)
rgbToLumaChroma (r,g,b) = (r + g + b, Eisen (r - b) (g - b))

-- | Inverse. INTEGER-EXACT for any chroma/luma produced by 'rgbToLumaChroma'
-- (the /3 numerators are always divisible by 3). For an arbitrary (L,a,b) the
-- three numerators must each be divisible by 3 — 'div' here would otherwise floor.
lumaChromaToRgb :: (Int, Eisen) -> (Int,Int,Int)
lumaChromaToRgb (l, Eisen a b) =
  ( (2*a + l - b) `div` 3
  , (2*b + l - a) `div` 3
  , (l - a - b)   `div` 3 )

-- ===========================================================================
-- (d) Example laws (each a Bool, checked over representative samples in main)
-- ===========================================================================

rgbSamples :: [(Int,Int,Int)]
rgbSamples = [(0,0,0),(255,255,255),(255,0,0),(0,255,0),(0,0,255)
             ,(128,64,200),(17,200,99),(255,128,0),(60,60,60),(3,251,7)]

octSample :: [(Int,Int,Int)]
octSample = [(0,0,0),(255,128,7),(17,200,99),(255,0,0)
            ,(0,255,0),(0,0,255),(60,90,255),(200,200,1)]

eisenSamples :: [Eisen]
eisenSamples = [Eisen 0 0, Eisen 1 0, Eisen 0 1, Eisen 3 (-2)
               ,Eisen (-4) 5, Eisen 7 7, Eisen (-9) (-2)]

-- | 1. The scalar S-transform round-trips (the substrate of the whole lift).
lawSLiftRoundTrips :: Bool
lawSLiftRoundTrips =
  and [ uncurry sUnlift (sLift x y) == (x,y) | x <- [-300..300], y <- [-9,0,7,255] ]

-- | 2. @unliftOct . liftOct = id@ on every RGB channel of a sample octant.
lawLiftOctRoundTrips :: Bool
lawLiftOctRoundTrips =
  let (br,bg,bb) = liftOctRGB octSample
      chan sel   = let [a,b,c,d,e,f,g,h] = map sel octSample in V8 a b c d e f g h
  in unliftOct br == chan (\(r,_,_) -> r)
  && unliftOct bg == chan (\(_,g,_) -> g)
  && unliftOct bb == chan (\(_,_,b) -> b)

-- | 3. @w^3 = 1@, so multiply-by-w (hueRotate) has ORDER 3, not 6.
lawOmegaCubedOrderThree :: Bool
lawOmegaCubedOrderThree =
  emul omega (emul omega omega) == eOne
  && and [ hueRotate (hueRotate (hueRotate z)) == z | z <- eisenSamples ]

-- | 4. The UNIT GROUP has order 6: u60 = -w^2 = exp(i*pi/3) generates it, u60^6 = 1
-- (and so w^6 = 1), and the 6 generated powers are exactly the 6 units.
lawUnitGroupOrderSix :: Bool
lawUnitGroupOrderSix =
  let pow k = foldr emul eOne (replicate k u60)
      gen   = [ pow k | k <- [1..6] ]
  in pow 6 == eOne
  && foldr emul eOne (replicate 6 omega) == eOne
  && all (`elem` units) gen
  && all (`elem` gen) units

-- | 5. The norm is multiplicative: @N(x*y) = N(x)*N(y)@.
lawNormMultiplicative :: Bool
lawNormMultiplicative =
  and [ norm (emul x y) == norm x * norm y | x <- eisenSamples, y <- eisenSamples ]

-- | 6. A gray pixel (r,r,r) has ZERO chroma (it lies on the (1,1,1) balance axis).
lawGrayHasZeroChroma :: Bool
lawGrayHasZeroChroma =
  and [ snd (rgbToLumaChroma (r,r,r)) == Eisen 0 0 | r <- [0,1,7,128,200,255] ]

-- | 7. The RGB -> (luma,chroma) -> RGB round trip is INTEGER-EXACT (a real GET:
-- byte-exact at the working-space level, no okLab<->sRGB lossy crossing).
lawRgbRoundTripExact :: Bool
lawRgbRoundTripExact =
  and [ lumaChromaToRgb (rgbToLumaChroma p) == p | p <- rgbSamples ]

-- | 8. Hue rotation (a unit multiply) preserves the chroma norm = it is a ROTATION,
-- not a scale (the 6 units are exactly the norm-1 elements of Z[w]).
lawHueRotatePreservesNorm :: Bool
lawHueRotatePreservesNorm =
  and [ norm (hueRotate z) == norm z | z <- eisenSamples ]
  && all ((== 1) . norm) units

-- ===========================================================================
-- (e) Runner
-- ===========================================================================

checks :: [(String, Bool)]
checks =
  [ ("lawSLiftRoundTrips",        lawSLiftRoundTrips)
  , ("lawLiftOctRoundTrips",      lawLiftOctRoundTrips)
  , ("lawOmegaCubedOrderThree",   lawOmegaCubedOrderThree)
  , ("lawUnitGroupOrderSix",      lawUnitGroupOrderSix)
  , ("lawNormMultiplicative",     lawNormMultiplicative)
  , ("lawGrayHasZeroChroma",      lawGrayHasZeroChroma)
  , ("lawRgbRoundTripExact",      lawRgbRoundTripExact)
  , ("lawHueRotatePreservesNorm", lawHueRotatePreservesNorm)
  ]

main :: IO ()
main = do
  mapM_ (\(n,ok) -> putStrLn ((if ok then "PASS " else "FAIL ") ++ n)) checks
  let passed = length (filter snd checks)
      total  = length checks
  putStrLn ("---- " ++ show passed ++ "/" ++ show total ++ " checks passed"
            ++ (if passed == total then " (ALL PASS)" else " (FAILURES)"))

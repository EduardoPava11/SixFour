{- |
Module      : V2LatentMaintenance
Description : EXPLORATION (NOT WIRED, base-only, runghc). The MAINTENANCE INVARIANT on top of the locked
              V2 latent: the model is CREATED AND MAINTAINED AT ALL TIMES in the [L,a,b,x,y,t] opponent
              latent. sRGB 8-bit appears ONLY in two boundary functions (encodeBoundary in, decodeBoundary
              out). Every interior operation (energy measurement, nudge/move, commit/snap) is typed
              Latent -> Latent (or Latent -> Int for a measurement); none of them mentions sRGB. "Lab in
              SHAPE, free in RGB": the AXES are the opponent Lab-like shape (the energy metric reads
              L,a,b), yet every Latent is byte-exactly reversible to a UNIQUE sRGB carrier.

  Check:  cd /Users/daniel/SixFour/spec && ~/.ghcup/bin/runghc exploration/V2LatentMaintenance.hs

  WHAT THIS MODELS (owner request #1, "latent maintained at all times in latent space"):
    * A small IN-LATENT algebra. The model never holds an sRGB value during reasoning. It encodes ONCE
      at ingest (encodeBoundary), then all moves are Latent -> Latent, and it decodes ONCE at export
      (decodeBoundary). The interior may sit OFF the index-6 lattice temporarily (a raw nudge), but the
      value is STILL a Latent (never an sRGB), and `commit` (= snapColour) lands it back on-lattice
      before export. So "maintained in latent space" = the carried value is always of type Latent.
    * The energy measurement (an energy-weighted L1, copied from V2EnergyWeave.dW) reads the opponent
      AXES directly off the Latent. That is the "Lab in shape" half: the geometry the search descends is
      the opponent shape. The "free in RGB" half: every on-lattice Latent inverts to a unique sRGB, so
      the carrier is byte-exact and recoverable at the boundary.

  THE BLESSED READING this relies on (cite V2Latent.hs, the LOCK; this EXTENDS it, does not re-open it):
    * The latent is OPPONENT-LITERAL and LOCKED: latL = R+G+B, latA = R-G, latB = R+G-2B, plus (x,y,t).
      The 6 fields are the 6 CNN channels. This module reuses that exact record and arithmetic.
    * Decode is invert-or-refuse on the index-6 lattice: (L - b) == 0 mod 3 AND (a + b) even. The "6 = 3*2"
      congruences. snapColour projects an off-lattice nudge back on. We reuse those verbatim.
    * V2EnergyWeave: the energy-weighted metric dW(ws) = sum w_i*|dp_i|, weights = per-axis entropy. We
      reuse dW over `channels` so energy is measured IN latent space.

  THE b-SIGN RECONCILIATION (owner request #2, stated plainly, NOT silently flipped):
    * The owner writes the yellow-blue / energy axis as  b_owner = 2B - (R+G).
    * V2Latent LOCKS the STORED field as          latB = R+G - 2B  =  -(b_owner)  (the NEGATION).
    * DECISION: we KEEP THE LOCKED STORED SIGN  latB = R+G-2B  (so decode/onLattice are unchanged and
      byte-exactness is preserved exactly as in V2Latent). The owner's axis is provided as a DERIVED,
      never-stored ENERGY VIEW  ownerBView lat = negate (latB lat) = 2B-(R+G).
    * WHY this is safe: the decode congruences ((L - latB) mod 3 == 0 AND (latA + latB) even) and the
      rr/gg/bb inverse are SIGN-SENSITIVE, so we must not substitute b_owner into them. But energy and
      every distance use |.|, and |b_owner| = |latB|, |b_owner1 - b_owner2| = |latB1 - latB2|, so the
      ENERGY comparison the owner asks for (b1:b2 in terms of energy) is identical under either sign.
      lawCarrierByteExactUnderChosenSign checks decode under the STORED sign on random RGB;
      lawEnergyBSignInvariant checks the energy/distance is sign-invariant AND that the flip is real.

  HONESTY (what is and is NOT claimed):
    * The "no interior operation calls the boundary" invariant is enforced by TYPE DISCIPLINE here, not by
      a runtime proof: every interior op has type `Latent -> Latent` (or `... -> Int` for a measurement),
      and sRGB8 appears ONLY in the type signatures of encodeBoundary / decodeBoundary. We WITNESS the
      invariant (an interior nudge produces a genuine off-lattice Latent, decoded nowhere, then committed
      back on-lattice), but Haskell's type system, not a law, is what forbids a hidden boundary call. This
      is a design claim made checkable by inspection, not a theorem about arbitrary code.
    * "Lab in shape" is the OPPONENT shape (a mutually-orthogonal 3-axis frame L=(1,1,1), a=(1,-1,0),
      b=(1,1,-2), det 6). It is NOT perceptual CIE Lab; we make no perceptual-uniformity claim. The
      witness shows two RGBs SHARING the opponent chroma shape (a,b) but differing only along the luma
      CARRIER L, both reversible to distinct unique RGBs. That is the precise content of "same shape,
      free carrier".
    * The energy weighting reused (energyMatched) is the hand-picked integer stand-in from V2EnergyWeave,
      not a recomputed entropy; we only use it to show dW is sign-invariant in b. No entropy claim is made
      here beyond reusing that vector.
    * This module does NOT re-open the opponent-literal LOCK, the index-6 lattice, or the stored b sign.
      It ADDS the maintenance invariant + energy-in-latent + the explicit sign reconciliation.

  Base-only (Prelude + Data.List/Data.Maybe). runghc. NOT in cabal/Map/gate. No em-dashes. Trainer untouched.
-}
module V2LatentMaintenance where

import Data.Maybe (isJust)

-- ===========================================================================
-- (0) Copied primitives from V2Latent.hs (the LOCK) and V2EnergyWeave.hs (energy).
--     Copied verbatim (base-only house style; do not import sixfour-spec).
-- ===========================================================================

-- | BOUNDARY representation: raw sRGB 8-bit (each channel 0..255). The ONLY non-latent colour type.
type SRGB8 = (Int, Int, Int)

-- | A position in the (x, y, t) box (which voxel / frame). Metadata, not decoded.
type Pos = (Int, Int, Int)

-- | THE LOCKED V2 LATENT (V2Latent.hs): opponent colour (L,a,b) + position (x,y,t). 6 CNN channels.
--   OPPONENT-LITERAL: latL = R+G+B, latA = R-G, latB = R+G-2B (the STORED sign we keep).
data Latent = Latent
  { latL :: !Int   -- ^ luma        = R + G + B
  , latA :: !Int   -- ^ red-green    = R - G
  , latB :: !Int   -- ^ yellow-blue  = R + G - 2B   (STORED sign; owner's 2B-(R+G) = negate this)
  , latX :: !Int   -- ^ position x
  , latY :: !Int   -- ^ position y
  , latT :: !Int   -- ^ frame t
  } deriving (Eq, Show)

-- | The 6 latent channels as a vector (the CNN input order [L,a,b,x,y,t]). The bridge to the P6 metric.
channels :: Latent -> [Int]
channels (Latent l a b x y t) = [l, a, b, x, y, t]

latentChannelCount :: Int
latentChannelCount = 6

inRange8 :: Int -> Bool
inRange8 v = v >= 0 && v <= 255

isSRGB8 :: SRGB8 -> Bool
isSRGB8 (r, g, b) = all inRange8 [r, g, b]

-- | Is the COLOUR part on the index-6 lattice? (L - b) divisible by 3 AND a + b even. Sign-sensitive in b.
onLattice :: Latent -> Bool
onLattice (Latent l a b _ _ _) = (l - b) `mod` 3 == 0 && (a + b) `mod` 2 == 0

-- | snapColour: project an off-lattice (nudged) colour back on. Parity first (adjust b), then mod-3 (adjust L).
snapColour :: Latent -> Latent
snapColour (Latent l a b x y t) =
  let b' = if (a + b) `mod` 2 == 0 then b else b + 1
      l' = l - ((l - b') `mod` 3)
  in Latent l' a b' x y t

-- | The ENERGY-WEIGHTED metric (V2EnergyWeave.dW): sum w_i*|dp_i| over a P6. Uses abs, so b-sign invariant.
dW :: [Int] -> [Int] -> [Int] -> Int
dW ws p q = sum (zipWith3 (\w pp qq -> w * abs (pp - qq)) ws p q)

flatWeights :: [Int]
flatWeights = replicate 6 1

-- | Energy-matched weights (V2EnergyWeave): L=3=t, a=5=x, b=2=y. Reused only to show dW is sign-invariant.
energyMatched :: [Int]
energyMatched = [3, 5, 2, 5, 2, 3]

-- ===========================================================================
-- (1) THE BOUNDARY: the ONLY two functions where SRGB8 appears.
-- ===========================================================================

-- | ENCODE-IN (the ONLY ingress). Takes raw sRGB plus a position and MAKES the opponent latent. Total.
--   This is the single point where an sRGB value becomes a Latent; after this the model is in latent space.
encodeBoundary :: SRGB8 -> Pos -> Latent
encodeBoundary (r, g, b) (x, y, t) = Latent (r + g + b) (r - g) (r + g - 2 * b) x y t

-- | DECODE-OUT (the ONLY egress). Invert-or-refuse on the index-6 lattice. Position is metadata, not decoded.
--   Refuses off-lattice or out of 0..255. This is the single point where a Latent becomes an sRGB value.
decodeBoundary :: Latent -> Maybe SRGB8
decodeBoundary lat@(Latent l a b _ _ _)
  | not (onLattice lat) = Nothing
  | not (isSRGB8 px)    = Nothing
  | otherwise           = Just px
  where
    rr = (2 * l + 3 * a + b) `div` 6
    gg = (2 * l - 3 * a + b) `div` 6
    bb = (l - b) `div` 3
    px = (rr, gg, bb)

-- ===========================================================================
-- (2) THE INTERIOR ALGEBRA: every op is Latent -> Latent (or Latent -> Int).
--     sRGB8 NEVER appears below this line until the runner's demo. This is the maintenance invariant.
-- ===========================================================================

-- | Owner request #2: the owner's yellow-blue / energy axis b_owner = 2B - (R+G) = negate latB.
--   DERIVED, NEVER STORED. We expose it only as an energy view; the stored field stays latB = R+G-2B.
ownerBView :: Latent -> Int
ownerBView lat = negate (latB lat)

-- | A raw interior MOVE in colour space. May land OFF the index-6 lattice. STILL a Latent (in latent space).
moveColour :: (Int, Int, Int) -> Latent -> Latent
moveColour (dl, da, db) (Latent l a b x y t) = Latent (l + dl) (a + da) (b + db) x y t

-- | A raw interior MOVE in position space (which voxel/frame). Pure metadata, stays in latent space.
movePos :: (Int, Int, Int) -> Latent -> Latent
movePos (dx, dy, dt) (Latent l a b x y t) = Latent l a b (x + dx) (y + dy) (t + dt)

-- | COMMIT: snap an off-lattice interior latent back onto the lattice (= snapColour). Latent -> Latent.
commit :: Latent -> Latent
commit = snapColour

-- | ENERGY MEASUREMENT in latent space: the energy-weighted L1 over the opponent axes [L,a,b,x,y,t].
--   A MEASUREMENT (Latent -> Latent -> Int): reads the shape, produces a scalar, never an sRGB.
energy :: [Int] -> Latent -> Latent -> Int
energy ws p q = dW ws (channels p) (channels q)

-- | The SAME energy metric but reading the OWNER b sign (b_owner) on the b axis. Used to prove sign-invariance.
channelsOwnerB :: Latent -> [Int]
channelsOwnerB lat = [latL lat, latA lat, ownerBView lat, latX lat, latY lat, latT lat]

energyOwnerB :: [Int] -> Latent -> Latent -> Int
energyOwnerB ws p q = dW ws (channelsOwnerB p) (channelsOwnerB q)

-- | Owner request #2, literal: the b ENERGY DISTANCE between two frames "beside each other" (separated by t).
--   |b_owner1 - b_owner2| = |[2B1-(R1+G1)] - [2B2-(R2+G2)]|. Sign-invariant (equals |latB1 - latB2|).
bEnergyDist :: Latent -> Latent -> Int
bEnergyDist p q = abs (ownerBView p - ownerBView q)

-- ===========================================================================
-- (3) Sample data: the grid cube, random RGB (an LCG), and the carrier-family witness.
-- ===========================================================================

grid :: [Int]
grid = [0, 1, 15, 16, 127, 128, 200, 254, 255]

cube :: [SRGB8]
cube = [(r, g, b) | r <- grid, g <- grid, b <- grid]

pos0 :: Pos
pos0 = (3, 4, 5)

-- | A tiny deterministic LCG so lawCarrierByteExactUnderChosenSign tests RANDOM RGB, not just the grid.
lcg :: Int -> Int
lcg s = (1103515245 * s + 12345) `mod` 2147483648

randRGBs :: Int -> [SRGB8]
randRGBs n = take n (go 7)
  where
    go s = let s1 = lcg s; s2 = lcg s1; s3 = lcg s2
           in (s1 `mod` 256, s2 `mod` 256, s3 `mod` 256) : go s3

-- | THE CARRIER FAMILY (witness for "same opponent shape, free in RGB carrier"). Every member shares the
--   SAME opponent chroma (latA,latB) = (2,4) but a different luma CARRIER L, and a distinct RGB.
--   For a=R-G=2 and b=R+G-2B=4: R = 3+B, G = 1+B. Varying B slides ONLY the luma carrier.
carrierFamily :: [SRGB8]
carrierFamily = [ (3 + bb, 1 + bb, bb) | bb <- [5, 10, 20, 50, 100] ]

-- | Frame pairs "beside each other" (same voxel, frames t and t+1) for the b-energy / sign-invariance laws.
framePairs :: [(SRGB8, SRGB8)]
framePairs =
  [ ((200, 50, 10), (40, 60, 220))
  , ((10, 10, 10),  (250, 5, 5))
  , ((128, 128, 0), (0, 0, 255))
  , ((30, 200, 90), (90, 30, 200))
  ]

-- | Encode a frame pair to two latents at adjacent t (the "separated by a t, beside each other" picture).
encPair :: (SRGB8, SRGB8) -> (Latent, Latent)
encPair (p, q) = (encodeBoundary p (1, 1, 0), encodeBoundary q (1, 1, 1))

-- ===========================================================================
-- (4) Laws
-- ===========================================================================

-- | THE BOUNDARY-ONLY ROUND TRIP. decodeBoundary . (flip encodeBoundary pos) == Just on every valid pixel
--   (the lattice the encoder lands on), AND the interior never needs the boundary: an interior pipeline
--   (moveColour off the lattice, then commit) keeps a Latent throughout and decodes only at the very end.
--   NON-VACUOUS tooth: the mid-pipeline value is GENUINELY off the lattice (so we proved we did not decode
--   it), yet after commit it decodes. The boundary is crossed exactly twice: encode in, decode out.
lawBoundaryOnlyRoundTrip :: Bool
lawBoundaryOnlyRoundTrip =
     all (\px -> decodeBoundary (encodeBoundary px pos0) == Just px) cube     -- in then out = identity
  && all (\px -> let lt0 = encodeBoundary px pos0                              -- encode ONCE (boundary in)
                     mid = moveColour (1, 0, 0) lt0                            -- interior move (Latent -> Latent)
                     fin = commit (movePos (2, 0, 0) mid)                      -- more interior, then commit
                 in not (onLattice mid)                                        -- mid is OFF-lattice (we did NOT decode it)
                    && onLattice fin                                           -- commit restored the lattice
                    && isJust (decodeBoundary fin)) cube                       -- decode ONCE at the end (boundary out)

-- | "Lab in SHAPE, free in RGB". The AXES are the opponent shape (the energy metric reads L,a,b), yet every
--   Latent is byte-exactly reversible to a UNIQUE RGB carrier. WITNESS: the carrier family shares the SAME
--   opponent chroma shape (latA,latB) but differs ONLY along the luma carrier L, and each member decodes to
--   its own distinct unique RGB. So the chroma-only energy reads 0 between any two (same shape) while the
--   full energy distinguishes them (different carrier), and decode recovers each RGB exactly.
lawShapeIsOpponentCarrierIsRgb :: Bool
lawShapeIsOpponentCarrierIsRgb =
     length lats >= 2
  && all (\lt -> (latA lt, latB lt) == (2, 4)) lats                            -- all share the opponent chroma shape
  && length (nubInt (map latL lats)) == length lats                           -- but the luma CARRIER differs for each
  && all (\(px, lt) -> decodeBoundary lt == Just px) (zip carrierFamily lats) -- each reverses to its UNIQUE RGB
  && length (nubRGB carrierFamily) == length carrierFamily                     -- the RGB carriers are all distinct
  && all (\(p, q) -> energy chromaOnly p q == 0) pairs                         -- chroma-only energy: same SHAPE -> 0
  && all (\(p, q) -> energy flatWeights p q > 0) pairs                         -- full energy: different CARRIER -> > 0
  where
    lats      = map (`encodeBoundary` pos0) carrierFamily
    pairs     = [ (a, b) | a <- lats, b <- lats, latL a < latL b ]            -- distinct-carrier pairs
    chromaOnly = [0, 1, 1, 0, 0, 0]                                            -- weight ONLY the opponent chroma axes a,b
    nubInt = foldr (\v acc -> if v `elem` acc then acc else v : acc) []
    nubRGB = foldr (\v acc -> if v `elem` acc then acc else v : acc) []

-- | THE CARRIER IS BYTE-EXACT UNDER THE CHOSEN (STORED) SIGN. On RANDOM RGB (an LCG, not just the grid),
--   encodeBoundary then decodeBoundary recovers the pixel exactly, AND the decode congruences hold UNDER
--   THE STORED SIGN latB = R+G-2B: (latL - latB) divisible by 3 AND (latA + latB) even. NON-VACUOUS tooth:
--   substituting the owner sign ownerBView = -(latB) into the SAME mod-3 congruence would FAIL on a real
--   pixel (it is not invariant under the flip), so keeping the stored sign is load-bearing, not cosmetic.
lawCarrierByteExactUnderChosenSign :: Bool
lawCarrierByteExactUnderChosenSign =
     all (\px -> decodeBoundary (encodeBoundary px pos0) == Just px) rnd        -- byte-exact on random RGB
  && all (\px -> let lt = encodeBoundary px pos0                                -- the congruences hold under STORED sign
                 in (latL lt - latB lt) `mod` 3 == 0 && (latA lt + latB lt) `mod` 2 == 0) rnd
  && any (\px -> let lt = encodeBoundary px pos0                                -- TOOTH: owner sign breaks the mod-3 guard
                 in (latL lt - ownerBView lt) `mod` 3 /= 0) rnd                 --        (so we must NOT silently flip)
  where rnd = randRGBs 200

-- | THE b-SIGN / ENERGY RECONCILIATION (owner request #2). The owner's b_owner = 2B-(R+G) is the NEGATION
--   of the stored latB, AND the flip is REAL (not all-zero). Yet the b ENERGY comparison the owner asks for,
--   "b1:b2 in terms of energy", is sign-INVARIANT: |b_owner1 - b_owner2| = |latB1 - latB2|, and the full
--   energy-weighted metric dW is identical whether it reads the stored or the owner sign on b. NON-VACUOUS:
--   we require a pair where latB is nonzero so the flip genuinely changes the raw value.
lawEnergyBSignInvariant :: Bool
lawEnergyBSignInvariant =
     all (\px -> let lt = encodeBoundary px pos0 in ownerBView lt == negate (latB lt)) cube   -- owner b = -(stored b)
  && any (\px -> let lt = encodeBoundary px pos0 in latB lt /= 0 && ownerBView lt /= latB lt) cube  -- flip is REAL
  && all (\fp -> let (p, q) = encPair fp                                                       -- owner b-energy distance
                 in bEnergyDist p q == abs (latB p - latB q)) framePairs                       --   == stored b distance
  && all (\fp -> let (p, q) = encPair fp                                                       -- full dW: sign-invariant
                 in energy energyMatched p q == energyOwnerB energyMatched p q) framePairs
  && any (\fp -> let (p, q) = encPair fp in latB p /= latB q) framePairs                       -- the b axis actually moves

-- | THE MAINTENANCE INVARIANT, restated end-to-end: a full session (encode in, several interior moves and
--   energy measurements, commit, decode out) keeps a Latent at every interior step and crosses the boundary
--   exactly twice. We witness that (a) every interior step is on the Latent type (trivially, by construction),
--   (b) an interior measurement (energy) produces a scalar, not an sRGB, and (c) the committed latent is
--   on-lattice so the boundary-out can ONLY refuse on gamut, never on lattice. NON-VACUOUS: the pipeline
--   visits an off-lattice Latent (the model stays in latent space WITHOUT exporting), the measured energy is
--   strictly positive (a real read), and a separate witness shows the boundary-out actually succeeds.
lawInteriorStaysInLatent :: Bool
lawInteriorStaysInLatent =
     all run cube
  && any (isJust . decodeBoundary . session) cube   -- boundary OUT actually succeeds on the in-gamut pixels
  && all (\px -> case decodeBoundary (session px) of -- decode refuses ONLY on gamut, NEVER on lattice
                   Just _  -> True
                   Nothing -> not (inGamut (session px))) cube
  where
    session px =
      let lt0 = encodeBoundary px pos0                 -- boundary IN (once)
          a1  = moveColour (5, 2, 1) lt0               -- interior: Latent -> Latent (may leave lattice)
          a2  = movePos (1, 0, 1) a1                   -- interior: Latent -> Latent
      in commit a2                                     -- interior: snap back on-lattice (the final Latent)
    run px =
      let lt0 = encodeBoundary px pos0
          a1  = moveColour (5, 2, 1) lt0
          a2  = movePos (1, 0, 1) a1
          e   = energy flatWeights lt0 a2              -- interior MEASUREMENT: Latent -> Int (no sRGB)
          fin = session px
      in not (onLattice a1)                            -- visited an off-lattice Latent (stayed in latent space)
         && e > 0                                      -- the measurement is a real, non-trivial scalar read
         && onLattice fin                              -- committed back on-lattice (so decode refuses only on gamut)
    -- A committed (on-lattice) latent is in gamut iff its decoded rr/gg/bb all lie in 0..255.
    inGamut (Latent l a b _ _ _) =
      isSRGB8 ((2*l + 3*a + b) `div` 6, (2*l - 3*a + b) `div` 6, (l - b) `div` 3)

-- ===========================================================================
-- (5) Runner
-- ===========================================================================

laws :: [(String, Bool)]
laws =
  [ ("lawBoundaryOnlyRoundTrip         (encode-in/decode-out only; interior off-lattice, never decoded)", lawBoundaryOnlyRoundTrip)
  , ("lawShapeIsOpponentCarrierIsRgb   (same opponent shape, free luma carrier, each reversible to RGB)", lawShapeIsOpponentCarrierIsRgb)
  , ("lawCarrierByteExactUnderChosenSign(random RGB round-trips; owner sign would break the mod-3 guard)", lawCarrierByteExactUnderChosenSign)
  , ("lawEnergyBSignInvariant          (owner b = -(stored b); flip real; b-energy & dW sign-invariant)",  lawEnergyBSignInvariant)
  , ("lawInteriorStaysInLatent         (full session: Latent at every interior step, boundary crossed 2x)", lawInteriorStaysInLatent)
  ]

main :: IO ()
main = do
  putStrLn "V2LatentMaintenance.hs  -- EXPLORATION (NOT WIRED): the latent-space MAINTENANCE invariant"
  putStrLn (replicate 78 '-')
  mapM_ (\(n, ok) -> putStrLn (verdict ok ++ "  " ++ n)) laws
  putStrLn (replicate 78 '-')
  let passed = length (filter snd laws); total = length laws
  putStrLn ("SUMMARY: " ++ show passed ++ "/" ++ show total ++ " laws PASS"
            ++ if passed == total then "  (all green)" else "  (FAILURES present)")
  putStrLn ""
  let lt   = encodeBoundary (200, 50, 10) (3, 4, 5)
      mid  = moveColour (1, 0, 0) lt
  putStrLn ("encodeBoundary (200,50,10) (3,4,5) = " ++ show lt)
  putStrLn ("  channels [L,a,b,x,y,t]           = " ++ show (channels lt))
  putStrLn ("  stored latB = R+G-2B             = " ++ show (latB lt)
            ++ "    owner b = 2B-(R+G) = ownerBView = " ++ show (ownerBView lt) ++ "  (the negation)")
  putStrLn ("  interior moveColour (1,0,0)      = " ++ show mid
            ++ "    onLattice? " ++ show (onLattice mid) ++ "  (off-lattice, still a Latent)")
  putStrLn ("  commit (snap back on-lattice)    = " ++ show (commit mid)
            ++ "    decodeBoundary = " ++ show (decodeBoundary (commit mid)))
  let famLats = map (`encodeBoundary` pos0) carrierFamily
  putStrLn ""
  putStrLn ("carrier family (same chroma (a,b)=(2,4), free luma carrier L):")
  putStrLn ("  RGB carriers = " ++ show carrierFamily)
  putStrLn ("  (a,b) each   = " ++ show (map (\l -> (latA l, latB l)) famLats))
  putStrLn ("  luma L each  = " ++ show (map latL famLats) ++ "  (the free carrier varies; shape fixed)")
  putStrLn ""
  putStrLn "MAINTENANCE INVARIANT: sRGB appears ONLY in encodeBoundary / decodeBoundary. Every interior op"
  putStrLn "is Latent -> Latent (or Latent -> Int). 'Lab in SHAPE' = the energy metric reads the opponent"
  putStrLn "axes; 'free in RGB' = every on-lattice Latent reverses to a unique sRGB carrier. The stored b"
  putStrLn "sign latB = R+G-2B is kept (= -(owner 2B-(R+G))); energy is |.|-based so the comparison is"
  putStrLn "sign-invariant, while decode stays sign-sensitive and byte-exact. Extends V2Latent's lock."
  where
    verdict True  = "PASS"
    verdict False = "FAIL"

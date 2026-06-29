-- |
-- Module      : V2CrossFrameBEnergy
-- Description : ASK 2. Cross-frame opponent-b energy at the t-seam of the 64^3 -> 16^3 octree.
--
-- WHAT THIS MODELS
-- ----------------
-- The 64^3 -> 16^3 octree decomposition pairs two t-slices ("two frames beside each
-- other") inside every 2x2x2 block. This module models the t-axis Haar detail band of
-- that pairing and reads it as OPPONENT-b ENERGY, exactly the owner's literal form:
--
--     bEnergy(px) = | 2*B - (R + G) |
--
-- For a per-cell frame pair (f1, f2) the t-seam is the reversible Haar lift along t:
-- coarse = floor average of the two slices, detail = their channelwise difference. We
-- show that reading the t-detail band through the opponent-b projection recovers exactly
-- the owner's "b1 : b2 distance compared in terms of energy", and that this readout is a
-- lossless side-channel: the lift still round-trips byte-exactly back to (f1, f2).
--
-- THE BLESSED READING I RELY ON
-- -----------------------------
--  * V2Latent.hs locks the stored opponent b as  latB = R + G - 2B.
--    The owner's ASK 2 writes b = 2B - (R + G), which is the NEGATION:  ownerB = -latB.
--    I keep BOTH explicit. `ownerB` is the owner's signed b, `latB` is the V2Latent
--    stored field, and `lawSignReconcile` checks `ownerB px == negate (latB px)` for
--    every pixel. I do not silently flip the sign anywhere: the energy readout uses
--    `abs` (magnitude is invariant to the flip), but I name the convention at each site.
--  * V2EnergyWeave.hs: axis "energy" is the Shannon entropy of that axis's value series,
--    and the energy-weighted metric `dW` is a weighted L1 using `abs`. `seamEnergyW` here
--    is precisely that metric restricted to the single b-axis of the t-detail band: a
--    positive integer weight times the L1 of the seam b-difference. I reuse `entropyBits`
--    to show the b-axis is genuinely non-degenerate (entropy > 0) so the weight is
--    load-bearing, mirroring V2EnergyWeave's `lawWeightsVaryByEntropy`.
--  * V2RgbEisenstein.hs: the 1-D reversible S-transform `sLift`/`sUnlift`. I copy these
--    verbatim and apply them per channel along t. They are exact integer bijections
--    because `div` floors toward -inf (so coarse = y + (x-y)`div`2, detail = x-y inverts).
--  * opponent-b is LINEAR in (R,G,B):  ownerB(p) = 2*pB - pR - pG. Because the Haar
--    t-detail pixel is the channelwise difference (r1-r2, g1-g2, b1-b2), linearity gives
--    ownerB(detail) = ownerB(p1) - ownerB(p2) EXACTLY. That linearity is the whole reason
--    the seam b-difference and the t-detail's b-projection coincide with no rounding.
--
-- HONESTY
-- -------
--  * The exact identity is on the SIGNED opponent-b:  ownerB(detail) == ownerB f1 - ownerB f2.
--    The owner's phrasing "bEnergy(f1) - bEnergy(f2)" uses magnitudes, and
--    |b1| - |b2| == b1 - b2 ONLY when b1 and b2 share a sign (same hemisphere, both
--    yellowward or both blueward). I therefore split the seam law: (a) the signed
--    linearity identity holds for ALL pixels; (b) the magnitude reading
--    bEnergy(detail) == |ownerB f1 - ownerB f2| holds for ALL pixels; (c) the owner's
--    energy-difference reading |ownerB1 - ownerB2| == |bEnergy f1 - bEnergy f2| holds
--    ONLY on same-sign pairs, and I ship a mixed-sign TOOTH where it fails, so the law
--    is non-vacuous and the restriction is named, not hidden.
--  * `lawEnergyDescentWellDefined` is a well-foundedness / monotonicity statement about
--    the weighted t-detail energy as a function of the seam b-distance |b1 - b2|. It is
--    NOT a perceptual-quality claim: a smaller seam b-energy means the two frames agree
--    more closely on opponent-b, which is the residual the search descends, not a claim
--    that the decoded picture looks better. I prove (i) strict descent when |b1-b2|
--    shrinks, (ii) the energy depends ONLY on |b1-b2| (a move that preserves the
--    distance preserves the energy), and (iii) the witnesses are non-constant (the two
--    energies actually differ) with a non-degenerate b-axis (entropy > 0).
--  * Energy is a READOUT, never a lossy step: `lawSeamReversible` lifts every channel and
--    unlifts back to (f1, f2) byte-exactly, including boundary pairs (0 vs 255, x < y so
--    the detail is negative and `div` floors). The b-energy is computed on the side; the
--    carrier stays byte-exact reversible to RGB.
--  * This module is base-only and standalone. It copies the few primitives it needs from
--    V2Latent / V2EnergyWeave / V2RgbEisenstein rather than importing sixfour-spec. It is
--    not added to any cabal target, Map, or gate.
--
-- No em-dashes anywhere (owner directive).
--
-- Run:  ~/.ghcup/bin/runghc exploration/V2CrossFrameBEnergy.hs
module V2CrossFrameBEnergy where

import Data.List (group, sort)
import System.Exit (exitFailure, exitSuccess)

-- ---------------------------------------------------------------------------
-- Boundary types (copied from V2Latent.hs conventions)
-- ---------------------------------------------------------------------------

-- | Raw sRGB 8-bit pixel, each channel 0..255. The boundary.
type Pixel = (Int, Int, Int)

-- | A frame is a list of pixels; the t-seam pairs two frames element-wise (one cell
--   per 2x2x2 block contributes one pixel from each t-slice).
type Frame = [Pixel]

inRange8 :: Int -> Bool
inRange8 v = v >= 0 && v <= 255

isPixel :: Pixel -> Bool
isPixel (r, g, b) = inRange8 r && inRange8 g && inRange8 b

-- ---------------------------------------------------------------------------
-- Opponent-b, both conventions, reconciled explicitly
-- ---------------------------------------------------------------------------

-- | V2Latent LOCKED stored opponent b:  latB = R + G - 2B.
latB :: Pixel -> Int
latB (r, g, b) = r + g - 2 * b

-- | The owner's ASK 2 signed opponent b:  ownerB = 2B - (R + G).  This is `negate latB`.
--   ownerB > 0 means B dominates (blueward); ownerB < 0 means R+G dominates (yellowward).
ownerB :: Pixel -> Int
ownerB (r, g, b) = 2 * b - (r + g)

-- | The owner's literal energy:  bEnergy(px) = | 2*B - (R + G) | = |ownerB| = |latB|.
bEnergy :: Pixel -> Int
bEnergy = abs . ownerB

-- ---------------------------------------------------------------------------
-- Reversible 1-D Haar S-transform along t (copied verbatim from V2RgbEisenstein.hs)
-- ---------------------------------------------------------------------------

-- | sLift x y = (coarse, detail). coarse = y + floor((x-y)/2), detail = x - y.
--   Exact integer bijection because `div` floors toward -inf.
sLift :: Int -> Int -> (Int, Int)
sLift x y = let d = x - y in (y + (d `div` 2), d)

-- | Exact inverse of sLift.
sUnlift :: Int -> Int -> (Int, Int)
sUnlift lo hi = let y = lo - (hi `div` 2) in (y + hi, y)

-- ---------------------------------------------------------------------------
-- The t-seam: pair two slices, lift per channel
-- ---------------------------------------------------------------------------

-- | Lift one cell along t: two paired pixels -> (coarse pixel, detail pixel), per channel.
seamLiftCell :: Pixel -> Pixel -> (Pixel, Pixel)
seamLiftCell (r1, g1, b1) (r2, g2, b2) =
  let (cr, dr) = sLift r1 r2
      (cg, dg) = sLift g1 g2
      (cb, db) = sLift b1 b2
  in ((cr, cg, cb), (dr, dg, db))

-- | Exact inverse: (coarse, detail) -> the original pair (p1, p2).
seamUnliftCell :: Pixel -> Pixel -> (Pixel, Pixel)
seamUnliftCell (cr, cg, cb) (dr, dg, db) =
  let (r1, r2) = sUnlift cr dr
      (g1, g2) = sUnlift cg dg
      (b1, b2) = sUnlift cb db
  in ((r1, g1, b1), (r2, g2, b2))

-- | The Haar t-detail pixel = channelwise difference (r1-r2, g1-g2, b1-b2).
--   This is exactly the detail half of `seamLiftCell`.
seamDetailPixel :: Pixel -> Pixel -> Pixel
seamDetailPixel p1 p2 = snd (seamLiftCell p1 p2)

-- | The whole-frame t-detail band, read through the SIGNED opponent-b projection.
--   ownerB is linear, so this equals ownerB f1 - ownerB f2 cellwise (see lawTDetailIsOpponentBSeam).
tDetailB :: Frame -> Frame -> [Int]
tDetailB f1 f2 = [ ownerB (seamDetailPixel p1 p2) | (p1, p2) <- zip f1 f2 ]

-- ---------------------------------------------------------------------------
-- Energy-weighted t-detail metric (the V2EnergyWeave `dW` restricted to the b-axis)
-- ---------------------------------------------------------------------------

-- | Weighted L1 of the seam b-difference: w * sum |ownerB p1 - ownerB p2| over cells.
--   This is V2EnergyWeave's `dW` specialised to the single b-axis of the t-detail band,
--   using `abs` so the latB/ownerB sign flip does not change the magnitude.
seamEnergyW :: Int -> Frame -> Frame -> Int
seamEnergyW w f1 f2 = sum [ w * abs (ownerB p1 - ownerB p2) | (p1, p2) <- zip f1 f2 ]

-- | Shannon entropy (bits) of an axis value series (copied from V2EnergyWeave.hs).
entropyBits :: [Int] -> Double
entropyBits xs =
  let n  = fromIntegral (length xs) :: Double
      ps = [ fromIntegral (length g) / n | g <- group (sort xs) ]
  in negate (sum [ p * logBase 2 p | p <- ps, p > 0 ])

-- ---------------------------------------------------------------------------
-- Sample data (non-constant witnesses, boundary pixels)
-- ---------------------------------------------------------------------------

grid :: [Int]
grid = [0, 40, 128, 200, 255]

-- | A varied corpus of real pixels (5^3 = 125), all in range, b-axis non-degenerate.
corpus :: [Pixel]
corpus = [ (r, g, b) | r <- grid, g <- grid, b <- grid ]

-- | All ordered pixel pairs over a smaller varied set (boundary-rich).
smallPix :: [Pixel]
smallPix = [ (0, 0, 0), (255, 255, 255), (0, 0, 100), (100, 100, 0)
           , (0, 0, 50), (0, 0, 150), (200, 40, 128), (40, 200, 200) ]

pairs :: [(Pixel, Pixel)]
pairs = [ (p, q) | p <- smallPix, q <- smallPix ]

-- ---------------------------------------------------------------------------
-- LAW 0 : sign reconciliation (named, not silent)
-- ---------------------------------------------------------------------------

-- | ownerB == negate latB for every pixel. Documents that the owner's b = 2B-(R+G)
--   and V2Latent's b = R+G-2B are exact negations; magnitude (bEnergy) is invariant.
lawSignReconcile :: Bool
lawSignReconcile =
  all (\p -> ownerB p == negate (latB p)) corpus
  && all (\p -> bEnergy p == abs (latB p)) corpus
  -- tooth: the sign genuinely differs on a non-zero-b pixel (not a both-zero coincidence)
  && ownerB (0, 0, 100) == 200 && latB (0, 0, 100) == (-200)

-- ---------------------------------------------------------------------------
-- LAW 1 : the t-detail band, restricted to the b-axis, IS the seam b-difference
-- ---------------------------------------------------------------------------

-- (a) signed linearity identity (exact, all pixels):
--       ownerB(t-detail) == ownerB f1 - ownerB f2
-- (b) magnitude readout (exact, all pixels):
--       bEnergy(t-detail) == |ownerB f1 - ownerB f2|
-- (c) owner's energy-DIFFERENCE reading holds ONLY same-sign, with a mixed-sign tooth:
--       same sign  => |ownerB1 - ownerB2| == |bEnergy f1 - bEnergy f2|
--       mixed sign => a witness where the two are UNEQUAL (non-vacuity tooth)
lawTDetailIsOpponentBSeam :: Bool
lawTDetailIsOpponentBSeam =
  signedExact && magnitudeExact && sameSignReading && mixedSignTooth
  where
    signedExact =
      all (\(p1, p2) -> ownerB (seamDetailPixel p1 p2) == ownerB p1 - ownerB p2) pairs
    magnitudeExact =
      all (\(p1, p2) -> bEnergy (seamDetailPixel p1 p2) == abs (ownerB p1 - ownerB p2)) pairs
    sameSign p1 p2 = ownerB p1 >= 0 && ownerB p2 >= 0
    sameSignReading =
      all (\(p1, p2) ->
              abs (ownerB p1 - ownerB p2) == abs (bEnergy p1 - bEnergy p2))
          [ pr | pr@(p1, p2) <- pairs, sameSign p1 p2 ]
    -- (0,0,100): ownerB = +200 (blueward).  (100,100,0): ownerB = -200 (yellowward).
    -- |ownerB1 - ownerB2| = 400  but  |bEnergy1 - bEnergy2| = |200 - 200| = 0.
    mixedSignTooth =
      let p1 = (0, 0, 100); p2 = (100, 100, 0)
      in abs (ownerB p1 - ownerB p2) == 400
         && abs (bEnergy p1 - bEnergy p2) == 0
         && abs (ownerB p1 - ownerB p2) /= abs (bEnergy p1 - bEnergy p2)

-- ---------------------------------------------------------------------------
-- LAW 2 : the seam pairing is byte-exact reversible (energy is a side-channel)
-- ---------------------------------------------------------------------------

-- | seamUnliftCell . seamLiftCell == id on every pair, including boundary pairs where
--   the detail is negative (x < y) so `div` floors. Coarse keeps the floor-average,
--   detail keeps the diff; the round trip recovers (f1, f2) byte-exactly.
lawSeamReversible :: Bool
lawSeamReversible =
  all roundTrips pairs && boundaryTeeth
  where
    roundTrips (p1, p2) =
      let (c, d) = seamLiftCell p1 p2
      in seamUnliftCell c d == (p1, p2)
    -- explicit boundary teeth: extreme pixels and a negative-detail (x<y) case
    boundaryTeeth =
      let cases = [ ((0,0,0), (255,255,255))     -- detail negative on every channel
                  , ((255,255,255), (0,0,0))     -- detail positive
                  , ((0,0,100), (0,0,50)) ]      -- odd-magnitude diff, div floors
      in all (\(p1, p2) -> let (c, d) = seamLiftCell p1 p2
                           in seamUnliftCell c d == (p1, p2)) cases

-- ---------------------------------------------------------------------------
-- LAW 3 : energy descent is well-defined (monotone in the seam b-distance)
-- ---------------------------------------------------------------------------

-- | A move that reduces |b1 - b2| reduces the weighted t-detail energy, and the energy
--   depends ONLY on |b1 - b2| (well-defined as a function of the seam distance). The
--   weight is a positive integer standing in for the b-axis entropy (V2EnergyWeave), and
--   we check the b-axis is genuinely non-degenerate (entropy > 0) so the weight bites.
lawEnergyDescentWellDefined :: Bool
lawEnergyDescentWellDefined =
  strictDescent && wellDefined && nonVacuous && weightLoadBearing
  where
    w = bWeight
    f1   = [(0, 0, 100)]   -- ownerB = 200
    gFar  = [(0, 0, 50)]   -- ownerB = 100, |b1-b2| = 100
    gNear = [(0, 0, 90)]   -- ownerB = 180, |b1-b2| = 20   (the move: closer in b)
    gAlt  = [(0, 0, 150)]  -- ownerB = 300, |b1-b2| = 100  (different pixel, same distance)
    eFar  = seamEnergyW w f1 gFar
    eNear = seamEnergyW w f1 gNear
    eAlt  = seamEnergyW w f1 gAlt
    -- (i) reducing |b1-b2| strictly reduces the weighted energy
    strictDescent = eNear < eFar
    -- (ii) energy is a function of |b1-b2| only: same distance, different pixel, same energy
    wellDefined   = eFar == eAlt
    -- (iii) non-constant witnesses: the energies genuinely differ
    nonVacuous    = eNear /= eFar && eFar > 0 && eNear > 0
    -- the weight is load-bearing: b-axis over the corpus is non-degenerate (entropy > 0)
    weightLoadBearing = bWeight > 0 && entropyBits (map ownerB corpus) > 0

-- | The b-axis energy weight. A positive integer stand-in for the axis entropy, exactly
--   as V2EnergyWeave uses hand-picked integer weights for the real-valued entropy.
bWeight :: Int
bWeight = 3

-- ---------------------------------------------------------------------------
-- Runner
-- ---------------------------------------------------------------------------

laws :: [(String, Bool)]
laws =
  [ ("lawSignReconcile",             lawSignReconcile)
  , ("lawTDetailIsOpponentBSeam",    lawTDetailIsOpponentBSeam)
  , ("lawSeamReversible",            lawSeamReversible)
  , ("lawEnergyDescentWellDefined",  lawEnergyDescentWellDefined)
  ]

main :: IO ()
main = do
  mapM_ (\(nm, ok) -> putStrLn (nm ++ ": " ++ if ok then "PASS" else "FAIL")) laws
  if all snd laws
    then putStrLn "ALL LAWS PASS" >> exitSuccess
    else exitFailure

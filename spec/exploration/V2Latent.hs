{- |
Module      : V2Latent
Description : EXPLORATION (NOT WIRED, base-only, runghc). THE LOCKED V2 LATENT TYPE. Q1 RESOLVED
              (2026-06-29): the latent is OPPONENT-LITERAL. The bytes the model stores and explores
              ARE the opponent axes (L=R+G+B, a=R-G, b=R+G-2B) plus position (x,y,t). sRGB 8-bit is
              the BOUNDARY only (encode in, decode/export out). This is the canonical type the energy
              metric, the SKI search, and the CNN wiring all reference.

  Check:  runghc V2Latent.hs

  THE LOCK (owner directive: "lock the latent type"):
    * BOUNDARY  = sRGB 8-bit. The encoder takes raw sRGB and MAKES the (L,a,b) representation; the
      decoder exports sRGB at 16^3 and 256^3. Lab is deprecated entirely.
    * LATENT (stored, explored) = the 6 opponent axes: colour (L, a, b) + position (x, y, t). This is
      OPPONENT-LITERAL: the bytes ARE (R+G+B, R-G, R+G-2B), not RGB-with-a-view. The model reasons in
      these axes (energy, search, wiring); the 6 fields ARE the 6 CNN input channels.
    * The colour decode is invert-or-refuse on the index-6 lattice ((L-b) == 0 mod 3 AND a+b even, the
      6 = 3*2 byte-exactness congruences). A nudge that lands a colour OFF the lattice is SNAPPED back
      on (snapColour) before commit, so byte-exactness is never lost.
    * The Eisenstein A2 hexagonal lens stays DERIVED for analysis, never stored (V2EncodeDecodeBoundary).

  Supersedes the tuple form of V2EncodeDecodeBoundary with a named record. Same arithmetic (det 6).
  Base-only, runghc, NOT in cabal/Map/gate. Trainer untouched.
-}
module V2Latent where

-- ===========================================================================
-- (1) The boundary type and THE LOCKED latent type
-- ===========================================================================

-- | The BOUNDARY representation: raw sRGB 8-bit (each channel 0..255).
type SRGB8 = (Int, Int, Int)

-- | A position in the (x, y, t) box (which voxel / frame).
type Pos = (Int, Int, Int)

-- | THE LOCKED V2 LATENT: opponent colour (L, a, b) + position (x, y, t). The 6 fields are the 6 CNN
--   input channels. OPPONENT-LITERAL: the colour fields ARE (R+G+B, R-G, R+G-2B), no green-blue.
data Latent = Latent
  { latL :: !Int   -- ^ luma        = R + G + B   (the achromatic axis)
  , latA :: !Int   -- ^ red-green    = R - G       (a>0 redward, a<0 greenward)
  , latB :: !Int   -- ^ yellow-blue  = R + G - 2B  (b>0 yellowward, b<0 blueward; yellow = R+G)
  , latX :: !Int   -- ^ position x
  , latY :: !Int   -- ^ position y
  , latT :: !Int   -- ^ frame t
  } deriving (Eq, Show)

-- | The 6 latent channels as a vector (the CNN input; matches V2ModelWiring.inputChannels = 6).
channels :: Latent -> [Int]
channels (Latent l a b x y t) = [l, a, b, x, y, t]

latentChannelCount :: Int
latentChannelCount = 6

-- ===========================================================================
-- (2) Encode (sRGB -> latent) and decode (latent -> sRGB), the boundary
-- ===========================================================================

inRange8 :: Int -> Bool
inRange8 v = v >= 0 && v <= 255

isSRGB8 :: SRGB8 -> Bool
isSRGB8 (r, g, b) = all inRange8 [r, g, b]

-- | ENCODE: the encoder takes raw sRGB plus a position and MAKES the opponent latent. Total.
encodeAt :: SRGB8 -> Pos -> Latent
encodeAt (r, g, b) (x, y, t) = Latent (r + g + b) (r - g) (r + g - 2 * b) x y t

-- | Is the COLOUR part of a latent on the index-6 lattice (does it invert to integer sRGB)? Two
--   independent congruences: (L - b) divisible by 3, AND a + b even. Every real pixel satisfies both.
onLattice :: Latent -> Bool
onLattice (Latent l a b _ _ _) = (l - b) `mod` 3 == 0 && (a + b) `mod` 2 == 0

-- | DECODE / EXPORT: recover the sRGB colour from a latent (the position is metadata, not decoded).
--   Invert-or-refuse: R=(2L+3a+b)/6, G=(2L-3a+b)/6, B=(L-b)/3, refusing off-lattice or out of 0..255.
decode :: Latent -> Maybe SRGB8
decode lat@(Latent l a b _ _ _)
  | not (onLattice lat) = Nothing
  | not (isSRGB8 px)    = Nothing
  | otherwise           = Just px
  where
    rr = (2 * l + 3 * a + b) `div` 6
    gg = (2 * l - 3 * a + b) `div` 6
    bb = (l - b) `div` 3
    px = (rr, gg, bb)

-- ===========================================================================
-- (3) Snap: project an off-lattice (nudged) colour back onto the lattice
-- ===========================================================================

-- | A nudge in latent space can land the colour OFF the index-6 lattice. snapColour projects it back
--   on (so byte-exactness is never lost): first make a+b even (adjust b), then (L-b) == 0 mod 3 (adjust
--   L). Lands ON the lattice; this is a valid projection, not necessarily the true nearest point.
snapColour :: Latent -> Latent
snapColour (Latent l a b x y t) =
  let b' = if (a + b) `mod` 2 == 0 then b else b + 1     -- parity guard (a + b even)
      l' = l - ((l - b') `mod` 3)                        -- mod-3 guard ((L - b) == 0 mod 3)
  in Latent l' a b' x y t

-- ===========================================================================
-- (4) Sample data
-- ===========================================================================

grid :: [Int]
grid = [0, 1, 15, 16, 127, 128, 200, 254, 255]

cube :: [SRGB8]
cube = [(r, g, b) | r <- grid, g <- grid, b <- grid]

pos0 :: Pos
pos0 = (3, 4, 5)

-- ===========================================================================
-- (5) Laws
-- ===========================================================================

-- | THE BOUNDARY ROUND TRIPS: encode then decode recovers the sRGB colour exactly, for every pixel.
lawEncodeDecodeRoundTrip :: Bool
lawEncodeDecodeRoundTrip = all (\px -> decode (encodeAt px pos0) == Just px) cube

-- | THE LATENT IS OPPONENT-LITERAL: the colour fields ARE (R+G+B, R-G, R+G-2B), position passes
--   through. Gray collapses to (a, b) = (0, 0). The 6 fields are the model's channels.
lawLatentIsOpponent :: Bool
lawLatentIsOpponent =
     all (\px@(r, g, b) -> let lt = encodeAt px pos0
                           in latL lt == r + g + b && latA lt == r - g && latB lt == r + g - 2 * b) cube
  && (let lt = encodeAt (3, 4, 5) (7, 8, 9) in (latX lt, latY lt, latT lt) == (7, 8, 9))  -- position kept
  && all (\k -> let lt = encodeAt (k, k, k) pos0 in (latA lt, latB lt) == (0, 0)) grid     -- gray -> 0 chroma
  && length (channels (encodeAt (1, 2, 3) pos0)) == 6                                       -- 6 CNN channels

-- | DECODE REFUSES off the index-6 lattice, with BOTH congruence guards toothed: a mod-3 failure and a
--   parity failure each refuse; every real pixel is on the lattice.
lawDecodeRefusesOffLattice :: Bool
lawDecodeRefusesOffLattice =
     decode (Latent 1 0 0 0 0 0) == Nothing            -- (L-b)=1 not div 3 (mod-3 guard)
  && decode (Latent 0 1 0 0 0 0) == Nothing            -- a+b=1 odd (parity guard)
  && all (\px -> onLattice (encodeAt px pos0)) cube      -- every real pixel on the lattice

-- | SNAP LANDS ON THE LATTICE: a nudged off-lattice colour, snapped, is on the lattice and decodes
--   (when in range). So a latent-space nudge never loses byte-exactness.
lawSnapLandsOnLattice :: Bool
lawSnapLandsOnLattice =
     all (\lt -> onLattice (snapColour lt)) offs
  && onLattice (snapColour (Latent 1 1 0 0 0 0))         -- both guards fired at once
  && snapColour (encodeAt (100, 50, 20) pos0) == encodeAt (100, 50, 20) pos0   -- on-lattice -> unchanged
  where offs = [ Latent l a b 0 0 0 | l <- [0 .. 9], a <- [-3 .. 3], b <- [-3 .. 3] ]

-- | THE LOCK is internally consistent: the 6 latent channels match the CNN input channel count, and
--   the latent is a faithful renaming of the V2EncodeDecodeBoundary opponent tuple (same arithmetic).
lawLockConsistent :: Bool
lawLockConsistent =
     latentChannelCount == 6
  && all (\px -> let Latent l a b _ _ _ = encodeAt px pos0
                 in (l, a, b) == (let (r, g, bb) = px in (r + g + bb, r - g, r + g - 2 * bb))) cube

-- ===========================================================================
-- (6) Runner
-- ===========================================================================

laws :: [(String, Bool)]
laws =
  [ ("lawEncodeDecodeRoundTrip   (sRGB -> latent -> sRGB is identity)",       lawEncodeDecodeRoundTrip)
  , ("lawLatentIsOpponent        (latent = L,a,b + x,y,t, opponent-literal)", lawLatentIsOpponent)
  , ("lawDecodeRefusesOffLattice (index-6 guards: mod-3 AND parity, teeth)",  lawDecodeRefusesOffLattice)
  , ("lawSnapLandsOnLattice      (nudge off-lattice -> snapped on, byte-exact)", lawSnapLandsOnLattice)
  , ("lawLockConsistent          (6 channels; faithful to the boundary)",     lawLockConsistent)
  ]

main :: IO ()
main = do
  putStrLn "V2Latent.hs  -- EXPLORATION (NOT WIRED): THE LOCKED V2 LATENT TYPE (opponent-literal)"
  putStrLn (replicate 72 '-')
  mapM_ (\(n, ok) -> putStrLn (verdict ok ++ "  " ++ n)) laws
  putStrLn (replicate 72 '-')
  let passed = length (filter snd laws); total = length laws
  putStrLn ("SUMMARY: " ++ show passed ++ "/" ++ show total ++ " laws PASS"
            ++ if passed == total then "  (all green)" else "  (FAILURES present)")
  putStrLn ""
  let lt = encodeAt (200, 50, 10) (3, 4, 5)
  putStrLn ("encodeAt (200,50,10) (3,4,5) = " ++ show lt)
  putStrLn ("channels (CNN input)         = " ++ show (channels lt))
  putStrLn ("decode                       = " ++ show (decode lt))
  putStrLn ""
  putStrLn "LOCKED (Q1 resolved): the latent is OPPONENT-LITERAL. The bytes ARE (L=R+G+B, a=R-G,"
  putStrLn "b=R+G-2B) + (x,y,t). sRGB only at the boundary. The 6 fields = the 6 CNN channels. A"
  putStrLn "latent nudge off the index-6 lattice is snapped back on; byte-exactness is never lost."
  where
    verdict True  = "PASS"
    verdict False = "FAIL"

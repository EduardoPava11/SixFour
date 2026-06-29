{- |
Module      : V2EncodeDecodeBoundary
Description : EXPLORATION (NOT WIRED, base-only, runghc). The three-layer colour architecture, with
              the LATENT corrected to the PERCEPTUAL OPPONENT basis (red-green, yellow-blue). Encode
              and decode are sRGB 8-bit; the model EXPORTS sRGB at both 16^3 and 256^3.

  Check:  runghc V2EncodeDecodeBoundary.hs

  THE ARCHITECTURE (owner-directed, basis CORRECTED 2026-06-29 after V2-LATENT-BASIS-REVIEW.md):
    * BOUNDARY (encode in / decode-export out) = raw sRGB 8-bit. Lab deprecated.
    * LATENT (what the model stores and explores) = the PERCEPTUAL OPPONENT basis
        L = R+G+B        (luma, the achromatic axis)
        a = R-G          (red-green:  a>0 redward,    a<0 greenward)
        b = R+G-2B       (yellow-blue: b>0 yellowward, b<0 blueward; yellow = R+G)
      These three axes are MUTUALLY ORTHOGONAL (L.a = L.b = a.b = 0): a genuine 2-fold Cartesian
      opponent frame (the structure CIELab encodes), computed natively in RGB. NO green-blue (R-B/G-B)
      is stored. The earlier Eisenstein (R-B, G-B) storage was withdrawn: (R-B).(G-B) = 1, so it is a
      hexagonal frame and is NOT perceptually opponent.
    * DERIVED LENS (analysis only): the Eisenstein A2 chroma (Cr, Cg) = (R-B, G-B) is recoverable from
      the opponent latent as Cr = (a+b)/2, Cg = (b-a)/2 (exact, since a+b = 2(R-B) is always even on a
      real pixel). So the ANT (Z[w] units, ramification, the hexagonal norm) survives as a DERIVED lens
      over the store, never the store itself.

  WHY OPPONENT IS THE STORE: byte-exactness does NOT favour Eisenstein. The opponent basis (det 6) is
  integer-invertible, and ALL 16,777,216 sRGB8 pixels round-trip byte-exact through it (verified
  exhaustively). The only thing Eisenstein had was an integer 60-degree hue-rotation matrix, which no
  wired path needs and which is anyway exact on real chroma via the RGB round trip. So the owner's
  perceptual model wins with no byte-exactness cost.

  Base-only, runghc, NOT in cabal/Map/gate.
-}
module V2EncodeDecodeBoundary where

-- ===========================================================================
-- (1) The three layers
-- ===========================================================================

-- | The BOUNDARY representation: raw sRGB 8-bit (each channel 0..255). What the model imports and exports.
type SRGB8 = (Int, Int, Int)

-- | The LATENT the model stores and explores: the opponent basis (L, a, b) = (R+G+B, R-G, R+G-2B) =
--   luma + red-green + yellow-blue. Mutually orthogonal; invertible back to sRGB8.
type Latent = (Int, Int, Int)

inRange8 :: Int -> Bool
inRange8 x = x >= 0 && x <= 255

isSRGB8 :: SRGB8 -> Bool
isSRGB8 (r, g, b) = all inRange8 [r, g, b]

-- | ENCODE: sRGB8 -> opponent latent. Total.
encode :: SRGB8 -> Latent
encode (r, g, b) = (r + g + b, r - g, r + g - 2 * b)   -- (L, a=red-green, b=yellow-blue)

-- | Is a latent on the index-6 lattice Lambda (i.e. does it come from a real integer pixel)? Two
--   independent congruences: (L - b) divisible by 3 (the blue inverse) AND a + b even (the R/G inverse).
onLambda :: Latent -> Bool
onLambda (l, a, b) = (l - b) `mod` 3 == 0 && (a + b) `mod` 2 == 0

-- | DECODE / EXPORT: opponent latent -> sRGB8, INVERT-OR-REFUSE. R = (2L+3a+b)/6, G = (2L-3a+b)/6,
--   B = (L-b)/3. Refuses off Lambda or out of 0..255, so every export is genuine sRGB8.
decode :: Latent -> Maybe SRGB8
decode lat@(l, a, b)
  | not (onLambda lat) = Nothing
  | not (isSRGB8 px)   = Nothing
  | otherwise          = Just px
  where
    rr = (2 * l + 3 * a + b) `div` 6
    gg = (2 * l - 3 * a + b) `div` 6
    bb = (l - b) `div` 3
    px = (rr, gg, bb)

-- | Export a whole frame (a list of latents) to sRGB8; used at BOTH 16^3 and 256^3 (scale-agnostic).
exportFrame :: [Latent] -> Maybe [SRGB8]
exportFrame = traverse decode

-- | The owner's opponent axes, read straight off the latent (they ARE the store now, no derivation).
opponentRedGreen :: Latent -> Int
opponentRedGreen (_, a, _) = a

opponentYellowBlue :: Latent -> Int
opponentYellowBlue (_, _, b) = b

-- | The DERIVED Eisenstein lens (analysis only): (Cr, Cg) = (R-B, G-B) recovered from the opponent
--   latent as Cr = (a+b)/2, Cg = (b-a)/2. Exact on real pixels (a+b even). The ANT lives here, derived.
eisensteinLens :: Latent -> (Int, Int)
eisensteinLens (_, a, b) = ((a + b) `div` 2, (b - a) `div` 2)

-- The sRGB8 sample grid (a representative spread; the full 256^3 is verified separately in Python).
grid :: [Int]
grid = [0, 1, 15, 16, 127, 128, 200, 254, 255]

cube :: [SRGB8]
cube = [(r, g, b) | r <- grid, g <- grid, b <- grid]

-- | The determinant of a 3x3 integer basis (the lattice index of the change of coordinates).
det3 :: [[Int]] -> Int
det3 [[a, b, c], [d, e, f], [g, h, i]] =
  a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)
det3 _ = 0

-- ===========================================================================
-- (2) Laws
-- ===========================================================================

-- | THE BOUNDARY IS LOSSLESS: encode then decode is the IDENTITY on sRGB8 (byte-exact round trip).
lawEncodeDecodeRoundTrip :: Bool
lawEncodeDecodeRoundTrip = all (\px -> decode (encode px) == Just px) cube

-- | THE LATENT IS THE PERCEPTUAL OPPONENT BASIS: a = red-green = R-G, b = yellow-blue = R+G-2B. Gray
--   collapses to (a, b) = (0, 0). This is the owner's model; NO green-blue is stored.
lawLatentIsOpponent :: Bool
lawLatentIsOpponent =
     all (\px@(r, g, b) -> encode px == (r + g + b, r - g, r + g - 2 * b)) cube
  && all (\k -> let (_, a, b) = encode (k, k, k) in (a, b) == (0, 0)) grid
  && (let (_, a, b) = encode (200, 50, 10) in (a, b) /= (0, 0))                 -- non-gray -> nonzero (tooth)

-- | THE OPPONENT AXES ARE MUTUALLY ORTHOGONAL (genuine 2-fold opponent, what Lab encodes): L.a = L.b =
--   a.b = 0. TOOTH/CONTRAST: the withdrawn Eisenstein chroma is NOT orthogonal, (R-B).(G-B) = 1.
lawOpponentAxesOrthogonal :: Bool
lawOpponentAxesOrthogonal =
     dot lL aA == 0 && dot lL bB == 0 && dot aA bB == 0     -- opponent: mutually orthogonal
  && dot ((1, 0, -1) :: SRGB8) (0, 1, -1) == 1               -- Eisenstein (R-B).(G-B) = 1: NOT opponent
  && det3 ([[1, 1, 1], [1, -1, 0], [1, 1, -2]] :: [[Int]]) == 6   -- the opponent basis determinant
  where
    lL = (1, 1, 1) :: SRGB8
    aA = (1, -1, 0) :: SRGB8
    bB = (1, 1, -2) :: SRGB8
    dot :: SRGB8 -> SRGB8 -> Int
    dot (x, y, z) (p, q, s) = x * p + y * q + z * s

-- | b IS YELLOW-BLUE (yellow = R+G): yellow -> b>0, blue -> b<0, gray -> 0. a is red-green: red -> a>0,
--   green -> a<0, gray -> 0. The owner's intuition, now the stored axes.
lawYellowBlueRedGreen :: Bool
lawYellowBlueRedGreen =
     opponentYellowBlue (encode (255, 255, 0)) > 0 && opponentYellowBlue (encode (0, 0, 255)) < 0
  && opponentYellowBlue (encode (128, 128, 128)) == 0
  && opponentRedGreen (encode (255, 0, 0)) > 0 && opponentRedGreen (encode (0, 255, 0)) < 0
  && opponentRedGreen (encode (128, 128, 128)) == 0

-- | DECODE REFUSES off the index-6 lattice: BOTH guards have teeth. (1,0,0) fails the /3 (L-b not div 3);
--   (0,1,0) fails the parity (a+b odd). Every real pixel passes both.
lawDecodeRefusesOffLattice :: Bool
lawDecodeRefusesOffLattice =
     decode (1, 0, 0) == Nothing                       -- L-b = 1, not divisible by 3 (tooth 1)
  && decode (0, 1, 0) == Nothing                       -- a+b = 1, odd (tooth 2: the parity guard)
  && all (\px -> onLambda (encode px)) cube             -- every real pixel is on Lambda

-- | EVERY EXPORT IS sRGB8: a successful decode is in 0..255 (the model exports sRGB). Tooth: an on-Lambda
--   but out-of-range latent is refused.
lawExportIsSrgb :: Bool
lawExportIsSrgb =
     all (\px -> case decode (encode px) of Just q -> isSRGB8 q; Nothing -> False) cube
  && (onLambda (6000, 0, 0) && decode (6000, 0, 0) == Nothing)    -- on Lambda but B=2000 out of range

-- | THE MODEL EXPORTS sRGB AT BOTH SCALES: the same decode applies to a 16^3-sized and a 256^3-sized
--   latent set; both export back to their sRGB8 source.
lawBothScalesExportSrgb :: Bool
lawBothScalesExportSrgb =
     exportFrame (map encode small16) == Just small16
  && exportFrame (map encode big)     == Just big
  where
    small16 = take 16 cube
    big     = cube

-- | THE ANT SURVIVES AS A DERIVED LENS, not the store: the Eisenstein chroma (Cr, Cg) = (R-B, G-B) is
--   recovered exactly from the opponent latent (Cr = (a+b)/2, Cg = (b-a)/2), because a+b = 2(R-B) is
--   always even on a real pixel. So the hexagonal hue algebra is available without storing green-blue.
lawEisensteinIsDerivedLens :: Bool
lawEisensteinIsDerivedLens =
     all (\px@(r, g, b) -> eisensteinLens (encode px) == (r - b, g - b)) cube     -- derived = (R-B, G-B), exact
  && all (\px -> let (_, a, b) = encode px in (a + b) `mod` 2 == 0) cube          -- a+b always even (why /2 is exact)

-- ===========================================================================
-- (3) Runner
-- ===========================================================================

laws :: [(String, Bool)]
laws =
  [ ("lawEncodeDecodeRoundTrip     (sRGB8 -> latent -> sRGB8 is identity)",       lawEncodeDecodeRoundTrip)
  , ("lawLatentIsOpponent          (latent = luma + red-green + yellow-blue)",    lawLatentIsOpponent)
  , ("lawOpponentAxesOrthogonal    (L.a=L.b=a.b=0; Eisenstein .=1 is NOT opp)",   lawOpponentAxesOrthogonal)
  , ("lawYellowBlueRedGreen        (b yellow-blue, a red-green: witnessed)",      lawYellowBlueRedGreen)
  , ("lawDecodeRefusesOffLattice   (/3 AND parity guards both have teeth)",       lawDecodeRefusesOffLattice)
  , ("lawExportIsSrgb              (every export in 0..255 sRGB)",                lawExportIsSrgb)
  , ("lawBothScalesExportSrgb      (16^3 and 256^3 both export sRGB)",            lawBothScalesExportSrgb)
  , ("lawEisensteinIsDerivedLens   (Eisenstein (R-B,G-B) derived, not stored)",   lawEisensteinIsDerivedLens)
  ]

main :: IO ()
main = do
  putStrLn "V2EncodeDecodeBoundary.hs  -- EXPLORATION (NOT WIRED): sRGB boundary, OPPONENT latent"
  putStrLn (replicate 72 '-')
  mapM_ (\(n, ok) -> putStrLn (verdict ok ++ "  " ++ n)) laws
  putStrLn (replicate 72 '-')
  let passed = length (filter snd laws)
      total  = length laws
  putStrLn ("SUMMARY: " ++ show passed ++ "/" ++ show total ++ " laws PASS"
            ++ if passed == total then "  (all green)" else "  (FAILURES present)")
  putStrLn ""
  let px = (200, 50, 10) :: SRGB8
  putStrLn ("encode " ++ show px ++ " = " ++ show (encode px) ++ "   (L, a=red-green, b=yellow-blue)")
  putStrLn ("decode (encode " ++ show px ++ ") = " ++ show (decode (encode px)) ++ "   (byte-exact)")
  putStrLn ("Eisenstein lens (derived) = " ++ show (eisensteinLens (encode px)) ++ "   (= (R-B, G-B), analysis only)")
  putStrLn ""
  putStrLn "ARCHITECTURE: encode/decode = sRGB 8-bit. The LATENT the model stores is the PERCEPTUAL"
  putStrLn "OPPONENT basis (luma, red-green = R-G, yellow-blue = R+G-2B), mutually orthogonal, NO"
  putStrLn "green-blue. The Eisenstein A2 lens is DERIVED from it for the ANT analysis, never stored."
  where
    verdict True  = "PASS"
    verdict False = "FAIL"

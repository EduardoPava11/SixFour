{- |
Module      : V2EncodeDecodeBoundary
Description : EXPLORATION (NOT WIRED, base-only, runghc). The three-layer colour architecture:
              ENCODE and DECODE are sRGB 8-bit; the LATENT is the opponent decomposition the model
              explores. The model EXPORTS sRGB values at both 16^3 and 256^3. Byte-exact round trip.

  Check:  runghc V2EncodeDecodeBoundary.hs

  THE ARCHITECTURE (owner directive 2026-06-29):
    * BOUNDARY (encode in / decode-export out) = raw sRGB 8-bit. The model imports sRGB8 and EXPORTS
      sRGB8 when it creates the 16^3 and the 256^3. Lab is deprecated from the boundary entirely.
    * LATENT (where the model explores / searches) = the opponent decomposition (L, Cr, Cg) =
      (R+G+B, R-B, G-B) = luma + Eisenstein A2 chroma. The owner's "Lab proxy" lives HERE, in the
      latent, NOT at the boundary, and only because it is byte-exact INVERTIBLE back to sRGB. (The
      latent may instead be a training-specific space; the only hard rule is encode/decode = sRGB8.)

  WHY IT WORKS: the latent change-of-coordinates (L, Cr, Cg) has determinant 3, so it is invertible
  (a genuine basis, not a lossy projection), and that determinant 3 IS the index of the sublattice
  Lambda. The export inverts via b = (L - Cr - Cg)/3, which is integer exactly on Lambda (every real
  sRGB8 pixel is on Lambda since L - Cr - Cg = 3b); off Lambda or out of 0..255 the export REFUSES,
  so every exported value is genuine sRGB8.

  Matches V2TrainingLattice / eisenstein.py conventions. Base-only, runghc, NOT in cabal/Map/gate.
-}
module V2EncodeDecodeBoundary where

-- ===========================================================================
-- (1) The three layers
-- ===========================================================================

-- | The BOUNDARY representation: raw sRGB 8-bit (each channel 0..255). What the model imports and exports.
type SRGB8 = (Int, Int, Int)

-- | The LATENT representation the model explores: (L, Cr, Cg) = (R+G+B, R-B, G-B) = luma + Eisenstein
--   A2 chroma. Invertible back to sRGB8 (that is the whole point); the model never exports this form.
type Latent = (Int, Int, Int)

inRange8 :: Int -> Bool
inRange8 x = x >= 0 && x <= 255

isSRGB8 :: SRGB8 -> Bool
isSRGB8 (r, g, b) = all inRange8 [r, g, b]

-- | ENCODE: sRGB8 -> latent. Total (every integer pixel has a latent).
encode :: SRGB8 -> Latent
encode (r, g, b) = (r + g + b, r - b, g - b)

-- | DECODE / EXPORT: latent -> sRGB8, INVERT-OR-REFUSE. Returns Nothing off the index-3 sublattice
--   Lambda (L-Cr-Cg not divisible by 3) OR if any channel leaves 0..255. So every export is genuine sRGB8.
decode :: Latent -> Maybe SRGB8
decode (l, cr, cg)
  | (l - cr - cg) `mod` 3 /= 0 = Nothing
  | not (isSRGB8 px)           = Nothing
  | otherwise                  = Just px
  where
    bb = (l - cr - cg) `div` 3
    px = (bb + cr, bb + cg, bb)

-- | Export a whole frame (a list of latents) to sRGB8, refusing if any latent is not exportable.
--   The model uses this at BOTH 16^3 and 256^3; the boundary is scale-agnostic.
exportFrame :: [Latent] -> Maybe [SRGB8]
exportFrame = traverse decode

-- The sRGB8 sample grid (a representative spread of the 256^3 cube; full 16.7M is too many for runghc).
grid :: [Int]
grid = [0, 1, 15, 16, 127, 128, 200, 254, 255]

cube :: [SRGB8]
cube = [(r, g, b) | r <- grid, g <- grid, b <- grid]

-- ===========================================================================
-- (2) Laws
-- ===========================================================================

-- | THE BOUNDARY IS LOSSLESS: encode then decode is the IDENTITY on sRGB8 (byte-exact round trip), so
--   the latent loses nothing and the export reproduces the input exactly.
lawEncodeDecodeRoundTrip :: Bool
lawEncodeDecodeRoundTrip = all (\px -> decode (encode px) == Just px) cube

-- | THE LATENT IS THE OPPONENT DECOMPOSITION (luma + Eisenstein chroma) the model explores: L is the
--   (1,1,1) average axis; (Cr, Cg) = (R-B, G-B). Gray collapses to ZERO chroma (the kernel); non-gray
--   does not (tooth). This is the "Lab proxy" latent, first-class and RGB-native.
lawLatentIsLumaChroma :: Bool
lawLatentIsLumaChroma =
     all (\px@(r, g, b) -> encode px == (r + g + b, r - b, g - b)) cube
  && all (\k -> let (_, cr, cg) = encode (k, k, k) in (cr, cg) == (0, 0)) grid     -- gray -> zero chroma
  && (let (_, cr, cg) = encode (200, 50, 10) in (cr, cg) /= (0, 0))                -- non-gray -> nonzero (tooth)

-- | DECODE REFUSES off the index-3 sublattice Lambda (the /3 guard): a latent whose L-Cr-Cg is not
--   divisible by 3 cannot be a real sRGB8, so the export refuses (never emits a non-sRGB pixel). But
--   every REAL pixel encodes onto Lambda, so the boundary never refuses a genuine colour.
lawDecodeRefusesOffLambda :: Bool
lawDecodeRefusesOffLambda =
     decode (1, 0, 0) == Nothing                          -- 1 not divisible by 3
  && decode (2, 0, 0) == Nothing                          -- 2 not divisible by 3
  && all (\px -> decode (encode px) /= Nothing) cube      -- every real pixel is on Lambda

-- | EVERY EXPORT IS sRGB8: when decode succeeds it yields channels in 0..255 (the model exports sRGB).
--   Tooth: a latent ON Lambda but out of range (b = 1000) is refused, so the boundary stays sRGB-only.
lawExportIsSrgb :: Bool
lawExportIsSrgb =
     all (\px -> case decode (encode px) of Just q -> isSRGB8 q; Nothing -> False) cube
  && decode (3000, 0, 0) == Nothing                       -- on Lambda (3000 mod 3 == 0) but b=1000 out of range

-- | THE MODEL EXPORTS sRGB AT BOTH SCALES: the same decode applies frame-by-frame to a 16^3-sized
--   latent set and a 256^3-sized latent set; both export back to exactly their sRGB8 source.
lawBothScalesExportSrgb :: Bool
lawBothScalesExportSrgb =
     exportFrame (map encode small16) == Just small16     -- a 16-entry (16^3-scale) frame round-trips
  && exportFrame (map encode big)     == Just big          -- a larger (256^3-scale) frame round-trips
  where
    small16 = take 16 cube
    big     = cube

-- | THE LATENT TRANSFORM IS INVERTIBLE, and its determinant IS the guard: det of the (L, Cr, Cg) basis
--   = 3, which equals the index of Lambda. Nonzero => a genuine change of coordinates (not lossy); the
--   value 3 is WHY the export divides by 3. Form follows function.
lawLatentInvertibleDetIsThree :: Bool
lawLatentInvertibleDetIsThree = basisDet == 3 && basisDet /= 0
  where
    basisDet = det3 ([[1, 1, 1], [1, 0, -1], [0, 1, -1]] :: [[Int]])   -- rows: L=R+G+B, Cr=R-B, Cg=G-B
    det3 [[a, b, c], [d, e, f], [g, h, i]] =
      a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)
    det3 _ = 0

-- ===========================================================================
-- (3) Runner
-- ===========================================================================

laws :: [(String, Bool)]
laws =
  [ ("lawEncodeDecodeRoundTrip       (sRGB8 -> latent -> sRGB8 is identity)",     lawEncodeDecodeRoundTrip)
  , ("lawLatentIsLumaChroma          (latent = luma + Eisenstein chroma)",        lawLatentIsLumaChroma)
  , ("lawDecodeRefusesOffLambda      (off-Lambda export refuses; real px on it)", lawDecodeRefusesOffLambda)
  , ("lawExportIsSrgb                (every export is in 0..255 sRGB)",           lawExportIsSrgb)
  , ("lawBothScalesExportSrgb        (16^3 and 256^3 both export sRGB)",          lawBothScalesExportSrgb)
  , ("lawLatentInvertibleDetIsThree  (det = 3 = the index = why /3)",             lawLatentInvertibleDetIsThree)
  ]

main :: IO ()
main = do
  putStrLn "V2EncodeDecodeBoundary.hs  -- EXPLORATION (NOT WIRED): sRGB boundary, opponent latent"
  putStrLn (replicate 72 '-')
  mapM_ (\(n, ok) -> putStrLn (verdict ok ++ "  " ++ n)) laws
  putStrLn (replicate 72 '-')
  let passed = length (filter snd laws)
      total  = length laws
  putStrLn ("SUMMARY: " ++ show passed ++ "/" ++ show total ++ " laws PASS"
            ++ if passed == total then "  (all green)" else "  (FAILURES present)")
  putStrLn ""
  let px = (200, 50, 10) :: SRGB8
  putStrLn ("encode " ++ show px ++ " = " ++ show (encode px) ++ "   (L, Cr, Cg : luma + Eisenstein chroma)")
  putStrLn ("decode (encode " ++ show px ++ ") = " ++ show (decode (encode px)) ++ "   (byte-exact export)")
  putStrLn ""
  putStrLn "ARCHITECTURE: encode/decode = sRGB 8-bit (the model imports and EXPORTS sRGB at 16^3 and"
  putStrLn "256^3). The latent it explores is the opponent decomposition (luma + Eisenstein chroma),"
  putStrLn "byte-exact invertible back to sRGB (det = 3 = the index = the /3 guard). Lab deprecated."
  where
    verdict True  = "PASS"
    verdict False = "FAIL"

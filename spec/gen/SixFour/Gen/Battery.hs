{-# LANGUAGE TypeApplications #-}
{- |
Module      : SixFour.Gen.Battery
Description : A seeded, parametric battery of FULL 64³ voxel volumes.

Each 'Case' is a 'CompleteVoxelVolume' (64 frames × 64×64, every frame
surjective onto all 256 colours) paired with 64 per-frame 256-colour palettes
— exactly the shape the app emits and the look-NN ingests. The cases are
chosen to exercise the behaviours the palette-trajectory NN must handle:

  [@rainbow-ramp@]      A static rainbow color-bar, identical every frame.
                        Zero temporal palette change — the trivial baseline.
  [@flat-rescued@]      A near-constant frame whose dominant index drifts over
                        time, made surjective by sprinkling the other 255
                        colours (the significance/surjectivity rescue made
                        literal). Maximal temporal palette change.
  [@spatial-gradient@]  A smooth diagonal index gradient with a slowly rotating
                        palette — locally smooth in space and time.
  [@high-diversity@]    Uniform-random indices and a random in-gamut palette.
                        Maximum spatial entropy and palette diversity.
  [@temporal-flicker@]  A two-colour checkerboard whose parity flips each frame
                        — high temporal frequency (the §8 cyclic flicker).
  [@palette-rotation@]  Indices held fixed while the palette cyclically rotates
                        — isolates the pure palette-trajectory signal.

Every case is gated through 'mkCompleteVoxelVolume' and 'mkPalette' at
construction; a case that failed completeness would 'error' here rather than
reach the encoder. Construction is total because 'forceSurjective' only ever
overwrites duplicate indices, so all 256 colours are present without losing any.
-}
module SixFour.Gen.Battery
  ( Case (..)
  , battery
  , forceSurjective
  ) where

import           Data.Maybe          (fromMaybe)
import           Data.Word           (Word64)
import           Data.Bits           (xor, shiftR, shiftL)
import qualified Data.IntMap.Strict  as IM

import SixFour.Spec.Shape   (T, H, W, K, tVal, hVal, wVal, kVal, pixelsPerFrame)
import SixFour.Spec.Color   (OKLab, SRGB (..), srgbToOKLab)
import SixFour.Spec.Palette (Palette, mkPalette)
import SixFour.Spec.Indices ( IndexTensor, CompleteVoxelVolume
                            , mkIndexTensor, mkCompleteVoxelVolume )

-- | One generated test GIF: a complete voxel volume + its per-frame palettes.
data Case = Case
  { caseName     :: String                    -- ^ file-stem / report label
  , caseNote     :: String                    -- ^ one-line description (→ GIF comment)
  , caseVolume   :: CompleteVoxelVolume T H W K
  , casePalettes :: [Palette K]               -- ^ length T
  }

-- | The whole battery, parameterised by a seed (varies @high-diversity@ etc.).
battery :: Word64 -> [Case]
battery seed =
  [ rainbowRamp
  , flatRescued
  , spatialGradient
  , highDiversity seed
  , temporalFlicker
  , paletteRotation
  ]

-- ---------------------------------------------------------------------------
-- Cases
-- ---------------------------------------------------------------------------

-- | Static rainbow color-bar: pixel @p ↦ p mod 256@ (already surjective),
-- a vivid hue sweep, identical on every frame.
rainbowRamp :: Case
rainbowRamp =
  mkCase "rainbow-ramp" "static rainbow color-bar; zero temporal palette change"
    (replicate tv colorBarFrame)
    (replicate tv rampPalette)

-- | Near-constant frame; the dominant index walks with @t@, the other 255
-- colours sprinkled in by the surjectivity rescue. The palette is per-frame
-- distinct so the dominant colour visibly changes — maximal palette motion.
flatRescued :: Case
flatRescued =
  mkCase "flat-rescued"
    "near-constant frames (dominant index drifts); surjective by rescue"
    [ replicate ppf (t `mod` kv) | t <- [0 .. tv - 1] ]
    [ rotateList (t * 7) rampPalette | t <- [0 .. tv - 1] ]

-- | Smooth diagonal index gradient with a slowly rotating palette.
spatialGradient :: Case
spatialGradient =
  mkCase "spatial-gradient"
    "smooth diagonal index gradient; slowly rotating palette"
    [ [ gradIndex x y | y <- [0 .. hv - 1], x <- [0 .. wv - 1] ] | _t <- [0 .. tv - 1] ]
    [ rotateList t rampPalette | t <- [0 .. tv - 1] ]
  where
    gradIndex x y = ((x + y) * (kv - 1)) `div` (hv + wv - 2)

-- | Uniform-random indices + a random in-gamut palette. Maximum entropy.
highDiversity :: Word64 -> Case
highDiversity seed =
  mkCase "high-diversity" "uniform-random indices and a random in-gamut palette"
    frames
    pals
  where
    (frames, s1) = genFrames (rngFrom seed) tv
    pals         = take tv (chunkPalettes (randomPalette s1))
    genFrames g 0 = ([], g)
    genFrames g n =
      let (f , g')  = genN g ppf
          (fs, g'') = genFrames g' (n - 1)
      in (f : fs, g'')
    genN g 0 = ([], g)
    genN g n = let (v, g')  = randInt g kv
                   (vs, g'') = genN g' (n - 1)
               in (v : vs, g'')

-- | Two-colour checkerboard whose parity flips each frame — high temporal
-- frequency. Surjective by rescue; rendered on the rainbow palette.
temporalFlicker :: Case
temporalFlicker =
  mkCase "temporal-flicker" "two-colour checkerboard, parity flips each frame"
    [ [ if even (x + y + t) then loIdx else hiIdx
      | y <- [0 .. hv - 1], x <- [0 .. wv - 1] ]
    | t <- [0 .. tv - 1] ]
    (replicate tv rampPalette)
  where loIdx = 24; hiIdx = 220

-- | Indices held fixed (the color-bar); the palette cyclically rotates so the
-- GIF "scrolls" hue with no index change — the pure palette-trajectory signal.
paletteRotation :: Case
paletteRotation =
  mkCase "palette-rotation" "fixed indices, cyclically rotating palette"
    (replicate tv colorBarFrame)
    [ rotateList (t * 4) rampPalette | t <- [0 .. tv - 1] ]

-- ---------------------------------------------------------------------------
-- Frame / palette helpers
-- ---------------------------------------------------------------------------

tv, hv, wv, kv, ppf :: Int
tv  = tVal
hv  = hVal
wv  = wVal
kv  = kVal
ppf = pixelsPerFrame

-- | @p ↦ p mod 256@ over a whole frame: every index appears 16×.
colorBarFrame :: [Int]
colorBarFrame = [ p `mod` kv | p <- [0 .. ppf - 1] ]

-- | Make every index in @[0,K-1]@ appear in a frame WITHOUT dropping any index
-- already present: only positions holding a duplicate value are overwritten.
-- Total on the SixFour shape (4096 ≥ 256 ⇒ ≥ 3840 duplicate positions).
forceSurjective :: Int -> [Int] -> [Int]
forceSurjective k base =
  let counts  = IM.fromListWith (+) [ (v, 1 :: Int) | v <- base ]
      missing = [ i | i <- [0 .. k - 1], not (IM.member i counts) ]
  in if null missing then base else inject missing counts base
  where
    inject [] _ rest = rest
    inject _  _ []   = []                      -- unreachable on this shape
    inject ms@(m : ms') cnt (v : vs)
      | IM.findWithDefault 0 v cnt > 1 =
          m : inject ms' (IM.adjust (subtract 1) v cnt) vs
      | otherwise = v : inject ms cnt vs

-- | Build a 'Case', forcing each frame surjective and validating the brand.
mkCase :: String -> String -> [[Int]] -> [[OKLab]] -> Case
mkCase name note frames palettes =
  Case name note vol pals
  where
    flat = concatMap (forceSurjective kv) frames
    it   = fromMaybe (errc "index tensor (wrong length / out of range)")
                     (mkIndexTensor @T @H @W @K flat)
    vol  = fromMaybe (errc "not a complete voxel volume (a frame is non-surjective)")
                     (mkCompleteVoxelVolume it)
    pals = map mkPal palettes
    mkPal cs = fromMaybe (errc "palette is not exactly K colours")
                         (mkPalette @K cs)
    errc msg = error ("Battery." ++ name ++ ": " ++ msg)

-- | Cyclic left-rotate a list by @n@ (used for palette rotation).
rotateList :: Int -> [a] -> [a]
rotateList n xs
  | null xs   = xs
  | otherwise = let m = n `mod` length xs in drop m xs ++ take m xs

-- ---------------------------------------------------------------------------
-- Palettes (built in sRGB, stored as OKLab so they are always in gamut)
-- ---------------------------------------------------------------------------

-- | 256-colour vivid rainbow: hue = i/256 at full saturation/value.
rampPalette :: [OKLab]
rampPalette = [ srgbToOKLab (hsv1 (fromIntegral i / fromIntegral kVal)) | i <- [0 .. kVal - 1] ]

-- | Full-saturation, full-value HSV → sRGB.
hsv1 :: Double -> SRGB
hsv1 h =
  let h6 = h * 6
      i  = floor h6 `mod` 6 :: Int
      f  = h6 - fromIntegral (floor h6 :: Int)
      q  = 1 - f
      t  = f
  in case i of
       0 -> SRGB 1 t 0
       1 -> SRGB q 1 0
       2 -> SRGB 0 1 t
       3 -> SRGB 0 q 1
       4 -> SRGB t 0 1
       _ -> SRGB 1 0 q

-- | An infinite stream of random palettes' OKLab colours, chunked into 256s.
randomPalette :: Rng -> [OKLab]
randomPalette g0 =
  let (r, g1) = randUnit g0
      (gg, g2) = randUnit g1
      (b, g3) = randUnit g2
  in srgbToOKLab (SRGB r gg b) : randomPalette g3

chunkPalettes :: [OKLab] -> [[OKLab]]
chunkPalettes xs = let (h', t') = splitAt kVal xs in h' : chunkPalettes t'

-- ---------------------------------------------------------------------------
-- Tiny splitmix64 PRNG (no extra deps; deterministic, seedable)
-- ---------------------------------------------------------------------------

newtype Rng = Rng Word64

rngFrom :: Word64 -> Rng
rngFrom = Rng

-- | splitmix64 step.
nextW :: Rng -> (Word64, Rng)
nextW (Rng s) =
  let z0 = s + 0x9E3779B97F4A7C15
      z1 = (z0 `xor` (z0 `shiftR` 30)) * 0xBF58476D1CE4E5B9
      z2 = (z1 `xor` (z1 `shiftR` 27)) * 0x94D049BB133111EB
      z3 = z2 `xor` (z2 `shiftR` 31)
  in (z3, Rng z0)

-- | Uniform @Int@ in @[0, n)@.
randInt :: Rng -> Int -> (Int, Rng)
randInt g n = let (w, g') = nextW g in (fromIntegral (w `mod` fromIntegral n), g')

-- | Uniform @Double@ in @[0,1]@.
randUnit :: Rng -> (Double, Rng)
randUnit g =
  let (w, g') = nextW g
  in (fromIntegral (w `shiftR` 11) / fromIntegral ((1 :: Word64) `shiftL` 53), g')

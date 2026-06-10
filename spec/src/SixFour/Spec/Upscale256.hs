{- |
Module      : SixFour.Spec.Upscale256
Description : The deterministic two-cube → 256³ endgame — recompute, never
              interpolate.

Design §6 (@docs/COLOR-ATLAS.md@). The 4× space-and-time upscale consumes BOTH
cubes (cube A = global-palette indices, cube B = the richer per-frame cubes),
the per-frame → global 'paletteMap', the carried
'SixFour.Spec.AtlasCascade.ExitState', and the pinned anchors:

  * __Slot alignment σ_t__ ('alignSlots') — slots of P_t and P_{t+1} sharing a
    paletteMap image are matched (ties → lowest); unmatched slots fall back to
    direct 'nearestQ16'. Raw index @k@ is NEVER blended across independently
    quantized frame palettes (the judge-rejected P2 shortcut).
  * __Output palettes__ ('blendPalettesQ16') — @P′[j] = ((4−k)·P_t[j] +
    k·P_{t+1}[σ_t(j)]) >> 2@ in Q16, exact integer ('Int' arithmetic, exact
    arithmetic shift); @k = 0@ reproduces @P_t@ byte-identically
    ('lawK0PaletteExact'). Anchors are then substituted VERBATIM
    ('applyAnchors', 'lawAnchorsVerbatim') — the user contract that pins
    survive to 256³.
  * __Per-pixel quantization__ ('quantizePrior') — prior-weighted nearest,
    ported from @/Users/daniel/QUAD-Spec/src/Quad/NN/PriorWeightedNearest.hs@:
    @score(j) = d²_Q16(x, P′[j]) − λ·prior(j)@, λ = 1, ties → lowest index.
    The prior is the carried drift agreement ('driftPrior') of the ExitState's
    slot M-image — the CONSUMPTION side QUAD left latent; here it is
    load-bearing ('lawLambdaConsumptionDiffers' is the anti-latent-carry
    proof, shipped in the same milestone as the producer).
  * __Killed-bin arbitration__ — where cube B's colour falls in a curation-
    killed region, cube A wins: the target snaps to its global leaf first.

The spec keeps the cube geometry PARAMETRIC (frames T, side S, palette size P)
so the properties run on tiny cubes; the app instantiates T = S = 64, P = 256.
The golden pin uses a deterministic FNV-1a 64 checksum ('outputChecksum') —
the spec-side stand-in for the SHA-256 the device asserts.
-}
module SixFour.Spec.Upscale256
  ( -- * Q16 pixels (the SpatialDither wire type)
    PxQ16
  , upscaleFactor
    -- * Slot alignment + palette blend
  , alignSlots
  , blendPxQ16
  , blendPalettesQ16
  , applyAnchors
    -- * Prior-weighted nearest (the ExitState consumer)
  , priorUnit
  , driftPrior
  , quantizePrior
  , quantizePriorAmong
    -- * The full upscale
  , UpscaleInput(..)
  , UpscaleOutput(..)
  , upscale256
    -- * Golden checksum
  , fnv1a64
  , outputChecksum
    -- * Pinned fixtures
  , consumptionFixturePalette
  , consumptionFixtureExit
  , consumptionFixtureTarget
    -- * Laws (predicates; QuickCheck'd in Properties.Upscale256)
  , lawK0PaletteExact
  , lawLambda0IsNearestQ16
  , lawLambdaConsumptionDiffers
  , lawAnchorsVerbatim
  , lawIntegerClosed
  , lawIndicesInRange
  ) where

import           Data.Bits   (shiftR, xor)
import           Data.List   (foldl', nub, sort)
import           Data.Word   (Word8, Word64)
import qualified Data.Vector as V

import SixFour.Spec.AtlasCascade  (ExitState(..), SlotExit(..), exitSlotCount)
import SixFour.Spec.SpatialDither (distSqQ16, nearestQ16)

-- | A Q16 OKLab pixel, the 'SixFour.Spec.SpatialDither.Px' wire type.
type PxQ16 = (Int, Int, Int)

-- | 4× in space AND time: 64³ → 256³.
upscaleFactor :: Int
upscaleFactor = 4

-- ---------------------------------------------------------------------------
-- Slot alignment + palette blend
-- ---------------------------------------------------------------------------

-- | σ_t: for each slot @j@ of P_t, the LOWEST slot @j′@ of P_{t+1} with the
-- same paletteMap image @M[t][j] = M[t+1][j′]@; unmatched slots fall back to
-- direct 'nearestQ16' of the P_t colour into P_{t+1}.
alignSlots
  :: [Int]    -- ^ M[t]   — per-frame slot → global slot
  -> [Int]    -- ^ M[t+1]
  -> [PxQ16]  -- ^ P_t
  -> [PxQ16]  -- ^ P_{t+1}
  -> [Int]    -- ^ σ_t, one entry per P_t slot
alignSlots mt mn pt pn = [ align j c | (j, c) <- zip [0 ..] pt ]
  where
    align j c =
      let g = if j < length mt then Just (mt !! j) else Nothing
      in case [ j' | Just gj <- [g], (j', g') <- zip [0 ..] mn, g' == gj ] of
           (j' : _) -> j'
           []       -> nearestQ16 pn c

-- | The exact Q16 temporal blend of two pixels at phase @k ∈ [0,4)@:
-- componentwise @((4−k)·a + k·b) >> 2@ (arithmetic shift — exact integer,
-- and for @a, b@ in any interval @[lo, hi]@ the result stays inside it:
-- 'lawIntegerClosed').
blendPxQ16 :: Int -> PxQ16 -> PxQ16 -> PxQ16
blendPxQ16 k (l1, a1, b1) (l2, a2, b2) = (c l1 l2, c a1 a2, c b1 b2)
  where c x y = ((4 - k) * x + k * y) `shiftR` 2

-- | The output palette before anchoring: @P′[j] = blend k P_t[j] P_{t+1}[σ(j)]@.
blendPalettesQ16 :: Int -> [PxQ16] -> [PxQ16] -> [Int] -> [PxQ16]
blendPalettesQ16 k pt pn sigma =
  [ blendPxQ16 k c (index pn j') | (c, j') <- zip pt sigma ]
  where index ps i = if i >= 0 && i < length ps then ps !! i else (0, 0, 0)

-- | Substitute the anchors EXACTLY into the palette: each anchor (in order)
-- replaces its nearest not-yet-anchored slot (ties → lowest), so distinct
-- anchors land in distinct slots and every anchor appears verbatim whenever
-- @#anchors ≤ #slots@.
applyAnchors :: [PxQ16] -> [PxQ16] -> [PxQ16]
applyAnchors anchors pal0 = foldl' place pal0 (take (length pal0) anchors)
  where
    place pal a =
      let taken = [ i | (i, c) <- zip [0 ..] pal, c `elem` anchors, c /= a ]
          free  = [ (i, c) | (i, c) <- zip [0 ..] pal, i `notElem` taken ]
      in case free of
           [] -> pal
           ((j0, c0) : rest) ->
             let best = fst (foldl' (\(bi, bd) (i, c) ->
                                       let d = distSqQ16 a c
                                       in if d < bd then (i, d) else (bi, bd))
                                    (j0, distSqQ16 a c0) rest)
             in [ if i == best then a else c | (i, c) <- zip [0 ..] pal ]

-- ---------------------------------------------------------------------------
-- Prior-weighted nearest (the consumer)
-- ---------------------------------------------------------------------------

-- | One sign-agreement is worth one Q16-LSB² of squared distance per
-- agreement unit times this scale — chosen so the prior can flip decisions
-- between perceptually-adjacent leaves but never across the gamut.
priorUnit :: Int
priorUnit = 65536

-- | The carried drift agreement of slot @j@'s M-image: for each of the three
-- carried residual rates (dL, da, db), +1 when the rate is non-zero and its
-- sign agrees with the corresponding component of @x − P′[j]@. Scaled by
-- 'priorUnit'. Out-of-range M-images score 0.
driftPrior :: ExitState -> [Int] -> [PxQ16] -> PxQ16 -> Int -> Int
driftPrior e m pal (xl, xa, xb) j
  | j < 0 || j >= length pal || j >= length m = 0
  | g < 0 || g >= exitSlotCount               = 0
  | otherwise = priorUnit * agreement
  where
    g  = m !! j
    s  = exitSlots e V.! g
    (pl, pa, pb) = pal !! j
    agree rate diff = if rate /= 0 && signum (fromIntegral rate :: Int) == signum diff
                        then 1 else (0 :: Int)
    agreement = agree (seDL s) (xl - pl)
              + agree (seDA s) (xa - pa)
              + agree (seDB s) (xb - pb)

-- | @argmin_j d²(x, pal[j]) − λ·prior(j)@, strict @<@ ⇒ lowest index on ties
-- (the 'nearestQ16' convention). Empty palette ⇒ 0. @λ = 0@ recovers
-- 'nearestQ16' EXACTLY ('lawLambda0IsNearestQ16').
quantizePrior :: Int -> [PxQ16] -> (Int -> Int) -> PxQ16 -> Int
quantizePrior lam pal prior x =
  quantizePriorAmong lam pal prior [0 .. length pal - 1] x

-- | The candidate-restricted form the upscaler uses (candidates ascending ⇒
-- ties → lowest candidate index). Empty candidate set ⇒ 0.
quantizePriorAmong :: Int -> [PxQ16] -> (Int -> Int) -> [Int] -> PxQ16 -> Int
quantizePriorAmong lam pal prior cands x =
  case [ j | j <- cands, j >= 0, j < length pal ] of
    []       -> 0
    (j0 : js) ->
      fst (foldl' step (j0, score j0) js)
  where
    score j = distSqQ16 x (pal !! j) - lam * prior j
    step (bj, bs) j = let s = score j in if s < bs then (j, s) else (bj, bs)

-- ---------------------------------------------------------------------------
-- The full upscale
-- ---------------------------------------------------------------------------

-- | Everything the deterministic endgame consumes. Parametric in T (frames),
-- S (side) and palette size so the law fixtures stay tiny; the app uses
-- T = S = 64 with 256-slot palettes.
data UpscaleInput = UpscaleInput
  { upFrames   :: Int               -- ^ T
  , upSide     :: Int               -- ^ S
  , upPalettes :: [[PxQ16]]         -- ^ cube B's per-frame palettes (T of them)
  , upMap      :: [[Int]]           -- ^ paletteMap M, T rows (slot → global slot)
  , upGlobal   :: [PxQ16]           -- ^ curated global leaves (cube A's palette)
  , upCubeB    :: [V.Vector Int]    -- ^ T planes of S·S per-frame slot indices
  , upCubeA    :: [V.Vector Int]    -- ^ T planes of S·S global slot indices
  , upKilled   :: PxQ16 -> Bool     -- ^ ch4 arbitration: colour in a killed bin?
  , upExit     :: ExitState         -- ^ the carried 64³ exit state
  , upAnchors  :: [PxQ16]           -- ^ pinned anchor colours (verbatim contract)
  , upLambda   :: Int               -- ^ prior weight λ (design: 1)
  }

-- | 4T output frames, each with its own anchored blended palette and a
-- @(4S)²@ index plane into it.
data UpscaleOutput = UpscaleOutput
  { outPalettes :: [[PxQ16]]
  , outCube     :: [V.Vector Int]
  } deriving (Eq, Show)

-- | The deterministic re-render (recompute, never interpolate). Output frame
-- @f′ = 4t + k@; output pixel @(4y+v, 4x+u)@ re-quantizes the temporal blend
-- of cube B's reconstructed colours at @(t,y,x)@ and @(t+1,y,x)@ (t = T−1
-- clamps) against the anchored blended palette, restricted to the source
-- pixel's 3×3 slot neighbourhood (≤ 10 candidates), scored by the carried
-- drift prior. Killed colours snap to cube A's leaf first.
upscale256 :: UpscaleInput -> UpscaleOutput
upscale256 inp = UpscaleOutput pals planes
  where
    tN   = upFrames inp
    s    = upSide inp
    sOut = upscaleFactor * s
    frames = [ (t, k) | t <- [0 .. tN - 1], k <- [0 .. upscaleFactor - 1] ]

    perFrame = [ renderFrame t k | (t, k) <- frames ]
    pals     = map fst perFrame
    planes   = map snd perFrame

    renderFrame t k =
      let tn    = min (t + 1) (tN - 1)        -- t = T−1 clamps
          pt    = upPalettes inp !! t
          pn    = upPalettes inp !! tn
          mt    = upMap inp !! t
          mn    = upMap inp !! tn
          sigma = alignSlots mt mn pt pn
          p'    = applyAnchors (upAnchors inp) (blendPalettesQ16 k pt pn sigma)
          prior = driftPrior (upExit inp) mt p'
          plane = V.generate (sOut * sOut) $ \pix ->
                    let yO = pix `div` sOut
                        xO = pix `mod` sOut
                        y  = yO `div` upscaleFactor
                        x  = xO `div` upscaleFactor
                    in renderPixel t tn k pt pn p' prior y x
      in (p', plane)

    renderPixel t tn k pt pn p' prior y x =
      let bAt fr yy xx =
            let yCl = max 0 (min (s - 1) yy)
                xCl = max 0 (min (s - 1) xx)
            in upCubeB inp !! fr V.! (yCl * s + xCl)
          j0  = bAt t y x
          ct  = at pt j0
          cn  = at pn (bAt tn y x)
          xb  = blendPxQ16 k ct cn
          -- killed-bin arbitration: cube A wins
          xc  = if upKilled inp xb
                  then at (upGlobal inp) (upCubeA inp !! t V.! (y * s + x))
                  else xb
          cands = sort (nub (j0 : [ bAt t (y + dy) (x + dx)
                                  | dy <- [-1, 0, 1], dx <- [-1, 0, 1] ]))
      in quantizePriorAmong (upLambda inp) p' (prior xc) cands xc

    at ps i = if i >= 0 && i < length ps then ps !! i else (0, 0, 0)

-- ---------------------------------------------------------------------------
-- Golden checksum
-- ---------------------------------------------------------------------------

-- | FNV-1a, 64-bit — the deterministic spec-side stand-in for the device's
-- SHA-256 golden pin.
fnv1a64 :: [Word8] -> Word64
fnv1a64 = foldl' (\h b -> (h `xor` fromIntegral b) * 0x100000001b3) 0xcbf29ce484222325

-- | Serialize an output (palettes then index planes, all components as
-- canonical decimal bytes) and hash it. Pinned on a fixed synthetic cube
-- pair in @Properties.Upscale256@.
outputChecksum :: UpscaleOutput -> Word64
outputChecksum (UpscaleOutput ps cubes) =
  fnv1a64 (map (fromIntegral . fromEnum) (show ps ++ "|" ++ show (map V.toList cubes)))

-- ---------------------------------------------------------------------------
-- Pinned fixtures (the anti-latent-carry proof)
-- ---------------------------------------------------------------------------

-- | Two leaves a small Q16 gap apart.
consumptionFixturePalette :: [PxQ16]
consumptionFixturePalette = [(0, 0, 0), (256, 0, 0)]

-- | An exit state whose slot-1 image carries a NEGATIVE dL rate — agreeing
-- with the fixture target's residual sign against leaf 1 only.
consumptionFixtureExit :: ExitState
consumptionFixtureExit = ExitState
  (V.replicate exitSlotCount (SlotExit 0 0 0 0 0 0 0)
     V.// [(1, SlotExit 0 (-5) 0 0 0 0 0)])
  0

-- | Nearer leaf 0 by plain distance (d² = 14400 vs 18496), but the carried
-- drift agreement (one component, 'priorUnit' = 65536) flips the choice at
-- λ = 1.
consumptionFixtureTarget :: PxQ16
consumptionFixtureTarget = (120, 0, 0)

-- ---------------------------------------------------------------------------
-- Laws
-- ---------------------------------------------------------------------------

-- | @k = 0@ reproduces P_t byte-identically, for ANY alignment.
lawK0PaletteExact :: [PxQ16] -> [PxQ16] -> [Int] -> Bool
lawK0PaletteExact pt pn sigma =
  length sigma /= length pt ||
  blendPalettesQ16 0 pt pn sigma == pt

-- | @λ = 0@ ⇒ the quantizer IS 'nearestQ16' (ties → lowest), whatever the
-- prior says.
lawLambda0IsNearestQ16 :: [PxQ16] -> [Int] -> PxQ16 -> Bool
lawLambda0IsNearestQ16 pal priors x =
  quantizePrior 0 pal prior x == nearestQ16 pal x
  where prior j = if j < length priors then priors !! j else 0

-- | THE anti-latent-carry pin: on the fixed fixture, λ = 1 and λ = 0 choose
-- DIFFERENT slots — the carried exit state is observably consumed.
lawLambdaConsumptionDiffers :: Bool
lawLambdaConsumptionDiffers =
  let pal   = consumptionFixturePalette
      m     = [0, 1]
      prior = driftPrior consumptionFixtureExit m pal consumptionFixtureTarget
      pick lam = quantizePrior lam pal prior consumptionFixtureTarget
  in pick 0 == 0 && pick 1 == 1 && pick 0 /= pick 1

-- | Every anchor appears VERBATIM in the anchored palette (whenever there are
-- at least as many slots as distinct anchors).
lawAnchorsVerbatim :: [PxQ16] -> [PxQ16] -> Bool
lawAnchorsVerbatim anchors pal =
  let as = nub anchors
  in length as > length pal ||
     all (`elem` applyAnchors as pal) as

-- | Integer closure of the blend: for inputs componentwise inside
-- @[lo, hi]@, the blend stays inside @[lo, hi]@ (exact shift arithmetic —
-- no overflow, no excursion outside the Q16 working range).
lawIntegerClosed :: Int -> PxQ16 -> PxQ16 -> Bool
lawIntegerClosed k a b =
  let kk = abs k `mod` 4
      (l, m, n) = blendPxQ16 kk a b
      within (x1, y1, z1) (x2, y2, z2) (xo, yo, zo) =
        inRange x1 x2 xo && inRange y1 y2 yo && inRange z1 z2 zo
      inRange u v w = w >= min u v && w <= max u v
  in within a b (l, m, n)

-- | Every output index addresses its frame's output palette.
lawIndicesInRange :: UpscaleInput -> Bool
lawIndicesInRange inp =
  let UpscaleOutput ps cubes = upscale256 inp
  in and [ V.all (\i -> i >= 0 && i < length p) cube
         | (p, cube) <- zip ps cubes ]

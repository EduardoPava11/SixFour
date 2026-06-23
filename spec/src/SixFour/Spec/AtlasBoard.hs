{- |
Module      : SixFour.Spec.AtlasBoard
Description : The Color Atlas BOARD STATE — the 16³ OKLab curation grid (s).

The canonical design is @docs/COLOR-ATLAS.md@ (§2 tensor table). The board is
the AlphaGo "board state" of the curation game: a @[16,16,16,6]@ tensor over
the EXACT 'Coverage.okLabBin' arithmetic (same grid as the coverage oracle and
the Swift @gamutCoverage@ — one binning, three languages).

Channels (ch0–ch5, §2):

  * ch0 @binMassPalettes@ — normalised occupancy of the 64 per-frame palettes
    (in the app the denominator is 64·256 = 16384; the spec normalises by the
    actual entry count so 'lawMassNormalized' is total).
  * ch1 @binMassPixels@   — normalised occupancy of the cube-B pixels routed
    through their per-frame palettes.
  * ch2 @globalCoverage@  — normalised occupancy of the CURRENT candidate
    global palette's 256 leaves.
  * ch3 @weightField@     — signed user weights (WeightRegion moves).
  * ch4 @killMask@        — {0,1} kill toggles (ToggleBin moves).
  * ch5 @anchorMask@      — {0,1} pinned-anchor bins (PinAnchor moves);
    'bAnchors' carries the pinned colours themselves (the @anchorColors@ plane).

LAW (the move/state split, §3.1): curation moves edit ch3–ch5 ONLY; ch0–ch2 are
recomputed from capture state and never touched by 'SixFour.Spec.AtlasMove'
('lawBaseChannelsUntouched' over there).

σ-mirror (§4.2 caveat): the chroma reflection 'sigmaReflect' acts on the board
as the bin mirror @(i, j, k) ↦ (i, 15−j, 15−k)@ — but only OFF the a/b bin
boundaries ('okLabBin' floors-and-clamps, so colours ON a lattice plane break
the mirror). 'lawSigmaMirrorOffBoundary' is stated with that caveat; the
QuickCheck generators avoid exact lattice points.
-}
-- COMPARTMENT: METAL-GPU | tag:none | STRADDLER
module SixFour.Spec.AtlasBoard
  ( -- * Bins (the 16³ lattice over 'Coverage.okLabBin')
    BinIdx(..)
  , boardBins
  , binInRange
  , binIndex
  , binOf
  , binCenter
  , mirrorBin
    -- * Q16 colour wire form (the pinned rounding seam, design §8 Phase D)
  , OKLabQ16
  , okLabToQ16
  , okLabFromQ16
    -- * The board
  , Board16(..)
  , boardChannels
  , emptyBoard
  , boardTensor
  , channelAt
    -- * Tokens (occupied bins → extended GMM tokens, design §2 @tokens@)
  , tokenWidth
  , boardTokens
    -- * The σ-action on the board (a/b bin mirror + anchor reflection)
  , boardSigma
  , offBinBoundary
    -- * Laws (predicates; QuickCheck'd in Properties.AtlasBoard)
  , lawMassNormalized
  , lawBinAgreesWithCoverage
  , lawSigmaMirrorOffBoundary
  , lawTokensSigmaInvariantCols
  , lawTotalOnEmpty
  ) where

import qualified Data.Vector as V

import SixFour.Spec.Color    (OKLab(..))
import SixFour.Spec.Coverage (coverageBinsPerAxis, okLabBin)
import SixFour.Spec.PairTree (sigmaReflect)

-- ---------------------------------------------------------------------------
-- Bins
-- ---------------------------------------------------------------------------

-- | A 16³ board cell: @(L bin, a bin, b bin)@, each in @[0, 16)@.
newtype BinIdx = BinIdx (Int, Int, Int)
  deriving (Eq, Ord, Show)

-- | Total board cells: @16³ = 4096@.
boardBins :: Int
boardBins = coverageBinsPerAxis ^ (3 :: Int)

-- | Is the bin on the board? (Out-of-range bins make moves act as identity.)
binInRange :: BinIdx -> Bool
binInRange (BinIdx (i, j, k)) = ok i && ok j && ok k
  where ok v = v >= 0 && v < coverageBinsPerAxis

-- | Flat index @((i·16) + j)·16 + k@ into a 4096-vector channel.
binIndex :: BinIdx -> Int
binIndex (BinIdx (i, j, k)) =
  (i * coverageBinsPerAxis + j) * coverageBinsPerAxis + k

-- | Inverse of 'binIndex' (internal layout; total for @[0, 4096)@).
unBinIndex :: Int -> BinIdx
unBinIndex ix =
  let n = coverageBinsPerAxis
  in BinIdx (ix `div` (n * n), (ix `div` n) `mod` n, ix `mod` n)

-- | The bin of a colour — EXACTLY 'Coverage.okLabBin' (pinned by
-- 'lawBinAgreesWithCoverage'; this module never reimplements the arithmetic).
binOf :: OKLab -> BinIdx
binOf = BinIdx . okLabBin

-- | The OKLab centre of a bin (@L@ over @[0,1]@; @a,b@ over @[−0.5,0.5]@ —
-- the 'okLabBin' working range). Exact dyadic arithmetic in 'Double'.
binCenter :: BinIdx -> OKLab
binCenter (BinIdx (i, j, k)) =
  let n = fromIntegral coverageBinsPerAxis
      l = (fromIntegral i + 0.5) / n
      a = (fromIntegral j + 0.5) / n - 0.5
      b = (fromIntegral k + 0.5) / n - 0.5
  in OKLab l a b

-- | The board-level σ: chroma negation mirrors the a/b axes,
-- @(i, j, k) ↦ (i, 15−j, 15−k)@. An involution on the lattice.
mirrorBin :: BinIdx -> BinIdx
mirrorBin (BinIdx (i, j, k)) =
  let m = coverageBinsPerAxis - 1
  in BinIdx (i, m - j, m - k)

-- ---------------------------------------------------------------------------
-- Q16 colour wire form
-- ---------------------------------------------------------------------------

-- | An OKLab triple as Q16 integers (scale @2^16@) — the render-path wire
-- form (design risk 7: ONE pinned rounding function, golden-vectored).
type OKLabQ16 = (Int, Int, Int)

-- | The pinned float → Q16 rounding: @⌊v·65536 + 0.5⌋@ (round half up),
-- per component. Golden vectors in @Properties.AtlasBoard@.
okLabToQ16 :: OKLab -> OKLabQ16
okLabToQ16 (OKLab l a b) = (q l, q a, q b)
  where q v = floor (v * 65536 + 0.5)

-- | Q16 → float OKLab. Division by @2^16@ is exact in 'Double'.
okLabFromQ16 :: OKLabQ16 -> OKLab
okLabFromQ16 (l, a, b) = OKLab (f l) (f a) (f b)
  where f v = fromIntegral v / 65536

-- ---------------------------------------------------------------------------
-- The board
-- ---------------------------------------------------------------------------

-- | The @[16,16,16,6]@ board state. Each channel is a flat 4096-vector
-- (layout 'binIndex'); 'bAnchors' carries the pinned anchor COLOURS (ch5 is
-- only the mask — the colours are the @anchorColors@ plane of design §2).
data Board16 = Board16
  { bMassPalettes :: V.Vector Double   -- ^ ch0
  , bMassPixels   :: V.Vector Double   -- ^ ch1
  , bCoverage     :: V.Vector Double   -- ^ ch2
  , bWeight       :: V.Vector Double   -- ^ ch3
  , bKill         :: V.Vector Double   -- ^ ch4
  , bAnchorMask   :: V.Vector Double   -- ^ ch5
  , bAnchors      :: [(BinIdx, OKLab)] -- ^ anchorColors, one per pinned bin
  } deriving (Eq, Show)

-- | Channel count (the tensor's last axis).
boardChannels :: Int
boardChannels = 6

-- | The all-zero board (the day-1 state before any capture or curation).
emptyBoard :: Board16
emptyBoard =
  let z = V.replicate boardBins 0
  in Board16 z z z z z z []

-- | Normalised bin histogram of a colour list (Σ = 1 for non-empty input).
histogram :: [OKLab] -> V.Vector Double
histogram cs =
  let n = length cs
      w = if n == 0 then 0 else 1 / fromIntegral n
  in V.accum (+) (V.replicate boardBins 0)
             [ (binIndex (binOf c), w) | c <- cs ]

-- | Build the base channels ch0–ch2 from capture state: the 64 per-frame
-- palettes, the cube-B pixel colours (through their palettes), and the
-- current candidate global palette's leaves. Curation channels start at zero
-- (they are the fold over the decision log — 'AtlasMove.boardFromLog').
boardTensor
  :: [[OKLab]]   -- ^ per-frame palettes (ch0 mass)
  -> [OKLab]     -- ^ cube-B pixel colours (ch1 mass)
  -> [OKLab]     -- ^ candidate global palette leaves (ch2 coverage)
  -> Board16
boardTensor pals pixels candidates = emptyBoard
  { bMassPalettes = histogram (concat pals)
  , bMassPixels   = histogram pixels
  , bCoverage     = histogram candidates
  }

-- | Read one channel at a bin (0 off the board — total).
channelAt :: (Board16 -> V.Vector Double) -> Board16 -> BinIdx -> Double
channelAt ch b bi
  | binInRange bi = ch b V.! binIndex bi
  | otherwise     = 0

-- ---------------------------------------------------------------------------
-- Tokens
-- ---------------------------------------------------------------------------

-- | Token width: 10 base columns + 3 σ-invariant curation scalars = 13
-- (design §2 @tokens@: the GMM-token column extension φ′).
tokenWidth :: Int
tokenWidth = 13

-- | Occupied bins → extended tokens, one 13-vector per bin with ANY non-zero
-- channel. Columns:
--
-- @
--   0 massPalettes | 1 massPixels | 2 coverage
--   3 cL | 4 cA | 5 cB                 (bin centre; 4–5 negate under σ)
--   6 cL² | 7 cA² | 8 cB² | 9 cA·cB    (σ-invariant second moments)
--   10 weight | 11 kill | 12 anchor    (the 3 σ-invariant curation scalars)
-- @
--
-- Under 'boardSigma' the token MULTISET maps by negating columns 4–5 and
-- fixing every other column ('lawTokensSigmaInvariantCols') — the mask-algebra
-- fact the φ′ column extension of the L3 encoder relies on (design §4.2).
boardTokens :: Board16 -> [[Double]]
boardTokens b =
  [ token ix
  | ix <- [0 .. boardBins - 1]
  , occupied ix
  ]
  where
    chans = [ bMassPalettes b, bMassPixels b, bCoverage b
            , bWeight b, bKill b, bAnchorMask b ]
    occupied ix = any (\v -> v V.! ix /= 0) chans
    token ix =
      let OKLab cl ca cb = binCenter (unBinIndex ix)
      in [ bMassPalettes b V.! ix
         , bMassPixels   b V.! ix
         , bCoverage     b V.! ix
         , cl, ca, cb
         , cl * cl, ca * ca, cb * cb, ca * cb
         , bWeight     b V.! ix
         , bKill       b V.! ix
         , bAnchorMask b V.! ix
         ]

-- ---------------------------------------------------------------------------
-- The σ-action
-- ---------------------------------------------------------------------------

-- | Mirror every channel through 'mirrorBin' and σ-reflect the anchor
-- colours. An involution ('boardSigma . boardSigma = id', exact — mirroring
-- permutes, 'sigmaReflect' negates).
boardSigma :: Board16 -> Board16
boardSigma b = Board16
  { bMassPalettes = mirrorVec (bMassPalettes b)
  , bMassPixels   = mirrorVec (bMassPixels b)
  , bCoverage     = mirrorVec (bCoverage b)
  , bWeight       = mirrorVec (bWeight b)
  , bKill         = mirrorVec (bKill b)
  , bAnchorMask   = mirrorVec (bAnchorMask b)
  , bAnchors      = [ (mirrorBin bi, sigmaReflect c) | (bi, c) <- bAnchors b ]
  }
  where
    mirrorVec v = V.generate boardBins (\ix -> v V.! binIndex (mirrorBin (unBinIndex ix)))

-- | A colour is OFF every a/b bin boundary (and strictly inside the clamped
-- working range): the precondition of the σ-mirror law. @floor@-and-clamp
-- binning breaks the mirror exactly ON lattice planes.
offBinBoundary :: OKLab -> Bool
offBinBoundary (OKLab _ a b) = ok a && ok b
  where
    n    = fromIntegral coverageBinsPerAxis
    ok v = let u = (v + 0.5) * n
           in u > 0 && u < n && u /= fromIntegral (round u :: Int)

-- ---------------------------------------------------------------------------
-- Laws
-- ---------------------------------------------------------------------------

-- | ch0 sums to 1 for any non-empty palette input (the @normalisedMass@
-- analogue; in the app the count is exactly 64·256 so this is count/16384).
lawMassNormalized :: [[OKLab]] -> Bool
lawMassNormalized pals =
  null (concat pals) ||
  abs (V.sum (bMassPalettes (boardTensor pals [] [])) - 1) < 1e-9

-- | The board's binning IS 'Coverage.okLabBin', pointwise (the single-grid
-- contract shared with Swift's @gamutCoverage@).
lawBinAgreesWithCoverage :: OKLab -> Bool
lawBinAgreesWithCoverage c = binOf c == BinIdx (okLabBin c)

-- | σ-mirror, off bin boundaries: building the board from σ-reflected colours
-- equals 'boardSigma' of the board from the originals. Stated ONLY for inputs
-- off the a/b lattice planes (design §4.2 caveat); exact (no ε) — the mirror
-- is a permutation and the histogram weights are identical.
lawSigmaMirrorOffBoundary :: [[OKLab]] -> [OKLab] -> [OKLab] -> Bool
lawSigmaMirrorOffBoundary pals pixels cands =
  not (all offBinBoundary (concat pals ++ pixels ++ cands)) ||
  boardTensor (map (map sigmaReflect) pals)
              (map sigmaReflect pixels)
              (map sigmaReflect cands)
    == boardSigma (boardTensor pals pixels cands)

-- | Under 'boardSigma' the token multiset maps by negating columns 4–5 (the
-- a/b bin centres) and fixing all others — in particular the 3 curation
-- columns (10–12) are σ-invariant. Exact: bin centres are dyadic.
lawTokensSigmaInvariantCols :: Board16 -> Bool
lawTokensSigmaInvariantCols b =
  msort (boardTokens (boardSigma b)) == msort (map negateAB (boardTokens b))
  where
    negateAB t = [ if i == 4 || i == 5 then negate v else v
                 | (i, v) <- zip [0 :: Int ..] t ]
    msort = foldr insert []
    insert x []       = [x]
    insert x (y : ys) = if x <= y then x : y : ys else y : insert x ys

-- | Totality on the empty capture: no input ⇒ the all-zero board, no tokens.
lawTotalOnEmpty :: Bool
lawTotalOnEmpty =
  boardTensor [] [] [] == emptyBoard && null (boardTokens emptyBoard)

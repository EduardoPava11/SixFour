{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE OverloadedStrings #-}
{- |
Module      : SixFour.Gen.Stats
Description : Exact palette-entropy targeting, §8 measurement, and JSON labels.

Three jobs:

  * __Target__ an /exact/ Shannon palette-entropy @H(w)@ per frame
    ('populationsForEntropy'): a monotone 1-D search over a Zipf skew exponent,
    floored at @minPopulation@ and apportioned to the 4096-pixel budget. This
    is the literal "calculated entropy".
  * __Measure__ the full statistical label of a stack ('measure'): the 16-D §8
    'descriptor', the per-frame @H(w)@/@H_g@ trajectories, LAB gamut coverage,
    and the effective colour dimension. All reused from the spec — this module
    computes nothing new, it only assembles.
  * __Serialize__ the label to JSON ('reportJSON') and a compact GIF comment
    ('summaryComment'). Hand-rolled (numbers + strings) so no @aeson@ dep.
-}
module SixFour.Gen.Stats
  ( -- * Exact entropy targeting
    populationsForEntropy
  , populationsForEntropySixFour
  , weightsForEntropySixFour
    -- * Measurement
  , CoreStats (..)
  , descriptorFieldNames
  , measure
  , measureFast
    -- * Serialization
  , reportJSON
  , summaryComment
  ) where

import           Data.List           (sortBy, intercalate)
import           Data.Ord            (comparing, Down (..))
import           GHC.TypeLits        (KnownNat)
import qualified Data.Vector         as V
import qualified Data.Text           as T

import SixFour.Spec.Shape   (pixelsPerFrame, kVal)
import SixFour.Spec.Color   (OKLab)
import SixFour.Spec.Palette (Palette, paletteToList)
import SixFour.Spec.Cyclic  ( Weights, CyclicStack (..), SinkhornParams
                            , descriptor, descriptorDim
                            , paletteEntropy, gaussianColorEntropy
                            , costMatrix, transitionPlan, transportCost
                            , transportEntropy, dftPower, spectralEntropy, entropyRate )
import SixFour.Spec.Coverage  (gamutCoverageFraction)
import SixFour.Spec.Diversity (effectiveDim)

import SixFour.Gen.Realize (quantizeWeights)
import SixFour.Gen.Synth   (SynthParams (..))

-- ---------------------------------------------------------------------------
-- Exact entropy targeting
-- ---------------------------------------------------------------------------

-- | Integer pixel populations over @k@ slots (budget @budget@, floor @floorN@)
-- whose Shannon entropy @H(w) = −Σ p log p@ is as close as possible to
-- @targetH@ (natural log; range @[0, log k]@). A Zipf family @w_i ∝ (i+1)^{−α}@
-- has entropy monotone-decreasing in the skew @α@, so a binary search on @α@
-- lands the target; the result is clamped to the achievable band the floor
-- allows. The returned counts feed 'SixFour.Gen.Realize.realize' unchanged.
populationsForEntropy :: Int -> Int -> Int -> Double -> [Int]
populationsForEntropy budget floorN k targetH =
  quantizeWeights budget floorN (zipfWeights k (solveAlpha budget floorN k targetH))

-- | A Zipf weight vector @w_i ∝ (i+1)^{−α}@ over @k@ slots.
zipfWeights :: Int -> Double -> Weights
zipfWeights k a = V.generate k (\i -> (fromIntegral (i + 1)) ** negate a)

-- | Binary-search the Zipf skew @α@ so that the entropy of the quantized
-- populations equals @targetH@. @H(α)@ is monotone-decreasing in @α@.
solveAlpha :: Int -> Int -> Int -> Double -> Double
solveAlpha budget floorN k targetH = search 0 50 (64 :: Int)
  where
    hAt a = paletteEntropy (V.fromList (map fromIntegral
                              (quantizeWeights budget floorN (zipfWeights k a))))
    search lo hi n
      | n <= 0    = (lo + hi) / 2
      | otherwise = let mid = (lo + hi) / 2
                    in if hAt mid > targetH then search mid hi (n - 1)
                                            else search lo mid (n - 1)

-- | 'populationsForEntropy' at the SixFour shape (budget 4096, floor 2, K 256).
populationsForEntropySixFour :: Double -> [Int]
populationsForEntropySixFour = populationsForEntropy pixelsPerFrame 2 kVal

-- | The /continuous/ solved-Zipf weights for a target @H(w)@ at the SixFour
-- shape. Feed these to 'SixFour.Gen.Realize.realize' so the floor-2
-- apportionment quantizes exactly __once__ (passing the pre-quantized
-- 'populationsForEntropySixFour' would quantize twice and inflate the floor
-- slots, pushing low targets upward). @realize ∘ this@ hits @H(w) = targetH@.
weightsForEntropySixFour :: Double -> Weights
weightsForEntropySixFour h = zipfWeights kVal (solveAlpha pixelsPerFrame 2 kVal h)

-- ---------------------------------------------------------------------------
-- Measurement
-- ---------------------------------------------------------------------------

-- | The statistical label of one GIF (everything is a reused spec functional).
data CoreStats = CoreStats
  { csDescriptor :: ![Double]   -- ^ the 16-D §8 descriptor (label order below)
  , csPerFrameHW :: ![Double]   -- ^ palette entropy H(w_t), one per frame
  , csPerFrameHG :: ![Double]   -- ^ Gaussian colour entropy H_g(t), per frame
  , csCoverage   :: !Double     -- ^ LAB gamut coverage fraction ∈ [0,1]
  , csEffDim     :: !Double     -- ^ effective colour dimension ∈ [0,3]
  } deriving (Eq, Show)

-- | Human/JSON names for the 16 descriptor components (matches the field order
-- in "SixFour.Spec.Cyclic".descriptor and the Rust oracle).
descriptorFieldNames :: [String]
descriptorFieldNames =
  [ "meanPaletteEntropy", "sdPaletteEntropy"
  , "meanColorEntropy",   "sdColorEntropy"
  , "totalTransportCost", "meanTransportCost", "meanTransportEntropy"
  , "spectralEntropyHW",  "spectralEntropyHG", "spectralEntropyCost"
  , "entropyRateHW",      "holonomyDefect"
  , "acPower1", "acPower2", "acPower3", "acPower4"
  ]

-- | Measure the full label of a stack. One 'descriptor' call (the costly part,
-- incl. holonomy) plus cheap per-frame entropies, coverage and effective dim.
measure
  :: forall t k. (KnownNat t, KnownNat k)
  => SinkhornParams -> CyclicStack t k -> CoreStats
measure params stk@(CyclicStack frames) =
  CoreStats
    { csDescriptor = V.toList (descriptor params stk)
    , csPerFrameHW = [ paletteEntropy w           | (_, w) <- fr ]
    , csPerFrameHG = [ gaussianColorEntropy p w   | (p, w) <- fr ]
    , csCoverage   = gamutCoverageFraction (map fst fr)
    , csEffDim     = effectiveDim pooled
    }
  where
    fr     = V.toList frames
    pooled = concat [ zip (paletteToList p) (V.toList w) | (p, w) <- fr ]

-- | Like 'measure' but omits the O(T·K³) holonomy defect (descriptor index 11
-- becomes @NaN@ → @null@ in JSON). Mirrors "SixFour.Spec.Cyclic".descriptor
-- component-for-component using the same exported primitives — only the
-- holonomy matrix-product chain is skipped — so the other 15 labels are
-- identical to full mode. Drops ~19s/GIF to ~1s for bulk corpus generation.
measureFast
  :: forall t k. (KnownNat t, KnownNat k)
  => SinkhornParams -> CyclicStack t k -> CoreStats
measureFast params (CyclicStack frames) =
  CoreStats
    { csDescriptor = descVec
    , csPerFrameHW = hW
    , csPerFrameHG = hG
    , csCoverage   = gamutCoverageFraction (map fst fr)
    , csEffDim     = effectiveDim pooled
    }
  where
    fr     = V.toList frames
    nt     = V.length frames
    pooled = concat [ zip (paletteToList p) (V.toList w) | (p, w) <- fr ]
    hW     = [ paletteEntropy w         | (_, w) <- fr ]
    hG     = [ gaussianColorEntropy p w | (p, w) <- fr ]
    transitions =
      [ (transportCost plan cost, transportEntropy plan)
      | t <- [0 .. nt - 1]
      , let (pa, wa) = frames V.! t
            (pb, wb) = frames V.! ((t + 1) `mod` nt)
            cost     = costMatrix pa pb
            plan     = transitionPlan params cost wa wb ]
    costs  = map fst transitions
    tpEnts = map snd transitions
    acPow  = let ac = drop 1 (dftPower hW); tot = sum ac
             in if tot <= 1e-12 then map (const 0) ac else map (/ tot) ac  -- finite (see Cyclic)
    coeff i = if i < length acPow then acPow !! i else 0
    descVec =
      [ meanD hW, sdD hW, meanD hG, sdD hG
      , sum costs, meanD costs, meanD tpEnts
      , spectralEntropy hW, spectralEntropy hG, spectralEntropy costs
      , entropyRate hW
      , 0 / 0                              -- holonomy omitted (fast mode) → null
      , coeff 0, coeff 1, coeff 2, coeff 3 ]

meanD :: [Double] -> Double
meanD [] = 0
meanD xs = sum xs / fromIntegral (length xs)

sdD :: [Double] -> Double
sdD [] = 0
sdD xs = let m = meanD xs in sqrt (meanD [ (x - m) ** 2 | x <- xs ])

-- ---------------------------------------------------------------------------
-- Serialization (tiny hand-rolled JSON)
-- ---------------------------------------------------------------------------

-- | A full manifest record: name, optional synth knobs, and the measured label.
reportJSON :: String -> Maybe SynthParams -> CoreStats -> T.Text
reportJSON name mparams cs =
  jObj
    [ ("name",          jStr name)
    , ("params",        maybe jNull paramsJSON mparams)
    , ("coverage",      jNum (csCoverage cs))
    , ("effectiveDim",  jNum (csEffDim cs))
    , ("descriptor",    jObj (zip descriptorFieldNames (map jNum (padTo descriptorDim (csDescriptor cs)))))
    , ("descriptorVector", jArr (map jNum (csDescriptor cs)))
    , ("perFrame",      jObj [ ("paletteEntropy", jArr (map jNum (csPerFrameHW cs)))
                             , ("colorEntropy",   jArr (map jNum (csPerFrameHG cs))) ])
    ]

paramsJSON :: SynthParams -> T.Text
paramsJSON p = jObj
  [ ("nClusters", jNum (fromIntegral (nClusters p)))
  , ("spread",    jNum (spread p))
  , ("drift",     jNum (drift p))
  , ("gamut",     jNum (gamut p))
  , ("concSkew",  jNum (concSkew p))
  , ("popDrift",  jNum (popDrift p))
  , ("seed",      jNum (fromIntegral (seed p)))
  ]

-- | One-line metadata stamped into the GIF Comment Extension.
summaryComment :: String -> CoreStats -> T.Text
summaryComment name cs =
  T.pack (intercalate " | "
    [ "SixFour spec-gen/stats"
    , name
    , "H(w)~"     ++ show3 (mean (csPerFrameHW cs))
    , "H_g~"      ++ show3 (mean (csPerFrameHG cs))
    , "coverage=" ++ show3 (csCoverage cs)
    , "effDim="   ++ show3 (csEffDim cs)
    , "holonomy=" ++ show3 (atOr 11 (csDescriptor cs))
    , "transport="++ show3 (atOr 4  (csDescriptor cs))
    ])

-- JSON primitives ----------------------------------------------------------

jObj :: [(String, T.Text)] -> T.Text
jObj kvs = "{" <> T.intercalate "," [ jStr k <> ":" <> v | (k, v) <- kvs ] <> "}"

jArr :: [T.Text] -> T.Text
jArr xs = "[" <> T.intercalate "," xs <> "]"

jStr :: String -> T.Text
jStr s = "\"" <> T.concatMap esc (T.pack s) <> "\""
  where esc '"'  = "\\\""
        esc '\\' = "\\\\"
        esc c    = T.singleton c

jNum :: Double -> T.Text
jNum x | isNaN x || isInfinite x = "null"
       | otherwise               = T.pack (show x)

jNull :: T.Text
jNull = "null"

-- small helpers -------------------------------------------------------------

padTo :: Int -> [Double] -> [Double]
padTo n xs = take n (xs ++ repeat 0)

atOr :: Int -> [Double] -> Double
atOr i xs = if i < length xs then xs !! i else 0

mean :: [Double] -> Double
mean [] = 0
mean xs = sum xs / fromIntegral (length xs)

show3 :: Double -> String
show3 x = show (fromIntegral (round (x * 1000) :: Integer) / 1000 :: Double)

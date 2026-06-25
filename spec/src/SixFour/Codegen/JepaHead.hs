{- |
Module      : SixFour.Codegen.JepaHead
Description : Emit @jepa_head_golden.json@ — the I-JEPA HEAD golden: the training-trajectory
endpoints of the only learned object (@theta_B@) plus byte-exact forward witnesses of the
77-param position-conditioned head. The MLX trainer (@trainer/mlx/@) is FORCED to reproduce
them, so the spec is the DESIGN AUTHORITY for the trainer, not just the data
("SixFour.Codegen.JepaData" does the same for the corpus).

Two things are pinned:

  * The TRAJECTORY endpoints from "SixFour.Spec.MaskedBandTrainer": 'trainerExample',
    'trainerSteps', 'goldenFloorBand' (@0@) and 'goldenTrainedBand' (@3000@) — the byte the
    MLX-trained @theta_B@ and the device forward pass must both reproduce.
  * FORWARD witnesses of 'predictMaskedBandPos' (the 77-param position head, which previously
    had NO golden). Each witness uses a SINGLE non-zero parameter so the readout is one term —
    there is no float summation order for the Haskell and Python tiers to disagree on, so the
    crossing is byte-exact by construction. Each still gates a real lane: the masked-row
    selection, one feature (bias / coarse / sibling / x / y), and the single @reenterQ16@ crossing.

GHC-boot-only; the emitter returns @Text@ like the other @Codegen.*@ emitters. Additive: pins
nothing new in the spec, re-pins no shipped contract.
-}
module SixFour.Codegen.JepaHead
  ( emitJepaHeadGolden
  ) where

import Data.List (intercalate)
import Data.Text (Text)
import qualified Data.Text as T

import SixFour.Spec.OctreeCell (Detail)
import SixFour.Spec.MaskedBandPrediction
  ( numBands, featureCountB, paramCountB, positionFeatureCount, paramCountBPos
  , MaskedBandExamplePos, predictMaskedBandPos )
import SixFour.Spec.MaskedBandTrainer
  ( trainerExample, trainerSteps, goldenFloorBand, goldenTrainedBand )

-- | A 77-wide one-hot parameter vector: weight @w@ at flat index @i@, zero elsewhere. One
-- non-zero term ⇒ the position readout is a single product, byte-exact across tiers.
oneHot :: Int -> Double -> [Double]
oneHot i w = [ if j == i then w else 0 | j <- [0 .. paramCountBPos - 1] ]

-- | The flat parameter index of feature @k@ in band @m@'s row (rows of 'positionFeatureCount').
rowFeature :: Int -> Int -> Int
rowFeature m k = m * positionFeatureCount + k

-- | One forward witness: a label, the single active (index, weight), and the example. The
-- predicted byte is computed by the spec's 'predictMaskedBandPos' (the authority).
data Witness = Witness
  { wLabel  :: String
  , wIndex  :: Int
  , wWeight :: Double
  , wEx     :: MaskedBandExamplePos
  }

-- | A detail with one band set (others zero), to drive a sibling-feature witness.
detailWith :: Int -> Int -> Detail
detailWith band v =
  let bands = [ if j == band then v else 0 | j <- [0 .. numBands - 1] ]
  in case bands of [a,b,c,d,e,f,g] -> (a,b,c,d,e,f,g); _ -> (0,0,0,0,0,0,0)

-- | The forward witnesses. Each isolates one lane with weight @1.0@ on a single feature:
-- the bias maps to @65536@, the coarse/sibling/x/y features map their Q16 input back to a byte.
witnesses :: [Witness]
witnesses =
  [ -- floor: zero params ⇒ floor band 0 (zero-genome == floor at the position head)
    Witness "floor-band0"     (rowFeature 0 0) 0.0 (20000, detailWith 0 3000, 0, (32768, 0))
    -- bias feature (phi_B0 = 1): raw = 1.0 ⇒ predict = 1.0 * 65536 = 65536
  , Witness "bias-band0"      (rowFeature 0 0) 1.0 (20000, detailWith 0 3000, 0, (32768, 0))
    -- coarse feature (phi = v~): raw = v/65536 ⇒ predict = v = 20000
  , Witness "coarse-band0"    (rowFeature 0 1) 1.0 (20000, detailWith 0 3000, 0, (0, 0))
    -- first sibling feature (mask 0 ⇒ band 1 is sibling slot 0 at row index 3): predict = 5000
  , Witness "sibling-band0"   (rowFeature 0 3) 1.0 (20000, detailWith 1 5000, 0, (0, 0))
    -- x position token (row index 9): predict = x = 12345
  , Witness "posx-band0"      (rowFeature 0 9) 1.0 (20000, detailWith 0 0, 0, (12345, 0))
    -- y position token (row index 10): predict = y = 6789
  , Witness "posy-band0"      (rowFeature 0 10) 1.0 (20000, detailWith 0 0, 0, (0, 6789))
    -- a DIFFERENT masked row (band 3) selects row 3's bias ⇒ predict = 65536 (row selection)
  , Witness "bias-band3"      (rowFeature 3 0) 1.0 (20000, detailWith 3 4000, 3, (32768, 0))
  , Witness "bias-band6"      (rowFeature 6 0) 1.0 (20000, detailWith 6 7000, 6, (0, 32768))
  ]

witnessJson :: Witness -> String
witnessJson w =
  let (coarse, det, mask, (x, y)) = wEx w
      (d0,d1,d2,d3,d4,d5,d6) = det
      predicted = predictMaskedBandPos (oneHot (wIndex w) (wWeight w)) (wEx w)
      arr xs = "[" ++ intercalate "," (map show xs) ++ "]"
  in "    {\"label\":\"" ++ wLabel w ++ "\""
     ++ ",\"index\":" ++ show (wIndex w)
     ++ ",\"weight\":" ++ show (wWeight w)
     ++ ",\"coarse\":" ++ show coarse
     ++ ",\"detail\":" ++ arr [d0,d1,d2,d3,d4,d5,d6]
     ++ ",\"mask\":" ++ show mask
     ++ ",\"x\":" ++ show x ++ ",\"y\":" ++ show y
     ++ ",\"predicted\":" ++ show predicted ++ "}"

-- | The head golden: shape, the training-trajectory endpoints, and the forward witnesses.
emitJepaHeadGolden :: Text
emitJepaHeadGolden = T.pack $
  let (tCoarse, tDet, tMask) = trainerExample
      (e0,e1,e2,e3,e4,e5,e6) = tDet
      arr xs = "[" ++ intercalate "," (map show xs) ++ "]"
  in unlines
    [ "{"
    , "  \"_doc\": \"I-JEPA head golden (SixFour.Codegen.JepaHead): theta_B training-trajectory\","
    , "  \"_doc2\": \"endpoints + single-active-term forward witnesses of the 77-param position head.\","
    , "  \"numBands\": " ++ show numBands ++ ","
    , "  \"featureCountB\": " ++ show featureCountB ++ ","
    , "  \"paramCountB\": " ++ show paramCountB ++ ","
    , "  \"positionFeatureCount\": " ++ show positionFeatureCount ++ ","
    , "  \"paramCountBPos\": " ++ show paramCountBPos ++ ","
    , "  \"trainer\": {"
    , "    \"coarse\": " ++ show tCoarse ++ ","
    , "    \"detail\": " ++ arr [e0,e1,e2,e3,e4,e5,e6] ++ ","
    , "    \"mask\": " ++ show tMask ++ ","
    , "    \"steps\": " ++ show trainerSteps ++ ","
    , "    \"goldenFloorBand\": " ++ show goldenFloorBand ++ ","
    , "    \"goldenTrainedBand\": " ++ show goldenTrainedBand
    , "  },"
    , "  \"posForward\": ["
    , intercalate ",\n" (map witnessJson witnesses)
    , "  ]"
    , "}"
    ]

{- |
Module      : SixFour.Codegen.JepaData
Description : Emit @jepa_data_golden.json@ — the I-JEPA training CORPUS golden. The spec
manufactures a fixed-seed set of @(cube, coarse, detail, mask, target)@ records via the
reversible lift ("SixFour.Spec.JepaData"); the Python data-loader (@trainer/jepa_data.py@) is
FORCED to reproduce them byte-exact. This is what makes the spec the DESIGN AUTHORITY for the
training data, not just a description of it: the data pipeline cannot drift from the spec.

Each record is proven invertible by @Spec.JepaData.lawDataEngineRoundTrips@
(@reconstruct (manufacture cube m) == cube@), so the corpus is a set of TRUE labels.
-}
module SixFour.Codegen.JepaData
  ( emitJepaDataGolden
  ) where
-- (emitter returns Text to match the other Codegen.* emitters / writeUtf8)

import Data.List (intercalate)
import Data.Text (Text)
import qualified Data.Text as T

import SixFour.Spec.OctreeCell (V8(..))
import SixFour.Spec.MaskedBandPrediction (numBands)
import SixFour.Spec.JepaData (manufactureExample, heldTarget)

-- | A deterministic spread of octant cells for cube @i@ (no RNG — reproducible across tiers).
mkCube :: Int -> V8 Int
mkCube i = V8 (f 0) (f 1) (f 2) (f 3) (f 4) (f 5) (f 6) (f 7)
  where f j = ((i * 101 + j * 37 + 13) `mod` 4096) - 2048   -- in [-2048, 2047]

-- | The fixed corpus: 8 cubes x 3 masks {0,3,6} = 24 records.
corpus :: [(V8 Int, Int)]
corpus = [ (mkCube i, m) | i <- [0 .. 7], m <- [0, 3, 6] ]

-- | One record as a JSON object.
recordJson :: (V8 Int, Int) -> String
recordJson (cube, m) =
  let (coarse, det, mask) = manufactureExample cube m
      (d0, d1, d2, d3, d4, d5, d6) = det
      V8 a b c e f g h i = cube
      target = heldTarget (coarse, det, mask)
      arr xs = "[" ++ intercalate "," (map show xs) ++ "]"
  in "    {\"cube\":" ++ arr [a, b, c, e, f, g, h, i]
     ++ ",\"coarse\":" ++ show coarse
     ++ ",\"detail\":" ++ arr [d0, d1, d2, d3, d4, d5, d6]
     ++ ",\"mask\":" ++ show mask
     ++ ",\"target\":" ++ show target ++ "}"

-- | The full corpus golden. @numBands@ + the record list; the loader asserts byte-equality.
emitJepaDataGolden :: Text
emitJepaDataGolden = T.pack $
  unlines
    [ "{"
    , "  \"_doc\": \"I-JEPA data-engine corpus golden (SixFour.Codegen.JepaData). Each record is\","
    , "  \"_doc2\": \"manufactured from cube via the reversible liftOct; reconstruct==cube (a true label).\","
    , "  \"numBands\": " ++ show numBands ++ ","
    , "  \"records\": ["
    , intercalate ",\n" (map recordJson corpus)
    , "  ]"
    , "}"
    ]

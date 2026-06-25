{- |
Module      : SixFour.Codegen.TemporalData
Description : Emit @temporal_data_golden.json@ — the TEMPORAL (inter-frame) data-engine golden.
The spec manufactures @(frame t, value target, policy target)@ records from captured frame PAIRS
@(t, t+1)@ ("SixFour.Spec.TemporalData"); the Python loader (@trainer/mlx/temporal_data.py@) is
FORCED to reproduce them byte-exact, the time-axis sibling of "SixFour.Codegen.JepaData".

The keystone the golden pins is 'SixFour.Spec.TemporalData.lawTemporalEngineRoundTrips':
@reconstructNext (manufacture ct ctNext) == ctNext@ — applying both data-manufactured deltas to
frame @t@ recovers frame @t+1@ EXACTLY. So the VALUE (recolour) and POLICY (motion) targets are
TRUE labels read off the REAL next frame, not a self-produced rollout — the time-axis analogue of
the collapse guard (no self-produced target). The golden also lets the loader check
'lawTemporalChannelsDisjoint': the value delta touches only the palette, the policy only the index.

GHC-boot-only; the emitter returns @Text@. Additive: pins nothing new in the spec.
-}
module SixFour.Codegen.TemporalData
  ( emitTemporalDataGolden
  ) where

import Data.List (intercalate)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Map as M

import SixFour.Spec.ConstructionEncoder (Construction(..), QColour)
import SixFour.Spec.HierarchicalDelta (ColourDelta(..), IndexDelta(..))
import SixFour.Spec.TemporalData
  (TemporalExample(..), manufactureTemporalExample)

-- | A deterministic same-shape frame pair (depth 1 = 8 voxels, 4-colour palette): a label and the
-- captured @(frame t, frame t+1)@. The three cases exercise recolour-only, motion-only, and both.
framePairs :: [(String, Construction, Construction)]
framePairs =
  [ ( "recolour-only"
    , Construction 1 [(1000,0,0),(2000,100,-50),(3000,-200,300),(0,0,0)]   [0,1,2,3,0,1,2,3]
    , Construction 1 [(1100,10,-5),(2000,100,-50),(2900,-180,290),(50,0,0)] [0,1,2,3,0,1,2,3] )
  , ( "motion-only"
    , Construction 1 [(1000,0,0),(2000,100,-50),(3000,-200,300),(0,0,0)] [0,1,2,3,0,1,2,3]
    , Construction 1 [(1000,0,0),(2000,100,-50),(3000,-200,300),(0,0,0)] [3,2,1,0,3,2,1,0] )
  , ( "recolour-and-motion"
    , Construction 1 [(1000,0,0),(2000,100,-50),(3000,-200,300),(0,0,0)]   [0,1,2,3,0,1,2,3]
    , Construction 1 [(1500,-30,40),(1900,90,-40),(3000,-200,300),(100,5,5)] [1,1,2,0,3,2,2,0] )
  ]

qcJson :: QColour -> String
qcJson (l, a, b) = "[" ++ show l ++ "," ++ show a ++ "," ++ show b ++ "]"

paletteJson :: [QColour] -> String
paletteJson xs = "[" ++ intercalate "," (map qcJson xs) ++ "]"

intArr :: [Int] -> String
intArr xs = "[" ++ intercalate "," (map show xs) ++ "]"

-- | The policy delta as a sorted @[[pos, old, new], ...]@ list (Data.Map is ordered by key).
policyJson :: IndexDelta -> String
policyJson (IndexDelta m) =
  "[" ++ intercalate "," [ "[" ++ show v ++ "," ++ show o ++ "," ++ show n ++ "]"
                         | (v, (o, n)) <- M.toList m ] ++ "]"

recordJson :: (String, Construction, Construction) -> String
recordJson (label, ct, ctNext) =
  let te = manufactureTemporalExample ct ctNext
      ColourDelta value = teValueTarget te
  in "    {\"label\":\"" ++ label ++ "\""
     ++ ",\"depth\":" ++ show (cDepth ct)
     ++ ",\"palette_t\":" ++ paletteJson (cPalette ct)
     ++ ",\"index_t\":"   ++ intArr (cIndex ct)
     ++ ",\"value\":"     ++ paletteJson value
     ++ ",\"policy\":"    ++ policyJson (tePolicyTarget te)
     ++ ",\"palette_next\":" ++ paletteJson (cPalette ctNext)
     ++ ",\"index_next\":"   ++ intArr (cIndex ctNext) ++ "}"

-- | The temporal corpus golden: the frame pairs + their manufactured value/policy targets. The
-- loader applies its OWN port of the deltas and asserts it reconstructs @frame t+1@ byte-exact.
emitTemporalDataGolden :: Text
emitTemporalDataGolden = T.pack $
  unlines
    [ "{"
    , "  \"_doc\": \"Temporal (inter-frame) data-engine golden (SixFour.Codegen.TemporalData).\","
    , "  \"_doc2\": \"manufacture(ct,ctNext) value/policy deltas; reconstructNext==ctNext (true labels).\","
    , "  \"records\": ["
    , intercalate ",\n" (map recordJson framePairs)
    , "  ]"
    , "}"
    ]

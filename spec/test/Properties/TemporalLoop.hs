module Properties.TemporalLoop (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.TemporalLoop

-- The TemporalLoop laws were authored as exported predicates with their test wiring
-- deferred ("test wiring pending" in the module header); this gates all 8 so the loop
-- closure + lossless temporal residual are enforced, not lying-green.
tests :: TestTree
tests = testGroup "TemporalLoop (exact 64-frame loop closure + low-frequency temporal residual)"
  [ testProperty "loopIndex is the Zig bitmask t .&. 63 (non-negative t)"
      lawLoopIndexIsBitmask
  , testProperty "temporalCos is exactly periodic with period 64 (the loop closes)"
      lawTemporalLoopClosesExact
  , testProperty "frame after 63 lands on exactly frame 0 (seam continuous)" $
      once lawLoopWrapsLastToFirst
  , testProperty "the cosine LUT has exactly 64 entries" $
      once lawCosLutLength
  , testProperty "temporal Haar split is lossless: haarJoinTime . haarSplitTime == id"
      lawTemporalSplitJoinExact
  , testProperty "the temporal residual IS the Haar low band"
      lawTemporalResidualLowFreq
  , testProperty "the local pair lift is byte-identical to the owned integer Haar"
      lawTemporalLiftMatchesHaar
  , testProperty "temporalCos / temporalResidual are pure integer (deterministic)"
      lawTemporalDeterministic
  ]

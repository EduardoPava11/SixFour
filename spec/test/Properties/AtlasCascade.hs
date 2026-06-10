{- |
Module      : Properties.AtlasCascade
Description : Property tests for 'SixFour.Spec.AtlasCascade' — the ExitState
              carry/reset (cascadeInit-literal, bias.zig div semantics).
-}
module Properties.AtlasCascade (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Test.QuickCheck

import qualified Data.Vector as V

import SixFour.Spec.AtlasCascade

genStat :: Gen PixelStat
genStat = PixelStat
  <$> choose (0, 255)
  <*> choose (-300, 300) <*> choose (-300, 300) <*> choose (-300, 300)
  <*> choose (-64, 64)   <*> choose (-64, 64)
  <*> choose (-64, 64)

genExit :: Gen ExitState
genExit = deriveExit <$> choose (0, 1000) <*> resize 64 (listOf genStat)

tests :: TestTree
tests = testGroup "AtlasCascade (ExitState carry/reset, 256 x 16 B)"
  [ testProperty "layout sums: 16 B/slot by construction, 256*16 = 4096" $
      forAll genExit lawLayoutSum4096
  , testProperty "exitInit zeroes the mass plane ONLY" $
      forAll genExit lawInitZeroesMassOnly
  , testProperty "carried 12 B/slot are byte-identical across init" $
      forAll genExit lawCarriedBytesIdentical
  , testProperty "init is idempotent on the slot plane" $
      forAll genExit lawInitIdempotentOnCarry
  , testProperty "GOLDEN: Q15/Q8.8 truncated-div means match bias.zig verbatim" $
      property lawQ15TruncDivMatchesQuad
  , testProperty "session counter increments by exactly one" $
      forAll genExit lawCounterMonotone
  , testProperty "deriveExit: slot mass = assigned-pixel count" $
      forAll (resize 64 (listOf genStat)) $ \stats ->
        let e = deriveExit 0 stats
        in and [ fromIntegral (seMass (exitSlots e V.! j))
                   == length (filter ((== j) . psSlot) stats)
               | j <- [0, 1, 7, 255] ]
  , testProperty "deriveExit of no stats is the empty plane" $
      forAll (choose (0, 9)) $ \c ->
        exitSlots (deriveExit c []) == exitSlots emptyExit
  , testProperty "rates are means: single-pixel slot reproduces its sample scaled" $
      forAll genStat $ \p ->
        let e = deriveExit 0 [p]
            s = exitSlots e V.! psSlot p
        in seDL s == clampI16 (fromIntegral (psDL p) * 128)
             && seDX s == clampI16 (fromIntegral (psDX p) * 256)
             && seDT s == clampI16 (fromIntegral (psDT p) * 256)
  ]

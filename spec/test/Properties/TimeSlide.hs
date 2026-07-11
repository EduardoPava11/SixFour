module Properties.TimeSlide (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.TimeSlide
import SixFour.Spec.MergeBoard (GameOp (..), MoveOp (..), regionCount)

-- Ops include out-of-range regions on purpose (refusals are total no-ops);
-- the slide law must hold over any board history.
genOp :: Gen GameOp
genOp = frequency
  [ (3, pure GPour)
  , (7, GMove <$> choose (-2, regionCount + 1)
              <*> elements [OpS, OpK, OpI])
  ]

genOps :: Gen [GameOp]
genOps = resize 60 (listOf genOp)

genQ16 :: Gen Integer
genQ16 = choose (-1000000, 1000000)

tests :: TestTree
tests = testGroup "TimeSlide (slide-to-dilate: detents are rungs, groups are poured windows, integrals divide once, the loop is always 320 cs)"
  [ -- The detent quantizer ---------------------------------------------------
    testProperty "cellsPerDetent WITNESS: the one named tuning integer is 16 (one region side of travel per rung)" $
      once (cellsPerDetent == 16)

  , testProperty "lawDetentTotal: every latch/travel pair lands in {0,1,2}" $
      \k dy -> lawDetentTotal k dy

  , testProperty "lawDetentMonotone: more downward travel never yields a finer detent" $
      \k dy1 dy2 -> lawDetentMonotone k dy1 dy2

  , testProperty "lawDetentEndpoints: zero travel holds the latch; one cellsPerDetent steps one rung; far travel clamps" $
      \k -> lawDetentEndpoints k

  , testProperty "lawDetentsAreRungs: periods exactly [1,2,4] ticks; the 3-tick delay is refused (64 mod 3 /= 0)" $
      once lawDetentsAreRungs

    -- The playhead on the one clock ------------------------------------------
  , testProperty "lawGroupChangesExactlyOnRealize: the display group steps iff realizesAt fires on the anchor offset" $
      \k aT aF t -> lawGroupChangesExactlyOnRealize k aT aF t

  , testProperty "lawGroupWindowIsPouredWindow (KEYSTONE): group j frames +1 == pouredWindow ENDING at r=(j+1)*2^k" $
      \k j -> lawGroupWindowIsPouredWindow k j

    -- The temporal integral --------------------------------------------------
  , testProperty "lawIntegralFineIsIdentity: the k=0 integral is the frame untouched" $
      \w j -> forAll (listOf genQ16) $ \flat -> lawIntegralFineIsIdentity w j flat

  , testProperty "lawIntegralIsSumsDividedOnce: subsums compose, ONE divide by 2^k (never 8^k), constants realize to themselves" $
      \k j -> forAll (listOf genQ16) $ \flat -> lawIntegralIsSumsDividedOnce k j flat

  , testProperty "lawLoopWallTimeInvariant (GRAFT): 64 ticks = 320 cs at EVERY detent — slower is chunkier, never longer" $
      once lawLoopWallTimeInvariant

    -- Round-half-up over negatives -------------------------------------------
  , testProperty "lawDivRoundHalfUpNegatives: the pinned negative-operand vectors (div floors; quot ports diverge at -5/4)" $
      once lawDivRoundHalfUpNegatives

  , testProperty "divRoundHalfUp is EXACTLY round-half-up: 2nq - n <= 2s < 2nq + n for every s and n >= 1" $
      forAll genQ16 $ \s -> forAll (choose (1, 4096)) $ \n ->
        let q = divRoundHalfUp s n
        in 2 * n * q - n <= 2 * s && 2 * s < 2 * n * q + n

    -- The slide never plays the board ----------------------------------------
  , testProperty "lawSlideNeverWritesTheWord: no detent/playhead transition yields a GameOp; replay is untouched" $
      \kFrom kTo -> forAll genOps $ \ops -> lawSlideNeverWritesTheWord kFrom kTo ops

    -- The cross-language goldens ---------------------------------------------
  , testProperty "goldenPlayhead16: the pinned 48-row playhead table (k x 16 ticks; the Swift twin mirrors this verbatim)" $
      once (goldenPlayhead16 ==
        [ (k, t, t, t `div` (2 ^ k), t `mod` (2 ^ k) == 0)
        | k <- [0 .. 2], t <- [0 .. 15] ])

  , testProperty "goldenIntegralQ16: the pinned negative-channel integral frames at k=0/1/2 (hand-derived literals)" $
      once (goldenIntegralQ16 ==
        [ (0, goldenVolumeQ16)
        , (1, [ [5, -3, 2, -5, 1,  8, 2, -1, 6, -6, 4, -2]
              , [6, -5, 4, -5, 3, 10, 4, -3, 4, -8, 6, -4] ])
        , (2, [ [6, -4, 3, -5, 2,  9, 3, -2, 5, -7, 5, -3] ])
        ])

  , testProperty "golden volume WITNESS: every frame carries negative entries (the a/b channels are genuinely signed)" $
      once (all (any (< 0)) goldenVolumeQ16)
  ]

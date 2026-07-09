module Properties.ColorTimeDisplay (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.ColorTimeDisplay
import SixFour.Spec.WeaveOrder (WeaveRung (..), unitsOf)

genRung :: Gen WeaveRung
genRung = elements [W64, W32, W16]

genTick :: Gen Int
genTick = choose (0, 4096)

tests :: TestTree
tests = testGroup "ColorTimeDisplay (the cadence-honest display beat: 4:2:1 realize, intake tallies, banked ledger, flux quantizer)"
  [ -- The one clock ----------------------------------------------------------
    testProperty "lawDisplayCadenceIsPoolDepth: refresh period = poolDepth (1/2/4), realize on the multiples" $
      forAll genRung $ \p -> forAll genTick $ \t -> lawDisplayCadenceIsPoolDepth p t

  , testProperty "FOIL (non-vacuity): a sample-and-hold at period 1 for W16 would violate the pinned ladder" $
      once (displayPeriodTicks W16 /= 1 && not (realizesAt W16 1))

  , testProperty "lawRealizeSamplesLadder: per-realize divisors 1 : 8 : 64 = unitsOf^3 (frames x pool area)" $
      once lawRealizeSamplesLadder

    -- The gathering beat -----------------------------------------------------
  , testProperty "lawTallyEqualsUnits: tally slot counts = unitsOf (2 over the 32-band, 4 over the 16-band)" $
      once lawTallyEqualsUnits

  , testProperty "lawTallyCyclicCover: any full period fills every slot exactly once; realize carries slot 0" $
      forAll genRung $ \p -> forAll genTick $ \t -> lawTallyCyclicCover p t

  , testProperty "lawPourWindowExact: the poured window is the n closing ticks, slot walk [1..n-1,0]" $
      forAll genRung $ \p -> forAll (choose (0, 1024)) $ \m -> lawPourWindowExact p m

  , testProperty "FOIL (non-vacuity): a window that started AT the realize tick would end on slot n-1, not 0" $
      once (map (tallySlot W16) [0 .. 3] /= map (tallySlot W16) (pouredWindow W16 4))

    -- The banked ledger ------------------------------------------------------
  , testProperty "lawLedgerConserves: 64 frames x 4 cells = 256 partitions the 16-square tile in order" $
      once lawLedgerConserves

  , testProperty "lawLedgerStepExact: fill is exact (+4 per landed frame), clamped, bounded" $
      forAll (choose (-8, 80)) lawLedgerStepExact

  , testProperty "FOIL (non-vacuity): 3 cells per frame would NOT conserve (3*64 /= 256)" $
      once (3 * burstFrames /= 256 && ledgerCellsPerFrame /= 3)

  , testProperty "lawBankedWindowExact: 5 cs per landed frame; 160/320cs at half; 320 at the full burst" $
      forAll (choose (-8, 80)) lawBankedWindowExact

    -- The flux quantizer -----------------------------------------------------
  , testProperty "lawFluxMonotoneBounded: bounded [0,16], zero at zero, monotone, log2 (doubling adds <= 1 cell)" $
      forAll (choose (0, 1000000)) $ \w1 -> forAll (choose (0, 1000000)) $ \w2 ->
        lawFluxMonotoneBounded w1 w2

  , testProperty "flux WITNESS: fills 0->0, 1->1, 2->2, 255->8, 65535->16, huge clamps at 16" $
      once (map fluxFillCount [0, 1, 2, 255, 65535, 123456789]
              == [0, 1, 2, 8, 16, 16])

    -- The golden cross-language schedule -------------------------------------
  , testProperty "goldenSchedule16: the pinned 16-tick schedule vector (Swift re-derives this exactly)" $
      once (goldenSchedule16 ==
        [ (t, even t, t `mod` 4 == 0, t `mod` 2, t `mod` 4) | t <- [0 .. 15] ])

  , testProperty "golden realize density: per 16 ticks the 32-band realizes 8x, the 16-band 4x (4:2:1)" $
      once ( length [ () | (_, r32, _, _, _) <- goldenSchedule16, r32 ] == 8
          && length [ () | (_, _, r16, _, _) <- goldenSchedule16, r16 ] == 4 )

  , testProperty "delegation WITNESS: framesPerRealize == unitsOf on every rung (four 64-ticks per 16-update)" $
      once (and [ framesPerRealize p == unitsOf p | p <- [W64, W32, W16] ]
              && framesPerRealize W16 == 4)
  ]

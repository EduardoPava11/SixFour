module Properties.MergeBoard (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.MergeBoard

-- Ops include OUT-OF-RANGE regions on purpose: totality ('OffBoard') is
-- part of the surface under test. Pours are common enough that random
-- walks actually afford some splits.
genOp :: Gen GameOp
genOp = frequency
  [ (3, pure GPour)
  , (7, GMove <$> choose (-2, regionCount + 1)
              <*> elements [OpS, OpK, OpI])
  ]

genOps :: Gen [GameOp]
genOps = resize 120 (listOf genOp)

genRegion :: Gen Region
genRegion = choose (0, regionCount - 1)

-- A directed run that ALWAYS fully constructs: 'canonicalConstruction'
-- interleaved with legality-preserving noise (holds, off-board ops, and
-- extra pours — none of which can starve a later split of signal or
-- evidence, and refusals are total no-ops).
genConstructionRun :: Gen [GameOp]
genConstructionRun = go canonicalConstruction
  where
    genNoise = frequency
      [ (2, pure GPour)
      , (4, GMove <$> genRegion <*> pure OpI)
      , (1, GMove <$> elements [-1, regionCount] <*> elements [OpS, OpK, OpI])
      ]
    go [] = pure []
    go (c : cs) = do
      pre <- resize 2 (listOf genNoise)
      rest <- go cs
      pure (pre ++ [c] ++ rest)

tests :: TestTree
tests = testGroup "MergeBoard (THE MERGE: 2048 inverted — S/K/I decomposition of the coarse board, pour economy, energy gate, the decision word as the training record)"
  [ -- The constants -------------------------------------------------------
    testProperty "lawInitIsCoarsest: the game opens on the all-16 board with an empty ledger and word" $
      once lawInitIsCoarsest

  , testProperty "lawEconomyIsTheWindow: 16 pours x 4 units == windowUnits == threshold32 (no free constants)" $
      once lawEconomyIsTheWindow

  , testProperty "lawSplitCostIsSTower: splitCost d = 2^d — the S-tower price (16->32 = 1, 32->64 = 2)" $
      once lawSplitCostIsSTower

  , testProperty "lawBoardPartitionsPlane: every 64^2 pixel in exactly one 16px-square region (the renderSelect field is total)" $
      once lawBoardPartitionsPlane

    -- The step algebra ----------------------------------------------------
  , testProperty "lawStepTotalAndRecorded: accepted ops append exactly themselves; rejected ops change NOTHING" $
      forAll genOps lawStepTotalAndRecorded

  , testProperty "lawSignalLedgerConserved: signal == deposits - spends, never negative, pours capped" $
      forAll genOps lawSignalLedgerConserved

  , testProperty "lawDepthCeiling: no reachable board escapes [0..2] — the 64 ceiling is honest" $
      forAll genOps lawDepthCeiling

  , testProperty "lawKKeepsAndNeverPays: K decrements only the depth; ledger and bank untouched" $
      forAll ((,) <$> genOps <*> genRegion) (uncurry lawKKeepsAndNeverPays)

    -- The energy gate -----------------------------------------------------
  , testProperty "lawUnlockMonotone: banked 32-evidence never decreases (K withdraws the claim, not the measurement)" $
      forAll genOps lawUnlockMonotone

  , testProperty "lawBankNeedsMeasurement: pours on the all-coarse board bank ZERO — measure at 32 before the gate can move" $
      forAll (choose (0, 32)) lawBankNeedsMeasurement

  , testProperty "lawPhaseGateIsEnergy: a 32->64 split is accepted iff the window is banked and the price funded" $
      forAll ((,) <$> genOps <*> genRegion) (uncurry lawPhaseGateIsEnergy)

    -- The record ----------------------------------------------------------
  , testProperty "lawWordReplaysBoard (KEYSTONE): replaying a board's own word reproduces the board exactly" $
      forAll genOps lawWordReplaysBoard

  , testProperty "lawWordReplaysBoard on directed full constructions" $
      forAll genConstructionRun lawWordReplaysBoard

  , testProperty "lawOrderSurvivesCancellation: S;K restores the depths but the word and the spend remember" $
      forAll ((,) <$> genOps <*> genRegion) (uncurry lawOrderSurvivesCancellation)

    -- Victory -------------------------------------------------------------
  , testProperty "lawWinCostsTheLadder: full construction needs >=32 S-moves, >=48 packets, and the banked window" $
      forAll genConstructionRun lawWinCostsTheLadder

  , testProperty "directed runs DO fully construct (the generator is not vacuous)" $
      forAll genConstructionRun (fullyConstructed . playAll)

  , testProperty "lawCanonicalRunConstructs: the pinned tight run — 12 pours, 48 spent, signal 0, word == run" $
      once lawCanonicalRunConstructs

    -- The SKI reading -----------------------------------------------------
  , testProperty "skiVerbOf is total and names the ladder: S@0=S_xy, S@1=S_xyt, K=K_t, I=hold" $
      once (   skiVerbOf OpS 0 == VerbSxy
            && skiVerbOf OpS 1 == VerbSxyt
            && skiVerbOf OpK 1 == VerbKt
            && skiVerbOf OpI 0 == VerbHold )
  ]

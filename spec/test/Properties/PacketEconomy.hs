module Properties.PacketEconomy (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.Q16 (toQ16)
import SixFour.Spec.DetailPredictor (defaultPredictorShape, paramCount)
import SixFour.Spec.PacketEconomy

nWords :: Int
nWords = paramCount defaultPredictorShape

geneOf :: [Int] -> Gene
geneOf ws = (defaultPredictorShape, map toQ16 (take nWords (ws ++ repeat 0)))

-- A held, data-manufactured target = the committed cloud of an expressive gene.
gTarget :: Gene
gTarget = geneOf [40,-20,30, 10,-5,15]

held :: HeldTarget
held = HeldTarget (decodeBytes gTarget)

-- gHigh matches the target exactly (max meaning) at FEW packets;
-- gMid is partial (lower meaning) at MORE packets, so gHigh Pareto-dominates it.
gHigh, gMid :: Gene
gHigh = gTarget
gMid  = geneOf [20,-10,15]

sHigh, sMid, sFloor :: Schedule
sHigh  = [I, S]          -- 1 packet above the floor
sMid   = [I, S, S, S]    -- 3 packets above the floor
sFloor = []              -- floor only, 0 packets

pool :: [(Gene, Schedule)]
pool = [ (gHigh, sHigh), (gMid, sMid), (floorGene, sFloor) ]

-- Random genes / schedules for the pairwise consistency law.
genGene :: Gen Gene
genGene = (\ws -> (defaultPredictorShape, map toQ16 ws)) <$> vectorOf nWords (choose (-40,40))

genSched :: Gen Schedule
genSched = (I :) <$> listOf (elements [K, S])

vacuousElite :: HeldTarget -> [(Gene,Schedule)] -> (Gene,Schedule) -> Bool
vacuousElite _ _ _ = False   -- the degenerate "nothing is ever elite"

tests :: TestTree
tests = testGroup "PacketEconomy (decode-compute is scarce: elites are meaning-per-S-packet Pareto-optimal)"
  [ testProperty "gHigh Pareto-dominates gMid (more meaning, fewer packets)" $
      once (dominates held (gHigh, sHigh) (gMid, sMid))

  , testProperty "KEYSTONE: a dominated gene is not an elite (over the whole pool)" $
      once (all (lawEfficiencyParetoDominated isElite held pool) pool)

  , testProperty "the dominated gMid is NOT elite; the undominated admitted gHigh IS" $
      once (not (isElite held pool (gMid, sMid)) && isElite held pool (gHigh, sHigh))

  , testProperty "LIVENESS: a pool with an admitted gene has a non-empty elite set" $
      once (lawEliteNonEmptyWhenAdmitted isElite held pool)

  , testProperty "NON-VACUITY: isElite = const False is REJECTED by liveness" $
      once (not (lawEliteNonEmptyWhenAdmitted vacuousElite held pool))

  , testProperty "every elite is admitted (elite set subset of admitted)" $
      once (all (lawEliteSubsetAdmitted isElite held pool) pool)

  , testProperty "floor gene is the Pareto origin (0 meaning, 0 packets, not admitted)" $
      once (lawFloorGeneIsParetoOrigin held)

  , testProperty "meaning-per-packet selection is integer cross-multiply (random genes)" $
      forAll genGene $ \gx -> forAll genGene $ \gy ->
      forAll genSched $ \sx -> forAll genSched $ \sy ->
        lawMeaningPerPacketSelected held (gx,sx) (gy,sy)

  , testProperty "packets charge only K/S, the leading I floor read is free" $
      once (packets sFloor == 0 && packets sHigh == 1 && packets sMid == 3 && packets [I] == 0)
  ]

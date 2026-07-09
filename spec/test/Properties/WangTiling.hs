module Properties.WangTiling (tests) where

import Data.List (nub)
import Data.Ratio ((%))
import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.WangTiling
import SixFour.Spec.OctantViews (Axis (..))
import SixFour.Spec.WeaveOrder (WeaveRung (..))

-- Oracle cell coordinates: exercised across a wide integer range (the exact
-- ℤ[φ] arithmetic is size-oblivious; a couple of dedicated once-tests go to ±1e9).
genCell :: Gen (Integer, Integer)
genCell = (,) <$> choose (-1000000, 1000000) <*> choose (-1000000, 1000000)

genGene :: Gen [Integer]
genGene = vectorOf 21 (choose (-262144, 262144))

tests :: TestTree
tests = testGroup "WangTiling (THE SCROLL substrate: Jeandel-Rao 11 tiles, exact toral oracle, tiles=SKI state machine, gene=attention, boot resolve, pour-group slices)"
  [ -- The tile set --------------------------------------------------------
    testProperty "lawElevenTiles: 11 pairwise-distinct tiles (minimal, arXiv:1506.06492 Thm 1)" $
      once lawElevenTiles

  , testProperty "lawFourColors: exactly 4 horizontal carriers (minimal) and 5 vertical grades" $
      once lawFourColors

    -- The exact ZPhi arithmetic ------------------------------------------
  , testProperty "ZPhi WITNESS: floor(phi)=1, floor(-phi)=-2, sign(phi-1)>0, sign(2-phi)>0, sign(1-phi)<0" $
      once (   floorQPhi phiQ == 1
            && floorQPhi (QPhi 0 (-1)) == -2
            && signQPhi (QPhi (-1) 1) > 0
            && signQPhi (QPhi 2 (-1)) > 0
            && signQPhi (QPhi 1 (-1)) < 0 )

  , testProperty "ZPhi floor vs integer shift: floor(q + n) == floor(q) + n (exact, any magnitude)" $
      forAll (choose (-1000000000, 1000000000)) $ \n ->
        floorQPhi (qAdd phiQ (qFromInt n)) == 1 + n

    -- The oracle ----------------------------------------------------------
  , testProperty "lawOracleWindowsValid (KEYSTONE): random 4x4 windows are edge-consistent Wang patches" $
      forAll genCell lawOracleWindowsValid

  , testProperty "lawOracleWindowsValid at +-1e9: the exact arithmetic does not degrade far from origin" $
      once (lawOracleWindowsValid (1000000000, -1000000000)
              && lawOracleWindowsValid (-999999937, 999999937))

  , testProperty "lawOracleDeterministic: recomputation + differently-anchored windows agree (context-free)" $
      forAll genCell lawOracleDeterministic

  , testProperty "lawNonperiodicWitness: every candidate period |v|<=2 has a defect in the 12x12 window (Thm 3)" $
      once lawNonperiodicWitness

  , testProperty "lawGoldenWindowPinned: the 8x8 golden window re-derives byte-for-byte (transcription gate)" $
      once lawGoldenWindowPinned

  , testProperty "oracle STATISTICS witness: over 20x20 all 11 tiles appear; t7 strictly beats t2 (Prop 9.1 ranking)" $
      once (let counts = [ length [ () | m <- [0 .. 19], n <- [0 .. 19]
                                       , tileIndexAt (m, n) == t ] | t <- [0 .. 10] ]
            in all (> 0) counts && counts !! 7 > counts !! 2)

    -- The state machine ---------------------------------------------------
  , testProperty "lawEdgeMatchIsCompositionLegal: edge match == FSM composability, all 121 pairs" $
      once (and [ lawEdgeMatchIsCompositionLegal i j | i <- [0 .. 10], j <- [0 .. 10] ])

  , testProperty "FOIL (non-vacuity): t0 (east Car2) refuses t2 (west Car3) — a real mismatch exists" $
      once (not (edgeMatchH (jrTiles !! 0) (jrTiles !! 2))
              && not (windowValid [[jrTiles !! 0, jrTiles !! 2]]))

  , testProperty "lawTilingRowIsLegalPipeline: any oracle row composes end-to-end through the FSM" $
      forAll genCell lawTilingRowIsLegalPipeline

  , testProperty "lawTilingColumnIsGradePath: any oracle column chains its grade letters (read==written)" $
      forAll genCell lawTilingColumnIsGradePath

  , testProperty "lawOpsAreElevenDistinct: 1 I + 3 K + 3+3+1 S, pairwise distinct AS FUNCTIONS on [1..8]" $
      once lawOpsAreElevenDistinct

  , testProperty "lawOpAssignmentPinned: opOf bijective; raising=>S, K=>lowering, I on t7 (most frequent)" $
      once lawOpAssignmentPinned

  , testProperty "lawKKillsItsBands: K_a zeroes exactly the a-containing bands = the AxisSKI wash kill set" $
      forAll (vectorOf 8 (choose (-512, 512))) lawKKillsItsBands

  , testProperty "lawSFloorIsZeroDetail: the 7 section floors flatten detail, keep coarse; sSection=zeroDetail" $
      forAll ((,) <$> vectorOf 8 (choose (-512, 512)) <*> choose (-1000, 1000)) $
        \(xs, c) -> lawSFloorIsZeroDetail xs c

    -- Gene = attention ----------------------------------------------------
  , testProperty "lawAttentionIsDistribution: 11 strictly-positive exact-rational weights summing to 1" $
      forAll genGene lawAttentionIsDistribution

  , testProperty "lawZeroGeneIsUniform: the zero gene is exactly uniform (1/11 each)" $
      once lawZeroGeneIsUniform

  , testProperty "lawAttentionModulatesNotMutates: the op schedule is gene-invariant (weights-only seam)" $
      forAll ((,) <$> genGene <*> choose (-1000, 1000)) $
        \(ws, s) -> lawAttentionModulatesNotMutates ws s

  , testProperty "FOIL (non-vacuity): a gene spending on band x skews the row off uniform, schedule unchanged" $
      once (let g = Gene (65536 : replicate 20 0)
            in attentionOf g /= attentionOf zeroGene
                 && map fst (scheduledOps g 3) == sliceOps 3)

  , testProperty "attention WITNESS: energy on band {x} favours S_x over S_y, and K_x pools LESS than K_y" $
      once (let g = Gene (65536 : replicate 20 0)
                row = attentionOf g
                ix op = head [ i | (i, o) <- zip [0 :: Int ..] opsCanonical, o == op ]
            in row !! ix (OpS [AxX]) > row !! ix (OpS [AxY])
                 && row !! ix (OpK AxX) < row !! ix (OpK AxY)
                 && row !! ix OpI < 1 % 11)

    -- Boot resolve --------------------------------------------------------
  , testProperty "lawBootResolveMonotone: coarse-first prefix order, never retracts" $
      forAll (choose (0, 64)) lawBootResolveMonotone

  , testProperty "lawBootResolveIsPourInverse: reveal ticks are pour boundaries; revealTick*units == 16" $
      once lawBootResolveIsPourInverse

  , testProperty "lawBootResolveTerminates: all rungs by tick 16 (= framesPerRealize^2); nothing at tick 0" $
      forAll (choose (0, 256)) lawBootResolveTerminates

  , testProperty "boot WITNESS: the reveal ladder is exactly 4 / 8 / 16 ticks (16-band, 32-band, 64-band)" $
      once (map revealTick [W16, W32, W64] == [4, 8, 16]
              && revealAt 3 == [] && revealAt 4 == [W16]
              && revealAt 8 == [W16, W32] && revealAt 16 == [W16, W32, W64])

    -- The tube schedule ---------------------------------------------------
  , testProperty "lawSliceIsRandomAccess: direct slice == rows of a taller window; shape = 4 x 16 (pour group)" $
      forAll (choose (-10000, 10000)) lawSliceIsRandomAccess

  , testProperty "lawSliceNeverRepeats: no vertical period up to the pour group in the first nine slices" $
      once lawSliceNeverRepeats

  , testProperty "slice WITNESS: consecutive slices share ops vocabulary but differ as sequences" $
      once (let a = sliceOps 0
                b = sliceOps 1
            in a /= b && not (null (nub a)))
  ]

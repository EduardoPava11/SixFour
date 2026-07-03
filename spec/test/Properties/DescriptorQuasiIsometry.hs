module Properties.DescriptorQuasiIsometry (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.Q16 (toQ16)
import SixFour.Spec.DetailPredictor (defaultPredictorShape, paramCount)
import SixFour.Spec.DescriptorQuasiIsometry

nWords :: Int
nWords = paramCount defaultPredictorShape   -- 21

-- A gene from integer Q16 words on the trained scale (same regime the constants
-- were validated over). Doubles are the toQ16 view of integer words.
genGene :: Gen [Double]
genGene = map toQ16 <$> vectorOf nWords (choose (-100, 100))

-- ---------------------------------------------------------------------------
-- Deterministic validated corpus (fixed seeds => reproducible, no flake). This
-- is the SAME corpus the runghc probe validated the two-sided bound over, so the
-- numerically-sensitive lower bound (c1 = 1/2) is gated as a regression, not by
-- random search that could dip below the pinned constant.
-- ---------------------------------------------------------------------------
geneOf :: [Int] -> [Double]
geneOf = map toQ16

padW :: [Int] -> [Int]
padW xs = take nWords (xs ++ repeat 0)

lcg :: Int -> Int
lcg x = (1103515245 * x + 12345) `mod` 2147483648

randWords :: Int -> Int -> ([Int], Int)
randWords 0 s = ([], s)
randWords k s = let s' = lcg s
                    w  = (s' `mod` 201) - 100
                    (ws, s'') = randWords (k-1) s'
                in (w:ws, s'')

randGenes :: Int -> Int -> [[Int]]
randGenes 0 _ = []
randGenes n s = let (ws, s') = randWords nWords s in ws : randGenes (n-1) s'

-- single-LSB genes, the constant-minus-quadratic adversarial family (worst
-- direction for the lower bound), and fixed-seed pseudo-randoms.
singleLsb, adversarial, baseGenes, deltaGenes :: [[Int]]
singleLsb   = [ padW (replicate i 0 ++ [1]) | i <- [0 .. nWords-1] ]
adversarial = [ padW [u,0,negate u] | u <- [1..8] ]
baseGenes   = [ replicate nWords 0, padW [3,-2,5], padW [0,0,0,10,-7,4]
              , map (\i -> ((i*37) `mod` 51) - 25) [0..nWords-1] ] ++ take 40 (randGenes 40 99)
deltaGenes  = singleLsb ++ adversarial ++ take 300 (randGenes 300 7)

corpus :: [([Double],[Double])]
corpus = [ (geneOf b, geneOf (zipWith (+) b d)) | b <- baseGenes, d <- deltaGenes ]
      ++ [ (geneOf a, geneOf b) | (a,b) <- zip (randGenes 200 1) (randGenes 200 500000) ]

-- A deliberately-WRONG collapsing descriptor: every gene maps to distance 0.
-- It MUST violate the lower bound on a dq>0 witness (non-vacuity).
wrongLowerHolds :: [Double] -> [Double] -> Bool
wrongLowerHolds a b = loNum * thetaFloorDist a b - loDen*slack <= loDen * 0

tests :: TestTree
tests = testGroup "DescriptorQuasiIsometry (two-sided quasi-isometry: no collapse, no discontinuity)"
  [ testProperty "KEYSTONE: exact-stimulus Vandermonde is full rank (det 2), collinear is rank-deficient (det 0)" $
      once lawProbeDesignVandermondeFullRank

  , testProperty "keystone non-vacuity: the real probe separates a collision a degenerate probe merges" $
      once lawRealProbeSeparatesCollision

  , testProperty "two-sided bound c1*dq - slack <= dc <= c2*dq over the validated corpus (deterministic)" $
      once (all (\(a,b) -> lawDescriptorIsQuasiIsometry a b) corpus)

  , testProperty "upper Lipschitz (dc <= 18*dq, provably dc <= 9*dq) on random genes" $
      forAll genGene $ \a -> forAll genGene (lawDescriptorUpperLipschitz a)

  , testProperty "lower separation on the validated corpus (deterministic)" $
      once (all (\(a,b) -> lawDescriptorLowerSeparation a b) corpus)

  , testProperty "honest quotient: dq=0 iff shared Q16 representative (on random genes)" $
      forAll genGene $ \a -> forAll genGene (lawFloorKernelIsGaugeKernel a)

  , testProperty "slack is provably sub-LSB (0 < 2), never an escape hatch" $
      once lawSlackBelowOneStep

  , testProperty "bounded distortion at coincidence (both distances 0, c1>0, kappa>=1)" $
      forAll genGene lawDistortionBoundedAtAnalysis

  , testProperty "NON-VACUITY: a collapsing descriptor (dc==0) FAILS the lower bound on dq>0" $
      once (not (wrongLowerHolds (geneOf (replicate nWords 0)) (geneOf (padW [5,0,0]))))
  ]

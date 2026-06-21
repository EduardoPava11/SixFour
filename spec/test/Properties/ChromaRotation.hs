module Properties.ChromaRotation (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.ChromaRotation

genInt :: Gen Int
genInt = choose (-65536, 65536)

genAB :: Gen (Int, Int)
genAB = (,) <$> genInt <*> genInt

tests :: TestTree
tests = testGroup "ChromaRotation (SO(2)/Cn chroma gauge; exact C4 + float detents)"
  [ testProperty "C4 is a group action: R_p . R_q = R_(p+q)" $
      \p q -> forAll genAB (lawRotateQuarterComposes p q)

  , testProperty "gray axis is the fixed point: R_theta (0,0) = (0,0)" $
      \q -> lawRotateFixesGray q

  , testProperty "a full turn is the identity (R_4k = id)" $
      \k -> forAll genAB (lawRightAngleFullTurn k)

  , testProperty "KEYSTONE: canonical form invariant under quarter-turn (rotation dedup)" $
      \r -> forAll (listOf genAB) (lawCanonicalChromaGaugeFixed r)

  , testProperty "gray axis is always degenerate for a positive floor" $
      forAll (choose (1, 65536)) lawGrayIsDegenerate

  , testProperty "detent steps are 30/45/60 and divide the circle" $
      once lawDetentSteps

  , testProperty "C4 lives inside the 30/45 detent grids, not 60" $
      once lawQuarterInDetent

  , testProperty "float guidance matches the exact subgroup at a right angle" $
      \a b -> lawFloatMatchesQuarterAtRightAngle a b
  ]

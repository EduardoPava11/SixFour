module Properties.CombinatorExactSequence (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.OctreeCell (V8(..), OctBand(..), Detail, liftOct, unliftOct, scalarCollapseLossy, ocDetail, ocCoarse)
import SixFour.Spec.CombinatorExactSequence

genV8 :: Gen (V8 Int)
genV8 = (\xs -> case xs of [a,b,c,d,e,f,g,h] -> V8 a b c d e f g h; _ -> V8 0 0 0 0 0 0 0 0)
          <$> vectorOf 8 (choose (-1000, 1000))

genDetail :: Gen Detail
genDetail = (,,,,,,) <$> g <*> g <*> g <*> g <*> g <*> g <*> g
  where g = choose (-500, 500)

-- A deliberately-WRONG "peeking" K that reads the detail: it must FAIL lawKForgetsDetail,
-- proving the real K genuinely forgets the detail (the surjection's kernel is the detail).
kPeek :: V8 Int -> Int
kPeek v = let (a,b,c,d,e,f,gg) = ocDetail (liftOct v) in scalarCollapseLossy v + a+b+c+d+e+f+gg

kForgetsWith :: (V8 Int -> Int) -> Int -> Detail -> Detail -> Bool
kForgetsWith k c d d' = k (unliftOct (OctBand c d)) == k (unliftOct (OctBand c d'))

tests :: TestTree
tests = testGroup "CombinatorExactSequence (S/K/I are the three maps of the octant short exact sequence)"
  [ testProperty "I is the SPLITTING: unliftOct(liftOct v)==v (exact iso, work 0)" $
      forAll genV8 lawISplitsExactly

  , testProperty "K is the SURJECTION forgetting detail: changing the 7 bands never changes K" $
      forAll (choose (-1000,1000)) $ \c -> forAll genDetail $ \d -> forAll genDetail (lawKForgetsDetail c d)

  , testProperty "NON-VACUITY: a peeking K (reads detail) FAILS lawKForgetsDetail; the real K passes" $
      forAll (choose (-1000,1000)) $ \c -> forAll genDetail $ \d -> forAll genDetail $ \d' ->
        kForgetsWith scalarCollapseLossy c d d'
        && (d == d' || not (kForgetsWith kPeek c d d'))

  , testProperty "S is a SECTION of K: K.S = id on the coarse" $
      forAll (choose (-100000,100000)) lawSIsSectionOfK

  , testProperty "S.K /= id: the residual witnesses non-split (nonzero detail iff v /= S(K v))" $
      forAll genV8 lawResidualWitnessesNonSplit

  , testProperty "zero-detail branch: a section point has zero detail and is its own S(K .)" $
      forAll (choose (-100000,100000)) $ \c ->
        ocDetail (liftOct (sSection c)) == zeroDetail && sSection (scalarCollapseLossy (sSection c)) == sSection c

  , testProperty "only I (full detail) reconstructs exactly; the zero-detail section does not" $
      forAll genV8 $ \v ->
        lawOnlyFullDetailReconstructs v
        && (ocDetail (liftOct v) == zeroDetail || v /= sSection (scalarCollapseLossy v))
  ]

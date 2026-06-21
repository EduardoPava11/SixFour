module Properties.ProjectionOrdering (tests) where

import Data.List (permutations, sort)
import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.Dim6 (Dim6(..), allDims, isUniversal)
import SixFour.Spec.ProjectionOrdering

-- | Every list reachable by 'mkOrdering' over all 6! permutations. With the
-- XOR-only convention (carrier fixed, pair-order fixed, within-pair fixed) this
-- is exactly the 2-element canonical vocabulary; the wider cosets are enumerated
-- separately below as raw permutations.
allValid :: [Ordering6]
allValid =
  [ o | p <- permutations allDims, Just o <- [mkOrdering p] ]

genOrdering :: Gen Ordering6
genOrdering = elements allValid

genXorBit :: Gen XorBit
genXorBit = elements [minBound .. maxBound]

genOp :: Gen OrderOp
genOp = elements [minBound .. maxBound]

genDimList :: Gen [Dim6]
genDimList = vectorOf 6 (elements allDims)

tests :: TestTree
tests = testGroup "ProjectionOrdering (carrier (L:t) fixed; XOR/Z2 search pairing; hash; group)"
  [ testProperty "mkOrdering round-trips a valid ordering" $
      forAll genOrdering lawMkRoundTrips

  , testProperty "mkOrdering rejects any non-(L,t) carrier head" $
      forAll genDimList lawMkRejectsBadCarrier

  , testProperty "carrier is the universal pair {L,t} at the head" $
      forAll genOrdering lawCarrierIsLT

  , testProperty "orthogonal projections: x and y carry different chroma (bijection)" $
      forAll genOrdering lawOrthogonalProjections

  , testProperty "XOR swap is its own inverse (reversibility = Z2 inverse)" $
      forAll genOrdering lawXorSelfInverse

  , testProperty "the pairing has exactly two cosets (searchBit . withXor = id)" $
      forAll genXorBit lawXorTwoCosets

  , testProperty "hash is injective on the canonical vocabulary" $
      once lawHashInjective

  , testProperty "OpId is a two-sided unit for composeOp" $
      forAll genOp lawIdentityUnit

  , testProperty "composeOp is associative" $
      forAll genOp $ \f -> forAll genOp $ \g -> forAll genOp (lawComposeAssoc f g)

  , testProperty "invertOp is a two-sided inverse" $
      forAll genOp lawComposeInverse

  , testProperty "group action is closed on valid orderings and respects composition" $
      forAll genOp $ \f -> forAll genOp $ \g -> forAll genOrdering (lawApplyClosed f g)

  , testProperty "canonical XOR-only vocabulary has exactly 2 projection-modes" $
      once lawVocabularyCount

    -- The VOCABULARY enumeration, pinned as goldens (the cabal-repl counts).
  , testProperty "ENUM: mkOrdering accepts exactly the 2 XOR projection-modes" $
      once (length allValid == 2)

  , testProperty "ENUM: XOR-only (t=L fixed + bijection) count = 2 (the Z2 search bit)" $
      once (length xorOnly == 2)

  , testProperty "ENUM: pair-order-free, within-pair-fixed count = 4 (2 XOR x 2 pair-order)" $
      once (length pairOrderFree == 4)

  , testProperty "ENUM: full coset (pair-order + within-pair flips free) count = 16" $
      once (length fullCoset == 16)
  ]
  where
    isPos d = d == DimX || d == DimY
    isChr d = d == DimA || d == DimB
    isCarrierHead p = take 2 p == [DimL, DimT]
    -- XOR-only: carrier fixed, tail pinned to [x, c1, y, c2] with {c1,c2}={a,b}
    xorOnly =
      [ p | p <- permutations allDims
          , isCarrierHead p
          , case drop 2 p of
              [DimX, c1, DimY, c2] -> isChr c1 && isChr c2 && c1 /= c2
              _                    -> False ]
    -- pair-order free, within-pair fixed (position then chroma)
    pairOrderFree =
      [ p | p <- permutations allDims
          , isCarrierHead p
          , case drop 2 p of
              [p1, c1, p2, c2] -> isPos p1 && isPos p2 && p1 /= p2
                                  && isChr c1 && isChr c2 && c1 /= c2
              _                -> False ]
    -- full coset: each adjacent pair is a (pos,chroma) bijection, in EITHER
    -- within-pair order (pos-then-chroma OR chroma-then-pos)
    fullCoset =
      [ p | p <- permutations allDims
          , isCarrierHead p
          , case drop 2 p of
              [a, b, c, d] ->
                validPair a b && validPair c d
                && length (filter isPos [a,b,c,d]) == 2
                && length (filter isChr [a,b,c,d]) == 2
              _ -> False ]
    validPair u v = (isPos u && isChr v) || (isChr u && isPos v)

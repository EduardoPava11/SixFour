{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}

module Properties.Tensor (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Test.QuickCheck

import qualified Data.Vector.Unboxed as U

import SixFour.Spec.Tensor
  ( Tensor1, Tensor2
  , fromList1, fromList2
  , size1, size2
  , gmmTokenSigmaMask
  , lawTabulateIndex1, lawIndexTabulate1
  , lawTabulateIndex2, lawIndexTabulate2
  , lawChannelViewRecombines, lawSumChannelsIsRowSum
  , lawGmmTokenSigmaInvolution, lawGmmTokenSigmaOrthogonal
  , lawPermutationInvariantReduce
  , lawSigma64Involution, lawSigma64Orthogonal, lawSigma64BiologicalRatio
  )

-- We fix small concrete Nat values for the generic laws — QuickCheck cannot
-- quantify over Nat itself, but a representative shape (here 4×10, matching the
-- L3 GMM-token shape down-scaled) is plenty to exercise the laws.
type SmallN = 5
type SmallM = 3
type Tokens = 4   -- "number of GMM tokens" stand-in for permutation invariance tests

genUnit :: Gen Double
genUnit = choose (-1, 1)

-- Vector of length n of unit-bounded doubles, as a Tensor1.
genTensor1Small :: Gen (Tensor1 SmallN Double)
genTensor1Small = do
  xs <- vectorOf 5 genUnit
  case fromList1 @SmallN xs of
    Just t  -> pure t
    Nothing -> error "genTensor1Small: shape mismatch (impossible)"

genTensor2Small :: Gen (Tensor2 SmallN SmallM Double)
genTensor2Small = do
  rows <- vectorOf 5 (vectorOf 3 genUnit)
  case fromList2 @SmallN @SmallM rows of
    Just t  -> pure t
    Nothing -> error "genTensor2Small: shape mismatch (impossible)"

-- A GMM-token tensor: T rows × 10 channels of unit-bounded doubles. Used to
-- exercise the σ-action laws on the canonical L3 input shape.
genGmmTokenTensor :: Gen (Tensor2 Tokens 10 Double)
genGmmTokenTensor = do
  rows <- vectorOf 4 (vectorOf 10 genUnit)
  case fromList2 @Tokens @10 rows of
    Just t  -> pure t
    Nothing -> error "genGmmTokenTensor: shape mismatch (impossible)"

-- A hidden-state tensor: T rows × 64 channels of unit-bounded doubles.
genHiddenTensor :: Gen (Tensor2 Tokens 64 Double)
genHiddenTensor = do
  rows <- vectorOf 4 (vectorOf 64 genUnit)
  case fromList2 @Tokens @64 rows of
    Just t  -> pure t
    Nothing -> error "genHiddenTensor: shape mismatch (impossible)"

-- A permutation of [0..Tokens-1]. Uses QuickCheck's @shuffle@.
genPermTokens :: Gen [Int]
genPermTokens = shuffle [0 .. 3]   -- Tokens = 4

-- Coefficient triples for f(i) = a*i² + b*i + c. We generate showable tuples
-- so QuickCheck can print counterexamples; the law builds the function inline.
type Coefs1 = (Double, Double, Double)
genCoefs1 :: Gen Coefs1
genCoefs1 = (,,) <$> choose (-1, 1) <*> choose (-1, 1) <*> choose (-1, 1)

mkFun1 :: Coefs1 -> (Int -> Double)
mkFun1 (a, b, c) i =
  let x = fromIntegral i :: Double
  in a * x * x + b * x + c

-- For rank-2: f(i,j) = a*i + b*j.
type Coefs2 = (Double, Double)
genCoefs2 :: Gen Coefs2
genCoefs2 = (,) <$> choose (-1, 1) <*> choose (-1, 1)

mkFun2 :: Coefs2 -> (Int -> Int -> Double)
mkFun2 (a, b) i j = a * fromIntegral i + b * fromIntegral j

tests :: TestTree
tests = testGroup "Tensor (Naperian typed tensors + SoA channel axis + GMM-token σ)"

  [ testProperty "Naperian round-trip 1: index1 (tabulate1 f) i ≡ f i" $
      forAll genCoefs1 (lawTabulateIndex1 @SmallN . mkFun1)

  , testProperty "Naperian round-trip 2: tabulate1 (index1 t) ≡ t" $
      forAll genTensor1Small (lawIndexTabulate1 @SmallN)

  , testProperty "Naperian round-trip 1 (rank-2): index2 (tabulate2 f) i j ≡ f i j" $
      forAll genCoefs2 (lawTabulateIndex2 @SmallN @SmallM . mkFun2)

  , testProperty "Naperian round-trip 2 (rank-2): tabulate2 (index2 t) ≡ t" $
      forAll genTensor2Small (lawIndexTabulate2 @SmallN @SmallM)

  , testProperty "SoA contract: channelView ∘ recombine ≡ id (parallel arrays ↔ row-major)" $
      forAll genTensor2Small (lawChannelViewRecombines @SmallN @SmallM)

  , testProperty "sumChannels equals explicit row-sum Σ_j t[i,j]" $
      forAll genTensor2Small (lawSumChannelsIsRowSum @SmallN @SmallM)

  , testProperty "GMM-token σ is an involution: σ ∘ σ ≡ id (exact, sign flips)" $
      forAll genGmmTokenTensor (lawGmmTokenSigmaInvolution @Tokens)

  , testProperty "GMM-token σ is orthogonal: preserves Euclidean norm exactly" $
      forAll genGmmTokenTensor (lawGmmTokenSigmaOrthogonal @Tokens)

  , testProperty "sum-pool is permutation-invariant up to FP reassociation (tol 1e-12)" $
      forAll genPermTokens $ \perm ->
        forAll genGmmTokenTensor (lawPermutationInvariantReduce @Tokens @10 1e-12 perm)

  , testProperty "GMM-token σ mask matches the derivation [μa,μb,ΣLa,ΣLb negate; rest fix]" $
      once $
        gmmTokenSigmaMask
          == [False, True, True, False, True, True, False, False, False, False]

  , testProperty "hidden-state σ is an involution (Hurvich-Jameson decomposition)" $
      forAll genHiddenTensor (lawSigma64Involution @Tokens)

  , testProperty "hidden-state σ is orthogonal (norm-preserving)" $
      forAll genHiddenTensor (lawSigma64Orthogonal @Tokens)

  , testProperty "hidden-state biological ratio: 22 achromatic + 21 R-G + 21 B-Y = 64 (1:2 opponent)" $
      once lawSigma64BiologicalRatio

  , testProperty "size accessors return type-level Nats" $
      once $
        let t1 = case fromList1 @SmallN ([0,0,0,0,0] :: [Double]) of
                   Just x  -> x
                   Nothing -> error "impossible"
            t2 = case fromList2 @SmallN @SmallM (replicate 5 ([0,0,0] :: [Double])) of
                   Just x  -> x
                   Nothing -> error "impossible"
        in size1 t1 == 5 && size2 t2 == (5, 3)
  ]

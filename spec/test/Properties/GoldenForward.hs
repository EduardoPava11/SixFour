{-# LANGUAGE ScopedTypeVariables #-}

module Properties.GoldenForward (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Test.QuickCheck

import qualified Data.Vector.Unboxed as U
import           Data.Word           (Word64)
import           GHC.Float           (castDoubleToWord64, castWord64ToDouble)
import           Numeric             (readHex)

import SixFour.Spec.Tensor    (Tensor1(..), gmmTokenSigmaMask)
import SixFour.Spec.LookNetD   (sigma768Mask)
import SixFour.Spec.LookNetEval
import SixFour.Codegen.Golden  (hexDouble)
import qualified Data.Text     as T

-- The concrete forward (LookNetEval) is the golden oracle. These laws pin its
-- self-consistency so the emitted golden vectors are trustworthy.

genToken :: Gen (Tensor1 10 Double)
genToken = do
  xs <- vectorOf 10 (choose (-1, 1) :: Gen Double)
  pure (Tensor1 (U.fromList xs))

genTokens :: Gen [Tensor1 10 Double]
genTokens = do
  n <- choose (1, 8)
  vectorOf n genToken

-- σ on an input token: negate channels where gmmTokenSigmaMask is True.
sigmaTok :: Tensor1 10 Double -> Tensor1 10 Double
sigmaTok (Tensor1 v) =
  Tensor1 (U.imap (\i x -> if gmmTokenSigmaMask !! i then negate x else x) v)

-- σ₇₆₈ on the flat output: negate channels where sigma768Mask is True.
sigma768List :: [Double] -> [Double]
sigma768List = zipWith (\b x -> if b then negate x else x) sigma768Mask

finite :: Double -> Bool
finite x = not (isNaN x) && not (isInfinite x)

w :: LookNetWeights
w = deterministicTestWeights

tests :: TestTree
tests = testGroup "GoldenForward (the concrete numeric forward — the golden-vector oracle)"

  [ testProperty "forward output is exactly 768-D" $
      forAll genTokens $ \toks -> length (ftOutput (forward w toks)) == 768

  , testProperty "forward output + context + halts are all finite (no NaN/Inf — JSON-safe)" $
      forAll genTokens $ \toks ->
        let tr = forward w toks
        in all finite (ftOutput tr) && all finite (ftContext tr) && all finite (ftHalts tr)

  , testProperty "deterministic test weights are all finite + bounded in [-0.1, 0.1]" $
      once $
        let allW = U.toList (wPhi w) ++ U.toList (wW1 w) ++ U.toList (wW2 w)
                ++ U.toList (wHaltW w) ++ [wHaltB w] ++ concatMap U.toList (wHeads w)
        in all finite allW && all (\x -> abs x <= 0.10000001) (U.toList (wPhi w) ++ U.toList (wW1 w))

  , testProperty "forward is σ-equivariant: output(σ_in tokens) ≈ σ₇₆₈(output tokens), tol 1e-9" $
      forAll genTokens $ \toks ->
        let a = ftOutput (forward w (map sigmaTok toks))
            b = sigma768List (ftOutput (forward w toks))
        in length a == length b
           && and (zipWith (\p q -> abs (p - q) <= 1e-9) a b)

  , testProperty "halts are σ-invariant ∈ [0,1] (σ-invariant features + sigmoid)" $
      forAll genTokens $ \toks ->
        let ha = ftHalts (forward w (map sigmaTok toks))
            hb = ftHalts (forward w toks)
        in length ha == 8
           && all (\x -> x >= 0 && x <= 1) hb
           && and (zipWith (\p q -> abs (p - q) <= 1e-9) ha hb)

  , testProperty "hexDouble round-trips bit-exactly (the transport format is lossless)" $
      forAll (choose (-1e6, 1e6) :: Gen Double) $ \x ->
        parseHexDouble (hexDouble x) == Just x
  ]

-- Parse the 16-hex-digit IEEE-754 bit pattern back to the Double (the inverse a
-- port performs: int(s,16)+struct / Double(bitPattern:)).
parseHexDouble :: T.Text -> Maybe Double
parseHexDouble t =
  case readHex (T.unpack t) of
    [(wd, "")] -> Just (castWord64ToDouble (wd :: Word64))
    _          -> Nothing

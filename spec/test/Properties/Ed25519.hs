{-# LANGUAGE ScopedTypeVariables #-}
module Properties.Ed25519 (tests) where

import Data.Bits (xor)
import Data.Word (Word8)
import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.Ed25519

-- A 32-byte Ed25519 seed.
seed32 :: Gen [Word8]
seed32 = vectorOf 32 arbitrary

tests :: TestTree
tests = testGroup "Ed25519 (RFC 8032, hand-written & byte-exact)"
  [ testProperty "known-answer: public keys" lawEd25519PublicKeyGolden
  , testProperty "known-answer: signatures"  lawEd25519SignGolden
  , testProperty "known-answer: verification" lawEd25519VerifyGolden
  , testProperty "round-trip: a genuine signature verifies" $
      withMaxSuccess 25 $ forAll seed32 $ \sk -> \(msg :: [Word8]) ->
        verify (publicKey sk) msg (sign sk msg)
  , testProperty "tamper: altering the signature is rejected" $
      withMaxSuccess 25 $ forAll seed32 $ \sk -> \(msg :: [Word8]) ->
        forAll (choose (32, 63)) $ \(i :: Int) ->   -- flip a byte of the S scalar half
          let sig  = sign sk msg
              sig' = [ if j == i then b `xor` 1 else b | (j, b) <- zip [0 :: Int ..] sig ]
          in not (verify (publicKey sk) msg sig')
  , testProperty "a different key does not verify" $
      withMaxSuccess 25 $ forAll seed32 $ \sk1 -> forAll seed32 $ \sk2 -> \(msg :: [Word8]) ->
        publicKey sk1 == publicKey sk2 || not (verify (publicKey sk2) msg (sign sk1 msg))
  ]

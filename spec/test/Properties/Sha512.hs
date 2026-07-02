{-# LANGUAGE ScopedTypeVariables #-}
module Properties.Sha512 (tests) where

import Data.Word (Word8)
import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.Sha512

tests :: TestTree
tests = testGroup "Sha512 (FIPS 180-4, hand-written & byte-exact)"
  [ testProperty "known-answer: SHA-512(\"\")" lawSha512EmptyGolden
  , testProperty "known-answer: SHA-512(\"abc\")" lawSha512AbcGolden
  , testProperty "the digest is always 64 bytes" $
      \(bytes :: [Word8]) -> length (sha512 bytes) == 64
  , testProperty "deterministic" $
      \(bytes :: [Word8]) -> sha512 bytes == sha512 bytes
  ]

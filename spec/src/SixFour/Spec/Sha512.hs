{- |
Module      : SixFour.Spec.Sha512
Description : SHA-512 (FIPS 180-4), hand-written and byte-exact — the hash Ed25519 (RFC 8032) is built on. Boot-only (@Data.Word@ / @Data.Bits@), verified against the NIST known-answer vectors for the empty string and @"abc"@ ('lawSha512EmptyGolden' \/ 'lawSha512AbcGolden').

This is a dependency-free reference the Swift\/Zig port is checked against, exactly like every other
SixFour primitive. It exists so "SixFour.Spec.Ed25519" can compute its nonce, public key and challenge
hashes without a crypto dependency; the RFC 8032 signature test vectors transitively gate this module
too (a wrong SHA-512 could not reproduce them).
-}
-- COMPARTMENT: SWIFT-APP-SOCIAL | tag:DisplaySide
module SixFour.Spec.Sha512
  ( sha512
  , lawSha512EmptyGolden
  , lawSha512AbcGolden
  ) where

import           Data.Bits (complement, rotateR, shiftL, shiftR, xor, (.&.), (.|.))
import           Data.Char (digitToInt)
import           Data.List (foldl')
import           Data.Word (Word8, Word64)

-- | The eight SHA-512 initial hash values (fractional parts of the square roots of the first 8 primes).
initialHash :: [Word64]
initialHash =
  [ 0x6a09e667f3bcc908, 0xbb67ae8584caa73b, 0x3c6ef372fe94f82b, 0xa54ff53a5f1d36f1
  , 0x510e527fade682d1, 0x9b05688c2b3e6c1f, 0x1f83d9abfb41bd6b, 0x5be0cd19137e2179 ]

-- | The eighty SHA-512 round constants (fractional parts of the cube roots of the first 80 primes).
roundConstants :: [Word64]
roundConstants =
  [ 0x428a2f98d728ae22, 0x7137449123ef65cd, 0xb5c0fbcfec4d3b2f, 0xe9b5dba58189dbbc
  , 0x3956c25bf348b538, 0x59f111f1b605d019, 0x923f82a4af194f9b, 0xab1c5ed5da6d8118
  , 0xd807aa98a3030242, 0x12835b0145706fbe, 0x243185be4ee4b28c, 0x550c7dc3d5ffb4e2
  , 0x72be5d74f27b896f, 0x80deb1fe3b1696b1, 0x9bdc06a725c71235, 0xc19bf174cf692694
  , 0xe49b69c19ef14ad2, 0xefbe4786384f25e3, 0x0fc19dc68b8cd5b5, 0x240ca1cc77ac9c65
  , 0x2de92c6f592b0275, 0x4a7484aa6ea6e483, 0x5cb0a9dcbd41fbd4, 0x76f988da831153b5
  , 0x983e5152ee66dfab, 0xa831c66d2db43210, 0xb00327c898fb213f, 0xbf597fc7beef0ee4
  , 0xc6e00bf33da88fc2, 0xd5a79147930aa725, 0x06ca6351e003826f, 0x142929670a0e6e70
  , 0x27b70a8546d22ffc, 0x2e1b21385c26c926, 0x4d2c6dfc5ac42aed, 0x53380d139d95b3df
  , 0x650a73548baf63de, 0x766a0abb3c77b2a8, 0x81c2c92e47edaee6, 0x92722c851482353b
  , 0xa2bfe8a14cf10364, 0xa81a664bbc423001, 0xc24b8b70d0f89791, 0xc76c51a30654be30
  , 0xd192e819d6ef5218, 0xd69906245565a910, 0xf40e35855771202a, 0x106aa07032bbd1b8
  , 0x19a4c116b8d2d0c8, 0x1e376c085141ab53, 0x2748774cdf8eeb99, 0x34b0bcb5e19b48a8
  , 0x391c0cb3c5c95a63, 0x4ed8aa4ae3418acb, 0x5b9cca4f7763e373, 0x682e6ff3d6b2b8a3
  , 0x748f82ee5defb2fc, 0x78a5636f43172f60, 0x84c87814a1f0ab72, 0x8cc702081a6439ec
  , 0x90befffa23631e28, 0xa4506cebde82bde9, 0xbef9a3f7b2c67915, 0xc67178f2e372532b
  , 0xca273eceea26619c, 0xd186b8c721c0c207, 0xeada7dd6cde0eb1e, 0xf57d4f7fee6ed178
  , 0x06f067aa72176fba, 0x0a637dc5a2c898a6, 0x113f9804bef90dae, 0x1b710b35131c471b
  , 0x28db77f523047d84, 0x32caab7b40c72493, 0x3c9ebe0a15c9bebc, 0x431d67c49c100d4c
  , 0x4cc5d4becb3e42b6, 0x597f299cfc657e2a, 0x5fcb6fab3ad6faec, 0x6c44198c4a475817 ]

-- round functions (FIPS 180-4 §4.1.3)
bigSigma0, bigSigma1, smallSigma0, smallSigma1 :: Word64 -> Word64
bigSigma0 x   = rotateR x 28 `xor` rotateR x 34 `xor` rotateR x 39
bigSigma1 x   = rotateR x 14 `xor` rotateR x 18 `xor` rotateR x 41
smallSigma0 x = rotateR x 1  `xor` rotateR x 8  `xor` (x `shiftR` 7)
smallSigma1 x = rotateR x 19 `xor` rotateR x 61 `xor` (x `shiftR` 6)

ch, maj :: Word64 -> Word64 -> Word64 -> Word64
ch  x y z = (x .&. y) `xor` (complement x .&. z)
maj x y z = (x .&. y) `xor` (x .&. z) `xor` (y .&. z)

-- | SHA-512: hash a byte string to its 64-byte digest.
sha512 :: [Word8] -> [Word8]
sha512 msg =
  concatMap word64BE (foldl' compressBlock initialHash (chunk 128 (pad msg)))

-- | Pad per FIPS 180-4 §5.1.2: append @0x80@, zero-pad to 112 mod 128, then the 128-bit big-endian
-- bit length.
pad :: [Word8] -> [Word8]
pad msg =
  let withOne     = msg ++ [0x80]
      zerosNeeded = (112 - (length withOne `mod` 128)) `mod` 128
      bitLen      = fromIntegral (length msg) * 8 :: Integer
      lenBytes    = [ fromIntegral (bitLen `shiftR` (8 * i)) | i <- [15, 14 .. 0] ]
  in withOne ++ replicate zerosNeeded 0 ++ lenBytes

-- | Compress one 128-byte block into the running hash state.
compressBlock :: [Word64] -> [Word8] -> [Word64]
compressBlock hIn block = zipWith (+) hIn [a, b, c, d, e, f, g, h]
  where
    w0            = map be64 (chunk 8 block)                       -- 16 words
    w             = schedule w0                                    -- 80 words
    (a,b,c,d,e,f,g,h) = foldl' step (tuple8 hIn) (zip roundConstants w)
    step (sa,sb,sc,sd,se,sf,sg,sh) (kt, wt) =
      let t1 = sh + bigSigma1 se + ch se sf sg + kt + wt
          t2 = bigSigma0 sa + maj sa sb sc
      in (t1 + t2, sa, sb, sc, sd + t1, se, sf, sg)

-- | Extend the 16 block words to the 80-word message schedule.
schedule :: [Word64] -> [Word64]
schedule ws0 = go ws0 (16 :: Int)
  where
    go ws t
      | t == 80   = ws
      | otherwise =
          let wt = smallSigma1 (ws !! (t-2)) + ws !! (t-7) + smallSigma0 (ws !! (t-15)) + ws !! (t-16)
          in go (ws ++ [wt]) (t + 1)

tuple8 :: [Word64] -> (Word64,Word64,Word64,Word64,Word64,Word64,Word64,Word64)
tuple8 [a,b,c,d,e,f,g,h] = (a,b,c,d,e,f,g,h)
tuple8 _ = error "SixFour.Spec.Sha512.tuple8: expected 8 words"

-- 8 big-endian bytes → Word64.
be64 :: [Word8] -> Word64
be64 = foldl' (\acc byte -> (acc `shiftL` 8) .|. fromIntegral byte) 0

-- Word64 → 8 big-endian bytes.
word64BE :: Word64 -> [Word8]
word64BE x = [ fromIntegral (x `shiftR` (8 * i)) | i <- [7, 6 .. 0] ]

chunk :: Int -> [a] -> [[a]]
chunk _ [] = []
chunk n xs = let (h, t) = splitAt n xs in h : chunk n t

-- ─────────────────────────────────────────────────────────────────────────────
-- Golden laws (QuickCheck'd in @Properties.Sha512@).
-- ─────────────────────────────────────────────────────────────────────────────

-- | Known-answer vector: SHA-512 of the empty string.
lawSha512EmptyGolden :: Bool
lawSha512EmptyGolden =
  sha512 [] == fromHex
    "cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce\
    \47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e"

-- | Known-answer vector: SHA-512 of @"abc"@.
lawSha512AbcGolden :: Bool
lawSha512AbcGolden =
  sha512 [0x61, 0x62, 0x63] == fromHex
    "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a\
    \2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f"

fromHex :: String -> [Word8]
fromHex [] = []
fromHex (x:y:rest) = fromIntegral (digitToInt x * 16 + digitToInt y) : fromHex rest
fromHex _ = error "SixFour.Spec.Sha512.fromHex: odd-length hex"

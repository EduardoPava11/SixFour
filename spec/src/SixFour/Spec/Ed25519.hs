{- |
Module      : SixFour.Spec.Ed25519
Description : Ed25519 (RFC 8032), hand-written and byte-exact — real public-key signatures for the creator sigchain, with NO crypto dependency. Twisted-Edwards curve arithmetic over @GF(2^255-19)@ in extended coordinates, on top of "SixFour.Spec.Sha512". Gated against ground-truth known-answer vectors (RFC 8032 tests + OpenSSL-generated), so 'publicKey', 'sign' and 'verify' reproduce a trusted implementation bit-for-bit.

This replaces the shared-modulus RSA STAND-IN that "SixFour.Spec.SigChain" used to bootstrap its laws:
authorship attestations are now signed with genuine Ed25519, deterministic per RFC 8032 (no per-signature
randomness), so the same @(seed, message)@ always yields the same 64-byte signature.

  * 'publicKey' — the 32-byte public key for a 32-byte seed.
  * 'sign' — the deterministic 64-byte signature of a message under a seed.
  * 'verify' — check a signature against a public key and message ([S]B = R + [k]A).
  * golden laws pin all three to the trusted vectors ('lawEd25519PublicKeyGolden' etc.); round-trip and
    tamper-rejection laws are QuickCheck'd in @Properties.Ed25519@.

GHC-boot-only (@base@: @Data.Word@, @Data.Bits@, and @Integer@ big-arithmetic). All field ops reduce
mod @p = 2^255-19@; scalars reduce mod the group order @L@. The reference is intentionally simple
(not constant-time) — the Swift\/Zig device port hardens timing while matching these bytes.
-}
-- COMPARTMENT: SWIFT-APP-SOCIAL | tag:DisplaySide
module SixFour.Spec.Ed25519
  ( publicKey
  , sign
  , verify
    -- * Golden laws (QuickCheck'd in @Properties.Ed25519@)
  , lawEd25519PublicKeyGolden
  , lawEd25519SignGolden
  , lawEd25519VerifyGolden
  ) where

import           Data.Bits (shiftL, shiftR, (.&.), (.|.))
import           Data.Char (digitToInt)
import           Data.Word (Word8)

import           SixFour.Spec.Sha512 (sha512)

-- ─────────────────────────────────────────────────────────────────────────────
-- Field & curve constants.
-- ─────────────────────────────────────────────────────────────────────────────

-- | The field prime, @2^255 - 19@.
p :: Integer
p = 2 ^ (255 :: Int) - 19

-- | The group order @L = 2^252 + 27742317777372353535851937790883648493@.
l :: Integer
l = 2 ^ (252 :: Int) + 27742317777372353535851937790883648493

-- | The curve constant @d = -121665/121666@.
d :: Integer
d = modp (negate 121665 * inv 121666)

-- | @2d@ (precomputed for the addition formula).
d2 :: Integer
d2 = modp (2 * d)

-- | @sqrt(-1) mod p@, used in x-coordinate recovery.
sqrtm1 :: Integer
sqrtm1 = powMod 2 ((p - 1) `div` 4) p

-- | The base point in extended coordinates @(X, Y, Z, T)@, with @By = 4/5@ and @Bx@ even.
base :: Point
base = case recoverX by 0 of
  Just bx -> (bx, by, 1, modp (bx * by))
  Nothing -> error "SixFour.Spec.Ed25519.base: unrecoverable base x"
  where by = modp (4 * inv 5)

-- ─────────────────────────────────────────────────────────────────────────────
-- Field arithmetic (mod p).
-- ─────────────────────────────────────────────────────────────────────────────

modp :: Integer -> Integer
modp x = x `mod` p

-- | Modular inverse mod p via Fermat (@a^(p-2)@).
inv :: Integer -> Integer
inv a = powMod a (p - 2) p

powMod :: Integer -> Integer -> Integer -> Integer
powMod _ 0 m = 1 `mod` m
powMod b e m =
  let half = powMod b (e `div` 2) m
      sq   = (half * half) `mod` m
  in if even e then sq else (sq * (b `mod` m)) `mod` m

-- ─────────────────────────────────────────────────────────────────────────────
-- Twisted-Edwards points in extended coordinates (a = -1).
-- ─────────────────────────────────────────────────────────────────────────────

-- | A curve point @(X, Y, Z, T)@ with @x = X/Z@, @y = Y/Z@, @xy = T/Z@.
type Point = (Integer, Integer, Integer, Integer)

identityP :: Point
identityP = (0, 1, 1, 0)

-- | Complete unified addition (Hisil–Wong–Carter–Dawson 2008, a = -1); also used for doubling.
pAdd :: Point -> Point -> Point
pAdd (x1,y1,z1,t1) (x2,y2,z2,t2) =
  let a  = modp ((y1 - x1) * (y2 - x2))
      b  = modp ((y1 + x1) * (y2 + x2))
      c  = modp (t1 * d2 * t2)
      dd = modp (z1 * 2 * z2)
      e  = modp (b - a)
      f  = modp (dd - c)
      g  = modp (dd + c)
      h  = modp (b + a)
  in (modp (e * f), modp (g * h), modp (f * g), modp (e * h))

-- | Scalar multiplication by double-and-add (LSB-first).
scalarMul :: Integer -> Point -> Point
scalarMul n pt
  | n <= 0    = identityP
  | otherwise = let q = scalarMul (n `div` 2) (pAdd pt pt)
                in if odd n then pAdd q pt else q

-- | Point equality via the normalized (affine) encoding.
pointEq :: Point -> Point -> Bool
pointEq a b = encodePoint a == encodePoint b

-- ─────────────────────────────────────────────────────────────────────────────
-- Encoding / decoding (32-byte little-endian, sign bit in bit 255).
-- ─────────────────────────────────────────────────────────────────────────────

-- | Encode a point to 32 bytes: @y@ little-endian, with the low bit of @x@ in bit 255.
encodePoint :: Point -> [Word8]
encodePoint (x, y, z, _) =
  let zi = inv z
      xa = modp (x * zi)
      ya = modp (y * zi)
      ybytes = leBytes32 ya
      top = fromIntegral ((xa .&. 1) `shiftL` 7) :: Word8
  in init ybytes ++ [last ybytes .|. top]

-- | Decode 32 bytes to a point, or 'Nothing' if it is not a valid encoding.
decodePoint :: [Word8] -> Maybe Point
decodePoint bs
  | length bs /= 32 = Nothing
  | otherwise =
      let n    = leInt bs
          xLSB = fromIntegral ((n `shiftR` 255) .&. 1) :: Int
          y    = n .&. ((1 `shiftL` 255) - 1)
      in if y >= p then Nothing
         else case recoverX y xLSB of
                Just x  -> Just (x, y, 1, modp (x * y))
                Nothing -> Nothing

-- | Recover the x-coordinate for a given y and desired low bit (p ≡ 5 mod 8).
recoverX :: Integer -> Int -> Maybe Integer
recoverX y xLSB =
  let u  = modp (y * y - 1)
      v  = modp (d * y * y + 1)
      xx = modp (u * inv v)
      c0 = powMod xx ((p + 3) `div` 8) p
      c1 = if modp (c0 * c0 - xx) == 0 then c0 else modp (c0 * sqrtm1)
  in if modp (c1 * c1 - xx) /= 0
       then Nothing
       else let x = if fromIntegral (c1 .&. 1) /= xLSB then modp (negate c1) else c1
            in if x == 0 && xLSB == 1 then Nothing else Just x

-- ─────────────────────────────────────────────────────────────────────────────
-- Integer / byte conversions.
-- ─────────────────────────────────────────────────────────────────────────────

-- | Little-endian bytes → integer.
leInt :: [Word8] -> Integer
leInt = foldr (\byte acc -> fromIntegral byte + 256 * acc) 0

-- | Integer → 32 little-endian bytes.
leBytes32 :: Integer -> [Word8]
leBytes32 x = [ fromIntegral ((x `shiftR` (8 * i)) .&. 0xff) | i <- [0 .. 31] ]

-- ─────────────────────────────────────────────────────────────────────────────
-- RFC 8032 key expansion / sign / verify.
-- ─────────────────────────────────────────────────────────────────────────────

-- | Expand a 32-byte seed into (private scalar @a@, PRF prefix, public-key bytes).
expand :: [Word8] -> (Integer, [Word8], [Word8])
expand seed =
  let h      = sha512 seed
      a      = clampScalar (take 32 h)
      prefix = drop 32 h
      aPub   = encodePoint (scalarMul a base)
  in (a, prefix, aPub)

-- | Clamp the low 32 hash bytes and read them as the private scalar (RFC 8032 §5.1.5).
clampScalar :: [Word8] -> Integer
clampScalar h =
  let b0  = (head h .&. 248)
      b31 = ((h !! 31) .&. 127) .|. 64
      clamped = b0 : take 30 (drop 1 h) ++ [b31]
  in leInt clamped

-- | The 32-byte Ed25519 public key for a 32-byte seed.
publicKey :: [Word8] -> [Word8]
publicKey seed = let (_, _, aPub) = expand seed in aPub

-- | The deterministic 64-byte Ed25519 signature of a message under a 32-byte seed.
sign :: [Word8] -> [Word8] -> [Word8]
sign seed msg =
  let (a, prefix, aPub) = expand seed
      r    = leInt (sha512 (prefix ++ msg)) `mod` l
      rEnc = encodePoint (scalarMul r base)
      k    = leInt (sha512 (rEnc ++ aPub ++ msg)) `mod` l
      s    = (r + k * a) `mod` l
  in rEnc ++ leBytes32 s

-- | Verify a 64-byte signature against a 32-byte public key and message.
verify :: [Word8] -> [Word8] -> [Word8] -> Bool
verify pub msg sig
  | length sig /= 64 || length pub /= 32 = False
  | s >= l                               = False
  | otherwise = case (decodePoint pub, decodePoint rEnc) of
      (Just aPt, Just rPt) ->
        let k = leInt (sha512 (rEnc ++ pub ++ msg)) `mod` l
        in pointEq (scalarMul s base) (pAdd rPt (scalarMul k aPt))
      _ -> False
  where
    rEnc = take 32 sig
    s    = leInt (drop 32 sig)

-- ─────────────────────────────────────────────────────────────────────────────
-- Golden laws — trusted known-answer vectors (RFC 8032 + OpenSSL 3.6.1).
-- ─────────────────────────────────────────────────────────────────────────────

-- (seed, publicKey, message, signature), all hex. Tests 2/3 are RFC 8032; the last is
-- OpenSSL-generated for seed 0x42… over the message "SixFour". Test 1 (empty message) has an
-- OpenSSL-verified public key.
vectors :: [([Word8], [Word8], [Word8], [Word8])]
vectors = map dec
  [ ( "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60"
    , "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a"
    , ""
    , "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b" )
  , ( "4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb"
    , "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c"
    , "72"
    , "92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00" )
  , ( "c5aa8df43f9f837bedb7442f31dcb7b166d38535076f094b85ce3a2e0b4458f7"
    , "fc51cd8e6218a1a38da47ed00230f0580816ed13ba3303ac5deb911548908025"
    , "af82"
    , "6291d657deec24024827e69c3abe01a30ce548a284743a445e3680d7db5ac3ac18ff9b538d16f290ae67f760984dc6594a7c15e9716ed28dc027beceea1ec40a" )
  , ( "4242424242424242424242424242424242424242424242424242424242424242"
    , "2152f8d19b791d24453242e15f2eab6cb7cffa7b6a5ed30097960e069881db12"
    , "536978466f7572"
    , "6b2d7e6b6a4d6d8bd34a901088787d476d931ec45bf0d30968e817bc64f7f9d4166f38b6f8a24b3a4137e40008a85317bd1e3ebb8adafda0129ac3b2a058890e" )
  ]
  where dec (a,b,c,e) = (fromHex a, fromHex b, fromHex c, fromHex e)

-- | Every vector's public key is derived correctly from its seed.
lawEd25519PublicKeyGolden :: Bool
lawEd25519PublicKeyGolden = all (\(sk, pk, _, _) -> publicKey sk == pk) vectors

-- | Every vector's signature is reproduced exactly (deterministic RFC 8032 signing).
lawEd25519SignGolden :: Bool
lawEd25519SignGolden = all (\(sk, _, m, sig) -> sign sk m == sig) vectors

-- | Every vector verifies under its public key.
lawEd25519VerifyGolden :: Bool
lawEd25519VerifyGolden = all (\(_, pk, m, sig) -> verify pk m sig) vectors

fromHex :: String -> [Word8]
fromHex [] = []
fromHex (x:y:rest) = fromIntegral (digitToInt x * 16 + digitToInt y) : fromHex rest
fromHex _ = error "SixFour.Spec.Ed25519.fromHex: odd-length hex"

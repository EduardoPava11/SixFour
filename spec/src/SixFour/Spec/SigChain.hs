{- |
Module      : SixFour.Spec.SigChain
Description : Tamper-evident creator authorship — a per-creator append-only, hash-linked chain of SIGNED authorship attestations, so "gene G was minted by creator X" is cryptographically true, not merely asserted. Each link names a "SixFour.Spec.Trade".'SixFour.Spec.Trade.GeneId' the creator claims, carries a sequence number, the hash of the previous link, and a signature over all three — so a link cannot be reordered, omitted from the interior, or its content spliced without invalidating the chain. This is the "SixFour.Spec.Lineage" @gtCreator@ claim, upgraded from a bare field to a public-key-verifiable statement (the Keybase-sigchain construction).

Two mechanisms compose the tamper-evidence, and the laws show EACH does load-bearing work:

  * the HASH CHAIN ('lPrev' = 'linkHash' of the predecessor) pins ordering and prevents interior
    omission — even a validly RE-SIGNED spliced link is caught because the successor's back-pointer no
    longer matches ('lawResignedSpliceRejected');
  * the SIGNATURE (over @seq · prev · attestation@) binds each link to its author AND its chain
    position, so a mutated body fails verification ('lawTamperedLinkRejected') and a foreign link fails
    under the creator's public key.

SIGNATURE PRIMITIVE — a STAND-IN. 'sign'\/'verify' are textbook RSA over 'Integer' (small,
shared-modulus, therefore NOT secure), included only so the sign\/verify laws are real and byte-exact
and so the chain laws are end-to-end. It satisfies the SAME interface a production Ed25519 verifier
slots into; the tamper-evidence laws below are scheme-AGNOSTIC (they hold for any correct signature).
Hand-porting a constant-time Ed25519 to GHC-boot-only Haskell + Swift and golden-gating it is tracked
separately (the research brief's open question); this module specifies the CHAIN, which is the novel,
composable part. The digest reuses "SixFour.Spec.GeneHash".'SixFour.Spec.GeneHash.fnv1a64', so the
whole social layer shares one hash.

GHC-boot-only (@base@). Laws QuickCheck'd in @Properties.SigChain@.
-}
-- COMPARTMENT: SWIFT-APP-SOCIAL | tag:DisplaySide
module SixFour.Spec.SigChain
  ( -- * The public-key primitive (a stand-in for Ed25519)
    PubKey(..)
  , SecKey(..)
  , KeyPair(..)
  , keyFor
  , sign
  , verify
    -- * The sigchain
  , Link(..)
  , SigChain
  , genesisPrev
  , linkHash
  , buildChain
  , verifyChain
    -- * Laws (QuickCheck'd in @Properties.SigChain@)
  , lawSignVerifies
  , lawTamperedMessageRejected
  , lawChainSeqConsecutive
  , lawChainPrevLinks
  , lawGenuineChainVerifies
  , lawTamperedLinkRejected
  , lawReorderBreaksChain
  , lawResignedSpliceRejected
  ) where

import           Data.Bits (shiftR)
import           Data.List (foldl')
import           Data.Word (Word8, Word64)

import           SixFour.Spec.GeneHash (fnv1a64)
import           SixFour.Spec.Trade    (GeneId(..))

-- ─────────────────────────────────────────────────────────────────────────────
-- The public-key primitive — textbook RSA over Integer. STAND-IN, not secure.
-- ─────────────────────────────────────────────────────────────────────────────

-- | A public verification key: exponent @e@ and modulus @n@.
data PubKey = PubKey { pkExp :: Integer, pkMod :: Integer } deriving (Eq, Show)

-- | A secret signing key: private exponent @d@ and modulus @n@.
data SecKey = SecKey { skExp :: Integer, skMod :: Integer } deriving (Eq, Show)

-- | A signing keypair.
data KeyPair = KeyPair { kpPub :: PubKey, kpSec :: SecKey } deriving (Eq, Show)

-- Fixed modulus for the stand-in: a product of two primes just above 2^33, so a 64-bit fnv digest is
-- strictly smaller than @n@ (no reduction loss). Shared across keys — a known RSA insecurity, fine for
-- a structural stand-in, and documented as such.
primeP, primeQ, modulusN, totientN :: Integer
primeP   = nextPrime (2 ^ (33 :: Int) + 7)
primeQ   = nextPrime (primeP + 2 ^ (12 :: Int))
modulusN = primeP * primeQ
totientN = (primeP - 1) * (primeQ - 1)

-- Public exponents coprime to the totient; a creator's seed selects one, giving distinct keypairs.
exponents :: [Integer]
exponents = filter (\e -> gcd e totientN == 1)
              [3,5,7,11,13,17,19,23,29,31,37,41,43,47,53,59,61,67,71,73,79,83,89,97,101,65537]

-- | A deterministic keypair for a creator seed (e.g. a "SixFour.Spec.Trade".'SixFour.Spec.Trade.CreatorId''s
-- integer). Distinct seeds that select distinct exponents give distinct keys. STAND-IN key derivation
-- — a real deployment binds a per-device Ed25519 key, not a shared-modulus RSA exponent.
keyFor :: Int -> KeyPair
keyFor seed =
  let e = exponents !! (seed `mod` length exponents)   -- `mod` by a positive divisor is in [0,len)
      d = modInv e totientN
  in KeyPair (PubKey e modulusN) (SecKey d modulusN)

-- | Sign a message: @digest(m)^d mod n@.
sign :: SecKey -> [Word8] -> Integer
sign (SecKey d n) msg = powMod (digest msg) d n

-- | Verify a signature: recover @sig^e mod n@ and check it equals the message digest.
verify :: PubKey -> [Word8] -> Integer -> Bool
verify (PubKey e n) msg s = powMod s e n == digest msg `mod` n

-- | The message digest fed to the primitive: the fnv-1a hash as a non-negative 'Integer' (< modulus).
digest :: [Word8] -> Integer
digest = fromIntegral . fnv1a64

-- ── number theory (boot-only) ────────────────────────────────────────────────

powMod :: Integer -> Integer -> Integer -> Integer
powMod _ 0 m = 1 `mod` m
powMod b e m =
  let half = powMod b (e `div` 2) m
      sq   = (half * half) `mod` m
  in if even e then sq else (sq * (b `mod` m)) `mod` m

-- | Modular inverse of @a@ mod @m@ (assumes @gcd a m == 1@).
modInv :: Integer -> Integer -> Integer
modInv a m = let (_, x, _) = egcd a m in x `mod` m

egcd :: Integer -> Integer -> (Integer, Integer, Integer)
egcd 0 b = (b, 0, 1)
egcd a b = let (g, x, y) = egcd (b `mod` a) a in (g, y - (b `div` a) * x, x)

isPrime :: Integer -> Bool
isPrime n
  | n < 2     = False
  | n < 4     = True
  | even n    = False
  | otherwise = go 3
  where go i | i * i > n      = True
             | n `mod` i == 0 = False
             | otherwise      = go (i + 2)

nextPrime :: Integer -> Integer
nextPrime n = if isPrime n then n else nextPrime (n + 1)

-- ─────────────────────────────────────────────────────────────────────────────
-- The sigchain.
-- ─────────────────────────────────────────────────────────────────────────────

-- | One link: its sequence number, the hash of the previous link (@genesisPrev@ for the first), the
-- 'GeneId' whose authorship it attests, and the signature over @seq · prev · attestation@.
data Link = Link
  { lSeq  :: Int      -- ^ position in the chain (0-based)
  , lPrev :: Int      -- ^ 'linkHash' of the predecessor ('genesisPrev' for the first link)
  , lAtt  :: GeneId   -- ^ the gene this link claims the creator authored
  , lSig  :: Integer  -- ^ signature over 'contentBytes' (binds author AND position)
  } deriving (Eq, Show)

-- | A creator's append-only signed authorship chain.
type SigChain = [Link]

-- | The sentinel back-pointer of the first (genesis) link.
genesisPrev :: Int
genesisPrev = 0

-- | The bytes a link commits to and signs: its sequence, back-pointer and attested gene, little-endian.
-- Excludes the signature, so the signature is a function of the other three (and thus of position).
contentBytes :: Link -> [Word8]
contentBytes l = concatMap le64 [ lSeq l, lPrev l, let GeneId i = lAtt l in i ]

-- | The hash a successor points back to: fnv-1a over the link's 'contentBytes'.
linkHash :: Link -> Int
linkHash = w64ToInt . fnv1a64 . contentBytes

-- | Append an authorship attestation, signing it with the creator's secret key. The new link's
-- back-pointer is the 'linkHash' of the current tip (or 'genesisPrev' if the chain is empty).
appendAtt :: SecKey -> SigChain -> GeneId -> SigChain
appendAtt sk chain att =
  let sq   = length chain
      prev = case chain of { [] -> genesisPrev; _ -> linkHash (last chain) }
      body = Link sq prev att 0
      sig  = sign sk (contentBytes body)
  in chain ++ [ body { lSig = sig } ]

-- | Build a whole chain by attesting a list of genes in order under one key.
buildChain :: SecKey -> [GeneId] -> SigChain
buildChain sk = foldl' (appendAtt sk) []

-- | Verify a chain under a public key: sequence numbers are @0..n-1@, every back-pointer matches the
-- predecessor's 'linkHash' (genesis for the first), and every link's signature verifies over its
-- 'contentBytes'.
verifyChain :: PubKey -> SigChain -> Bool
verifyChain pk chain =
  and [ lSeq l == i | (i, l) <- zip [0 ..] chain ]
  && prevsOk
  && all (\l -> verify pk (contentBytes l) (lSig l)) chain
  where
    prevsOk = go genesisPrev chain
    go _        []       = True
    go expected (l : ls) = lPrev l == expected && go (linkHash l) ls

-- ─────────────────────────────────────────────────────────────────────────────
-- Byte helpers (mirror "SixFour.Spec.GeneHash"'s little-endian encoding).
-- ─────────────────────────────────────────────────────────────────────────────

le64 :: Int -> [Word8]
le64 x = [ fromIntegral ((fromIntegral x :: Word64) `shiftR` (8 * i)) | i <- [0 .. 7] ]

w64ToInt :: Word64 -> Int
w64ToInt = fromIntegral

-- ─────────────────────────────────────────────────────────────────────────────
-- Laws (QuickCheck'd in @Properties.SigChain@).
-- ─────────────────────────────────────────────────────────────────────────────

-- | The primitive round-trips: a signature made with a keypair's secret verifies under its public key.
lawSignVerifies :: Int -> [Word8] -> Bool
lawSignVerifies seed msg =
  let kp = keyFor seed in verify (kpPub kp) msg (sign (kpSec kp) msg)

-- | A signature is bound to its message: verifying it against a message with a DIFFERENT digest fails.
-- Deterministic — RSA verification recovers exactly the signed digest, which then mismatches.
lawTamperedMessageRejected :: Int -> [Word8] -> [Word8] -> Bool
lawTamperedMessageRejected seed m1 m2 =
  let kp = keyFor seed
  in digest m1 == digest m2
       || not (verify (kpPub kp) m2 (sign (kpSec kp) m1))

-- | A built chain has sequence numbers @0, 1, …, n-1@.
lawChainSeqConsecutive :: Int -> [GeneId] -> Bool
lawChainSeqConsecutive seed atts =
  let chain = buildChain (kpSec (keyFor seed)) atts
  in map lSeq chain == [0 .. length atts - 1]

-- | Every link's back-pointer is the 'linkHash' of its predecessor (the genesis sentinel for the
-- first) — the hash chain is well-formed.
lawChainPrevLinks :: Int -> [GeneId] -> Bool
lawChainPrevLinks seed atts =
  let chain = buildChain (kpSec (keyFor seed)) atts
  in and [ lPrev l == expected
         | (l, expected) <- zip chain (genesisPrev : map linkHash chain) ]

-- | A genuine chain — every link built and signed by the creator — verifies under their public key.
lawGenuineChainVerifies :: Int -> [GeneId] -> Bool
lawGenuineChainVerifies seed atts =
  let kp = keyFor seed
  in verifyChain (kpPub kp) (buildChain (kpSec kp) atts)

-- | The SIGNATURE does load-bearing work: mutating a link's attested gene (leaving its now-stale
-- signature) makes the chain fail verification — the signature no longer matches the content.
lawTamperedLinkRejected :: Int -> [GeneId] -> Int -> GeneId -> Bool
lawTamperedLinkRejected seed atts i newAtt =
  let kp    = keyFor seed
      chain = buildChain (kpSec kp) atts
      n     = length chain
  in if n == 0 then True
     else let idx = i `mod` n
              bad = setAt idx (\l -> l { lAtt = newAtt }) chain
          in lAtt (chain !! idx) == newAtt          -- skip a no-op "change"
             || not (verifyChain (kpPub kp) bad)

-- | Reordering is detected: swapping two links (with distinct attestations) breaks the chain — their
-- sequence numbers and back-pointers no longer line up.
lawReorderBreaksChain :: Int -> [GeneId] -> Int -> Int -> Bool
lawReorderBreaksChain seed atts a b =
  let kp    = keyFor seed
      chain = buildChain (kpSec kp) atts
      n     = length chain
  in if n < 2 then True
     else let i = a `mod` n; j = b `mod` n
          in i == j
             || lAtt (chain !! i) == lAtt (chain !! j)
             || not (verifyChain (kpPub kp) (swapAt i j chain))

-- | The HASH CHAIN does load-bearing work independently of the signature: even if an interior link is
-- mutated and VALIDLY RE-SIGNED (so its own signature verifies), the successor's back-pointer no
-- longer matches its new 'linkHash', so the chain is still rejected. This is why a hash chain buys
-- more than per-link signatures alone.
lawResignedSpliceRejected :: Int -> [GeneId] -> Int -> GeneId -> Bool
lawResignedSpliceRejected seed atts i newAtt =
  let kp    = keyFor seed
      chain = buildChain (kpSec kp) atts
      n     = length chain
  in if n < 2 then True
     else let idx = i `mod` (n - 1)   -- an interior link (has a successor)
              old = chain !! idx
          in lAtt old == newAtt
             || let resigned = let body = old { lAtt = newAtt }
                               in body { lSig = sign (kpSec kp) (contentBytes body) }
                    spliced  = take idx chain ++ [resigned] ++ drop (idx + 1) chain
                in verify (kpPub kp) (contentBytes resigned) (lSig resigned)   -- link itself is valid
                   && not (verifyChain (kpPub kp) spliced)                     -- but the chain is not

-- helpers for the tamper laws
setAt :: Int -> (a -> a) -> [a] -> [a]
setAt i f xs = [ if k == i then f x else x | (k, x) <- zip [0 ..] xs ]

swapAt :: Int -> Int -> [a] -> [a]
swapAt i j xs =
  [ if k == i then xs !! j else if k == j then xs !! i else x
  | (k, x) <- zip [0 ..] xs ]

{- |
Module      : SixFour.Spec.SigChain
Description : Tamper-evident creator authorship — a per-creator append-only, hash-linked chain of Ed25519-SIGNED authorship attestations, so "gene G was minted by creator X" is cryptographically true, not merely asserted. Each link names a "SixFour.Spec.Trade".'SixFour.Spec.Trade.GeneId' the creator claims, carries a sequence number, the hash of the previous link, and a signature over all three — so a link cannot be reordered, omitted from the interior, or its content spliced without invalidating the chain. This is the "SixFour.Spec.Lineage" @gtCreator@ claim, upgraded from a bare field to a public-key-verifiable statement (the Keybase-sigchain construction).

Two mechanisms compose the tamper-evidence, and the laws show EACH does load-bearing work:

  * the HASH CHAIN ('lPrev' = 'linkHash' of the predecessor) pins ordering and prevents interior
    omission — even a validly RE-SIGNED spliced link is caught because the successor's back-pointer no
    longer matches ('lawResignedSpliceRejected');
  * the SIGNATURE (over @seq · prev · attestation@) binds each link to its author AND its chain
    position, so a mutated body fails verification ('lawTamperedLinkRejected') and a foreign link fails
    under the creator's public key.

The signatures are genuine __Ed25519__ (RFC 8032) via "SixFour.Spec.Ed25519" — hand-written,
byte-exact, zero third-party dependency — over the "SixFour.Spec.GeneHash".@fnv1a64@-derived link
hashes, so the whole social layer shares one hash and one signature scheme. (This supersedes the
shared-modulus RSA stand-in the module bootstrapped with; the primitive's own known-answer and
round-trip laws live in @Properties.Ed25519@.)

GHC-boot-only. Chain laws QuickCheck'd in @Properties.SigChain@.
-}
-- COMPARTMENT: SWIFT-APP-SOCIAL | tag:DisplaySide
module SixFour.Spec.SigChain
  ( -- * Creator keys (Ed25519)
    KeyPair(..)
  , keyFor
    -- * The sigchain
  , Link(..)
  , SigChain
  , genesisPrev
  , linkHash
  , contentBytes
  , buildChain
  , verifyChain
    -- * Laws (QuickCheck'd in @Properties.SigChain@)
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

import qualified SixFour.Spec.Ed25519 as Ed
import           SixFour.Spec.GeneHash (fnv1a64)
import           SixFour.Spec.Sha512   (sha512)
import           SixFour.Spec.Trade    (GeneId(..))

-- ─────────────────────────────────────────────────────────────────────────────
-- Creator keys.
-- ─────────────────────────────────────────────────────────────────────────────

-- | An Ed25519 creator identity: the 32-byte secret seed and the derived 32-byte public key.
data KeyPair = KeyPair
  { kpSeed :: [Word8]  -- ^ the secret seed (signs)
  , kpPub  :: [Word8]  -- ^ the public key (verifies)
  } deriving (Eq, Show)

-- | A deterministic Ed25519 keypair for a creator seed (e.g. a "SixFour.Spec.Trade".'SixFour.Spec.Trade.CreatorId''s
-- integer): SHA-512 the integer, take 32 bytes as the Ed25519 seed. Distinct integers give distinct
-- keys. (A real deployment binds a per-device Ed25519 key at enrolment; this makes the laws concrete.)
keyFor :: Int -> KeyPair
keyFor n = let s = take 32 (sha512 (le64 n)) in KeyPair s (Ed.publicKey s)

-- ─────────────────────────────────────────────────────────────────────────────
-- The sigchain.
-- ─────────────────────────────────────────────────────────────────────────────

-- | One link: its sequence number, the hash of the previous link (@genesisPrev@ for the first), the
-- 'GeneId' whose authorship it attests, and the Ed25519 signature over @seq · prev · attestation@.
data Link = Link
  { lSeq  :: Int       -- ^ position in the chain (0-based)
  , lPrev :: Int       -- ^ 'linkHash' of the predecessor ('genesisPrev' for the first link)
  , lAtt  :: GeneId    -- ^ the gene this link claims the creator authored
  , lSig  :: [Word8]   -- ^ Ed25519 signature over 'contentBytes' (binds author AND position)
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

-- | Append an authorship attestation, signing it with the creator's seed. The new link's back-pointer
-- is the 'linkHash' of the current tip (or 'genesisPrev' if the chain is empty).
appendAtt :: [Word8] -> SigChain -> GeneId -> SigChain
appendAtt seed chain att =
  let sq   = length chain
      prev = case chain of { [] -> genesisPrev; _ -> linkHash (last chain) }
      body = Link sq prev att []
      sig  = Ed.sign seed (contentBytes body)
  in chain ++ [ body { lSig = sig } ]

-- | Build a whole chain by attesting a list of genes in order under one seed.
buildChain :: [Word8] -> [GeneId] -> SigChain
buildChain seed = foldl' (appendAtt seed) []

-- | Verify a chain under a public key: sequence numbers are @0..n-1@, every back-pointer matches the
-- predecessor's 'linkHash' (genesis for the first), and every link's Ed25519 signature verifies over
-- its 'contentBytes'.
verifyChain :: [Word8] -> SigChain -> Bool
verifyChain pub chain =
  and [ lSeq l == i | (i, l) <- zip [0 ..] chain ]
  && prevsOk
  && all (\l -> Ed.verify pub (contentBytes l) (lSig l)) chain
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

-- | A built chain has sequence numbers @0, 1, …, n-1@.
lawChainSeqConsecutive :: Int -> [GeneId] -> Bool
lawChainSeqConsecutive seed atts =
  let chain = buildChain (kpSeed (keyFor seed)) atts
  in map lSeq chain == [0 .. length atts - 1]

-- | Every link's back-pointer is the 'linkHash' of its predecessor (the genesis sentinel for the
-- first) — the hash chain is well-formed.
lawChainPrevLinks :: Int -> [GeneId] -> Bool
lawChainPrevLinks seed atts =
  let chain = buildChain (kpSeed (keyFor seed)) atts
  in and [ lPrev l == expected
         | (l, expected) <- zip chain (genesisPrev : map linkHash chain) ]

-- | A genuine chain — every link built and signed by the creator — verifies under their public key.
lawGenuineChainVerifies :: Int -> [GeneId] -> Bool
lawGenuineChainVerifies seed atts =
  let kp = keyFor seed
  in verifyChain (kpPub kp) (buildChain (kpSeed kp) atts)

-- | The SIGNATURE does load-bearing work: mutating a link's attested gene (leaving its now-stale
-- signature) makes the chain fail verification — the signature no longer matches the content.
lawTamperedLinkRejected :: Int -> [GeneId] -> Int -> GeneId -> Bool
lawTamperedLinkRejected seed atts i newAtt =
  let kp    = keyFor seed
      chain = buildChain (kpSeed kp) atts
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
      chain = buildChain (kpSeed kp) atts
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
      chain = buildChain (kpSeed kp) atts
      n     = length chain
  in if n < 2 then True
     else let idx = i `mod` (n - 1)   -- an interior link (has a successor)
              old = chain !! idx
          in lAtt old == newAtt
             || let resigned = let body = old { lAtt = newAtt }
                               in body { lSig = Ed.sign (kpSeed kp) (contentBytes body) }
                    spliced  = take idx chain ++ [resigned] ++ drop (idx + 1) chain
                in Ed.verify (kpPub kp) (contentBytes resigned) (lSig resigned)  -- link itself is valid
                   && not (verifyChain (kpPub kp) spliced)                       -- but the chain is not

-- helpers for the tamper laws
setAt :: Int -> (a -> a) -> [a] -> [a]
setAt i f xs = [ if k == i then f x else x | (k, x) <- zip [0 ..] xs ]

swapAt :: Int -> Int -> [a] -> [a]
swapAt i j xs =
  [ if k == i then xs !! j else if k == j then xs !! i else x
  | (k, x) <- zip [0 ..] xs ]

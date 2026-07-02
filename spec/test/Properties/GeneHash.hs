{-# OPTIONS_GHC -Wno-orphans #-}
module Properties.GeneHash (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.GeneHash
import SixFour.Spec.Lineage (Genealogy)
import SixFour.Spec.Trade   (GeneId(..))
import Properties.Trade ()          -- reuse Arbitrary CreatorId / GeneId

-- A preimage: a small payload plus a few parent ids (order significant).
instance Arbitrary GenePreimage where
  arbitrary = GenePreimage <$> smallInts <*> resize 5 (listOf arbitrary)
    where smallInts = resize 6 (listOf arbitrary)
  shrink (GenePreimage pay ps) =
    [ GenePreimage pay' ps  | pay' <- shrink pay ] ++
    [ GenePreimage pay  ps' | ps'  <- shrink ps ]

-- A mint instruction: parents are indices into already-built genes, kept small.
instance Arbitrary MintOp where
  arbitrary = MintOp
    <$> arbitrary
    <*> resize 6 (listOf arbitrary)
    <*> resize 4 (listOf (choose (0, 11)))
    <*> choose (0, 20)

-- A genealogy built the only legal way — by folding mint instructions from nothing. Every such
-- genealogy is content-addressed and, by construction, acyclic.
newtype Built = Built Genealogy deriving Show

instance Arbitrary Built where
  arbitrary = Built . buildFrom <$> resize 14 (listOf arbitrary)

tests :: TestTree
tests = testGroup "GeneHash (parents[] in the content-address ⇒ acyclic genealogy)"
  [ testProperty "canonical serialisation round-trips (⇒ injective)" $
      \p -> lawCanonicalRoundTrip p
  , testProperty "different parents ⇒ different address bytes" $
      \pay ps qs -> lawParentsChangeAddress pay ps qs
  , testProperty "different payload ⇒ different address bytes" $
      \p q parents -> lawPayloadChangesAddress p q parents
  , testProperty "a minted id is the content-hash of (payload, parents)" $
      \(Built g) cr pay parents ep -> lawMintIdIsContentHash g cr pay parents ep
  , testProperty "mint refuses an absent parent" $
      \(Built g) cr pay parents ep -> lawMintRequiresParentsPresent g cr pay parents ep
  , testProperty "a new tag's address commits to its own parents" $
      \(Built g) cr pay parents ep -> lawMintedTagCommitsToParents g cr pay parents ep
  , testProperty "an origin (no parents) always mints" $
      \(Built g) cr pay ep -> lawOriginMintSucceeds g cr pay ep
  , testProperty "built genealogy: every edge points strictly backward" $
      \ops -> lawBuiltEdgesPointBackward ops
  , testProperty "THEOREM: a built genealogy is acyclic" $
      \ops -> lawBuiltGenealogyAcyclic ops
  ]

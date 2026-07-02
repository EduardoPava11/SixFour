module Properties.SigChain (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.SigChain
import SixFour.Spec.Trade (GeneId)
import Properties.Trade ()          -- reuse Arbitrary GeneId

-- Keep chains short — every link is a real Ed25519 sign/verify, so cap counts to keep the suite fast.
smallAtts :: Gen [GeneId]
smallAtts = resize 6 (listOf arbitrary)

tests :: TestTree
tests = testGroup "SigChain (tamper-evident creator authorship: an Ed25519-signed hash chain)"
  [ testProperty "a built chain has consecutive sequence numbers" $
      \seed -> forAll smallAtts $ \atts -> lawChainSeqConsecutive seed atts
  , testProperty "every back-pointer is the predecessor's linkHash" $
      withMaxSuccess 20 $ \seed -> forAll smallAtts $ \atts -> lawChainPrevLinks seed atts
  , testProperty "a genuine chain verifies under the creator's key" $
      withMaxSuccess 20 $ \seed -> forAll smallAtts $ \atts -> lawGenuineChainVerifies seed atts
  , testProperty "signature: a mutated link is rejected" $
      withMaxSuccess 20 $ \seed -> forAll smallAtts $ \atts ->
        \i newAtt -> lawTamperedLinkRejected seed atts i newAtt
  , testProperty "reorder: swapping two links breaks the chain" $
      withMaxSuccess 20 $ \seed -> forAll smallAtts $ \atts ->
        \a b -> lawReorderBreaksChain seed atts a b
  , testProperty "hash chain: a validly re-signed interior splice is still rejected" $
      withMaxSuccess 20 $ \seed -> forAll smallAtts $ \atts ->
        \i newAtt -> lawResignedSpliceRejected seed atts i newAtt
  , testProperty "non-repudiation: a foreign key cannot pass verification" $
      withMaxSuccess 20 $ \seedA seedB -> forAll smallAtts $ \atts ->
        let a = keyFor seedA
            b = keyFor seedB
        in kpPub a == kpPub b || null atts
             || not (verifyChain (kpPub b) (buildChain (kpSeed a) atts))
  ]

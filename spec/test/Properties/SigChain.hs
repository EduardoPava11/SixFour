module Properties.SigChain (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.SigChain
import Properties.Trade ()          -- reuse Arbitrary GeneId

tests :: TestTree
tests = testGroup "SigChain (tamper-evident creator authorship: a signed hash chain)"
  [ testProperty "the primitive round-trips: sign then verify" $
      \seed msg -> lawSignVerifies seed msg
  , testProperty "a signature is bound to its message" $
      \seed m1 m2 -> lawTamperedMessageRejected seed m1 m2
  , testProperty "a built chain has consecutive sequence numbers" $
      \seed atts -> lawChainSeqConsecutive seed atts
  , testProperty "every back-pointer is the predecessor's linkHash" $
      \seed atts -> lawChainPrevLinks seed atts
  , testProperty "a genuine chain verifies under the creator's key" $
      \seed atts -> lawGenuineChainVerifies seed atts
  , testProperty "signature: a mutated link is rejected" $
      \seed atts i newAtt -> lawTamperedLinkRejected seed atts i newAtt
  , testProperty "reorder: swapping two links breaks the chain" $
      \seed atts a b -> lawReorderBreaksChain seed atts a b
  , testProperty "hash chain: a validly re-signed interior splice is still rejected" $
      \seed atts i newAtt -> lawResignedSpliceRejected seed atts i newAtt
  , testProperty "non-repudiation: a foreign key cannot pass verification" $
      \seedA seedB atts ->
        let a = keyFor seedA
            b = keyFor seedB
        in kpPub a == kpPub b || null atts
             || not (verifyChain (kpPub b) (buildChain (kpSec a) atts))
  ]

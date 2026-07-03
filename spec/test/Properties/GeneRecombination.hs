module Properties.GeneRecombination (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.GeneRecombination
import SixFour.Spec.GeneHash        (GenePreimage(..), geneHash, MintOp(..), lawBuiltGenealogyAcyclic)
import SixFour.Spec.Trade           (CreatorId(..), GeneId(..), Ledger, propose, accept)
import SixFour.Spec.GeneSimilarity  (geneDistance)
import SixFour.Spec.DetailPredictor (defaultPredictorShape)
import SixFour.Spec.Q16             (toQ16)

paramsOf :: GenePreimage -> [Double]
paramsOf = map toQ16 . gpPayload

-- Pinned parents: a diverse off-floor gene and the flat floor seed.
payloadA, payloadB :: [Int]
payloadA = take 21 (cycle [65536, 32768, 16384])
payloadB = replicate 21 0

pa, pb :: ParentGene
pa = GenePreimage payloadA []
pb = GenePreimage payloadB []

alice, bob :: CreatorId
alice = CreatorId 1
bob   = CreatorId 2

-- A settled grant of gene `offered` to bob (alice offers, bob accepts).
grantTo :: GeneId -> GeneId -> a -> Ledger
grantTo offered dummyWant _ = [ accept bob Nothing (propose alice offered (Just dummyWant) 0) ]

ledgerBoth, ledgerOne :: Ledger
ledgerBoth = grantTo (idOf pa) (GeneId 900) () ++ grantTo (idOf pb) (GeneId 901) ()
ledgerOne  = grantTo (idOf pa) (GeneId 900) ()

childHalf :: Child
childHalf = recombine defaultPredictorShape halfLambda pa pb

-- The deliberately-WRONG grant predicate (OR = the single-parent laundering hole).
mayGrantChildWrong :: Ledger -> CreatorId -> Child -> Bool
mayGrantChildWrong led who child =
  holdsGene led who (gpParents child !! 0) || holdsGene led who (gpParents child !! 1)

-- Random parents for the structural laws.
genParent :: Gen ParentGene
genParent = (\ws -> GenePreimage ws []) <$> vectorOf 21 (choose (-65536, 65536))

tests :: TestTree
tests = testGroup "GeneRecombination (sexual crossover, balanced by lineage-keyed grant)"
  [ testProperty "G1 lambda=0x8000 payload == per-word midpoint floor((a+b)/2)" $
      once (gpPayload childHalf == take 21 (cycle [32768, 16384, 8192]))

  , testProperty "endpoint recovery: lambda=0 -> pa, lambda=unit -> pb (byte-exact AND cloud distance 0)" $
      once ( lawBlendRecoversParentAtEndpoint pa pb
           && geneDistance defaultPredictorShape (paramsOf (recombine defaultPredictorShape 0 pa pb)) (paramsOf pa) == 0
           && geneDistance defaultPredictorShape (paramsOf (recombine defaultPredictorShape unitQ16 pa pb)) (paramsOf pb) == 0 )

  , testProperty "ordered lineage: hash(child pa pb) /= hash(child pb pa) though midpoint payloads are equal" $
      once ( geneHash childHalf /= geneHash (recombine defaultPredictorShape halfLambda pb pa)
           && gpPayload childHalf == gpPayload (recombine defaultPredictorShape halfLambda pb pa) )

  , testProperty "KEYSTONE lawChildGrantableIffBothParentsHeld on both/one/none ledgers" $
      once ( lawChildGrantableIffBothParentsHeld ledgerBoth bob pa pb
           && lawChildGrantableIffBothParentsHeld ledgerOne  bob pa pb
           && lawChildGrantableIffBothParentsHeld []         bob pa pb )

  , testProperty "NON-VACUITY: correct grant refuses single-parent laundering; WRONG (OR) launders and FAILS the keystone" $
      once ( not (mayGrantChild ledgerOne bob childHalf)
           && keystoneWith mayGrantChild      ledgerOne bob pa pb
           && not (keystoneWith mayGrantChildWrong ledgerOne bob pa pb) )

  , testProperty "MUST-NOT-BREAK: the recombination genealogy stays acyclic (lawBuiltGenealogyAcyclic)" $
      once (lawBuiltGenealogyAcyclic
              [ MintOp alice payloadA [] 0
              , MintOp alice payloadB [] 0
              , MintOp bob (gpPayload childHalf) [0,1] 1 ])

  , testProperty "child stays on the 21-word manifold (no dimensionality drift)" $
      forAll genParent $ \a -> forAll genParent (lawCrossoverPreservesShape halfLambda a)

  , testProperty "child lineage is exactly the ordered mate pair" $
      forAll genParent $ \a -> forAll genParent (lawChildParentsAreMates halfLambda a)

  , testProperty "BALANCE: crossover conjures no credit (empty ledger -> child not grantable)" $
      forAll genParent $ \a -> forAll genParent (lawRecombineCreditNeutralOnEmptyLedger bob a)
  ]

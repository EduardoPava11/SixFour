{- |
Module      : Properties.DecisionLog
Description : Property tests for 'SixFour.Spec.DecisionLog' — the SF64 TLV
              replay container.

Generators produce wire-representable logs (u8 bins, 384-float genomes, ≤8
visit rows, 24576-float boards) plus the occasional non-canonical one — the
round trip is stated through 'normalizeLog' so both are exercised.
-}
module Properties.DecisionLog (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Test.QuickCheck

import qualified Data.Vector as V

import SixFour.Spec.AtlasBoard  (BinIdx(..), Board16, boardTensor, okLabToQ16)
import SixFour.Spec.AtlasMove   (CurationMove(..), GenomeHash(..), Q88(..),
                                 boardFromLog)
import SixFour.Spec.Color       (OKLab(..))
import SixFour.Spec.DecisionLog

genOKLab :: Gen OKLab
genOKLab = OKLab <$> choose (0, 1) <*> choose (-0.4, 0.4) <*> choose (-0.4, 0.4)

genBin :: Gen BinIdx
genBin = fmap BinIdx ((,,) <$> choose (0, 15) <*> choose (0, 15) <*> choose (0, 15))

genHash :: Gen GenomeHash
genHash = GenomeHash <$> arbitrary

genCuration :: Gen CurationMove
genCuration = oneof
  [ ToggleBin <$> genBin
  , WeightRegion <$> genBin <*> (Q88 <$> arbitrary)
  , PinAnchor <$> genBin <*> (okLabToQ16 <$> genOKLab)
  , Compare <$> genHash <*> genHash
  ]

genF32 :: Gen Float
genF32 = choose (-4, 4)

genBoard :: Gen Board16
genBoard = do
  pals   <- resize 2 (listOf (resize 6 (listOf genOKLab)))
  pixels <- resize 8 (listOf genOKLab)
  pure (boardFromLog (boardTensor pals pixels []) [])

-- | A wire-representable log (kept small — a BORD plane is 24576 floats).
genLog :: Gen SF64Log
genLog = do
  ds <- resize 10 (listOf genCuration)
  gs <- resize 2 (listOf ((,) <$> genHash <*> vectorOf genomeFloats genF32))
  vs <- resize 2 (listOf ((,) <$> genHash
                              <*> resize visitCap
                                    (listOf ((,) <$> arbitrary <*> genF32))))
  bs <- frequency [ (3, pure [])
                  , (1, (: []) . boardSnapshot <$> genBoard) ]
  es <- resize 2 (listOf ((,,,) <$> genHash <*> genHash
                                <*> vectorOf embeddingFloats genF32
                                <*> vectorOf embeddingFloats genF32))
  pure (SF64Log ds gs vs bs es)

tests :: TestTree
tests = testGroup "DecisionLog (SF64 TLV replay container)"
  [ testProperty "round trip: decode . encode = normalizeLog (= id when well-formed)" $
      withMaxSuccess 50 $ forAll genLog $ \lg ->
        lawRoundTrip lg .&&. property (wellFormedLog lg ==> normalizeLog lg == lg)
  , testProperty "TLV chunks decode order-insensitively" $
      withMaxSuccess 30 $ forAll genLog $ \lg ->
        forAll (resize 6 (listOf (choose (0, 3)))) $ \perm ->
          lawTLVOrderInsensitive lg perm
  , testProperty "DECN entries are exactly 32 B (explicit named-field sum)" $
      forAll genCuration lawEntrySize32
  , testProperty "unknown chunk tags are skipped (forward compatibility)" $
      withMaxSuccess 30 $ forAll genLog $ \lg ->
        forAll arbitrary $ \at -> forAll (resize 16 (listOf arbitrary)) $ \junk ->
          lawUnknownTagSkip lg at junk
  , testProperty "replay is monotone: appending never disturbs the prefix" $
      forAll genBoard $ \b ->
      forAll (resize 8 (listOf genCuration)) $ \xs ->
      forAll (resize 8 (listOf genCuration)) $ \ys ->
        lawReplayMonotone b xs ys
  , testProperty "non-zero pad is REJECTED on read (assert-zero contract)" $
      forAll genCuration $ \m ->
        let bs       = encodeEntry m
            poisoned = take (decnEntrySize - 1) bs ++ [1]
        in decodeEntry poisoned == Nothing
  , testProperty "truncated containers and bad magic are rejected (total decode)" $
      forAll genLog $ \lg ->
        let bs = encodeLog lg
        in decodeLog (take (length bs - 1) bs) == Nothing
             && decodeLog (0x58 : drop 1 bs) == Nothing
  , testProperty "board snapshot has the [16,16,16,6] float count" $
      forAll genBoard $ \b -> V.length (boardSnapshot b) == boardFloats
  , testProperty "CMPE Compare embeddings round-trip (770-f winner/loser survive)" $
      withMaxSuccess 30 $
        forAll (resize 2 (listOf ((,,,) <$> genHash <*> genHash
                                        <*> vectorOf embeddingFloats genF32
                                        <*> vectorOf embeddingFloats genF32)))
          lawCompareEmbeddingRoundTrip
  , testProperty "backward compat: a v1 container (no CMPE) decodes with empty embeddings" $
      withMaxSuccess 40 $ forAll genLog lawBackwardCompatNoCMPE
  ]

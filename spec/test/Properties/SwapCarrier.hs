module Properties.SwapCarrier (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.Lineage     (GeneTag (..))
import SixFour.Spec.SwapCarrier
import SixFour.Spec.Trade       (CreatorId (..), GeneId (..))

-- gene/creator/parents span the FULL i64 range (the 64-bit GeneHash id); minted is the i32 epoch.
genTag :: Gen GeneTag
genTag = GeneTag
  <$> (GeneId <$> choose (-9223372036854775808, 9223372036854775807))
  <*> (CreatorId <$> choose (-9223372036854775808, 9223372036854775807))
  <*> (fmap GeneId <$> listOf (choose (-9223372036854775808, 9223372036854775807)))
  <*> choose (0, 2147483647)

genPayload :: Gen SwapPayload
genPayload = SwapPayload
  <$> elements [Showcase, Grant]
  <*> (do n <- choose (0, 24); vectorOf n (elements (['a' .. 'z'] ++ "-0123456789")))
  <*> genTag
  <*> (do k <- choose (0, 400); vectorOf k (choose (-2147483648, 2147483647 :: Int)))

tests :: TestTree
tests = testGroup "SwapCarrier (S4GX gene-in-GIF codec — the governance-swap wire + mint gate)"
  [ testProperty "embed/extract round-trip (gene + lineage tag + grant weights) byte-exact" $
      forAll genPayload lawEmbedExtractRoundTrip

  , testProperty "valid GIF89a Application-Extension framing (viewers play it, parsers skip it)" $
      forAll genPayload lawGif89aValidity

  , testProperty "a Showcase is INERT on the wire: no weights serialized, expresses as the floor" $
      forAll genPayload lawShowcaseIsInert

  , testProperty "grants mint ONLY from a settled trade (hybrid: both parties; creator sovereign; fallback = showcase)" $
      once lawGrantOnlyFromSettledTrade

  , testProperty "carriage is memehood (a carried Somatic theta-up is a Meme; the registry is untouched)" $
      once lawCarriageIsMemehood

  , testProperty "grant weight counts derive from the gene registry (384 sigma-look / 21 theta-up; off-by-one fails)" $
      once lawWireSizesFromRegistry

  , testProperty "S4GN and S4GX blocks coexist in one GIF; each extractor finds only its own" $
      once lawBlocksCoexist

  , testProperty "CRC32 rejects any single-byte corruption" $
      forAll genPayload $ \p -> forAll (choose (0, 4000)) (lawCRCRejectsCorruption p)

  , testProperty "version: minor forward-compatible, future major refused (never a partial parse)" $
      forAll genPayload lawVersionTolerance

  , testProperty "a 64-bit GeneHash id survives the round-trip (v1 truncated it — the R2 fix)" $
      once lawWideIdSurvivesRoundTrip
  ]

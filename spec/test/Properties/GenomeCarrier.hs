module Properties.GenomeCarrier (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.GenomeCarrier

genHeader :: Gen S4GNHeader
genHeader = S4GNHeader
  <$> elements [0, 1, 2]                                  -- major (1 = current)
  <*> (fromIntegral <$> choose (0, 5 :: Int))            -- minor
  <*> (fromIntegral <$> choose (0, 65535 :: Int))        -- flags
  <*> (fromIntegral <$> choose (0, 768 :: Int))          -- dof
  <*> (fromIntegral <$> choose (0, 255 :: Int))          -- radix
  <*> (fromIntegral <$> choose (0, 4294967295 :: Integer)) -- deviceIdHash
  <*> (fromIntegral <$> choose (0, 100000 :: Int))       -- btCompares

genPayload :: Gen GenomePayload
genPayload = do
  h  <- genHeader
  k  <- choose (0, 400)
  cs <- vectorOf k (choose (-2147483648, 2147483647 :: Int))
  pure (GenomePayload h cs)

tests :: TestTree
tests = testGroup "GenomeCarrier (S4GN genome-in-GIF codec — Int32 LE Q16 + CRC32)"
  [ testProperty "embed/extract round-trip (current major) byte-exact" $
      forAll genPayload lawEmbedExtractRoundTrip

  , testProperty "valid GIF89a Application-Extension framing" $
      forAll genPayload lawGif89aValidity

  , testProperty "canonical capacity fits (1536 / 1564 / 7 sub-blocks)" (once lawCapacityFits)

  , testProperty "Int32 Q16 coefficients round-trip exact" $
      forAll genPayload lawQ16RoundTripExact

  , testProperty "CRC32 rejects any single-byte corruption" $
      forAll genPayload $ \p -> forAll (choose (0, 2000)) (lawCRCRejectsCorruption p)

  , testProperty "version: minor forward-compatible, major rejected" $
      forAll genPayload lawVersionTolerance
  ]

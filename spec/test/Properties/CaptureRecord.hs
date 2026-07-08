module Properties.CaptureRecord (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.CaptureRecord
import SixFour.Spec.WeaveOrder (WeaveRung (..))

genRung :: Gen WeaveRung
genRung = elements [W64, W32, W16]

genAscii :: Gen String
genAscii = listOf (elements (['a' .. 'z'] ++ ['0' .. '9']))

genUInt :: Gen Integer
genUInt = getNonNegative <$> arbitrary

-- | Sized CBOR values inside the subset (unsigned, bytes, ASCII text,
-- arrays, maps).
genCbor :: Int -> Gen Cbor
genCbor depth = oneof (leaves ++ if depth <= 0 then [] else branches)
  where
    leaves =
      [ CUInt . getNonNegative <$> arbitrary
      , CBytes <$> listOf (fromIntegral <$> choose (0, 255 :: Int))
      , CText <$> genAscii
      ]
    branches =
      [ CArray <$> resize 4 (listOf (genCbor (depth - 1)))
      , CMap <$> resize 4 (listOf ((,) <$> genCbor 0 <*> genCbor (depth - 1)))
      ]

genExposure :: Gen RungExposure
genExposure = RungExposure <$> genUInt <*> genUInt <*> arbitrary -- EV is SIGNED

genTelemetry :: Gen (Maybe TelemetrySnapshot)
genTelemetry = oneof
  [ pure Nothing
  , Just <$> (TelemetrySnapshot <$> listOf genUInt <*> listOf genUInt <*> genUInt)
  ]

genRecord :: Gen CaptureRecord
genRecord = do
  w   <- listOf genRung
  dts <- listOf (getNonNegative <$> arbitrary)
  ss  <- listOf (getNonNegative <$> arbitrary)
  g   <- listOf (fromIntegral <$> choose (0, 255 :: Int))
  pure goldenRecord { crWeave = w, crFrameIntervalsUs = dts
                    , crSums16 = ss, crGct = g }

-- | A version-2 record: the v1 fields plus populated rung cubes, exposures,
-- telemetry — the 12-key wire shape.
genRecordV2 :: Gen CaptureRecord
genRecordV2 = do
  base <- genRecord
  c64  <- listOf genUInt
  c32  <- listOf genUInt
  c16  <- listOf genUInt
  es   <- resize 3 (listOf genExposure)
  tel  <- genTelemetry
  pure base { crVersion = 2, crCube64 = c64, crCube32 = c32, crCube16 = c16
            , crExposures = es, crTelemetry = tel }

tests :: TestTree
tests = testGroup "CaptureRecord (the shutter's ledger: deterministic CBOR, order preserved)"
  [ testGroup "The deterministic subset"
      [ testProperty "heads are minimal at every boundary" $
          once lawHeadsAreMinimal
      , testProperty "map keys strictly increasing bytewise (core deterministic)" $
          forAll genRecord lawMapKeysSortedBytewise
      , testProperty "map keys strictly increasing bytewise on the 12-key v2 map" $
          forAll genRecordV2 lawMapKeysSortedBytewise
      , testProperty "decode inverts encode (canonical, all bytes consumed)" $
          forAll (genCbor 3) lawDecodeInvertsEncode
      , testProperty "re-encoding a decoded encoding is byte-identical" $
          forAll (genCbor 3) lawEncodingIsCanonicallyStable
      , testProperty "zigzag round-trips every signed integer inside major 0" $
          lawZigzagRoundTrips
      ]

  , testGroup "The record"
      [ testProperty "KEYSTONE: the weave word survives the bytes IN ORDER" $
          forAll (listOf genRung) lawWeaveSurvivesTheRecord
      , testProperty "golden bytes pinned (the Swift port's parity gate)" $
          once lawGoldenRecordPinned
      ]

  , testGroup "Version 2 — the independent rungs"
      [ testProperty "the weave word survives the v2 record too" $
          forAll (listOf genRung) lawWeaveSurvivesTheRecordV2
      , testProperty "cubes, exposures (signed EV), telemetry survive the bytes" $
          forAll ((,,,,) <$> listOf genUInt <*> listOf genUInt <*> listOf genUInt
                         <*> resize 3 (listOf genExposure) <*> genTelemetry) $
            \(c64, c32, c16, es, tel) ->
              lawRungFieldsSurviveTheRecord c64 c32 c16 es tel
      , testProperty "v1 records decode under the v2 reader (absent-as-empty)" $
          once lawV1DecodesUnderV2Reader
      , testProperty "golden v2 bytes pinned (the Swift v2 writer's parity gate)" $
          once lawGoldenRecordV2Pinned
      ]
  ]

module Properties.CaptureRecord (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.CaptureRecord
import SixFour.Spec.WeaveOrder (WeaveRung (..))

genRung :: Gen WeaveRung
genRung = elements [W64, W32, W16]

genAscii :: Gen String
genAscii = listOf (elements (['a' .. 'z'] ++ ['0' .. '9']))

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

genRecord :: Gen CaptureRecord
genRecord = do
  w   <- listOf genRung
  dts <- listOf (getNonNegative <$> arbitrary)
  ss  <- listOf (getNonNegative <$> arbitrary)
  g   <- listOf (fromIntegral <$> choose (0, 255 :: Int))
  pure goldenRecord { crWeave = w, crFrameIntervalsUs = dts
                    , crSums16 = ss, crGct = g }

tests :: TestTree
tests = testGroup "CaptureRecord (the shutter's ledger: deterministic CBOR, order preserved)"
  [ testGroup "The deterministic subset"
      [ testProperty "heads are minimal at every boundary" $
          once lawHeadsAreMinimal
      , testProperty "map keys strictly increasing bytewise (core deterministic)" $
          forAll genRecord lawMapKeysSortedBytewise
      , testProperty "decode inverts encode (canonical, all bytes consumed)" $
          forAll (genCbor 3) lawDecodeInvertsEncode
      , testProperty "re-encoding a decoded encoding is byte-identical" $
          forAll (genCbor 3) lawEncodingIsCanonicallyStable
      ]

  , testGroup "The record"
      [ testProperty "KEYSTONE: the weave word survives the bytes IN ORDER" $
          forAll (listOf genRung) lawWeaveSurvivesTheRecord
      , testProperty "golden bytes pinned (the Swift port's parity gate)" $
          once lawGoldenRecordPinned
      ]
  ]

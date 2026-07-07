module Properties.RadiometricRealize (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.RadiometricRealize

-- Raw linear16 seeds (each law clamps into [0,65535] itself, as the device fills
-- linear-light bin sums).
genLin :: Gen Int
genLin = choose (0, 65535)

tests :: TestTree
tests = testGroup "RadiometricRealize (inverse-EOTF realization: linear16 bin sums → sRGB8)"
  [ testProperty "KEYSTONE: encode is the EXACT inverse of the sRGB decode (round-trips all 256 codes)"
      lawEncodeInvertsEotf
  , testProperty "endpoints: black→0, full-linear→255" $
      once lawBlackWhiteEndpoints
  , testProperty "encode is monotone nondecreasing in linear16" $
      forAll genLin $ \a -> forAll genLin $ \b -> lawRealizeMonotone a b
  , testProperty "TEETH: mean-then-encode does NOT compose (mid-gray → 188, not 128)" $
      once lawRealizeIsMeanThenEncode
  , testProperty "BT.2020→sRGB: the neutral (grey) axis is preserved bit-exactly" $
      forAll genLin lawGrayAxisPreserved
  , testProperty "BT.2020→sRGB: gamut-hop endpoints (black→black, white→white)" $
      once lawBt2020Endpoints
  , testProperty "BT.2020→sRGB: TOTAL — every output channel clamps into [0,65535]" $
      forAll genLin $ \r -> forAll genLin $ \g -> forAll genLin $ \b -> lawBt2020InGamut r g b
    -- The Zig literal golden matches the oracle (spot-checks pinned in
    -- palette16_test.zig; here we pin the oracle values themselves).
  , testProperty "encode spot goldens (thresh boundaries + mid-gray)" $ once $
      srgbEncodeThresh16 1 == 10 && srgbEncodeThresh16 2 == 30
        && srgbEncodeThresh16 10 == 189 && srgbEncodeThresh16 64 == 3309
        && srgbEncodeThresh16 128 == 14027 && srgbEncodeThresh16 255 == 65243
        && linear16ToSrgb8 14146 == 128 && linear16ToSrgb8 32768 == 188
  , testProperty "BT.2020 Q15 matrix rows sum to 32768 (grey-preserving)" $ once $
      let m = bt2020ToSrgbQ15
      in sum (take 3 m) == 32768
           && sum (take 3 (drop 3 m)) == 32768
           && sum (take 3 (drop 6 m)) == 32768
  ]

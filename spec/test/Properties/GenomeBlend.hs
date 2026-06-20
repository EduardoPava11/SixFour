{- |
Module      : Properties.GenomeBlend
Description : Property tests for 'SixFour.Spec.GenomeBlend' — receiver-side
              federated transport (a foreign look enters as ONE gated Compare).

Wires the six exported laws into the suite (the source module's "test wiring
pending — build step 7"). σ-override and integer-Haar generators mirror
'Properties.LeafOverride' / 'Properties.PairTreeFixed'; each adoption scenario is
generated at one consistent embedding dimension so the gate and score paths are
exercised non-trivially.
-}
module Properties.GenomeBlend (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Test.QuickCheck

import SixFour.Spec.Preference     (Embedding)
import SixFour.Spec.PairTreeFixed  (OKLabI, HaarPaletteI, analyzeFixed)
import SixFour.Spec.LeafOverride   (SigmaOverride)
import SixFour.Spec.PersonalGenome (PersonalGenome(..), Pick, genomeVersion)
import SixFour.Spec.GenomeBlend

-- -- Embedding-space generators (one consistent dimension per scenario) --------

genDim :: Gen Int
genDim = choose (1, 8)

genVecN :: Int -> Gen [Double]
genVecN n = vectorOf n (choose (-2, 2))

genPickN :: Int -> Gen Pick
genPickN n = (,) <$> genVecN n <*> genVecN n

genLogN :: Int -> Gen [Pick]
genLogN n = choose (0, 8) >>= \k -> vectorOf k (genPickN n)

genGenomeN :: Int -> Gen PersonalGenome
genGenomeN n = PersonalGenome <$> genVecN n <*> choose (0, 40) <*> pure genomeVersion

-- -- σ-override + integer-Haar generators (mirror Properties.LeafOverride) -----

genPxI :: Gen OKLabI
genPxI = (,,) <$> choose (0, 65536) <*> choose (-26214, 26214) <*> choose (-26214, 26214)

genDeltaI :: Gen OKLabI
genDeltaI = (,,) <$> choose (-8192, 8192) <*> choose (-8192, 8192) <*> choose (-8192, 8192)

genOverride :: Gen SigmaOverride
genOverride = choose (0, 160) >>= \k -> vectorOf k genDeltaI

genHaarI :: Gen HaarPaletteI
genHaarI = do
  d <- choose (0, 7) :: Gen Int
  analyzeFixed <$> vectorOf (2 ^ d) genPxI

-- -- Foreign payload + extraction outcome --------------------------------------

-- | Trust spans both sides of zero so the zero-trust identity path is hit ~¼ of
-- the time and the trusted-adoption path the rest.
genTrust :: Gen Double
genTrust = choose (-1, 3)

genForeignN :: Int -> Gen ForeignGenome
genForeignN n = ForeignGenome <$> genOverride <*> genVecN n <*> genTrust

genForeign :: Gen ForeignGenome
genForeign = genDim >>= genForeignN

genExtractedN :: Int -> Gen Extracted
genExtractedN n = frequency
  [ (3, Present <$> genForeignN n)
  , (1, pure Absent)
  , (1, pure Corrupt)
  ]

tests :: TestTree
tests = testGroup "GenomeBlend (receiver-side federated transport — gated Compare)"
  [ testProperty "adoption is exactly ONE Compare, never a splice" $
      forAll genDim $ \n -> forAll (genGenomeN n) $ \cur -> forAll (genLogN n) $ \recent ->
        forAll (genVecN n) $ \local -> forAll (genForeignN n) $ \fg ->
          lawBlendIsACompare cur recent local fg
  , testProperty "zero trust is the exact identity" $
      forAll genDim $ \n -> forAll (genGenomeN n) $ \cur -> forAll (genLogN n) $ \recent ->
        forAll (genVecN n) $ \local -> forAll (genForeignN n) $ \fg ->
          lawZeroTrustIsIdentity cur recent local fg
  , testProperty "absent and corrupt never change theta" $
      forAll genDim $ \n -> forAll (genGenomeN n) $ \cur -> forAll (genLogN n) $ \recent ->
        forAll (genVecN n) $ \local -> lawNoForeignIsIdentity cur recent local
  , testProperty "any non-Adopted outcome keeps the current genome" $
      forAll genDim $ \n -> forAll (genGenomeN n) $ \cur -> forAll (genLogN n) $ \recent ->
        forAll (genVecN n) $ \local -> forAll (genExtractedN n) $ \ext ->
          lawResistedKeepsCurrent cur recent local ext
  , testProperty "high local confidence resists a regressing blend (the gate)" $
      forAll genDim $ \n -> forAll (genGenomeN n) $ \cur -> forAll (genLogN n) $ \recent ->
        forAll (genVecN n) $ \local -> forAll (genForeignN n) $ \fg ->
          lawHighLocalConfidenceResistsBlend cur recent local fg
  , testProperty "a foreign look stays sigma-symmetric over any base palette" $
      forAll genForeign $ \fg -> forAll genHaarI (lawBlendStaysSigmaSymmetric fg)
  ]

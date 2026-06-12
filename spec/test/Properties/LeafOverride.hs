module Properties.LeafOverride (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.PairTreeFixed  (OKLabI, HaarPaletteI, analyzeFixed, reconstructFixed)
import SixFour.Spec.SigmaPairFixed (reconstructPairedFixed, sigmaReflectI)
import SixFour.Spec.LeafOverride

-- A Q16 OKLab triple (same bounds as Properties.SigmaPairFixed).
genPxI :: Gen OKLabI
genPxI = (,,) <$> choose (0, 65536) <*> choose (-26214, 26214) <*> choose (-26214, 26214)

-- A small Q16 δ — bipolar, the slider's range.
genDeltaI :: Gen OKLabI
genDeltaI = (,,) <$> choose (-8192, 8192) <*> choose (-8192, 8192) <*> choose (-8192, 8192)

-- A well-formed integer Haar tree of depth 0..7 (the σ-pair generator tree is depth 7).
genHaarI :: Gen HaarPaletteI
genHaarI = do
  d <- choose (0, 7) :: Gen Int
  analyzeFixed <$> vectorOf (2 ^ d) genPxI

-- An override of arbitrary length (incl. shorter than the generator count → zero-padded,
-- and longer → extra entries ignored).
genOverride :: Gen SigmaOverride
genOverride = do
  k <- choose (0, 160) :: Gen Int
  vectorOf k genDeltaI

tests :: TestTree
tests = testGroup "LeafOverride (generator-space σ-locked δ — EXACT, no tolerance)"
  [ testProperty "identity override (all-zero) is a byte-exact no-op" $
      forAll genHaarI lawSigmaOverrideIdentityNoOp

  , testProperty "the empty override equals reconstructPairedFixed" $
      forAll genHaarI $ \hp ->
        applySigmaOverride zeroSigmaOverride hp == reconstructPairedFixed hp

  , testProperty "ANY override keeps the palette σ-fixed (symmetry unbreakable)" $
      forAll genOverride $ \o -> forAll genHaarI (lawSigmaOverridePreservesSymmetry o)

  , testProperty "the override adds EXACTLY to the generators (δ reaches the genome)" $
      forAll genOverride $ \o -> forAll genHaarI (lawSigmaOverrideAddsToGenerators o)

  , testProperty "an override on generator i touches ONLY leaves 2i, 2i+1 (brush-scoped)" $
      forAll genHaarI $ \hp ->
        forAll (choose (0, 1000)) $ \i ->
          forAll genDeltaI (lawSigmaOverrideScopedToGenerator hp i)

  , testProperty "every odd leaf is the σ-reflection of its even predecessor (post-override)" $
      forAll genOverride $ \o -> forAll genHaarI (lawSigmaOverrideOddLeafCarriesSigmaOfNudged o)

  , testProperty "a nonzero δ on generator i DOES move its pair (the edit is real)" $
      forAll genHaarI $ \hp ->
        let gens = reconstructFixed hp in not (null gens) ==>
        forAll (choose (0, length gens - 1)) $ \i ->
          forAll genDeltaI $ \d -> d /= (0,0,0) ==>
            let o    = replicate i (0,0,0) ++ [d]
                base = reconstructPairedFixed hp
                pal  = applySigmaOverride o hp
            in pal !! (2*i) /= base !! (2*i)
            && pal !! (2*i+1) == sigmaReflectI (pal !! (2*i))

  -- NEW adversarial laws ----------------------------------------------------

  , testProperty "δ is ADDITIVE in generator space (apply o₁⊕o₂ == add δ₁+δ₂)" $
      forAll genOverride $ \o1 -> forAll genOverride $ \o2 ->
        forAll genHaarI (lawSigmaOverrideAdditive o1 o2)

  , testProperty "override is IGNORED past the generator count (tail is inert)" $
      forAll genOverride $ \o -> forAll genOverride $ \tl ->
        forAll genHaarI (lawSigmaOverrideIgnoresTailPastGenerators o tl)

  , testProperty "DIFFERENT generators get INDEPENDENT deltas (no cross-talk)" $
      forAll genHaarI $ \hp ->
        forAll (choose (0, 1000)) $ \i -> forAll (choose (0, 1000)) $ \j ->
          forAll genDeltaI $ \di -> forAll genDeltaI $ \dj ->
            lawSigmaOverrideGeneratorsIndependent hp i j di dj
  ]

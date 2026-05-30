-- | Laws for 'SixFour.Spec.Obfuscation': the lossless grey/chroma split Ω
-- (BLEED_LOOP Def 45–47, laws L45.1–L45.8, Thm 14). L obfuscates A+B: the grayscale
-- view HIDES chroma, retained and recoverable — it never discards it.
module Properties.Obfuscation (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck

import SixFour.Spec.Color       (OKLab(..))
import SixFour.Spec.PairTree    (sigmaReflect)
import SixFour.Spec.Obfuscation

genOKLab :: Gen OKLab
genOKLab = OKLab <$> choose (0, 1) <*> choose (-0.4, 0.4) <*> choose (-0.4, 0.4)

-- | A guaranteed-chromatic colour (|chroma| bounded away from 0), for the
-- discriminating law's existential witness.
genChromatic :: Gen OKLab
genChromatic = do
  l <- choose (0, 1)
  a <- oneof [choose (0.05, 0.4), choose (-0.4, -0.05)]
  b <- choose (-0.4, 0.4)
  pure (OKLab l a b)

genPal :: Gen [OKLab]
genPal = resize 32 (listOf1 genOKLab)

eqLab :: OKLab -> OKLab -> Bool
eqLab (OKLab l1 a1 b1) (OKLab l2 a2 b2) = l1 == l2 && a1 == a2 && b1 == b2

-- | Float-tolerant equality (Parseval sums in a different association order).
approx :: Double -> Double -> Bool
approx x y = abs (x - y) <= 1e-9

tests :: TestTree
tests = testGroup "Obfuscation (L hides A+B — the lossless Ω split)"
  [ -- L45.1 — the GRAYSCALE-TRUTH discriminator (adjudicates the architecture).
    -- 'shown' (= projectAxis AxisL) ZEROES chroma; the σ kernel 'sigmaReflect'
    -- (the σ inside symPart = ½(H+σH)) PRESERVES chroma magnitude. So symPart is
    -- NOT the obfuscation operator.
    testProperty "L45.1 GRAYSCALE-TRUTH: shown is achromatic (a=b=0)" $
      forAll genOKLab $ \c -> isAchromatic (shown c)

  , testProperty "L45.1 FAILING TWIN: the σ-fold (sigmaReflect) preserves chroma — it does NOT obfuscate" $
      forAll genChromatic $ \c ->
           chromaMagSq (shown c)         == 0                 -- obfuscation kills chroma
        && chromaMagSq (sigmaReflect c)  == chromaMagSq c     -- σ-fold preserves it
        && not (isAchromatic (sigmaReflect c))                -- so σ-fold ≠ obfuscation

    -- L45.2 — RETENTION (lossless): Ω⁻¹ ∘ Ω = id (Thm 14). Chroma is banked, never deleted.
  , testProperty "L45.2 RETENTION: deobfuscate ∘ obfuscate ≡ id" $
      forAll genOKLab $ \c -> eqLab (deobfuscate (obfuscate c)) c

    -- L45.3 — ORTHOGONALITY: shown ⊥ retained (exact: (L,0,0)·(0,a,b) = 0).
  , testProperty "L45.3 ORTHOGONALITY: ⟨S c, R c⟩ = 0" $
      forAll genOKLab $ \c -> labDot (shown c) (retained c) == 0

    -- L45.4 — PARSEVAL: ‖c‖² = ‖S c‖² + ‖R c‖² (float-tolerant: different add order).
  , testProperty "L45.4 PARSEVAL: ‖c‖² = ‖S c‖² + ‖R c‖²" $
      forAll genOKLab $ \c ->
        approx (labNormSq c) (labNormSq (shown c) + labNormSq (retained c))

    -- L45.5 — IDEMPOTENCE / NILPOTENCE of the two projectors.
  , testProperty "L45.5 IDEMPOTENCE/NILPOTENCE: S∘S=S, R∘R=R, S∘R=0, R∘S=0" $
      forAll genOKLab $ \c ->
           eqLab (shown (shown c))       (shown c)
        && eqLab (retained (retained c)) (retained c)
        && eqLab (shown (retained c))    zeroLab
        && eqLab (retained (shown c))    zeroLab

    -- L45.6 — GREY VACUITY: a grey is its own complement; nothing to obfuscate.
  , testProperty "L45.6 GREY VACUITY: a=b=0 ⇒ S c = c ∧ R c = 0" $
      forAll (choose (0, 1)) $ \l ->
        let c = OKLab l 0 0 in eqLab (shown c) c && eqLab (retained c) zeroLab

    -- L45.7 — CAPTURE-IN-COLOUR: chroma exists ⟺ there is something to reveal.
  , testProperty "L45.7 CAPTURE-IN-COLOUR: R c ≠ 0 ⟺ (a,b) ≠ 0" $
      forAll genOKLab $ \c ->
        (not (eqLab (retained c) zeroLab)) == not (isAchromatic c)

  , testProperty "L45.7 obfDepth > 0 ⟺ palette is chromatic" $
      forAll genPal $ \ps ->
        (obfDepth ps > 0) == any (not . isAchromatic) ps

    -- L45.8 — σ INHERITED: S c is σ-fixed, R c is σ-negated (a theorem ABOUT Ω).
  , testProperty "L45.8 σ INHERITED: σ(S c) = S c ∧ σ(R c) = −(R c)" $
      forAll genOKLab $ \c ->
        let OKLab _ ra rb = retained c
        in eqLab (sigmaReflect (shown c)) (shown c)
           && eqLab (sigmaReflect (retained c)) (OKLab 0 (negate ra) (negate rb))

    -- Def 46 — obfDepth is a well-formed fraction in [0,1].
  , testProperty "Def 46: obfDepth ∈ [0,1]" $
      forAll genPal $ \ps -> let d = obfDepth ps in d >= 0 && d <= 1 + 1e-12

  , testProperty "Def 46: all-grey palette has obfDepth 0" $
      forAll (resize 32 (listOf1 (choose (0, 1)))) $ \ls ->
        obfDepth [ OKLab l 0 0 | l <- ls ] == 0
  ]

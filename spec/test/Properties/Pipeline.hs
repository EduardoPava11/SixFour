{-# LANGUAGE GADTs #-}

module Properties.Pipeline (tests) where

import Test.Tasty
import Test.Tasty.QuickCheck
import Test.QuickCheck

import           Data.Proxy           (Proxy(..))
import qualified Data.Vector.Unboxed  as U

import SixFour.Spec.Bottleneck16 ( Histogram4096(..), histogramFromOKLabs )
import SixFour.Spec.Color        (OKLab(..))
import SixFour.Spec.PairTree     (sigmaReflect)
import SixFour.Spec.Pipeline
import SixFour.Spec.Quad4        (Quad4Palette(..), quad4Depth)
import SixFour.Spec.PairTree     (HaarPalette(..))
import SixFour.Spec.SigmaPairHead
  ( SigmaPairTree(..), reconstructPaired, sigmaPairDepth, sigmaPairLeaves )

-- =============================================================================
-- Generators
-- =============================================================================

genOKLab :: Gen OKLab
genOKLab = OKLab <$> choose (0, 1) <*> choose (-0.4, 0.4) <*> choose (-0.4, 0.4)

-- A short list of OKLab samples — keeps QuickCheck fast.
genOKLabList :: Gen [OKLab]
genOKLabList = resize 32 (listOf1 genOKLab)

genHistogram :: Gen Histogram4096
genHistogram = histogramFromOKLabs <$> genOKLabList

-- An achromatic-root Quad4 tree (small offsets so leaves stay in gamut).
genAchromatic :: Gen AchromaticQuad4
genAchromatic = do
  l   <- choose (0.3, 0.7)
  let rt = OKLab l 0 0
  lvls <- mapM (\lev -> vectorOf (4 ^ lev)
                  ((,) <$> genOff <*> genOff))
                [0 .. quad4Depth - 1]
  pure (AchromaticQuad4 (Quad4Palette rt lvls))
  where
    genOff = OKLab <$> choose (-0.02, 0.02)
                   <*> choose (-0.02, 0.02)
                   <*> choose (-0.02, 0.02)

-- =============================================================================
-- Tests
-- =============================================================================

tests :: TestTree
tests = testGroup "Pipeline (type-class framework for the look-NN)"
  [ -- ---------------------------------------------------------------------
    -- Stage instances exist and run end-to-end at the expected dimensions.
    -- ---------------------------------------------------------------------
    testProperty "Stage Bin16: output has 4096 bins, mass ≈ 1" $
      forAll genOKLabList $ \xs ->
        let Histogram4096 v = step @Bin16 xs
        in U.length v == 4096 && abs (U.sum v - 1.0) < 1e-9

  , testProperty "Stage SymSelect: output stays mass-1, ≥0" $
      forAll genHistogram $ \h ->
        let Histogram4096 v = step @SymSelect h
        in U.all (>= 0) v && abs (U.sum v - 1.0) < 1e-9

  , testProperty "Stage Quad4ReconAchroma: output has 256 leaves" $
      forAll genAchromatic $ \aq ->
        length (step @Quad4ReconAchroma aq) == 256

    -- ---------------------------------------------------------------------
    -- σ-equivariance laws (each instance, exact).
    -- ---------------------------------------------------------------------
  , testProperty "SigmaEquivariant Bin16: step ∘ σ_in ≡ σ_out ∘ step" $
      forAll genOKLabList (lawSigmaEquivariant @Bin16)

  , testProperty "SigmaEquivariant SymSelect: step ∘ σ_in ≡ σ_out ∘ step" $
      forAll genHistogram (lawSigmaEquivariant @SymSelect)

  , testProperty "SigmaSymmetricRange SymSelect: σ_out ∘ step ≡ step" $
      forAll genHistogram (lawSigmaSymmetricRange @SymSelect)

    -- Quad4ReconAchroma equivariance uses approximate OKLab equality.
  , testProperty "SigmaEquivariant Quad4ReconAchroma (under okClose 1e-12)" $
      forAll genAchromatic $ \aq ->
        let lhs = step @Quad4ReconAchroma (sigmaIn @Quad4ReconAchroma aq)
            rhs = sigmaOut @Quad4ReconAchroma (step @Quad4ReconAchroma aq)
        in length lhs == length rhs
           && and (zipWith (okClose 1e-12) lhs rhs)

    -- ---------------------------------------------------------------------
    -- Composition: Pipeline4Boundary derives BOTH classes mechanically.
    -- The fact that THIS TEST COMPILES is the proof: the type-class
    -- resolution found the SigmaEquivariant and SigmaSymmetricRange
    -- instances for SymSelect :> Bin16 by composition of its parts.
    -- ---------------------------------------------------------------------
  , testProperty "compositional: Pipeline4Boundary derives SigmaEquivariant" $
      once $
        let _proof :: SigmaEquivariantDict Pipeline4Boundary
            _proof = SigmaEquivariantDict
        in True

  , testProperty "compositional: Pipeline4Boundary derives SigmaSymmetricRange" $
      once $
        let _proof :: SigmaSymmetricRangeDict Pipeline4Boundary
            _proof = SigmaSymmetricRangeDict
        in True

  , -- The composition law: the chain σ_out(step(σ_in(x))) ≡ step(x) for any
    -- pipeline whose endpoints are σ-symmetric-range. Pipeline4Boundary is
    -- SymSelect ∘ Bin16, so σ_out(step(samples)) == step(samples) after the
    -- Bin16→SymSelect projection — i.e. the image lies in H_sym.
    testProperty "Pipeline4Boundary: image lies in σ-symmetric subspace" $
      forAll genOKLabList (lawSigmaSymmetricRange @Pipeline4Boundary)

    -- ---------------------------------------------------------------------
    -- option4Theorem — instantiated at the simplest possible learned middle:
    -- the achromatic-projection map (which IS algebraically σ-equivariant on
    -- the boundary types). The fact that option4Theorem typechecks at this
    -- instance is the conditional-equivariance theorem stated as code.
    -- ---------------------------------------------------------------------
  , testProperty "option4Theorem instantiates at an achromatic-projection middle" $
      once $
        let _proof :: SigmaEquivariantDict (Pipeline4 IdentityMiddle)
            _proof = option4Theorem (Proxy :: Proxy (Pipeline4 IdentityMiddle))
        in True

    -- ---------------------------------------------------------------------
    -- SigmaPairRecon — the ADOPTED L6 stage (SigmaPairHead pivot).
    -- ---------------------------------------------------------------------
  , testProperty "Stage SigmaPairRecon: output has 256 σ-pair leaves" $
      forAll genSigmaPairTree $ \t ->
        length (step @SigmaPairRecon t) == sigmaPairLeaves

  , testProperty "SigmaSymmetricRange SigmaPairRecon: σ_out ∘ step ≡ step (image is σ-fixed)" $
      forAll genSigmaPairTree (lawSigmaSymmetricRange @SigmaPairRecon)

  , testProperty "SigmaEquivariant SigmaPairRecon: step ∘ σ_in ≡ σ_out ∘ step" $
      forAll genSigmaPairTree (lawSigmaEquivariant @SigmaPairRecon)

    -- sigmaPairHeadTheorem re-instantiates option4Theorem at SigmaPairRecon:
    -- the composition is BOTH SigmaEquivariant AND SigmaSymmetricRange (the
    -- guarantee Quad4ReconAchroma could not give). THIS TEST COMPILING is the
    -- proof — NOTES 2026-05-28 open Q#2.
  , testProperty "sigmaPairHeadTheorem: Pipeline4SigmaPair is σ-equivariant AND σ-symmetric-range" $
      once $
        let (_eq, _sym) = sigmaPairHeadTheorem (Proxy :: Proxy (Pipeline4SigmaPair SigmaPairMiddle))
            _eqProof  :: SigmaEquivariantDict   (Pipeline4SigmaPair SigmaPairMiddle)
            _eqProof  = _eq
            _symProof :: SigmaSymmetricRangeDict (Pipeline4SigmaPair SigmaPairMiddle)
            _symProof = _sym
        in True
  ]

-- A well-formed depth-'sigmaPairDepth' (= 7) generator Haar palette wrapped as a
-- SigmaPairTree. Small offsets so leaves stay in gamut.
genSigmaPairTree :: Gen SigmaPairTree
genSigmaPairTree = do
  rt   <- genOKLab
  lvls <- mapM (\l -> vectorOf (2 ^ l) genOff) [0 .. sigmaPairDepth - 1]
  pure (SigmaPairTree (HaarPalette rt lvls))
  where
    genOff = OKLab <$> choose (-0.02, 0.02) <*> choose (-0.02, 0.02) <*> choose (-0.02, 0.02)

-- | A learned middle Histogram4096 → SigmaPairTree satisfying sigmaPairHeadTheorem's
-- hypotheses (σ-equivariant on the boundary types). Maps to the canonical
-- zero-offset generator tree; σ on the input acts via the bin permutation, σ on
-- the SigmaPairTree output reflects each generator coefficient.
data SigmaPairMiddle

instance Stage SigmaPairMiddle where
  type In  SigmaPairMiddle = Histogram4096
  type Out SigmaPairMiddle = SigmaPairTree
  step _ = SigmaPairTree
    (HaarPalette (OKLab 0.5 0 0)
       [ replicate (2 ^ l) (OKLab 0 0 0) | l <- [0 .. sigmaPairDepth - 1] ])

instance SigmaEquivariant SigmaPairMiddle where
  sigmaIn (Histogram4096 v) = Histogram4096 (sigmaApplyVec v)
  sigmaOut (SigmaPairTree (HaarPalette rt lvls)) =
    SigmaPairTree (HaarPalette (sigmaReflect rt)
      [ map sigmaReflect lvl | lvl <- lvls ])

-- | A trivial "identity-shaped" learned middle: takes a Histogram4096 to a
-- canonical 'AchromaticQuad4' (an achromatic-root tree with zero offsets). It
-- carries no useful information, but it IS algebraically σ-equivariant on
-- the boundary types, so it satisfies the hypotheses of 'option4Theorem' and
-- demonstrates the theorem can be instantiated.
data IdentityMiddle

instance Stage IdentityMiddle where
  type In  IdentityMiddle = Histogram4096
  type Out IdentityMiddle = AchromaticQuad4
  step _ = AchromaticQuad4
    (Quad4Palette
       (OKLab 0.5 0 0)
       [ replicate (4 ^ l) (OKLab 0 0 0, OKLab 0 0 0)
       | l <- [0 .. quad4Depth - 1] ])

-- σ on Histogram4096 input acts via the bin permutation; σ on AchromaticQuad4
-- output reflects each offset (matching Quad4ReconAchroma's sigmaIn, so the
-- composition's middle σ-actions agree). For this canonical all-zero-offset
-- tree the σ-action happens to be the identity, but the definition is the
-- generic action so the law @sigmaOut (step (sigmaIn x)) ≡ sigmaOut (step x)@
-- composes consistently in 'option4Theorem'.
instance SigmaEquivariant IdentityMiddle where
  sigmaIn (Histogram4096 v) = Histogram4096 (sigmaApplyVec v)
  sigmaOut (AchromaticQuad4 (Quad4Palette rt lvls)) =
    AchromaticQuad4 (Quad4Palette rt
      [ [ (sigmaReflect d1, sigmaReflect d2) | (d1, d2) <- lvl ] | lvl <- lvls ])

-- =============================================================================
-- Helpers (private)
-- =============================================================================

okClose :: Double -> OKLab -> OKLab -> Bool
okClose tol (OKLab l a b) (OKLab l' a' b') =
  abs (l - l') <= tol && abs (a - a') <= tol && abs (b - b') <= tol

{- |
Module      : SixFour.Spec.Obfuscation
Description : L obfuscates A+B — the lossless grey/chroma split Ω (BLEED_LOOP Def 45–47, Thm 14).

A SixFour capture is **full colour** @c = OKLab L a b@, but the deployed L head shows only
its lightness. This module formalises that as **lossless obfuscation**, not discarding: the
chroma is hidden behind the shown grey, *retained* and recoverable. (See @spec/BLEED_LOOP.md@.)

  * 'shown'    @S c = (L,0,0)@  — the grayscale view (the σ-fixed grey axis @V₊@).
  * 'retained' @R c = (0,a,b)@  — the banked chroma residual (the σ-antisymmetric plane @V₋@).
  * 'obfuscate' @Ω c = (S c, R c)@ and 'deobfuscate' @Ω⁻¹(s,r) = s + r@ with @Ω⁻¹ ∘ Ω = id@.

== The keystone correction (the one that adjudicates the architecture)

There are TWO distinct σ-splits in the wider design and they must NOT be conflated:

  * The **obfuscation** split is the AxisNet coordinate split @L ⊥ {a,b}@ — 'shown' is exactly
    'SixFour.Spec.AxisNet.projectAxis' @AxisL@. Its orthogonality is the geometry of OKLab
    (the grey L axis ⊥ the chroma plane), exact and σ-INDEPENDENT.
  * The **σ-fold** split is 'SixFour.Spec.SigmaDecomp.symPart'/'asymPart' on the 4096-bin
    histogram — it permutes bins by chroma PARITY and does NOT zero chroma. Its role here is
    only the scene-affordance *ceiling* ('SixFour.Spec.SigmaDecomp.sigmaSymFraction'), never
    the obfuscation operator.

The discriminating fact (law @lawGrayscaleTruth@, the first to gate): 'shown' zeroes chroma
(@a = b = 0@), whereas the σ kernel 'SixFour.Spec.PairTree.sigmaReflect' (the @σ@ inside
@symPart = ½(H + σH)@) PRESERVES chroma magnitude. Using @symPart@ as the obfuscation operator
would make "show L, hide a,b" false.

Laws live in @Properties.Obfuscation@.
-}
-- COMPARTMENT: MLX-MODEL | tag:MacTag
module SixFour.Spec.Obfuscation
  ( -- * The obfuscation operator Ω (Def 45)
    shown
  , retained
  , obfuscate
  , deobfuscate
    -- * Obfuscation depth (Def 46)
  , obfDepth
    -- * Chroma helpers
  , chromaMagSq
  , isAchromatic
    -- * OKLab as a Euclidean vector space (for the laws)
  , labAdd
  , labSub
  , labDot
  , labNormSq
  , zeroLab
  ) where

import SixFour.Spec.Color   (OKLab(..))
import SixFour.Spec.AxisNet (ColorAxis(..), projectAxis)

-- =============================================================================
-- OKLab as a Euclidean vector space
-- =============================================================================

-- | The OKLab origin @(0,0,0)@.
zeroLab :: OKLab
zeroLab = OKLab 0 0 0

-- | Componentwise sum of two OKLab triples.
labAdd :: OKLab -> OKLab -> OKLab
labAdd (OKLab l1 a1 b1) (OKLab l2 a2 b2) = OKLab (l1 + l2) (a1 + a2) (b1 + b2)

-- | Componentwise difference of two OKLab triples.
labSub :: OKLab -> OKLab -> OKLab
labSub (OKLab l1 a1 b1) (OKLab l2 a2 b2) = OKLab (l1 - l2) (a1 - a2) (b1 - b2)

-- | Euclidean inner product on OKLab.
labDot :: OKLab -> OKLab -> Double
labDot (OKLab l1 a1 b1) (OKLab l2 a2 b2) = l1 * l2 + a1 * a2 + b1 * b2

-- | Squared Euclidean norm @‖c‖²@.
labNormSq :: OKLab -> Double
labNormSq c = labDot c c

-- | The chroma energy @a² + b²@ of a colour.
chromaMagSq :: OKLab -> Double
chromaMagSq (OKLab _ a b) = a * a + b * b

-- | Is the colour on the grey axis (@a = b = 0@)?
isAchromatic :: OKLab -> Bool
isAchromatic (OKLab _ a b) = a == 0 && b == 0

-- =============================================================================
-- The obfuscation operator Ω (Def 45)
-- =============================================================================

-- | @S c = (L,0,0)@ — the SHOWN grayscale view. This is exactly
-- 'SixFour.Spec.AxisNet.projectAxis' @AxisL@ (the tie is deliberate: the obfuscation
-- operator IS the AxisL projector, NOT the σ-fold).
shown :: OKLab -> OKLab
shown = projectAxis AxisL

-- | @R c = c − S c = (0,a,b)@ — the RETAINED chroma residual (the σ-antisymmetric
-- plane @V₋@). Banked, never deleted.
retained :: OKLab -> OKLab
retained c = labSub c (shown c)

-- | @Ω c = (S c, R c)@ — split a colour into its shown grey and retained chroma.
obfuscate :: OKLab -> (OKLab, OKLab)
obfuscate c = (shown c, retained c)

-- | @Ω⁻¹(s,r) = s + r@ — recombine. 'deobfuscate' . 'obfuscate' is the identity
-- (Thm 14, RETENTION): the obfuscation is lossless.
deobfuscate :: (OKLab, OKLab) -> OKLab
deobfuscate (s, r) = labAdd s r

-- =============================================================================
-- Obfuscation depth (Def 46)
-- =============================================================================

-- | @obfDepth P = (Σ‖R cᵢ‖²) / (Σ‖cᵢ‖²) ∈ [0,1]@ — the fraction of palette energy
-- currently HIDDEN behind the grey view. Measures chroma (the @V₋@ analogue), NOT
-- σ-parity. An empty or all-black palette (zero total energy) has depth 0.
obfDepth :: [OKLab] -> Double
obfDepth ps
  | total <= 1e-300 = 0
  | otherwise       = hidden / total
  where
    hidden = sum [ labNormSq (retained c) | c <- ps ]
    total  = sum [ labNormSq c            | c <- ps ]

{- |
Module      : SixFour.Spec.LeafOverride
Description : User δ-overrides on the integer σ-pair genome — generator-space, σ-locked, EXACT.

The PALETTE creation control (@docs/SIXFOUR-GLOBAL-PALETTE-CONTROL.md@, SIXFOUR-WIDGETS
Family 2) lets the user nudge the global palette by an OKLab colour delta. A naive
per-LEAF delta is impossible for the 2⁸ σ-pair genome:
'SixFour.Spec.SigmaPairFixed.analyzePairedFixed' discards the odd leaves and regenerates
them as @σ(cᵢ)@, so a leaf-space nudge on an odd leaf is thrown away (the critique that
killed the "drag any swatch" design). The honest edit lives in GENERATOR space: nudge the
generator @cᵢ@ by @δ@, and the σ-partner becomes @σ(cᵢ + δ)@ /by construction/. The
σ-symmetry is therefore preserved for FREE — the user gets @(ΔL, Δa, Δb)@ on @cᵢ@ and the
mirror gets @(ΔL, −Δa, −Δb)@, exactly, with no way to break the genome.

This is the integer (Q16) override the shipped GIFB path uses. It is a pure post-step on
the reconstructed generators — it never touches the reversible integer Haar of
'SixFour.Spec.PairTreeFixed' — so it is EXACT (integer equality, no tolerance) and adds
zero error. The Swift twin is @BranchedPalette.projectQ16(_, branching:, override:)@,
gated byte-exact against these laws.

Laws (QuickCheck'd in @Properties.LeafOverride@, EXACT — no ε):
  * the all-zero override is a no-op — byte-identical to the un-overridden genome
    ('lawSigmaOverrideIdentityNoOp');
  * ANY override keeps the palette σ-fixed — @sigmaSwapAndReflectI@ is the identity on it
    ('lawSigmaOverridePreservesSymmetry'); the symmetry cannot be broken;
  * the override adds EXACTLY to the generators — the even leaves equal @generators + δ@
    ('lawSigmaOverrideAddsToGenerators');
  * an override on generator @i@ touches ONLY leaves @2i@ and @2i+1@ — every other leaf is
    byte-identical (brush-scoped editing, 'lawSigmaOverrideScopedToGenerator').
-}
module SixFour.Spec.LeafOverride
  ( -- * The generator-space override
    SigmaOverride
  , zeroSigmaOverride
  , applySigmaOverride
    -- * Laws (QuickCheck'd in Properties.LeafOverride)
  , lawSigmaOverrideIdentityNoOp
  , lawSigmaOverridePreservesSymmetry
  , lawSigmaOverrideAddsToGenerators
  , lawSigmaOverrideScopedToGenerator
  , lawSigmaOverrideOddLeafCarriesSigmaOfNudged
  , lawSigmaOverrideAdditive
  , lawSigmaOverrideIgnoresTailPastGenerators
  , lawSigmaOverrideGeneratorsIndependent
  ) where

import SixFour.Spec.PairTreeFixed  (OKLabI, HaarPaletteI, reconstructFixed, wellFormedI)
import SixFour.Spec.SigmaPairFixed (sigmaReflectI, sigmaSwapAndReflectI, reconstructPairedFixed)

-- | A generator-space override: the @i@-th entry is the δ added to generator @cᵢ@. A list
-- shorter than the generator count is zero-padded (the missing tail is no nudge), so the
-- empty list is the identity.
type SigmaOverride = [OKLabI]

-- | The no-op override (no entries ⇒ every generator unchanged).
zeroSigmaOverride :: SigmaOverride
zeroSigmaOverride = []

-- | Component-wise integer add of two Q16 OKLab triples (exact).
addI :: OKLabI -> OKLabI -> OKLabI
addI (l, a, b) (l', a', b') = (l + l', a + a', b + b')

-- | Even-indexed elements (the generators @cᵢ@ live at the even leaf positions).
evensOf :: [a] -> [a]
evensOf (x : _ : rest) = x : evensOf rest
evensOf xs             = xs

-- | Reconstruct the σ-pair palette @[g₀, σ(g₀), g₁, σ(g₁), …]@ with a generator-space
-- override, where @gᵢ = cᵢ + δᵢ@. The reversible Haar produces the generators @cᵢ@; the
-- override is a pure exact-integer post-step (add then mirror). δ shorter than the
-- generator count is zero-padded.
applySigmaOverride :: SigmaOverride -> HaarPaletteI -> [OKLabI]
applySigmaOverride deltas hp =
  concatMap (\g -> [g, sigmaReflectI g])
            (zipWith addI (reconstructFixed hp) (deltas ++ repeat (0, 0, 0)))

-- ---------------------------------------------------------------------------
-- Laws
-- ---------------------------------------------------------------------------

-- | The all-zero override is the identity: byte-identical to 'reconstructPairedFixed'.
lawSigmaOverrideIdentityNoOp :: HaarPaletteI -> Bool
lawSigmaOverrideIdentityNoOp hp =
  not (wellFormedI hp) ||
  applySigmaOverride zeroSigmaOverride hp == reconstructPairedFixed hp

-- | ANY override keeps the palette σ-fixed: 'sigmaSwapAndReflectI' is the identity on it.
-- The σ-symmetry cannot be broken — the partner is @σ(generator)@ by construction.
lawSigmaOverridePreservesSymmetry :: SigmaOverride -> HaarPaletteI -> Bool
lawSigmaOverridePreservesSymmetry o hp =
  not (wellFormedI hp) ||
  let pal = applySigmaOverride o hp
  in sigmaSwapAndReflectI pal == pal

-- | The override adds EXACTLY to the generators: the even leaves equal @generators + δ@
-- (zero-padded). This pins that the user's δ reaches the genome unattenuated.
lawSigmaOverrideAddsToGenerators :: SigmaOverride -> HaarPaletteI -> Bool
lawSigmaOverrideAddsToGenerators o hp =
  not (wellFormedI hp) ||
  evensOf (applySigmaOverride o hp)
    == zipWith addI (reconstructFixed hp) (o ++ repeat (0, 0, 0))

-- | An override on a SINGLE generator @i@ leaves every OTHER leaf byte-identical to the
-- un-overridden genome — only leaves @2i@ and @2i+1@ may change. Brush-scoped editing.
lawSigmaOverrideScopedToGenerator :: HaarPaletteI -> Int -> OKLabI -> Bool
lawSigmaOverrideScopedToGenerator hp i d =
  not (wellFormedI hp) ||
  let gens = reconstructFixed hp
      n    = length gens
  in n == 0 ||
     let j    = abs i `mod` n
         o    = replicate j (0, 0, 0) ++ [d]
         base = reconstructPairedFixed hp
         pal  = applySigmaOverride o hp
     in and [ pal !! k == base !! k
            | k <- [0 .. 2 * n - 1], k /= 2 * j, k /= 2 * j + 1 ]

-- | Every ODD leaf @2i+1@ is the σ-reflection of its even predecessor @2i@ (= the
-- NUDGED generator @cᵢ + δᵢ@), for ANY override — the genome's σ-symmetry is locked to
-- the post-override generator, not the original. This pins what the Swift twin's
-- @out[2i+1] = σ(g)@ where @g = cᵢ + δᵢ@ must reproduce.
lawSigmaOverrideOddLeafCarriesSigmaOfNudged :: SigmaOverride -> HaarPaletteI -> Bool
lawSigmaOverrideOddLeafCarriesSigmaOfNudged o hp =
  not (wellFormedI hp) ||
  let pal = applySigmaOverride o hp
      n   = length pal `div` 2
  in and [ pal !! (2*k+1) == sigmaReflectI (pal !! (2*k)) | k <- [0 .. n-1] ]

-- | δ is purely ADDITIVE in generator space: applying the componentwise sum of two
-- overrides equals applying one then re-feeding nothing for the other — i.e.
-- @applySigmaOverride (o₁ ⊕ o₂) hp@ adds @(δ₁ + δ₂)@ to every generator. This is the
-- stateless compositionality the live UI relies on (independent ΔL/Δa/Δb edits and
-- re-brushes superpose without compounding or attenuation). Pinned as a regression law:
-- a future refactor that re-fed the overridden palette through @analyzePairedFixed@
-- would break additivity (it re-Haars the evens) and this law would catch it.
lawSigmaOverrideAdditive :: SigmaOverride -> SigmaOverride -> HaarPaletteI -> Bool
lawSigmaOverrideAdditive o1 o2 hp =
  not (wellFormedI hp) ||
  let summed = zipLongest addI o1 o2
  in applySigmaOverride summed hp
       == evensInterleave (zipWith addI
                            (zipWith addI (reconstructFixed hp) (o1 ++ repeat (0,0,0)))
                            (o2 ++ repeat (0,0,0)))
  where
    evensInterleave = concatMap (\g -> [g, sigmaReflectI g])
    -- componentwise sum of two overrides, zero-padding the shorter to the longer
    zipLongest f (x:xs) (y:ys) = f x y : zipLongest f xs ys
    zipLongest _ xs     []     = xs
    zipLongest _ []     ys     = ys

-- | An override is IGNORED beyond the generator count: appending arbitrary extra δ
-- entries past the @n@ generators is byte-identical to truncating the override to @n@.
-- Pins the "longer-override-ignores-tail" contract (Swift guards @idx < override.count@
-- over @ci@; Haskell @zipWith@ truncates against @reconstructFixed@).
lawSigmaOverrideIgnoresTailPastGenerators :: SigmaOverride -> SigmaOverride -> HaarPaletteI -> Bool
lawSigmaOverrideIgnoresTailPastGenerators o tailExtra hp =
  not (wellFormedI hp) ||
  let n        = length (reconstructFixed hp)
      truncated = take n (o ++ repeat (0,0,0))
  in applySigmaOverride (truncated ++ tailExtra) hp
       == applySigmaOverride truncated hp

-- | DIFFERENT generators get INDEPENDENT deltas — no cross-talk. Overriding generator
-- @i@ with @dᵢ@ and generator @j@ (≠ i) with @dⱼ@ in the SAME call yields, at pair @i@,
-- exactly what overriding @i@ ALONE yields, and at pair @j@ exactly what overriding @j@
-- alone yields. A stale-index bug that let @override[i]@ bleed into pair @j@ would fail
-- here (the single-generator scoped law cannot catch superposition cross-talk).
lawSigmaOverrideGeneratorsIndependent :: HaarPaletteI -> Int -> Int -> OKLabI -> OKLabI -> Bool
lawSigmaOverrideGeneratorsIndependent hp i j di dj =
  not (wellFormedI hp) ||
  let n = length (reconstructFixed hp)
  in n < 2 ||
     let a    = abs i `mod` n
         b0   = abs j `mod` n
         b    = if b0 == a then (a + 1) `mod` n else b0   -- force i ≠ j
         setAt k d = replicate k (0,0,0) ++ [d]
         oi   = setAt a di
         oj   = setAt b dj
         oBoth = [ if k == a then di else if k == b then dj else (0,0,0) | k <- [0 .. n-1] ]
         both = applySigmaOverride oBoth hp
         soloI = applySigmaOverride oi hp
         soloJ = applySigmaOverride oj hp
     in both !! (2*a)   == soloI !! (2*a)
     && both !! (2*a+1) == soloI !! (2*a+1)
     && both !! (2*b)   == soloJ !! (2*b)
     && both !! (2*b+1) == soloJ !! (2*b+1)

{- |
Module      : SixFour.Spec.SigmaPairFixed
Description : The OWNED integer (Q16) σ-pair genome — EXACTLY reversible.

The σ-pair decoder genome of 'SixFour.Spec.SigmaPairHead' is float (it rides the
@Double@ 'SixFour.Spec.PairTree'). Per the integer-quantization research
(Jacob et al. 2018 dyadic fixed-point; float NN inference is non-associative and
NOT cross-device byte-exact), a STRUCTURED linear transform like the σ-pair genome
integerizes EXACTLY via a lifting scheme — no quantization error. This module is
that integer twin: it reuses the reversible integer Haar of
'SixFour.Spec.PairTreeFixed' (the S-transform) for the 128 @c_i@ generators and an
exact integer σ-reflection for the mirror, so:

  * @analyzePairedFixed . reconstructPairedFixed = id@ is EXACT (integer equality,
    NO tolerance) — 'lawReconstructAnalyzePairedFixedRoundTrip';
  * @reconstructPairedFixed . analyzePairedFixed@ PROJECTS any palette onto the
    σ-symmetric subspace, exactly ('lawAnalyzePairedFixedProjectsSigmaFixed').

This is the genome the 2⁸ control selects; making it exact-integer keeps the GIFB
global colour table byte-exact cross-device for the σ-pair branching (the FLAT 16²
branching is already byte-exact; this closes 2⁸). The 4-ary Quad4 genome gets the
same treatment via a nested integer lift (future 'Spec.Quad4Fixed').

The σ-pair palette is @[c_0, σ(c_0), c_1, σ(c_1), …]@ with @σ(L,a,b) = (L,−a,−b)@,
the exact integer negation of the chroma channels.
-}
-- COMPARTMENT: ZIG-FLOOR | tag:DeviceTag
module SixFour.Spec.SigmaPairFixed
  ( sigmaReflectI
  , sigmaSwapAndReflectI
  , sigmaPartner
  , analyzePairedFixed
  , reconstructPairedFixed
    -- * Laws (QuickCheck'd in Properties.SigmaPairFixed)
  , lawReconstructAnalyzePairedFixedRoundTrip
  , lawAnalyzePairedFixedProjectsSigmaFixed
  , lawSigmaReflectInvolutionI
  , lawSigmaPartnerIsReflection
  ) where

import Data.Bits (xor)

import SixFour.Spec.PairTreeFixed
  ( OKLabI, HaarPaletteI, wellFormedI, analyzeFixed, reconstructFixed )

-- | Exact integer σ-reflection @σ(L,a,b) = (L,−a,−b)@ (negation is exact in 'Int').
sigmaReflectI :: OKLabI -> OKLabI
sigmaReflectI (l, a, b) = (l, negate a, negate b)

-- | Pointwise σ then swap adjacent pairs — the identity on a σ-pair-interleaved
-- palette (the integer mirror of 'SixFour.Spec.SigmaPairHead.sigmaSwapAndReflect').
sigmaSwapAndReflectI :: [OKLabI] -> [OKLabI]
sigmaSwapAndReflectI = swapPairs . map sigmaReflectI
  where
    swapPairs (x : y : rest) = y : x : swapPairs rest
    swapPairs xs             = xs

-- | Inverse: a depth-@D@ integer Haar tree of @c_i@ generators → the σ-pair palette
-- @[c_0, σ(c_0), c_1, σ(c_1), …]@. Exact integers throughout.
reconstructPairedFixed :: HaarPaletteI -> [OKLabI]
reconstructPairedFixed hp = concatMap (\c -> [c, sigmaReflectI c]) (reconstructFixed hp)

-- | Forward: the 128 @c_i@ are the even-indexed leaves; integer-Haar-analyse them.
-- Exact inverse of 'reconstructPairedFixed' on σ-pair palettes; the exact integer
-- PROJECTION onto the σ-pair subspace on arbitrary input (odd leaves discarded,
-- regenerated as @σ(c_i)@).
analyzePairedFixed :: [OKLabI] -> HaarPaletteI
analyzePairedFixed = analyzeFixed . evens
  where
    evens (x : _ : rest) = x : evens rest
    evens [x]            = [x]
    evens []             = []

-- ---------------------------------------------------------------------------
-- Laws
-- ---------------------------------------------------------------------------

-- | EXACT round-trip (integer equality, NO tolerance): re-analysing the σ-pair
-- palette of a well-formed tree recovers that tree exactly. (The float twin needed
-- @haarClose ε@; the integer lift needs nothing.)
lawReconstructAnalyzePairedFixedRoundTrip :: HaarPaletteI -> Bool
lawReconstructAnalyzePairedFixedRoundTrip t =
  not (wellFormedI t) || analyzePairedFixed (reconstructPairedFixed t) == t

-- | For ANY even-length integer palette, @reconstructPairedFixed (analyzePairedFixed
-- leaves)@ is EXACTLY σ-fixed: @sigmaSwapAndReflectI@ is the identity on it. The
-- forward analyser projects onto the σ-pair genome (exact, no tolerance).
lawAnalyzePairedFixedProjectsSigmaFixed :: [OKLabI] -> Bool
lawAnalyzePairedFixedProjectsSigmaFixed leaves =
  odd (length leaves) ||
  let pal = reconstructPairedFixed (analyzePairedFixed leaves)
  in sigmaSwapAndReflectI pal == pal

-- | @σ@ is an involution on the integers: @σ(σ x) = x@ (exact).
lawSigmaReflectInvolutionI :: OKLabI -> Bool
lawSigmaReflectInvolutionI x = sigmaReflectI (sigmaReflectI x) == x

-- | The σ-pair PARTNER of a leaf index: @k ^ 1@ swaps each even leaf @2i@ with its
-- σ-mirror @2i+1@ (and back). This is the cross-view brush rule for the 2⁸ genome —
-- brushing a colour also lights its σ-partner. Pure index op (involutive).
sigmaPartner :: Int -> Int
sigmaPartner = (`xor` 1)

-- | On a σ-pair palette, the leaf at 'sigmaPartner k' IS the σ-reflection of the
-- leaf at @k@ — so highlighting the partner highlights the exact σ-mirror colour.
lawSigmaPartnerIsReflection :: HaarPaletteI -> Int -> Bool
lawSigmaPartnerIsReflection t k =
  not (wellFormedI t) ||
  let pal = reconstructPairedFixed t
      n   = length pal
  in n == 0 ||
     let i = (abs k) `mod` n
     in pal !! sigmaPartner i == sigmaReflectI (pal !! i)

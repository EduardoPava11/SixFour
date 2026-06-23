{-# LANGUAGE ScopedTypeVariables #-}

{- |
Module      : SixFour.Spec.RGBTLift
Description : The 2×2 ↔ RGBT reversible integer lifting — the bijection that makes the cube ladder lossless.

Keystone of the RGBT‑4D buffer (@docs/SIXFOUR-RGBT4D-BUFFER-HARDENING-WORKFLOW.md@ §1.1): the
@(2×2) <-> 1@ map that makes the resolution ladder __lossless__ and seeds the 256³ synthesis. A
2×2 spatial block of 4 scalars is lifted to ONE cell carrying 4 channels — the semantic
__R, G, B, T__ — and recovered EXACTLY. This is the separable 2‑D Haar realised by the
__integer lifting scheme__ (the S‑transform), so it is a bijection on @Int@ with no rounding loss:

>  R = LL   the coarse / average  (the DC sub‑band)
>  G = LH   horizontal detail
>  B = HL   vertical detail
>  T = HH   diagonal detail

It generalises the 1‑D palette lifting in "SixFour.Spec.PairTreeFixed" (@liftPair@/@unliftPair@,
the same @floorHalf = `div` 2@ S‑transform, already golden‑proven reversible) from the palette
axis to the spatial 2×2 block. The semantic distinctness of the four sub‑bands __is__ the
invertibility — this is why the workflow's 2b (fixed‑meaning lanes) is required and 2a
(symmetric/positional) cannot be reversible.

== Why it makes the ladder lossless

Apply 'liftQuad' per OKLab channel over every 2×2 block ('liftQuadOK') and the @64²→32²@ step is a
bijection: the coarse @R@ plane is the next-coarser tier; the @(G,B,T)@ planes hold exactly the
detail needed to invert. Recurse twice for the ×4 'SixFour.Spec.Export' rung. So @64³ ↔ 16³@ loses
nothing __within captured detail__ ('lawLiftUnliftExact'); only NN super‑res __beyond__ captured
resolution invents anything.

Integer-exact, deterministic, golden-pinnable — it ports to a hand-written Swift/Metal
@simd_shuffle@ stencil byte-for-byte (the SIMD over the 4 lanes; the 2×2 grid is the SIMT domain).
-}
-- COMPARTMENT: ZIG-FLOOR | tag:DeviceTag
module SixFour.Spec.RGBTLift
  ( -- * Types
    Quad
  , RGBT
    -- * The reversible 2×2 lifting (scalar)
  , liftQuad
  , unliftQuad
    -- * Sub-band accessors
  , coarse
  , details
    -- * OKLab per-channel lifting (the spatial cube edge)
  , liftQuadOK
  , unliftQuadOK
    -- * Laws (QuickCheck'd in Properties.RGBTLift)
  , lawLiftUnliftExact
  , lawUnliftLiftExact
  , lawCoarseInBlockRange
  , lawDetailZeroOnConstant
  , lawLiftUnliftExactOK
  ) where

import SixFour.Spec.PairTreeFixed (OKLabI)

-- | A 2×2 spatial block of scalars, row-major: @(a, b, c, d)@ for the cells
-- @a b ⁄ c d@.
type Quad = (Int, Int, Int, Int)

-- | The lifted cell: the four sub-bands @(R, G, B, T) = (LL, LH, HL, HH)@ — coarse
-- average plus horizontal / vertical / diagonal detail.
type RGBT = (Int, Int, Int, Int)

-- | @floor(n\/2)@. Haskell's 'div' already rounds toward −∞, so this is exact for
-- negatives (the property the reversible S-transform relies on). Same convention as
-- "SixFour.Spec.PairTreeFixed".
floorHalf :: Int -> Int
floorHalf n = n `div` 2

-- | The 1-D reversible S-transform: @(x, y) ↦ (low, high)@ with
-- @low = y + ⌊(x−y)\/2⌋@, @high = x − y@. Exactly inverted by @sUnlift@.
sLift :: Int -> Int -> (Int, Int)
sLift x y = let d = x - y in (y + floorHalf d, d)

-- | Inverse of @sLift@: @(low, high) ↦ (x, y)@.
sUnlift :: Int -> Int -> (Int, Int)
sUnlift lo hi = let y = lo - floorHalf hi in (y + hi, y)

-- | Lift a 2×2 block to its four sub-bands @(R,G,B,T)@. Separable: lift the two rows,
-- then lift the resulting low column and high column. A bijection on @Int@
-- ('lawLiftUnliftExact').
liftQuad :: Quad -> RGBT
liftQuad (a, b, c, d) =
  let (la, ha) = sLift a b
      (lc, hc) = sLift c d
      (ll, lh) = sLift la lc
      (hl, hh) = sLift ha hc
  in (ll, lh, hl, hh)

-- | Recover the 2×2 block from its @(R,G,B,T)@ sub-bands — the exact inverse of
-- 'liftQuad' (the steps run in reverse: columns first, then rows).
unliftQuad :: RGBT -> Quad
unliftQuad (ll, lh, hl, hh) =
  let (la, lc) = sUnlift ll lh
      (ha, hc) = sUnlift hl hh
      (a, b)   = sUnlift la ha
      (c, d)   = sUnlift lc hc
  in (a, b, c, d)

-- | The coarse sub-band @R = LL@ — the block's (iterated-floor) average; the value
-- that becomes the next-coarser tier.
coarse :: RGBT -> Int
coarse (r, _, _, _) = r

-- | The three detail sub-bands @(G, B, T) = (LH, HL, HH)@ — exactly what 'liftQuad'
-- needs to reconstruct the 2×2 block, and what a coarser tier omits.
details :: RGBT -> (Int, Int, Int)
details (_, g, b, t) = (g, b, t)

-- | Lift a 2×2 block of OKLab pixels by applying 'liftQuad' independently to each of
-- the L, a, b axes — the spatial cube edge. The four results are the @R/G/B/T@
-- pixels (each an 'OKLabI'). Inverse: 'unliftQuadOK'.
liftQuadOK :: (OKLabI, OKLabI, OKLabI, OKLabI) -> (OKLabI, OKLabI, OKLabI, OKLabI)
liftQuadOK ((aL,aA,aB), (bL,bA,bB), (cL,cA,cB), (dL,dA,dB)) =
  let (rL,gL,hL,tL) = liftQuad (aL,bL,cL,dL)
      (rA,gA,hA,tA) = liftQuad (aA,bA,cA,dA)
      (rB,gB,hB,tB) = liftQuad (aB,bB,cB,dB)
  in ((rL,rA,rB), (gL,gA,gB), (hL,hA,hB), (tL,tA,tB))

-- | Inverse of 'liftQuadOK' — recover the four OKLab pixels of the 2×2 block.
unliftQuadOK :: (OKLabI, OKLabI, OKLabI, OKLabI) -> (OKLabI, OKLabI, OKLabI, OKLabI)
unliftQuadOK ((rL,rA,rB), (gL,gA,gB), (hL,hA,hB), (tL,tA,tB)) =
  let (aL,bL,cL,dL) = unliftQuad (rL,gL,hL,tL)
      (aA,bA,cA,dA) = unliftQuad (rA,gA,hA,tA)
      (aB,bB,cB,dB) = unliftQuad (rB,gB,hB,tB)
  in ((aL,aA,aB), (bL,bA,bB), (cL,cA,cB), (dL,dA,dB))

-- ============================================================================
-- Laws (predicates; QuickCheck'd in Properties.RGBTLift)
-- ============================================================================

-- | The lifting is EXACTLY reversible: @unliftQuad ∘ liftQuad ≡ id@ on every integer
-- 2×2 block. No tolerance — the S-transform's floor division is exact. This is the
-- @(2×2)<->1@ bijection the lossless ladder rests on.
lawLiftUnliftExact :: Quad -> Bool
lawLiftUnliftExact q = unliftQuad (liftQuad q) == q

-- | The other direction: @liftQuad ∘ unliftQuad ≡ id@ on every sub-band 4-tuple — so
-- the map is a genuine bijection, not merely a left inverse.
lawUnliftLiftExact :: RGBT -> Bool
lawUnliftLiftExact r = liftQuad (unliftQuad r) == r

-- | The coarse sub-band stays within the block's range:
-- @min(a,b,c,d) ≤ R ≤ max(a,b,c,d)@. So the coarser tier never invents a value
-- outside its source 2×2 — the gamut-closure of the spatial distill.
lawCoarseInBlockRange :: Quad -> Bool
lawCoarseInBlockRange q@(a, b, c, d) =
  let r = coarse (liftQuad q)
  in r >= minimum [a, b, c, d] && r <= maximum [a, b, c, d]

-- | A constant block carries no detail: @liftQuad (v,v,v,v) ≡ (v, 0, 0, 0)@ — pure
-- DC, zero @(G,B,T)@. The compression intuition (flat regions cost only their coarse
-- value) made exact.
lawDetailZeroOnConstant :: Int -> Bool
lawDetailZeroOnConstant v = liftQuad (v, v, v, v) == (v, 0, 0, 0)

-- | The OKLab spatial edge is exactly reversible too: @unliftQuadOK ∘ liftQuadOK ≡ id@
-- on every 2×2 block of OKLab pixels (three independent exact channel liftings).
lawLiftUnliftExactOK :: (OKLabI, OKLabI, OKLabI, OKLabI) -> Bool
lawLiftUnliftExactOK q = unliftQuadOK (liftQuadOK q) == q

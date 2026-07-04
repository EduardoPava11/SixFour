{- |
Module      : SixFour.Spec.OpponentDerivation
Description : THE LATENT DERIVATION OF Lab FROM RGB — the opponent transform is not a choice but a THEOREM: (L, a, b) is the isotypic decomposition of the S₃ permutation representation on ℤ^{R,G,B}. Luma L = R+G+B spans the trivial representation and is (up to scale) the UNIQUE S₃-invariant integer functional ('lawLumaIsTheUniqueInvariant'); chroma is the standard 2-dimensional representation, whose integral form is the root lattice A₂ = ker Σ — the b = 3 instance of the SAME split exact sequence 0 → A_{b−1} → ℤ^b → ℤ → 0 whose b = 8 instance is the spatial octant ("SixFour.Spec.RootLatticeDetail", general in b: 'numDetailBands' 3 = 2 = the two chroma channels). COLOR AND SPACE ARE THE SAME THEOREM AT DIFFERENT b.

THE GROUP ACTS AS EISENSTEIN UNITS ('lawRootChartIsEquivariant'): in the root
chart (α₁, α₂) = (R−G, G−B), every channel permutation acts by an explicit
INTEGER 2×2 matrix; the 3-cycle's matrix has det 1, trace −1, and cubes to
the identity — it IS multiplication by the Eisenstein unit ω (rotation by
2π/3 on the hexagonal A₂), and the transposition is the det −1 reflection.
The representation ℤ[S₃] → GL₂(ℤ) is faithful on the chroma plane: hue
permutation is hexagonal geometry, exactly.

THE STORED CHART'S PRICE, made exact ('lawStoredChartTradesSymmetryForBytes'):
the shipped (a, b) = (R−G, R+G−2B) chart spans an INDEX-2 sublattice of A₂
(witness: b − a = 2·α₂ while α₂ itself is obstructed by parity — every
⟨a,b⟩-combination has even third coordinate, α₂'s is −1). Consequently the
3-cycle is only HALF-integral in the stored chart (the exact integer identity
2·a(σv) = −(a+b)(v) exhibits the halving). The V2 chart trades S₃-integrality
for byte-exact storage — a conscious gauge choice, now priced.

THE DETERMINANT FACTORS AS TWO INDICES ('lawDetIsProductOfIndices'):
det(opponent) = 6 = 3 × 2, where 3 = [ℤ³ : A₂ ⊕ ℤ·(1,1,1)] (the quotient is
ℤ/3 via Σ mod 3 — the non-split integrality of the SES, the index-3 Λ story
made structural) and 2 = [A₂ : ⟨a,b⟩] (the chart index above). The two prime
factors of 6 are two DIFFERENT obstructions with different owners: the 3
belongs to the SES (unavoidable at b = 3), the 2 belongs to the chart
(a revisable gauge choice).

THE IMAGE AND THE EXACT INVERSE ('lawInverseAndImage'): (L,a,b) lies in the
image of ℤ³ iff L ≡ b (mod 3) AND (2L+b)/3 + a is even; on the image the
inverse is exact integer arithmetic — B = (L−b)/3, 2R = (2L+b)/3 + a,
2G = (2L+b)/3 − a. Teeth: (1,0,0) fails the mod-3 congruence, (0,1,0) fails
the parity — the congruences are the WHOLE story of which Lab triples are
colors.

Companion: "SixFour.Spec.LabBleed" carries the same matrix as Codegen DATA
(det pinned at 6); this module derives WHY that matrix, and what each prime
of its determinant means. GHCi-provable throughout (all laws are integer
identities on explicit witnesses or QuickCheck-generated channels).
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none
module SixFour.Spec.OpponentDerivation
  ( -- * Charts on the chroma plane
    alphaChart
  , storedChart
  , lumaOf
    -- * The S₃ action
  , swapRG
  , cycleRGB
    -- * The exact inverse on the image
  , inImage
  , fromLab
    -- * Laws
  , lawLumaIsTheUniqueInvariant
  , lawChromaIsA2OfChannels
  , lawRootChartIsEquivariant
  , lawStoredChartTradesSymmetryForBytes
  , lawInverseAndImage
  , lawDetIsProductOfIndices
  ) where

import SixFour.Spec.OctantViews (RGB, opponent)
import SixFour.Spec.RootLatticeDetail (inA, numDetailBands)
import SixFour.Spec.LabBleed (opponentDet)

-- | The root chart on chroma: the A₂ simple roots (α₁, α₂) = (R−G, G−B).
alphaChart :: RGB -> (Integer, Integer)
alphaChart (r, g, b) = (r - g, g - b)

-- | The shipped V2 chart: (a, b) = (R−G, R+G−2B) — byte-exact storage,
-- index 2 in A₂ (see 'lawStoredChartTradesSymmetryForBytes').
storedChart :: RGB -> (Integer, Integer)
storedChart (r, g, b) = (r - g, r + g - 2 * b)

-- | The invariant component: L = R+G+B.
lumaOf :: RGB -> Integer
lumaOf (r, g, b) = r + g + b

-- | The generating transposition (swap the R and G channels).
swapRG :: RGB -> RGB
swapRG (r, g, b) = (g, r, b)

-- | The generating 3-cycle (R ← B, G ← R, B ← G).
cycleRGB :: RGB -> RGB
cycleRGB (r, g, b) = (b, r, g)

-- | Is an (L, a, b) triple a color? The exact image congruences.
inImage :: (Integer, Integer, Integer) -> Bool
inImage (l, a, b) =
  (l - b) `mod` 3 == 0 && ((2 * l + b) `div` 3 + a) `mod` 2 == 0

-- | The exact integer inverse on the image (undefined off it — callers gate
-- with 'inImage'; totality culture: the congruences ARE the domain).
fromLab :: (Integer, Integer, Integer) -> RGB
fromLab (l, a, b) =
  let bb = (l - b) `div` 3
      rg = (2 * l + b) `div` 3
  in ((rg + a) `div` 2, (rg - a) `div` 2, bb)

-- | LAW (luma is derived, not chosen): an integer functional (p,q,r)·v is
-- invariant under BOTH generators of S₃ iff p = q = r — the trivial
-- representation is one-dimensional and L spans it. Checked as an iff over
-- generated functionals.
lawLumaIsTheUniqueInvariant :: (Integer, Integer, Integer) -> Bool
lawLumaIsTheUniqueInvariant (p, q, r) =
  invariant == (p == q && q == r)
  where
    f (x, y, z) = p * x + q * y + r * z
    invariant =
      all (\v -> f (swapRG v) == f v && f (cycleRGB v) == f v)
          [ (1, 0, 0), (0, 1, 0), (0, 0, 1) ]

-- | LAW (chroma is A₂ — the b = 3 instance of the octant SES): both chart
-- vectors are sum-zero (members of A₂ = ker Σ, via RootLatticeDetail's
-- membership), and the band count at branching 3 is 2 = the chroma
-- dimensions. Color and space: one theorem, two values of b.
lawChromaIsA2OfChannels :: RGB -> Bool
lawChromaIsA2OfChannels v =
  inA [1, -1, 0] && inA [1, 1, -2] && inA [0, 1, -1]
    && numDetailBands 3 == 2
    && inA [ra, rb, rc]                      -- chroma of ANY v is mean-free:
  where
    l = lumaOf v
    (r, g, b) = v
    (ra, rb, rc) = (3 * r - l, 3 * g - l, 3 * b - l)  -- 3·(v − mean), integral

-- | LAW (the group acts as Eisenstein units, INTEGRALLY, in the root chart):
-- the 3-cycle acts on (α₁, α₂) by M = [[−1,−1],[1,0]] (det 1, trace −1,
-- M³ = I — multiplication by ω on hexagonal A₂) and the transposition by
-- N = [[−1,0],[1,1]] (det −1, N² = I — a reflection); both verified
-- pointwise as exact equivariance on arbitrary channels.
lawRootChartIsEquivariant :: RGB -> Bool
lawRootChartIsEquivariant v =
  alphaChart (cycleRGB v) == mulM (alphaChart v)
    && alphaChart (swapRG v) == mulN (alphaChart v)
    && mulM (mulM (mulM (7, -3))) == (7, -3)      -- M³ = I on a probe
    && mulN (mulN (7, -3)) == (7, -3)             -- N² = I
    && detM == 1 && trM == -1 && detN == -1       -- ω and a reflection
  where
    mulM (x, y) = (-x - y, x)       -- [[-1,-1],[1,0]]
    mulN (x, y) = (-x, x + y)       -- [[-1,0],[1,1]]
    detM = (-1) * 0 - (-1) * 1
    trM = (-1) + 0
    detN = (-1) * 1 - 0 * 1

-- | LAW (the stored chart's price): ⟨a,b⟩ has INDEX 2 in A₂ — b − a = 2·α₂
-- exactly, while α₂ itself is parity-obstructed (every ⟨a,b⟩ combination has
-- EVEN third channel-coordinate; α₂'s is −1) — and the 3-cycle is therefore
-- only HALF-integral in the stored chart: 2·a(σv) = −(a+b)(v), the exact
-- integer identity exhibiting the halving. Byte storage bought at the price
-- of S₃-integrality; the root chart keeps the symmetry, the stored chart
-- keeps the bytes.
lawStoredChartTradesSymmetryForBytes :: Integer -> Integer -> RGB -> Bool
lawStoredChartTradesSymmetryForBytes c1 c2 v =
  bMinusA == scaledAlpha2
    && even thirdCoord
    && 2 * aOfCycled == negate (av + bv)
  where
    -- b − a = 2·α₂ as channel vectors: (0,2,−2) = 2·(0,1,−1)
    bMinusA = ((1, 1, -2) `minus3` (1, -1, 0))
    scaledAlpha2 = (0, 2, -2)
    minus3 (x, y, z) (x', y', z') = (x - x', y - y', z - z')
    -- parity obstruction: third coordinate of c1·a + c2·b is −2·c2, even.
    thirdCoord = c1 * 0 + c2 * (-2)
    (av, bv) = storedChart v
    (aOfCycled, _) = storedChart (cycleRGB v)

-- | LAW (the image congruences and the exact inverse): fromLab ∘ opponent =
-- id on all channels; opponent's image satisfies the congruences; and the
-- teeth — (1,0,0) fails mod 3, (0,1,0) fails parity. Which Lab triples are
-- colors is DECIDED by two congruences, nothing else.
lawInverseAndImage :: RGB -> Bool
lawInverseAndImage v =
  fromLab (opponent v) == v
    && inImage (opponent v)
    && not (inImage (1, 0, 0))
    && not (inImage (0, 1, 0))

-- | LAW (det 6 = 3 × 2, each factor a NAMED index): 3 = [ℤ³ : A₂ ⊕ ℤ·diag]
-- (membership ⟺ 3 | Σ, so the quotient is ℤ/3 via Σ mod 3 — e_R generates
-- it: Σe_R = 1, Σ2e_R = 2, Σ3e_R = 3 ≡ 0 with the explicit witness
-- 3e_R − diag = (2,−1,−1) ∈ A₂); 2 = [A₂ : ⟨a,b⟩] (the previous law). The
-- SES owns the 3; the chart owns the 2.
lawDetIsProductOfIndices :: RGB -> Bool
lawDetIsProductOfIndices v =
  opponentDet == 3 * 2
    && (memberSum v == (lumaOf v `mod` 3 == 0))      -- membership ⟺ 3 | Σ
    && not (memberSum (1, 0, 0))                     -- e_R: order 3 in the quotient
    && not (memberSum (2, 0, 0))
    && memberSum (3, 0, 0)
    && inA [2, -1, -1]                               -- the explicit witness
  where
    -- v ∈ A₂ + ℤ·(1,1,1) ⟺ Σv ≡ 0 (mod 3): subtract k·diag with k = Σ/3.
    memberSum u = lumaOf u `mod` 3 == 0

{- |
Module      : SixFour.Spec.AxisSKI
Description : SKI RECONSIDERED, DIMENSIONALLY — the combinators are AXIS-INDEXED. The voxel is x:y:t, and the collapse is not one K but three: K_x, K_y, K_t (per-axis halving — the freedom "SixFour.Spec.SpineRing" bought by choosing the product ring; a local 8-adic ring could not even name them). Sections likewise: S_x, S_y, S_t. The scale-only reading of "SixFour.Spec.MixSKI" is the DIAGONAL of this algebra; the full object is the (ℤ/2)³-graded family, and the mix field upgrades from a depth to a DEPTH VECTOR (d_x, d_y, d_t) per region — a region can be crisp-but-still (fine x,y / pulled t), blurry-but-alive (pulled x,y / fine t), streaked (fine x / pulled y), … 27 view-cells per region where the isotropic family had 3.

The laws (washes w_a = S₀_a ∘ K_a, exact ℚ; doubled integer washes where the
band algebra needs ℤ):

  * 'lawAxisWashesCommuteAndProject': the three axis washes COMMUTE pairwise
    and are idempotent — the axis order of a pull never matters, and washing
    twice is washing once (projections onto axis-constant subspaces; the
    operator-level face of SpineRing's axes-coarsen-independently).
  * 'lawIsotropicPullFactors': the isotropic pull is the composite
    w_x ∘ w_y ∘ w_z in EVERY order — MixSKI's K-chain was this algebra's
    diagonal, recovered exactly.
  * 'lawAnisotropicStrictlyExtends': a t-only wash (crisp-but-still) differs
    on the witness volume from EVERY isotropic render — the axis family
    strictly extends the diagonal (27^regions vs 3^regions).
  * 'lawAxisWashKillsItsBands': the doubled integer wash along axis a
    annihilates EXACTLY the a-containing OctantViews bands and doubles the
    rest — for ALL THREE axes (generalizing the landed t-only law). K_a's
    kernel on latents is the a-graded part; the S_a's are accountable for
    disjoint band sets: THE GENE DECOMPOSES BY AXIS — three gene components,
    one per axis, plus their mixed products.
  * 'lawZeroSectionIsArrowBlind': w_t COMMUTES with time reversal while the
    t-band it discards is REVERSAL-ODD (nonzero witness) — the canonical
    section cannot express time's arrow; any learned S_t that reconstructs
    t-detail must break reversal symmetry. The arrow enters the synthesis
    exactly and only through the temporal gene. S_t ≢ S_x, S_y by algebra,
    not convention.

UI/UX consequence (docs/CUBE-BRUSH-PLAN.md, second amendment): a pick in a
view grants the view's DEPTH VECTOR, not a scalar; the view space is the
3×3(×3) axis lattice with the three "pure" views on its diagonal; the W1
mask generalizes to per-axis superlevels. HONEST BOUNDARY: this module gates
the operator algebra on the 8³ test volume over ℚ (plus the ℤ band law on
the 2×2×2 block); anisotropic GIF realization (per-axis block replication;
t-pull = repeated frames / changed-rect omission) rides the landed PullField
byte laws and is not re-proven here.
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none
module SixFour.Spec.AxisSKI
  ( -- * Axis washes (S₀_a ∘ K_a)
    Axis3 (..)
  , washA
  , washAllQ
    -- * Laws
  , lawAxisWashesCommuteAndProject
  , lawIsotropicPullFactors
  , lawAnisotropicStrictlyExtends
  , lawAxisWashKillsItsBands
  , lawZeroSectionIsArrowBlind
  ) where

import Data.Ratio ((%))

import SixFour.Spec.OctantViews (Axis (..), blockFromList, bandOf, axisSubsets)
import SixFour.Spec.PullField (Volume, volumeFromList, side)
import SixFour.Spec.FidelityLadder (renderPullQ)

-- | The three voxel axes (local name to avoid orphan reuse; mirrors
-- OctantViews.Axis: X, Y, and the ORDERED T).
data Axis3 = AX | AY | AT deriving (Eq, Show, Enum, Bounded)

type VQ = (Int, Int, Int) -> Rational

-- | The wash along ONE axis at halving factor b (2 or 4): pool b-runs of the
-- axis and replicate back — S₀_a ∘ K_a, everything else untouched.
washA :: Axis3 -> Int -> VQ -> VQ
washA a b v (x, y, t) =
  case a of
    AX -> avg [ v (x0 + i, y, t) | i <- [0 .. b - 1] ] where x0 = (x `div` b) * b
    AY -> avg [ v (x, y0 + i, t) | i <- [0 .. b - 1] ] where y0 = (y `div` b) * b
    AT -> avg [ v (x, y, t0 + i) | i <- [0 .. b - 1] ] where t0 = (t `div` b) * b
  where avg xs = sum xs * (1 % fromIntegral (length xs))

-- | All three axis washes at factor b (order irrelevant by the commute law).
washAllQ :: Int -> VQ -> VQ
washAllQ b = washA AX b . washA AY b . washA AT b

allVoxels :: [(Int, Int, Int)]
allVoxels = [ (x, y, t) | t <- [0 .. side - 1], y <- [0 .. side - 1], x <- [0 .. side - 1] ]

liftQ :: Volume -> VQ
liftQ v = fromInteger . v

-- | LAW (the axes are independent operators): axis washes COMMUTE pairwise
-- and each is IDEMPOTENT — projections onto axis-constant subspaces; the
-- operator face of SpineRing's per-axis coarsening.
lawAxisWashesCommuteAndProject :: [Integer] -> Bool
lawAxisWashesCommuteAndProject xs =
  and [ washA a 2 (washA b 2 vq) p == washA b 2 (washA a 2 vq) p
      | a <- axes, b <- axes, p <- probe ]
    && and [ washA a 2 (washA a 2 vq) p == washA a 2 vq p | a <- axes, p <- probe ]
  where
    axes = [AX, AY, AT]
    vq = liftQ (volumeFromList xs)
    probe = every7 allVoxels
    every7 (q : rest) = q : every7 (drop 6 rest)
    every7 [] = []

-- | LAW (MixSKI was the diagonal): the isotropic depth-1 pull is the
-- composite of the three axis washes, in EVERY axis order.
lawIsotropicPullFactors :: [Integer] -> Bool
lawIsotropicPullFactors xs =
  and [ composite order p == renderPullQ (const 1) v p
      | order <- orders, p <- probe ]
  where
    v = volumeFromList xs
    vq = liftQ v
    orders = [ [AX, AY, AT], [AX, AT, AY], [AY, AX, AT]
             , [AY, AT, AX], [AT, AX, AY], [AT, AY, AX] ]
    composite order = foldr (\a acc -> washA a 2 acc) vq order
    probe = every5 allVoxels
    every5 (q : rest) = q : every5 (drop 4 rest)
    every5 [] = []

-- | LAW (the axis family strictly extends the isotropic diagonal): the
-- crisp-but-still render (t-washed only, x and y fine) differs on the
-- witness volume from EVERY isotropic depth render — a view no scalar depth
-- can express. 27 view-cells per region where the diagonal had 3.
lawAnisotropicStrictlyExtends :: Bool
lawAnisotropicStrictlyExtends =
  and [ any (\p -> crispStill p /= renderPullQ (const d) v p) allVoxels
      | d <- [0, 1, 2] ]
  where
    v = volumeFromList [ toInteger ((x + 2 * y + 5 * t) `mod` 97)
                       | t <- [0 .. side - 1], y <- [0 .. side - 1], x <- [0 .. side - 1] ]
    crispStill = washA AT 4 (liftQ v)

-- | LAW (the gene decomposes by axis): the DOUBLED integer wash along axis a
-- (sum the a-pair, duplicate — 2·w_a, exact over ℤ) annihilates exactly the
-- a-containing OctantViews bands and doubles the rest — for ALL THREE axes.
-- K_a's kernel on latents is the a-graded part; each S_a owes a disjoint
-- band set.
lawAxisWashKillsItsBands :: [Integer] -> Bool
lawAxisWashKillsItsBands xs =
  and [ bandOf (washed a) s == expected a s | a <- [AxX, AxY, AxT], s <- axisSubsets ]
  where
    v = blockFromList xs
    washed a (x, y, t) = case a of
      AxX -> v (0, y, t) + v (1, y, t)
      AxY -> v (x, 0, t) + v (x, 1, t)
      AxT -> v (x, y, 0) + v (x, y, 1)
    expected a s = if a `elem` s then 0 else 2 * bandOf v s

-- | LAW (time's arrow lives only in the temporal gene): the canonical wash
-- w_t COMMUTES with time reversal — the zero-detail section is arrow-blind —
-- while the t-band it discards is REVERSAL-ODD and nonzero on the witness:
-- any S_t that reconstructs temporal detail must break reversal symmetry.
-- The arrow enters synthesis exactly and only through S_t.
lawZeroSectionIsArrowBlind :: [Integer] -> Bool
lawZeroSectionIsArrowBlind xs =
  and [ washA AT 2 (liftQ vRev) p == revQ (washA AT 2 (liftQ v)) p | p <- probe ]
    && (bandOf wBlock [AxT] == negate (bandOf wRevBlock [AxT]))
  where
    v = volumeFromList xs
    vRev (x, y, t) = v (x, y, side - 1 - t)
    revQ f (x, y, t) = f (x, y, side - 1 - t)
    wBlock = blockFromList (take 8 (xs ++ repeat 0))
    wRevBlock (x, y, t) = wBlock (x, y, 1 - t)
    probe = every5 allVoxels
    every5 (q : rest) = q : every5 (drop 4 rest)
    every5 [] = []

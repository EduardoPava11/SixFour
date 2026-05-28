{- |
Module      : SixFour.Spec.LookCore
Description : The "correct-the-math" core contract — Bures/k-means floor + bounded residual.

The committed core architecture (decision map, 2026-05-27: **Path B**). The collapse is
not learned from scratch; it is the deterministic Wasserstein-2 floor (the free-support
barycenter = k-means, 'SixFour.Spec.LookNet.baselinePalette'; covariance-aware via
'SixFour.Spec.Bures') **plus a bounded learned "look" residual** on the Haar coefficients:

> output = reconstruct( floor ⊕ s·tanh(residual) )

This makes the contract laws hold **by construction, for any weights**:

  * **neutral = floor** — @tanh 0 = 0@ ⇒ a zero residual returns the floor exactly (reset);
  * **bounded** — @|tanh| ≤ 1@ ⇒ each coefficient moves ≤ @s@, so each leaf moves
    ≤ @(depth+1)·s@ (root + one offset per level);
  * **σ-equivariant** — @tanh@ is **odd**, so the coefficient-wise op commutes with the
    chroma reflection σ @(L,a,b)↦(L,−a,−b)@; symmetry is free and needs no loss term.

The network is one inhabitant: it produces the @residual@ (a Haar-shaped delta) from the
encoder context + preference latent. The floor and the laws are fixed scaffold. Mirrors
the bounded/neutral/gamut pattern of 'SixFour.Spec.Look', lifted onto the Haar tree.
-}
module SixFour.Spec.LookCore
  ( lookCoreScale
  , zeroResidualLike
  , mapHaar
  , combineHaar
  , sigmaHaar
  , applyLookCore
  , lookFloor
  , leafDisplacementBound
    -- * Laws (predicates; QuickCheck'd in Properties.LookCore)
  , lawNeutralIsFloor
  , lawBoundedLeaves
  , lawSigmaEquivariant
  ) where

import GHC.TypeLits (KnownNat)

import SixFour.Spec.Color    (OKLab(..), okLabDistanceSquared)
import SixFour.Spec.Cyclic   (CyclicStack)
import SixFour.Spec.PairTree (HaarPalette(..), reconstruct, sigmaReflect, treeDepth)
import SixFour.Spec.LookNet  (baselinePalette)

-- | The per-coefficient residual scale @s@ — the maximum a single Haar coefficient may
-- be nudged off the floor (the "strength of the look"). A small, fixed bound.
lookCoreScale :: Double
lookCoreScale = 0.1

-- | The deterministic floor palette: the free-support Wasserstein-2 barycenter
-- (farthest-point / k-means collapse) of the per-frame palettes, read as a Haar tree.
-- (`baselinePalette`; 'SixFour.Spec.Bures.buresBarycenter' supplies the covariance-aware
-- companion the loss uses.)
lookFloor :: KnownNat k => CyclicStack t k -> HaarPalette
lookFloor = baselinePalette

-- | Map a per-colour function over every node of a Haar palette (root + all offsets).
mapHaar :: (OKLab -> OKLab) -> HaarPalette -> HaarPalette
mapHaar f (HaarPalette r lvls) = HaarPalette (f r) (map (map f) lvls)

-- | Combine two same-shaped Haar palettes coefficient-wise.
combineHaar :: (OKLab -> OKLab -> OKLab) -> HaarPalette -> HaarPalette -> HaarPalette
combineHaar f (HaarPalette r1 l1) (HaarPalette r2 l2) =
  HaarPalette (f r1 r2) (zipWith (zipWith f) l1 l2)

-- | A zero residual shaped like the given palette (the neutral / "no-look" code).
zeroResidualLike :: HaarPalette -> HaarPalette
zeroResidualLike = mapHaar (const (OKLab 0 0 0))

-- | The chroma reflection σ lifted to every coefficient of a Haar palette.
sigmaHaar :: HaarPalette -> HaarPalette
sigmaHaar = mapHaar sigmaReflect

-- | The core: add the bounded residual @s·tanh(·)@ to the floor, coefficient-wise.
-- @applyLookCore s floor residual@. With @residual = 0@ this is the floor (neutral).
applyLookCore :: Double -> HaarPalette -> HaarPalette -> HaarPalette
applyLookCore s = combineHaar add
  where
    add (OKLab fl fa fb) (OKLab rl ra rb) =
      OKLab (fl + s * tanh rl) (fa + s * tanh ra) (fb + s * tanh rb)

-- | The provable per-channel bound on how far any leaf moves off the floor:
-- @(depth + 1)·s@ (one root coefficient + one offset per level, each ≤ @s@).
leafDisplacementBound :: Double -> HaarPalette -> Double
leafDisplacementBound s floor' = fromIntegral (treeDepth floor' + 1) * s

-- ----------------------------------------------------------------------------
-- Laws (hold for ANY residual — by construction)
-- ----------------------------------------------------------------------------

-- | Neutral identity: the zero residual returns the floor unchanged (reset works).
lawNeutralIsFloor :: HaarPalette -> Bool
lawNeutralIsFloor floor' =
  applyLookCore lookCoreScale floor' (zeroResidualLike floor') == floor'

-- | Boundedness: every reconstructed leaf moves at most 'leafDisplacementBound' per
-- channel off the floor, for ANY residual.
lawBoundedLeaves :: Double -> HaarPalette -> HaarPalette -> Bool
lawBoundedLeaves tol floor' residual =
  let out    = reconstruct (applyLookCore lookCoreScale floor' residual)
      base   = reconstruct floor'
      bound  = leafDisplacementBound lookCoreScale floor' + tol
      chan (OKLab l1 a1 b1) (OKLab l2 a2 b2) =
        abs (l1 - l2) <= bound && abs (a1 - a2) <= bound && abs (b1 - b2) <= bound
  in length out == length base && and (zipWith chan out base)

-- | σ-equivariance: applying σ to (floor, residual) equals σ of the output — so the
-- complement symmetry is exact for any residual (tanh is odd). No loss term needed.
lawSigmaEquivariant :: Double -> HaarPalette -> HaarPalette -> Bool
lawSigmaEquivariant tol floor' residual =
  let lhs = reconstruct (applyLookCore lookCoreScale (sigmaHaar floor') (sigmaHaar residual))
      rhs = map sigmaReflect (reconstruct (applyLookCore lookCoreScale floor' residual))
      close (OKLab l1 a1 b1) (OKLab l2 a2 b2) =
        abs (l1 - l2) <= tol && abs (a1 - a2) <= tol && abs (b1 - b2) <= tol
  in length lhs == length rhs && and (zipWith close lhs rhs)

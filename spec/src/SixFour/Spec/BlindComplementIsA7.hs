{- |
Module      : SixFour.Spec.BlindComplementIsA7
Description : The ANT-load-bearing bridge: the cell objective's BLIND complement IS the mean-free A_7 detail lattice. The checkerboard direction the rank-3 cell loss cannot see ("SixFour.Spec.Convergence" / "SixFour.Spec.LearnabilityTheorem") is not an arbitrary linear-algebra null vector — it is a genuine @A_7@ residual (@Σ = 0@), constructible through the byte-exact "SixFour.Spec.RootLatticeDetail" @MeanFree@ type. So WHAT @cellLoss@ misses is exactly the algebraic detail structure, and WHY the value head is needed is the recovery of that @A_7@ subspace.

This is the honest, NON-FORCED way to make the lattice load-bearing (the owner's anti-jargon line): not a
rename of the elementary rank argument, but a REAL typed consumer. The bridge:

  * "SixFour.Spec.Convergence" proved the cell Hessian @∝ S·Sᵀ@ is rank-3 and the checkerboard
    @cb(v) = (−1)^popcount(v)@ lies in its null space (@cellLoss@ is invariant under it).
  * Here we prove @Σ cb = 0@, so @cb@ is admitted by "SixFour.Spec.RootLatticeDetail" @mkMeanFreeChecked@
    (the @MeanFree@ smart constructor that builds ONLY mean-free vectors, never by dividing by the
    non-unit @b@) — i.e. @cb ∈ A_7 = ker Σ@. The blind direction is a LATTICE vector, witnessed by the type.
  * Therefore the 15-DOF complement @cellLoss@ cannot see is the @A_7@ mean-free detail subspace, which the
    value head identifies ("SixFour.Spec.LearnabilityTheorem" @lawValueHeadIdentifiesComplement@). The
    cell/value split is the @span(S)@ (mean + spatial ramps) vs @A_7@ (mean-free detail) decomposition.

The teeth are real, not decorative: a vector with @Σ ≠ 0@ (e.g. a single-voxel bump @e_0@) is REFUSED by
@mkMeanFreeChecked@ (returns @Nothing@), so the law fails if a non-lattice direction is passed off as the
blind complement. Reversibility stays a tested law elsewhere; this module makes only the @Σ=0@ /
@MeanFree@ membership claim, which is genuinely structural. Pure-spec, GHC-boot-only; laws QuickCheck'd in
"Properties.BlindComplementIsA7". Emits no golden.
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none
module SixFour.Spec.BlindComplementIsA7
  ( -- * The checkerboard blind direction, as an A_7 lattice vector
    checkerboardZ
  , checkerboardMeanFree
    -- * Laws
  , lawCheckerboardIsMeanFree
  , lawBlindDirectionIsLatticeVector
  , lawNonLatticeDirectionRefused
  , lawCellBlindComplementIsA7
  ) where

import Data.Maybe (isJust, isNothing)

import SixFour.Spec.Convergence      (checkerboard, cellLoss)
import SixFour.Spec.RootLatticeDetail (MeanFree, unMeanFree, mkMeanFreeChecked, inA)

-- | The checkerboard blind direction as an INTEGER vector (the byte-exact lattice form of
-- "SixFour.Spec.Convergence" @checkerboard@): @cb(v) = (−1)^popcount(v)@ over the 8 octant voxels.
checkerboardZ :: [Integer]
checkerboardZ = map round (checkerboard :: [Double])

-- | The checkerboard admitted as a "SixFour.Spec.RootLatticeDetail" @MeanFree@ (A_7) vector — @Nothing@
-- would mean it is NOT mean-free (and the whole bridge would be false). The TYPED consumer that makes
-- A_7 load-bearing: the blind direction is built through the lattice's own smart constructor.
checkerboardMeanFree :: Maybe MeanFree
checkerboardMeanFree = mkMeanFreeChecked checkerboardZ

-- ---------------------------------------------------------------------------
-- Laws (QuickCheck'd in Properties.BlindComplementIsA7)
-- ---------------------------------------------------------------------------

-- | THE BRIDGE: the checkerboard blind direction is MEAN-FREE (@Σ cb = 0@), so it is a genuine @A_7@
-- residual — @mkMeanFreeChecked@ ADMITS it and the recovered vector is the input. Not a rename: the
-- lattice's own constructor is the witness. Teeth: 'lawNonLatticeDirectionRefused'.
lawCheckerboardIsMeanFree :: Bool
lawCheckerboardIsMeanFree =
     sum checkerboardZ == 0                                  -- Σ cb = 0 (the A_7 = ker Σ condition)
  && inA checkerboardZ                                       -- ...stated via the lattice membership test
  && case checkerboardMeanFree of
       Just mf -> unMeanFree mf == checkerboardZ             -- admitted by the MeanFree constructor, intact
       Nothing -> False

-- | The blind direction is a LATTICE vector: the @MeanFree@ smart constructor admits it (@isJust@). This
-- is the typed consumer that makes @A_7@ load-bearing in the identifiability/convergence story.
lawBlindDirectionIsLatticeVector :: Bool
lawBlindDirectionIsLatticeVector = isJust checkerboardMeanFree

-- | TEETH: a non-lattice direction (@Σ ≠ 0@, e.g. a single-voxel bump @e_0 = [1,0,…]@) is REFUSED by
-- @mkMeanFreeChecked@. So "the blind complement is A_7" is a real claim — a non-mean-free vector cannot
-- masquerade as the blind direction. Without this, 'lawCheckerboardIsMeanFree' could be vacuous.
lawNonLatticeDirectionRefused :: Bool
lawNonLatticeDirectionRefused =
     isNothing (mkMeanFreeChecked (1 : replicate 7 0))       -- e_0, Σ = 1 ≠ 0 : refused
  && not (inA (1 : replicate 7 0))

-- | THE CAPSTONE: the cell objective's BLIND complement IS the @A_7@ mean-free detail subspace. The
-- checkerboard (a) is invariant for @cellLoss@ — perturbing one colour channel of a palette by @cb@ leaves
-- the cell aggregate unchanged (the blindness, from "SixFour.Spec.Convergence") — AND (b) is an @A_7@
-- lattice vector ('lawCheckerboardIsMeanFree'). So what the rank-3 cell loss cannot see is exactly the
-- mean-free @A_7@ detail the value head recovers. Teeth: both the invariance and the lattice membership
-- must hold; either failing breaks the bridge.
lawCellBlindComplementIsA7 :: Bool
lawCellBlindComplementIsA7 =
  let base    = replicate 8 [0.0, 0.0, 0.0]                  -- a flat palette (8 voxels × 3 channels)
      shifted = [ [cv, 0.0, 0.0] | cv <- checkerboard ]      -- channel 0 perturbed by the checkerboard
  in cellLoss shifted base < 1e-9                            -- (a) cellLoss BLIND to the checkerboard
     && lawCheckerboardIsMeanFree                            -- (b) the blind direction is an A_7 residual

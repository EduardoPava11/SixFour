{- |
Module      : SixFour.Spec.BlindComplementGeometry
Description : The PRECISE geometry behind "SixFour.Spec.BlindComplementIsA7": the cell-blind complement @S^⊥@ and the mean-free lattice @A_7@ are DISTINCT subspaces (different dimensions), NEITHER contained in the other; their load-bearing OVERLAP is exactly the mean-free blind subspace @S^⊥ ∩ A_7@ where the checkerboard lives. This sharpens "the blind complement is A_7" to the honest, gateable form — the value head's @A_7@ algebra is load-bearing precisely on that overlap, not on the whole blind complement.

Why this module exists (the honest-close audit). "SixFour.Spec.BlindComplementIsA7" proves a SOUND law —
the checkerboard @cb@ is both blind to @cellLoss@ and a legal @A_7@ residual — but its surrounding framing
("the 15-DOF complement @cellLoss@ cannot see is EXACTLY the @A_7@ detail subspace", "@span(S)@ = mean +
spatial ramps") slightly OVERSTATES the geometry. The cell loss sees @span(S)@ where @S@ has the three
@{0,1}³@ coordinate columns @x,y,t@ (NO constant column — "SixFour.Spec.Convergence" @spaceLattice@), so:

  * The cell-blind complement is @S^⊥@, dimension @8 − 3 = 5@ per colour channel (@15@ across the 3 OKLab
    channels). @A_7 = ker Σ@ has dimension @7@ per channel (@21@ across channels). @15 ≠ 21@: the blind
    complement is NOT the @A_7@ subspace ('lawBlindAndA7DimsDiffer').
  * @S^⊥ ⊄ A_7@: the origin-voxel bump @e_0 = [1,0,…,0]@ is BLIND to @cellLoss@ (voxel @0@ has space
    coordinate @(0,0,0)@, so it contributes nothing to the cross-moment @A = C·Sᵀ@), yet @Σ e_0 = 1 ≠ 0@,
    so @e_0 ∉ A_7@ — it is REFUSED by "SixFour.Spec.RootLatticeDetail" @mkMeanFreeChecked@. So there is a
    genuine blind direction OUTSIDE @A_7@ ('lawBlindDirectionOutsideA7'). (Poignantly, @e_0@ is the very
    vector "SixFour.Spec.BlindComplementIsA7" uses as its "refused, not the blind complement" teeth — yet
    it IS blind; it just is not mean-free.)
  * @A_7 ⊄ S^⊥@: the mean-free difference @v = x − y@ is a legal @A_7@ residual (@Σ v = 0@, admitted by
    @mkMeanFreeChecked@) that @cellLoss@ SEES (@v·x = 2 ≠ 0@) ('lawA7DirectionSeenByCell').

The HONEST capstone ('lawBlindMeetsA7InMeanFreeBlind'): the two subspaces MEET in @S^⊥ ∩ A_7@, the
mean-free blind subspace @{1,x,y,t}^⊥@ of dimension @8 − 4 = 4@ per channel (@12@ across channels), and
THAT is where the checkerboard lives and where the value head's @A_7@ (mean-free) algebra is genuinely
load-bearing. So the correct statement is not "blind complement = @A_7@" but "the lattice is load-bearing
on the mean-free blind directions, which include the checkerboard" — exactly what
"SixFour.Spec.BlindComplementIsA7" @lawCheckerboardIsMeanFree@ witnesses, now with its scope pinned.

Ranks are computed by exact rational Gaussian elimination ('rankQ'), so every dimension claim is a teeth
fact (a wrong rank fails the law). Reuses "SixFour.Spec.Convergence" @cellLoss@ / @checkerboard@ and
"SixFour.Spec.RootLatticeDetail" @inA@ unchanged. Pure-spec, GHC-boot-only; laws QuickCheck'd in
"Properties.BlindComplementGeometry". Emits no golden.
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none
module SixFour.Spec.BlindComplementGeometry
  ( -- * The octant space columns and the witness directions
    colX, colY, colT, ones8
  , originBump
  , xMinusY
    -- * Blindness via the real cell loss
  , isBlindToCell
    -- * Exact subspace dimensions
  , rankQ
  , blindDim, a7Dim, meanFreeBlindDim
    -- * Laws
  , lawCheckerboardInBlindAndA7
  , lawBlindDirectionOutsideA7
  , lawA7DirectionSeenByCell
  , lawBlindAndA7DimsDiffer
  , lawBlindMeetsA7InMeanFreeBlind
  ) where

import Data.Ratio (Ratio, (%))

import SixFour.Spec.Convergence       (cellLoss, checkerboard)
import SixFour.Spec.RootLatticeDetail (inA, mkMeanFreeChecked)
import Data.Maybe (isJust, isNothing)

-- ---------------------------------------------------------------------------
-- The octant space lattice columns (the SAME {0,1}³ coordinates Convergence uses)
-- ---------------------------------------------------------------------------

-- | The @x@ coordinate over the 8 octant voxels (frame-major @{0,1}³@): a column of @S@.
colX :: [Integer]
colX = [0,1,0,1,0,1,0,1]

-- | The @y@ coordinate over the 8 octant voxels: a column of @S@.
colY :: [Integer]
colY = [0,0,1,1,0,0,1,1]

-- | The @t@ coordinate over the 8 octant voxels: a column of @S@.
colT :: [Integer]
colT = [0,0,0,0,1,1,1,1]

-- | The constant (mean) direction over the 8 voxels. NOT a column of @S@ — this is the crux: the cell
-- loss does NOT see the mean directly (@1 ∉ span(S)@), so the mean partly leaks into the blind complement.
ones8 :: [Integer]
ones8 = replicate 8 1

-- | The origin-voxel bump @e_0 = [1,0,…,0]@: a unit perturbation at voxel @0@ (space coordinate
-- @(0,0,0)@). Because voxel @0@ contributes @0@ to the cross-moment, @e_0@ is BLIND to @cellLoss@ — yet
-- @Σ e_0 = 1 ≠ 0@, so it is not an @A_7@ residual.
originBump :: [Integer]
originBump = 1 : replicate 7 0

-- | The mean-free difference @x − y = [0,1,−1,0,0,1,−1,0]@: a legal @A_7@ residual (@Σ = 0@) that the
-- cell loss DOES see (its projection onto @span(S)@ is non-zero).
xMinusY :: [Integer]
xMinusY = zipWith (-) colX colY

-- ---------------------------------------------------------------------------
-- Blindness via the actual cell loss (reuses Convergence.cellLoss)
-- ---------------------------------------------------------------------------

eps :: Double
eps = 1e-9

-- | Is an integer direction BLIND to the cell loss? Perturb a flat palette's channel-0 by the direction
-- and ask whether @cellLoss@ moved. Blind ⟺ the direction lies in @S^⊥@ (the cross-moment is unchanged).
-- This is the exact predicate "SixFour.Spec.BlindComplementIsA7" uses for the checkerboard, generalised.
isBlindToCell :: [Integer] -> Bool
isBlindToCell d =
  let base = replicate 8 [0.0, 0.0, 0.0]
      pert = [ [fromIntegral dv, 0.0, 0.0] | dv <- d ]
  in cellLoss pert base < eps

-- ---------------------------------------------------------------------------
-- Exact rational rank (so every dimension claim has teeth)
-- ---------------------------------------------------------------------------

-- | The rank of an integer matrix (rows) by exact rational Gaussian elimination — no float error, so a
-- dimension law that depended on a wrong rank would fail.
rankQ :: [[Integer]] -> Int
rankQ rows0 = go (map (map fromIntegral) rows0) 0
  where
    cols = if null rows0 then 0 else length (head rows0)
    go :: [[Ratio Integer]] -> Int -> Int
    go rows c
      | c >= cols = 0
      | otherwise =
          case break (\r -> r !! c /= 0) rows of
            (_, [])            -> go rows (c + 1)            -- no pivot in this column
            (above, piv : below) ->
              let pivVal  = piv !! c
                  pivN    = map (/ pivVal) piv
                  elim r  = let f = r !! c in zipWith (\a b -> a - f * b) r pivN
                  rest    = map elim (above ++ below)
              in 1 + go rest (c + 1)

-- | Dimension of the cell-blind complement @S^⊥@ PER colour channel: @8 − rank[x,y,t]@. Across the 3
-- OKLab channels the blind complement is @3 ×@ this (the @15@ DOF "SixFour.Spec.LearnabilityTheorem"
-- counts).
blindDim :: Int
blindDim = 8 - rankQ [colX, colY, colT]

-- | Dimension of the mean-free lattice @A_7 = ker Σ@ PER channel: @8 − rank[1]= 7@. Across the 3 channels
-- @A_7@ is @21@ DOF — strictly more than the @15@ blind DOF.
a7Dim :: Int
a7Dim = 8 - rankQ [ones8]

-- | Dimension of the OVERLAP @S^⊥ ∩ A_7@ PER channel: @8 − rank[x,y,t,1]@. This is the mean-free blind
-- subspace where the checkerboard lives; across channels it is @12@ DOF.
meanFreeBlindDim :: Int
meanFreeBlindDim = 8 - rankQ [colX, colY, colT, ones8]

-- ---------------------------------------------------------------------------
-- Laws (QuickCheck'd in Properties.BlindComplementGeometry)
-- ---------------------------------------------------------------------------

-- | The honest CORE (agreeing with "SixFour.Spec.BlindComplementIsA7"): the checkerboard @cb@ is in BOTH
-- @S^⊥@ (blind to @cellLoss@) and @A_7@ (mean-free, admitted by @mkMeanFreeChecked@). So it is a genuine
-- mean-free blind direction — a member of the overlap @S^⊥ ∩ A_7@. Teeth: either membership failing breaks it.
lawCheckerboardInBlindAndA7 :: Bool
lawCheckerboardInBlindAndA7 =
  let cb = map round (checkerboard :: [Double]) :: [Integer]
  in isBlindToCell cb && inA cb && isJust (mkMeanFreeChecked cb)

-- | THE CORRECTION (i): @S^⊥ ⊄ A_7@. The origin bump @e_0@ is BLIND to @cellLoss@ (voxel @0@ has space
-- coordinate @(0,0,0)@, contributing nothing to the cross-moment) yet @Σ e_0 = 1 ≠ 0@, so it is NOT an
-- @A_7@ residual — @mkMeanFreeChecked@ REFUSES it. So the blind complement strictly contains a non-@A_7@
-- direction; "blind complement = @A_7@" is too strong. Teeth: if @e_0@ were seen, or were in @A_7@, it fails.
lawBlindDirectionOutsideA7 :: Bool
lawBlindDirectionOutsideA7 =
     isBlindToCell originBump                  -- e_0 IS blind (in S^⊥)
  && sum originBump /= 0                       -- but Σ ≠ 0
  && not (inA originBump)                      -- ...so NOT in A_7
  && isNothing (mkMeanFreeChecked originBump)  -- refused by the lattice constructor

-- | THE CORRECTION (ii): @A_7 ⊄ S^⊥@. The mean-free difference @x − y@ is a legal @A_7@ residual
-- (@Σ = 0@, admitted) that @cellLoss@ DOES see (its @span(S)@ projection is non-zero). So @A_7@ is not
-- contained in the blind complement either — the two subspaces genuinely cross. Teeth: if it were blind,
-- or not in @A_7@, it fails.
lawA7DirectionSeenByCell :: Bool
lawA7DirectionSeenByCell =
     inA xMinusY                       -- x − y is a legal A_7 residual (mean-free)
  && isJust (mkMeanFreeChecked xMinusY)
  && not (isBlindToCell xMinusY)       -- but the cell loss SEES it (not in S^⊥)

-- | THE CORRECTION (iii): the dimensions differ. Per channel the blind complement is @5@-dim and @A_7@ is
-- @7@-dim, and their overlap is @4@-dim; across the 3 OKLab channels that is @15@ vs @21@ (overlap @12@).
-- So the @15@-DOF blind complement is NOT the @A_7@ detail subspace (which is @21@-DOF). Teeth: each rank
-- is computed exactly, so a wrong dimension fails.
lawBlindAndA7DimsDiffer :: Bool
lawBlindAndA7DimsDiffer =
     blindDim == 5 && a7Dim == 7 && meanFreeBlindDim == 4   -- per channel
  && 3 * blindDim == 15 && 3 * a7Dim == 21                  -- across channels: 15 ≠ 21
  && blindDim /= a7Dim                                       -- the headline inequality
  && meanFreeBlindDim < blindDim && meanFreeBlindDim < a7Dim -- the overlap is a proper subspace of each

-- | THE HONEST CAPSTONE: the cell-blind complement @S^⊥@ and the lattice @A_7@ are DISTINCT (neither
-- contains the other), and their load-bearing OVERLAP is the mean-free blind subspace @S^⊥ ∩ A_7@ where
-- the checkerboard lives. This is the precise, gateable form of "the blind complement is @A_7@": the
-- value head's @A_7@ algebra is load-bearing on the mean-free blind directions (the @12@-DOF overlap),
-- not on the whole @15@-DOF blind complement. Conjoins the core + the three corrections.
lawBlindMeetsA7InMeanFreeBlind :: Bool
lawBlindMeetsA7InMeanFreeBlind =
     lawCheckerboardInBlindAndA7   -- the overlap is non-empty: cb ∈ S^⊥ ∩ A_7
  && lawBlindDirectionOutsideA7    -- S^⊥ ⊄ A_7 (e_0 leaks the mean)
  && lawA7DirectionSeenByCell      -- A_7 ⊄ S^⊥ (x − y is seen)
  && lawBlindAndA7DimsDiffer       -- 15 ≠ 21, overlap 12

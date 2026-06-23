{-# LANGUAGE ScopedTypeVariables #-}

{- |
Module      : SixFour.Spec.Barycenter
Description : Free-support Wasserstein barycenter (particle-flow) — a candidate GIFA→GIFB collapse MOVE.

The open keystone (@docs/GIFA-GIFB-COLLAPSE-REDESIGN.md@) asks: /how do 64 per-frame
palettes become one global palette?/ The shipped baseline is the deterministic,
gamut-closed maximin in "SixFour.Spec.Collapse" (it only PICKS input colours — it
never moves mass). This module specs the next rung the redesign brief's move-set
survey points to: a __free-support W₂ barycenter__ that lets the global atoms move to
the optimal-transport average of the inputs, not merely select among them.

== The math (Cuturi & Doucet 2014; the 2025 free-support particle-flow framing)

Given input measures @β¹,…,β^S@ (the per-frame palettes as discrete OKLab measures)
and an initial @K@-atom support @Z = {z₁,…,z_K}@ (seeded from the maximin collapse),
iterate the displacement fixed point: for each input @s@, the entropic-OT plan
@P^s@ from @Z@ to @β^s@ ('SixFour.Spec.Sinkhorn.sinkhornPlan') gives each atom its
__barycentric projection__

>   t_i^s = (Σⱼ P^s_{ij} y_j^s) / (Σⱼ P^s_{ij})     -- a convex combination of β^s's atoms

and the atom moves to the average of those targets across inputs,
@z_i ← (1/S) Σ_s t_i^s@. Repeated, @Z@ flows to the (entropic) W₂ barycenter — the
"particles advected by averaged optimal-transport displacements" of the 2025
free-support algorithm, built from nothing but the Sinkhorn matrix–vector kernel
(no LP, no eigensolve), so it ports to MLX / hand-written Swift under the Tier-2
zero-dependency contract.

== What is PROVED here (see @Properties.Barycenter@)

  * 'lawBarycenterPreservesSupportSize' — the move keeps exactly @K@ atoms (a
    palette stays a @K@-palette), structurally.
  * 'lawBarycenterStaysInInputHull' — every output atom is a convex combination of
    input atoms, so the barycenter is GAMUT-CLOSED: it cannot invent colour outside
    the inputs' convex hull (the same guarantee the maximin collapse gives by
    construction, now under mass transport).
  * 'lawBarycenterTranslationEquivariant' — translating every input atom AND the
    seed by @v@ translates the barycenter by @v@ (the OT plan depends only on
    pairwise distances, so it is unchanged; the targets shift exactly). This is the
    defining symmetry of a barycenter.

== Status

This is a /design-surface/ spec, not the shipped path: it gives the redesign brief
an executable, golden-checkable candidate move with proven gamut-closure, to be
scored by 'SixFour.Spec.PaletteOracle' / searched by 'SixFour.Spec.PaletteSearch'
before any Swift/Metal port. The byte-exact shipped collapse remains
'SixFour.Spec.Collapse.globalCollapseQ16' until a move is settled.
-}
-- COMPARTMENT: MLX-MODEL | tag:MacTag
module SixFour.Spec.Barycenter
  ( -- * Parameters
    BarycenterParams(..)
  , defaultBarycenterParams
    -- * The barycenter move
  , barycentricProjection
  , freeSupportBarycenter
    -- * Laws (predicates; QuickCheck'd in Properties.Barycenter)
  , lawBarycenterPreservesSupportSize
  , lawBarycenterStaysInInputHull
  , lawBarycenterTranslationEquivariant
  ) where

import Data.List (transpose, foldl')

import SixFour.Spec.Color    (OKLab(..))
import SixFour.Spec.Sinkhorn (Measure, SinkhornParams, defaultSinkhornParams, sinkhornPlan)

-- | Free-support barycenter parameters: the inner entropic-OT solver ('bpSinkhorn')
-- and the number of outer displacement iterations ('bpOuter').
data BarycenterParams = BarycenterParams
  { bpSinkhorn :: !SinkhornParams
  , bpOuter    :: !Int
  } deriving (Eq, Show)

-- | Spec-default: the default Sinkhorn solver and @10@ outer iterations — enough for
-- the displacement flow to settle on the small supports the spec exercises. The
-- trainer / search tunes these.
defaultBarycenterParams :: BarycenterParams
defaultBarycenterParams = BarycenterParams defaultSinkhornParams 10

addOK :: OKLab -> OKLab -> OKLab
addOK (OKLab l a b) (OKLab l' a' b') = OKLab (l + l') (a + a') (b + b')

scaleOK :: Double -> OKLab -> OKLab
scaleOK s (OKLab l a b) = OKLab (s * l) (s * a) (s * b)

zeroOK :: OKLab
zeroOK = OKLab 0 0 0

-- | The barycentric projection of a support set onto ONE target measure: for each
-- support atom, the OT-plan-weighted average of the target's atoms
-- @t_i = (Σⱼ P_{ij} y_j) / (Σⱼ P_{ij})@. A convex combination of the target atoms
-- (so it lands in their hull). An atom with no transported mass (or an empty target)
-- stays put.
barycentricProjection :: SinkhornParams -> [OKLab] -> Measure -> [OKLab]
barycentricProjection sp support target =
  let src  = [ (z, 1) | z <- support ]
      plan = sinkhornPlan sp src target     -- |support| rows, each |target| long
      ys   = map fst target
  in [ let rowSum = sum row
       in if rowSum <= 0
            then z
            else foldl' addOK zeroOK [ scaleOK (w / rowSum) y | (w, y) <- zip row ys ]
     | (z, row) <- zip support plan ]

-- | The free-support Wasserstein barycenter of a list of input measures, seeded at
-- the given support points. Each outer iteration moves every atom to the average,
-- over the (positive-mass) inputs, of its 'barycentricProjection'. The support size
-- is preserved; the result is gamut-closed (within the inputs' convex hull). Inputs
-- with non-positive total mass are ignored; if none remain the seed is returned.
freeSupportBarycenter :: BarycenterParams -> [Measure] -> [OKLab] -> [OKLab]
freeSupportBarycenter (BarycenterParams sp outer) measures seed =
  let live = [ m | m <- measures, sum (map snd m) > 0 ]
      s    = length live
      step support =
        if s == 0 then support
        else let projs = [ barycentricProjection sp support m | m <- live ]
             in [ scaleOK (1 / fromIntegral s) (foldl' addOK zeroOK col)
                | col <- transpose projs ]
      go 0 z = z
      go k z = go (k - 1 :: Int) (step z)
  in go (max 0 outer) seed

-- ============================================================================
-- Laws (predicates; QuickCheck'd in Properties.Barycenter)
-- ============================================================================

-- | The barycenter move preserves the support size: a @K@-atom seed yields a
-- @K@-atom palette. Structural (every step is a length-preserving map).
lawBarycenterPreservesSupportSize :: [Measure] -> [OKLab] -> Bool
lawBarycenterPreservesSupportSize measures seed =
  length (freeSupportBarycenter defaultBarycenterParams measures seed) == length seed

-- | Gamut-closure: every output atom lies within the axis-aligned bounding box of
-- all input atoms (a necessary condition for "inside the convex hull"). Holds
-- because each atom is a convex combination of input atoms. Vacuously true when
-- there are no positive-mass inputs or no atoms.
lawBarycenterStaysInInputHull :: [Measure] -> [OKLab] -> Bool
lawBarycenterStaysInInputHull measures seed =
  let live   = [ m | m <- measures, sum (map snd m) > 0 ]
      atoms  = [ y | m <- live, (y, _) <- m ]
      out    = freeSupportBarycenter defaultBarycenterParams measures seed
      tol    = 1e-9
  in if null live || null atoms || null out then True
     else let ls = [ l | OKLab l _ _ <- atoms ]
              as = [ a | OKLab _ a _ <- atoms ]
              bs = [ b | OKLab _ _ b <- atoms ]
              within lo hi x = x >= lo - tol && x <= hi + tol
          in all (\(OKLab l a b) ->
                    within (minimum ls) (maximum ls) l
                 && within (minimum as) (maximum as) a
                 && within (minimum bs) (maximum bs) b) out

-- | Translation equivariance: shifting every input atom and the seed by a constant
-- vector @v@ shifts the barycenter by @v@. The OT plan depends only on pairwise
-- distances (unchanged by a common translation), so the barycentric targets move
-- exactly with @v@. The defining symmetry of a barycenter (checked to fp slack).
lawBarycenterTranslationEquivariant :: [Measure] -> [OKLab] -> (Double, Double, Double) -> Bool
lawBarycenterTranslationEquivariant measures seed (vl, va, vb) =
  let v          = OKLab vl va vb
      shiftM m   = [ (addOK y v, w) | (y, w) <- m ]
      base       = freeSupportBarycenter defaultBarycenterParams measures seed
      shifted    = freeSupportBarycenter defaultBarycenterParams (map shiftM measures) (map (`addOK` v) seed)
      near (OKLab l1 a1 b1) (OKLab l2 a2 b2) =
        abs (l1 - l2) < 1e-9 && abs (a1 - a2) < 1e-9 && abs (b1 - b2) < 1e-9
  in length base == length shifted
     && and (zipWith (\z zs -> near (addOK z v) zs) base shifted)

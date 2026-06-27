{- |
Module      : SixFour.Spec.GlobalUniqueness
Description : The AUDIT CLOSE on the real residue of OVERCLAIM-CONVERGENCE-1: the convergence docstring claims a 'UNIQUE global minimum at the target', but "SixFour.Spec.Convergence" @lawCompositeUniqueMinIffValueWeighted@ and "SixFour.Spec.ValueWeightThreshold" only examine the SINGLE cell-blind checkerboard null direction. Global uniqueness over all 24 DOF is STRICT CONVEXITY of @composite w@ for @w > 0@ — and the existing laws prove only CONVEXITY (@≤@ the chord), which never gives it. This module proves strict convexity directly: for arbitrary DISTINCT palettes @p ≠ q@ and @λ ∈ (0,1)@, @composite w (λp+(1−λ)q) t < λ·composite w p t + (1−λ)·composite w q t@ when @w > 0@; hence the target (loss 0, a global min) is the UNIQUE global minimum in EVERY direction, not just one witness.

The audit finding (OVERCLAIM-CONVERGENCE-1): "uniqueness" was demonstrated only along @cb@ (one direction
in the 5-dim cell-blind complement). Convexity (@≤@) admits a whole FLAT affine subspace of minimizers; only
STRICT convexity (@<@ for distinct endpoints) forces the minimizer to be a single point. The distinction
between non-strict and strict convexity is a real mathematical gap the @≤@-chord laws never close.

The closed-form reason it is provable (NOT a rename — it reuses "SixFour.Spec.Convergence"
@composite@/@cellLoss@/@valueLoss@/@checkerboard@ directly): for ANY quadratic @f@ with Hessian @H@, the
Jensen gap along @p,q@ is EXACTLY @λ(1−λ)·½·(p−q)ᵀH(p−q)@. So

  * @jensenGapValue = ½·λ(1−λ)·‖p−q‖²@  (value Hessian @= I@, FULL rank) — strictly @> 0@ for @p ≠ q@.
  * @jensenGapCell ≥ 0@  (cell Hessian @∝ S·Sᵀ@, @rank S = 3@, rank-DEFICIENT) — and @= 0@ along the
    checkerboard direction @cb@ (where @S·cb = 0@), i.e. the cell objective is only convex, FLAT there.
  * @jensenGapComposite w = jensenGapCell + w·jensenGapValue@. Hence @> 0@ strictly IFF @w > 0@ for distinct
    @p,q@: even in the cell-blind direction (where @jensenGapCell = 0@) the full-rank value term @w·jensenGapValue@
    rescues strictness — so strict convexity, and therefore global uniqueness in every direction, genuinely
    NEEDS @w > 0@.

This is NOT "SixFour.Spec.ValueWeightThreshold" restated: that module parametrized the WEIGHT axis along ONE
fixed (checkerboard) direction (@shiftedGap w = 4·w@); this proves uniqueness across the DIRECTION axis (the
full palette space) via strict-vs-non-strict convexity. No fancy algebra is invoked — plain Jensen-strictness
on a PD-Hessian quadratic. Pure-spec, GHC-boot-only; laws QuickCheck'd in @Properties.GlobalUniqueness@. Emits
no golden (it is a guarantee, not a fixture).
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none
module SixFour.Spec.GlobalUniqueness
  ( -- * The exact Jensen gaps of the three quadratics
    jensenGapComposite
  , jensenGapCell
  , jensenGapValue
    -- * The strict-convexity / global-uniqueness laws
  , lawJensenGapDecomposesByRank
  , lawValueGapStrictPositiveFullRank
  , lawDegenerateDirectionGivesEquality
  , lawCheckerboardDirectionCellBlind
  , lawStrictGapArbitraryDistinctAtUnitWeight
  , lawStrictConvexityNeedsValueWeightInBlindDirection
  , lawStrictlyConvexEveryDirectionAtPositiveWeight
  , lawTargetUniqueGlobalMinIffValueWeighted
  ) where

import SixFour.Spec.Convergence (composite, cellLoss, valueLoss, checkerboard)

-- A palette is 8 voxels x 3 OKLab channels (the same shape Convergence uses).
type Pal = [[Double]]

-- | numeric tolerance for EQUALITY assertions (closed-form matches, flat directions).
eps :: Double
eps = 1e-6

-- | strict-positivity noise floor for arbitrary distinct palettes: well BELOW the smallest genuine quadratic
-- gap a distinct (0.01-quantized) palette pair can produce (@½·0.09·0.0001 ≈ 4.5e-6@) yet far ABOVE float
-- round-off (@~1e-15@). An affine / merely-convex objective gives EXACTLY 0 along distinct endpoints and so
-- fails @> strictEps@ — this is the tooth that distinguishes STRICT from non-strict convexity.
strictEps :: Double
strictEps = 1e-9

-- | comfortable strict margin for CONSTRUCTED large-bump directions (@‖p−q‖² ≥ 1@).
posEps :: Double
posEps = 1e-3

-- bounded sample palettes from arbitrary doubles, mirroring Convergence.samp / ValueWeightThreshold.samp so
-- all three modules exercise the SAME well-conditioned (0.01-quantized) palette space.
samp :: [Double] -> Pal
samp = reshape24 . map (\x -> fromIntegral (round (x * 100) `mod` 200 - 100 :: Int) / 100)
  where reshape24 xs = [ take 3 (drop (3 * v) ys) | v <- [0 .. 7] ]
          where ys = take 24 (xs ++ repeat 0)

-- the convex combination @λ·p + (1−λ)·q@ (the chord's interior point).
lerpP :: Double -> Pal -> Pal -> Pal
lerpP l = zipWith (zipWith (\x y -> l * x + (1 - l) * y))

-- squared palette distance @‖p−q‖²@ (the value Hessian's quadratic form).
sqDist :: Pal -> Pal -> Double
sqDist p q = sum [ (a - b) * (a - b) | (rp, rq) <- zip p q, (a, b) <- zip rp rq ]

-- exact-equality test on palettes (distinctness guard).
palEq :: Pal -> Pal -> Bool
palEq p q = sqDist p q < 1e-12

-- a guaranteed-distinct perturbation (@‖·‖² ≥ amt²@): bump one channel of one voxel.
bumpAt :: Int -> Int -> Double -> Pal -> Pal
bumpAt vox ch amt p =
  [ [ if v == vox && c == ch then x + amt else x | (c, x) <- zip [0 :: Int ..] row ]
  | (v, row) <- zip [0 :: Int ..] p ]

-- the cell-blind checkerboard direction: add @cb@ to channel 0 (Convergence's null-space generator).
shiftedPal :: Pal -> Pal
shiftedPal t = [ [ (t !! v !! 0) + (checkerboard !! v), t !! v !! 1, t !! v !! 2 ] | v <- [0 .. 7] ]

clampLam :: Double -> Double
clampLam x = fromIntegral (round (x * 100) `mod` 81 + 10 :: Int) / 100     -- λ in [0.10, 0.90] ⊂ (0,1)

clampW :: Double -> Double
clampW x = fromIntegral (round (x * 10) `mod` 1000 - 500 :: Int) / 10       -- w in [-50.0, 49.9], both signs

-- ---------------------------------------------------------------------------
-- The exact Jensen gaps: chord_value − function_value (≥ 0 ⟺ convex; > 0 ⟺ strict here)
-- ---------------------------------------------------------------------------

-- | The Jensen gap of @composite w@ along @p,q@ at mix @λ@: @λ·f(p)+(1−λ)·f(q) − f(λp+(1−λ)q)@. For a
-- quadratic this equals @λ(1−λ)·½·(p−q)ᵀH(p−q)@ with @H@ the composite Hessian. @> 0@ ⟺ STRICTLY convex
-- along @p,q@.
jensenGapComposite :: Double -> Double -> Pal -> Pal -> Pal -> Double
jensenGapComposite w lam p q t =
  lam * composite w p t + (1 - lam) * composite w q t - composite w (lerpP lam p q) t

-- | The Jensen gap of the rank-deficient @cellLoss@. @≥ 0@ (convex), and @= 0@ in the cell-blind directions.
jensenGapCell :: Double -> Pal -> Pal -> Pal -> Double
jensenGapCell lam p q t =
  lam * cellLoss p t + (1 - lam) * cellLoss q t - cellLoss (lerpP lam p q) t

-- | The Jensen gap of the full-rank @valueLoss@. Equals @½·λ(1−λ)·‖p−q‖²@, @> 0@ for any distinct @p,q@.
jensenGapValue :: Double -> Pal -> Pal -> Pal -> Double
jensenGapValue lam p q t =
  lam * valueLoss p t + (1 - lam) * valueLoss q t - valueLoss (lerpP lam p q) t

-- ---------------------------------------------------------------------------
-- Laws (QuickCheck'd in Properties.GlobalUniqueness)
-- ---------------------------------------------------------------------------

-- | THE ENGINE: the composite Jensen gap SPLITS exactly as @jensenGapCell + w·jensenGapValue@ for EVERY
-- weight (both signs) — the convexity contributions are linear in @w@ because @composite = cell + w·value@
-- pointwise. This is the rank split made exact: the rank-deficient cell part and the full-rank value part
-- add. Teeth: an arbitrary weight @w@ (positive AND negative) and arbitrary @p,q,λ@ must satisfy the
-- identity to @eps@; a mis-stated combination (e.g. @w²@, or dropping the value term) fails.
lawJensenGapDecomposesByRank :: [Double] -> [Double] -> [Double] -> Double -> Double -> Bool
lawJensenGapDecomposesByRank pp qq tt lam0 w0 =
  let p = samp pp; q = samp qq; t = samp tt; lam = clampLam lam0; w = clampW w0
  in abs ( jensenGapComposite w lam p q t
           - (jensenGapCell lam p q t + w * jensenGapValue lam p q t) ) < eps

-- | THE FULL-RANK STRICTNESS: the value Jensen gap is STRICTLY positive for any distinct @p,q@ and equals
-- the closed form @½·λ(1−λ)·‖p−q‖²@ exactly. This is the term that makes the composite strictly convex.
-- Teeth: @> strictEps@ (a rank-deficient value Hessian — i.e. a value loss blind to some direction — would
-- give 0 and fail); AND it matches @½·λ(1−λ)·‖p−q‖²@ to @eps@, pinning it as the FULL-rank identity form.
lawValueGapStrictPositiveFullRank :: [Double] -> [Double] -> [Double] -> Double -> Bool
lawValueGapStrictPositiveFullRank pp qq tt lam0 =
  let p = samp pp; q0 = samp qq; t = samp tt; lam = clampLam lam0
      q = if palEq p q0 then bumpAt 3 1 1.0 q0 else q0   -- force distinctness only in the rare collision
      g = jensenGapValue lam p q t
  in g > strictEps
     && abs (g - 0.5 * lam * (1 - lam) * sqDist p q) < eps

-- | THE DEGENERATE CASE IS EXCLUDED (so the strict laws are not trivially satisfiable): when @p == q@ the
-- chord is a point, every Jensen gap is EXACTLY 0 (equality, NOT strict). The strict laws below all require
-- DISTINCT endpoints; this witnesses that equality is the right verdict precisely when they don't apply.
-- Teeth: all three gaps must be 0 to @eps@ for arbitrary weight and @λ@; a law that claimed @> 0@ here
-- (ignoring the @p ≠ q@ side condition) would be false.
lawDegenerateDirectionGivesEquality :: [Double] -> Double -> Double -> Bool
lawDegenerateDirectionGivesEquality pp lam0 w0 =
  let p = samp pp; lam = clampLam lam0; w = clampW w0
  in abs (jensenGapComposite w lam p p p) < eps
     && abs (jensenGapValue lam p p p) < eps
     && abs (jensenGapCell lam p p p) < eps

-- | THE NON-STRICT (FLAT) DIRECTION: the cell objective is only CONVEX, not strictly — along the cell-blind
-- checkerboard direction its Jensen gap is EXACTLY 0 even though the two palettes are genuinely DISTINCT
-- (@‖t − shifted‖² = Σ cb² = 8@). This is the direction that defeats uniqueness when the value term is off.
-- Teeth: @sqDist > posEps@ (non-vacuous — it really is a nonzero direction, not @p == q@ in disguise) AND
-- @jensenGapCell == 0@ (cell is flat); a full-rank cell objective would make this gap positive and fail.
lawCheckerboardDirectionCellBlind :: [Double] -> Double -> Bool
lawCheckerboardDirectionCellBlind tt lam0 =
  let t = samp tt; s = shiftedPal t; lam = clampLam lam0
  in sqDist t s > posEps
     && abs (jensenGapCell lam t s t) < eps

-- | TOOTH (a) — STRICT @<@ FOR ARBITRARY DISTINCT @p,q@ AT @w = 1@: the composite gap is STRICTLY positive
-- (@> strictEps@), i.e. @composite 1 (λp+(1−λ)q) t < λ·composite 1 p t + (1−λ)·composite 1 q t@, for
-- QuickCheck'd arbitrary distinct palettes. A merely-convex / affine objective gives EQUALITY (gap 0) and
-- fails. Teeth: distinctness is enforced (collision → bump), and @strictEps@ sits below the smallest genuine
-- distinct-pair gap but above float noise, so only a genuinely STRICTLY-convex objective passes.
lawStrictGapArbitraryDistinctAtUnitWeight :: [Double] -> [Double] -> [Double] -> Double -> Bool
lawStrictGapArbitraryDistinctAtUnitWeight pp qq tt lam0 =
  let p = samp pp; q0 = samp qq; t = samp tt; lam = clampLam lam0
      q = if palEq p q0 then bumpAt 3 1 1.0 q0 else q0
  in jensenGapComposite 1 lam p q t > strictEps

-- | TOOTH (b) — UNIQUENESS GENUINELY NEEDS @w > 0@, IN THE DIRECTION THE CELL TERM IS BLIND TO: along the
-- checkerboard direction (where the cell gap is 0), the composite gap is EXACTLY 0 at @w = 0@ (strict
-- convexity FAILS — a flat direction, non-unique min) but STRICTLY positive for every @w > 0@ (strictness
-- restored by the full-rank value term). Teeth: @w = 0@ gives equality to @eps@; the swept @w ∈
-- {0.001,0.1,1,5}@ all give @> strictEps@; and at @w = 1@ the gap matches the closed form @4·λ(1−λ)@
-- (@= 1·½·8·λ(1−λ)@), pinning the slope to the value Hessian. So the @w = 0@ tie is observably fatal and any
-- positive weight observably fixes it.
lawStrictConvexityNeedsValueWeightInBlindDirection :: [Double] -> Double -> Bool
lawStrictConvexityNeedsValueWeightInBlindDirection tt lam0 =
  let t = samp tt; s = shiftedPal t; lam = clampLam lam0
  in abs (jensenGapComposite 0 lam t s t) < eps
     && all (\w -> jensenGapComposite w lam t s t > strictEps) [0.001, 0.1, 1, 5]
     && abs (jensenGapComposite 1 lam t s t - 4 * lam * (1 - lam)) < eps

-- | STRICT CONVEXITY IN EVERY DIRECTION (not one witness) AT @w > 0@: for FOUR distinct directions off the
-- target — the cell-blind checkerboard plus three different single-voxel coordinate bumps — the composite
-- gap is strictly positive at @w = 1@. This is the breadth the original one-direction "uniqueness" lacked:
-- the min is strict whether the direction lies in the cell-blind complement OR the cell-visible subspace.
-- Teeth: each direction is non-vacuous (@sqDist > posEps@) and each gap @> posEps@; an objective flat in
-- ANY of these directions (non-unique min) fails.
lawStrictlyConvexEveryDirectionAtPositiveWeight :: [Double] -> Double -> Bool
lawStrictlyConvexEveryDirectionAtPositiveWeight tt lam0 =
  let t = samp tt; lam = clampLam lam0
      dirs = [ shiftedPal t, bumpAt 0 0 1.0 t, bumpAt 5 2 1.0 t, bumpAt 2 1 1.0 t ]
  in all (\d -> sqDist t d > posEps && jensenGapComposite 1 lam t d t > posEps) dirs

-- | TOOTH (d) + THE CAPSTONE CONSEQUENCE: the target achieves @composite = 0@ (a global min) at every
-- weight, and that global min is the UNIQUE one IFF @w > 0@. At @w = 1@ both a generic distinct palette AND
-- the cell-blind shifted palette are strictly positive (unique). At @w = 0@ the cell-blind shifted palette
-- TIES the target at @composite = 0@ (a second global minimizer — NOT unique). Teeth: the four
-- positive-weight strictness checks AND the @w = 0@ tie are all asserted, so the uniqueness claim is
-- observably conditional on @w > 0@, not a standalone assertion.
lawTargetUniqueGlobalMinIffValueWeighted :: [Double] -> Bool
lawTargetUniqueGlobalMinIffValueWeighted tt =
  let t = samp tt
      p = bumpAt 3 1 1.0 t          -- a generic distinct palette (cell-visible)
      s = shiftedPal t              -- the cell-blind distinct palette
  in composite 1 t t < eps                              -- target is a global min (loss 0) at w=1
     && composite 0 t t < eps                           -- ...and at w=0
     && composite 1 p t > posEps                        -- w>0: a distinct palette strictly loses (UNIQUE)
     && composite 1 s t > posEps                        -- ...including the cell-blind one (value restores strictness)
     && abs (composite 0 s t - composite 0 t t) < eps   -- w=0: the cell-blind palette TIES the target (NOT unique)

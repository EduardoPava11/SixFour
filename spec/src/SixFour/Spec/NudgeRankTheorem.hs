{- |
Module      : SixFour.Spec.NudgeRankTheorem
Description : THREE designed hypotheses turned into theorems — (1) the 9-pair nudge is RANK-honest at the CELL even though rank-1 per VOXEL, (2) the octant collapse folds the SPACE-TIME lattice while one OKLab CHANNEL rides as the value (a φ6 GAUGE choice, not an intrinsic fact), (3) the down-rung residual is a self-similar PRIOR for the up-rung invention (reuse-as-seed) but NOT the answer (refutes copy-as-ground-truth).

This module is the algebraic settling of three questions that all live at the same
seam — the rank/DOF of the comparison object, what the octant operator actually
collapses, and whether the exact down-residual can drive the invented up-residual.
Nothing is re-derived: every law REUSES an already-proven organ and pins the new
fact as a non-vacuous witness.

== H1 — RANK (the 9-pair nudge: honest at the cell, degenerate at the voxel)

Per voxel @M(v) = colorVec(v) ⊗ spaceVec(v)@ is one integer outer product, so
@rank ≤ 1@ (every 2×2 minor vanishes — the GIF89a separability of
"SixFour.Spec.ChannelProduct" @lawComparisonIsSeparable@; the honest DOF count is the
6-D P6 generator, "SixFour.Spec.MatrixTarget" @lawGeneratorIsSixNotNine@). The CELL
aggregate @A = Σ_v colorVec(v) ⊗ spaceVec(v) = C·Sᵀ@ has @rank ≤ min(rank C, rank S) ≤ 3@,
and that bound is ACHIEVED (3 voxels on the φ6 diagonal already give @A = I@, det 1).
So the off-diagonal chroma×space channels are independently addressable AT THE CELL
('lawCellAggregateReachesRank3', 'lawNineIndependentAtCellNotVoxel') but NOT at the
voxel ('lawSingleVoxelRank1'). Consequence: the held-out 'MatrixTarget' supervision
must be the full-rank cell-aggregate, NOT a per-voxel rank-1 matrix and NOT a sum of
per-voxel losses ('lawHeldOutLossIsCellAggregateNotPerVoxel', lifting
@MatrixTarget.lawMatrixLossSeesOffDiagonal@ from the L-row blind spot to the
cross-voxel chroma×space coupling).

== H2 — COLLAPSE (which structure is folded, which is the value)

The octant axes ARE the space-time lattice @(x,y,t)@: @liftOct@ factors EXACTLY as
two spatial @liftQuad@ xy-Haars (one per t-face) + one temporal @sLift@ t-Haar
('lawOctantAxesAreSpaceTime'). The lifted @Int@ payload is ONE OKLab channel value,
and @L,a,b@ collapse by three INDEPENDENT @liftOct@ passes — colour rides as the
value, never an octant axis ('lawColourIsTheLiftedValue'). The 64³→16³ rung is two
octant levels collapsing space-time /4 per linear dim while the channel survives
losslessly ('lawTwoLevelsCollapseSpaceTimeNotColour'). ANSWER to "is one level
spatial, one temporal": NO — each single level mixes BOTH axes and the two levels
are the identical self-similar operator ('lawBothLevelsAreMixedSpaceTime', which
CONFIRMS "both mixed" and REFUTES any spatial-then-temporal factoring). CAVEAT
(the real subtlety): "colour is the value / space-time is collapsed" is a φ6 GAUGE
choice, not intrinsic — φ6 exchanges the colour and space cubes
("SixFour.Spec.DualCube" @lawCubesExchangedByPhi6@), so the dual reading is equally
valid ('lawValueSplitIsPhi6Gauge', which REFUTES the naive "colour is intrinsically
the value").

== H3 — RESIDUAL REUSE (self-similar prior, not a copy of the answer)

The down-residual (16³→64³ held band) and the up-residual (64³→256³ invented band)
are the SAME @[[Detail]]@ type consumed by the SAME operator
("SixFour.Spec.SelfSimilarReconstruct" @octantLift@), because each rung spans 2
octant levels ('lawResidualTypeScaleInvariant'). Both inhabit the SAME root lattice
@A₇ = ker Σ@ at every level ("SixFour.Spec.RootLatticeDetail",
'lawResidualIsA7AtEveryLevel'). So a captured down-residual is a TYPE-LEGAL,
information-positive conditioning SEED for the up-invention — strictly richer than
the zero floor ('lawDownResidualConditionsUpInvention'). BUT it is NOT the exact
up-residual: copying it as ground truth would make capture↦256³ injective, which is
FALSE ("SixFour.Spec.SelfSimilarReconstruct" @lawBeyondCaptureInvented@:
two latent tails on one cube64 give distinct 256³). So reuse = a self-similar prior
to be refined and re-entered via @reenterQ16@, NEVER a copy
('lawDownResidualIsNotUpGroundTruth', the honest boundary that keeps
'lawResidualTypeScaleInvariant' from over-claiming).

Pure-spec, emits no golden. Laws are exported predicates, QuickCheck'd in
@Properties.NudgeRankTheorem@.
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none
module SixFour.Spec.NudgeRankTheorem
  ( -- * Matrix helpers (the cell-aggregate cross-form A = Σ colour ⊗ space)
    outerI
  , cellAggregate
  , matAddI
  , det3
  , minor2
  , aggSqLoss
  , allMinors2Zero
    -- * H1 — RANK
  , lawSingleVoxelRank1
  , lawSingleVoxelRank1Everywhere
  , lawTwoVoxelAggregateIsSingular
  , lawRank3ReachableAtEveryScale
  , lawCellAggregateReachesRank3
  , lawNineIndependentAtCellNotVoxel
  , lawHeldOutLossIsCellAggregateNotPerVoxel
    -- * H2 — COLLAPSE
  , lawOctantAxesAreSpaceTime
  , lawColourIsTheLiftedValue
  , lawTwoLevelsCollapseSpaceTimeNotColour
  , lawBothLevelsAreMixedSpaceTime
  , lawValueSplitIsPhi6Gauge
    -- * H3 — RESIDUAL REUSE
  , lawResidualTypeScaleInvariant
  , lawResidualIsA7AtEveryLevel
  , lawDownResidualConditionsUpInvention
  , lawDownResidualIsNotUpGroundTruth
  ) where

import SixFour.Spec.DualCube              (P6(..), lawCubesExchangedByPhi6, lawNoPrivilegedCarrier)
import SixFour.Spec.ChannelProduct        (colorVec, spaceVec, compareMatrix, lawComparisonIsSeparable)
import SixFour.Spec.RGBTLift              (liftQuad)
import SixFour.Spec.OctreeCell
  ( V8(..), OctBand(..), Detail, liftOct, detailToList
  , octantDistill, octantSynthesize, levelsBetween )
import SixFour.Spec.SelfSimilarReconstruct
  ( DetailSource(..), detailBands, octantLift
  , lawSameOperatorBothRungs, lawBeyondCaptureInvented )
import SixFour.Spec.RootLatticeDetail     (fromRootCoords, inA, numDetailBands, lawOctantIsA7)

-- ---------------------------------------------------------------------------
-- Matrix helpers: the cell-aggregate cross-form A = Σ_v colour(v) ⊗ space(v)
-- ---------------------------------------------------------------------------

-- | The integer outer product @c ⊗ s@ (one voxel's rank-1 comparison matrix).
outerI :: [Integer] -> [Integer] -> [[Integer]]
outerI cs ss = [ [ c * s | s <- ss ] | c <- cs ]

-- | The 3×3 zero matrix.
zero3 :: [[Integer]]
zero3 = replicate 3 (replicate 3 0)

-- | Entrywise matrix addition.
matAddI :: [[Integer]] -> [[Integer]] -> [[Integer]]
matAddI = zipWith (zipWith (+))

-- | The CELL aggregate: the sum over the cell's voxels of each voxel's rank-1 outer
-- product @colorVec(v) ⊗ spaceVec(v)@ — the cross-covariance / Gram cross-form
-- @A = C·Sᵀ@. (Note @compareMatrix v == outerI (colorVec v) (spaceVec v)@.)
cellAggregate :: [P6] -> [[Integer]]
cellAggregate = foldr (\v acc -> matAddI (outerI (colorVec v) (spaceVec v)) acc) zero3

-- | The 3×3 determinant (rank-3 witness: @det ≠ 0 ⇒ full rank@).
det3 :: [[Integer]] -> Integer
det3 [[a,b,c],[d,e,f],[g,h,i]] =
  a * (e*i - f*h) - b * (d*i - f*g) + c * (d*h - e*g)
det3 _ = 0

-- | The 2×2 minor on rows @i,i'@ and columns @j,j'@ (a non-zero minor ⇒ @rank ≥ 2@).
minor2 :: [[Integer]] -> Int -> Int -> Int -> Int -> Integer
minor2 m i i' j j' =
  at i j * at i' j' - at i j' * at i' j
  where at r c = (m !! r) !! c

-- | All 2×2 minors vanish (the rank-≤1 / separability test).
allMinors2Zero :: [[Integer]] -> Bool
allMinors2Zero m =
  and [ minor2 m i i' j j' == 0
      | i <- [0..2], i' <- [0..2], j <- [0..2], j' <- [0..2] ]

-- | Summed squared error over all 9 aggregate cells (the held-out matrix loss
-- measured ON the cell-aggregate, not piecewise per voxel).
aggSqLoss :: [[Integer]] -> [[Integer]] -> Integer
aggSqLoss a b =
  sum [ (x - y) * (x - y) | (ra, rb) <- zip a b, (x, y) <- zip ra rb ]

-- ===========================================================================
-- H1 — RANK: honest at the cell, degenerate at the voxel
-- ===========================================================================

-- | A SINGLE voxel's comparison matrix is rank ≤ 1: every 2×2 minor vanishes, so the
-- 9 cells are fixed by the 6-DOF generator @(a,b,L,x,y,t)@ — the off-diagonal
-- chroma×space cells are NOT independently movable per voxel. This is exactly
-- @ChannelProduct.lawComparisonIsSeparable@ restated as a rank ceiling. CONFIRMS.
lawSingleVoxelRank1 :: Bool
lawSingleVoxelRank1 =
  let p = P6 5 1 2 3 4 6                                -- L=5,a=1,b=2,x=3,y=4,t=6
      m = compareMatrix p                               -- == [[3,4,6],[6,8,12],[15,20,30]]
  in m == outerI (colorVec p) (spaceVec p)              -- it IS a single outer product
     && allMinors2Zero m                                -- rank ≤ 1
     && lawComparisonIsSeparable p                      -- reuse the proven separability

-- | QUANTIFIED RANK CEILING (2026-07-03, audit G2): the rank-≤1 verdict holds at EVERY voxel,
-- not at one hand-built witness — for ALL @P6@, the comparison matrix IS the outer product
-- @colorVec ⊗ spaceVec@ and every 2×2 minor vanishes. This is the theorem
-- 'lawSingleVoxelRank1' witnesses, now universally quantified.
lawSingleVoxelRank1Everywhere :: Integer -> Integer -> Integer -> Integer -> Integer -> Integer -> Bool
lawSingleVoxelRank1Everywhere l a b x y t =
  let p = P6 l a b x y t
      m = compareMatrix p
  in m == outerI (colorVec p) (spaceVec p) && allMinors2Zero m

-- | QUANTIFIED MINIMALITY (2026-07-03, audit G2): the OTHER half of "minimum voxels for rank 3
-- is exactly 3", previously prose — a TWO-voxel aggregate is ALWAYS singular (a sum of two
-- rank-1 outer products has rank ≤ 2, so @det3 == 0@), for all pairs of voxels. Together with
-- 'lawRank3ReachableAtEveryScale' this pins the minimum at exactly 3 as a law, not a comment.
lawTwoVoxelAggregateIsSingular :: [Integer] -> [Integer] -> Bool
lawTwoVoxelAggregateIsSingular u v =
  det3 (cellAggregate [mkP6 u, mkP6 v]) == 0
  where mkP6 ws = case ws ++ repeat 0 of
          (l:a:b:x:y:t:_) -> P6 l a b x y t
          _               -> P6 0 0 0 0 0 0   -- unreachable (the padded list is infinite)

-- | QUANTIFIED REACHABILITY (2026-07-03, audit G2): rank 3 is reached at EVERY scale, not just
-- by the unit witness — the φ6-paired family @{(a,x), (b,y), (L,t)}@ aggregates to
-- @diag(a·x, b·y, L·t)@ with @det = a·x·b·y·L·t ≠ 0@ for any nonzero components. The 9-channel
-- cell surface is honest for arbitrarily large (and mixed-sign) paint magnitudes.
lawRank3ReachableAtEveryScale :: Integer -> Integer -> Integer -> Integer -> Integer -> Integer -> Bool
lawRank3ReachableAtEveryScale a0 b0 l0 x0 y0 t0 =
  let nz w = if w == 0 then 1 else w
      (a, b, l, x, y, t) = (nz a0, nz b0, nz l0, nz x0, nz y0, nz t0)
      agg = cellAggregate [ P6 0 a 0 x 0 0, P6 0 0 b 0 y 0, P6 l 0 0 0 0 t ]
  in agg == [[a*x, 0, 0], [0, b*y, 0], [0, 0, l*t]]
     && det3 agg == a*x * b*y * l*t
     && det3 agg /= 0

-- | The CELL aggregate of ≥3 generic voxels reaches FULL RANK 3 (non-zero 3×3 det),
-- so the cell has 9 genuinely independent comparison entries. Minimum voxels for
-- rank 3 is exactly 3 (a sum of k rank-1 terms has rank ≤ k); one voxel per
-- φ6-fixed pair already suffices and gives @A = I@. CONFIRMS.
lawCellAggregateReachesRank3 :: Bool
lawCellAggregateReachesRank3 =
  let v1 = P6 0 1 0 1 0 0      -- a=1,x=1 → colorVec [1,0,0], spaceVec [1,0,0] → E(A,X)
      v2 = P6 0 0 1 0 1 0      -- b=1,y=1 → E(B,Y)
      v3 = P6 1 0 0 0 0 1      -- L=1,t=1 → E(L,T)
      a  = cellAggregate [v1, v2, v3]
  in a == [[1,0,0],[0,1,0],[0,0,1]]                     -- the 3×3 identity
     && det3 a == 1                                     -- rank 3, 9 independent entries

-- | The 9 channels are independently nudgeable AT THE CELL but degenerate AT THE
-- VOXEL: the same chroma×space comparison family gives opposite rank verdicts. The
-- minor test is the witness — voxel: all 2×2 minors 0 (rank 1); cell: a non-zero
-- 2×2 minor (rank ≥ 2) AND a non-zero det (rank 3). So the 9-DOF nudge lives at the
-- cell, not the voxel. CONFIRMS.
lawNineIndependentAtCellNotVoxel :: Bool
lawNineIndependentAtCellNotVoxel =
  let voxel = compareMatrix (P6 5 1 2 3 4 6)
      cell  = cellAggregate [P6 0 1 0 1 0 0, P6 0 0 1 0 1 0, P6 1 0 0 0 0 1]
  in allMinors2Zero voxel                               -- voxel: rank 1 (every minor 0)
     && minor2 voxel 0 1 0 1 == 0                        -- (named) the top-left voxel minor IS 0
     && minor2 cell  0 1 0 1 == 1                        -- cell: a non-zero 2×2 minor ⇒ rank ≥ 2
     && det3 cell == 1                                   -- cell: non-zero det ⇒ rank 3

-- | The held-out 'MatrixTarget' loss must be measured on the full-rank CELL-AGGREGATE,
-- NOT on per-voxel rank-1 matrices and NOT recovered as a sum of per-voxel losses.
-- Witness: a prediction that reuses the SAME three unit rank-1 magnitudes but MISPAIRS
-- chroma with space (the off-diagonal swap) is invisible to any per-voxel / magnitude
-- view (each predicted voxel is STILL a valid unit rank-1 outer product, all minors 0)
-- yet the aggregate loss SEES it (@aggSqLoss = 4 > 0@). Lifts
-- @MatrixTarget.lawMatrixLossSeesOffDiagonal@ from the per-voxel L-row blind spot to
-- the cross-voxel chroma×space coupling. CONFIRMS.
lawHeldOutLossIsCellAggregateNotPerVoxel :: Bool
lawHeldOutLossIsCellAggregateNotPerVoxel =
  let tgtVoxels  = [P6 0 1 0 1 0 0, P6 0 0 1 0 1 0, P6 1 0 0 0 0 1]  -- aggregate = I
      predVoxels = [P6 0 1 0 0 1 0, P6 0 0 1 1 0 0, P6 1 0 0 0 0 1]  -- mispaired chroma↔space
      aTgt  = cellAggregate tgtVoxels
      aPred = cellAggregate predVoxels
  in aTgt == [[1,0,0],[0,1,0],[0,0,1]]
     && aPred == [[0,1,0],[1,0,0],[0,0,1]]               -- still rank 3, but ≠ I
     && det3 aPred == (-1)
     -- the AGGREGATE loss sees the mispaired off-diagonal coupling:
     && aggSqLoss aPred aTgt == 4
     -- ...while EVERY predicted voxel is itself a locally-honest unit rank-1 matrix
     -- (all 2×2 minors 0), so a per-voxel / magnitude-only view cannot distinguish it:
     && all (allMinors2Zero . compareMatrix) predVoxels

-- ===========================================================================
-- H2 — COLLAPSE: space-time is folded, one OKLab channel is the value (a φ6 gauge)
-- ===========================================================================

-- | The local S-transform along the t (z) axis (same floor convention as
-- "SixFour.Spec.OctreeCell"; kept local because @sLift@ is not exported).
sLiftLocal :: Int -> Int -> (Int, Int)
sLiftLocal x y = let d = x - y in (y + (d `div` 2), d)

-- | The 8 octant children are the space-time lattice @(x,y,t)@: @liftOct@ factors
-- EXACTLY as two spatial @liftQuad@ xy-Haars (one per t-face) followed by one
-- temporal @sLift@ t-Haar. CONFIRMS — the octant axes are demonstrably @(x,y,t)@.
lawOctantAxesAreSpaceTime :: Bool
lawOctantAxesAreSpaceTime =
  let v8 = V8 1 2 3 4 5 6 7 8
      (r0,g0,b0,t0) = liftQuad (1,2,3,4)     -- t=0 (near-z) xy-face Haar  (SPATIAL)
      (r1,g1,b1,t1) = liftQuad (5,6,7,8)     -- t=1 (far-z)  xy-face Haar  (SPATIAL)
      (rr, dz)      = sLiftLocal r0 r1        -- t-axis Haar on the two DCs (TEMPORAL)
      expected      = OctBand rr (g0,b0,t0, g1,b1,t1, dz)
  in liftOct v8 == expected

-- | The lifted @Int@ payload is ONE OKLab channel value; @L,a,b@ collapse by three
-- INDEPENDENT @liftOct@ passes — colour is the value that rides through, never an
-- octant axis. Witness: perturbing the @a@-channel cube leaves the @L@-channel band
-- untouched, and the @L@ band is just @liftOct@ on the @L@ cube. CONFIRMS.
lawColourIsTheLiftedValue :: Bool
lawColourIsTheLiftedValue =
  let lCube  = V8 1 2 3 4 5 6 7 8
      aCube  = V8 9 9 9 9 9 9 9 9
      aCube' = V8 0 1 2 3 4 5 6 7        -- perturb ONLY the a channel
      bCube  = V8 0 0 0 0 0 0 0 0
      lift3 l a b = map liftOct [l, a, b]
  in (lift3 lCube aCube bCube !! 0) == (lift3 lCube aCube' bCube !! 0)   -- L band ⟂ a cube
     && liftOct lCube == (lift3 lCube aCube bCube !! 0)                  -- L band = liftOct(L cube)
     && (lift3 lCube aCube bCube !! 1) /= (lift3 lCube aCube' bCube !! 1) -- the a band DID move

-- | The 64³→16³ rung is two octant levels (each halves x,y AND t, ×64 volume) while
-- the colour channel rides through LOSSLESSLY: @octantSynthesize ∘ octantDistill 2 ≡ id@
-- on one channel's voxel list. The residual is the SPACE-TIME detail of a fixed
-- colour channel; colour is not collapsed, it indexes which cube you lift. CONFIRMS.
lawTwoLevelsCollapseSpaceTimeNotColour :: Bool
lawTwoLevelsCollapseSpaceTimeNotColour =
  let sample = take (8 ^ (2 :: Int)) [0 ..] :: [Int]      -- one channel's 64-voxel cube
  in levelsBetween 64 16 == 2
     && octantSynthesize (octantDistill 2 sample) == sample

-- | ANSWER to "one level spatial, one level temporal": NO. A SINGLE octant level
-- already mixes BOTH axes (a difference across the two t-faces moves the temporal
-- band @dz@; a difference within one xy-face moves a spatial band), and the two
-- levels are the IDENTICAL self-similar operator. CONFIRMS "both mixed" and REFUTES
-- any spatial-then-temporal factoring.
lawBothLevelsAreMixedSpaceTime :: Bool
lawBothLevelsAreMixedSpaceTime =
  let base           = liftOct (V8 0 0 0 0 0 0 0 0)
      temporalTouch  = liftOct (V8 0 0 0 0 1 1 1 1) /= base   -- t-face difference ⇒ dz moves
      spatialTouch   = liftOct (V8 1 0 0 0 0 0 0 0) /= base   -- xy difference (one t-face) moves a band
  in levelsBetween 64 16 == 2
     && levelsBetween 256 64 == 2
     && levelsBetween 64 16 == levelsBetween 256 64           -- identical self-similar operator
     && temporalTouch && spatialTouch                          -- BOTH axes touched WITHIN one level

-- | The "space-time is collapsed / colour is the value" split is a φ6 GAUGE choice,
-- not intrinsic. φ6 (@L↔t, a↔x, b↔y@) is a ℤ⁶-module automorphism that EXCHANGES
-- the colour and space cubes, so the dual reading (collapse colour, keep space-time)
-- is equally valid. REFUTES the naive "colour is intrinsically the value"; confirms
-- it is a gauge the per-channel @liftOct@ happens to fix. Reuses
-- @DualCube.lawCubesExchangedByPhi6@ / @lawNoPrivilegedCarrier@.
lawValueSplitIsPhi6Gauge :: Bool
lawValueSplitIsPhi6Gauge =
  let p = P6 5 1 2 3 4 6
  in lawCubesExchangedByPhi6 p     -- colorCube (phi6 p) == spaceCube p (and vice versa)
     && lawNoPrivilegedCarrier p   -- L-of-colour == t-after-φ6 ⇒ no canonical carrier

-- ===========================================================================
-- H3 — RESIDUAL REUSE: self-similar prior, not a copy of the answer
-- ===========================================================================

-- | The down-rung residual (16³→64³ held band) and the up-rung residual (64³→256³
-- invented band) are the SAME @[[Detail]]@ type consumed by the SAME source-agnostic
-- operator @octantLift@, because each rung spans 2 octant levels. Reuses the proven
-- @SelfSimilarReconstruct.lawSameOperatorBothRungs@: @octantLift@ on a Held source and
-- on an Invented source is the identical function. CONFIRMS (true by construction).
lawResidualTypeScaleInvariant :: Bool
lawResidualTypeScaleInvariant =
  let coarse = [10,20,30,40,50,60,70,80] :: [Int]
      det    = [[(1,2,3,4,5,6,7)]] :: [[Detail]]
  in lawSameOperatorBothRungs coarse det
     -- (explicit) the SAME band type flows through both arms of DetailSource:
     && octantLift coarse (detailBands (Held det))
          == octantLift coarse (detailBands (Invented det))

-- | At EVERY octree level the 7-band residual is membership in the root lattice
-- @A₇ = ker Σ ⊂ ℤ⁸@: any length-7 'Detail' embeds (via @fromRootCoords 8@) into the
-- mean-free kernel. Since A₇-membership is an algebraic identity in the branching
-- b=8 (independent of which level the band sits at), the down-residual and
-- up-residual inhabit the SAME lattice. Teeth: a non-mean-free ℤ⁸ vector is NOT in
-- A₇. Reuses @RootLatticeDetail.lawOctantIsA7@. CONFIRMS.
lawResidualIsA7AtEveryLevel :: Bool
lawResidualIsA7AtEveryLevel =
  let downBand = ( 1,-1, 0, 0, 0, 0, 0) :: Detail   -- a 16→64 held residual
      upBand   = ( 3,-1,-2, 5,-5, 0, 0) :: Detail   -- a 64→256 invented residual
      embed d  = fromRootCoords 8 (map fromIntegral (detailToList d))
  in lawOctantIsA7
     && numDetailBands 8 == 7
     && inA (embed downBand)                              -- down residual ∈ A₇
     && inA (embed upBand)                                -- up residual ∈ the SAME A₇
     && length (detailToList downBand) == length (detailToList upBand)  -- same rank both levels
     && not (inA (1 : replicate 7 0))                    -- TEETH: e₀ (sum 1) is NOT in A₇

-- | The down-residual is a LEGITIMATE conditioning seed for the up-invention: feeding
-- a real captured held band into the SAME @octantLift@ type-checks, runs, and (when
-- the band is nonzero) yields a reconstruction STRICTLY richer than the zero-detail
-- floor (@SelfSimilarReconstruct.synthBeyond@). So the data-grounded down-residual is
-- a better prior than the zero tail the net otherwise starts from. CONFIRMS the
-- reuse-as-seed reading.
lawDownResidualConditionsUpInvention :: Bool
lawDownResidualConditionsUpInvention =
  let cube64   = [5] :: [Int]
      heldBand = [[(3,1,4,1,5,9,2)]] :: [[Detail]]   -- a real captured down residual (nonzero)
      floorDet = [[(0,0,0,0,0,0,0)]] :: [[Detail]]   -- the zero-detail floor
  in octantLift cube64 heldBand /= octantLift cube64 floorDet

-- | THE HONEST BOUNDARY: the down-residual is a scale-SHIFTED prior, NOT the exact
-- up-residual. Copying the 16→64 band into the 64→256 slot as ground truth would make
-- capture↦256³ injective — which is FALSE: two distinct latent tails on the SAME
-- cube64 give distinct 256³ (@SelfSimilarReconstruct.lawBeyondCaptureInvented@). A
-- copied down-residual is just one tail among infinitely many ⇒ generically wrong.
-- REFUTES "copy the residual as the invented detail"; keeps
-- 'lawResidualTypeScaleInvariant' from over-claiming. Reuse = a prior to be refined
-- and re-entered via @reenterQ16@, never a copy.
lawDownResidualIsNotUpGroundTruth :: Bool
lawDownResidualIsNotUpGroundTruth =
  let cube64 = [3,1,4,1,5,9,2,6] :: [Int]
  in lawBeyondCaptureInvented cube64

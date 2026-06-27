{- |
Module      : SixFour.Spec.LearnabilityTheorem
Description : THE LEARNABILITY THEOREM — a single capstone law 'lawModelWillLearn' proving, as a theorem over the project's discrete-geometry + algebraic-number-theory substrate, that θ_B + the value head WILL learn the data-manufactured target. The proof walks the STATISTICAL moment ladder (mean < variance/covariance < higher moments < the full distribution) and pivots on the cell aggregate @A = C·Sᵀ = Σ_v colour(v) ⊗ space(v)@ — literally the 2nd CROSS-MOMENT (cross-covariance) between colour and the data-fixed octant space lattice.

The capstone is the conjunction of five delegated, already-green conjuncts plus ONE net-new
identifiability completion:

  SIGNAL ∧ EXPRESSIVITY ∧ IDENTIFIABILITY ∧ DESCENT ∧ NO-COLLAPSE  ⇒  the model WILL learn,
  conditional on the value-head weight @w_value > 0@.

The five delegated conjuncts (each a green law of an existing module):

  * SIGNAL ('lawLearnableSignalExists') — there is detail energy above the root-lattice floor in at
    least one of the owner's two lenses (the @d6@\/@ℓ¹@ lattice norm on L = DISCRETE GEOMETRY, the
    @ℤ[i]@ Gaussian field norm on chroma = ALGEBRAIC NUMBER THEORY). Delegates
    "SixFour.Spec.AnchorDiagnostic". The Flat scene (both lenses at the floor) is the boundary tooth:
    a degenerate corpus has NOTHING to learn.
  * EXPRESSIVITY ('lawTargetExpressibleAboveFloor') — the target lives in the head's codomain
    @A₇ = ker Σ ⊂ ℤ⁸@ and a ≥1-LSB invented coefficient survives the Q16 commit and moves the output
    off the deterministic floor. Delegates "SixFour.Spec.AboveFloorMargin" + "SixFour.Spec.RootLatticeDetail".
  * IDENTIFIABILITY-rank3 ('lawCellLossIdentifiesRank3Subspace') — the trained loss @cellLoss@ on the
    2nd cross-moment @A@ (full column rank @S@ = 3 ⇒ @A@ rank ≤ 3) is a SUFFICIENT STATISTIC for
    exactly the rank-3 projection of the palette onto @span(S)@ (the 9 aggregate entries), the honest
    cell-aggregate not a per-voxel rank-1 sum. Delegates "SixFour.Spec.MatrixTarget" +
    "SixFour.Spec.NudgeRankTheorem".
  * DESCENT ('lawDescentReachesGoldenByteExact') — @trainBandJoint@ drives the loss monotonically to a
    tiny fraction of the floor loss and recovers the golden committed band @3000@ byte-exact. Delegates
    "SixFour.Spec.MaskedBandTrainer".
  * NO-COLLAPSE ('lawNoCollapseKeepsCrossMomentFullRank') — the VICReg per-factor std hinge keeps both
    factors of @A@ above a variance floor, so @A@ stays rank-3 and the sufficient statistic stays
    informative. Delegates "SixFour.Spec.VarianceFloorGuard".

The ONE net-new piece ('lawValueHeadIdentifiesComplement') is the heart of the improvement: @cellLoss@
is rank-DEFICIENT — it is exactly ANCILLARY on the 15-DOF orthogonal complement of @span(S)@ (the
balanced \/ checkerboard within-octant patterns). The witness is the @ℤ⁸@ checkerboard PARITY vector
@cb = [1,-1,-1,1,-1,1,1,-1] = (-1)^(x+y+t)@ over the eight @{0,1}³@ octant corners. @cb@ is orthogonal
to every column of @S@ (the @x@, @y@, @t@ space coordinates) AND to the constant @1@ direction, so
perturbing the palette's @a@-channel by @cb@ leaves the cross-moment @A@ — and hence @cellLoss@ —
EXACTLY unchanged (blind), while the palette genuinely differs. The value (palette) head, supervised by
the OKLab regression @valueLoss@ with weight @w_value > 0@, is a sufficient statistic for that
complement, so the PAIR @(cellLoss, w_value·valueLoss)@ jointly identifies the full palette. Hence
full-palette learnability is CONDITIONAL on @w_value > 0@; the capstone is TRUE at @w_value = 1@ and
FALSE at @w_value = 0@ (the current trainer default), proving the side condition is load-bearing.

Pure-spec, emits no golden (the goldens are the delegated modules' exported constants). Laws @once@- /
QuickCheck'd in "Properties.LearnabilityTheorem".
-}
-- COMPARTMENT: MLX-MODEL | tag:MacTag
module SixFour.Spec.LearnabilityTheorem
  ( -- * The statistical degrees-of-freedom split (the rank-3 / complement accounting)
    identifiedDof
  , blindDof
  , totalColourDof
    -- * The checkerboard-parity complement witness (the value-head teeth)
  , checkerboardParity
  , octantCorners
  , complementIdentifiedAt
    -- * The six conjuncts of the theorem
  , lawLearnableSignalExists
  , lawTargetExpressibleAboveFloor
  , lawCellLossIdentifiesRank3Subspace
  , lawValueHeadIdentifiesComplement
  , lawDescentReachesGoldenByteExact
  , lawNoCollapseKeepsCrossMomentFullRank
    -- * The capstone
  , willLearn
  , lawModelWillLearn
  ) where

import SixFour.Spec.DualCube            (P6(..))
import SixFour.Spec.MatrixTarget        (cellLoss)
import SixFour.Spec.NudgeRankTheorem    (cellAggregate, det3)
import SixFour.Spec.HierarchicalDelta   (ColourDelta(..))
import SixFour.Spec.DeltaSurrogate      (ValueSurrogate, embedValue, valueLoss)

import qualified SixFour.Spec.AnchorDiagnostic  as Anchor
import qualified SixFour.Spec.AboveFloorMargin  as Margin
import qualified SixFour.Spec.RootLatticeDetail as Root
import qualified SixFour.Spec.MatrixTarget      as MT
import qualified SixFour.Spec.NudgeRankTheorem  as NR
import qualified SixFour.Spec.MaskedBandTrainer as Trainer
import qualified SixFour.Spec.VarianceFloorGuard as Guard

-- ===========================================================================
-- The statistical DOF accounting: 9 identified (rank-3 cross-moment) + 15 blind
-- ===========================================================================

-- | The colour degrees of freedom the cross-moment @A = C·Sᵀ@ IDENTIFIES: the 9 entries of the
-- rank-3 (3×3) cell aggregate — the projection of the palette onto @span(S)@.
identifiedDof :: Int
identifiedDof = 9

-- | The colour degrees of freedom @cellLoss@ is BLIND to: the orthogonal complement of @span(S)@,
-- @totalColourDof - identifiedDof = 24 - 9 = 15@ (the balanced \/ checkerboard within-octant patterns
-- across the 3 colour channels). Only the value head can identify these.
blindDof :: Int
blindDof = totalColourDof - identifiedDof

-- | The full palette colour degrees of freedom of one octant: 8 voxels × 3 OKLab channels = 24.
totalColourDof :: Int
totalColourDof = 8 * 3

-- ===========================================================================
-- The checkerboard-parity complement witness (the value-head identifiability teeth)
-- ===========================================================================

-- | The eight octant corners @(x,y,t) ∈ {0,1}³@ — the rows of the data-fixed space lattice @S@.
octantCorners :: [(Integer, Integer, Integer)]
octantCorners =
  [ (0,0,0), (1,0,0), (0,1,0), (1,1,0)
  , (0,0,1), (1,0,1), (0,1,1), (1,1,1) ]

-- | The checkerboard PARITY vector @(-1)^(x+y+t)@ over 'octantCorners': @[1,-1,-1,1,-1,1,1,-1]@. It is
-- orthogonal to every column of @S@ (the @x@,@y@,@t@ coordinates) AND to the constant @1@ direction,
-- so it lives ENTIRELY in the orthogonal complement of @span(S)@ — the subspace @cellLoss@ cannot see.
checkerboardParity :: [Integer]
checkerboardParity = [ if even (x + y + t) then 1 else -1 | (x,y,t) <- octantCorners ]

-- | The TARGET octant cell: a constant @a@-channel base of @2@, @L = b = 0@, on the eight corners
-- (@P6 L a b x y t@). Its cross-moment @A@ is the reference the held-out supervision scores.
tgtCell :: [P6]
tgtCell = [ P6 0 2 0 x y t | (x,y,t) <- octantCorners ]

-- | The COMPLEMENT-perturbed cell: the @a@-channel of each voxel shifted by 'checkerboardParity'. Since
-- @cb · S = 0@, this changes @A@ in NO entry — @cellLoss@ is blind — yet the palette genuinely differs.
predCellComplement :: [P6]
predCellComplement =
  [ P6 0 (2 + d) 0 x y t | ((x,y,t), d) <- zip octantCorners checkerboardParity ]

-- | An IN-SUBSPACE perturbed cell: the @a@-channel shifted by the @x@ coordinate itself (a column of
-- @S@, so IN @span(S)@). This moves @A@ (@Σ x² = 4 ≠ 0@) and @cellLoss@ SEES it — proving @cellLoss@ is
-- a genuine partial sufficient statistic on the rank-3 subspace, not blind to everything.
predCellSubspace :: [P6]
predCellSubspace = [ P6 0 (2 + x) 0 x y t | (x,y,t) <- octantCorners ]

-- | The value head's TARGET palette as a 'ColourDelta' (per-voxel OKLab @(L,a,b)@).
tgtPalette :: ColourDelta
tgtPalette = ColourDelta [ (0, 2, 0) | _ <- octantCorners ]

-- | The value head's COMPLEMENT-perturbed palette surrogate (the @a@-channel shifted by @cb@). The
-- regression @valueLoss@ against 'tgtPalette' is @Σ cb² = 8 > 0@: the value head SEES what @cellLoss@
-- cannot.
predPaletteComplement :: ValueSurrogate
predPaletteComplement =
  embedValue (ColourDelta [ (0, 2 + fromIntegral d, 0) | d <- checkerboardParity ])

-- | The complement regression loss the value head incurs on the checkerboard perturbation: @Σ cb² = 8@.
complementValueLoss :: Double
complementValueLoss = valueLoss predPaletteComplement tgtPalette

-- | Does the JOINT objective @cellLoss + w·valueLoss@ identify the complement (i.e. separate the two
-- palettes)? On the checkerboard witness @cellLoss = 0@, so the joint loss is @w · 8@, which is positive
-- IFF @w > 0@. This is the exact operationalization of "full-palette identifiability ⟺ @w_value > 0@".
complementIdentifiedAt :: Double -> Bool
complementIdentifiedAt w =
  fromIntegral (cellLoss predCellComplement tgtCell) + w * complementValueLoss > 0

-- ===========================================================================
-- The six conjuncts (five delegate to green laws; one is net-new)
-- ===========================================================================

-- | SIGNAL — across the owner's two lenses the corpus carries non-floor detail energy. The
-- iso-luminant witness shows signal can live ENTIRELY in the @ℤ[i]@ chroma ring while L is at the
-- lattice floor (so an L-only anchor is provably blind); the high-frequency witness lights both lenses.
-- Teeth (delegated): the Flat scene floors EVERY channel — a degenerate corpus has no learnable signal.
-- Delegates "SixFour.Spec.AnchorDiagnostic".
lawLearnableSignalExists :: Bool
lawLearnableSignalExists =
     Anchor.lawIsoLuminantSignalIsInChromaRingNotL   -- chroma energy > 0 while L at the floor
  && Anchor.lawHighFreqLightsAllChannels             -- both lenses carry signal
  && Anchor.lawConstantChannelIsLatticeFloor 50      -- a constant channel IS the floor (forced)
  && Anchor.lawFlatSceneFloorsAllChannels            -- TEETH: the flat boundary has nothing to learn

-- | EXPRESSIVITY — the target is representable in the head's codomain @A₇ = ker Σ@ AND a single 1-LSB
-- invented coefficient survives the Q16 commit (a ½-LSB rounds to the floor under round-half-to-even)
-- and, because the octant lift is a reversible integer bijection, moves the reconstructed cube off the
-- deterministic floor. Delegates "SixFour.Spec.AboveFloorMargin" + "SixFour.Spec.RootLatticeDetail".
lawTargetExpressibleAboveFloor :: Bool
lawTargetExpressibleAboveFloor =
     Margin.lawFloorMarginIsFinite          -- ½ LSB → floor, 1 LSB survives (a finite threshold)
  && Margin.lawAboveFloorMarginReachable    -- a surviving LSB moves the output (floor not absorbing)
  && Margin.lawSurvivingDetailIsA7          -- the surviving bands are a legal mean-free A₇ residual
  && Root.lawOctantIsA7                      -- the b=8 octant's 7 detail bands ARE rank A₇
  && Margin.marginCoeffQ16 == 1              -- the margin the trainer must exceed is one Q16 LSB

-- | IDENTIFIABILITY (rank-3) — the trained loss @cellLoss@ is squared error on the 2nd cross-moment
-- @A = C·Sᵀ@; @S@ has full column rank 3 ⇒ @A@ is rank ≤ 3 and reaches it, so @cellLoss@ is a
-- sufficient statistic for the 9 identified aggregate entries (the colour×space first spatial moments +
-- off-diagonal chroma×space coupling the L-row loss is blind to). It is the honest cell-aggregate, not a
-- per-voxel rank-1 sum. Delegates "SixFour.Spec.MatrixTarget" + "SixFour.Spec.NudgeRankTheorem".
lawCellLossIdentifiesRank3Subspace :: Bool
lawCellLossIdentifiesRank3Subspace =
     NR.lawCellAggregateReachesRank3              -- A reaches full rank 3 (det 1) on 3 generic voxels
  && MT.lawCellLossIsAggregateNotPerVoxel         -- the loss scores the aggregate, not per-voxel rank-1
  && MT.lawMatrixLossSeesOffDiagonal              -- it sees the off-diagonal chroma×space coupling
  && NR.lawHeldOutLossIsCellAggregateNotPerVoxel  -- a mispaired off-diagonal is invisible per-voxel
  && length (concat (cellAggregate tgtCell)) == identifiedDof   -- exactly 9 identified entries

-- | IDENTIFIABILITY (the complement) — THE NET-NEW LAW. @cellLoss@ is rank-DEFICIENT: it is exactly
-- ANCILLARY on the 15-DOF orthogonal complement of @span(S)@. Perturbing the palette's @a@-channel by
-- the checkerboard PARITY vector @cb@ (which is @S@-orthogonal and mean-free, so in the complement)
-- leaves @cellLoss@ EXACTLY zero — blind — while the palette differs; the value head's OKLab regression
-- @valueLoss@ sees it (@Σ cb² = 8 > 0@). Therefore the PAIR @(cellLoss, w_value·valueLoss)@ identifies
-- the complement IFF @w_value > 0@. Teeth: (1) the in-@span(S)@ @x@-perturbation @cellLoss@ DOES see
-- (so the loss is not blind to everything), and (2) the joint objective separates the palettes at
-- @w_value = 1@ but NOT at @w_value = 0@ — the current trainer default leaves the 15 DOF unconstrained.
lawValueHeadIdentifiesComplement :: Bool
lawValueHeadIdentifiesComplement =
     cellLoss predCellComplement tgtCell == 0       -- (1) cellLoss is BLIND to the complement perturbation
  && complementValueLoss > 0                         -- (2) the value head's regression SEES the palette diff
  && cellLoss predCellSubspace  tgtCell > 0          -- (3) cellLoss IS informative on span(S) (not blind to all)
  && det3 (cellAggregate tgtCell) == 0               -- the a-only target's A is rank-deficient by construction
  && identifiedDof + blindDof == totalColourDof      -- the 9 + 15 = 24 DOF accounting closes
  && complementIdentifiedAt 1.0                      -- (4a) w_value = 1 > 0  ⇒ complement identified
  && not (complementIdentifiedAt 0)                  -- (4b) w_value = 0      ⇒ complement UNidentified (default)

-- | DESCENT — on the data-manufactured golden fixture @trainBandJoint@ drives the masked-band loss
-- MONOTONICALLY to a tiny fraction of the floor loss and recovers the golden committed band @3000@
-- byte-exact (the MLX-trained θ_B and the device hand-written forward pass must both reproduce it). The
-- identified optimum is not just reachable but actually REACHED. Delegates "SixFour.Spec.MaskedBandTrainer".
lawDescentReachesGoldenByteExact :: Bool
lawDescentReachesGoldenByteExact =
     Trainer.lawZeroGenomeIsFloor                   -- start at the floor band, off-floor target incurs loss
  && Trainer.lawTrainingDrivesLossDown              -- loss → < 1e-3 of the floor loss
  && Trainer.lawTrainedForwardIsGolden              -- the committed band is exactly the golden 3000
  && Trainer.lawTrainingDescendsMonotonically       -- more steps never increase the loss
  && Trainer.lawStableTrainerSurvivesBatchDivergence -- the mean-gradient trainer survives high-ṽ batches
  && Trainer.goldenTrainedBand == 3000              -- the byte-exact endpoint pinned

-- | NO-COLLAPSE — the VICReg per-factor std hinge penalizes a collapse of EITHER the colour factor or
-- the space factor of @A@. Since the target is data-manufactured (no EMA, no @L_close@ orbit), the only
-- collapse risk is the never-surfaced mid-latent going constant; the guard keeps each factor's 2nd
-- central moment above a floor, so @A@ stays rank-3 and the sufficient statistic stays informative.
-- Delegates "SixFour.Spec.VarianceFloorGuard".
lawNoCollapseKeepsCrossMomentFullRank :: Bool
lawNoCollapseKeepsCrossMomentFullRank =
     Guard.lawEitherCollapseTripsGuard   -- a flat colour OR space factor trips the combined guard
  && Guard.lawHingeAtBoundary            -- the hinge fires exactly when std < γ (std, not variance)

-- ===========================================================================
-- The capstone
-- ===========================================================================

-- | The full learnability conjunction PARAMETERIZED by the value-head weight @w_value@: SIGNAL ∧
-- EXPRESSIVITY ∧ rank-3 IDENTIFIABILITY ∧ (the complement is identified at this @w_value@) ∧ DESCENT ∧
-- NO-COLLAPSE. The complement conjunct is the ONLY one that depends on @w_value@ — it holds iff
-- @w_value > 0@ — so this is the precise place the side condition enters.
willLearn :: Double -> Bool
willLearn wValue =
     lawLearnableSignalExists
  && lawTargetExpressibleAboveFloor
  && lawCellLossIdentifiesRank3Subspace
  && complementIdentifiedAt wValue
  && lawDescentReachesGoldenByteExact
  && lawNoCollapseKeepsCrossMomentFullRank

-- | THE CAPSTONE — the model WILL learn the data-manufactured target, as a theorem CONDITIONAL on the
-- value-head weight @w_value > 0@. There IS signal, it is EXPRESSIBLE above the Q16 floor, the joint
-- objective @(cellLoss + w_value·valueLoss)@ IDENTIFIES the full palette (rank-3 via @cellLoss@ + the
-- complement via the value head), monotone DESCENT REACHES the byte-exact optimum, and NO-COLLAPSE keeps
-- that optimum non-degenerate. The law is TRUE at @w_value = 1@ and FALSE at @w_value = 0@ — proving the
-- side condition is load-bearing, not decorative (the current trainer default @w_value = 0@ leaves the
-- 15-DOF complement unidentified, so "the model will learn" is FALSE for those DOF). Drop ANY conjunct
-- and a concrete witness breaks the promise (a Flat corpus, a ½-LSB target, the checkerboard-parity
-- palette, a high-ṽ fixed-η batch, or a constant mid-latent factor).
lawModelWillLearn :: Bool
lawModelWillLearn =
     willLearn 1.0          -- with the value head on (w_value > 0): the full palette is learnable
  && not (willLearn 0)      -- with the value head off (w_value = 0): the complement is UNidentified

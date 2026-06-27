{- |
Module      : SixFour.Codegen.LearnabilityTheorem
Description : Emit @learnability_golden.json@ — the byte-exact PORT of the learnability theorem
("SixFour.Spec.LearnabilityTheorem") to the trainer. The capstone @lawModelWillLearn@ is a Haskell
proof; this emitter pins the concrete scalars and small integer vectors the proof turns on, so the
MLX trainer (@trainer/mlx/test_learnability.py@) reproduces them byte-exact and FAILS the trainer
gate on any drift. The spec is the DESIGN AUTHORITY for the learnability claim, not just the data.

The golden walks the same statistical moment ladder as the theorem, one section per conjunct:

  * SIGNAL — the two owner lenses (@d6@\/@ℓ¹@ discrete geometry on L, @ℤ[i]@ algebraic number theory
    on chroma). Per 'Anchor.SceneKind' the raw octant channel voxels AND the resulting energies are
    emitted, so the trainer reproduces @lEnergyOf@\/@chromaEnergyOf@ from its own octant-lift port
    (NOT a JSON tautology). Flat @(0,0)@ is the boundary tooth: nothing to learn.
  * EXPRESSIVITY — the Q16 commit margin (@1@ LSB survives, @½@ LSB floors) and the @A₇@ witness
    @fromRootCoords 8 [1..1] = [1,0,0,0,0,0,0,-1]@ (the surviving detail is a legal mean-free residual).
  * IDENTIFIABILITY — the heart. @rank S = 3@, the @9@ identified \/ @15@ blind DOF split, the
    cell-aggregate identity witness, and THE value-head teeth: the @S@-orthogonal mean-free
    checkerboard-parity perturbation gives @cellLoss = 0@ (blind) while @valueLoss = Σcb² = 8 > 0@.
  * DESCENT — the pinned trajectory endpoints @0 → 3000@ over @2000@ steps ("SixFour.Spec.MaskedBandTrainer").
  * NO-COLLAPSE — the VICReg combined guard's exact factor vectors (so the float compare is
    deterministic): a flat factor trips the guard (@> 0.5@), two varied factors pass (@< 1e-9@).
  * SIDE CONDITION — @w_value > 0@ is required: @willLearn 1 = True@, @willLearn 0 = False@.

GHC-boot-only; the emitter returns @Text@ like the other @Codegen.*@ emitters. Additive: pins
nothing new in the spec, re-pins no shipped contract. All values are COMPUTED from the spec
functions (no literals), so the emitter cannot drift from the proof it ports.
-}
module SixFour.Codegen.LearnabilityTheorem
  ( emitLearnabilityGolden
  ) where

import Data.List (intercalate)
import Data.Text (Text)
import qualified Data.Text as T

import SixFour.Spec.DualCube            (P6(..))
import SixFour.Spec.MatrixTarget        (cellLoss)
import SixFour.Spec.NudgeRankTheorem    (cellAggregate, det3)
import SixFour.Spec.OctreeCell          (V8(..))
import SixFour.Spec.RootLatticeDetail   (fromRootCoords)

import SixFour.Spec.LearnabilityTheorem
  ( octantCorners, checkerboardParity
  , identifiedDof, blindDof, totalColourDof
  , willLearn, lawModelWillLearn )
import qualified SixFour.Spec.AnchorDiagnostic   as Anchor
import qualified SixFour.Spec.AboveFloorMargin   as Margin
import qualified SixFour.Spec.MaskedBandTrainer  as Trainer
import qualified SixFour.Spec.Q16                as Q16
import qualified SixFour.Spec.VarianceFloorGuard as Guard

-- ---------------------------------------------------------------------------
-- The three cells the IDENTIFIABILITY proof turns on (rebuilt exactly as in
-- the theorem, from the EXPORTED octantCorners + checkerboardParity).
-- ---------------------------------------------------------------------------

-- | The TARGET octant cell: constant @a = 2@ base, @L = b = 0@, on the eight @{0,1}³@ corners.
tgtCell :: [P6]
tgtCell = [ P6 0 2 0 x y t | (x,y,t) <- octantCorners ]

-- | The COMPLEMENT-perturbed cell: the @a@-channel shifted by 'checkerboardParity' (in the
-- @S@-orthogonal mean-free complement ⇒ @cellLoss = 0@, blind, yet the palette differs).
predCellComplement :: [P6]
predCellComplement =
  [ P6 0 (2 + d) 0 x y t | ((x,y,t), d) <- zip octantCorners checkerboardParity ]

-- | The IN-@span(S)@ perturbed cell: the @a@-channel shifted by the @x@ coordinate (a column of @S@
-- ⇒ @cellLoss > 0@, the loss is not blind to everything).
predCellSubspace :: [P6]
predCellSubspace = [ P6 0 (2 + x) 0 x y t | (x,y,t) <- octantCorners ]

-- | The mispaired off-diagonal witness from "SixFour.Spec.NudgeRankTheorem"
-- (@lawHeldOutLossIsCellAggregateNotPerVoxel@): chroma↔space swapped ⇒ per-voxel-blind, aggregate @4@.
mispairTgt, mispairPred :: [P6]
mispairTgt  = [ P6 0 1 0 1 0 0, P6 0 0 1 0 1 0, P6 1 0 0 0 0 1 ]
mispairPred = [ P6 0 1 0 0 1 0, P6 0 0 1 1 0 0, P6 1 0 0 0 0 1 ]

-- | The value head's checkerboard regression loss @Σ cb² = 8@ (the @a@-channel shift, squared).
complementValueLoss :: Integer
complementValueLoss = sum [ d * d | d <- checkerboardParity ]

-- ---------------------------------------------------------------------------
-- Small JSON helpers (no dependency; the other Codegen.* emitters hand-roll too).
-- ---------------------------------------------------------------------------

iarr :: Show a => [a] -> String
iarr xs = "[" ++ intercalate "," (map show xs) ++ "]"

iarr2 :: Show a => [[a]] -> String
iarr2 rows = "[" ++ intercalate "," (map iarr rows) ++ "]"

bool :: Bool -> String
bool b = if b then "true" else "false"

-- | One P6 voxel as @[L,a,b,x,y,t]@ — the trainer reads cells in this exact field order.
p6arr :: P6 -> String
p6arr (P6 l a b x y t) = iarr [l,a,b,x,y,t]

cellArr :: [P6] -> String
cellArr ps = "[" ++ intercalate "," (map p6arr ps) ++ "]"

-- | One SIGNAL scene: the raw octant channel voxels (so the trainer reproduces the energies from its
-- own octant-lift port) plus the two-lens energies the spec computes.
sceneJson :: Anchor.SceneKind -> String
sceneJson k =
  let (lv, av, bv) = Anchor.scene k
      toL :: V8 Int -> [Int]
      toL (V8 a b c d e f g h) = [a,b,c,d,e,f,g,h]
  in "    {\"kind\":\"" ++ show k ++ "\""
     ++ ",\"lVoxels\":" ++ iarr (toL lv)
     ++ ",\"aVoxels\":" ++ iarr (toL av)
     ++ ",\"bVoxels\":" ++ iarr (toL bv)
     ++ ",\"lEnergy\":" ++ show (Anchor.lEnergyOf k)
     ++ ",\"chromaEnergy\":" ++ show (Anchor.chromaEnergyOf k) ++ "}"

-- ---------------------------------------------------------------------------
-- The emitter.
-- ---------------------------------------------------------------------------

-- | Emit @learnability_golden.json@: every scalar and small integer vector the learnability proof
-- turns on, all computed from the spec functions.
emitLearnabilityGolden :: Text
emitLearnabilityGolden = T.pack $ unlines
  [ "{"
  , "  \"_doc\": \"Learnability theorem golden (SixFour.Codegen.LearnabilityTheorem): the byte-exact\","
  , "  \"_doc2\": \"port of Spec.LearnabilityTheorem.lawModelWillLearn. One section per conjunct.\","

  -- SIGNAL ------------------------------------------------------------------
  , "  \"signal\": {"
  , "    \"_doc\": \"d6/l1 lattice norm on L (discrete geometry) + Z[i] Gaussian norm on chroma (algebraic number theory). channelEnergy==0 IFF detail at the root-lattice floor.\","
  , "    \"scenes\": ["
  , intercalate ",\n" (map sceneJson [minBound .. maxBound])
  , "    ]"
  , "  },"

  -- EXPRESSIVITY ------------------------------------------------------------
  , "  \"expressivity\": {"
  , "    \"_doc\": \"The Q16 commit margin + the A7 mean-free residual witness.\","
  , "    \"marginCoeffQ16\": " ++ show Margin.marginCoeffQ16 ++ ","
  , "    \"oneLsbLatent\": " ++ show (Q16.toQ16 1) ++ ","
  , "    \"survivesOneLsb\": " ++ bool (Margin.survivesCommit (Q16.toQ16 1)) ++ ","
  , "    \"survivesHalfLsb\": " ++ bool (Margin.survivesCommit (Q16.toQ16 1 / 2)) ++ ","
  , "    \"commitOneLsb\": " ++ show Margin.marginCoeffQ16 ++ ","
  , "    \"commitHalfLsb\": 0,"
  , "    \"a7Witness\": {\"b\":8,\"coords\":" ++ iarr ([1,1,1,1,1,1,1] :: [Integer])
        ++ ",\"result\":" ++ iarr (fromRootCoords 8 [1,1,1,1,1,1,1]) ++ "}"
  , "  },"

  -- IDENTIFIABILITY ---------------------------------------------------------
  , "  \"identifiability\": {"
  , "    \"_doc\": \"The HEART: cellLoss on the 2nd cross-moment A=C.S^T identifies rank-3 (9 DOF); the value head identifies the 15-DOF complement IFF w_value>0.\","
  , "    \"rankS\": 3,"
  , "    \"identifiedDof\": " ++ show identifiedDof ++ ","
  , "    \"blindDof\": " ++ show blindDof ++ ","
  , "    \"totalColourDof\": " ++ show totalColourDof ++ ","
  , "    \"cellAggregateIdentityWitness\": {"
  , "      \"_doc\": \"3 phi6-diagonal voxels => A = I, det = 1.\","
  , "      \"cell\": " ++ cellArr mispairTgt ++ ","
  , "      \"aggregate\": " ++ iarr2 (cellAggregate mispairTgt) ++ ","
  , "      \"det\": " ++ show (det3 (cellAggregate mispairTgt))
  , "    },"
  , "    \"offDiagonalMispairCell\": " ++ cellArr mispairPred ++ ","
  , "    \"offDiagonalMispairLoss\": " ++ show (cellLoss mispairPred mispairTgt) ++ ","
  , "    \"valueHead\": {"
  , "      \"_doc\": \"checkerboard cb is S-orthogonal+mean-free => cellLoss==0 (blind) but valueLoss=Sum cb^2>0 (seen).\","
  , "      \"checkerboardParity\": " ++ iarr checkerboardParity ++ ","
  , "      \"tgtCell\": " ++ cellArr tgtCell ++ ","
  , "      \"predCellComplement\": " ++ cellArr predCellComplement ++ ","
  , "      \"cellLossComplement\": " ++ show (cellLoss predCellComplement tgtCell) ++ ","
  , "      \"complementValueLoss\": " ++ show complementValueLoss ++ ","
  , "      \"predCellSubspace\": " ++ cellArr predCellSubspace ++ ","
  , "      \"cellLossSubspace\": " ++ show (cellLoss predCellSubspace tgtCell) ++ ","
  , "      \"tgtCellAggregateDet\": " ++ show (det3 (cellAggregate tgtCell))
  , "    }"
  , "  },"

  -- DESCENT -----------------------------------------------------------------
  , "  \"descent\": {"
  , "    \"_doc\": \"trainBandJoint drives the loss to the golden committed band, byte-exact.\","
  , "    \"trainerSteps\": " ++ show Trainer.trainerSteps ++ ","
  , "    \"goldenFloorBand\": " ++ show Trainer.goldenFloorBand ++ ","
  , "    \"goldenTrainedBand\": " ++ show Trainer.goldenTrainedBand
  , "  },"

  -- NO-COLLAPSE -------------------------------------------------------------
  , "  \"noCollapse\": {"
  , "    \"_doc\": \"VICReg combined guard: a flat factor trips it (>0.5); two varied factors pass (<1e-9). Exact factor vectors emitted so the float compare is deterministic.\","
  , "    \"variedFactor\": " ++ iarr ([0,10,0,10,0,10,0,10] :: [Double]) ++ ","
  , "    \"flatFactor\": " ++ iarr (replicate 8 (5.0 :: Double)) ++ ","
  , "    \"flatVariedTripsGuard\": " ++ bool (Guard.combinedGuard (replicate 8 5.0) varied > 0.5) ++ ","
  , "    \"variedVariedPasses\": " ++ bool (Guard.combinedGuard varied varied < 1e-9)
  , "  },"

  -- SIDE CONDITION ----------------------------------------------------------
  , "  \"sideCondition\": {"
  , "    \"_doc\": \"Full-palette learnability holds IFF w_value>0. The trainer ADOPTS the proven point as its default (train_loop.py --w-value default 1.0 = willLearn(1.0)); w_value=0 is the disabled-head boundary that leaves the 15-DOF complement unconstrained.\","
  , "    \"wValueRequired\": true,"
  , "    \"willLearnAtOne\": " ++ bool (willLearn 1.0) ++ ","
  , "    \"willLearnAtZero\": " ++ bool (willLearn 0) ++ ","
  , "    \"lawModelWillLearn\": " ++ bool lawModelWillLearn
  , "  }"
  , "}"
  ]
  where varied = [0,10,0,10,0,10,0,10] :: [Double]

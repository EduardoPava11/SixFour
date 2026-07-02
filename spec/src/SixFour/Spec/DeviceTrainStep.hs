{- |
Module      : SixFour.Spec.DeviceTrainStep
Description : The ON-DEVICE per-capture training gate (V3.0): the capture manufactures its OWN supervision pair (the exact 'liftOct' of a fine octant), the mean-gradient descent recovers the detail EXACTLY through the Q16 crossing, and the pinned post-commit bytes are what the MPSGraph and Metal-4 device trainers must both reproduce.

V3.0 moves the up-rung fine-tune ONTO the phone. The learned object is unchanged — the
"SixFour.Spec.DetailPredictor" @f_θ : coarse → detail@ (21 params, @θ·φ@ per band) — but the
training data is no longer a Mac-side corpus: EVERY capture carries its own ground truth,
because pooling the real fine cube one octant step down is the EXACT reversible 'liftOct'.
The pair @(coarse, detail) = liftOct fineBlock@ loses nothing ('lawSupervisionPairIsExact'),
so the device can fit @f_θ@ to the capture it just took, then reuse the SAME weights on the
beyond-capture rung ("SixFour.Spec.DetailPredictor" @lawReusesOnBothRungs@ — @64³:16³ ::
256³:64³@).

This module is the training GATE for that on-device step, the exact
"SixFour.Spec.MaskedBandTrainer" idiom one organ over: a fixed fixture, a fixed step count,
a pinned trajectory with byte-exact endpoints.

  * 'lawSupervisionPairIsExact' — the pair manufacture is the reversible lift: for ANY fine
    block, @unliftOct@ of the pair recovers the block (each capture IS its own lossless
    training set), and the golden fixture's pair is exactly @('deviceCoarse',
    'deviceTargetDetail')@.
  * 'lawDeviceZeroParamsIsFloor' — the descent starts at the floor (zero params ⇒
    'floorResidual' by arithmetic) and the target genuinely incurs loss (non-vacuous).
  * 'lawDeviceTrainingDrivesLossDown' — 'trainDevice' drives the supervised band loss to a
    tiny fraction of the floor loss.
  * 'lawDeviceTrainedDetailIsGolden' (THE TWIN) — after 'deviceTrainSteps' the COMMITTED
    detail is exactly 'goldenDeviceDetail': the descent recovers the manufactured bands
    through the Q16 crossing. The MPSGraph trainer (B1) and the Metal-4 tensor trainer (B2)
    gate on these POST-COMMIT bytes — float trajectories may differ per backend (summation
    order, float32 on the neural accelerator); the committed integers may NOT. The fixture
    is float32-ROBUST by construction: the targets are exact integers in Q16 units and the
    single-example descent converges far inside the half-LSB rounding margin.
  * 'lawDeviceDescentMonotone' — more steps never increase the loss (the divergence guard).
  * 'lawTrainedDetailSurvivesCommit' — every trained nonzero band clears the
    "SixFour.Spec.AboveFloorMargin" 'survivesCommit' threshold: the per-capture fine-tune
    genuinely moves the output OFF the deterministic floor on its own fixture.
  * 'lawDeviceBatchIsStableMeanGradient' — 'trainDevice' descends the MEAN gradient
    (batch-size-independent step, the "SixFour.Spec.MaskedBandTrainer"
    @trainBandJointStable@ lesson applied from the start), so a two-pair batch stays finite
    and converges. η and step count match the Mac twin (@trainer/mlx/superres.py
    train_detail@: η = 0.2, 600 steps), so one golden gates all three backends.

Additive: a pure law module over "SixFour.Spec.DetailPredictor" (forward/loss/gradient
untouched) + "SixFour.Spec.OctreeCell" ('liftOct'/'unliftOct' untouched) +
"SixFour.Spec.AboveFloorMargin" ('survivesCommit' delegated). Emits
@SixFour/Generated/DeviceTrainGolden.swift@ via "SixFour.Codegen.DeviceTrain". GHC-boot-only;
laws tested in @Properties.DeviceTrainStep@.
-}
-- COMPARTMENT: MLX-MODEL | tag:MacTag
module SixFour.Spec.DeviceTrainStep
  ( -- * The on-device supervision-pair manufacture (the capture is its own ground truth)
    supervisionPair
    -- * The golden fixture + its pinned trajectory endpoint
  , deviceCoarse
  , deviceTargetDetail
  , deviceFineBlock
  , devicePair
  , deviceEta
  , deviceTrainSteps
  , goldenDeviceDetail
    -- * The device trainer twin (mean-gradient GD from the floor)
  , trainDevice
  , deviceLossSum
  , deviceTheta
    -- * Laws (tested in @Properties.DeviceTrainStep@)
  , lawSupervisionPairIsExact
  , lawDeviceZeroParamsIsFloor
  , lawDeviceTrainingDrivesLossDown
  , lawDeviceTrainedDetailIsGolden
  , lawDeviceDescentMonotone
  , lawTrainedDetailSurvivesCommit
  , lawDeviceBatchIsStableMeanGradient
    -- * The hardware obligation (CONTRACT-ONLY)
  , contractDeviceGoldenUnrunOnHardware
  ) where

import SixFour.Spec.OctreeCell
  ( V8(..), OctBand(..), Detail, liftOct, unliftOct, detailToList )
import SixFour.Spec.DetailPredictor
  ( defaultPredictorShape, paramCount, zeroParams
  , rawBands, predictDetail, bandLoss, predictorGradient )
import SixFour.Spec.PairedResidual  (floorResidual)
import SixFour.Spec.AboveFloorMargin (survivesCommit)

-- ---------------------------------------------------------------------------
-- Supervision-pair manufacture
-- ---------------------------------------------------------------------------

-- | Manufacture the on-device training pair from a captured fine octant: the EXACT
-- reversible pool, @(coarse, detail) = liftOct block@. This is the whole V3.0 data story —
-- no corpus crosses to the phone; the capture that was just taken IS the supervision.
supervisionPair :: V8 Int -> (Int, Detail)
supervisionPair block = let b = liftOct block in (ocCoarse b, ocDetail b)

-- ---------------------------------------------------------------------------
-- The golden fixture
-- ---------------------------------------------------------------------------

-- | The fixture's coarse value (ṽ ≈ 0.305 — moderate, the same well-conditioned regime as
-- the "SixFour.Spec.MaskedBandTrainer" fixture).
deviceCoarse :: Int
deviceCoarse = 20000

-- | The fixture's manufactured detail bands — all seven NONZERO (so 'survivesCommit' is
-- exercised on every band), all exact integers in Q16 units (so the committed golden is
-- robust to a float32 device descent: the converged raw band sits within ~1e-2 of an
-- integer whose rounding margin is 0.5).
deviceTargetDetail :: Detail
deviceTargetDetail = (3000, 1500, -700, 400, -200, 100, 50)

-- | The fine 2×2×2 block the DEVICE starts from — the fixture is stated in capture space,
-- and the pair is MANUFACTURED by the lift ('supervisionPair'), never assumed. Built by
-- 'unliftOct' so 'lawSupervisionPairIsExact' pins the round trip.
deviceFineBlock :: V8 Int
deviceFineBlock = unliftOct (OctBand deviceCoarse deviceTargetDetail)

-- | The manufactured golden pair (equals @('deviceCoarse', 'deviceTargetDetail')@ by
-- octant reversibility — asserted, not assumed, in 'lawSupervisionPairIsExact').
devicePair :: (Int, Detail)
devicePair = supervisionPair deviceFineBlock

-- | The learning rate — matches the Mac twin @trainer/mlx/superres.py train_detail@
-- (η = 0.2), so the Haskell gate, the Python trainer, and the device trainer descend the
-- same trajectory.
deviceEta :: Double
deviceEta = 0.2

-- | The fixed step count for the golden descent — matches @superres.py train_detail@
-- (600 steps).
deviceTrainSteps :: Int
deviceTrainSteps = 600

-- | The committed detail after the golden descent: the descent RECOVERS the manufactured
-- bands exactly through the Q16 crossing (@raw_j → t_j@, and @t_j·65536@ is the integer
-- band). These are the POST-COMMIT bytes every backend must reproduce.
goldenDeviceDetail :: Detail
goldenDeviceDetail = (3000, 1500, -700, 400, -200, 100, 50)

-- ---------------------------------------------------------------------------
-- The device trainer twin
-- ---------------------------------------------------------------------------

-- | The on-device trainer twin: full-batch gradient descent on the MEAN per-pair gradient
-- (batch-size-independent step — the "SixFour.Spec.MaskedBandTrainer"
-- @trainBandJointStable@ lesson, adopted from the start), from the zero-param floor.
-- Mirrors @superres.py train_detail@ line for line.
trainDevice :: Int -> [(Int, Detail)] -> [Double]
trainDevice n exs =
  let sh          = defaultPredictorShape
      m           = fromIntegral (max 1 (length exs))
      meanGrad ps = map (/ m) (foldr (zipWith (+)) (replicate (paramCount sh) 0)
                                     (map (predictorGradient sh ps) exs))
      step ps     = zipWith (\p g -> p - deviceEta * g) ps (meanGrad ps)
  in iterate step (zeroParams sh) !! max 0 n

-- | Summed supervised band loss over a batch of pairs (the quantity the descent reduces).
deviceLossSum :: [Double] -> [(Int, Detail)] -> Double
deviceLossSum ps = sum . map (bandLoss defaultPredictorShape ps)

-- | The θ produced by the golden descent (shared by the laws and the codegen emitter).
deviceTheta :: [Double]
deviceTheta = trainDevice deviceTrainSteps [devicePair]

-- ============================================================================
-- Laws (tested in Properties.DeviceTrainStep)
-- ============================================================================

-- | THE PAIR MANUFACTURE IS THE EXACT LIFT. For ANY fine block (padded from the generated
-- list), rebuilding from the manufactured pair recovers the block bit-for-bit — the
-- capture is a LOSSLESS training set for its own down-rung. And on the golden fixture the
-- manufactured pair is exactly @('deviceCoarse', 'deviceTargetDetail')@ (so the fixture's
-- pair is derived, never asserted). Teeth: a lossy pool, or a drifted fixture, fails.
lawSupervisionPairIsExact :: [Int] -> Bool
lawSupervisionPairIsExact xs =
  let block  = toBlock (take 8 (xs ++ repeat 0))
      (c, d) = supervisionPair block
  in unliftOct (OctBand c d) == block
     && devicePair == (deviceCoarse, deviceTargetDetail)
  where
    toBlock [a, b, c', d', e, f, g, h] = V8 a b c' d' e f g h
    toBlock _                          = V8 0 0 0 0 0 0 0 0

-- | The descent starts AT the floor: zero params predict 'floorResidual' (by arithmetic,
-- "SixFour.Spec.DetailPredictor" @lawZeroParamsIsFloorArithmetic@) and the manufactured
-- target genuinely incurs loss — the problem is non-vacuous.
lawDeviceZeroParamsIsFloor :: Bool
lawDeviceZeroParamsIsFloor =
  let sh = defaultPredictorShape
  in predictDetail sh (zeroParams sh) deviceCoarse == floorResidual
     && bandLoss sh (zeroParams sh) devicePair > 1e-6

-- | Training drives the supervised loss to a tiny fraction (< 1e-6) of the floor loss —
-- the manufactured label is learnable from the capture alone.
lawDeviceTrainingDrivesLossDown :: Bool
lawDeviceTrainingDrivesLossDown =
  let sh = defaultPredictorShape
  in bandLoss sh deviceTheta devicePair
       < 1e-6 * bandLoss sh (zeroParams sh) devicePair

-- | THE BYTE-CHECKABLE TWIN: after the golden descent the committed detail is exactly
-- 'goldenDeviceDetail' — the descent recovers the manufactured bands through the Q16
-- crossing. The MPSGraph trainer AND the Metal-4 tensor trainer must reproduce these
-- POST-COMMIT bytes on the same fixture; a drifted trainer or a wrong commit fails here.
-- (Also pins that the golden IS the manufactured target — recovery, not invention.)
lawDeviceTrainedDetailIsGolden :: Bool
lawDeviceTrainedDetailIsGolden =
  predictDetail defaultPredictorShape deviceTheta deviceCoarse == goldenDeviceDetail
    && goldenDeviceDetail == snd devicePair

-- | The descent is MONOTONE: more steps never increase the loss (the fixed-η divergence
-- guard, stated on the golden fixture).
lawDeviceDescentMonotone :: Bool
lawDeviceDescentMonotone =
  let sh = defaultPredictorShape
  in bandLoss sh (trainDevice deviceTrainSteps [devicePair]) devicePair
       <= bandLoss sh (trainDevice 100 [devicePair]) devicePair

-- | THE POINT OF THE FINE-TUNE: every trained band whose target is nonzero clears the
-- "SixFour.Spec.AboveFloorMargin" 'survivesCommit' threshold — the per-capture adaptation
-- emits coefficients that SURVIVE the Q16 commit and reach the output, off the floor.
-- (On this fixture all seven targets are nonzero, so all seven bands are checked.)
lawTrainedDetailSurvivesCommit :: Bool
lawTrainedDetailSurvivesCommit =
  let raws = rawBands defaultPredictorShape deviceTheta deviceCoarse
      tgts = detailToList deviceTargetDetail
  in and [ survivesCommit r | (r, t) <- zip raws tgts, t /= 0 ]

-- | The MEAN-gradient step is batch-stable: on a TWO-pair batch (two manufactured pairs at
-- distinct coarse values) the descent stays finite and converges well below the floor loss.
-- The step is batch-size-independent by construction — the summed-gradient divergence the
-- "SixFour.Spec.MaskedBandTrainer" defect law reproduced cannot arise here.
lawDeviceBatchIsStableMeanGradient :: Bool
lawDeviceBatchIsStableMeanGradient =
  let sh     = defaultPredictorShape
      block2 = unliftOct (OctBand 40000 (-1200, 800, 300, -50, 60, -30, 10))
      batch  = [devicePair, supervisionPair block2]
      theta  = trainDevice deviceTrainSteps batch
      lossT  = deviceLossSum theta batch
      lossZ  = deviceLossSum (zeroParams sh) batch
  in not (isNaN lossT || isInfinite lossT)
     && lossT < 1e-2 * lossZ

-- | CONTRACT-ONLY (carries no truth value) — the HARDWARE obligation. The laws above pin
-- the trajectory in Haskell; they do NOT prove a Swift trainer on the physical iPhone
-- reproduces 'goldenDeviceDetail'. That is the discharge: the MPSGraph trainer (workflow
-- B1) and the Metal-4 tensor trainer (B2) each run the fixture ON DEVICE and byte-compare
-- the committed detail against @DeviceTrainGolden.committed@ (the
-- "SixFour.Codegen.DeviceTrain" emission). See @docs/V3-BUILD-WORKFLOW.md@.
contractDeviceGoldenUnrunOnHardware :: ()
contractDeviceGoldenUnrunOnHardware = ()

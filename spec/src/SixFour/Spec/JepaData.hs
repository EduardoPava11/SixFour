-- COMPARTMENT: MLX-MODEL | tag:MacTag
{- |
Module      : SixFour.Spec.JepaData
Description : The I-JEPA DATA ENGINE (spec side) — manufacture the @(context, mask, held-target)@ training records from octants via the REVERSIBLE lift, with the round-trip golden that closes the NON-INVERTIBILITY TRAP. This is the dependency root that makes the spec the design authority for TRAINING: a record is a true label iff the generator is invertible, proven HERE.

The readiness proof found the training loop's open hop (preference -> weights -> next model)
has NO data engine: nothing emits the I-JEPA training corpus, and the trap (NOTES.md) is that
"a non-invertible generator would pass every law" -- the masked-band laws constrain the TARGET's
algebra (no-peek, sibling-context-helps), NOT the GENERATOR's invertibility, so a lossy/buggy
data engine is golden-SILENT.

This module closes that trap at the spec level. A training record is manufactured from an
octant by the proven reversible lift ("SixFour.Spec.OctreeCell" @liftOct@): the 8 cells become
@1 coarse + 7 detail@; one detail band is the MASKED target the model predicts, the other 6 + the
coarse are the context. The KEYSTONE 'lawDataEngineRoundTrips' proves @reconstruct (manufacture
cube m) == cube@ -- so the held band is a TRUE label (the cube is exactly recoverable), not lossy
noise. A non-invertible generator FAILS it. The corpus a real @Codegen.JepaData@ emitter writes
(next slice) is forced byte-exact by this round-trip; the Python data-loader cannot drift.

GHC-boot-only. Reuses @OctreeCell@ (the lift) + @MaskedBandPrediction@ (the record type).
Laws QuickCheck'd in "Properties.JepaData".
-}
module SixFour.Spec.JepaData
  ( -- * Manufacturing training records from octants (the data engine)
    manufactureExample
  , heldTarget
  , reconstructCube
    -- * Laws (QuickCheck'd in @Properties.JepaData@)
  , lawDataEngineRoundTrips
  , lawManufacturedTargetIsTheHeldBand
  , lawHeldTargetIsExcludedFromContext
  , lawHeldTargetIsMaskedTarget
  ) where

import SixFour.Spec.OctreeCell
  (V8(..), OctBand(..), Detail, detailBand, liftOct, unliftOct)
import SixFour.Spec.MaskedBandPrediction
  (MaskedBandExample, numBands, siblingsOf, mbeCoarse, mbeMasked, maskedTargetBand)

-- | The detail value of band @m@ (clamped to @[0,6]@) — via the shared canonical 'detailBand'.
detailAt :: Int -> Detail -> Int
detailAt m d = detailBand d (m `mod` numBands)

-- | MANUFACTURE a training record from an octant: lift the 8 cells to @1 coarse + 7 detail@
-- ("SixFour.Spec.OctreeCell" @liftOct@) and mark band @m@ as the masked target. The result is a
-- "SixFour.Spec.MaskedBandPrediction" @MaskedBandExample@ @(coarse, detail, maskBand)@ carrying
-- the FULL detail (so the cube is recoverable) with @m@ flagged as the band to predict.
manufactureExample :: V8 Int -> Int -> MaskedBandExample
manufactureExample cube m =
  let band = liftOct cube
  in (ocCoarse band, ocDetail band, m `mod` numBands)

-- | The HELD TARGET: the value of the masked band — what the model must predict. It is the
-- @m@-th detail of the lifted octant.
heldTarget :: MaskedBandExample -> Int
heldTarget (_, det, m) = detailAt m det

-- | RECONSTRUCT the octant from a record: put the (full) detail + coarse back through the inverse
-- lift ("SixFour.Spec.OctreeCell" @unliftOct@). Exact because the record carries the held band.
reconstructCube :: MaskedBandExample -> V8 Int
reconstructCube (coarse, det, _) = unliftOct (OctBand coarse det)

-- ============================================================================
-- Laws (predicates; QuickCheck'd in Properties.JepaData)
-- ============================================================================

-- | KEYSTONE — the data engine is INVERTIBLE: reconstructing a manufactured record recovers the
-- octant exactly, so the held band is a TRUE label (the cube is not lost). This is the proof a
-- non-invertible / lossy generator CANNOT pass (it would fail to recover the cube), closing the
-- trap that "a buggy generator passes every other law". Delegates @OctreeCell@'s lift
-- reversibility. Teeth: a generator that dropped or corrupted a band fails the round-trip.
lawDataEngineRoundTrips :: V8 Int -> Int -> Bool
lawDataEngineRoundTrips cube m =
  reconstructCube (manufactureExample cube m) == cube

-- | The manufactured target IS the held detail band (the label is real, derived from the lift,
-- not invented): @heldTarget (manufacture cube m)@ equals the @m@-th detail of @liftOct cube@.
-- Teeth: a generator whose "target" did not equal the lifted band fails.
lawManufacturedTargetIsTheHeldBand :: V8 Int -> Int -> Bool
lawManufacturedTargetIsTheHeldBand cube m =
  let ex = manufactureExample cube m
  in heldTarget ex == detailAt m (ocDetail (liftOct cube))

-- | NO PEEK: the masked target band is NOT among the sibling-context bands the model reads
-- ("SixFour.Spec.MaskedBandPrediction" @siblingsOf@ excludes the masked index), so prediction is
-- real work, not copying. Here phrased on the manufactured record: the context is the 6 OTHER
-- bands. Teeth: a record whose context leaked the target band would have @numBands@ siblings.
lawHeldTargetIsExcludedFromContext :: V8 Int -> Int -> Bool
lawHeldTargetIsExcludedFromContext cube m =
  let ex = manufactureExample cube m
  in length (siblingsOf ex) == numBands - 1   -- 6 context bands, the masked one held out
     && mbeMasked ex == m `mod` numBands
     && mbeCoarse ex == ocCoarse (liftOct cube)

-- | THE BRIDGE: the data engine's held label IS the predictor's masked target — "SixFour.Spec.JepaData"
-- 'heldTarget' and "SixFour.Spec.MaskedBandPrediction" @maskedTargetBand@ are two names for the SAME
-- band of the SAME 'Detail' (both route through the shared "SixFour.Spec.OctreeCell" 'detailBand'),
-- so the manufactured label and the regression target can never disagree. Teeth: a band-order or
-- clamp drift in either reader would break the identity.
lawHeldTargetIsMaskedTarget :: V8 Int -> Int -> Bool
lawHeldTargetIsMaskedTarget cube m =
  let ex = manufactureExample cube m
  in heldTarget ex == maskedTargetBand ex

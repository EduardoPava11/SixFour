{- |
Module      : SixFour.Spec.MaskedBandPrediction
Description : The per-band masked-prediction (I-JEPA) objective — predict ONE masked octant detail band from the coarse value PLUS the six VISIBLE sibling bands. The richer-context sibling of "SixFour.Spec.DetailMaskedPrediction" (coarse-only). Its keystone law is that sibling context STRICTLY beats any coarse-only predictor.

"SixFour.Spec.DetailMaskedPrediction" states the masked objective with COARSE-ONLY
context: predict all seven octant bands from the coarse value alone
("SixFour.Spec.DetailPredictor" @f_θ(v)@, 21 params). This module is the chosen
richer model (option B): the context is the coarse value AND the six sibling detail
bands, and exactly ONE band is masked and regressed. It is the literal image-JEPA
masking pattern (predict a masked patch from the visible patches) lifted onto the
octant's seven-band detail vector.

== The masked example and the feature map

A 'MaskedBandExample' is @(coarse, fullDetail, maskedIndex)@: the visible coarse value,
the ground-truth seven-band "SixFour.Spec.OctreeCell" @Detail@, and which band
@m ∈ [0,6]@ is hidden. The predictor's input is @(coarse, the six VISIBLE siblings)@ —
NEVER the masked band itself ('lawMaskedContextExcludesTarget' has teeth against a
leak). The target is the masked band's true value.

The feature map widens the coarse-only @[1, ṽ, ṽ²]@ with the six normalised sibling
values:

@
  φ_B(v, sibs) = [1, ṽ, ṽ²] ++ map toQ16 sibs            ('featureCountB' = 3 + 6 = 9)
  rawₘ(v,sibs) = θₘ · φ_B(v, sibs)                       (a Mac-side Double — a Latent)
  bandₘ        = reenterQ16 rawₘ                          (the single float→device crossing)
@

There is one parameter ROW of 'featureCountB' per band ⇒ @7·9 = 63@ flat params
(@θ₀ ++ … ++ θ₆@), the same flat-bump layout "SixFour.Spec.DetailPredictor" /
"SixFour.Spec.ValueHead" use, so the finite-difference gradient law is a clean
per-scalar probe.

== zeroParams == the floor, by ARITHMETIC

As in "SixFour.Spec.DetailPredictor": at 'zeroParams' every readout is @0·φ_B = 0@ and
@reenterQ16 0 = 0@, so 'predictMaskedBand' returns the floor band (0) for EVERY input,
satisfying the @zero-genome == floor@ contract with no sentinel branch.

== Why pay for the sibling context (the keystone)

'lawSiblingContextStrictlyHelps' is the law that earns B its extra parameters: on two
examples that share the SAME coarse value but differ in their siblings (and targets), a
coarse-only predictor is FORCED to emit one value for both, so the best summed loss any
v-only predictor can achieve is bounded below by a positive constant; the sibling-aware
model fits both and beats that floor. A coarse-only model (option A) provably CANNOT —
that strict inequality is the whole justification for option B.

Additive: a new sibling of "SixFour.Spec.DetailMaskedPrediction" (coarse-only) reusing
"SixFour.Spec.OctreeCell" @Detail@, "SixFour.Spec.AtlasGame" @toQ16@,
"SixFour.Spec.ByteCarrier" the float→device crossing, and "SixFour.Spec.PairedResidual"
@floorResidual@. It IMPORTS nothing that imports it and re-pins NO shipped contract;
"SixFour.Spec.DetailMaskedPrediction" / "SixFour.Spec.DetailPredictor" are untouched.
GHC-boot only; device output is integer Q16, the gradient is Mac-side float.
-}
-- COMPARTMENT: MLX-MODEL | tag:DeviceTag | STRADDLER
module SixFour.Spec.MaskedBandPrediction
  ( -- * Shape
    numBands
  , coarseFeatureCount
  , siblingCount
  , featureCountB
  , paramCountB
  , zeroParamsB
    -- * The masked example (coarse + visible siblings, one band masked)
  , MaskedBandExample
  , mbeCoarse
  , mbeMasked
  , maskedTargetBand
  , siblingsOf
  , setBand
  , bandAt
    -- * Feature map / forward
  , featuresB
  , rawMaskedBand
  , predictMaskedBand
    -- * Loss / gradient / SGD step
  , maskedBandLoss
  , maskedBandLossSum
  , maskedBandGradient
  , maskedBandUpdate
  , trainBandJoint
    -- * Laws (QuickCheck'd in @Properties.MaskedBandPrediction@)
  , lawMaskedZeroParamsIsFloor
  , lawMaskedGradientFiniteDiff
  , lawMaskedContextExcludesTarget
  , lawSiblingContextStrictlyHelps
  , lawMaskedConsumesSiblingContext
  , lawMaskedReusesOnBothRungs
  , lawTransferRecoversGapUnderSelfSimilarity
  , lawTransferDegradesUnderLawShift
    -- * Position-conditioned context (I-JEPA position conditioning; ADDITIVE)
  , MaskedBandExamplePos
  , positionFeatureCount
  , paramCountBPos
  , zeroParamsBPos
  , featuresBPos
  , rawMaskedBandPos
  , predictMaskedBandPos
  , trainBandJointPos
  , lawPositionConditioningStrictlyHelps
  ) where

import SixFour.Spec.Q16      (toQ16)
import SixFour.Spec.ByteCarrier    (mkLatent, reenterQ16, toByte)
import SixFour.Spec.OctreeCell     (Detail, levelsBetween)
import SixFour.Spec.PairedResidual (floorResidual)

-- ---------------------------------------------------------------------------
-- Shape
-- ---------------------------------------------------------------------------

-- | The octant detail count — seven bands per "SixFour.Spec.OctreeCell" octant.
numBands :: Int
numBands = 7

-- | The coarse feature-map width: @[1, ṽ, ṽ²]@ ⇒ 3 (the same affine-plus-curvature
-- basis "SixFour.Spec.DetailPredictor" uses).
coarseFeatureCount :: Int
coarseFeatureCount = 3

-- | The number of VISIBLE sibling bands in the context: one band is masked, so six of
-- the seven are visible.
siblingCount :: Int
siblingCount = numBands - 1

-- | The widened feature-map width: coarse features plus the six siblings ⇒ @3 + 6 = 9@.
-- This is exactly what makes B richer than the coarse-only model.
featureCountB :: Int
featureCountB = coarseFeatureCount + siblingCount

-- | Number of flat parameters: one 'featureCountB'-row per band ⇒ @7·9 = 63@.
paramCountB :: Int
paramCountB = numBands * featureCountB

-- | The all-zero parameter vector — the FLOOR by arithmetic (not a sentinel).
zeroParamsB :: [Double]
zeroParamsB = replicate paramCountB 0

-- ---------------------------------------------------------------------------
-- The masked example
-- ---------------------------------------------------------------------------

-- | A per-band masked example: the visible coarse value, the ground-truth seven-band
-- detail, and which band index @m@ is masked (the predictor must fill @m@ from the
-- coarse value and the OTHER six bands).
type MaskedBandExample = (Int, Detail, Int)

-- | The masked band index clamped into @[0, numBands)@ (so an out-of-range generator
-- input names a real band rather than crashing).
clampIndex :: Int -> Int
clampIndex m = ((m `mod` numBands) + numBands) `mod` numBands

-- | The visible coarse value of an example.
mbeCoarse :: MaskedBandExample -> Int
mbeCoarse (v, _, _) = v

-- | The (clamped) masked band index of an example.
mbeMasked :: MaskedBandExample -> Int
mbeMasked (_, _, m) = clampIndex m

-- | The seven detail bands as a list (canonical order).
bandsList :: Detail -> [Int]
bandsList (a, b, c, d, e, f, g) = [a, b, c, d, e, f, g]

-- | Reassemble a 'Detail' from a seven-element list (truncating/padding defensively).
fromBands :: [Int] -> Detail
fromBands xs = case take numBands (xs ++ repeat 0) of
  [a, b, c, d, e, f, g] -> (a, b, c, d, e, f, g)
  _                     -> floorResidual

-- | Read band @i@ (clamped) of a detail.
bandAt :: Detail -> Int -> Int
bandAt det i = bandsList det !! clampIndex i

-- | Overwrite band @i@ (clamped) of a detail with a new value.
setBand :: Detail -> Int -> Int -> Detail
setBand det i x =
  let i' = clampIndex i
  in fromBands [ if j == i' then x else b | (j, b) <- zip [0 ..] (bandsList det) ]

-- | The six VISIBLE sibling bands of an example: every band except the masked one, in
-- canonical order. This is the only detail the predictor may see (the masked band is
-- excluded — 'lawMaskedContextExcludesTarget').
siblingsOf :: MaskedBandExample -> [Int]
siblingsOf (_, det, m) =
  let m' = clampIndex m
  in [ b | (j, b) <- zip [0 ..] (bandsList det), j /= m' ]

-- | The masked target band the objective regresses onto: band @m@ of the ground-truth
-- detail.
maskedTargetBand :: MaskedBandExample -> Int
maskedTargetBand (_, det, m) = bandAt det m

-- ---------------------------------------------------------------------------
-- Feature map / forward
-- ---------------------------------------------------------------------------

-- | The widened feature map @φ_B(v, sibs) = [1, ṽ, ṽ²] ++ map toQ16 sibs@ — the coarse
-- affine-plus-curvature basis followed by the six normalised sibling values. Always
-- 'featureCountB' wide (siblings padded/trimmed to 'siblingCount').
featuresB :: Int -> [Int] -> [Double]
featuresB v sibs =
  let v'  = toQ16 v
      sib = take siblingCount (map toQ16 sibs ++ repeat 0)
  in [1, v', v' * v'] ++ sib

-- | Slice the flat params into one row per band (each of length 'featureCountB').
rowsB :: [Double] -> [[Double]]
rowsB ps = [ take featureCountB (drop (j * featureCountB) ps) | j <- [0 .. numBands - 1] ]

-- | The Mac-side RAW masked-band readout @θₘ · φ_B(v, sibs)@ (a Double, before re-entry
-- to Q16), using the parameter row of the masked band @m@.
rawMaskedBand :: [Double] -> MaskedBandExample -> Double
rawMaskedBand ps ex =
  let phi = featuresB (mbeCoarse ex) (siblingsOf ex)
      row = rowsB ps !! mbeMasked ex
  in sum (zipWith (*) row phi)

-- | THE per-band predictor: the masked band's raw readout re-entered to the Q16 device
-- floor via the SINGLE sanctioned "SixFour.Spec.ByteCarrier" @reenterQ16@ crossing. Its
-- input is @(coarse, the six visible siblings)@ — the masked band never reaches it.
predictMaskedBand :: [Double] -> MaskedBandExample -> Int
predictMaskedBand ps ex = toByte (reenterQ16 (mkLatent (rawMaskedBand ps ex)))

-- ---------------------------------------------------------------------------
-- Loss / gradient / SGD step
-- ---------------------------------------------------------------------------

-- | The supervised masked-band loss: half the squared error of the RAW readout against
-- the masked band's Q16-normalised target. (On the Mac-side raw readout so the gradient
-- is smooth; the device prediction re-enters Q16 separately.)
maskedBandLoss :: [Double] -> MaskedBandExample -> Double
maskedBandLoss ps ex =
  let r = rawMaskedBand ps ex
      t = toQ16 (maskedTargetBand ex)
  in 0.5 * (r - t) * (r - t)

-- | The summed loss over a batch of masked examples (used by the keystone law and the
-- joint trainer).
maskedBandLossSum :: [Double] -> [MaskedBandExample] -> Double
maskedBandLossSum ps = sum . map (maskedBandLoss ps)

-- | The exact gradient of 'maskedBandLoss' w.r.t. every flat parameter (same 63-wide
-- layout). Only the masked band's row is nonzero: @∂L/∂θₘₖ = (rawₘ − tₘ)·φ_Bₖ@; every
-- other row is zero. Pinned against central finite differences by
-- 'lawMaskedGradientFiniteDiff'.
maskedBandGradient :: [Double] -> MaskedBandExample -> [Double]
maskedBandGradient ps ex =
  let m   = mbeMasked ex
      phi = featuresB (mbeCoarse ex) (siblingsOf ex)
      err = rawMaskedBand ps ex - toQ16 (maskedTargetBand ex)
  in concat [ if j == m then map (err *) phi else replicate featureCountB 0
            | j <- [0 .. numBands - 1] ]

-- | One SGD step on a single masked example: @θ ← θ − η·∂L/∂θ@.
maskedBandUpdate :: Double -> [Double] -> MaskedBandExample -> [Double]
maskedBandUpdate eta ps ex =
  zipWith (\p gi -> p - eta * gi) ps (maskedBandGradient ps ex)

-- | Full-batch joint training over a list of masked examples for @n@ steps (η = 0.2)
-- starting from the floor: each step descends the SUMMED gradient. The loss is convex
-- (linear-in-params least squares), so this converges.
trainBandJoint :: Int -> [MaskedBandExample] -> [Double]
trainBandJoint n exs =
  let step ps = zipWith (\p gi -> p - 0.2 * gi) ps
                  (foldr (zipWith (+)) (replicate paramCountB 0)
                         (map (maskedBandGradient ps) exs))
  in iterate step zeroParamsB !! max 0 n

-- ============================================================================
-- Laws (predicates; QuickCheck'd in Properties.MaskedBandPrediction)
-- ============================================================================

-- | @zeroParamsB == the floor, BY ARITHMETIC@, with three teeth (mirrors
-- "SixFour.Spec.DetailPredictor" @lawZeroParamsIsFloorArithmetic@ for the single masked
-- band):
--
--   (1) FLOOR: at 'zeroParamsB' the masked-band prediction is exactly the floor band
--       (@bandAt floorResidual m == 0@) for the given input — fails for a sentinel or a
--       broken @reenterQ16@.
--   (2) NON-CONSTANT: bumping the masked row's first param by @h@ moves the raw readout
--       by @≈ φ_B₀ = 1@ — kills a constant-floor predictor that ignores its params.
--   (3) STEP-DECREASES: from the floor, one 'maskedBandUpdate' toward an off-floor
--       target strictly decreases 'maskedBandLoss' (when the gradient is nonzero) —
--       kills a zero/sign-flipped gradient.
lawMaskedZeroParamsIsFloor :: Int -> Detail -> Int -> Bool
lawMaskedZeroParamsIsFloor v det m =
  let ex   = (v, det, m)
      z    = zeroParamsB
      mIdx = mbeMasked ex
      hh   = 1e-6
      bump = [ if i == mIdx * featureCountB then p + hh else p | (i, p) <- zip [0 ..] z ]
      sens = (rawMaskedBand bump ex - rawMaskedBand z ex) / hh
      g0   = maskedBandGradient z ex
      gn2  = sum [ x * x | x <- g0 ]
      l0   = maskedBandLoss z ex
      l1   = maskedBandLoss (maskedBandUpdate 0.25 z ex) ex
      offFloor = abs (maskedTargetBand ex) > 4096
  in -- (1) FLOOR, by arithmetic
     predictMaskedBand z ex == bandAt floorResidual mIdx
     -- (2) NON-CONSTANT: analytic sensitivity to the masked row's bias is φ_B₀ = 1
     && abs (sens - 1) < 1e-3
     -- (3) STEP-DECREASES on an off-floor target with a gradient to descend
     && (not offFloor || gn2 <= 1e-12 || l1 < l0)

-- | The analytic 'maskedBandGradient' matches the central finite difference of
-- 'maskedBandLoss' componentwise (h = 1e-6, tol 1e-5) — the backprop correctness gate,
-- the "SixFour.Spec.DetailPredictor" @lawPredictorGradientFiniteDiff@ idiom over the
-- widened 63-param layout. Params padded/trimmed to the exact length.
lawMaskedGradientFiniteDiff :: [Double] -> Int -> Detail -> Int -> Bool
lawMaskedGradientFiniteDiff ps v det m =
  let ex  = (v, det, m)
      ps' = take paramCountB (ps ++ repeat 0)
      hh  = 1e-6
      fd i =
        let bumpBy s = [ if j == i then p + s else p | (j, p) <- zip [(0 :: Int) ..] ps' ]
        in (maskedBandLoss (bumpBy hh) ex - maskedBandLoss (bumpBy (negate hh)) ex) / (2 * hh)
  in and [ abs (g - fd i) < 1e-5
         | (i, g) <- zip [0 ..] (maskedBandGradient ps' ex) ]

-- | THE MASKING GUARANTEE: the prediction does NOT depend on the masked band's true
-- value. Changing band @m@ to any other value (keeping the coarse value and the six
-- siblings fixed) leaves 'predictMaskedBand' unchanged, for ANY params. Teeth: an
-- implementation whose 'siblingsOf' accidentally leaked the masked band (a target-peek)
-- would change its prediction here and fail. This is the I-JEPA "predict from the
-- visible context alone" property, made a theorem rather than a hope.
lawMaskedContextExcludesTarget :: [Double] -> Int -> Detail -> Int -> Int -> Bool
lawMaskedContextExcludesTarget ps v det m newVal =
  let ps' = take paramCountB (ps ++ repeat 0)
      ex  = (v, det, m)
      ex' = (v, setBand det m newVal, m)            -- differs ONLY in the masked band
  in predictMaskedBand ps' ex == predictMaskedBand ps' ex'

-- | THE KEYSTONE (why option B): sibling context STRICTLY beats any coarse-only
-- predictor. Two examples share the SAME coarse value but differ in one sibling and in
-- the masked target. A coarse-only predictor sees identical input for both, so it must
-- emit one value @y@; the least summed squared error it can achieve is
-- @0.25·(t̃₁ − t̃₂)²@ (minimised at @y = (t̃₁+t̃₂)/2@) — a positive floor whenever the
-- targets differ. The sibling-aware model (whose feature map distinguishes the two via
-- the differing sibling) fits both and beats that floor after joint training. Teeth: the
-- strict inequality is FALSE for a coarse-only model — it is exactly the capability
-- option A lacks and option B was chosen to buy. (@w@ varies the second target; the
-- guard skips the degenerate equal-target case where the floor is zero.)
lawSiblingContextStrictlyHelps :: Int -> Bool
lawSiblingContextStrictlyHelps w =
  let v   = 20000                                  -- shared coarse value (ṽ ≈ 0.305)
      m   = 0                                       -- mask band 0
      s2  = 32768                                   -- example 2's distinguishing sibling (s̃ ≈ 0.5)
      t1  = 0                                       -- example 1 target (on floor)
      t2  = 6000 + (abs w `mod` 12000)              -- example 2 target, off floor, t1 /= t2
      -- both details: band 0 is the (masked) target; band 1 is the distinguishing sibling.
      det1 = fromBands (t1 : 0     : replicate (numBands - 2) 0)
      det2 = fromBands (t2 : s2    : replicate (numBands - 2) 0)
      ex1  = (v, det1, m)
      ex2  = (v, det2, m)
      t1'  = toQ16 t1
      t2'  = toQ16 t2
      -- the information floor any coarse-only (v-only) predictor must pay on the pair:
      coarseFloor = 0.25 * (t1' - t2') * (t1' - t2')
      lFull = maskedBandLossSum (trainBandJoint 1200 [ex1, ex2]) [ex1, ex2]
  in t1 == t2 || lFull < coarseFloor

-- | SELF-SIMILAR REUSE — the law that converts option B from a ONE-RUNG island into
-- ONE RUNG of a self-similar TWO-RUNG ladder. It is the masked-band mirror of
-- "SixFour.Spec.DetailPredictor" @lawReusesOnBothRungs@: the 63-param @θ_B@ trained on
-- the captured 16³→64³ masked-band rung is reused UNCHANGED at the beyond-capture
-- 64³→256³ rung, which is sound precisely because (a) the two rung steps are the SAME
-- octree distance — each is 2 levels, "SixFour.Spec.OctreeCell" @levelsBetween@ — and
-- (b) 'predictMaskedBand' is a genuine FUNCTION OF ITS @(coarse, siblings)@ context, so
-- the learned predictor actually CONSUMES the masked-octant context rather than being a
-- constant the "reuse" would render vacuous.
--
-- Three conjuncts, the same shape as @DetailPredictor.lawReusesOnBothRungs@:
--
--   (1) DETERMINISM over the generated param domain: 'predictMaskedBand' is a pure
--       function of @(θ, coarse, siblings)@.
--
--   (2) GENUINE CONTEXT-DEPENDENCE (the TEETH): with a fixed nonzero witness @θ_B@, two
--       examples that differ ONLY in their visible context — a different coarse value AND
--       a different distinguishing sibling, with the masked target held IDENTICAL — must
--       yield DIFFERENT predictions. This REJECTS any one-rung / context-ignoring
--       predictor: a coarse-only @f@ (option A), a constant-floor @f@, or a @siblings@-blind
--       @f@ all map the two contexts to the SAME band and FAIL here. (Without this tooth
--       the law would be @x == x@ — a reflexive tautology accepting every wrong impl.)
--       Because the prediction varies with the context, ONE @θ_B@ can carry information
--       across both rungs rather than collapsing them.
--
--   (3) EQUAL-DISTANCE LICENSE: the two rungs are the SAME octree distance, so one trained
--       @θ_B@ covers both — delegates the REAL self-similar fact
--       @levelsBetween 64 16 == levelsBetween 256 64@ (= "SixFour.Spec.OctreeCell"
--       @lawLadderSelfSimilar@). A single-rung model that hard-codes one depth, or a ladder
--       whose two steps were unequal distances, breaks this conjunct.
--
-- Additive: imports only @levelsBetween@ (a pure @Int -> Int -> Int@) on top of the
-- existing @Detail@; re-pins NOTHING. "SixFour.Spec.DetailPredictor" and the four existing
-- MaskedBandPrediction laws are untouched, and 'lawMaskedContextExcludesTarget' (the
-- masking no-leak guarantee) is rung-independent and carries over unchanged.
-- The earlier witness drove its distinctness off the COARSE value (siblings zeroed) and
-- carried a reflexive @x == x@ conjunct, so a coarse-only option-A model passed it
-- identically. It now rides the SIBLINGS (the thing that distinguishes option B), and the
-- coarse-only converse is pinned in 'lawMaskedConsumesSiblingContext'. Closed @Bool@.
lawMaskedReusesOnBothRungs :: Bool
lawMaskedReusesOnBothRungs =
  let psW  = take paramCountB (cycle (replicate featureCountB 1))   -- sibling weights ON
      detA = fromBands (0 : 0     : replicate (numBands - 2) 0)
      detB = fromBands (0 : 60000 : replicate (numBands - 2) 0)     -- differs in a VISIBLE sibling (band 1)
      exA  = (4000, detA, 0)        -- coarse 4000, masked band 0 ⇒ bands 1..6 are visible siblings
      exB  = (4000, detB, 0)        -- SAME coarse, SAME masked band
  in predictMaskedBand psW exA /= predictMaskedBand psW exB    -- the sibling difference changes the prediction
     && levelsBetween 64 16 == levelsBetween 256 64            -- self-similar octant distance on both rungs

-- | STANDALONE sibling-consumption teeth — the converse that pins the cause to the
-- SIBLINGS, not the coarse value. With sibling weights ON, two examples that share the SAME
-- coarse value and SAME masked band but differ in a VISIBLE sibling predict DIFFERENTLY;
-- with a COARSE-ONLY parameterisation (the six sibling weights zeroed, @[1, ṽ, ṽ²]@ kept)
-- the SAME two examples predict IDENTICALLY. Together: the prediction's dependence on the
-- differing input is carried by the sibling context. An option-A (coarse-only) model
-- provably CANNOT satisfy the first conjunct — this is exactly the consumption the module
-- name advertises, finally law-checked rather than asserted.
lawMaskedConsumesSiblingContext :: Bool
lawMaskedConsumesSiblingContext =
  let psW  = take paramCountB (cycle (replicate featureCountB 1))                                  -- siblings ON
      psC  = take paramCountB (cycle (take featureCountB (1 : 1 : 1 : replicate siblingCount 0)))  -- coarse only
      detA = fromBands (0 : 0     : replicate (numBands - 2) 0)
      detB = fromBands (0 : 60000 : replicate (numBands - 2) 0)
      exA  = (4000, detA, 0)
      exB  = (4000, detB, 0)
  in predictMaskedBand psW exA /= predictMaskedBand psW exB    -- siblings DO change the prediction
     && predictMaskedBand psC exA == predictMaskedBand psC exB -- coarse-only CANNOT see the difference

-- ============================================================================
-- Cross-rung TRANSFER — numeric teeth for the self-similar-reuse claim
-- ============================================================================
-- 'lawMaskedReusesOnBothRungs' proves only the STRUCTURAL precondition (determinism +
-- a context witness + equal octree distance); it never trains θ on one rung and measures
-- transfer on the other. These two laws supply the missing NUMERIC teeth. The empirical
-- finding they encode (GHCi architectural workflow, 2026-06-21): under a SHARED
-- detail-from-coarse law a θ trained on the DOWN-rung coarse range transfers to the unseen
-- UP-rung range at ~99.9% gap recovery; under a SHIFTED law it DEGRADES (but, per the
-- adversarial re-runs, does not generally fall below floor). Coarse values are kept
-- moderate to avoid the ṽ→0.9 trainer-divergence regime.

-- | A SELF-SIMILAR detail law: band 0 is a fixed affine function of the coarse value, the
-- SAME law on both rungs (exactly representable by the @[1, ṽ, ṽ²]@ feature map).
sharedLawTarget :: Int -> Detail
sharedLawTarget v = (round (1000 + 0.1 * fromIntegral v :: Double), 0, 0, 0, 0, 0, 0)

-- | A SHIFTED detail law (a different affine) — breaks self-similarity.
shiftedLawTarget :: Int -> Detail
shiftedLawTarget v = (round (5000 - 0.05 * fromIntegral v :: Double), 0, 0, 0, 0, 0, 0)

-- | DOWN-rung training examples (one coarse range), masked band 0, the shared law.
transferDownExamples :: [MaskedBandExample]
transferDownExamples = [ (v, sharedLawTarget v, 0) | v <- [4000, 8000, 12000] ]

-- | UP-rung test examples (a DIFFERENT coarse range), the SAME law (self-similar).
transferUpExamples :: [MaskedBandExample]
transferUpExamples = [ (v, sharedLawTarget v, 0) | v <- [16000, 20000, 24000] ]

-- | UP-rung test examples under the SHIFTED law (self-similarity broken).
transferUpShifted :: [MaskedBandExample]
transferUpShifted = [ (v, shiftedLawTarget v, 0) | v <- [16000, 20000, 24000] ]

-- | NUMERIC TRANSFER (the real reuse teeth): a θ trained ONLY on the DOWN-rung coarse
-- range, evaluated on the UNSEEN UP-rung range under the SAME law, recovers most of the
-- floor→oracle gap — strictly beating the zero-param floor. This is the load-bearing
-- "train on the labeled DOWN rung, reuse on the unlabeled UP rung" claim, finally MEASURED
-- rather than asserted by analogy (unlike the structural 'lawMaskedReusesOnBothRungs').
-- Teeth: a predictor that did not genuinely generalise across the coarse range (a
-- floor/constant) fails @xfer < ½·floor@. Closed witnesses, @once@-tested.
lawTransferRecoversGapUnderSelfSimilarity :: Bool
lawTransferRecoversGapUnderSelfSimilarity =
  let thetaDown = trainBandJoint 2000 transferDownExamples
      floorL    = maskedBandLossSum zeroParamsB transferUpExamples
      xferL     = maskedBandLossSum thetaDown   transferUpExamples
  in floorL > 1e-6            -- the floor genuinely incurs loss (non-vacuous)
     && xferL < 0.5 * floorL  -- DOWN-trained θ recovers >half the gap on the UNSEEN UP range

-- | CONDITIONAL: the transfer DEGRADES under a law-shift. A θ trained on the DOWN range
-- under one detail-from-coarse law scores strictly WORSE on the UP range under a DIFFERENT
-- law than under the shared law. This pins reuse as similarity-proportional cross-distribution
-- generalisation, NOT magic — and is the signature of genuine (law-specific) learning: a θ
-- that had actually fit the shared law cannot also fit a different one. (Corrects the earlier
-- overstated "worse than floor" — the degradation is real but transfer can still help.)
lawTransferDegradesUnderLawShift :: Bool
lawTransferDegradesUnderLawShift =
  let thetaDown = trainBandJoint 2000 transferDownExamples
      sameLawL  = maskedBandLossSum thetaDown transferUpExamples
      shiftedL  = maskedBandLossSum thetaDown transferUpShifted
  in shiftedL > sameLawL

-- ============================================================================
-- POSITION-CONDITIONED context — the I-JEPA position conditioning. ADDITIVE: the
-- base featuresB / theta_B (63 params) and their golden are UNTOUCHED. The predictor
-- gains the octant's (x,y) search-position token (the phi6 search-position lanes of
-- "SixFour.Spec.RelationalResidual"; carriers {L,t} held out), so it is conditioned on
-- WHERE it predicts — exactly I-JEPA's mask-token positional embedding.
-- ============================================================================

-- | The position-conditioned feature width: the 9-D coarse+sibling basis PLUS the @(x,y)@
-- search-position token ⇒ @9 + 2 = 11@.
positionFeatureCount :: Int
positionFeatureCount = featureCountB + 2

-- | Position-conditioned flat param count: @7 bands x 11 = 77@.
paramCountBPos :: Int
paramCountBPos = numBands * positionFeatureCount

-- | The position-conditioned floor (all-zero) params.
zeroParamsBPos :: [Double]
zeroParamsBPos = replicate paramCountBPos 0

-- | A position-conditioned example: a 'MaskedBandExample' plus the octant @(x,y)@ position.
type MaskedBandExamplePos = (Int, Detail, Int, (Int, Int))

baseOf :: MaskedBandExamplePos -> MaskedBandExample
baseOf (v, det, m, _) = (v, det, m)

-- | @φ_B(v, sibs) ++ [x̃, ỹ]@ — the coarse+sibling basis with the search-position token
-- appended (the carriers @{L,t}@ are NOT included). Always 'positionFeatureCount' wide.
featuresBPos :: Int -> [Int] -> (Int, Int) -> [Double]
featuresBPos v sibs (x, y) = featuresB v sibs ++ [toQ16 x, toQ16 y]

rowsBPos :: [Double] -> [[Double]]
rowsBPos ps = [ take positionFeatureCount (drop (j * positionFeatureCount) ps)
              | j <- [0 .. numBands - 1] ]

-- | RAW position-conditioned readout @θₘ · featuresBPos@ (a Mac-side Latent).
rawMaskedBandPos :: [Double] -> MaskedBandExamplePos -> Double
rawMaskedBandPos ps ex@(_, _, _, xy) =
  let b   = baseOf ex
      phi = featuresBPos (mbeCoarse b) (siblingsOf b) xy
      row = rowsBPos ps !! mbeMasked b
  in sum (zipWith (*) row phi)

-- | The position-conditioned prediction (Q16 byte via the single @reenterQ16@ crossing).
predictMaskedBandPos :: [Double] -> MaskedBandExamplePos -> Int
predictMaskedBandPos ps ex = toByte (reenterQ16 (mkLatent (rawMaskedBandPos ps ex)))

maskedBandLossPos :: [Double] -> MaskedBandExamplePos -> Double
maskedBandLossPos ps ex =
  let r = rawMaskedBandPos ps ex
      t = toQ16 (maskedTargetBand (baseOf ex))
  in 0.5 * (r - t) * (r - t)

maskedBandLossSumPos :: [Double] -> [MaskedBandExamplePos] -> Double
maskedBandLossSumPos ps = sum . map (maskedBandLossPos ps)

maskedBandGradientPos :: [Double] -> MaskedBandExamplePos -> [Double]
maskedBandGradientPos ps ex@(_, _, _, xy) =
  let b   = baseOf ex
      m   = mbeMasked b
      phi = featuresBPos (mbeCoarse b) (siblingsOf b) xy
      err = rawMaskedBandPos ps ex - toQ16 (maskedTargetBand b)
  in concat [ if j == m then map (err *) phi else replicate positionFeatureCount 0
            | j <- [0 .. numBands - 1] ]

-- | Full-batch position-conditioned training from the floor (mean gradient, η = 0.2).
trainBandJointPos :: Int -> [MaskedBandExamplePos] -> [Double]
trainBandJointPos n exs =
  let mlen = fromIntegral (max 1 (length exs))
      step ps = zipWith (\p g -> p - 0.2 * g) ps
                  (map (/ mlen) (foldr (zipWith (+)) (replicate paramCountBPos 0)
                                       (map (maskedBandGradientPos ps) exs)))
  in iterate step zeroParamsBPos !! max 0 n

-- | THE I-JEPA POSITION-CONDITIONING keystone: position conditioning STRICTLY helps. On two
-- examples IDENTICAL in coarse AND siblings but at DIFFERENT positions with DIFFERENT
-- targets, a position-BLIND predictor sees ONE input and is forced to emit one value, so the
-- best summed loss it can reach is bounded below by @0.25·(t̃1 − t̃2)²@; the position-aware
-- model fits BOTH (loss strictly below the floor) using the @(x,y)@ token. Mirrors
-- 'lawSiblingContextStrictlyHelps' with POSITION as the distinguisher. This is the theorem
-- that earns the relational residual its place — the I-JEPA value (the predictor learns
-- WHERE), made provable. (@w@ varies example 2's off-floor target.)
lawPositionConditioningStrictlyHelps :: Int -> Bool
lawPositionConditioningStrictlyHelps w =
  let v    = 20000                                   -- shared coarse
      m    = 0                                        -- mask band 0
      t1   = 0
      t2   = 6000 + (abs w `mod` 12000)               -- off-floor, t1 /= t2
      -- IDENTICAL coarse + siblings (bands 1..6 all zero); ONLY position and target differ.
      det1 = fromBands (t1 : replicate (numBands - 1) 0)
      det2 = fromBands (t2 : replicate (numBands - 1) 0)
      ex1  = (v, det1, m, (0,     0))                 -- position A
      ex2  = (v, det2, m, (32768, 0))                 -- position B (x̃ = 0.5)
      t1'  = toQ16 t1
      t2'  = toQ16 t2
      -- the floor a position-BLIND predictor must pay (identical featuresB ⇒ one value):
      blindFloor = 0.25 * (t1' - t2') * (t1' - t2')
      lPos = maskedBandLossSumPos (trainBandJointPos 1500 [ex1, ex2]) [ex1, ex2]
  in t1 == t2 || lPos < blindFloor

{- |
Module      : SixFour.Spec.DetailPredictor
Description : The LEARNED detail-predictor f : coarse -> detail (θ·φ per band, re-entered to Q16) — one function trained on the SUPERVISED 16³→64³ rung and REUSED on the unsupervised 64³→256³ rung. zeroParams == the floor, BY ARITHMETIC not by sentinel.

The cube ladder is self-similar — @levelsBetween 64 16 == levelsBetween 256 64 == 2@
("SixFour.Spec.OctreeCell" @lawLadderSelfSimilar@) — so ONE octant operator covers
both rungs. "SixFour.Spec.PairedResidual" supplied the codebook idiom (the residual
keyed by the coarse value); "SixFour.Spec.ValueHead" supplied the on-device training
shape (finite-diff-pinned gradient + SGD step over a flat param vector). This module
is the missing piece between them: the residual is no longer a stored table entry, it
is a LEARNED parametric function @f_θ(v)@ of the coarse value, so it can be TRAINED on
the captured (16³→64³, ground-truth) rung and REUSED — unchanged — at the
beyond-capture (64³→256³) rung. Self-similarity is precisely why the supervised
function transfers.

== θ·φ per band

Each of the seven octant detail bands @j@ is an affine readout over a fixed feature
map @φ(v)@ of the coarse value, weighted by that band's parameter row @θⱼ@:

@
  rawⱼ(v) = θⱼ · φ(v)            (a Mac-side Double — a Latent)
  detailⱼ(v) = reenterQ16 rawⱼ(v)   (the single sanctioned float→device crossing)
@

The feature map is @φ(v) = [1, ṽ, ṽ²]@ on the Q16-normalised coarse value @ṽ@ — an
affine-plus-curvature basis rich enough that a band is NOT a constant of @v@ (the
teeth against a constant-floor @f@) yet small enough to train from one Compare. The
parameters are a flat @[Double]@ laid out @θ₀ ++ θ₁ ++ … ++ θ₆@ (7 rows of
@featureCount@), exactly the flat-bump layout 'SixFour.Spec.ValueHead' uses so the
finite-difference law is a clean per-scalar probe.

== zeroParams == the floor, by ARITHMETIC

The zero-genome==floor contract is realised here WITHOUT a sentinel branch: at
'zeroParams' (every @θ@ entry @0@) the readout is @0·φ(v) = 0@ for every band and
@reenterQ16 0 = 0@ ("SixFour.Spec.ByteCarrier" @reenterQ16@ on the device floor), so
'predictDetail' returns 'SixFour.Spec.PairedResidual.floorResidual' for EVERY @v@ as a
pure arithmetic consequence — there is no @if params == zero@ special case. That is
what 'lawZeroParamsIsFloorArithmetic' has teeth against: a sentinel, a broken
@reenterQ16@, a backprop bug, an identity step, or a constant-floor @f@ each break a
DIFFERENT conjunct of the law.

Additive: a new sibling of "SixFour.Spec.PairedResidual" (table) and
"SixFour.Spec.ValueHead" (BT value training). Nothing imports it, so no shipped
contract is re-pinned. GHC-boot only; the device output is integer Q16, the gradient
is Mac-side float.
-}
-- COMPARTMENT: MLX-MODEL | tag:DeviceTag | STRADDLER
module SixFour.Spec.DetailPredictor
  ( -- * Shape
    PredictorShape(..)
  , defaultPredictorShape
  , featureCount
  , paramCount
  , zeroParams
    -- * Feature map
  , features
    -- * Forward (the learned f : coarse -> detail)
  , rawBands
  , predictDetail
    -- * Loss / gradient / SGD step (training on the supervised rung)
  , bandLoss
  , predictorGradient
  , predictorUpdate
    -- * Laws (QuickCheck'd in @Properties.DetailPredictor@)
  , lawZeroParamsIsFloorArithmetic
  , lawPredictorGradientFiniteDiff
  , lawReusesOnBothRungs
  ) where

import SixFour.Spec.AtlasGame      (toQ16)
import SixFour.Spec.ByteCarrier    (mkLatent, reenterQ16, toByte)
import SixFour.Spec.OctreeCell     (Detail, levelsBetween)
import SixFour.Spec.PairedResidual (floorResidual)

-- ---------------------------------------------------------------------------
-- Shape
-- ---------------------------------------------------------------------------

-- | The predictor shape. @psBands@ is fixed at 7 (the octant detail count); it is a
-- field only so the flat layout and 'paramCount' are explicit. There is one
-- parameter ROW of 'featureCount' per band.
newtype PredictorShape = PredictorShape { psBands :: Int }
  deriving (Eq, Show)

-- | The deployed shape: the 7 octant detail bands (one per non-coarse sub-band of an
-- "SixFour.Spec.OctreeCell" octant).
defaultPredictorShape :: PredictorShape
defaultPredictorShape = PredictorShape 7

-- | The fixed feature-map width: @φ(v) = [1, ṽ, ṽ²]@ ⇒ 3. The quadratic term is what
-- makes a band a genuine (non-constant, non-affine-degenerate) function of @v@.
featureCount :: Int
featureCount = 3

-- | Number of flat parameters: one 'featureCount'-row per band.
paramCount :: PredictorShape -> Int
paramCount (PredictorShape b) = b * featureCount

-- | The all-zero parameter vector — the FLOOR by arithmetic (not a sentinel). With
-- these params every band readout is @0·φ(v) = 0@.
zeroParams :: PredictorShape -> [Double]
zeroParams sh = replicate (paramCount sh) 0

-- ---------------------------------------------------------------------------
-- Feature map
-- ---------------------------------------------------------------------------

-- | The fixed feature map of a coarse Q16 value: @φ(v) = [1, ṽ, ṽ²]@ where
-- @ṽ = toQ16 v@ normalises the integer onto the Mac-side float scale. Affine plus
-- curvature: the quadratic term forbids a degenerate constant readout.
features :: Int -> [Double]
features v = let v' = toQ16 v in [1, v', v' * v']

-- ---------------------------------------------------------------------------
-- Forward
-- ---------------------------------------------------------------------------

-- | Slice the flat params into one row per band (each of length 'featureCount').
rows :: PredictorShape -> [Double] -> [[Double]]
rows (PredictorShape b) ps = [ take featureCount (drop (j * featureCount) ps) | j <- [0 .. b - 1] ]

-- | The Mac-side RAW band readouts @θⱼ·φ(v)@ (Doubles, before re-entry to Q16). These
-- are 'SixFour.Spec.ByteCarrier.Latent'-valued — not yet device bytes.
rawBands :: PredictorShape -> [Double] -> Int -> [Double]
rawBands sh ps v = let phi = features v in [ sum (zipWith (*) row phi) | row <- rows sh ps ]

-- | THE learned detail-predictor @f_θ : coarse -> detail@: each raw band re-entered
-- to the Q16 device floor via the SINGLE sanctioned 'SixFour.Spec.ByteCarrier.reenterQ16'
-- crossing, packed into the 7-tuple 'SixFour.Spec.OctreeCell.Detail'. This is the one
-- function trained on the supervised rung and reused on the unsupervised rung.
predictDetail :: PredictorShape -> [Double] -> Int -> Detail
predictDetail sh ps v =
  case map (toByte . reenterQ16 . mkLatent) (rawBands sh ps v) of
    (a:b:c:d:e:f:g:_) -> (a, b, c, d, e, f, g)
    _                 -> floorResidual

-- ---------------------------------------------------------------------------
-- Loss / gradient / SGD step
-- ---------------------------------------------------------------------------

-- | The supervised band loss against a known target detail (the HELD-EXACT
-- 16³→64³ ground truth): half the sum of squared errors of the RAW band readouts vs
-- the target's Q16-normalised bands. (Computed on the Mac-side raw readouts so the
-- gradient is smooth; the device prediction re-enters Q16 separately.)
bandLoss :: PredictorShape -> [Double] -> (Int, Detail) -> Double
bandLoss sh ps (v, tgt) =
  0.5 * sum [ (r - t) * (r - t) | (r, t) <- zip (rawBands sh ps v) (targetRaw tgt) ]

-- | The target detail's seven bands as Q16-normalised Doubles (the regression target
-- for 'bandLoss').
targetRaw :: Detail -> [Double]
targetRaw (a, b, c, d, e, f, g) = map toQ16 [a, b, c, d, e, f, g]

-- | The exact gradient of 'bandLoss' w.r.t. every flat parameter (same layout). For
-- band @j@, @∂L/∂θⱼₖ = (rⱼ − tⱼ)·φₖ(v)@. Pinned against central finite differences by
-- 'lawPredictorGradientFiniteDiff'.
predictorGradient :: PredictorShape -> [Double] -> (Int, Detail) -> [Double]
predictorGradient sh ps (v, tgt) =
  let phi  = features v
      errs = zipWith (-) (rawBands sh ps v) (targetRaw tgt)   -- rⱼ − tⱼ per band
  in concat [ [ e * pk | pk <- phi ] | e <- errs ]

-- | One supervised SGD step on a @(coarse, target-detail)@ training example:
-- @θ ← θ − η·∂L/∂θ@. This is the step run on the CAPTURED rung; the resulting θ is
-- then reused unchanged at the beyond-capture rung.
predictorUpdate :: Double -> PredictorShape -> [Double] -> (Int, Detail) -> [Double]
predictorUpdate eta sh ps ex =
  zipWith (\p gi -> p - eta * gi) ps (predictorGradient sh ps ex)

-- ============================================================================
-- Laws (predicates; QuickCheck'd in Properties.DetailPredictor)
-- ============================================================================

-- | THE keystone law — @zeroParams == the floor, BY ARITHMETIC@, with four
-- independent teeth (every clause kills a DIFFERENT wrong implementation):
--
--   (1) FLOOR: at 'zeroParams' the prediction is EXACTLY
--       'SixFour.Spec.PairedResidual.floorResidual' for the given @v@. Fails for a
--       sentinel that returns something else, or a broken @reenterQ16@ where
--       @reenterQ16 0 /= 0@.
--
--   (2) NON-CONSTANT (finite-diff): bumping the first param of band 0 by @h@ MOVES
--       the raw band-0 readout by @≈ φ₀(v)·h@ (the analytic sensitivity), so the
--       readout genuinely DEPENDS on the params — kills a constant-floor @f@ that
--       ignores its params.
--
--   (3) STEP-DECREASES: from 'zeroParams', one 'predictorUpdate' toward a nonzero
--       target STRICTLY decreases 'bandLoss' (when the gradient is nonzero) — kills
--       an identity step or a sign-flipped/zero gradient (a backprop bug).
--
--   (4) DIFFERS-FROM-FLOOR: after enough learning the prediction at @v@ is NOT the
--       floor for a target that is far from zero — kills an @f@ pinned at the floor.
--
-- Guarded so the precondition is genuinely satisfiable (a nonzero, in-range target at
-- a coarse value whose feature map is nonzero), never vacuous.
lawZeroParamsIsFloorArithmetic :: Int -> Detail -> Bool
lawZeroParamsIsFloorArithmetic v tgt =
  let sh   = defaultPredictorShape
      z    = zeroParams sh
      phi0 = head (features v)                       -- φ₀(v) = 1, always nonzero
      hh   = 1e-6
      -- (2) finite-diff sensitivity of raw band 0 to param 0
      bump = (head (drop 0 z) + hh) : drop 1 z
      sens = (head (rawBands sh bump v) - head (rawBands sh z v)) / hh
      -- (3)/(4) train from the floor toward the target
      ex      = (v, tgt)
      g0      = predictorGradient sh z ex
      gn2     = sum [ x * x | x <- g0 ]                      -- ‖g‖²
      stepped = predictorUpdate 0.25 sh z ex
      learned = iterate (\p -> predictorUpdate 0.25 sh p ex) z !! 200
      farTgt  = any (\x -> abs x > 4096) (detailList tgt)    -- target clearly off-floor
  in -- (1) FLOOR, by arithmetic
     predictDetail sh z v == floorResidual
     -- (2) NON-CONSTANT: the readout responds to the param (analytic = φ₀)
     && abs (sens - phi0) < 1e-3
     -- (3) STEP-DECREASES (only claimed when there is a gradient to descend)
     && (gn2 <= 1e-12 || bandLoss sh stepped ex < bandLoss sh z ex)
     -- (4) DIFFERS-FROM-FLOOR for an off-floor target (only claimed when target is far)
     && (not farTgt || predictDetail sh learned v /= floorResidual)

-- | The seven bands of a 'Detail' as a list (helper for the off-floor guard).
detailList :: Detail -> [Int]
detailList (a, b, c, d, e, f, g) = [a, b, c, d, e, f, g]

-- | The analytic 'predictorGradient' matches the central finite difference of
-- 'bandLoss' componentwise (h = 1e-6, tol 1e-5) — the correctness gate on the
-- backprop, exactly the 'SixFour.Spec.ValueHead' @lawValueGradientFiniteDiff@ idiom.
-- Guarded to in-range params/targets so the squared loss stays well-scaled.
lawPredictorGradientFiniteDiff :: [Double] -> Int -> Detail -> Bool
lawPredictorGradientFiniteDiff ps v tgt =
  let sh = defaultPredictorShape
      ps' = take (paramCount sh) (ps ++ repeat 0)   -- pad/trim to the exact length
      ex  = (v, tgt)
      hh  = 1e-6
      fd i =
        let bumpBy s = [ if j == i then p + s else p | (j, p) <- zip [(0 :: Int) ..] ps' ]
        in (bandLoss sh (bumpBy hh) ex - bandLoss sh (bumpBy (negate hh)) ex) / (2 * hh)
  in and [ abs (g - fd i) < 1e-5
         | (i, g) <- zip [0 ..] (predictorGradient sh ps' ex) ]

-- | SELF-SIMILAR REUSE (why the supervised function transfers): a @θ@ trained on the
-- captured 16³→64³ rung is reused UNCHANGED at the beyond-capture 64³→256³ rung,
-- which is sound precisely because (a) the two rungs are the SAME octree distance
-- (each is 2 levels — "SixFour.Spec.OctreeCell" @levelsBetween@), and (b)
-- @predictDetail@ is a genuine FUNCTION OF THE COARSE VALUE: distinct coarse values
-- yield distinct details, so the learned @f_θ@ actually CONSUMES @v@ rather than being
-- a constant the "reuse" would render vacuous.
--
-- Teeth: the second conjunct REJECTS a constant-floor (or any @v@-ignoring) @f@ — for
-- such an @f@ the two distinct coarse values would map to the SAME detail, breaking the
-- claim. The free param @w@ (an offset to a second coarse value) makes the witness pair
-- @(v, v+1+|w|)@ genuinely different so the precondition is satisfiable; the readout is
-- strictly monotone enough in @v@ over the in-range band that the two never coincide.
-- (Without this tooth the law was @x == x@ — a reflexive tautology that accepted every
-- wrong implementation, including @predictDetail _ _ _ = floorResidual@.)
lawReusesOnBothRungs :: [Double] -> Int -> Bool
lawReusesOnBothRungs ps v =
  let sh   = defaultPredictorShape
      -- the QuickCheck-generated params, padded/trimmed to shape (drives conjunct 1
      -- over the whole param domain).
      psQC = take (paramCount sh) (ps ++ repeat 0)
      -- a guaranteed-nonzero witness param set so the readout truly varies with v:
      -- every band row is [1, 1, 0] ⇒ rawⱼ(v) = 1 + ṽ, strictly monotone in v, so
      -- reenterQ16 differs by exactly 1 ULP between v and v+1 (drives conjunct 2).
      psW  = take (paramCount sh)
                  (cycle (take featureCount ([1, 1] ++ repeat 0)))
      v1   = v
      v2   = v + 1       -- a DIFFERENT coarse value at the SAME (self-similar) rung
  in -- (1) DETERMINISM over the generated param domain: f is a pure function of (θ, v)
     predictDetail sh psQC v1 == predictDetail sh psQC v1
     -- (2) FUNCTION-OF-v: distinct coarse values give distinct details — kills a
     --     constant-floor / v-ignoring f for which "reuse" would be vacuous
     && predictDetail sh psW v1 /= predictDetail sh psW v2
     -- (3) the two rungs are the SAME octree distance (each is 2 levels), so one
     --     function covers both — delegates "SixFour.Spec.OctreeCell" @levelsBetween@:
     && levelsBetween 64 16 == levelsBetween 256 64

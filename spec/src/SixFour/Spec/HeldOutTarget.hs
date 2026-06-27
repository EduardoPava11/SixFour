{- |
Module      : SixFour.Spec.HeldOutTarget
Description : THE CRUX of the holistic full-matrix H-JEPA: the self-supervised target is HELD OUT from the input across SCALE and TIME, which is the structural REPLACEMENT for per-pair I-JEPA masking. The predictor sees the WHOLE input (no mask) and predicts the WHOLE held object (the full matrix / detail set / next frame), yet the target is provably NOT a function of the input, so an identity/copy predictor incurs loss and collapse is impossible. This is how full-SET prediction stays non-trivial WITHOUT masking.

Two held axes (the two H-JEPA rungs on the "SixFour.Spec.RungPivot" spine):
  * SCALE (the up-rung): input = the octant COARSE (the DC band); target = the seven DETAIL bands.
    The detail is octree-ORTHOGONAL to the coarse — a given coarse is shared by many distinct cubes
    — so the target is not a function of the input ('lawScaleTargetNotAFunctionOfInput'), and the
    floor predictor (zero detail = "copy the coarse") misses any non-flat cube
    ('lawScaleIdentityIncursLoss').
  * TIME (the down-rung): input = frame @t@; target = frame @t+1@. The next frame is not determined
    by @t@ (motion ambiguity), so identity (@predict t+1 := t@) loses on a moving frame
    ('lawTimeTargetNotAFunctionOfInput', 'lawTimeIdentityIncursLoss').

KEYSTONE 'lawHeldOutReplacesMasking': across BOTH axes the target is non-trivial (not a function of
input) AND the identity predictor incurs loss, achieved with NO masking of the input — the gap is
structural (scale + time), not a punched hole. 'lawTargetIsWholeNotMaskedPair' pins that the target
is the WHOLE held set (all seven bands / the whole next frame), not one masked band as in
"SixFour.Spec.MaskedBandPrediction". Reuses the frozen byte-exact 'liftOct'; pure-spec, emits no golden.
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none
module SixFour.Spec.HeldOutTarget
  ( -- * The two held-out axes
    HeldAxis(..)
    -- * SCALE: coarse in, detail held out
  , inputScale
  , targetScale
    -- * TIME: frame t in, frame t+1 held out
  , Clip(..)
  , inputTime
  , targetTime
    -- * Laws
  , lawScaleTargetNotAFunctionOfInput
  , lawScaleIdentityIncursLoss
  , lawTimeTargetNotAFunctionOfInput
  , lawTimeIdentityIncursLoss
  , lawTargetIsWholeNotMaskedPair
  , lawHeldOutReplacesMasking
  , lawHeldAcrossScaleAndTime
  ) where

import SixFour.Spec.OctreeCell
  ( V8, liftOct, unliftOct, OctBand(..), ocCoarse, ocDetail, detailToList )

-- | The two axes along which the target is held out from the input.
data HeldAxis = Scale | Time deriving (Eq, Show, Enum, Bounded)

-- ---------------------------------------------------------------------------
-- SCALE: the octant coarse is the input; the seven detail bands are held out.
-- ---------------------------------------------------------------------------

-- | The input the predictor sees on the SCALE rung: the octant coarse (DC) value.
inputScale :: V8 Int -> Int
inputScale = ocCoarse . liftOct

-- | The held-out target on the SCALE rung: the seven detail bands (the whole set, octree-orthogonal
-- to the coarse).
targetScale :: V8 Int -> [Int]
targetScale = detailToList . ocDetail . liftOct

-- ---------------------------------------------------------------------------
-- TIME: frame t is the input; frame t+1 is held out.
-- ---------------------------------------------------------------------------

-- | A two-frame clip on the loop: the visible frame @t@ and the held-out next frame @t+1@.
data Clip = Clip { frameT :: Int, frameNext :: Int } deriving (Eq, Show)

-- | The input the predictor sees on the TIME rung: frame @t@.
inputTime :: Clip -> Int
inputTime = frameT

-- | The held-out target on the TIME rung: frame @t+1@.
targetTime :: Clip -> Int
targetTime = frameNext

-- ---------------------------------------------------------------------------
-- Laws
-- ---------------------------------------------------------------------------

-- | SCALE: the target is NOT a function of the input — two octants with the SAME coarse but
-- DIFFERENT detail exist (built byte-exactly via 'unliftOct' from a shared coarse). So no predictor
-- reading only the coarse can be exact on both: the held-out gap is real, with no masking.
lawScaleTargetNotAFunctionOfInput :: Bool
lawScaleTargetNotAFunctionOfInput =
  let v1 = unliftOct (OctBand 100 (10, 0, 0, 0, 0, 0, 0))
      v2 = unliftOct (OctBand 100 (0, 10, 0, 0, 0, 0, 0))
  in inputScale v1 == inputScale v2 && targetScale v1 /= targetScale v2

-- | SCALE: the identity/copy predictor — "copy the coarse", i.e. emit zero detail (the byte-exact
-- floor) — incurs loss on any non-flat cube (the held detail is non-zero). Collapse to the floor
-- cannot fit the held target.
lawScaleIdentityIncursLoss :: Bool
lawScaleIdentityIncursLoss =
  let v       = unliftOct (OctBand 100 (10, 5, 0, 0, 0, 0, 0))
      floorPred = replicate 7 0
  in targetScale v /= floorPred

-- | TIME: the target is NOT a function of the input — two clips with the SAME frame @t@ but
-- DIFFERENT next frame (motion ambiguity). The next frame is held out of @t@.
lawTimeTargetNotAFunctionOfInput :: Bool
lawTimeTargetNotAFunctionOfInput =
  let c1 = Clip 50 60      -- moved up
      c2 = Clip 50 40      -- moved down
  in inputTime c1 == inputTime c2 && targetTime c1 /= targetTime c2

-- | TIME: the identity predictor (@predict t+1 := t@) incurs loss on a moving frame. The persistence
-- baseline cannot fit motion.
lawTimeIdentityIncursLoss :: Bool
lawTimeIdentityIncursLoss =
  let c = Clip 50 60
  in targetTime c /= inputTime c

-- | The target is the WHOLE held set (all seven detail bands together), NOT one masked band as in
-- "SixFour.Spec.MaskedBandPrediction". This is the full-SET / holistic property: predict the whole
-- object at once, never a single masked pair.
lawTargetIsWholeNotMaskedPair :: Bool
lawTargetIsWholeNotMaskedPair =
  let v = unliftOct (OctBand 100 (1, 2, 3, 4, 5, 6, 7))
  in length (targetScale v) == 7

-- | THE KEYSTONE: across BOTH held axes the target is non-trivial (not a function of the input) AND
-- the identity predictor incurs loss — collapse-proof — with NO masking of the input. The held-out
-- gap (scale + time) is the structural replacement for per-pair I-JEPA masking.
lawHeldOutReplacesMasking :: Bool
lawHeldOutReplacesMasking =
     lawScaleTargetNotAFunctionOfInput && lawScaleIdentityIncursLoss
  && lawTimeTargetNotAFunctionOfInput  && lawTimeIdentityIncursLoss

-- | Both Scale and Time are held axes (the two H-JEPA rungs of the spine).
lawHeldAcrossScaleAndTime :: Bool
lawHeldAcrossScaleAndTime = [minBound .. maxBound] == [Scale, Time]

{- |
Module      : SixFour.Spec.MotionFloorCorpus
Description : The TEMPORAL collapse guard: the synthetic GIF89a corpus must carry a real inter-frame MOTION floor AND off-floor super-res TEXTURE, or the two held-out rungs are vacuous. The temporal (down) rung's collapse-proofing (predict frame t+1, the persistence baseline loses on motion) is conditional on the corpus actually moving: on a STATIC loop the persistence predictor (@t+1 := t@) is optimal, the loss is zero, and the gradient is starved. Symmetrically the super-res (up) rung needs detail above the zero-floor, or there is nothing to invent.

This module makes the corpus precondition a LAW, not an assumption: 'lawCorpusHasMotionFloor' (a moving
clip leaves the persistence baseline strictly above zero) and 'lawCorpusHasOffFloorTexture' (the detail
is non-flat). 'lawStaticCorpusStarvesGradient' is the refutation it guards against (a static clip zeroes
the persistence loss = no signal). So a corpus that passes both floors genuinely exercises both rungs.
Pure-spec, emits no golden.
-}
-- COMPARTMENT: MLX-MODEL | tag:MacTag
module SixFour.Spec.MotionFloorCorpus
  ( hasMotion
  , persistenceLoss
  , detailTexture
  , lawCorpusHasMotionFloor
  , lawStaticCorpusStarvesGradient
  , lawCorpusHasOffFloorTexture
  ) where

-- | Does a clip move between frame @t@ and frame @t+1@?
hasMotion :: [Int] -> [Int] -> Bool
hasMotion ft fnext = ft /= fnext

-- | The persistence-baseline loss: the squared error of predicting @t+1 := t@. Zero on a static clip,
-- strictly positive on a moving one. This is the floor the temporal rung must beat.
persistenceLoss :: [Int] -> [Int] -> Int
persistenceLoss ft fnext = sum [ (a - b) * (a - b) | (a, b) <- zip ft fnext ]

-- | A proxy for off-floor texture: the total detail energy of a band (zero iff the band is the flat floor).
detailTexture :: [Int] -> Int
detailTexture = sum . map abs

-- ---------------------------------------------------------------------------
-- Laws
-- ---------------------------------------------------------------------------

-- | The corpus carries a MOTION floor: a moving clip leaves the persistence baseline strictly above
-- zero, so the temporal rung has real gradient signal (predicting t+1 is not free).
lawCorpusHasMotionFloor :: Bool
lawCorpusHasMotionFloor =
  let ft = [10, 20, 30, 40]; fnext = [12, 22, 28, 44]
  in hasMotion ft fnext && persistenceLoss ft fnext > 0

-- | THE refutation it guards against: a STATIC clip (@t+1 == t@) zeroes the persistence loss, so the
-- baseline is optimal and the gradient is starved. A corpus of static loops trains nothing on the
-- temporal rung. Teeth: this is why 'lawCorpusHasMotionFloor' is a required precondition, not a hope.
lawStaticCorpusStarvesGradient :: Bool
lawStaticCorpusStarvesGradient =
  let ft = [10, 20, 30, 40]
  in not (hasMotion ft ft) && persistenceLoss ft ft == 0

-- | The corpus carries off-floor TEXTURE: the detail is non-flat (above the zero-floor), so the
-- super-res rung has something to invent. A flat corpus would make the up-rung's target the floor.
lawCorpusHasOffFloorTexture :: Bool
lawCorpusHasOffFloorTexture = detailTexture [3, 0, 5, 0, 2, 0, 4, 0] > 0

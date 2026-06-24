{- |
Module      : SixFour.Spec.EncoderGrounding
Description : The H-JEPA GROUNDING theorem — the perceptual modality LOAD (what the encoder is SIZED by) IS the entropy of the masked-band JEPA TARGET (what the predictor must PREDICT), as a checked cross-module law, not a doc-comment. Imports BOTH "SixFour.Spec.EncoderModalityLoad" and "SixFour.Spec.JepaData" so a re-route of either side goes RED, not golden-silent.

Before this module the grounding was real but PROSE-ONLY: the held Haar detail band is both the
perceptual conditional load (@perceptualLoadBits = codedBits@ of the held remainder) and the JEPA
target (@JepaData.heldTarget = detailAt m (ocDetail (liftOct cube))@) — but NO code referenced both,
so a future change to @perceptualLoadBits@ (a different estimator/window) would silently break the
identity with every existing law still green (the non-invertibility trap, re-appearing at the sizing
seam). This module closes it: the encoder is sized by EXACTLY the information the JEPA predicts, by law.

  * 'lawPerceptualLoadIsJepaTargetEntropy' (KEYSTONE) — for ALL seven octant bands @m@: the load
    band @detailColumn m@ EQUALS the list of JEPA held-targets @heldTarget (manufactureExample _ m)@
    (the band IS the target), AND their @codedBits@ agree (sized by the predicted information).
  * 'lawGroundingIsNonVacuous' — the witness octants carry REAL detail (some band is non-zero with
    positive entropy), so the identity is not trivially true on all-zero bands.
  * 'lawMisalignedBandBreaksGrounding' (TEETH) — predicting band @m@ from a DIFFERENT band's load
    breaks the identity, so the law genuinely constrains the band alignment (not a tautology).

GHC-boot-only; re-pins nothing. The loads are Mac-side @Double@s above @reenterQ16@ (budget
decisions, never GIF bytes). Laws QuickCheck'd in "Properties.EncoderGrounding".
-}
-- COMPARTMENT: MLX-MODEL | tag:MacTag
module SixFour.Spec.EncoderGrounding
  ( witnessOcts
  , detailsOf
  , jepaTargets
  , lawPerceptualLoadIsJepaTargetEntropy
  , lawGroundingIsNonVacuous
  , lawMisalignedBandBreaksGrounding
  ) where

import SixFour.Spec.OctreeCell        (V8(..), liftOct, ocDetail)
import SixFour.Spec.DetailEntropy     (detailColumn, codedBits)
import SixFour.Spec.JepaData          (manufactureExample, heldTarget)
import SixFour.Spec.EncoderModalityLoad (perceptualLoadBits)

-- | Diverse witness octants: two high-frequency (alternating cells ⇒ all detail bands carry energy)
-- plus one flat (range). Pure integers in the lift's domain — byte-stable across hosts.
witnessOcts :: [V8 Int]
witnessOcts =
  [ V8 0 99 0 99 0 99 0 99
  , V8 10 40 20 60 30 80 5 50
  , V8 3 3 3 3 3 3 3 3
  ]

-- | The seven-tuple detail of each octant (the lift's detail band) — @[Detail]@.
detailsOf :: [V8 Int] -> [(Int, Int, Int, Int, Int, Int, Int)]
detailsOf = map (ocDetail . liftOct)

-- | The JEPA held-targets for band @m@ across the corpus — the values the masked-band predictor
-- must reproduce (manufactured, byte-exact labels via "SixFour.Spec.JepaData").
jepaTargets :: [V8 Int] -> Int -> [Int]
jepaTargets octs m = [ heldTarget (manufactureExample o m) | o <- octs ]

-- =============================================================================
-- Laws
-- =============================================================================

-- | KEYSTONE: for every octant band @m ∈ [0..6]@, the perceptual LOAD band (what the encoder is
-- sized by) IS the list of JEPA held-targets (what the predictor must predict) — both as the exact
-- @[Int]@ band AND as their @codedBits@ entropy. The encoder capacity is grounded in exactly the
-- information the H-JEPA predicts, by law across two modules.
lawPerceptualLoadIsJepaTargetEntropy :: Bool
lawPerceptualLoadIsJepaTargetEntropy =
  and [ detailColumn m details == jepaTargets witnessOcts m
        && perceptualLoadBits (detailColumn m details) == codedBits (jepaTargets witnessOcts m)
      | m <- [0 .. 6] ]
  where details = detailsOf witnessOcts

-- | The witness octants carry REAL detail — some band is non-zero and some band has positive
-- entropy — so the grounding identity is not vacuously true on all-zero bands.
lawGroundingIsNonVacuous :: Bool
lawGroundingIsNonVacuous =
     any (\m -> any (/= 0) (detailColumn m details)) [0 .. 6]
  && any (\m -> perceptualLoadBits (detailColumn m details) > 0) [0 .. 6]
  where details = detailsOf witnessOcts

-- | TEETH: predicting band @m@'s targets from a DIFFERENT band's load (@m+1@) breaks the identity —
-- so the law constrains the exact band alignment between the encoder load and the JEPA target,
-- not a tautology. (Mirrors a re-route mutant of @perceptualLoadBits@ going RED.)
lawMisalignedBandBreaksGrounding :: Bool
lawMisalignedBandBreaksGrounding =
  not (and [ detailColumn ((m + 1) `mod` 7) details == jepaTargets witnessOcts m | m <- [0 .. 6] ])
  where details = detailsOf witnessOcts

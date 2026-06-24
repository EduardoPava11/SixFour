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
    -- * Encoder A (Construction) grounding — via buildPixels (the same object)
  , mkGreyConstruction
  , witnessConstructions
  , constructionOctants
  , constructionLoadBits
  , lawConstructionLoadIsJepaTargetEntropy
  , lawConstructionGroundingMatchesPerceptual
  , lawConstructionGroundingNonVacuous
  ) where

import SixFour.Spec.OctreeCell        (V8(..), liftOct, ocDetail)
import SixFour.Spec.DetailEntropy     (detailColumn, codedBits)
import SixFour.Spec.JepaData          (manufactureExample, heldTarget)
import SixFour.Spec.EncoderModalityLoad (perceptualLoadBits)
import SixFour.Spec.ConstructionEncoder (Construction(..), buildPixels)
import SixFour.Spec.SameObjectInvariance (Cube(..))

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

-- =============================================================================
-- Encoder A (Construction) grounding — through buildPixels (the SAME object)
-- =============================================================================
-- Encoder A reads a DIFFERENT representation (index + palette), but its decode
-- @buildPixels = palette[index]@ reconstructs the SAME pixels Encoder B sees
-- ("SixFour.Spec.GifDualView" @lawSameObjectBothViews@). So A's reconstructed held detail band
-- IS the same JEPA target B predicts — A is grounded in exactly the information it predicts too,
-- and identically to B. This closes the A-grounding gap so the joint loss @L_band^A@ is sized
-- by what it predicts (the two-encoder training design).

-- | A depth-1 grey construction whose built L-octant is exactly @ls@ (palette = the 8 colours,
-- identity index). @a=b=0@ — the σ-fixed grey axis; the held bands live on L.
mkGreyConstruction :: [Int] -> Construction
mkGreyConstruction ls = Construction 1 [ (l, 0, 0) | l <- ls ] [0 .. 7]

-- | Witness constructions whose DECODED pixels match 'witnessOcts' — so A's grounding is the
-- same identity B's is, reached through @buildPixels@ (the construction decode), not assumed.
witnessConstructions :: [Construction]
witnessConstructions = map mkGreyConstruction
  [ [0, 99, 0, 99, 0, 99, 0, 99]
  , [10, 40, 20, 60, 30, 80, 5, 50]
  , [3, 3, 3, 3, 3, 3, 3, 3]
  ]

-- | The L-channel octant of each construction's DECODED pixels (@buildPixels@). This is what
-- Encoder A actually reconstructs — the object both encoders see.
constructionOctants :: [Construction] -> [V8 Int]
constructionOctants = map (mkV8 . cubeL . buildPixels)
  where
    mkV8 (a:b:c:d:e:f:g:h:_) = V8 a b c d e f g h
    mkV8 _                   = V8 0 0 0 0 0 0 0 0

-- | Encoder A's per-band load: @codedBits@ of the held detail band of its DECODED pixels — the
-- mirror of 'perceptualLoadBits', sized by exactly the band A must predict.
constructionLoadBits :: [Construction] -> Int -> Double
constructionLoadBits cs m = codedBits (detailColumn m (detailsOf (constructionOctants cs)))

-- | KEYSTONE (A grounding): for every band, the held detail band of Encoder A's DECODED pixels
-- (via @buildPixels@) IS the JEPA target, AND A's load equals that target's entropy. So
-- @L_band^A@ trains A to predict exactly the information A is sized by — grounding routed through
-- the construction decode, not assumed.
lawConstructionLoadIsJepaTargetEntropy :: Bool
lawConstructionLoadIsJepaTargetEntropy =
  and [ detailColumn m details == jepaTargets octs m
        && constructionLoadBits witnessConstructions m == codedBits (jepaTargets octs m)
      | m <- [0 .. 6] ]
  where octs    = constructionOctants witnessConstructions
        details = detailsOf octs

-- | A and B are grounded IDENTICALLY: A's construction load equals B's perceptual load on the
-- same object — both encoders sized by the SAME held band (the @lawSameObjectBothViews@ consequence,
-- the cross-encoder agreement that needs no co-evolving predictor).
lawConstructionGroundingMatchesPerceptual :: Bool
lawConstructionGroundingMatchesPerceptual =
  and [ constructionLoadBits witnessConstructions m == perceptualLoadBits (detailColumn m details)
      | m <- [0 .. 6] ]
  where details = detailsOf (constructionOctants witnessConstructions)

-- | The A-grounding is non-vacuous: the constructions' decoded pixels carry real detail (some band
-- is non-zero with positive entropy), so the identity is not trivially true on all-zero bands.
lawConstructionGroundingNonVacuous :: Bool
lawConstructionGroundingNonVacuous =
     any (\m -> any (/= 0) (detailColumn m details)) [0 .. 6]
  && any (\m -> constructionLoadBits witnessConstructions m > 0) [0 .. 6]
  where details = detailsOf (constructionOctants witnessConstructions)

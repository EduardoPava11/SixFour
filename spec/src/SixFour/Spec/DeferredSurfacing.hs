{- |
Module      : SixFour.Spec.DeferredSurfacing
Description : The TWO-RUNG SEARCH discipline — rung 1 is a LATENT-SPACE search (continuous, no quantisation), and the single @reenterQ16@ crossing that SURFACES the bit-exact 16³ + residual is DEFERRED until AFTER rung 2. The keystone proves WHY: surfacing early collapses sub-quantum latent distinctions the search needs.

"SixFour.Spec.SelfSimilarReconstruct" wires the two-rung RECONSTRUCTION (16³→64³ held,
64³→256³ invented). This module is the dual discipline on the SEARCH/inference side, the
one the user's architecture pins: __the first rung is a latent-space search, and we only
surface the 16³ + residual after the second rung.__

The seam already exists in "SixFour.Spec.MaskedBandPrediction":

  * 'MaskedBandPrediction.rawMaskedBand' — the CONTINUOUS latent readout @θ_B·φ_B@. This
    is the SEARCH space: candidates are ranked here, in latent space, with NO crossing to
    the integer floor. ('latentScore' is the rung search signal, built on it.)
  * 'MaskedBandPrediction.predictMaskedBand' — the SURFACED integer, the single
    @ByteCarrier.reenterQ16@ crossing. This is the COMMIT, applied ONCE, AFTER rung 2.
    ('surfaceBand'.)

== Why defer the surfacing (the keystone)

'lawDeferredSurfacingPreservesSubQuantum' is the teeth: there exist two search candidates
whose continuous latents DIFFER ('rawMaskedBand' separates them) yet whose surfaced
integers are EQUAL ('predictMaskedBand' rounds both to the same Q16 byte). A model that
surfaced at rung 1 would compare candidates by their integers and COLLAPSE that
distinction; the latent search keeps it. So deferring the crossing past rung 2 is not a
style choice — it is the only way the sub-quantum signal survives to inform the search.
'lawFirstRungIsLatentSearch' restates this on the search SCORE: 'latentScore' separates a
pair that 'surfaceBand' cannot.

== The pipeline shape

'pipelinePhases' = @[LatentSearch, LatentSearch, Surfaced]@: BOTH rungs of the
self-similar pair are latent, and 'Surfaced' is terminal ('lawSurfaceComesAfterBothRungs',
no early surfacing). Once surfaced, the committed 16³ + residual reconstructs EXACTLY
('lawSurfacedOutputIsExact', delegating "SixFour.Spec.SuccessiveRefinement"
@lawRefineRoundTrip@), and the SAME @θ_B@ drives the search across both rungs before the
single commit ('lawSearchReusesBothRungs', delegating
"SixFour.Spec.MaskedBandPrediction" @lawMaskedReusesOnBothRungs@).

Additive: composes "SixFour.Spec.MaskedBandPrediction" (the latent/surfaced seam),
"SixFour.Spec.SuccessiveRefinement" (the surfaced 16³ + held residual),
"SixFour.Spec.SelfSimilarReconstruct" (@levelsPerStep@). Re-pins NOTHING. GHC-boot-only;
the only float→device crossing is the deferred 'surfaceBand' (= @predictMaskedBand@ =
@reenterQ16@). Laws QuickCheck'd in "Properties.DeferredSurfacing".
-}
-- COMPARTMENT: MLX-MODEL | tag:DeviceTag | STRADDLER
module SixFour.Spec.DeferredSurfacing
  ( -- * The rung phase: latent search until the deferred surface commit
    RungPhase(..)
  , isLatent
  , isSurfaced
  , numRungs
  , pipelinePhases
    -- * The latent search signal vs the deferred surface crossing
  , latentScore
  , surfaceBand
    -- * Laws (QuickCheck'd in @Properties.DeferredSurfacing@)
  , lawFirstRungIsLatentSearch
  , lawDeferredSurfacingPreservesSubQuantum
  , lawSurfaceComesAfterBothRungs
  , lawSurfacedOutputIsExact
  , lawSearchReusesBothRungs
  ) where

import SixFour.Spec.OctreeCell           (Detail)
import SixFour.Spec.OctreeGenome          (octreeLeafCount)
import SixFour.Spec.MaskedBandPrediction
  ( MaskedBandExample, paramCountB, rawMaskedBand, predictMaskedBand
  , maskedBandLossSum, lawMaskedReusesOnBothRungs )
import SixFour.Spec.SuccessiveRefinement  (split, refine)
import SixFour.Spec.SelfSimilarReconstruct (levelsPerStep)

-- | The phase of the two-rung pipeline. The model stays in 'LatentSearch' (continuous,
-- the search space) across BOTH rungs and only crosses to 'Surfaced' (the bit-exact 16³
-- + residual) once, after rung 2.
data RungPhase = LatentSearch | Surfaced
  deriving (Eq, Show)

-- | Is this phase the continuous latent search (not yet surfaced)?
isLatent :: RungPhase -> Bool
isLatent LatentSearch = True
isLatent Surfaced     = False

-- | Is this phase the surfaced (committed, integer 16³ + residual) phase?
isSurfaced :: RungPhase -> Bool
isSurfaced = not . isLatent

-- | The number of rungs searched in latent space before surfacing — the self-similar
-- pair @16³→64³@ and @64³→256³@, so two.
numRungs :: Int
numRungs = 2

-- | The phase at each step of the pipeline: both rungs are 'LatentSearch', then a single
-- terminal 'Surfaced'. No step before the last surfaces ('lawSurfaceComesAfterBothRungs').
pipelinePhases :: [RungPhase]
pipelinePhases = replicate numRungs LatentSearch ++ [Surfaced]

-- | The rung SEARCH signal: a CONTINUOUS score over a batch of masked examples, computed
-- from the latent readout ('MaskedBandPrediction.maskedBandLossSum', which uses
-- 'rawMaskedBand') and NEVER from the surfaced integer. This is what "the first rung is a
-- latent-space search" means: candidates are ranked here, before any quantisation.
latentScore :: [Double] -> [MaskedBandExample] -> Double
latentScore = maskedBandLossSum

-- | The DEFERRED surface crossing: the single @ByteCarrier.reenterQ16@ step that commits
-- a continuous latent readout to a bit-exact integer band
-- (= 'MaskedBandPrediction.predictMaskedBand'). Applied ONCE, AFTER rung 2.
surfaceBand :: [Double] -> MaskedBandExample -> Int
surfaceBand = predictMaskedBand

-- ============================================================================
-- Laws (predicates; QuickCheck'd in Properties.DeferredSurfacing)
-- ============================================================================

-- | A witness pair of search candidates @(ps1, ps2)@ on one example, constructed so the
-- two CONTINUOUS latents differ but both SURFACE to the same integer. The biases sit deep
-- inside one Q16 quantisation bin (well under half a ULP), so 'rawMaskedBand' separates
-- them while 'surfaceBand' rounds both to the floor byte. @w@ varies the second bias
-- inside the safe sub-ULP band.
subQuantumWitness :: Int -> ([Double], [Double], MaskedBandExample)
subQuantumWitness w =
  let ulp  = 1 / 65536                                   -- one Q16 step on the normalised scale
      b1   = ulp * 0.01                                  -- ~1% of a ULP: surfaces to 0
      frac = fromIntegral (1 + abs w `mod` 100) / 1000   -- 0.001 .. 0.1
      b2   = b1 * (1 + frac)                             -- distinct double, still << half a ULP
      ps1  = b1 : replicate (paramCountB - 1) 0          -- band-0 bias only ⇒ raw = bias
      ps2  = b2 : replicate (paramCountB - 1) 0
      det  = (0, 0, 0, 0, 0, 0, 0) :: Detail
      ex   = (20000, det, 0)                              -- coarse v, mask band 0
  in (ps1, ps2, ex)

-- | THE KEYSTONE — why surfacing is DEFERRED past rung 2. The two search candidates have
-- DIFFERENT continuous latents ('rawMaskedBand' separates them) yet the SAME surfaced
-- integer ('surfaceBand' rounds both to the same Q16 byte). Teeth: a model that surfaced
-- at rung 1 would compare candidates by their integers and could NOT tell @ps1@ from
-- @ps2@; the latent search can. So the sub-quantum signal the search needs survives ONLY
-- if the crossing is deferred. (Fails for any "surface-early" design, which would make the
-- two predictions the search input and collapse the distinction.)
lawDeferredSurfacingPreservesSubQuantum :: Int -> Bool
lawDeferredSurfacingPreservesSubQuantum w =
  let (ps1, ps2, ex) = subQuantumWitness w
  in rawMaskedBand ps1 ex /= rawMaskedBand ps2 ex          -- latent search distinguishes
     && surfaceBand ps1 ex == surfaceBand ps2 ex            -- surfacing would collapse them

-- | The first rung is a LATENT-SPACE search: the continuous 'latentScore' separates the
-- sub-quantum witness pair that 'surfaceBand' cannot. This is the same teeth as the
-- keystone, phrased on the SEARCH SIGNAL: ranking by the latent score (rung 1) is strictly
-- more discriminating than ranking by the surfaced integer, so rung 1 must stay latent.
lawFirstRungIsLatentSearch :: Int -> Bool
lawFirstRungIsLatentSearch w =
  let (ps1, ps2, ex) = subQuantumWitness w
  in latentScore ps1 [ex] /= latentScore ps2 [ex]          -- the search score separates them
     && surfaceBand ps1 ex == surfaceBand ps2 ex            -- the surfaced integer does not

-- | The pipeline surfaces ONCE, AFTER both rungs: 'pipelinePhases' has exactly 'numRungs'
-- latent steps, 'Surfaced' is terminal, and NO step before the last surfaces. Teeth: an
-- early-surfacing pipeline (a 'Surfaced' in @init@) fails the third conjunct. The rung
-- count is anchored to the self-similar pair via "SixFour.Spec.SelfSimilarReconstruct"
-- @levelsPerStep == 2@.
lawSurfaceComesAfterBothRungs :: Bool
lawSurfaceComesAfterBothRungs =
     length (filter isLatent pipelinePhases) == numRungs    -- both rungs are latent search
  && last pipelinePhases == Surfaced                        -- surfacing is the terminal step
  && all isLatent (init pipelinePhases)                     -- NO early surfacing before rung 2
  && levelsPerStep == 2                                     -- each rung is a 2-level octant step

-- | Once SURFACED (after rung 2), the committed 16³ + residual reconstructs EXACTLY: the
-- surfaced/held split of a real capture refines back bit-for-bit. Delegates
-- "SixFour.Spec.SuccessiveRefinement" @lawRefineRoundTrip@ — the deferred crossing loses
-- nothing the integer floor must keep. (Guarded to a valid @(k,d,capture)@.)
lawSurfacedOutputIsExact :: Int -> Int -> [Int] -> Bool
lawSurfacedOutputIsExact k d cap =
  not (d >= 0 && k >= 0 && k <= d && length cap == octreeLeafCount d)
    || refine d (split k d cap) == take (octreeLeafCount d) cap

-- | The SAME @θ_B@ drives the latent search across BOTH rungs before the single surface
-- commit. Delegates "SixFour.Spec.MaskedBandPrediction" @lawMaskedReusesOnBothRungs@: the
-- two-rung reuse is exactly what lets one search run span the pair @16³→64³@ and
-- @64³→256³@ and surface once at the end.
lawSearchReusesBothRungs :: Bool
lawSearchReusesBothRungs = lawMaskedReusesOnBothRungs

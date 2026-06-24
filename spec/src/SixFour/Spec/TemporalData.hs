-- COMPARTMENT: MLX-MODEL | tag:MacTag
{- |
Module      : SixFour.Spec.TemporalData
Description : The TEMPORAL data engine (spec side) — manufacture the @(frame t, value target, policy target)@ training records from a captured frame PAIR @(t, t+1)@, with the round-trip golden that closes the non-invertibility trap on the TIME axis. The temporal sibling of "SixFour.Spec.JepaData": that one makes the spatial masked-band corpus, this one makes the inter-frame delta corpus.

"SixFour.Spec.JepaData" closed the trap for the SPATIAL corpus (a non-invertible octant
generator would pass every masked-band law) with @lawDataEngineRoundTrips@. The TIME axis has the
SAME trap: nothing emits @(t, t+1)@ training pairs, and a lossy temporal generator — one whose
manufactured value\/policy targets do not actually reconstruct frame @t+1@ — would be golden-SILENT,
because "SixFour.Spec.HierarchicalDelta"'s carrier laws constrain each delta's ALGEBRA (group,
transport, gauge), NOT whether the manufactured PAIR is invertible.

This module closes that trap. A temporal record is manufactured from a frame pair by the
data-manufactured carriers ("SixFour.Spec.HierarchicalDelta" 'colourDeltaOf' \/ 'indexDeltaOf'):
frame @t@ is the context, the VALUE target is the recolour and the POLICY target is the motion.
The KEYSTONE 'lawTemporalEngineRoundTrips' proves @reconstructNext (manufacture ct ctNext) ==
ctNext@ — applying both manufactured deltas to frame @t@ recovers frame @t+1@ EXACTLY, so the two
targets are TRUE labels (frame @t+1@ is exactly recoverable), not lossy noise. A lossy temporal
generator FAILS it. The 'lawTemporalChannelsDisjoint' law proves the value channel touches only the
palette and the policy channel only the index — the orthogonality that lets the two heads train
INDEPENDENTLY — and 'lawTemporalBandingReconstructs' bridges to the multi-scale (coarse\/fine) head
via "SixFour.Spec.HierarchicalDelta" 'bandedDeltaTarget'.

GHC-boot-only. Reuses @ConstructionEncoder@ (the frame), @HierarchicalDelta@ (the carriers + the
octant pyramid), @OctreeCell@ (the ladder). Laws QuickCheck'd in "Properties.TemporalData".
-}
module SixFour.Spec.TemporalData
  ( -- * Manufacturing temporal records from a captured frame pair (the time-axis data engine)
    TemporalExample(..)
  , manufactureTemporalExample
  , applyPolicyDelta
  , reconstructNext
  , sameShape
    -- * The multi-scale (coarse/fine) bridge
  , bandedLuminanceDelta
    -- * Laws (QuickCheck'd in @Properties.TemporalData@)
  , lawTemporalEngineRoundTrips
  , lawTemporalChannelsDisjoint
  , lawTemporalBandingReconstructs
  ) where

import SixFour.Spec.ConstructionEncoder
  ( Construction(..), buildPixels, validConstruction )
import SixFour.Spec.HierarchicalDelta
  ( ColourDelta, IndexDelta
  , colourDeltaOf, indexDeltaOf, applyValueDelta, applyDelta, bandedDeltaTarget )
import SixFour.Spec.OctreeCell (Detail, octantSynthesize)
import SixFour.Spec.SameObjectInvariance (Cube(..))

-- | A TEMPORAL training record: frame @t@ as the context the predictor conditions on, plus the
-- two data-manufactured targets for frame @t+1@ — the VALUE recolour ('ColourDelta') and the
-- POLICY motion ('IndexDelta'). The inter-frame analogue of a "SixFour.Spec.MaskedBandPrediction"
-- @MaskedBandExample@ (context + held target), with the held target split into the two orthogonal
-- channels.
data TemporalExample = TemporalExample
  { teCurrent      :: !Construction   -- ^ frame @t@ — the context.
  , teValueTarget  :: !ColourDelta    -- ^ the data-manufactured VALUE target (recolour @t → t+1@).
  , tePolicyTarget :: !IndexDelta     -- ^ the data-manufactured POLICY target (motion @t → t+1@).
  } deriving (Eq, Show)

-- | MANUFACTURE a temporal record from a captured frame pair: frame @t@ is the context, and the
-- two targets are the carriers' data-manufactured deltas to frame @t+1@ (both @θ@-free pure
-- functions of the next captured frame).
manufactureTemporalExample :: Construction -> Construction -> TemporalExample
manufactureTemporalExample ct ctNext =
  TemporalExample ct (colourDeltaOf ct ctNext) (indexDeltaOf ct ctNext)

-- | Apply a POLICY (motion) delta to a frame: advance only the index map, holding the palette
-- fixed (the transport pushforward on the Morton index).
applyPolicyDelta :: IndexDelta -> Construction -> Construction
applyPolicyDelta d c = c { cIndex = applyDelta d (cIndex c) }

-- | RECONSTRUCT frame @t+1@ from a record: apply the VALUE delta (recolour the palette) then the
-- POLICY delta (move the index) to frame @t@. Exact because the two manufactured targets carry the
-- full change — the temporal analogue of "SixFour.Spec.JepaData" @reconstructCube@.
reconstructNext :: TemporalExample -> Construction
reconstructNext (TemporalExample ct v p) = applyPolicyDelta p (applyValueDelta v ct)

-- | Two frames have the SAME SHAPE when they share octant depth, palette size and index length —
-- the realistic case for frames of one clip. The round-trip is stated under this guard (a recolour
-- across two differently-sized palettes is a re-quantization, not a pure inter-frame delta).
sameShape :: Construction -> Construction -> Bool
sameShape a b =
     cDepth a == cDepth b
  && length (cPalette a) == length (cPalette b)
  && length (cIndex a)   == length (cIndex b)

-- | The MULTI-SCALE view of a record's recolour: the octant-banded delta (1 coarse + 7 detail per
-- level) of the @L@ channel of the built pixels, feeding the per-scale head via
-- "SixFour.Spec.HierarchicalDelta" 'bandedDeltaTarget'. The @a@\/@b@ channels follow identically.
-- This is how the @(t, t+1)@ engine connects to the coarse\/fine hierarchy.
bandedLuminanceDelta :: TemporalExample -> ([Int], [[Detail]])
bandedLuminanceDelta te =
  let ct            = teCurrent te
      Cube l0 _ _   = buildPixels ct
      Cube l1 _ _   = buildPixels (reconstructNext te)
  in bandedDeltaTarget (cDepth ct) l0 l1

-- ============================================================================
-- Laws (predicates; QuickCheck'd in Properties.TemporalData)
-- ============================================================================

-- | KEYSTONE — the temporal engine is INVERTIBLE: applying both manufactured deltas to frame @t@
-- recovers frame @t+1@ exactly, so the value\/policy targets are TRUE labels (frame @t+1@ is not
-- lost). This is the proof a lossy temporal generator CANNOT pass, closing the time-axis analogue
-- of the "a buggy generator passes every other law" trap. Teeth: a generator whose deltas dropped
-- the palette change or the motion fails the round-trip. (Stated under 'sameShape', the per-clip case.)
lawTemporalEngineRoundTrips :: Construction -> Construction -> Bool
lawTemporalEngineRoundTrips ct ctNext =
  not (sameShape ct ctNext)
    || reconstructNext (manufactureTemporalExample ct ctNext) == ctNext

-- | THE ORTHOGONALITY that lets the two heads train INDEPENDENTLY: the VALUE delta touches ONLY the
-- palette (the index is unchanged) and the POLICY delta touches ONLY the index (the palette is
-- unchanged). So a value-head gradient cannot perturb the policy target and vice versa — the
-- structural justification for two separate temporal heads. Teeth: a value delta that also moved the
-- index, or a policy delta that recoloured, fails.
lawTemporalChannelsDisjoint :: Construction -> Construction -> Bool
lawTemporalChannelsDisjoint ct ctNext =
  not (sameShape ct ctNext)
    || let te          = manufactureTemporalExample ct ctNext
           afterValue  = applyValueDelta  (teValueTarget te)  ct
           afterPolicy = applyPolicyDelta (tePolicyTarget te) ct
       in cIndex afterValue   == cIndex ct        -- VALUE leaves the index untouched
          && cPalette afterPolicy == cPalette ct  -- POLICY leaves the palette untouched

-- | THE MULTI-SCALE BRIDGE: the octant-banded luminance delta reconstructs the raw @L@ data delta
-- exactly (the octant ladder is a @θ@-free bijection), so the coarse\/fine supervision is lossless —
-- the per-scale head and the flat delta agree. Delegates "SixFour.Spec.HierarchicalDelta"
-- 'bandedDeltaTarget' over the octant ladder. Teeth: a lossy banding (a dropped detail band) fails.
lawTemporalBandingReconstructs :: Construction -> Construction -> Bool
lawTemporalBandingReconstructs ct ctNext =
  not (sameShape ct ctNext && validConstruction ct && validConstruction ctNext)
    || let te          = manufactureTemporalExample ct ctNext
           Cube l0 _ _ = buildPixels ct
           Cube l1 _ _ = buildPixels (reconstructNext te)
       in octantSynthesize (bandedLuminanceDelta te) == zipWith (-) l1 l0

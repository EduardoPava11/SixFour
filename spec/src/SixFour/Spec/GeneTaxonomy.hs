{- |
Module      : SixFour.Spec.GeneTaxonomy
Description : The V3.0 GENE REGISTRY — every learned parameter blob ("gene") categorised by lifecycle class (Germline\/Somatic\/Identity\/Meme), training site, and size; with the Shader-ML fold-in boundary (fits-in-threadgroup, weights+grads) as a LAW, real on both sides.

V3.0 trains on the phone, so the learned objects multiply: per-capture fine-tunes,
per-user preference weights, shareable looks, shipped base blobs. This module is the
one registry that CATEGORISES them — the classification the gene store, the trainer
dispatch, and the AirDrop surface all read from. The class names are biological
because the lifecycles genuinely differ along biology's axes:

  * 'Germline' — shipped base weights, immutable per release, trained OFFLINE on the
    Mac (MLX). Never mutated on a phone. (θ_B, the V3 field encoder.)
  * 'Somatic' — per-CAPTURE genes, trained on-device from the capture's OWN
    manufactured supervision ("SixFour.Spec.DeviceTrainStep"), living and dying with
    the capture bundle. (θ_up, θ_cell, the time rung.)
  * 'Identity' — per-USER genes, trained on-device from the decision stream,
    persistent, never shared by default. (The preference value head.)
  * 'Meme' — SHAREABLE genes: the AirDrop\/gene-library social layer
    (@SixFour/GeneLibrary/GeneStore.swift@, organ slots). (The σ-pair look genome,
    the metric organ.)

Every class keeps the one non-negotiable: __zero-gene == floor__. Deleting ANY gene
degrades the output to the deterministic byte-exact floor, never to garbage — that is
what makes the whole zoo safely mortal (a somatic gene can die with its capture, a
meme can be declined, germline can be rolled back). The per-gene floor proofs live in
the genes' own modules (e.g. "SixFour.Spec.DetailPredictor"
@lawZeroParamsIsFloorArithmetic@); this registry pins that each entry CLAIMS one.

== The cascade boundary, as a law

The V3.0 execution shape is a CASCADE: integer floor ops (Zig on CPU, or their
byte-exact Metal integer twins on GPU) alternating with learned float layers that hit
the A19 tensor units, with the Q16 commit ("SixFour.Spec.ByteCarrier" @reenterQ16@)
sealing every seam. A gene's training FOLDS INTO the rung dispatch (Shader-ML style,
no device-memory round trip) only when its working set — weights + gradients, fp32 —
fits the 32 KiB threadgroup budget ('foldsIntoRungDispatch'). The law
'lawFoldBoundaryIsRealOnBothSides' pins that boundary with genes on BOTH sides:
θ_up\/θ_cell fold; the time rung and the preference head do NOT (they run as separate
tensor-op\/MPSGraph dispatches). So "can we cascade Zig and Metal layers" is not a
mood — it is a size predicate with named members.

Honest scope: this is a CONTRACT REGISTRY. Its teeth are cross-module derivation
('lawSizesAreDerivedNotAsserted' imports the real param counts — a predictor reshape
breaks this module), class\/site coherence, and the fold boundary. It does not prove
any gene trains well (see the ContractOnly markers in the genes' own modules).
Additive; GHC-boot-only; emits no golden; laws @once@-tested in
@Properties.GeneTaxonomy@.
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none
module SixFour.Spec.GeneTaxonomy
  ( -- * The taxonomy
    GeneClass(..)
  , TrainSite(..)
  , GeneSpec(..)
    -- * The registry (the one list everything reads)
  , geneRegistry
  , geneBytesF32
    -- * The cascade fold-in boundary
  , threadgroupBudgetBytes
  , foldsIntoRungDispatch
    -- * Laws (once-tested in @Properties.GeneTaxonomy@)
  , lawSizesAreDerivedNotAsserted
  , lawClassDeterminesSite
  , lawGermlineNeverTrainsOnDevice
  , lawEveryGeneClaimsAFloor
  , lawFoldBoundaryIsRealOnBothSides
  , lawRegistryNamesUnique
  ) where

import Data.List (nub)

import SixFour.Spec.DetailPredictor      (defaultPredictorShape, paramCount)
import SixFour.Spec.MaskedBandPrediction (paramCountB)

-- | The gene lifecycle classes (see the module header for the biology).
data GeneClass = Germline | Somatic | Identity | Meme
  deriving (Eq, Show, Enum, Bounded)

-- | Where a gene's parameters are produced.
data TrainSite
  = MacOffline        -- ^ Mac MLX (Tier-1 tooling); ships as a blob.
  | DevicePerCapture  -- ^ on-device, from the capture's own manufactured pairs.
  | DevicePerUser     -- ^ on-device, from the user's decision stream.
  | NotTrained        -- ^ emitted\/curated, not gradient-descended (the look genome).
  deriving (Eq, Show, Enum, Bounded)

-- | One registry entry: a named learned parameter blob and its category.
data GeneSpec = GeneSpec
  { gsName        :: String     -- ^ the registry key (unique).
  , gsParams      :: Int        -- ^ parameter count (fp32 scalars).
  , gsClass       :: GeneClass  -- ^ lifecycle class.
  , gsSite        :: TrainSite  -- ^ where it trains.
  , gsZeroIsFloor :: Bool       -- ^ CLAIMS zero-gene == floor (proof in its own module).
  } deriving (Eq, Show)

-- | The σ-pair look-genome DOF: 3·128 generators (the CLAUDE.md pin; the V2 global
-- path is deferred but the genome FORM is the shareable look object either way).
sigmaPairDOF :: Int
sigmaPairDOF = 3 * 128

-- | THE REGISTRY. Sizes are DERIVED where a pinning module exists (θ_up from
-- "SixFour.Spec.DetailPredictor", θ_B from "SixFour.Spec.MaskedBandPrediction",
-- the preference head from its layer algebra over 'sigmaPairDOF') — see
-- 'lawSizesAreDerivedNotAsserted'.
geneRegistry :: [GeneSpec]
geneRegistry =
  [ -- The V3.0 on-device somatic pair (Spec.DeviceTrainStep trains these).
    GeneSpec "theta-up"      (paramCount defaultPredictorShape)  -- 7 bands × [1,ṽ,ṽ²] = 21
             Somatic DevicePerCapture True
  , GeneSpec "theta-cell"    (3 * 3)                             -- the 9 ChannelProduct pairs
             Somatic DevicePerCapture True
  , GeneSpec "time-rung"     (12 * 64 + 64 + 64 * 64 + 64 + 64 * 12 + 12)  -- 5,772 (d=64 MLP)
             Somatic DevicePerCapture True
    -- Shipped base weights.
  , GeneSpec "theta-b"       paramCountB                         -- 63 (masked-band, hand-written fwd)
             Germline MacOffline True
  , GeneSpec "field-encoder" 1000000                             -- BUDGET CEILING — undesigned (D1)
             Germline MacOffline True
    -- The per-user preference head (the AtlasTrainer value path; layer algebra:
    -- board 6→64 ‖ genome 384→64 → 128→32 → 32→1, biases included).
  , GeneSpec "value-pref"    (6 * 64 + 64 + sigmaPairDOF * 64 + 64
                              + 128 * 32 + 32 + 32 * 1 + 1)      -- 29,249
             Identity DevicePerUser True
    -- The shareable layer (GeneStore organ slots; .metric is the one live slot).
  , GeneSpec "sigma-look"    sigmaPairDOF                        -- 384 (zero-genome == floor)
             Meme NotTrained True
  , GeneSpec "metric-organ"  9                                   -- PSD Cholesky OKLab metric
             Meme MacOffline True
  ]

-- | A gene's fp32 weight bytes.
geneBytesF32 :: GeneSpec -> Int
geneBytesF32 g = 4 * gsParams g

-- | The Apple-GPU threadgroup memory budget (32 KiB) — the Shader-ML fold-in
-- ceiling: a training layer that lives INSIDE the rung dispatch must hold its
-- working set here, or it round-trips device memory and is a separate dispatch.
threadgroupBudgetBytes :: Int
threadgroupBudgetBytes = 32768

-- | Does this gene's TRAINING fold into the rung dispatch? Working set = weights +
-- gradients, fp32 (activations for these tiny heads are noise). Fold-in is what
-- makes the Zig-floor \/ tensor-layer cascade round-trip-free at a rung.
foldsIntoRungDispatch :: GeneSpec -> Bool
foldsIntoRungDispatch g = 2 * geneBytesF32 g <= threadgroupBudgetBytes

-- ============================================================================
-- Laws (once-tested in Properties.GeneTaxonomy)
-- ============================================================================

-- | Sizes are DERIVED, not asserted: the registry's θ_up count IS
-- "SixFour.Spec.DetailPredictor" 'paramCount' (21) and θ_B IS
-- "SixFour.Spec.MaskedBandPrediction" 'paramCountB' (63). Teeth: reshaping either
-- predictor breaks this module until the registry is re-categorised.
lawSizesAreDerivedNotAsserted :: Bool
lawSizesAreDerivedNotAsserted =
     lookupParams "theta-up" == Just (paramCount defaultPredictorShape)
  && lookupParams "theta-up" == Just 21
  && lookupParams "theta-b"  == Just paramCountB
  && lookupParams "theta-b"  == Just 63
  && lookupParams "value-pref" == Just 29249   -- the layer algebra, pinned
  where lookupParams n = gsParams <$> lookup n [ (gsName g, g) | g <- geneRegistry ]

-- | Class determines site (the coherence that makes the class names honest):
-- Somatic ⇒ per-capture, Identity ⇒ per-user, Germline\/Meme ⇒ never
-- device-trained-per-capture.
lawClassDeterminesSite :: Bool
lawClassDeterminesSite = all ok geneRegistry
  where
    ok g = case gsClass g of
      Somatic  -> gsSite g == DevicePerCapture
      Identity -> gsSite g == DevicePerUser
      Germline -> gsSite g `elem` [MacOffline, NotTrained]
      Meme     -> gsSite g `elem` [MacOffline, NotTrained]

-- | Germline never trains on a phone — the base is immutable per release
-- (rollback-able), which is what makes on-device mutation safe everywhere else.
lawGermlineNeverTrainsOnDevice :: Bool
lawGermlineNeverTrainsOnDevice =
  all (\g -> gsClass g /= Germline
             || gsSite g `notElem` [DevicePerCapture, DevicePerUser])
      geneRegistry

-- | Every registered gene CLAIMS zero-gene == floor. (The claim's proof lives in
-- the gene's own module; an entry registered without a floor story is a design
-- error this law rejects at the registry.)
lawEveryGeneClaimsAFloor :: Bool
lawEveryGeneClaimsAFloor = all gsZeroIsFloor geneRegistry

-- | THE CASCADE BOUNDARY IS REAL ON BOTH SIDES: θ_up and θ_cell FOLD into the rung
-- dispatch (weights+grads ≪ 32 KiB — trainable inside the capture dispatch chain,
-- no memory round trip), while the time rung and the preference head do NOT (they
-- are separate tensor-op\/MPSGraph dispatches). Teeth: if the budget rule were
-- vacuous (everything folds, or nothing does) this fails.
lawFoldBoundaryIsRealOnBothSides :: Bool
lawFoldBoundaryIsRealOnBothSides =
     folds "theta-up" && folds "theta-cell"
  && not (folds "time-rung") && not (folds "value-pref")
  where
    folds n = any (\g -> gsName g == n && foldsIntoRungDispatch g) geneRegistry

-- | Registry keys are unique (the gene store indexes by name).
lawRegistryNamesUnique :: Bool
lawRegistryNamesUnique =
  let names = map gsName geneRegistry
  in length names == length (nub names)

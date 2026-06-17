{- |
Module      : SixFour.Spec.ExportFamily
Description : One chosen genome → three R-views {16³, 64³, 256³}, each carrying the SAME
              S4GN genome block. Composes RGBTLift + CubeLadder.

The "Export Family" action: one genome → one global palette → three rungs of the
reversible R operator. genome ⊥ R for the 16³/64³ rungs (palette factor only — preserves
preview≡ship and the lossless ladder); the genome touches R ONLY via 'NetSynth256'
above-capture detail at 256³.

This module also declares the two sub-spec sections referenced by the plan as inline
groups: TemporalPool (time-axis S-transform) and NetSynth256 (genome → synth detail,
degrading to the 'synthBeyond' floor).

== Rung decisions

16³ is 64 frames at 16² spatial (temporally LOSSLESS) — so the down-up bijection is FULL.
64³ is the R-identity reference, byte-exact. 256³ floor is nearest-neighbour replicate
('synthBeyond'); NetSynth256 detail is a SEPARATE gated enhancement, proven
bit-exact-equal to the floor at zero genome.

GHC-boot-only.
-}
module SixFour.Spec.ExportFamily
  ( -- * Tiers
    RungTier(..)
    -- * Family I/O
  , FamilyInput(..)
  , RungProduct(..)
  , ExportFamily(..)
  , exportFamily
    -- * TemporalPool (time-axis S-transform)
  , temporalDistill
  , temporalSynthesize
    -- * NetSynth256 (genome → above-capture detail)
  , genomeToSynthSeed
  , synthDetail
  , synthBeyond256
    -- * Laws (QuickCheck'd in Properties.ExportFamily)
  , lawFamilyOneGenome
  , lawLadderConsistencyDownUp
  , lawTier64IsReference
  , lawTier256FloorIsNearestNeighbour
  , lawZeroGenomeIsFloor
  , lawTemporalReversibleOnCarriedDetail
  , lawFamilyDeterministic
  , lawFamilyGamutClosed
  ) where

import SixFour.Spec.CubeLadder     (distill, synthesize, synthBeyond)
import SixFour.Spec.RGBTLift       (liftQuad, unliftQuad)
import SixFour.Spec.PairTreeFixed  (OKLabI)

-- | The three rungs.
data RungTier = Tier16 | Tier64 | Tier256
  deriving (Eq, Show, Enum, Bounded)

-- | Everything the family export needs: the chosen 384-DOF genome, the index cube, and
-- the reconstructed global table.
data FamilyInput = FamilyInput
  { fiGenome384  :: [Int]      -- ^ chosen σ-pair genome, Q16, flattenHaar order.
  , fiIndexCube  :: [Int]      -- ^ the (x,y,t) index cube.
  , fiGlobalTable :: [OKLabI]  -- ^ the reconstructed 256-leaf global palette.
  } deriving (Eq, Show)

-- | One produced rung.
data RungProduct = RungProduct
  { rungSide    :: Int          -- ^ spatial side (16/64/256).
  , rungFrames  :: Int          -- ^ frame count (64 across the carried ladder).
  , rungCube    :: [Int]        -- ^ index cube for this rung.
  , rungPalette :: [OKLabI]     -- ^ palette (bit-identical across rungs).
  } deriving (Eq, Show)

-- | The three-rung product, all carrying the same S4GN block.
data ExportFamily = ExportFamily
  { fam16  :: RungProduct
  , fam64  :: RungProduct
  , fam256 :: RungProduct
  } deriving (Eq, Show)

-- | The G6 orchestrator: one genome → {16³, 64³, 256³}.
exportFamily :: FamilyInput -> ExportFamily
exportFamily = error "TODO"

-- | Time-axis S-transform distill (64-frame object → carried coarse + detail).
temporalDistill :: [Int] -> ([Int], [Int])
temporalDistill = error "TODO"

-- | Inverse of 'temporalDistill' (exact on the carried detail).
temporalSynthesize :: ([Int], [Int]) -> [Int]
temporalSynthesize = error "TODO"

-- | The genome → 256³ synthesis seed.
genomeToSynthSeed :: [Int] -> [Int]
genomeToSynthSeed = error "TODO"

-- | Above-capture detail; degrades to 'synthBeyond256' floor at zero genome.
synthDetail :: [Int] -> [Int] -> [Int]
synthDetail = error "TODO"

-- | The canonical 256³ nearest-neighbour floor.
synthBeyond256 :: [Int] -> [Int]
synthBeyond256 = error "TODO"

-- ---------------------------------------------------------------------------
-- Laws
-- ---------------------------------------------------------------------------

-- | All three rungs reconstruct bit-identical palette from the one genome.
lawFamilyOneGenome :: FamilyInput -> Bool
lawFamilyOneGenome = error "TODO"

-- | @distill . synthesize = id@ on the SPATIAL floor (EXACT, reversible integer
-- wavelet). 16³ = 64 frames at 16² spatial ⇒ the bijection is FULL.
lawLadderConsistencyDownUp :: FamilyInput -> Bool
lawLadderConsistencyDownUp = error "TODO"

-- | fam64 = R-identity, byte-exact.
lawTier64IsReference :: FamilyInput -> Bool
lawTier64IsReference = error "TODO"

-- | With NN detail zeroed, 256³ == synthBeyond == nearest-neighbour replicate.
lawTier256FloorIsNearestNeighbour :: FamilyInput -> Bool
lawTier256FloorIsNearestNeighbour = error "TODO"

-- | synthDetail of zero genome == synthBeyond floor — golden-pinned bit-exact equality.
lawZeroGenomeIsFloor :: [Int] -> Bool
lawZeroGenomeIsFloor = error "TODO"

-- | Temporal down-up EXACT on the carried 64-frame object (non-vacuous: shipped 16³
-- keeps 64 frames).
lawTemporalReversibleOnCarriedDetail :: [Int] -> Bool
lawTemporalReversibleOnCarriedDetail = error "TODO"

-- | 'exportFamily' is pure ⇒ identical product cross-device.
lawFamilyDeterministic :: FamilyInput -> Bool
lawFamilyDeterministic = error "TODO"

-- | Every rung's palette is gamut-closed.
lawFamilyGamutClosed :: FamilyInput -> Bool
lawFamilyGamutClosed = error "TODO"

{- |
Module      : SixFour.Spec.GenomeBlend
Description : Receiver-side federated transport — an extracted foreign genome enters as
              ONE gated Bradley–Terry Compare, NEVER a θ splice.

When a SixFour GIF is received, its carried genome ('SixFour.Spec.GenomeCarrier' decodes
the @S4GN@ block) can be ADOPTED into the receiver's own taste. The single rule that keeps
the system sound: a foreign look is adopted as exactly ONE ordered Bradley–Terry Compare —
the foreign look as winner, the receiver's current look as loser — folded by the same
'SixFour.Spec.PersonalGenome.applyPick' as any local pick, and then GATED. It is NEVER a
convex splice of foreign θ into local θ: a splice would make θ unreproducible from
@coldStartGenome@ + the local ordered log and break
'SixFour.Spec.PersonalGenome.lawReplayDeterministic'. (Amendment decision Q5.)

== Why this module does not touch 'SixFour.Spec.GenomeCarrier'

Adoption logic is independent of HOW the genome was pulled out of the GIF bytes. This
module takes an already-decoded 'Extracted' value (Present\/Absent\/Corrupt), so it stays
off the carrier's byte cone and is testable in isolation. The carrier produces the
'Extracted'; this module decides what to do with it.

== The three extraction outcomes and the gate (the UX surface)

  * 'Absent'  — the GIF has no @S4GN@ block (a normal GIF, or one re-saved by a tool that
    dropped the block): @NoGenomePresent@, the receiver's genome is unchanged.
  * 'Corrupt' — the block is present but fails its CRC\/version check: @CorruptPayload@,
    unchanged. (Distinguishing Absent from Corrupt is the honest "your look didn't survive
    transcoding" signal the UX needs.)
  * 'Present' — a valid foreign genome. With zero trust (the user did not ask to pull it)
    or if adopting it would REGRESS the receiver's recent picks, the foreign Compare fails
    'SixFour.Spec.PersonalGenome.gatePasses' and the genome is unchanged
    (@ResistedByGate@); otherwise the Compare is folded in (@Adopted@).

The gate is what gives "receiver-confidence-weighted trust": a receiver with strong,
consistent recent picks ('SixFour.Spec.PersonalGenome' has many local Compares that a
foreign look would contradict) resists adoption, because the post-Compare candidate fails
the majority replay test ('lawHighLocalConfidenceResistsBlend'). Confidence lives in the
log + gate, not in a special learning rate — so replay determinism is preserved.

GHC-boot-only. Laws are exported predicates, to be QuickCheck'd in @Properties.GenomeBlend@
(test wiring pending — this module lands at build step 7).
-}
-- COMPARTMENT: SWIFT-COREAI | tag:CommitSide
module SixFour.Spec.GenomeBlend
  ( -- * The foreign payload and extraction outcome
    ForeignGenome(..)
  , Extracted(..)
    -- * The adoption result
  , BlendOutcome(..)
  , BlendResult(..)
    -- * Adoption
  , realizeForeignLook
  , adoptForeign
    -- * Laws (to be QuickCheck'd in Properties.GenomeBlend)
  , lawBlendIsACompare
  , lawZeroTrustIsIdentity
  , lawNoForeignIsIdentity
  , lawResistedKeepsCurrent
  , lawHighLocalConfidenceResistsBlend
  , lawBlendStaysSigmaSymmetric
  ) where

import SixFour.Spec.Preference     (Embedding)
import SixFour.Spec.PairTreeFixed  (OKLabI, HaarPaletteI)
import SixFour.Spec.LeafOverride   (SigmaOverride, applySigmaOverride, lawSigmaOverridePreservesSymmetry)
import SixFour.Spec.PersonalGenome (PersonalGenome(..), Pick, applyPick, gatePasses)

-- ---------------------------------------------------------------------------
-- The foreign payload and extraction outcome
-- ---------------------------------------------------------------------------

-- | A decoded foreign genome carried in a received GIF. It bundles the 384-DOF look
-- (the carried palette-space override), its 770-D taste embedding (computed by the
-- producer so this module stays off the Atlas embedding cone), and the receiver's trust
-- in the source (0 = do not pull; > 0 = the user asked to adopt this look).
data ForeignGenome = ForeignGenome
  { fgOverride  :: SigmaOverride   -- ^ the carried 384-DOF look (palette-space σ-override)
  , fgEmbedding :: Embedding       -- ^ its 770-D taste embedding (the Compare winner)
  , fgTrust     :: Double          -- ^ receiver's adopt switch\/confidence in the source
  } deriving (Eq, Show)

-- | The result of trying to pull a genome out of a received GIF.
data Extracted
  = Present ForeignGenome   -- ^ a valid foreign genome was decoded
  | Absent                  -- ^ no @S4GN@ block (normal GIF, or block dropped on re-save)
  | Corrupt                 -- ^ a block was present but failed its CRC\/version check
  deriving (Eq, Show)

-- ---------------------------------------------------------------------------
-- The adoption result
-- ---------------------------------------------------------------------------

-- | What happened when adopting an 'Extracted' genome.
data BlendOutcome
  = Adopted          -- ^ the foreign Compare was folded in
  | ResistedByGate   -- ^ present but zero-trust or gate-rejected ⇒ genome unchanged
  | NoGenomePresent  -- ^ 'Absent' ⇒ unchanged
  | CorruptPayload   -- ^ 'Corrupt' ⇒ unchanged
  deriving (Eq, Show)

-- | The (possibly unchanged) genome plus the outcome, so the UX can show the honest
-- distinction between "no genome", "corrupt", "resisted", and "adopted".
data BlendResult = BlendResult
  { brGenome  :: PersonalGenome
  , brOutcome :: BlendOutcome
  } deriving (Eq, Show)

-- ---------------------------------------------------------------------------
-- Adoption
-- ---------------------------------------------------------------------------

-- | Realize the foreign look as an actual palette over a base genome tree — the carried
-- σ-override applied to @base@. σ-symmetry is preserved for free
-- ('lawBlendStaysSigmaSymmetric'), so a foreign look can never produce an invalid palette.
realizeForeignLook :: ForeignGenome -> HaarPaletteI -> [OKLabI]
realizeForeignLook fg = applySigmaOverride (fgOverride fg)

-- | Adopt an extracted genome into the receiver's 'PersonalGenome', given the receiver's
-- recent pick log and current look embedding. The ONLY way θ moves is one gated
-- 'applyPick' Compare (foreign look beats current look). Anything else — absent, corrupt,
-- zero trust, or a gate rejection — leaves the genome byte-identical.
adoptForeign :: PersonalGenome -> [Pick] -> Embedding -> Extracted -> BlendResult
adoptForeign current _       _     Absent      = BlendResult current NoGenomePresent
adoptForeign current _       _     Corrupt     = BlendResult current CorruptPayload
adoptForeign current recent local (Present fg)
  | fgTrust fg <= 0             = BlendResult current ResistedByGate
  | gatePasses candidate recent = BlendResult candidate Adopted
  | otherwise                   = BlendResult current   ResistedByGate
  where candidate = applyPick current (fgEmbedding fg, local)

-- ---------------------------------------------------------------------------
-- Laws (predicates; to be exercised by Properties.GenomeBlend)
-- ---------------------------------------------------------------------------

-- | Adoption is exactly ONE Compare, never a splice: when the outcome is 'Adopted', the
-- resulting genome equals @applyPick current (foreignEmbedding, localLook)@ — a single
-- ordered Bradley–Terry step, so θ stays a pure memoised fold over the local log.
lawBlendIsACompare :: PersonalGenome -> [Pick] -> Embedding -> ForeignGenome -> Bool
lawBlendIsACompare current recent local fg =
  let r = adoptForeign current recent local (Present fg)
  in brOutcome r /= Adopted || brGenome r == applyPick current (fgEmbedding fg, local)

-- | Zero trust is the exact identity: a present-but-untrusted genome leaves θ unchanged.
lawZeroTrustIsIdentity :: PersonalGenome -> [Pick] -> Embedding -> ForeignGenome -> Bool
lawZeroTrustIsIdentity current recent local fg =
  fgTrust fg > 0 ||
  brGenome (adoptForeign current recent local (Present fg)) == current

-- | No usable genome is the exact identity: 'Absent' and 'Corrupt' never change θ.
lawNoForeignIsIdentity :: PersonalGenome -> [Pick] -> Embedding -> Bool
lawNoForeignIsIdentity current recent local =
  brGenome (adoptForeign current recent local Absent)  == current
  && brGenome (adoptForeign current recent local Corrupt) == current

-- | Whenever the outcome is NOT 'Adopted', the genome is returned unchanged — the safety
-- invariant: θ can only ever move via an accepted Compare.
lawResistedKeepsCurrent :: PersonalGenome -> [Pick] -> Embedding -> Extracted -> Bool
lawResistedKeepsCurrent current recent local ext =
  let r = adoptForeign current recent local ext
  in brOutcome r == Adopted || brGenome r == current

-- | A receiver whose recent picks would be REGRESSED by the foreign look resists it: if the
-- post-Compare candidate fails the majority replay gate, the foreign genome is not adopted.
-- This is "high local confidence resists blend", expressed through the gate.
lawHighLocalConfidenceResistsBlend :: PersonalGenome -> [Pick] -> Embedding -> ForeignGenome -> Bool
lawHighLocalConfidenceResistsBlend current recent local fg =
  let candidate = applyPick current (fgEmbedding fg, local)
  in gatePasses candidate recent ||
     brOutcome (adoptForeign current recent local (Present fg)) /= Adopted

-- | A foreign look, realized as a palette over any well-formed base, stays σ-fixed — the
-- federated transport can never inject an asymmetric (invalid) palette. Reuses
-- 'SixFour.Spec.LeafOverride.lawSigmaOverridePreservesSymmetry'.
lawBlendStaysSigmaSymmetric :: ForeignGenome -> HaarPaletteI -> Bool
lawBlendStaysSigmaSymmetric fg base = lawSigmaOverridePreservesSymmetry (fgOverride fg) base

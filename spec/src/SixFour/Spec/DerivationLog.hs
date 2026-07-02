{- |
Module      : SixFour.Spec.DerivationLog
Description : Genealogy as a FOLD over an append-only derivation log — the same shape "SixFour.Spec.Trade" gives the holdings\/reputation scalars, now for lineage. Each event is a self-contained, content-addressed derivation (payload + absolute parent ids + who\/when); folding the log dedups by content-address into a "SixFour.Spec.Lineage".'Genealogy'. Because a gene's id is 'SixFour.Spec.GeneHash.geneHash' of @(payload, parents)@, the fold is a Merkle-CRDT in miniature: it is ORDER-INDEPENDENT ('lawGenealogyReverseInvariant' + the permutation test), IDEMPOTENT ('lawGenealogyIdempotent') and MONOTONE ('lawGenealogyMonotone') — so two devices that create derived genes concurrently converge to the SAME genealogy with no coordination, exactly as the trade ledger's holdings do.

Where "SixFour.Spec.GeneHash".'SixFour.Spec.GeneHash.MintOp' references parents by BUILD-ORDER
INDEX (a construction transcript), a 'DerivationEvent' names its parents by ABSOLUTE content-address,
so the log is position-independent: it can be gossiped, reordered, deduplicated and merged, and every
replica folds it to the same DAG. This is the append-only-log realisation of the design brief's "make
provenance a fold of an append-only log, same style as governance" — the genealogy sibling of
"SixFour.Spec.Trade".

  * 'DerivationEvent' \/ 'DerivationLog' — the event (payload, parents, creator, epoch) and the log.
    'eventId' is DERIVED (@geneHash (payload, parents)@), so an event is self-verifying
    ('lawEventIdSelfVerifying'); 'eventTag' is the "SixFour.Spec.Lineage".'GeneTag' it contributes.
  * 'genealogyOf' — the fold: group by content-address, pick the canonical (earliest-by-@(epoch,
    creator)@) tag per id, emit in address order. A deterministic reduction ⇒ order-independent.
  * 'logFromOps' — the bridge to "SixFour.Spec.GeneHash": replay 'SixFour.Spec.GeneHash.MintOp's into
    a causally-complete log. Folding it back reconstructs an ACYCLIC genealogy
    ('lawReconstructedGenealogyAcyclic') carrying exactly the ids direct construction would
    ('lawLogFaithful').

GHC-boot-only (@base@, @containers@). Laws QuickCheck'd in @Properties.DerivationLog@.
-}
-- COMPARTMENT: SWIFT-APP-SOCIAL | tag:DisplaySide
module SixFour.Spec.DerivationLog
  ( -- * The append-only derivation log
    DerivationEvent(..)
  , DerivationLog
  , eventId
  , eventTag
    -- * The fold (order-independent ⇒ convergent)
  , genealogyOf
    -- * The bridge to "SixFour.Spec.GeneHash"
  , logFromOps
    -- * Laws (QuickCheck'd in @Properties.DerivationLog@)
  , lawEventIdSelfVerifying
  , lawEventTagCommitsToParents
  , lawGenealogyIdempotent
  , lawGenealogyReverseInvariant
  , lawGenealogyMonotone
  , lawReconstructedGenealogyAcyclic
  , lawLogFaithful
  ) where

import           Data.List (foldl', minimumBy)
import qualified Data.Map.Strict as Map
import           Data.Ord (comparing)
import qualified Data.Set as Set

import           SixFour.Spec.GeneHash
                   ( GenePreimage(..), MintOp(..), buildFrom, geneHash )
import           SixFour.Spec.Lineage
                   ( GeneTag(..), Genealogy, geneIds, lawAcyclicNoSelfAncestor )
import           SixFour.Spec.Trade (CreatorId, Epoch, GeneId(..))

-- ─────────────────────────────────────────────────────────────────────────────
-- The append-only derivation log.
-- ─────────────────────────────────────────────────────────────────────────────

-- | A self-contained, content-addressed derivation event: the canonical payload, the ABSOLUTE parent
-- content-addresses it derives from (@[]@ = an origin), and the provenance metadata (creator, epoch).
-- Everything needed to verify the gene's own address travels in the event, so the log is
-- position-independent — it can be reordered or merged and still fold to the same genealogy.
data DerivationEvent = DerivationEvent
  { dePayload :: [Int]      -- ^ the canonical Q16 weight bytes
  , deParents :: [GeneId]   -- ^ ancestry, as absolute content-addresses (@[]@ = origin)
  , deCreator :: CreatorId  -- ^ who minted it (provenance metadata, not in the address)
  , deEpoch   :: Epoch      -- ^ first-seen logical time (provenance metadata, not in the address)
  } deriving (Eq, Show)

-- | The append-only log of derivation events. Genealogy is a pure fold of this ('genealogyOf') — the
-- lineage analogue of "SixFour.Spec.Trade".'SixFour.Spec.Trade.Ledger'.
type DerivationLog = [DerivationEvent]

-- | The content-address of the gene an event mints — DERIVED from its content, never stored, so an
-- event cannot lie about its own id ('lawEventIdSelfVerifying').
eventId :: DerivationEvent -> GeneId
eventId e = geneHash (GenePreimage (dePayload e) (deParents e))

-- | The "SixFour.Spec.Lineage".'GeneTag' an event contributes to the genealogy DAG.
eventTag :: DerivationEvent -> GeneTag
eventTag e = GeneTag (eventId e) (deCreator e) (deParents e) (deEpoch e)

-- ─────────────────────────────────────────────────────────────────────────────
-- The fold — order-independent, hence convergent.
-- ─────────────────────────────────────────────────────────────────────────────

-- | Fold a log into a genealogy: group events by content-address, keep the CANONICAL tag per id (the
-- earliest by @(epoch, creator)@ — first mint wins, deterministically), and emit in address order.
-- Because the result is a deterministic reduction of the event SET, it is independent of the log's
-- order and of duplicates — the Strong-Eventual-Consistency property ("same events ⇒ same
-- genealogy") the swap economy needs.
genealogyOf :: DerivationLog -> Genealogy
genealogyOf theLog =
  [ eventTag (minimumBy (comparing canonicalKey) es) | (_gid, es) <- Map.toList grouped ]
  where
    grouped = Map.fromListWith (++) [ (eventId e, [e]) | e <- theLog ]
    canonicalKey e = (deEpoch e, deCreator e)

-- ─────────────────────────────────────────────────────────────────────────────
-- The bridge to "SixFour.Spec.GeneHash" — replay MintOps into a causally-complete log.
-- ─────────────────────────────────────────────────────────────────────────────

-- | Replay a construction transcript ('SixFour.Spec.GeneHash.MintOp's, whose parents are build-order
-- indices) into a causally-complete 'DerivationLog', whose parents are absolute addresses. Each
-- successful mint emits one event; re-mints of identical content+parents dedup. Folding the result
-- back reconstructs an acyclic genealogy ('lawReconstructedGenealogyAcyclic') with exactly the ids
-- direct construction gives ('lawLogFaithful').
logFromOps :: [MintOp] -> DerivationLog
logFromOps = reverse . snd . foldl' step ([], [])
  where
    step (built, evs) (MintOp cr pay pidx ep) =
      let parents = [ built !! i | i <- pidx, i >= 0, i < length built ]
          e       = DerivationEvent pay parents cr ep
          gid     = eventId e
      in if gid `elem` built
           then (built, evs)                 -- dedup: identical content+parents already minted
           else (built ++ [gid], e : evs)    -- record the id (in order) and prepend the event

-- ─────────────────────────────────────────────────────────────────────────────
-- Laws (QuickCheck'd in @Properties.DerivationLog@).
-- ─────────────────────────────────────────────────────────────────────────────

-- | An event's id is exactly @geneHash (payload, parents)@ — it cannot claim an address that
-- disagrees with its content and ancestry (self-verifying, ties to "SixFour.Spec.GeneHash").
lawEventIdSelfVerifying :: DerivationEvent -> Bool
lawEventIdSelfVerifying e =
  eventId e == geneHash (GenePreimage (dePayload e) (deParents e))

-- | The tag an event contributes commits to its OWN recorded parents: @gtGene == geneHash (payload,
-- gtParents)@. Makes "SixFour.Spec.Lineage"'s content-addressing literally true of the folded DAG.
lawEventTagCommitsToParents :: DerivationEvent -> Bool
lawEventTagCommitsToParents e =
  let t = eventTag e in gtGene t == geneHash (GenePreimage (dePayload e) (gtParents t))

-- | IDEMPOTENT (G-Set): folding a log that repeats every event yields the same genealogy as folding
-- it once — duplicate delivery over a gossip layer is harmless.
lawGenealogyIdempotent :: DerivationLog -> Bool
lawGenealogyIdempotent theLog = genealogyOf (theLog ++ theLog) == genealogyOf theLog

-- | ORDER-INDEPENDENT: reversing the log does not change the folded genealogy. (A concrete
-- reordering; @Properties.DerivationLog@ additionally checks invariance under a random permutation —
-- the full Strong-Eventual-Consistency statement.)
lawGenealogyReverseInvariant :: DerivationLog -> Bool
lawGenealogyReverseInvariant theLog = genealogyOf (reverse theLog) == genealogyOf theLog

-- | MONOTONE: appending events never removes a gene from the genealogy — the gene set only grows,
-- matching "SixFour.Spec.Trade"'s monotone holdings. (Genealogy convergence is grow-only, like a
-- Merkle-CRDT's append-only history.)
lawGenealogyMonotone :: DerivationLog -> DerivationLog -> Bool
lawGenealogyMonotone theLog extra =
  Set.fromList (geneIds (genealogyOf theLog))
    `Set.isSubsetOf` Set.fromList (geneIds (genealogyOf (theLog ++ extra)))

-- | THE THEOREM: a genealogy folded from a causally-complete log (built by 'logFromOps') is acyclic.
-- Reordering does not endanger this — content-addressing means a parent edge can only name an id that
-- already existed, so no cycle survives the fold regardless of delivery order.
lawReconstructedGenealogyAcyclic :: [MintOp] -> Bool
lawReconstructedGenealogyAcyclic = lawAcyclicNoSelfAncestor . genealogyOf . logFromOps

-- | The append-only log FAITHFULLY carries the DAG: folding @logFromOps ops@ yields exactly the gene
-- ids that direct construction ("SixFour.Spec.GeneHash".'SixFour.Spec.GeneHash.buildFrom') would, so
-- nothing is lost in moving from a construction transcript to a position-independent, gossip-able log.
lawLogFaithful :: [MintOp] -> Bool
lawLogFaithful ops =
  Set.fromList (geneIds (genealogyOf (logFromOps ops)))
    == Set.fromList (geneIds (buildFrom ops))

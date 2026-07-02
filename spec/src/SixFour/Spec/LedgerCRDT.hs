{- |
Module      : SixFour.Spec.LedgerCRDT
Description : The trade ledger is a CvRDT — proven. "SixFour.Spec.Trade"'s HYBRID-GRANT, holdings-only-grow design is (perhaps accidentally) a state-based Conflict-free Replicated Data Type: the observable social state is the SET of @(creator, gene)@ grants, its merge is set UNION — a join-semilattice that is commutative, associative and idempotent — and folding the ledger into it is a monotone homomorphism. By the Shapiro et al. (2011) characterisation, a monotone join-semilattice earns STRONG EVENTUAL CONSISTENCY: two devices that have seen the same set of trades hold identical state, regardless of gossip order or duplicate delivery. So the convergence the swap economy needs is not something to engineer — the ledger already had it.

This is the CONVERGENCE fold, orthogonal to the state-machine in "SixFour.Spec.Trade" (which is the
substrate) and a sibling of "SixFour.Spec.DerivationLog" (the genealogy fold, likewise a Merkle-CRDT).
Together they say the whole social layer — holdings, genealogy — converges under gossip with no
coordinator, provably.

  * 'Grants' — the CvRDT state: the set of @(creator, gene)@ access grants. 'stateOf' folds a
    "SixFour.Spec.Trade".'SixFour.Spec.Trade.Ledger' into it; 'mergeGrants' is the join (union);
    'emptyGrants' is bottom.
  * The join-semilattice laws ('lawMergeCommutative' \/ 'lawMergeAssociative' \/ 'lawMergeIdempotent'
    \/ 'lawBottomIdentity') and the fold homomorphism ('lawStateHomomorphism',
    'lawStateEmptyIsBottom') are the CvRDT contract; 'lawStateMonotone' + 'lawLedgerIdempotent' are the
    grow-only property.
  * 'lawStrongEventualConsistency' is the capstone (same trade-set ⇒ same state); 'lawHoldingsFromState'
    proves the shipped "SixFour.Spec.Trade".'SixFour.Spec.Trade.holdings' fold is exactly a slice of
    this CvRDT state, so nothing new is invented — the guarantee is on the existing design.

SCOPE: this models the GRANT\/holdings convergence (a grow-only set). The per-trade
@Proposed→Accepted@ settlement is a separate last-writer-wins concern (a trade settles once); merging
divergent trade STATES is future work and does not affect the grant-set result here. GHC-boot-only
(@containers@). Laws QuickCheck'd in @Properties.LedgerCRDT@.
-}
-- COMPARTMENT: SWIFT-APP-SOCIAL | tag:DisplaySide
module SixFour.Spec.LedgerCRDT
  ( -- * The CvRDT state
    Grants
  , stateOf
  , mergeGrants
  , emptyGrants
    -- * The join-semilattice contract (Shapiro et al. 2011)
  , lawMergeCommutative
  , lawMergeAssociative
  , lawMergeIdempotent
  , lawBottomIdentity
    -- * The fold is a monotone homomorphism
  , lawStateHomomorphism
  , lawStateEmptyIsBottom
  , lawStateMonotone
  , lawLedgerIdempotent
    -- * Strong Eventual Consistency + the bridge to the shipped fold
  , lawStrongEventualConsistency
  , lawHoldingsFromState
  ) where

import           Data.Set (Set)
import qualified Data.Set as Set

import           SixFour.Spec.Trade
                   ( CreatorId, GeneId, Ledger, grants, holdings )

-- ─────────────────────────────────────────────────────────────────────────────
-- The CvRDT state — a grow-only set of access grants.
-- ─────────────────────────────────────────────────────────────────────────────

-- | The convergent state of the swap economy: the set of @(creator, gene)@ access grants. This is
-- the least structure that "SixFour.Spec.Trade".'SixFour.Spec.Trade.holdings' is a view of, and it is
-- a Grow-only Set (G-Set) — the canonical state-based CRDT.
type Grants = Set (CreatorId, GeneId)

-- | Fold a ledger into its grant set: the union of every settled trade's grants (a non-'Accepted'
-- trade grants nothing, per "SixFour.Spec.Trade".'SixFour.Spec.Trade.grants').
stateOf :: Ledger -> Grants
stateOf = Set.fromList . concatMap grants

-- | The JOIN of the semilattice: merging two replica states is set union (the least upper bound). A
-- merge can be lost, duplicated or reordered without harm — that is what makes convergence a theorem.
mergeGrants :: Grants -> Grants -> Grants
mergeGrants = Set.union

-- | Bottom: the initial state before any trade (@stateOf [] == emptyGrants@).
emptyGrants :: Grants
emptyGrants = Set.empty

-- ─────────────────────────────────────────────────────────────────────────────
-- The join-semilattice contract (a CvRDT merge must be commutative, associative, idempotent).
-- ─────────────────────────────────────────────────────────────────────────────

-- | The join is COMMUTATIVE — merge order does not matter.
lawMergeCommutative :: Grants -> Grants -> Bool
lawMergeCommutative a b = mergeGrants a b == mergeGrants b a

-- | The join is ASSOCIATIVE — grouping of merges does not matter.
lawMergeAssociative :: Grants -> Grants -> Grants -> Bool
lawMergeAssociative a b c =
  mergeGrants (mergeGrants a b) c == mergeGrants a (mergeGrants b c)

-- | The join is IDEMPOTENT — re-merging a state with itself is a no-op (a replica can absorb the same
-- update any number of times).
lawMergeIdempotent :: Grants -> Bool
lawMergeIdempotent a = mergeGrants a a == a

-- | Bottom is the identity of the join: merging with the empty state changes nothing.
lawBottomIdentity :: Grants -> Bool
lawBottomIdentity a = mergeGrants emptyGrants a == a && mergeGrants a emptyGrants == a

-- ─────────────────────────────────────────────────────────────────────────────
-- The fold is a monotone homomorphism (Ledger, ++) → (Grants, mergeGrants).
-- ─────────────────────────────────────────────────────────────────────────────

-- | 'stateOf' is a HOMOMORPHISM: the state of a concatenated ledger is the merge of the parts' states.
-- This is what lets each device fold its OWN slice of the log and merge results — the essence of a
-- state-based CRDT.
lawStateHomomorphism :: Ledger -> Ledger -> Bool
lawStateHomomorphism a b = stateOf (a ++ b) == mergeGrants (stateOf a) (stateOf b)

-- | The empty ledger folds to bottom.
lawStateEmptyIsBottom :: Bool
lawStateEmptyIsBottom = stateOf [] == emptyGrants

-- | MONOTONE in the semilattice order (@⊑@ = subset): appending trades only moves the state UP, never
-- down. (The grant-set restatement of "SixFour.Spec.Trade".'SixFour.Spec.Trade.lawHoldingsMonotone'.)
lawStateMonotone :: Ledger -> Ledger -> Bool
lawStateMonotone a b = stateOf a `Set.isSubsetOf` stateOf (a ++ b)

-- | Duplicate delivery is harmless at the ledger level: folding a log that repeats every trade yields
-- the same state as folding it once.
lawLedgerIdempotent :: Ledger -> Bool
lawLedgerIdempotent l = stateOf (l ++ l) == stateOf l

-- ─────────────────────────────────────────────────────────────────────────────
-- Strong Eventual Consistency + the bridge to the shipped holdings fold.
-- ─────────────────────────────────────────────────────────────────────────────

-- | STRONG EVENTUAL CONSISTENCY (the capstone): replicas that have delivered the same SET of trades
-- hold identical state, regardless of order or duplication. Stated as an implication over
-- element-equal ledgers; @Properties.LedgerCRDT@ additionally drives it constructively by shuffling a
-- duplicated ledger. This is the Shapiro et al. guarantee the monotone-grant design earns for free.
lawStrongEventualConsistency :: Ledger -> Ledger -> Bool
lawStrongEventualConsistency a b
  | sameElems a b = stateOf a == stateOf b
  | otherwise     = True
  where sameElems xs ys = all (`elem` ys) xs && all (`elem` xs) ys

-- | The shipped "SixFour.Spec.Trade".'SixFour.Spec.Trade.holdings' fold is exactly a per-creator slice
-- of the CvRDT state — so this convergence guarantee is about the ACTUAL design, not a parallel model.
lawHoldingsFromState :: Ledger -> CreatorId -> Bool
lawHoldingsFromState led who =
  holdings led who == Set.fromList [ g | (c, g) <- Set.toList (stateOf led), c == who ]

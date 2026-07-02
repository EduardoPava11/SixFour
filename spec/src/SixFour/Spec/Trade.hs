{- |
Module      : SixFour.Spec.Trade
Description : The swap-economy SUBSTRATE — an append-only trade ledger with HYBRID grant semantics. A trade is a bilateral, consented event (a transaction, not a like); the whole polity — holdings, demand, reliability — is a pure FOLD over the ledger. Accepting a trade GRANTS access to both parties without stripping anyone (view-free / asset-trade-gated), so holdings only ever grow ('lawHoldingsMonotone') — scarcity without dispossession.

This is the foundation the governance layer folds over. The design decision it encodes (the locked
"hybrid" swap model): the tiny showcase GIF is public and abundant, but the working weight blob moves
only through a settled trade. Modelled here as GRANT, not TRANSFER — an 'Accepted' trade grants the
proposer the wanted gene and the counterparty the offered gene, and removes nothing. That single
choice buys a real exchange economy (demand, price, guild-gated assets) while dodging the two failure
modes of true transfer: forced digital-scarcity enforcement and newcomer lock-out.

  * 'Trade' / 'Ledger' — the event + the append-only log. A trade is 'Proposed', then settles to
    'Accepted' \/ 'Declined' \/ 'Expired'. 'tWant' = 'Nothing' is an open "best offer" bazaar listing
    (the counterparty supplies the gene they give on 'accept').
  * 'propose' \/ 'accept' \/ 'decline' \/ 'expire' — the state machine. Only a 'Proposed' trade
    settles ('lawOnlyProposedSettles'); you cannot accept your own proposal ('lawNoSelfAccept').
  * 'grants' \/ 'holdings' — the grant fold. 'grants' is the access one settled trade confers;
    'holdings' is the union over the ledger. Non-'Accepted' trades confer nothing
    ('lawUnsettledGrantsNothing').
  * 'demand' — the reputation scalar (people took what you offered). 'reliability' — the trust
    scalar (settled-as-accepted over all your settled proposals), a probability ('lawReliabilityUnit')
    that the governance layer ("SixFour.Spec.GuildScale" sizes the bodies) can gate membership on.

'GeneId' is an 'Int' stand-in for the content-address (the hash of the canonical weight bytes) — the
intrinsic, tamper-evident gene identity; genealogy (parents\/creator) rides in the gene tag, not here.

GHC-boot-only (@containers@). Laws QuickCheck'd in @Properties.Trade@ (to be wired).
-}
-- COMPARTMENT: SWIFT-APP-SOCIAL | tag:DisplaySide
module SixFour.Spec.Trade
  ( -- * Identities
    GeneId(..)
  , CreatorId(..)
  , Epoch
    -- * The event + ledger
  , TradeState(..)
  , Trade(..)
  , Ledger
    -- * The state machine
  , propose
  , accept
  , decline
  , expire
  , isOpen
  , isSettled
    -- * The grant fold (holdings)
  , grants
  , holdings
    -- * The governance scalars
  , demand
  , reliability
    -- * Laws (QuickCheck'd in @Properties.Trade@)
  , lawHoldingsMonotone
  , lawOnlyProposedSettles
  , lawNoSelfAccept
  , lawUnsettledGrantsNothing
  , lawReliabilityUnit
  ) where

import           Data.Maybe (maybeToList)
import           Data.Set   (Set)
import qualified Data.Set   as Set

-- ─────────────────────────────────────────────────────────────────────────────
-- Identities.
-- ─────────────────────────────────────────────────────────────────────────────

-- | A gene's content-address (stand-in for the hash of its canonical weight bytes) — the intrinsic,
-- dedup-able, tamper-evident identity. Creator\/genealogy live in the gene tag, not the trade.
newtype GeneId = GeneId Int
  deriving (Eq, Ord, Show)

-- | A participant identity (stand-in for the public profile handle bound to a Game Center player).
newtype CreatorId = CreatorId Int
  deriving (Eq, Ord, Show)

-- | A logical time step (monotone tick), for ordering and expiry.
type Epoch = Int

-- ─────────────────────────────────────────────────────────────────────────────
-- The event + ledger.
-- ─────────────────────────────────────────────────────────────────────────────

-- | The lifecycle of a trade. 'Proposed' is the only open state; the other three are terminal.
data TradeState = Proposed | Accepted | Declined | Expired
  deriving (Eq, Show)

-- | A single trade event. @tWant = Nothing@ is an open "best offer" listing; the counterparty
-- supplies the gene they give when they 'accept'.
data Trade = Trade
  { tOffer    :: GeneId           -- ^ what the proposer puts up (shown as its 16³ GIF)
  , tWant     :: Maybe GeneId     -- ^ the specific gene wanted, or 'Nothing' = open listing
  , tProposer :: CreatorId        -- ^ who opened the trade
  , tCounter  :: Maybe CreatorId  -- ^ who settled it (set on 'accept')
  , tState    :: TradeState       -- ^ lifecycle position
  , tEpoch    :: Epoch            -- ^ when it was opened
  } deriving (Eq, Show)

-- | The append-only trade log. The entire social layer is a pure fold of this — nothing is stored
-- that cannot be recomputed from the ledger, so @same ledger ⇒ same society@.
type Ledger = [Trade]

-- ─────────────────────────────────────────────────────────────────────────────
-- The state machine.
-- ─────────────────────────────────────────────────────────────────────────────

-- | Open a trade: proposer offers @offer@, optionally wanting a specific @want@ ('Nothing' = open
-- listing), at epoch @e@.
propose :: CreatorId -> GeneId -> Maybe GeneId -> Epoch -> Trade
propose who offer want e = Trade offer want who Nothing Proposed e

-- | Settle a 'Proposed' trade as 'Accepted', recording the counterparty. For an open listing the
-- counterparty's supplied gene @mGiven@ fills 'tWant'; a trade that already names a want keeps it.
-- No-op (identity) on a non-'Proposed' trade, or if the proposer tries to accept their own.
accept :: CreatorId -> Maybe GeneId -> Trade -> Trade
accept who mGiven t
  | tState t /= Proposed = t
  | who == tProposer t   = t
  | otherwise = t { tState   = Accepted
                  , tCounter = Just who
                  , tWant    = maybe mGiven Just (tWant t) }

-- | Settle a 'Proposed' trade as 'Declined'. No-op on a non-'Proposed' trade.
decline :: Trade -> Trade
decline t
  | tState t == Proposed = t { tState = Declined }
  | otherwise            = t

-- | Settle a 'Proposed' trade as 'Expired'. No-op on a non-'Proposed' trade.
expire :: Trade -> Trade
expire t
  | tState t == Proposed = t { tState = Expired }
  | otherwise            = t

-- | Is the trade still open (awaiting a counterparty)?
isOpen :: Trade -> Bool
isOpen t = tState t == Proposed

-- | Has the trade reached a terminal state?
isSettled :: Trade -> Bool
isSettled = not . isOpen

-- ─────────────────────────────────────────────────────────────────────────────
-- The grant fold — holdings.
-- ─────────────────────────────────────────────────────────────────────────────

-- | The access one trade confers. HYBRID GRANT: an 'Accepted' trade grants the proposer the wanted
-- gene and the counterparty the offered gene — and removes nothing. Any non-'Accepted' trade grants
-- @[]@.
grants :: Trade -> [(CreatorId, GeneId)]
grants t
  | tState t /= Accepted = []
  | otherwise =
      [ (tProposer t, g) | g <- maybeToList (tWant t) ]
        ++ [ (c, tOffer t) | c <- maybeToList (tCounter t) ]

-- | The set of genes a creator has been granted access to across the whole ledger. (Genes a creator
-- minted from their own captures seed this separately, via the gene tag — not modelled here.)
holdings :: Ledger -> CreatorId -> Set GeneId
holdings led who =
  Set.fromList [ g | t <- led, (c, g) <- grants t, c == who ]

-- ─────────────────────────────────────────────────────────────────────────────
-- The governance scalars.
-- ─────────────────────────────────────────────────────────────────────────────

-- | Demand for a creator = how many of their proposals were taken (people accepted what they
-- offered). The reputation\/prestige scalar the rank axis is built on.
demand :: Ledger -> CreatorId -> Int
demand led who =
  length [ () | t <- led, tState t == Accepted, tProposer t == who ]

-- | A creator's trade reliability = accepted over all their settled proposals, in @[0,1]@; a fresh
-- creator with no settled proposals is trusted (@1@). The trust scalar guilds can gate on.
reliability :: Ledger -> CreatorId -> Double
reliability led who =
  let mine = [ t | t <- led, tProposer t == who, isSettled t ]
      done = length [ t | t <- mine, tState t == Accepted ]
  in case length mine of
       0 -> 1.0
       n -> fromIntegral done / fromIntegral n

-- ─────────────────────────────────────────────────────────────────────────────
-- Laws (QuickCheck'd in @Properties.Trade@).
-- ─────────────────────────────────────────────────────────────────────────────

-- | HYBRID grant is non-destructive: appending any trade to the ledger never shrinks anyone's
-- holdings. This is the formal statement of "view free, asset trade-gated" — scarcity without
-- dispossession.
lawHoldingsMonotone :: Ledger -> Trade -> CreatorId -> Bool
lawHoldingsMonotone led t who =
  holdings led who `Set.isSubsetOf` holdings (led ++ [t]) who

-- | Only a 'Proposed' trade settles: 'decline', 'expire', and 'accept' are all the identity on a
-- trade that is already terminal.
lawOnlyProposedSettles :: Trade -> Maybe GeneId -> CreatorId -> Bool
lawOnlyProposedSettles t g who
  | tState t == Proposed = True
  | otherwise = decline t == t && expire t == t && accept who g t == t

-- | You cannot accept your own proposal (accept-by-proposer is the identity).
lawNoSelfAccept :: Trade -> Maybe GeneId -> Bool
lawNoSelfAccept t g = tState t /= Proposed || accept (tProposer t) g t == t

-- | A trade that does not reach 'Accepted' grants nothing — declined, expired, and open trades are
-- inert in the holdings fold.
lawUnsettledGrantsNothing :: Trade -> Bool
lawUnsettledGrantsNothing t = tState t == Accepted || null (grants t)

-- | Reliability is a probability: it lies in @[0,1]@ for every creator and ledger.
lawReliabilityUnit :: Ledger -> CreatorId -> Bool
lawReliabilityUnit led who = let r = reliability led who in r >= 0 && r <= 1

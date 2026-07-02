{- |
Module      : SixFour.Spec.Affiliation
Description : GUILDS as connected components of the trade graph — affiliation is BEHAVIOURAL (who you swap with), not declared. An accepted trade is an undirected edge between its two parties; a guild is a connected component of active traders; the partition is exact ('lawAffiliationPartitions'). Components that exceed the derived 'guildCap' are flagged for schism (a governance event), tying this layer to "SixFour.Spec.GuildScale".

The affiliation half of the swap economy: "SixFour.Spec.Trade" is the ledger, this is the fold that
finds the tribes in it. Behavioural affiliation is truer than a chosen label — you belong to whom you
actually exchange with. Feeds "SixFour.Spec.Governance" (each component is a guild whose council is
the top 'councilSize' of its governed roster).

  * 'tradeEdges' \/ 'tradeGraph' — the undirected co-trade graph from ACCEPTED trades (open\/declined\/
    expired trades are inert). Symmetric adjacency ('lawGraphSymmetric').
  * 'components' \/ 'affiliationOf' — the guilds (connected components) and the guild of a given
    trader. Every active trader lands in exactly one guild ('lawEveryActiveHasGuild',
    'lawAffiliationPartitions'); trade partners share a guild ('lawPartnersShareGuild').
  * 'oversizeGuilds' — components larger than 'guildCap' (150): the ones that must schism.

GHC-boot-only (@containers@). Laws QuickCheck'd in @Properties.Affiliation@.
-}
-- COMPARTMENT: SWIFT-APP-SOCIAL | tag:DisplaySide
module SixFour.Spec.Affiliation
  ( -- * The trade graph
    Edge
  , tradeEdges
  , tradeGraph
    -- * Guilds (connected components)
  , components
  , affiliationOf
  , oversizeGuilds
    -- * Laws (QuickCheck'd in @Properties.Affiliation@)
  , lawGraphSymmetric
  , lawAffiliationPartitions
  , lawEveryActiveHasGuild
  , lawPartnersShareGuild
  ) where

import           Data.List  (find, foldl')
import           Data.Map   (Map)
import qualified Data.Map   as Map
import           Data.Maybe (mapMaybe)
import           Data.Set   (Set)
import qualified Data.Set   as Set

import           SixFour.Spec.GuildScale (guildCap)
import           SixFour.Spec.Trade      (CreatorId, Ledger, Trade(..), TradeState(..))

-- | An undirected co-trade edge between two distinct traders (stored normalised, smaller id first).
type Edge = (CreatorId, CreatorId)

-- | The edges of the trade graph: one per ACCEPTED trade that has a counterparty. Open, declined, and
-- expired trades contribute nothing (they never bound two people together).
tradeEdges :: Ledger -> [Edge]
tradeEdges = mapMaybe edgeOf
  where
    edgeOf t
      | tState t /= Accepted            = Nothing
      | Just c <- tCounter t, c /= tProposer t =
          Just (if tProposer t <= c then (tProposer t, c) else (c, tProposer t))
      | otherwise                       = Nothing

-- | The undirected adjacency map of the trade graph (symmetric by construction).
tradeGraph :: Ledger -> Map CreatorId (Set CreatorId)
tradeGraph led =
  Map.fromListWith Set.union
    (concat [ [(a, Set.singleton b), (b, Set.singleton a)] | (a, b) <- tradeEdges led ])

-- | The guilds: connected components of the trade graph, each a set of traders.
components :: Ledger -> [Set CreatorId]
components led = go (Map.keys g) Set.empty []
  where
    g = tradeGraph led
    go []       _    acc = reverse acc
    go (n : ns) seen acc
      | n `Set.member` seen = go ns seen acc
      | otherwise           = let comp = bfs g n
                              in go ns (Set.union seen comp) (comp : acc)

-- | Breadth-first flood of the component containing @start@.
bfs :: Map CreatorId (Set CreatorId) -> CreatorId -> Set CreatorId
bfs g start = go [start] Set.empty
  where
    go []       seen = seen
    go (x : xs) seen
      | x `Set.member` seen = go xs seen
      | otherwise           =
          let nbrs = Set.toList (Map.findWithDefault Set.empty x g)
          in go (nbrs ++ xs) (Set.insert x seen)

-- | The guild containing a trader, or 'Nothing' if they have no accepted trades (not active).
affiliationOf :: Ledger -> CreatorId -> Maybe (Set CreatorId)
affiliationOf led who = find (who `Set.member`) (components led)

-- | Guilds that exceed the derived 'guildCap' — the ones a healthy polity must schism.
oversizeGuilds :: Ledger -> [Set CreatorId]
oversizeGuilds led = filter ((> guildCap) . Set.size) (components led)

-- ─────────────────────────────────────────────────────────────────────────────
-- Laws (QuickCheck'd in @Properties.Affiliation@).
-- ─────────────────────────────────────────────────────────────────────────────

-- | The trade graph is symmetric: @b@ is a neighbour of @a@ iff @a@ is a neighbour of @b@.
lawGraphSymmetric :: Ledger -> Bool
lawGraphSymmetric led =
  and [ Set.member b (nbrs a) == Set.member a (nbrs b)
      | a <- nodes, b <- nodes ]
  where
    g       = tradeGraph led
    nodes   = Map.keys g
    nbrs x  = Map.findWithDefault Set.empty x g

-- | The guilds PARTITION the active traders: pairwise disjoint (sizes sum to the whole) and covering
-- exactly the graph's nodes.
lawAffiliationPartitions :: Ledger -> Bool
lawAffiliationPartitions led =
  let comps = components led
      nodes = Set.fromList (Map.keys (tradeGraph led))
      union = Set.unions comps
      sizes = sum (map Set.size comps)
  in union == nodes && sizes == Set.size union

-- | Every active trader (a node of the graph) belongs to some guild.
lawEveryActiveHasGuild :: Ledger -> Bool
lawEveryActiveHasGuild led =
  all (\n -> affiliationOf led n /= Nothing) (Map.keys (tradeGraph led))

-- | Trade partners share a guild: both parties of an accepted trade land in the same component.
lawPartnersShareGuild :: Ledger -> Bool
lawPartnersShareGuild led =
  all (\(a, b) -> affiliationOf led a == affiliationOf led b) (tradeEdges led)

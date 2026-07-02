{- |
Module      : SixFour.Spec.Lineage
Description : The gene GENEALOGY as a content-addressed DAG — each gene tag carries its creator and its parents (the genes it was remixed from), so influence is a fold over descendants. Adopt-and-remix appends an edge; @influence = |descendants|@ is the lineage rank scalar, and a gene with no parents is an origin (a wild capture). Acyclic BY CONSTRUCTION (a content-addressed child's hash depends on its parents, so it cannot be its own ancestor).

This is the genealogy half of the swap economy (the trade LEDGER is "SixFour.Spec.Trade"; genealogy
is orthogonal — it tracks where genes come FROM, not who traded them). Together they feed
"SixFour.Spec.Governance": prestige = trade demand, LINEAGE = descendant influence.

  * 'GeneTag' \/ 'Genealogy' — a gene's provenance (creator + parents + mint epoch) and the DAG as a
    tag list. 'isOrigin' = no parents = a wild capture.
  * 'ancestors' \/ 'descendants' — the transitive closures (visited-guarded, so total even on
    malformed input). Dual: @b ∈ descendants a ⇔ a ∈ ancestors b@ ('lawAncestorDescendantDual').
  * 'generation' — longest path from an origin (0 for an origin), strictly above every parent
    ('lawGenerationExceedsParents').
  * 'influence' \/ 'creatorInfluence' — descendant count of a gene \/ of all a creator's genes: the
    LINEAGE reputation scalar ('lawInfluenceIsDescendantCount').

GHC-boot-only (@containers@). Laws QuickCheck'd in @Properties.Lineage@ over generated DAGs.
-}
-- COMPARTMENT: SWIFT-APP-SOCIAL | tag:DisplaySide
module SixFour.Spec.Lineage
  ( -- * The genealogy DAG
    GeneTag(..)
  , Genealogy
  , isOrigin
  , geneIds
  , parentsOf
  , childrenOf
    -- * Closures & depth
  , ancestors
  , descendants
  , generation
    -- * Lineage reputation
  , influence
  , creatorInfluence
    -- * Laws (QuickCheck'd in @Properties.Lineage@)
  , lawOriginHasNoAncestors
  , lawAncestorDescendantDual
  , lawAcyclicNoSelfAncestor
  , lawGenerationOriginZero
  , lawGenerationExceedsParents
  , lawInfluenceIsDescendantCount
  ) where

import           Data.Set (Set)
import qualified Data.Set as Set

import           SixFour.Spec.Trade (CreatorId, Epoch, GeneId)

-- ─────────────────────────────────────────────────────────────────────────────
-- The genealogy DAG.
-- ─────────────────────────────────────────────────────────────────────────────

-- | A gene's provenance tag. @gtParents@ are the genes it was remixed from ('[]' = an origin, minted
-- fresh from a capture). Acyclic by construction: a content-addressed child hashes over its parents.
data GeneTag = GeneTag
  { gtGene    :: GeneId      -- ^ the content-address of this gene
  , gtCreator :: CreatorId   -- ^ who minted it
  , gtParents :: [GeneId]    -- ^ the genes it derived from ('[]' = origin)
  , gtMinted  :: Epoch       -- ^ first-seen epoch (provenance)
  } deriving (Eq, Show)

-- | The genealogy as a tag list (the DAG's nodes-with-edges).
type Genealogy = [GeneTag]

-- | Is this gene an origin (a wild capture, no parents)?
isOrigin :: GeneTag -> Bool
isOrigin = null . gtParents

-- | Every gene id present in the genealogy.
geneIds :: Genealogy -> [GeneId]
geneIds = map gtGene

-- | The immediate parents (derived-from) of a gene.
parentsOf :: Genealogy -> GeneId -> [GeneId]
parentsOf g gid = case [ t | t <- g, gtGene t == gid ] of
  (t : _) -> gtParents t
  []      -> []

-- | The immediate children (genes that remixed this one).
childrenOf :: Genealogy -> GeneId -> [GeneId]
childrenOf g gid = [ gtGene t | t <- g, gid `elem` gtParents t ]

-- ─────────────────────────────────────────────────────────────────────────────
-- Closures & depth.
-- ─────────────────────────────────────────────────────────────────────────────

-- | Transitive closure of a neighbour step from a start node, EXCLUDING the start unless a cycle
-- reaches back to it. Visited-guarded, so total on any input.
reachable :: (GeneId -> [GeneId]) -> GeneId -> Set GeneId
reachable step start = go (step start) Set.empty
  where
    go []       seen = seen
    go (x : xs) seen
      | x `Set.member` seen = go xs seen
      | otherwise           = go (step x ++ xs) (Set.insert x seen)

-- | All ancestors of a gene (transitively up the parent edges).
ancestors :: Genealogy -> GeneId -> Set GeneId
ancestors g = reachable (parentsOf g)

-- | All descendants of a gene (transitively down the child edges) — the lineage it seeded.
descendants :: Genealogy -> GeneId -> Set GeneId
descendants g = reachable (childrenOf g)

-- | The generation of a gene: 0 for an origin, else one more than its deepest parent. Visited-guarded
-- (returns 0 on a revisit) so it is total even on malformed cyclic input.
generation :: Genealogy -> GeneId -> Int
generation g = go Set.empty
  where
    go seen gid
      | gid `Set.member` seen = 0
      | otherwise = case parentsOf g gid of
          [] -> 0
          ps -> 1 + maximum (map (go (Set.insert gid seen)) ps)

-- ─────────────────────────────────────────────────────────────────────────────
-- Lineage reputation.
-- ─────────────────────────────────────────────────────────────────────────────

-- | The influence of a gene = how many genes descend from it (the lineage rank scalar).
influence :: Genealogy -> GeneId -> Int
influence g = Set.size . descendants g

-- | A creator's total lineage influence = the descendant count summed over every gene they minted.
creatorInfluence :: Genealogy -> CreatorId -> Int
creatorInfluence g who =
  sum [ influence g (gtGene t) | t <- g, gtCreator t == who ]

-- ─────────────────────────────────────────────────────────────────────────────
-- Laws (QuickCheck'd in @Properties.Lineage@ over generated DAGs).
-- ─────────────────────────────────────────────────────────────────────────────

-- | An origin gene has no ancestors.
lawOriginHasNoAncestors :: Genealogy -> Bool
lawOriginHasNoAncestors g =
  all (\t -> not (isOrigin t) || Set.null (ancestors g (gtGene t))) g

-- | Ancestry and descent are dual: @b ∈ descendants a ⇔ a ∈ ancestors b@ for every pair of genes.
lawAncestorDescendantDual :: Genealogy -> Bool
lawAncestorDescendantDual g =
  and [ (b `Set.member` descendants g a) == (a `Set.member` ancestors g b)
      | a <- ids, b <- ids ]
  where ids = geneIds g

-- | On an acyclic genealogy no gene is its own ancestor (the DAG invariant content-addressing gives).
lawAcyclicNoSelfAncestor :: Genealogy -> Bool
lawAcyclicNoSelfAncestor g =
  all (\gid -> not (gid `Set.member` ancestors g gid)) (geneIds g)

-- | An origin sits at generation 0.
lawGenerationOriginZero :: Genealogy -> Bool
lawGenerationOriginZero g =
  all (\t -> not (isOrigin t) || generation g (gtGene t) == 0) g

-- | A gene's generation strictly exceeds every parent's — depth increases down the lineage.
lawGenerationExceedsParents :: Genealogy -> Bool
lawGenerationExceedsParents g =
  all (\gid -> all (\p -> generation g gid > generation g p) (parentsOf g gid))
      (geneIds g)

-- | Influence is exactly the descendant count (pins the lineage scalar to the DAG).
lawInfluenceIsDescendantCount :: Genealogy -> Bool
lawInfluenceIsDescendantCount g =
  all (\gid -> influence g gid == Set.size (descendants g gid)) (geneIds g)

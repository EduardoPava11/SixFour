{- |
Module      : SixFour.Spec.GeneRecombination
Description : Sexual, balanced gene crossover. Two parent θ blobs recombine into a child whose lineage commits BOTH parents (extending the acyclic Merkle-DAG), and whose grantability is decided by LINEAGE (the child is tradeable to someone only if they hold BOTH parents), never by payload-in-holdings, so crossover conjures no mint credit.

The swap substrate records a gene's @gpParents@ but never had the OPERATOR that
produces a two-parent child. This module mints it. SEXUAL = a per-word Q16 lerp
@child = (1−λ)·A + λ·B@ over the 21-word @θ_up@ manifold; because the detail head
@rawBands@ is LINEAR in θ (no hidden-unit permutation symmetry), the two parents
already share one basis and the blend needs no Git-Re-Basin alignment (the
degenerate always-connected case of linear mode connectivity). BALANCED = the
child rides its parents' existing grants and adds nothing to the ledger: 'recombine'
has NO @Ledger@ in its type, so it cannot create credit; credit is minted only at a
settled trade ('SixFour.Spec.SwapCarrier' @mintGrant@), never at a crossover.

The keystone is RE-KEYED on lineage. A naive "grantable iff the child's PAYLOAD is
in holdings" is dead: a byte-novel blend is NEVER in holdings, so that predicate is
vacuously false in the interior and false at the endpoints. Instead grantability is
DAG membership ('mayGrantChild' = holds BOTH parent ids), which the mint actually
populates. This closes the single-parent laundering hole ('lawChildGrantableIffBothParentsHeld',
with the OR-variant 'keystoneWith' shown to FAIL on a single-parent ledger).

== The gene is an S-combinator; crossover composes two of them

In the S\/K\/I reading (@I = λx.x@ floor, @K = λx y.x@ pool, @S = λf g x. f x (g x)@
expand), a gene is exactly the weight payload of an @S@ operation, the only place
detail is invented. Recombination COMPOSES two @S@ inventors into one; the balance
law is the constraint that the composition mints no new economic mass, only new
phenotype.

== Discrete geometry + algebraic number theory

  * The lerp is byte-exact and order-independent: integer accumulate then arithmetic
    shift @>>16@ (@lerpWord a b = (a·(1−λ) + b·λ) >> 16@), a ℤ[1\/2] dyadic operation,
    so a power-of-two @λ@ (0x8000 = ½) blends without leaving ℤ ('lawBlendRecoversParentAtEndpoint').
  * @gpParents@ commits @[idOf pa, idOf pb]@ IN ORDER; the mate order is
    hash-significant, so the credit law treats the unordered pair as one event while
    the DAG stays acyclic ('SixFour.Spec.GeneHash' @lawBuiltGenealogyAcyclic@).
  * The child stays on the 21-word manifold ('lawCrossoverPreservesShape'): crossover
    is a within-lattice move, never a dimensionality drift.
-}
-- COMPARTMENT: SWIFT-APP-SOCIAL | tag:DisplaySide
module SixFour.Spec.GeneRecombination
  ( -- * Blend weights (Q16 fractions)
    BlendWeight
  , unitQ16
  , halfLambda
    -- * The crossover operator and lineage-keyed grant
  , ParentGene
  , Child
  , recombine
  , idOf
  , holdsGene
  , mayGrantChild
    -- * Keystone (re-keyed on lineage) and its parameterised form
  , lawChildGrantableIffBothParentsHeld
  , keystoneWith
    -- * Supporting laws
  , lawCrossoverPreservesShape
  , lawChildParentsAreMates
  , lawBlendRecoversParentAtEndpoint
  , lawRecombineCreditNeutralOnEmptyLedger
  ) where

import           Data.Bits (shiftR)
import qualified Data.Set  as Set

import SixFour.Spec.GeneHash        (GenePreimage(..), geneHash)
import SixFour.Spec.DetailPredictor (PredictorShape, defaultPredictorShape, paramCount)
import SixFour.Spec.Trade           (CreatorId, GeneId, Ledger, holdings)

-- | A blend weight is a Q16 fraction. Unity (λ = 1.0) is @0x10000@, NOT @0xFFFF@.
type BlendWeight = Int

-- | @λ = 1.0@ in Q16.
unitQ16 :: BlendWeight
unitQ16 = 0x10000

-- | @λ = 0.5@ in Q16 (a power of two, so the blend is an exact shift).
halfLambda :: BlendWeight
halfLambda = 0x8000

-- | A parent gene IS a 'GenePreimage': payload = Q16 words, @gpParents@ = lineage.
type ParentGene = GenePreimage

-- | A bred child gene (also a 'GenePreimage'); its @gpParents@ is the ordered mate pair.
type Child      = GenePreimage

-- | A gene's content-address (the real 'geneHash' over its canonical bytes).
idOf :: GenePreimage -> GeneId
idOf = geneHash

-- | Does @who@ hold this gene id, per the real settled-trade grant fold (NOT
-- payload-in-holdings)?
holdsGene :: Ledger -> CreatorId -> GeneId -> Bool
holdsGene led who g = Set.member g (holdings led who)

-- | THE OPERATOR: a per-word Q16 lerp over the 21-word manifold,
-- @child = (1−λ)·A + λ·B@. Integer accumulate then @>>16@ = byte-exact and
-- order-independent. @gpParents@ commits @[idOf pa, idOf pb]@ in order.
recombine :: PredictorShape -> BlendWeight -> ParentGene -> ParentGene -> Child
recombine sh lam pa pb =
  GenePreimage
    { gpPayload = zipWith lerpWord (fit (gpPayload pa)) (fit (gpPayload pb))
    , gpParents = [idOf pa, idOf pb] }
  where
    n = paramCount sh
    fit xs = take n (xs ++ repeat 0)
    lerpWord a b = (a * (unitQ16 - lam) + b * lam) `shiftR` 16

-- | Grantability of a bred child is DAG membership: @who@ may be granted the child
-- only by holding BOTH parents. Never payload-in-holdings (a novel blend is never there).
mayGrantChild :: Ledger -> CreatorId -> Child -> Bool
mayGrantChild led who child =
     holdsGene led who (gpParents child !! 0)
  && holdsGene led who (gpParents child !! 1)

-- | ★ KEYSTONE (re-keyed on lineage): a mid-blend child is grantable to @who@ iff
-- @who@ holds BOTH parents. Closes the single-parent laundering hole.
lawChildGrantableIffBothParentsHeld :: Ledger -> CreatorId -> ParentGene -> ParentGene -> Bool
lawChildGrantableIffBothParentsHeld led who pa pb =
  let child = recombine defaultPredictorShape halfLambda pa pb
  in  mayGrantChild led who child
        == (holdsGene led who (idOf pa) && holdsGene led who (idOf pb))

-- | The keystone parameterised by the grant predicate, so a WRONG (OR) implementation
-- is provably falsified on a single-parent ledger.
keystoneWith
  :: (Ledger -> CreatorId -> Child -> Bool)
  -> Ledger -> CreatorId -> ParentGene -> ParentGene -> Bool
keystoneWith mgc led who pa pb =
  let child = recombine defaultPredictorShape halfLambda pa pb
  in  mgc led who child == (holdsGene led who (idOf pa) && holdsGene led who (idOf pb))

-- | The child stays on the 21-word manifold (no dimensionality drift).
lawCrossoverPreservesShape :: BlendWeight -> ParentGene -> ParentGene -> Bool
lawCrossoverPreservesShape lam pa pb =
  length (gpPayload (recombine defaultPredictorShape lam pa pb)) == paramCount defaultPredictorShape

-- | The child's lineage is exactly its ordered mate pair (extends the acyclic DAG).
lawChildParentsAreMates :: BlendWeight -> ParentGene -> ParentGene -> Bool
lawChildParentsAreMates lam pa pb =
  gpParents (recombine defaultPredictorShape lam pa pb) == [idOf pa, idOf pb]

-- | Endpoints recover a parent byte-exactly: @λ=0@ ⇒ payload of A, @λ=unit@ ⇒ payload of B.
lawBlendRecoversParentAtEndpoint :: ParentGene -> ParentGene -> Bool
lawBlendRecoversParentAtEndpoint pa pb =
  let fit xs = take (paramCount defaultPredictorShape) (xs ++ repeat 0)
  in  gpPayload (recombine defaultPredictorShape 0       pa pb) == fit (gpPayload pa)
   && gpPayload (recombine defaultPredictorShape unitQ16 pa pb) == fit (gpPayload pb)

-- | Balance: 'recombine' has no @Ledger@ in its type, so on an EMPTY ledger no bred
-- child is grantable to anyone. Crossover conjures no credit; credit is minted only
-- at a settled trade.
lawRecombineCreditNeutralOnEmptyLedger :: CreatorId -> ParentGene -> ParentGene -> Bool
lawRecombineCreditNeutralOnEmptyLedger who pa pb =
  not (mayGrantChild [] who (recombine defaultPredictorShape halfLambda pa pb))

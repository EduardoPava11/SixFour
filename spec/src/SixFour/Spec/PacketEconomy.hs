{- |
Module      : SixFour.Spec.PacketEconomy
Description : Decode-compute is the scarce resource genes compete for. A gene is passed on in proportion to the MEANING it delivers per decode-packet, so a gene Pareto-dominated (weakly more meaning for weakly fewer packets, strict in one axis) is NOT an elite. Encode is cheap; decode spends S/K/I packets; the competition is for the weighted S-packet.

Genes are trained per capture and stored cheaply (encoding is the frozen reversible
lift). What is scarce is DECODING: expressing a gene up the rung ladder spends real
packets. This module makes "efficient genes are the elites" a law and keeps the two
fitnesses DISJOINT so the atlas cannot collapse to a monoculture:

  * "does something" is OBJECTIVE, machine-measured against a HELD data-manufactured
    target ('meaning' > 0, 'admitted'); it is the ADMISSION gate and ships now.
  * "human attention" is SOCIAL, entitlement-gated, dormant; it would be a
    within-cell selector and is deliberately absent here. There is no single global
    fitness scalar: 'meaning' never reads a gene's own output (that self-produced
    target is the BYOL / L_close collapse), and attention is not fused into it.

== The S, K, I combinators (as lambda terms)

The refinement ladder is a substructural spine. Each rung is one combinator, and
a schedule is a coarse-to-fine list of them. Written as pure lambdas:

@
  I = λx. x            -- identity: the reversible coarse FLOOR read. FREE (0 packets).
  K = λx y. x          -- const: a lossy POOL that keeps one band and weakens the rest.
  S = λf g x. f x (g x)  -- the weighted EXPAND/invent where the GENE's θ lives.
@

'I' is weakening's dual identity, 'K' is weakening (discard), 'S' carries contraction
(the shared @x@ used twice = the duplicate-and-combine that manufactures detail). The
gene rides the 'S' band, so "genes compete for decode-compute" is precisely "genes
compete for S-packets": 'packets' charges every 'K' and 'S' one unit and the leading
'I' floor read nothing ('lawFloorGeneIsParetoOrigin' pins the empty schedule at 0).
Maximising the useful latent operations per packet of allowable compute IS climbing
the meaning-per-'S'-packet Pareto frontier.

== Discrete geometry + algebraic number theory

  * 'meaning' is an INTEGER: the L¹ byte distance to a held target, floor-relative
    (@L¹(floor,target) − L¹(gene,target)@), computed on committed @P6.L@ bytes, never
    on raw floats. "Does something" = strictly above the floor.
  * Selection order is meaning-per-packet by INTEGER CROSS-MULTIPLY
    (@mx·py ≤ my·px@, 'lawMeaningPerPacketSelected'), never a division: ratios on the
    ℤ[1\/2] floor are compared without leaving ℤ.
  * The floor gene ('zeroParams') is the Pareto ORIGIN: 0 meaning, 0 packets, not
    admitted, never elite; the whole frontier is anchored there.
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none
module SixFour.Spec.PacketEconomy
  ( -- * Domain
    Combinator(..)
  , Schedule
  , Packets
  , Meaning
  , Gene
  , HeldTarget(..)
    -- * The economy (concrete, total, over real primitives)
  , decodeBytes
  , meaning
  , packets
  , admitted
  , dominates
  , isElite
  , selWeightLeq
  , floorGene
    -- * Laws (parameterised by the elite predicate, so a vacuous @const False@ is falsified)
  , lawEfficiencyParetoDominated
  , lawEliteNonEmptyWhenAdmitted
  , lawEliteSubsetAdmitted
  , lawMeaningPerPacketSelected
  , lawFloorGeneIsParetoOrigin
  ) where

import SixFour.Spec.DetailPredictor    (PredictorShape, defaultPredictorShape, zeroParams)
import SixFour.Spec.GeneSimilarity     (expressGene)
import SixFour.Spec.RelationalResidual  (P6(..))

sh :: PredictorShape
sh = defaultPredictorShape

-- | The three refinement combinators, as their pure lambda terms:
--   @I = λx. x@ (the free reversible floor read), @K = λx y. x@ (a lossy pool),
--   @S = λf g x. f x (g x)@ (the weighted expand/invent where the gene lives).
data Combinator = I | K | S deriving (Eq, Show)

-- | A coarse-to-fine schedule of refinement packets (the leading floor read is @I@).
type Schedule = [Combinator]

-- | Packets spent ABOVE the floor: the @I@ floor read is free, every @K@ or @S@ costs 1.
type Packets = Int

-- | Meaning delivered, an integer L¹ byte reduction versus a held target.
type Meaning = Int

-- | A gene: a predictor shape and its flat θ words (the @expressGene@ input).
type Gene = (PredictorShape, [Double])

-- | A held, data-manufactured target (REAL bytes, never a gene's own output).
newtype HeldTarget = HeldTarget { targetBytes :: [Int] }

-- | The L-axis committed byte cloud a gene decodes to on the pinned probe lattice
-- (the REAL device forward @expressGene@ → @predictDetail@ → @P6.L@ byte).
decodeBytes :: Gene -> [Int]
decodeBytes (s, ps) = [ p6L p | p <- expressGene s ps ]

l1 :: [Int] -> [Int] -> Int
l1 a b = sum (zipWith (\x y -> abs (x - y)) a b)

-- | @meaning t g@ = @L¹(decode floor, target) − L¹(decode g, target)@. The reference
-- is the HELD data, never the gene: this is the anti-collapse guarantee.
meaning :: HeldTarget -> Gene -> Meaning
meaning (HeldTarget tgt) (s, ps) =
  l1 (decodeBytes (s, zeroParams s)) tgt - l1 (decodeBytes (s, ps)) tgt

-- | Packets above the floor: charge every @K@ and @S@, the @I@ floor read is free.
packets :: Schedule -> Packets
packets = length . filter (/= I)

-- | "Does something": strictly above the floor.
admitted :: HeldTarget -> Gene -> Bool
admitted t g = meaning t g > 0

-- | Pareto domination on (meaning UP, packets DOWN), strict in at least one axis.
dominates :: HeldTarget -> (Gene,Schedule) -> (Gene,Schedule) -> Bool
dominates t (gb,sb) (ga,sa) =
     meaning t gb >= meaning t ga && packets sb <= packets sa
  && (meaning t gb >  meaning t ga || packets sb <  packets sa)

-- | The canonical elite predicate: admitted AND not Pareto-dominated by any pool member.
isElite :: HeldTarget -> [(Gene,Schedule)] -> (Gene,Schedule) -> Bool
isElite t pool a = admitted t (fst a) && not (any (\b -> dominates t b a) pool)

-- | Selection ordered EXACTLY by meaning-per-packet, integer cross-multiply, no divide.
selWeightLeq :: HeldTarget -> (Gene,Schedule) -> (Gene,Schedule) -> Bool
selWeightLeq t (gx,sx) (gy,sy) = meaning t gx * packets sy <= meaning t gy * packets sx

-- | The floor gene: zero θ, the Pareto origin.
floorGene :: Gene
floorGene = (sh, zeroParams sh)

infixr 0 ==>
(==>) :: Bool -> Bool -> Bool
p ==> q = not p || q

-- | KEYSTONE: no Pareto-dominated gene is an elite (dominated ⇒ not elite). Parameterised
-- by the elite predicate so the vacuous @const False@ is caught by the liveness law below.
lawEfficiencyParetoDominated
  :: (HeldTarget -> [(Gene,Schedule)] -> (Gene,Schedule) -> Bool)
  -> HeldTarget -> [(Gene,Schedule)] -> (Gene,Schedule) -> Bool
lawEfficiencyParetoDominated elite t pool a =
  any (\b -> dominates t b a) pool ==> not (elite t pool a)

-- | LIVENESS (de-vacuifying): if the pool has an admitted gene, the elite set is
-- non-empty. This makes @isElite = const False@ ILLEGAL, so the keystone constrains
-- a genuinely non-empty frontier.
lawEliteNonEmptyWhenAdmitted
  :: (HeldTarget -> [(Gene,Schedule)] -> (Gene,Schedule) -> Bool)
  -> HeldTarget -> [(Gene,Schedule)] -> Bool
lawEliteNonEmptyWhenAdmitted elite t pool =
  any (admitted t . fst) pool ==> any (elite t pool) pool

-- | Every elite is admitted (the elite set is a subset of the admitted set).
lawEliteSubsetAdmitted
  :: (HeldTarget -> [(Gene,Schedule)] -> (Gene,Schedule) -> Bool)
  -> HeldTarget -> [(Gene,Schedule)] -> (Gene,Schedule) -> Bool
lawEliteSubsetAdmitted elite t pool a = elite t pool a ==> admitted t (fst a)

-- | Selection weight orders exactly as integer meaning-per-packet.
lawMeaningPerPacketSelected :: HeldTarget -> (Gene,Schedule) -> (Gene,Schedule) -> Bool
lawMeaningPerPacketSelected t x@(gx,_) y@(gy,_) =
  (admitted t gx && admitted t gy) ==>
    (selWeightLeq t x y == (meaning t gx * packets (snd y) <= meaning t gy * packets (snd x)))

-- | The floor gene is the Pareto origin: 0 meaning, 0 packets, not admitted.
lawFloorGeneIsParetoOrigin :: HeldTarget -> Bool
lawFloorGeneIsParetoOrigin t =
  meaning t floorGene == 0 && packets [] == 0 && not (admitted t floorGene)

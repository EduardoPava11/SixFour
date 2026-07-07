{- |
Module      : SixFour.Spec.GeneDensity
Description : A GENE IS A MASS-PRESERVING-UP-TO-WARP PUSHFORWARD on the 64³ colour density. The density is the byte-exact integer count histogram @ρ@ already shipped as "SixFour.Spec.V21Transport" 'SixFour.Spec.V21Transport.Hist' (per-value counts over @0..levels-1@). A gene ("SixFour.Spec.GeneHash" 'GenePreimage') deterministically manufactures a per-value WARP @φ_g@; its ACTION @g·ρ@ re-buckets the finite integer multiset by pushforward, so total mass is conserved EXACTLY in ℤ while colour is redistributed. The whole structure is a MONOID ACTION on the ℤ≥0-module of densities: 'composeWarp'/'identityWarp' are the action axioms, 'lawGeneMassConserved' says the action preserves the augmentation @Σρ@, 'lawActionIsPushforward' is the single-target (Monge) qualifier, 'lawWarpBiLipschitz' is admissibility/no-collapse, 'lawScaleEquivariant' is naturality across the 64/32/16 pyramid, and 'lawRecombinationClosed' is closure of the warp set under breeding. Every law is a byte-exact QuickCheck predicate on integer histograms and warps — no float, no tolerance.

== THE CARRIER (the one committed decision)

The reused "SixFour.Spec.V21Transport" 'SixFour.Spec.V21Transport.pushforward' is RANK-indexed: it
sorts @ρ@ into a mass line and displaces per-rank. As a map on COLOUR VALUES it is @ρ@-dependent, not
single-target, non-linear, and DROPS out-of-gamut mass — so it is NOT a monoid action and does not
satisfy Monge, composition, linearity, or scale-equivariance on colour space. This module therefore
commits to the OTHER, provable carrier: a __value point-map__ @φ : {0..levels-1} → {0..levels-1}@ (the
'Warp', the "SixFour.Spec.TransportGroup" slot-permutation face specialised to the value axis). Its
pushforward is the explicit PREIMAGE-SUM @(φ#ρ)[y] = Σ_{x: φ(x)=y} ρ[x]@ ('pushDensity'). This ρ-INDEPENDENT
bin→bin map is the object for which mass conservation, single-target Monge, functorial composition,
linearity, and pool-equivariance are all THEOREMS in ℤ. The rank-'SixFour.Spec.V21Transport.Disp' face is
cited but not built on (its laws live in "SixFour.Spec.V21Transport").

== ADMISSIBILITY (no-collapse is a GATE, not a universal law)

A general 'Warp' may be non-injective — 'pushDensity' still conserves mass (preimage-sum re-buckets a
finite multiset; a clamped many-to-one target PILES mass on a bin, never DROPS it). The
"SixFour.Spec.CombinatorExactSequence" coarse-forgetting @K@ is exactly such a mass-conserving but
non-injective operator: an operator, but NOT an admissible gene. 'admissible' (the two-sided integer
bi-Lipschitz bound of "SixFour.Spec.DescriptorQuasiIsometry", reused verbatim) is the GATE genes must
pass ('lawWarpBiLipschitz'); the exact-arithmetic admissible warps are the L¹ isometry group of the
value axis (@Z₂ = {identity, reversal}@), which 'warpOf' ranges over as the PURE-SPEC-WALL standin. The
real 21-word @θ_up → colour-index@ realization is a separate MLX-MODEL seam behind 'warpOf' and must not
leak into these pure laws.

== TWO 'MASS' NOTIONS (do not overload)

'dcOf' here is COLOUR-DENSITY mass @Σρ@ = photon count = the DC read by @K@ ('lawWarpCommutesWithK'). This
is a DIFFERENT quantity from "SixFour.Spec.GeneRecombination"'s ECONOMIC mass (credit/ledger, "mints no
new mass"); that module's ring is left alone. A marginal (per-channel) warp cannot express channel-coupled
hue/chroma rotations — the byte-exact joint 3-D RGB carrier is out of scope, stated here as a boundary, not
a law. Pure-spec, exact @Integer@, reusing "SixFour.Spec.V21Transport" / "SixFour.Spec.V21Pyramid" /
"SixFour.Spec.DescriptorQuasiIsometry" / "SixFour.Spec.GeneHash".
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none
module SixFour.Spec.GeneDensity
  ( -- * The density and its warp carrier
    Density
  , DensityField
  , Warp
  , nLevels
    -- * Value point-maps (the warp algebra)
  , identityWarp
  , reverseWarp
  , composeWarp
  , admissible
    -- * The action of a gene on a density
  , warpOf
  , idGene
  , pushDensity
  , act
  , actField
  , dcOf
  , expressedEnergy
  , recombineWarp
    -- * Laws
  , lawGeneMassConserved
  , lawActionIsPushforward
  , lawActionComposes
  , lawIdentityGeneIsIdentityWarp
  , lawWarpBiLipschitz
  , lawScaleEquivariant
  , lawRecombinationClosed
  , lawWarpCommutesWithK
  , lawExpressedEnergyBounded
  ) where

import SixFour.Spec.V21Transport (Hist, mass)
import SixFour.Spec.V21Pyramid (Side, Factor, poolSpatial)
import SixFour.Spec.DetailPredictor (PredictorShape(..))
import SixFour.Spec.GeneHash (GenePreimage(..), gpPayload)
import SixFour.Spec.DescriptorQuasiIsometry (loNum, loDen, hiNum, hiDen, slack)

-- | The colour DENSITY: the per-value integer COUNT histogram over @0..levels-1@, REUSED verbatim from
--   "SixFour.Spec.V21Transport" ('SixFour.Spec.V21Transport.Hist'). The density IS the shipped count
--   histogram; this is not a new type.
type Density = Hist

-- | The spatial-cube face of @ρ@: the FLAT "SixFour.Spec.V21Pyramid" pyramid field in the
--   @((bin*3+ch)*levels+value)@ layout that 'poolSpatial' consumes — a stack of per-@(bin,channel)@
--   value 'Density' slices. The object 'lawScaleEquivariant' is stated on.
type DensityField = [Int]

-- | A WARP @φ@: a per-VALUE point-map of length @levels@, where @φ !! x@ is the target value bin of
--   source bin @x@ (the value-axis face of a "SixFour.Spec.TransportGroup" slot permutation). This — NOT
--   the rank-'SixFour.Spec.V21Transport.Disp' — is the committed carrier: a ρ-independent bin→bin map
--   whose pushforward is a genuine, mass-conserving, composable monoid action.
type Warp = [Int]

-- | The value alphabet size (REUSE "SixFour.Spec.V21Field" @nLevels = 256@). Laws are parameterised on a
--   small @levels@ for exhaustive QuickCheck, exactly as "SixFour.Spec.V21Transport" does.
nLevels :: Int
nLevels = 256

-- Clamp a target into the legal value alphabet @[0, levels)@ (PILES out-of-gamut mass on the boundary
-- face, never drops it — the mass-conservation convention).
clampBin :: Int -> Int -> Int
clampBin levels v = max 0 (min (levels - 1) v)

-- Total value point-map lookup: out-of-length / out-of-range indices clamp into the alphabet.
warpAt :: Int -> Warp -> Int -> Int
warpAt levels w x
  | x >= 0 && x < length w = clampBin levels (w !! x)
  | otherwise              = clampBin levels x

-- | The IDENTITY warp @φ(x) = x@ (the monoid unit's realization; the I-combinator face). @φ#ρ = ρ@.
identityWarp :: Int -> Warp
identityWarp levels = [0 .. levels - 1]

-- | The REVERSAL warp @φ(x) = levels-1-x@: the only non-trivial L¹ ISOMETRY of the value axis
--   (@|φx-φy| = |x-y|@), hence 'admissible' with distortion @κ = 1@. The second element of the
--   value-axis isometry group @Z₂@.
reverseWarp :: Int -> Warp
reverseWarp levels = [levels - 1, levels - 2 .. 0]

-- | WARP COMPOSITION @φ_{g∘h} = φ_g ∘ φ_h@ (read @h@ then @g@): @composeWarp levels g h !! x = g(h(x))@.
--   Associative and NON-ABELIAN as an operation on the full warp set (function composition on a finite
--   set does not commute in general). Backs 'lawActionComposes'; the value-face analogue of
--   "SixFour.Spec.TransportGroup" 'SixFour.Spec.TransportGroup.tcomp'.
composeWarp :: Int -> Warp -> Warp -> Warp
composeWarp levels g h = [ warpAt levels g (warpAt levels h x) | x <- [0 .. levels - 1] ]

-- | THE ADMISSIBILITY GATE (no collapse / no discontinuity): the two-sided integer bi-Lipschitz bound of
--   "SixFour.Spec.DescriptorQuasiIsometry", RETARGETED to the value-warp @φ@ on the L¹ colour metric
--   @d(x,y)=|x-y|@. For every pair, @loNum·d(x,y) - loDen·slack ≤ loDen·d(φx,φy)@ (LOWER: distinct
--   colours never merge, @σ_min>0@) and @d(φx,φy)·hiDen ≤ hiNum·d(x,y)@ (UPPER: a 1-LSB step cannot jump
--   unboundedly). K-like collapsing operators FAIL this gate; L¹ isometries pass with @κ=1@.
admissible :: Int -> Warp -> Bool
admissible levels w =
  and [ loNum * dq - loDen * slack <= loDen * dc && dc * hiDen <= hiNum * dq
      | x <- [0 .. levels - 1], y <- [0 .. levels - 1]
      , let dq = abs (x - y)
            dc = abs (warpAt levels w x - warpAt levels w y) ]

-- | THE ONLY GENUINELY NEW PRIMITIVE — deterministically manufacture a gene's value warp @φ_g@ from its
--   @gpPayload@. PURE-SPEC-WALL standin: it ranges over the exact-arithmetic 'admissible' set (the value
--   isometry group @{identityWarp, reverseWarp}@), selected by the payload — the floor/zero payload gives
--   'identityWarp', an odd-parity payload the 'reverseWarp'. ρ-INDEPENDENT (takes only the alphabet size),
--   so a gene is a fixed object and the monoid-action framing holds. The real 21-word @θ_up → colour-index@
--   map is the MLX-MODEL seam behind this standin; @shape@ is the manifold the payload decodes under.
warpOf :: Int -> PredictorShape -> GenePreimage -> Warp
warpOf levels _shape g
  | all (== 0) (gpPayload g) = identityWarp levels
  | even (sum (gpPayload g)) = identityWarp levels
  | otherwise                = reverseWarp levels

-- | THE MONOID UNIT — the FLOOR gene (empty/zero @θ@ payload, no parents; the origin of
--   "SixFour.Spec.GeneSimilarity"'s floor metric). @warpOf levels shape idGene = identityWarp levels@, so
--   @idGene·ρ = ρ@. The I-combinator realized on the density.
idGene :: GenePreimage
idGene = GenePreimage [] []

-- | THE ACTION AS A PUSHFORWARD — push a density forward along a value warp by the explicit PREIMAGE-SUM
--   @(φ#ρ)[y] = Σ_{x: φ(x)=y} ρ[x]@. Because every source bin is delivered to exactly ONE (clamped)
--   target, total mass is conserved EXACTLY in ℤ ('lawGeneMassConserved'), and the map is functorial in
--   @φ@ ('lawActionComposes') and linear in @ρ@ (the engine of 'lawScaleEquivariant').
pushDensity :: Int -> Warp -> Density -> Density
pushDensity levels w rho =
  [ sum [ c | (x, c) <- indexed, warpAt levels w x == y ] | y <- [0 .. levels - 1] ]
  where indexed = zip [0 ..] rho

-- | THE GENE ACTION @g·ρ@ = 'pushDensity' along @φ_g@. Mass-conserving and single-target by construction.
act :: Int -> PredictorShape -> GenePreimage -> Density -> Density
act levels shape g rho = pushDensity levels (warpOf levels shape g) rho

-- | THE SPATIAL-CUBE ACTION — apply the gene's warp to the value axis of EVERY @(bin,channel)@ slice of a
--   flat pyramid 'DensityField' (each contiguous @levels@-chunk). Since the warp is ρ-independent and
--   'pushDensity' is linear, this commutes with 'poolSpatial' ('lawScaleEquivariant'): a gene MEANS THE
--   SAME at 16/32/64.
actField :: Int -> PredictorShape -> GenePreimage -> DensityField -> DensityField
actField levels shape g = concatMap (pushDensity levels (warpOf levels shape g)) . chunksOf levels

-- Split a flat field into its per-@(bin,channel)@ value-histogram slices.
chunksOf :: Int -> [Int] -> [[Int]]
chunksOf _ [] = []
chunksOf n xs = take n xs : chunksOf n (drop n xs)

-- | THE CONSERVED FUNCTIONAL @K@ — colour-density mass @Σρ@ = the DC read by
--   "SixFour.Spec.CombinatorExactSequence"'s coarse-forgetting surjection. REUSE
--   "SixFour.Spec.V21Transport" 'SixFour.Spec.V21Transport.mass'. This is the quantity every gene
--   preserves; it is NOT "SixFour.Spec.GeneRecombination"'s economic mass.
dcOf :: Density -> Int
dcOf = mass

-- | EXPRESSED ENERGY — the L¹ mass of "invented detail above the floor" (bin @0@), i.e. @Σ_{x≥1} ρ[x]@,
--   REUSING "SixFour.Spec.GeneSimilarity"'s energy notion. Invariant under a floor-fixing permutation
--   warp and bounded by 'dcOf' under any 'admissible' warp ('lawExpressedEnergyBounded').
expressedEnergy :: Density -> Int
expressedEnergy = sum . drop 1

-- | DISPLACEMENT-INTERPOLATION RECOMBINATION — the child warp is the per-bin (blend @½@) MEAN of the two
--   parents' value maps, @φ_c(x) = ⌊(φ_a(x)+φ_b(x))/2⌋@ (the 1-D W₂ geodesic midpoint, the value-face of
--   "SixFour.Spec.V21Transport" 'SixFour.Spec.V21Transport.barycenter'). Stays a valid single-target warp
--   ('lawRecombinationClosed'), UNLIKE the shipped "SixFour.Spec.GeneRecombination" @θ@-lerp whose action
--   is a mass-splitting coupling, not a pushforward: recombination is resolved HERE at the warp level.
recombineWarp :: Int -> Warp -> Warp -> Warp
recombineWarp levels a b =
  [ clampBin levels ((warpAt levels a x + warpAt levels b x) `div` 2) | x <- [0 .. levels - 1] ]

-- ─────────────────────────────────────────────────────────────────────────────
-- Laws (predicates; QuickCheck'd in @Properties.GeneDensity@). Densities are built
-- from a raw int seed cycled into small non-negative counts of length exactly
-- @levels@, the same "coerce raw generators into legal payloads" discipline as
-- "SixFour.Spec.V21Transport" / "SixFour.Spec.V21Pyramid".
-- ─────────────────────────────────────────────────────────────────────────────

-- Coerce a raw seed into a legal length-@levels@ count density (small non-negative).
mkDensity :: Int -> [Int] -> Density
mkDensity levels seed = take levels (map (\x -> abs x `mod` 5) seed ++ repeat 0)

-- Coerce a raw seed into a gene (its payload drives 'warpOf' identity/reversal branch).
mkGene :: [Int] -> GenePreimage
mkGene payload = GenePreimage payload []

-- | THE DEFINING LAW — @Σ(g·ρ) = Σρ@: a gene conserves total colour-density mass EXACTLY. The
--   pushforward re-buckets a finite integer multiset (out-of-gamut mass PILES on the boundary, never
--   drops), so the augmentation is invariant. The ℤ roof over "SixFour.Spec.V21Pyramid"
--   'SixFour.Spec.V21Pyramid.lawMassConserved'.
lawGeneMassConserved :: Int -> [Int] -> [Int] -> Bool
lawGeneMassConserved lraw payload seed =
  let levels = 1 + abs lraw `mod` 16
      rho    = mkDensity levels seed
      g      = mkGene payload
  in dcOf (act levels defaultShape g rho) == dcOf rho

-- | THE UP-TO-WARP QUALIFIER — the action factors through a deterministic point map: @act = pushDensity@
--   along @φ_g@, and each source bin is delivered to a SINGLE target (Monge, not a mass-splitting
--   Kantorovich plan). Single-target is witnessed by @φ_g@ being a length-@levels@ function of the value.
lawActionIsPushforward :: Int -> [Int] -> [Int] -> Bool
lawActionIsPushforward lraw payload seed =
  let levels = 1 + abs lraw `mod` 16
      rho    = mkDensity levels seed
      g      = mkGene payload
      w      = warpOf levels defaultShape g
  in act levels defaultShape g rho == pushDensity levels w rho
     && length w == levels                                  -- total point map on the value axis
     && all (\x -> warpAt levels w x >= 0 && warpAt levels w x < levels) [0 .. levels - 1]

-- | MONOID-ACTION ASSOCIATIVITY — the induced density action is FUNCTORIAL in the warp:
--   @act g (act h ρ) = pushDensity ρ (composeWarp g h)@, and 'composeWarp' is genuinely NON-ABELIAN as an
--   operation (witnessed by a swap pair). Lifts "SixFour.Spec.TransportGroup" chaining and
--   "SixFour.Spec.CombinatorExactSequence" S-composition to the density.
lawActionComposes :: Int -> [Int] -> [Int] -> [Int] -> Bool
lawActionComposes lraw pg ph seed =
  let levels = 1 + abs lraw `mod` 16
      rho    = mkDensity levels seed
      wg     = warpOf levels defaultShape (mkGene pg)
      wh     = warpOf levels defaultShape (mkGene ph)
      functorial =
        pushDensity levels wg (pushDensity levels wh rho)
          == pushDensity levels (composeWarp levels wg wh) rho
      -- non-abelian witness on general warps (adjacent-transposition pair)
      a = [1, 0, 2]; b = [0, 2, 1]
      nonAbelian = composeWarp 3 a b /= composeWarp 3 b a
  in functorial && nonAbelian

-- | THE MONOID UNIT — @warpOf idGene = identityWarp@ and hence @idGene·ρ = ρ@ (the I-combinator, work 0).
lawIdentityGeneIsIdentityWarp :: Int -> [Int] -> Bool
lawIdentityGeneIsIdentityWarp lraw seed =
  let levels = 1 + abs lraw `mod` 16
      rho    = mkDensity levels seed
  in warpOf levels defaultShape idGene == identityWarp levels
     && act levels defaultShape idGene rho == rho

-- | NO-COLLAPSE / QUASI-ISOMETRY — the warp a gene manufactures PASSES the 'admissible' gate: it is a
--   two-sided bi-Lipschitz map of the colour L¹ metric (distinct colours never merge, a 1-LSB step never
--   jumps unboundedly). The exact-arithmetic standin lands in the value isometry group (@κ=1@). Also pins
--   that 'reverseWarp' is admissible while the collapsing constant map is NOT.
lawWarpBiLipschitz :: Int -> [Int] -> Bool
lawWarpBiLipschitz lraw payload =
  let levels = 2 + abs lraw `mod` 15
      g      = mkGene payload
  in admissible levels (warpOf levels defaultShape g)
     && admissible levels (reverseWarp levels)
     && not (admissible levels (replicate levels 0))        -- the collapsing K-like map fails the gate

-- | SCALE-EQUIVARIANCE — warp-then-pool equals pool-then-warp, so a gene means the same at 16/32/64.
--   Follows from 'pushDensity' being LINEAR in @ρ@ and 'poolSpatial' being a block-SUM on the spatial
--   axis (the value axis, where @φ@ acts, is untouched). Composes with "SixFour.Spec.V21Pyramid"
--   'SixFour.Spec.V21Pyramid.lawPyramidTransitive'.
lawScaleEquivariant :: Int -> Int -> Int -> [Int] -> Bool
lawScaleEquivariant lraw sraw fraw seed =
  let levels = 1 + abs lraw `mod` 6
      f      = 2 + abs fraw `mod` 3
      cs     = 1 + abs sraw `mod` 3
      side   = cs * f
      fine   = mkField levels side seed
      g      = mkGene (1 : seed)                              -- payload drives the warp branch
  in poolSpatial levels side f (actField levels defaultShape g fine)
       == actField levels defaultShape g (poolSpatial levels side f fine)

-- Build a legal flat pyramid field of dims @side×side×3×levels@ (reused discipline from V21Pyramid).
mkField :: Int -> Side -> [Int] -> [Int]
mkField levels side seed =
  let n = side * side * 3 * levels
      s = if null seed then [0] else map (\x -> abs x `mod` 5) seed
  in take n (cycle s)

-- | RECOMBINATION IS CLOSED — the displacement-interpolation child is again a valid gene-warp: its action
--   conserves mass and it is a single-target pushforward (every child target lands in @[0,levels)@). Closure
--   under crossover at the WARP level, resolving the tension with "SixFour.Spec.GeneRecombination"'s
--   θ-lerp child (whose action is a coupling, not a pushforward).
lawRecombinationClosed :: Int -> [Int] -> [Int] -> [Int] -> Bool
lawRecombinationClosed lraw pa pb seed =
  let levels = 1 + abs lraw `mod` 16
      rho    = mkDensity levels seed
      wa     = warpOf levels defaultShape (mkGene pa)
      wb     = warpOf levels defaultShape (mkGene pb)
      child  = recombineWarp levels wa wb
  in dcOf (pushDensity levels child rho) == dcOf rho
     && length child == levels
     && all (\y -> y >= 0 && y < levels) child

-- | THE GENE COMMUTES WITH @K@ — @K∘act = K@, i.e. the coarse DC (here @dcOf = Σρ@, the density-level
--   realization of "SixFour.Spec.CombinatorExactSequence"'s coarse-forgetting @K@) is invariant under the
--   action. Makes "mass" PRECISELY the DC: a gene redistributes detail among value bins while the total
--   read by @K@ is untouched. (Identical content to 'lawGeneMassConserved', stated as the cross-law that
--   pins WHICH functional is conserved.)
lawWarpCommutesWithK :: Int -> [Int] -> [Int] -> Bool
lawWarpCommutesWithK lraw payload seed =
  let levels = 1 + abs lraw `mod` 16
      rho    = mkDensity levels seed
      g      = mkGene payload
  in dcOf (act levels defaultShape g rho) == dcOf rho

-- | EXPRESSED-ENERGY BRIDGE — the L¹ "invented detail above the floor" is INVARIANT under a floor-fixing
--   permutation warp (it only relabels non-floor bins, @Σ@ over them preserved) and BOUNDED by total mass
--   'dcOf' under any 'admissible' warp. Ties density-mass to "SixFour.Spec.GeneSimilarity"'s energy
--   functional.
lawExpressedEnergyBounded :: Int -> [Int] -> Bool
lawExpressedEnergyBounded lraw seed =
  let levels = 3 + abs lraw `mod` 13
      rho    = mkDensity levels seed
      -- a floor-fixing permutation: swap the two non-floor bins 1 and 2, fix the rest
      swap12 = [ if x == 1 then 2 else if x == 2 then 1 else x | x <- [0 .. levels - 1] ]
      invariant = expressedEnergy (pushDensity levels swap12 rho) == expressedEnergy rho
      bounded   = expressedEnergy (pushDensity levels (reverseWarp levels) rho) <= dcOf rho
  in invariant && bounded

-- The shipped predictor manifold the payload decodes under (7 bands × 3 features = 21 words).
defaultShape :: PredictorShape
defaultShape = PredictorShape 7

{- |
Module      : SixFour.Spec.GeneDensity3D
Description : THE 3-D ROOF over "SixFour.Spec.GeneDensity" — a gene is a JOINT mass-preserving pushforward on the coupled RGB colour density @ρ@ over the centred integer cube @{0..L-1}³@, strictly extending the 1-D per-value axis to the whole colour cube. The exact-arithmetic admissible (mass-preserving, no-collapse, @κ=1@ L¹ isometry) joint warps are EXACTLY the hyperoctahedral group @B3@ (order 48 = signed permutations of the R,G,B axes = @(Z₂)³⋊S3@): the @S3@ axis-permutation face REUSES "SixFour.Spec.OpponentDerivation" @swapRG@/@cycleRGB@, the @(Z₂)³@ per-axis-sign face REUSES "SixFour.Spec.GeneDensity" 'SixFour.Spec.GeneDensity.reverseWarp'. "SixFour.Spec.GeneDensity"'s marginal warps embed as the NORMAL product subgroup @(Z₂)³@ (@π=id@) via 'marginalToJoint', and the quotient @S3@ is the irreducible channel-coupling. The 120° hue rotation 'hueRotate' is the @C3@ axis 3-cycle (@= cycleRGB@ lifted, @Φ(r,g,b)=(b,r,g)@), which fixes the achromatic grey diagonal yet is provably NOT any product-of-marginals — the witness OUTSIDE the marginal subgroup that proves @GeneDensity ⊊ GeneDensity3D@.

== THE CROWN (strict inclusion)

'lawHueRotationIsChannelCoupled' + 'lawHueRotationNotMarginal' are the crown pair. The C3 hue is 'admissible3' + mass-preserving and fixes the grey diagonal @(v,v,v)@, YET for the density @ρ@ = unit masses at @(0,0,1)@ and @(0,1,0)@ (both @R=0@), @hueRotate#ρ@ raises the R-axis marginal support from 1 to 2. Any product map @Φ = φ_R×φ_G×φ_B@ satisfies @marginal_R(Φ#ρ) = φ_R#(marginal_R ρ)@, and a function pushforward can MERGE but never SPLIT a marginal's support — so no product-of-marginals can equal @hueRotate#ρ@. This turns "SixFour.Spec.GeneDensity"'s flagged boundary (a marginal warp cannot express channel-coupled hue rotations) into a positive law.

== ADMISSIBILITY IS THE EXACT L¹-CUBE ISOMETRY GATE

'admissible3' is the two-sided integer bi-Lipschitz gate of "SixFour.Spec.DescriptorQuasiIsometry" retargeted to the L¹ CUBE metric @d(x,y)=‖x−y‖₁@, specialised to the EXACT-isometry constants @loNum\/loDen = hiNum\/hiDen = 1@ (i.e. @d(Φx,Φy) == d(x,y)@ for every pair, @κ=1@). This exact specialisation — NOT the loose DQI band whose @hiNum=18@ was tuned for the 1-D axis — is what makes @B3@ EXACTLY the passing set (order 48): every @B3@ element passes as an isometry, the collapsing constant map fails, and at @L=2@ filtering all @8! = 40320@ cube bijections yields exactly 48 ('lawWarpBiLipschitz3'). The isometry-converse (integer isometry ⇒ signed permutation) is exhaustive only at @L=2@; at @L≥3@ the forward direction @B3 ⊆ isometries@ is checked and the converse rests on the discrete-geometry theorem.

== TWO 'MASS' NOTIONS (do not overload)

'dcOf3' is COLOUR-DENSITY mass @Σρ@ over the 3-D histogram = photon count = the DC read by "SixFour.Spec.CombinatorExactSequence"'s coarse-forgetting ('lawWarpCommutesWithK3'). It REUSES "SixFour.Spec.V21Transport" 'SixFour.Spec.V21Transport.mass' and stays strictly distinct from "SixFour.Spec.GeneRecombination"'s economic/ledger mass. 'warpOf3' is the MLX-MODEL seam (@θ_up → B3 element@): the PURE-SPEC-WALL standin ranges over @B3@ only, exactly as "SixFour.Spec.GeneDensity" 'SixFour.Spec.GeneDensity.warpOf' ranges over @{identity, reversal}@. @Density3@ is @L³@ cells; laws hold at small @L@ (2\/3\/4), the shipped @L=256@ carrier stays the marginal per-axis form with the joint @B3@ structure living at the gene-selection level. Pure-spec, exact @Integer@, reusing "SixFour.Spec.GeneDensity" \/ "SixFour.Spec.V21Transport" \/ "SixFour.Spec.V21Pyramid" \/ "SixFour.Spec.GeneHash".
-}
-- COMPARTMENT: PURE-SPEC-WALL | tag:none
module SixFour.Spec.GeneDensity3D
  ( -- * The joint colour density and its B3 warp carrier
    Density3
  , DensityField3
  , SignedPerm(..)
  , Warp3
  , nLevels3
    -- * The B3 warp algebra
  , identityWarp3
  , hueRotate
  , applyB3
  , composeWarp3
  , invertB3
  , marginalToJoint
  , admissible3
    -- * The action of a gene on the joint density
  , warpOf3
  , pushDensity3
  , act3
  , actField3
  , dcOf3
  , expressedEnergy3
  , recombine3
    -- * Laws
  , lawGeneMassConserved3
  , lawActionIsPushforward3
  , lawActionComposes3
  , lawIdentityGeneIsIdentityWarp3
  , lawWarpBiLipschitz3
  , lawScaleEquivariant3
  , lawRecombinationClosed3
  , lawWarpCommutesWithK3
  , lawExpressedEnergyBounded3
  , lawHueRotationIsChannelCoupled
  , lawHueRotationNotMarginal
  , lawMarginalEmbedsInJoint
  ) where

import qualified Data.Map.Strict as M
import Data.List (sort, permutations, nub)

import SixFour.Spec.GeneDensity (Warp, identityWarp, reverseWarp, idGene, nLevels)
import SixFour.Spec.V21Transport (mass)
import SixFour.Spec.V21Pyramid (Side, Factor, poolSpatial)
import SixFour.Spec.DetailPredictor (PredictorShape(..))
import SixFour.Spec.GeneHash (GenePreimage(..), gpPayload)

-- | The JOINT colour density: a flat length-@L³@ integer COUNT histogram over the centred cube
--   @{0..L-1}³@ in lexicographic layout index @(r*L + g)*L + b@. The 3-D roof over
--   "SixFour.Spec.GeneDensity" 'SixFour.Spec.GeneDensity.Density'; REUSES "SixFour.Spec.V21Transport"
--   'SixFour.Spec.V21Transport.Hist' verbatim (still just @[Int]@), so 'dcOf3' is 'mass' with no new
--   mass type.
type Density3 = [Int]

-- | The spatial-pyramid face: a flat @side×side×3×L³@ stack of per-bin joint 'Density3' cubes in the
--   @((bin*3 + ch)*L³ + cell)@ layout that "SixFour.Spec.V21Pyramid" 'poolSpatial' consumes (the 3
--   channels are carried inertly, exactly as "SixFour.Spec.GeneDensity"
--   'SixFour.Spec.GeneDensity.actField' reuses 'poolSpatial'). 'lawScaleEquivariant3' is stated on it.
type DensityField3 = [Int]

-- | A @B3@ element — the joint warp's representation (NOT a law). @spPerm@ is an @S3@ permutation of
--   @[0,1,2]@ (built from "SixFour.Spec.OpponentDerivation" @swapRG@\/@cycleRGB@ as generators),
--   @spSigns@ ∈ @{+1,-1}³@ is the per-axis reflection sign (each @-1@ = "SixFour.Spec.GeneDensity"
--   'SixFour.Spec.GeneDensity.reverseWarp' on that axis). Order 48 = @|(Z₂)³⋊S3|@.
data SignedPerm = SignedPerm
  { spPerm  :: [Int]   -- ^ the @S3@ axis permutation of @[0,1,2]@ (the channel-coupling face)
  , spSigns :: [Int]   -- ^ the per-axis reflection signs ∈ @{+1,-1}³@ (the @(Z₂)³@ marginal face)
  } deriving (Eq, Show)

-- | The committed JOINT point-map carrier @Φ:{0..L-1}³→{0..L-1}³@, @Φ(x)_j = ref(s_j, x_{π(j)})@; the
--   coupled-cube generalisation of "SixFour.Spec.GeneDensity" 'SixFour.Spec.GeneDensity.Warp'.
type Warp3 = SignedPerm

-- | The value alphabet size per axis (REUSE "SixFour.Spec.GeneDensity" 'SixFour.Spec.GeneDensity.nLevels'
--   @= 256@); laws parameterise on a small @L@ for exhaustive QuickCheck since the cube is @L³@.
nLevels3 :: Int
nLevels3 = nLevels

-- Read coordinate @j@ (0=R,1=G,2=B) of a cube point.
coord :: Int -> (Int, Int, Int) -> Int
coord 0 (r, _, _) = r
coord 1 (_, g, _) = g
coord _ (_, _, b) = b

-- Reflect a value under a per-axis sign: @ref(+1,v)=v@, @ref(-1,v)=L-1-v@ (REUSE the reversal map).
ref :: Int -> Int -> Int -> Int
ref levels s v = if s == (-1) then levels - 1 - v else v

-- The @L³@ cube cells in lexicographic order (matches the 'Density3' layout).
cubeCells :: Int -> [(Int, Int, Int)]
cubeCells levels = [ (r, g, b) | r <- [0 .. levels - 1], g <- [0 .. levels - 1], b <- [0 .. levels - 1] ]

-- Flat lexicographic index of a cube cell.
idxCell :: Int -> (Int, Int, Int) -> Int
idxCell levels (r, g, b) = (r * levels + g) * levels + b

-- L¹ (Manhattan) distance on the cube — the metric 'admissible3' preserves.
l1cube :: (Int, Int, Int) -> (Int, Int, Int) -> Int
l1cube (a, b, c) (d, e, f) = abs (a - d) + abs (b - e) + abs (c - f)

-- Each element paired with the elements strictly after it (the @i < j@ unordered pairs).
zipTails :: [a] -> [(a, [a])]
zipTails []       = []
zipTails (x : xs) = (x, xs) : zipTails xs

-- The 6 elements of @S3@ (all permutations of @[0,1,2]@), in a fixed deterministic order.
allS3 :: [[Int]]
allS3 = [ [0,1,2], [0,2,1], [1,0,2], [1,2,0], [2,0,1], [2,1,0] ]

-- The 8 per-axis sign combinations @{+1,-1}³@.
allSignCombos :: [[Int]]
allSignCombos = [ [a, b, c] | a <- [-1, 1], b <- [-1, 1], c <- [-1, 1] ]

-- The full hyperoctahedral group @B3@ (all 48 signed permutations).
allB3 :: [Warp3]
allB3 = [ SignedPerm p s | p <- allS3, s <- allSignCombos ]

-- | THE MONOID UNIT — @SignedPerm [0,1,2] [1,1,1]@; @Φ = id@ on the cube, @Φ#ρ = ρ@. The I-combinator
--   face and @π=id@ sign-identity element of @B3@. Mirrors "SixFour.Spec.GeneDensity"
--   'SixFour.Spec.GeneDensity.identityWarp'.
identityWarp3 :: Warp3
identityWarp3 = SignedPerm [0, 1, 2] [1, 1, 1]

-- | THE JOINT-ONLY PRIMITIVE — the 120° hue rotation = the @C3@ axis 3-cycle @SignedPerm [2,0,1]
--   [1,1,1]@, @Φ(r,g,b)=(b,r,g)@ (this is exactly "SixFour.Spec.OpponentDerivation" @cycleRGB@ lifted
--   to the cube). Order 3, fixes the grey diagonal @(v,v,v)@. The bit-exact joint-cube analogue of
--   "SixFour.Spec.ChromaRotation" @rotateQuarter@'s @C4@ about the grey axis; lives in an @S3@ coset
--   OUTSIDE the marginal @(Z₂)³@ subgroup.
hueRotate :: Warp3
hueRotate = SignedPerm [2, 0, 1] [1, 1, 1]

-- | THE POINT ACTION of a @B3@ element: @applyB3 L (SignedPerm π s) x@ has coordinate @j@ given by
--   @ref(s_j, x_{π(j)})@, @ref(+1,v)=v@, @ref(-1,v)=L-1-v@ (the @-1@ axis map is the value-axis
--   reversal). Induces the joint point-map @Φ@ the density action pushes along.
applyB3 :: Int -> Warp3 -> (Int, Int, Int) -> (Int, Int, Int)
applyB3 levels (SignedPerm p s) x =
  ( ref levels (s !! 0) (coord (p !! 0) x)
  , ref levels (s !! 1) (coord (p !! 1) x)
  , ref levels (s !! 2) (coord (p !! 2) x) )

-- The induced cube point-map: image of every cell (in 'cubeCells' order).
inducedMap :: Int -> Warp3 -> [(Int, Int, Int)]
inducedMap levels w = map (applyB3 levels w) (cubeCells levels)

-- | THE JOINT ACTION AS PUSHFORWARD — the explicit preimage-sum @(Φ#ρ)[c] = Σ_{x: Φx = c} ρ[x]@ over
--   the @L³@ cube. Every @B3@ element is a cube bijection, so mass is conserved EXACTLY in ℤ (zero
--   drop), linear in @ρ@, functorial in @Φ@. 3-D roof over "SixFour.Spec.GeneDensity"
--   'SixFour.Spec.GeneDensity.pushDensity'; its axis-marginal restricts to the 1-D pushforward.
pushDensity3 :: Int -> Warp3 -> Density3 -> Density3
pushDensity3 levels w rho =
  let cells = cubeCells levels
      m = M.fromListWith (+) [ (idxCell levels (applyB3 levels w x), c) | (x, c) <- zip cells rho ]
  in [ M.findWithDefault 0 j m | j <- [0 .. levels * levels * levels - 1] ]

-- | THE ONLY GENUINELY NEW PRIMITIVE — deterministically manufacture a gene's joint warp @Φ_g@ from
--   @gpPayload@. PURE-SPEC-WALL standin ranging over the exact @B3@ admissible group: the zero payload
--   gives 'identityWarp3', otherwise @|Σpayload| mod 6@ selects the @S3@ permutation and three payload
--   parities select the per-axis signs. ρ-INDEPENDENT. The real @θ_up → B3-element@ realization is the
--   MLX-MODEL seam behind it. Mirrors "SixFour.Spec.GeneDensity" 'SixFour.Spec.GeneDensity.warpOf'.
warpOf3 :: Int -> PredictorShape -> GenePreimage -> Warp3
warpOf3 _levels _shape g
  | all (== 0) (gpPayload g) = identityWarp3
  | otherwise =
      let p    = gpPayload g
          perm = allS3 !! (abs (sum p) `mod` 6)
          bit k = if odd (sum [ p !! i | i <- [0 .. length p - 1], i `mod` 3 == k ]) then (-1) else 1
      in SignedPerm perm [bit 0, bit 1, bit 2]

-- | THE GENE ACTION @g·ρ@ = 'pushDensity3' along 'warpOf3'. Mass-conserving and single-target (Monge)
--   by construction. Mirrors "SixFour.Spec.GeneDensity" 'SixFour.Spec.GeneDensity.act'.
act3 :: Int -> PredictorShape -> GenePreimage -> Density3 -> Density3
act3 levels shape g = pushDensity3 levels (warpOf3 levels shape g)

-- | THE SPATIAL-CUBE ACTION — apply the gene's joint warp to every per-bin @L³@ cube chunk of a flat
--   pyramid 'DensityField3'. ρ-independent + linear ⇒ commutes with "SixFour.Spec.V21Pyramid"
--   'poolSpatial' ('lawScaleEquivariant3'): a hue gene means the same at 16\/32\/64. 3-D analogue of
--   "SixFour.Spec.GeneDensity" 'SixFour.Spec.GeneDensity.actField'.
actField3 :: Int -> PredictorShape -> GenePreimage -> DensityField3 -> DensityField3
actField3 levels shape g = concatMap (pushDensity3 levels (warpOf3 levels shape g)) . chunksOf (levels * levels * levels)

-- Split a flat field into its per-bin @L³@ cube slices.
chunksOf :: Int -> [Int] -> [[Int]]
chunksOf _ [] = []
chunksOf n xs = take n xs : chunksOf n (drop n xs)

-- | @B3@ COMPOSITION @Φ_g ∘ Φ_h@ (read @h@ then @g@) via the semidirect product @(Z₂)³⋊S3@: the signs
--   twist by the permutation (@s_j = sg_j · sh_{πg(j)}@, @π = πh ∘ πg@). Associative and genuinely
--   NON-ABELIAN (a per-axis reflection and the hue @C3@ fail to commute). Lifts
--   "SixFour.Spec.GeneDensity" 'SixFour.Spec.GeneDensity.composeWarp' and "SixFour.Spec.TransportGroup"
--   @tcomp@ to the coupled cube.
composeWarp3 :: Warp3 -> Warp3 -> Warp3
composeWarp3 (SignedPerm pg sg) (SignedPerm ph sh) =
  SignedPerm [ ph !! (pg !! j)               | j <- [0 .. 2] ]
             [ (sg !! j) * (sh !! (pg !! j))  | j <- [0 .. 2] ]

-- | THE GROUP INVERSE in @B3@ (the semidirect-product inverse), so the admissible warps form a GROUP
--   not just a monoid. Lifts "SixFour.Spec.TransportGroup" @tinv@ from the value axis to the 3 coupled
--   axes: @Φ⁻¹(y)_k = ref(s_{π⁻¹(k)}, y_{π⁻¹(k)})@.
invertB3 :: Warp3 -> Warp3
invertB3 (SignedPerm p s) =
  let pinv = [ head [ j | j <- [0 .. 2], p !! j == k ] | k <- [0 .. 2] ]
  in SignedPerm pinv [ s !! (pinv !! k) | k <- [0 .. 2] ]

-- | THE EMBEDDING HOMOMORPHISM — three per-axis "SixFour.Spec.GeneDensity" warps (each ∈
--   @{identityWarp, reverseWarp}@) map to @SignedPerm [0,1,2] s@ (@π = id@) with @s_j = -1@ iff axis
--   @j@ is a reversal. Image = the NORMAL product subgroup @(Z₂)³@ (order 8), realising
--   @GeneDensity ⊂ GeneDensity3D@ as the axis-diagonal\/product subgroup.
marginalToJoint :: (Warp, Warp, Warp) -> Warp3
marginalToJoint (wR, wG, wB) = SignedPerm [0, 1, 2] [ signOf wR, signOf wG, signOf wB ]
  where signOf w = if not (null w) && head w == 0 then 1 else (-1)

-- Exact L¹-cube isometry test on a general cube point-map (image list in 'cubeCells' order): every pair
-- keeps its distance, @d(Φx,Φy) == d(x,y)@ (κ=1). This is the DQI gate specialised to the exact-isometry
-- constants @loNum\/loDen = hiNum\/hiDen = 1@ — NOT the loose band — so its passing set is EXACTLY the
-- isometry group.
isIsometricCubeMap :: Int -> [(Int, Int, Int)] -> Bool
isIsometricCubeMap levels img =
  let cs = zip cells img
      cells = cubeCells levels
  in and [ l1cube yi yj == l1cube xi xj
         | ((xi, yi), rest) <- zipTails cs
         , (xj, yj) <- rest ]

-- | THE JOINT ADMISSIBILITY GATE — the two-sided integer bi-Lipschitz bound of
--   "SixFour.Spec.DescriptorQuasiIsometry" retargeted to the L¹ CUBE metric @‖x−y‖₁@ and specialised to
--   the EXACT-isometry constants @loNum\/loDen = hiNum\/hiDen = 1@ (@d(Φx,Φy) == d(x,y)@, @κ=1@). Every
--   @B3@ element passes; the collapsing constant map FAILS; and @B3@ is EXACTLY the passing set (order
--   48, 'lawWarpBiLipschitz3'). Generalises "SixFour.Spec.GeneDensity"
--   'SixFour.Spec.GeneDensity.admissible' from the value-axis @Z₂@ to the cube.
admissible3 :: Int -> Warp3 -> Bool
admissible3 levels w = isIsometricCubeMap levels (inducedMap levels w)

-- | THE CONSERVED FUNCTIONAL @K@ — colour-density mass @Σρ@ over the 3-D histogram = photon count = the
--   DC read by "SixFour.Spec.CombinatorExactSequence"'s coarse-forgetting. REUSE
--   "SixFour.Spec.V21Transport" 'SixFour.Spec.V21Transport.mass'. Distinct from
--   "SixFour.Spec.GeneRecombination"'s economic mass. Mirrors "SixFour.Spec.GeneDensity"
--   'SixFour.Spec.GeneDensity.dcOf'.
dcOf3 :: Density3 -> Int
dcOf3 = mass

-- | EXPRESSED ENERGY — the L¹ mass of invented detail above the floor cell @(0,0,0)@ (flat index 0),
--   i.e. @Σ@ over all non-floor cube cells. Invariant under a floor-fixing @B3@ element, bounded by
--   'dcOf3' under any 'admissible3' warp ('lawExpressedEnergyBounded3'). Mirrors
--   "SixFour.Spec.GeneDensity" 'SixFour.Spec.GeneDensity.expressedEnergy'.
expressedEnergy3 :: Density3 -> Int
expressedEnergy3 = sum . drop 1

-- | DISPLACEMENT-INTERPOLATION RECOMBINATION — the child @B3@ element, defined on @(perm,signs)@ so
--   closure in the group is GUARANTEED (unlike a naive per-cell midpoint @⌊(Φa+Φb)/2⌋@ which can leave
--   @B3@): each sign is the parents' agreed sign or the rest sign @+1@ on disagreement, and the
--   permutation is the shared parent permutation or the identity @[0,1,2]@ (the @S3@ rest point) on
--   disagreement. Stays a valid single-target mass-conserving warp ('lawRecombinationClosed3'). 3-D
--   analogue of "SixFour.Spec.GeneDensity" 'SixFour.Spec.GeneDensity.recombineWarp'.
recombine3 :: Int -> Warp3 -> Warp3 -> Warp3
recombine3 _levels (SignedPerm pa sa) (SignedPerm pb sb) =
  SignedPerm (if pa == pb then pa else [0, 1, 2])
             [ if sa !! j == sb !! j then sa !! j else 1 | j <- [0 .. 2] ]

-- ─────────────────────────────────────────────────────────────────────────────
-- Laws (predicates; QuickCheck'd in @Properties.GeneDensity3D@). Joint densities
-- are built from a raw int seed cycled into small non-negative counts of length
-- exactly @L³@, the same "coerce raw generators into legal payloads" discipline as
-- "SixFour.Spec.GeneDensity". @L@ ranges over @{2,3,4}@ so the @L³@ cube stays
-- exhaustively checkable.
-- ─────────────────────────────────────────────────────────────────────────────

-- Small cube side @L@ ∈ @{2,3,4}@ from a raw seed.
smallL :: Int -> Int
smallL lraw = 2 + abs lraw `mod` 3

-- Coerce a raw seed into a legal length-@L³@ joint density (small non-negative counts).
mkDensity3 :: Int -> [Int] -> Density3
mkDensity3 levels seed = take (levels * levels * levels) (map (\x -> abs x `mod` 5) seed ++ repeat 0)

-- Coerce a raw payload into a gene (its payload drives 'warpOf3').
mkGene3 :: [Int] -> GenePreimage
mkGene3 payload = GenePreimage payload []

-- The shipped predictor manifold the payload decodes under (7 bands × 3 features = 21 words).
defaultShape :: PredictorShape
defaultShape = PredictorShape 7

-- A per-axis reflection witness (reflect the R axis) — the non-abelian partner of 'hueRotate'.
reflR :: Warp3
reflR = SignedPerm [0, 1, 2] [-1, 1, 1]

-- A floor-fixing @B3@ element: the pure @swapRG@ permutation (all signs @+1@) fixes @(0,0,0)@ and only
-- relabels non-floor cells.
floorFixingB3 :: Warp3
floorFixingB3 = SignedPerm [1, 0, 2] [1, 1, 1]

-- The collapsing constant cube map (every cell → the floor cell): mass-conserving but NOT an isometry.
constCubeMap :: Int -> [(Int, Int, Int)]
constCubeMap levels = replicate (levels * levels * levels) (0, 0, 0)

-- All @|cube|!@ cube bijections (permutations of the cells) — used only at @L=2@ (8! = 40320).
allCubeBijections :: Int -> [[(Int, Int, Int)]]
allCubeBijections levels = permutations (cubeCells levels)

-- The number of admissible (exact-isometry) cube bijections at @L=2@ — a top-level CAF so the 40320-way
-- filter is computed at most once. The discrete-geometry fact: this equals @|B3| = 48@.
b3CountAtL2 :: Int
b3CountAtL2 = length (filter (isIsometricCubeMap 2) (allCubeBijections 2))

-- Whether a warp's induced cube map is a bijection (hits every cell exactly once).
isBijectiveOnCube :: Int -> Warp3 -> Bool
isBijectiveOnCube levels w = sort (inducedMap levels w) == cubeCells levels

-- Whether a candidate warp is a genuine @B3@ element (a signed permutation of the 3 axes).
isB3Element :: Warp3 -> Bool
isB3Element w = w `elem` allB3

-- A joint density with unit masses at the given cells (0 elsewhere).
unitMasses :: Int -> [(Int, Int, Int)] -> Density3
unitMasses levels cs = [ if c `elem` cs then 1 else 0 | c <- cubeCells levels ]

-- All axis functions @{0..L-1} → {0..L-1}@ (there are @L^L@ of them).
allAxisMaps :: Int -> [[Int]]
allAxisMaps levels = sequence (replicate levels [0 .. levels - 1])

-- The product-of-marginals pushforward @Φ = φ_R×φ_G×φ_B@ applied to a joint density (preimage-sum).
productPush :: Int -> [Int] -> [Int] -> [Int] -> Density3 -> Density3
productPush levels fr fg fb rho =
  let cells = cubeCells levels
      ap (r, g, b) = (idxAxis fr r, idxAxis fg g, idxAxis fb b)
      idxAxis f v = if v >= 0 && v < length f then f !! v else v
      m = M.fromListWith (+) [ (idxCell levels (ap x), c) | (x, c) <- zip cells rho ]
  in [ M.findWithDefault 0 j m | j <- [0 .. levels * levels * levels - 1] ]

-- The independent per-axis action of three "SixFour.Spec.GeneDensity" warps — equals 'productPush'.
perAxisMarginalAct :: Int -> Warp -> Warp -> Warp -> Density3 -> Density3
perAxisMarginalAct = productPush

-- Support size (number of non-zero bins) of a joint density's marginal onto the given axis.
marginalSupportSize :: Int -> Int -> Density3 -> Int
marginalSupportSize ax levels rho =
  length [ () | v <- [0 .. levels - 1]
              , sum [ rho !! idxCell levels cell | cell <- cubeCells levels, coord ax cell == v ] > 0 ]

-- | THE DEFINING LAW (3-D roof over "SixFour.Spec.GeneDensity"
--   'SixFour.Spec.GeneDensity.lawGeneMassConserved') — every @B3@ gene conserves total colour-density
--   mass EXACTLY: each element is a cube bijection, so 'pushDensity3' re-buckets the finite integer
--   multiset with zero drop.
lawGeneMassConserved3 :: Int -> [Int] -> [Int] -> Bool
lawGeneMassConserved3 lraw payload seed =
  let levels = smallL lraw
      rho    = mkDensity3 levels seed
      g      = mkGene3 payload
  in dcOf3 (act3 levels defaultShape g rho) == dcOf3 rho

-- | THE MONGE QUALIFIER — 'act3' factors through the deterministic joint point-map (@act3 = pushDensity3@
--   along 'warpOf3'), and every source cell is delivered to a SINGLE target (a bijection, not a
--   mass-splitting Kantorovich plan). Lifts "SixFour.Spec.GeneDensity"
--   'SixFour.Spec.GeneDensity.lawActionIsPushforward'.
lawActionIsPushforward3 :: Int -> [Int] -> [Int] -> Bool
lawActionIsPushforward3 lraw payload seed =
  let levels = smallL lraw
      rho    = mkDensity3 levels seed
      g      = mkGene3 payload
      w      = warpOf3 levels defaultShape g
  in act3 levels defaultShape g rho == pushDensity3 levels w rho
     && isBijectiveOnCube levels w

-- | MONOID\/GROUP-ACTION FUNCTORIALITY — @Φ_g#(Φ_h#ρ) = (composeWarp3 g h)#ρ@, and 'composeWarp3' is
--   genuinely NON-ABELIAN (a per-axis reflection and the hue @C3@ fail to commute). 3-D lift of
--   "SixFour.Spec.GeneDensity" 'SixFour.Spec.GeneDensity.lawActionComposes'.
lawActionComposes3 :: Int -> [Int] -> [Int] -> [Int] -> Bool
lawActionComposes3 lraw pg ph seed =
  let levels = smallL lraw
      rho    = mkDensity3 levels seed
      wg     = warpOf3 levels defaultShape (mkGene3 pg)
      wh     = warpOf3 levels defaultShape (mkGene3 ph)
      functorial =
        pushDensity3 levels wg (pushDensity3 levels wh rho)
          == pushDensity3 levels (composeWarp3 wg wh) rho
      nonAbelian = composeWarp3 reflR hueRotate /= composeWarp3 hueRotate reflR
  in functorial && nonAbelian

-- | THE MONOID UNIT — @warpOf3 idGene = identityWarp3@ and hence @idGene·ρ = ρ@ (the I-combinator on
--   the cube, work 0). Lifts "SixFour.Spec.GeneDensity"
--   'SixFour.Spec.GeneDensity.lawIdentityGeneIsIdentityWarp'.
lawIdentityGeneIsIdentityWarp3 :: Int -> [Int] -> Bool
lawIdentityGeneIsIdentityWarp3 lraw seed =
  let levels = smallL lraw
      rho    = mkDensity3 levels seed
  in warpOf3 levels defaultShape idGene == identityWarp3
     && act3 levels defaultShape idGene rho == rho

-- | NO-COLLAPSE\/QUASI-ISOMETRY + @B3@ IS EXACTLY ADMISSIBLE — the warp a gene manufactures passes
--   'admissible3' (an exact @κ=1@ L¹-cube isometry); 'hueRotate' passes; the collapsing constant map
--   FAILS; and @B3@ (order 48) is EXACTLY the admissible set (exhaustively verified at @L=2@ by
--   filtering all @8! = 40320@ cube bijections to exactly 48). Generalises "SixFour.Spec.GeneDensity"
--   'SixFour.Spec.GeneDensity.lawWarpBiLipschitz'.
lawWarpBiLipschitz3 :: Int -> [Int] -> Bool
lawWarpBiLipschitz3 lraw payload =
  let levels = smallL lraw
      g      = mkGene3 payload
  in admissible3 levels (warpOf3 levels defaultShape g)
     && admissible3 levels hueRotate
     && not (isIsometricCubeMap levels (constCubeMap levels))
     && (levels > 2 || b3CountAtL2 == 48)

-- | SCALE-EQUIVARIANCE — a joint warp acts only on the value axes, so warp-then-pool = pool-then-warp:
--   a hue gene MEANS THE SAME at 16\/32\/64. Follows from 'pushDensity3' linear in @ρ@ and
--   "SixFour.Spec.V21Pyramid" 'poolSpatial' a spatial block-sum. Mirrors "SixFour.Spec.GeneDensity"
--   'SixFour.Spec.GeneDensity.lawScaleEquivariant'.
lawScaleEquivariant3 :: Int -> Int -> Int -> [Int] -> Bool
lawScaleEquivariant3 lraw sraw fraw seed =
  let levels = 2 + abs lraw `mod` 2          -- {2,3} keeps the pooled L³ field small
      lc     = levels * levels * levels
      f      = 2 + abs fraw `mod` 2          -- {2,3}
      cs     = 1 + abs sraw `mod` 2          -- {1,2}
      side   = cs * f
      fine   = mkField3 levels side seed
      g      = mkGene3 (1 : seed)
  in poolSpatial lc side f (actField3 levels defaultShape g fine)
       == actField3 levels defaultShape g (poolSpatial lc side f fine)

-- Build a legal flat pyramid field of dims @side×side×3×L³@ (reused discipline from V21Pyramid).
mkField3 :: Int -> Side -> [Int] -> [Int]
mkField3 levels side seed =
  let n = side * side * 3 * (levels * levels * levels)
      s = if null seed then [0] else map (\x -> abs x `mod` 5) seed
  in take n (cycle s)

-- | RECOMBINATION IS CLOSED — the displacement-interpolation child 'recombine3' is again a valid @B3@
--   gene-warp: it stays in @B3@, its action conserves mass, and it is a single-target pushforward. Lifts
--   "SixFour.Spec.GeneDensity" 'SixFour.Spec.GeneDensity.lawRecombinationClosed'.
lawRecombinationClosed3 :: Int -> [Int] -> [Int] -> [Int] -> Bool
lawRecombinationClosed3 lraw pa pb seed =
  let levels = smallL lraw
      rho    = mkDensity3 levels seed
      wa     = warpOf3 levels defaultShape (mkGene3 pa)
      wb     = warpOf3 levels defaultShape (mkGene3 pb)
      child  = recombine3 levels wa wb
  in isB3Element child && dcOf3 (pushDensity3 levels child rho) == dcOf3 rho

-- | THE GENE COMMUTES WITH @K@ — @K∘act3 = K@: the coarse DC 'dcOf3' (photon-count mass, the
--   "SixFour.Spec.CombinatorExactSequence" coarse-forgetting on the joint cube) is invariant under the
--   action. Pins WHICH functional is conserved. Lifts "SixFour.Spec.GeneDensity"
--   'SixFour.Spec.GeneDensity.lawWarpCommutesWithK'.
lawWarpCommutesWithK3 :: Int -> [Int] -> [Int] -> Bool
lawWarpCommutesWithK3 lraw payload seed =
  let levels = smallL lraw
      rho    = mkDensity3 levels seed
      g      = mkGene3 payload
  in dcOf3 (act3 levels defaultShape g rho) == dcOf3 rho

-- | EXPRESSED-ENERGY BRIDGE — 'expressedEnergy3' (invented detail above the floor cell) is INVARIANT
--   under a floor-fixing @B3@ element (it only relabels non-floor cells) and BOUNDED by 'dcOf3' under
--   any 'admissible3' warp. Lifts "SixFour.Spec.GeneDensity"
--   'SixFour.Spec.GeneDensity.lawExpressedEnergyBounded' to the cube.
lawExpressedEnergyBounded3 :: Int -> [Int] -> Bool
lawExpressedEnergyBounded3 lraw seed =
  let levels    = smallL lraw
      rho       = mkDensity3 levels seed
      invariant = expressedEnergy3 (pushDensity3 levels floorFixingB3 rho) == expressedEnergy3 rho
      bounded   = expressedEnergy3 (pushDensity3 levels hueRotate rho) <= dcOf3 rho
  in invariant && bounded

-- | CROWN PAIR (1\/2) — the hue @C3@ is 'admissible3' + mass-preserving and fixes the achromatic
--   diagonal @(v,v,v)↦(v,v,v)@ (the joint-cube analogue of "SixFour.Spec.ChromaRotation"
--   @lawRotateFixesGray@), YET it is channel-coupled: two points differing only in G — @(0,0,0)@ and
--   @(0,1,0)@ — map to points differing in B (@(0,0,0)@ and @(0,0,1)@). Turns
--   "SixFour.Spec.GeneDensity"'s flagged boundary into a positive law.
lawHueRotationIsChannelCoupled :: Int -> [Int] -> Bool
lawHueRotationIsChannelCoupled lraw seed =
  let levels = smallL lraw
      rho    = mkDensity3 levels seed
  in admissible3 levels hueRotate
     && dcOf3 (pushDensity3 levels hueRotate rho) == dcOf3 rho
     && applyB3 2 hueRotate (0, 1, 0) == (0, 0, 1)
     && applyB3 2 hueRotate (0, 0, 0) == (0, 0, 0)
     && all (\v -> applyB3 levels hueRotate (v, v, v) == (v, v, v)) [0 .. levels - 1]

-- | ★ THE CROWN (2\/2) — for @ρ@ = unit masses at @(0,0,1)@ and @(0,1,0)@ (both @R=0@), for ALL
--   marginal triples @(φ_R,φ_G,φ_B)@, @hueRotate#ρ ≠ (φ_R×φ_G×φ_B)#ρ@. Certificate: @hueRotate#ρ@ has
--   R-marginal support size 2 while a product map satisfies @marginal_R(Φ#ρ) = φ_R#(marginal_R ρ)@,
--   whose support (≤ source support = 1) can MERGE but never SPLIT. Proves @GeneDensity ⊊ GeneDensity3D@
--   strictly; exhausted at @L=2@ over all @(L^L)³@ product maps.
lawHueRotationNotMarginal :: Bool
lawHueRotationNotMarginal =
  let rho     = unitMasses 2 [(0, 0, 1), (0, 1, 0)]
      target  = pushDensity3 2 hueRotate rho
      maps    = allAxisMaps 2
      triples = [ (fr, fg, fb) | fr <- maps, fg <- maps, fb <- maps ]
      noProductMatches = all (\(fr, fg, fb) -> target /= productPush 2 fr fg fb rho) triples
      supportGrows     = marginalSupportSize 0 2 target > marginalSupportSize 0 2 rho
  in noProductMatches && supportGrows

-- | @GeneDensity ⊂ GeneDensity3D@ — 'marginalToJoint' embeds "SixFour.Spec.GeneDensity"'s per-axis
--   warps as the PRODUCT subgroup of @B3@ (@π=id@, signs free = @(Z₂)³@, order 8): the independent
--   per-axis action equals the @π=id@ @B3@ action. Algebraically @(Z₂)³@ is NORMAL in @B3@ with quotient
--   @B3/(Z₂)³ ≅ S3@ (order 6). Checkable at @L=2\/3\/4@.
lawMarginalEmbedsInJoint :: Int -> Int -> Int -> Int -> [Int] -> Bool
lawMarginalEmbedsInJoint lraw sa sb sc seed =
  let levels = smallL lraw
      pick n = if odd (abs n) then reverseWarp levels else identityWarp levels
      wR = pick sa; wG = pick sb; wB = pick sc
      rho = mkDensity3 levels seed
      embedEq =
        perAxisMarginalAct levels wR wG wB rho
          == pushDensity3 levels (marginalToJoint (wR, wG, wB)) rho
      hsub = nub [ marginalToJoint (mw x, mw y, mw z) | x <- bs, y <- bs, z <- bs ]
      mw t  = if t then reverseWarp levels else identityWarp levels
      bs    = [False, True]
      conj g h = composeWarp3 (composeWarp3 g h) (invertB3 g)
      normal = all (\g -> all (\h -> conj g h `elem` hsub) hsub) allB3
      qOrder = length allB3 `div` length hsub
  in embedEq && normal && qOrder == 6

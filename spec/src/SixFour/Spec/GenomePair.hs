{- |
Module      : SixFour.Spec.GenomePair
Description : KEYSTONE — two distinct, genome-orthogonal, σ-valid candidate
              displacements (δ_A, δ_B) proposed from a capture's base genome g0.

The A/B screen (the pivoted product, @docs/SIXFOUR-GENOME-AB-PIVOT-WORKFLOW.md@)
shows the user the deterministic 64³ reference plus TWO competing 16³ candidate
looks; the user picks one. This module pins the math of that /pair/: it must be
(1) genuinely DISTINCT (a real choice, not two near-duplicates), (2) ORTHOGONAL
(so A and B explore independent directions of the look space), and (3) VALID (each
keeps the σ-pair genome well-formed). All three are delivered by ONE construction —
band-disjoint support in generator space.

== The three guarantees, and why each is free or exact

[Validity is FREE]
  A candidate is a 'SixFour.Spec.LeafOverride.SigmaOverride' — a per-generator Q16
  delta. ANY override keeps the palette σ-fixed by construction (the σ-partner is
  @σ(generator)@ regardless of the nudge), so 'lawPairValidSigma' just reuses
  'SixFour.Spec.LeafOverride.lawSigmaOverridePreservesSymmetry' verbatim. There is
  no validity constraint to satisfy and nothing to reject-resample.

[Orthogonality is EXACT, by disjoint support — never Gram–Schmidt]
  δ_A nudges generator-index set @S_A@; δ_B nudges the DISJOINT set @S_B@. Because
  the two displacements are nonzero on disjoint generators, every term of the inner
  product 'genomeInner' has a zero factor, so @genomeInner bandWeights δ_A δ_B == 0@
  EXACTLY on the Q16 lattice — 'lawPairOrthogonalExact'. This is an algebraic
  decomposition of ONE signal into disjoint coordinates; it needs no Gram–Schmidt
  and no ε. (A GS-orthogonalised δ_B snapped back to the integer step lattice would
  generically /lose/ the exact zero; disjoint support cannot.)

[Distinctness is structural]
  Disjoint nonempty supports differ as vectors, and each candidate's W-norm exceeds
  'minGenomeStep' (see the arithmetic on 'minGenomeStep') — 'lawPairDistinct'.

== Which space orthogonality lives in (the decision-ledger keystone)

'genomeInner' is the weighted dot on the GENERATOR-space displacement vectors — the
same 384-D space ('maxGenerators' generators × 3 OKLab channels) that the user/θ
actually edits via 'SixFour.Spec.LeafOverride'. It is NOT defined on a
reconstructed-leaf vector: the generator space and the leaf space are related by the
non-orthogonal, per-level-scaled integer Haar of 'SixFour.Spec.PairTreeFixed', so
orthogonality in one is not orthogonality in the other. Metric and move basis
therefore share one space — this is the ruling that makes 'lawPairOrthogonalExact'
type-correct (see @SIXFOUR-GENOME-AB-PIVOT-RESEARCH-AMENDMENT.md@, decision Q1).

NOTE — "sub-band axes" are PALETTE generators, not spatial RGBT. A generator index
is a leaf of the /palette/ Haar tree; it has NO correspondence to the spatial RGBT
LL\/LH\/HL\/HH lift (palette Haar has one detail family per level, the spatial Haar
has three). The genome is the palette factor; R\/RGBT spatial lift is the index
factor; they are decoupled. The "spatial-vs-temporal" idea CubeGIF used for A\/B is
demoted here to a PARTITION HEURISTIC that only chooses /which/ disjoint generator
bands seed A vs B — it can never produce overlapping support
('lawSelectorRidesOnDisjoint').

== Cold start (the live gap this module closes)

WHICH generators rank highest is θ-dependent once the personal genome is trained
('SixFour.Spec.PersonalGenome'), but on day 1 (fewer than ~8 logged Compares) θ is
untrained. 'sampleOrthogonalPair' therefore falls back to 'captureMeasureRanking'
— a pure, θ-independent ranking by each generator's Q16 colour energy — so the A/B
screen has REAL, valid, orthogonal candidates from the very first capture
('lawColdStartStillOrthogonal'). This is the deterministic integer analogue of
KataGo's "ship a fixed warm prior, never @Float.random@".

OPEN DECISION (amendment, conflict ⚑2): the cold-start ranking source — per-generator
colour energy (implemented here) vs a fixed founder band-partition preset — is an
owner call. The implementation is structured so only 'captureMeasureRanking' changes
if that ruling differs; the orthogonality\/validity guarantees are independent of it.

GHC-boot-only. Laws are exported predicates, to be QuickCheck'd in
@Properties.GenomePair@ (test wiring pending — this module lands at build step 2).
-}
module SixFour.Spec.GenomePair
  ( -- * Types
    GenomeDisplacement
  , GenomePair
  , BandWeights
  , SubBandSupport
  , Ranking
    -- * Golden-pinned constants
  , maxGenerators
  , pairBudget
  , stepQ16
  , bandWeights
  , minGenomeStep
    -- * The inner product
  , genomeInner
  , genomeNorm
  , support
  , generatorCount
    -- * Proposing the pair
  , captureMeasureRanking
  , sampleOrthogonalPair
    -- * Laws (to be QuickCheck'd in Properties.GenomePair)
  , lawWeightsPositiveDefinite
  , lawPairOrthogonalExact
  , lawPairDistinct
  , lawPairValidSigma
  , lawPairReversible
  , lawPairDeterministic
  , lawBandDisjoint
  , lawColdStartRankingDeterministic
  , lawColdStartStillOrthogonal
  , lawSelectorRidesOnDisjoint
  ) where

import Data.List (intersect, sortBy)
import Data.Ord  (comparing, Down(..))

import SixFour.Spec.PairTreeFixed  (OKLabI, HaarPaletteI, reconstructFixed, wellFormedI)
import SixFour.Spec.SigmaPairFixed (analyzePairedFixed, reconstructPairedFixed)
import SixFour.Spec.LeafOverride   (SigmaOverride, applySigmaOverride, lawSigmaOverridePreservesSymmetry)

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------

-- | A candidate look = a generator-space displacement, Q16, σ-locked. This is a
-- direct reuse of 'SixFour.Spec.LeafOverride.SigmaOverride' (a per-generator δ list);
-- entry @i@ is the Q16 OKLab nudge added to generator @c_i@, and the σ-partner follows
-- for free. The empty list is the no-op displacement.
type GenomeDisplacement = SigmaOverride

-- | The two competing candidates @(δ_A, δ_B)@ shown on the A/B screen.
type GenomePair = (GenomeDisplacement, GenomeDisplacement)

-- | Per-generator weights for 'genomeInner', ALL STRICTLY > 0 so the inner product is
-- positive-DEFINITE. The shipped weight is uniform unit ('bandWeights'); non-uniform
-- per-Haar-level weighting is a flagged future refinement, not a tunable.
type BandWeights = [Double]

-- | The set of generator indices a displacement actually touches (its nonzero support).
-- Disjointness of two supports is exactly what makes 'genomeInner' vanish.
type SubBandSupport = [Int]

-- | A score per generator index — higher means "more salient, prefer to nudge". Supplied
-- by the personal genome θ once trained ('SixFour.Spec.PersonalGenome'), and by the
-- θ-independent 'captureMeasureRanking' on cold start. A ranking shorter than the
-- generator count signals "not yet trained" and triggers the cold-start fallback.
type Ranking = [Double]

-- ---------------------------------------------------------------------------
-- Golden-pinned constants
-- ---------------------------------------------------------------------------

-- | The σ-pair genome has @maxGenerators@ = 128 generators (a depth-7 palette Haar
-- tree), i.e. @128 × 3@ = 384 DOF — the @SIGMA_PAIR_DOF@ the decoder emits.
maxGenerators :: Int
maxGenerators = 128

-- | How many generators each candidate nudges. A and B draw from the top
-- @2·pairBudget@ ranked generators, split into two disjoint @pairBudget@-sized bands,
-- so both candidates are strong (high-energy generators) yet provably non-overlapping.
pairBudget :: Int
pairBudget = 8

-- | The cold-start nudge magnitude per OKLab channel, Q16 (so @stepQ16 \/ 65536 ≈
-- 0.0156@ OKLab units — a visible but not garish look shift). Golden-pinned; the SIGN
-- per channel is set per generator by 'sampleOrthogonalPair', the magnitude is fixed so
-- orthogonality comes purely from disjoint support, never from the step direction.
stepQ16 :: Int
stepQ16 = 1024

-- | Uniform unit weights — the golden-pinned positive-definite choice (every weight is
-- exactly @1.0@, so the golden vector is trivial and cross-device-stable). 'genomeInner'
-- zips against this, so the infinite list simply supplies a @1.0@ per generator.
--
-- NOTE: a per-Haar-level weighting (down-weighting coarse DC generators) is a plausible
-- future refinement tied to amendment conflict ⚑2; it would replace this single
-- definition without touching the inner-product algebra or any orthogonality law.
bandWeights :: BandWeights
bandWeights = repeat 1.0

-- | The minimum W-norm a candidate must reach to count as a real choice (not noise).
--
-- Arithmetic: a candidate nudges at least one generator by @(±stepQ16, ±stepQ16,
-- ±stepQ16)@, contributing @3·stepQ16²@ to the squared norm, so its norm is at least
-- @sqrt 3 · stepQ16 ≈ 1774@. A full candidate nudges 'pairBudget' generators, giving
-- @sqrt (pairBudget·3) · stepQ16 ≈ 5016@. The threshold @1024@ sits safely below even
-- the single-generator floor, so 'lawPairDistinct' holds whenever both bands are
-- non-empty (i.e. @generatorCount ≥ 2@).
minGenomeStep :: Double
minGenomeStep = 1024.0

-- ---------------------------------------------------------------------------
-- The inner product
-- ---------------------------------------------------------------------------

-- | The W-weighted inner product on two generator-space displacements, @⟨δ_A, δ_B⟩_W =
-- Σ_i w_i · (l_i l_i' + a_i a_i' + b_i b_i')@. Shorter displacements are zero-padded so
-- the result is well-defined for any two. With disjoint support every term has a zero
-- factor and the sum is exactly @0.0@ (the basis of 'lawPairOrthogonalExact').
genomeInner :: BandWeights -> GenomeDisplacement -> GenomeDisplacement -> Double
genomeInner ws da db =
  let n      = max (length da) (length db)
      pad xs = take n (xs ++ repeat (0, 0, 0))
      dot3 (l, a, b) (l', a', b') = l * l' + a * a' + b * b'
  in sum (zipWith3 (\w x y -> w * fromIntegral (dot3 x y)) ws (pad da) (pad db))

-- | @genomeNorm w δ = sqrt (genomeInner w δ δ)@ — the W-length of a single candidate.
genomeNorm :: BandWeights -> GenomeDisplacement -> Double
genomeNorm w d = sqrt (genomeInner w d d)

-- | The generator indices a displacement touches (nonzero entries). The construction
-- guarantees @support δ_A ∩ support δ_B = ∅@ ('lawBandDisjoint').
support :: GenomeDisplacement -> SubBandSupport
support deltas = [ i | (i, c) <- zip [0 ..] deltas, c /= (0, 0, 0) ]

-- | The number of σ-pair generators in a base genome — the even leaves of its Haar
-- tree, i.e. @length (reconstructFixed g0)@ (= 'maxGenerators' for a depth-7 tree).
generatorCount :: HaarPaletteI -> Int
generatorCount = length . reconstructFixed

-- ---------------------------------------------------------------------------
-- Proposing the pair
-- ---------------------------------------------------------------------------

-- | The θ-independent cold-start ranking: score each generator by its Q16 colour energy
-- @l² + a² + b²@. Salient (high-chroma\/high-lightness) generators rank first, so day-1
-- candidates nudge the colours that most define the look. Pure function of @g0@ ⇒
-- identical cross-device ('lawColdStartRankingDeterministic').
captureMeasureRanking :: HaarPaletteI -> Ranking
captureMeasureRanking g0 =
  [ fromIntegral (l * l + a * a + b * b) | (l, a, b) <- reconstructFixed g0 ]

-- | Generator indices sorted by score (descending), ties broken by ascending index — a
-- deterministic total order, so the partition below is reproducible. Rankings shorter
-- than the generator count are zero-padded.
rankedIndices :: Ranking -> Int -> [Int]
rankedIndices scores g =
  map fst (sortBy (comparing (\(i, s) -> (Down s, i))) (take g (zip [0 ..] (scores ++ repeat 0))))

-- | Split the top @2·pairBudget@ ranked generators into two DISJOINT bands by parity of
-- rank (rank 0,2,4… → S_A; rank 1,3,5… → S_B). Each index appears in exactly one band,
-- so the bands are disjoint by construction ('lawSelectorRidesOnDisjoint') while both
-- receive high-ranked generators. (Parity interleave is the demoted "one semantic axis →
-- two distinct candidates" idea from CubeGIF, riding on top of the exact guarantee.)
chooseDisjointBands :: Ranking -> Int -> ([Int], [Int])
chooseDisjointBands scores g =
  let ranked = take (min (2 * pairBudget) g) (rankedIndices scores g)
      tagged = zip [0 :: Int ..] ranked
  in ( [ i | (k, i) <- tagged, even k ]
     , [ i | (k, i) <- tagged, odd k ] )

-- | The cold-start nudge for generator @i@: a fixed-magnitude step whose SIGN follows
-- the generator's own lean (push each channel further from neutral), so the candidate is
-- a meaningful, capture-dependent perturbation. The magnitude is independent of @i@, so
-- orthogonality is delivered purely by disjoint support — the direction never matters
-- for ⟂. Out-of-range indices act as the identity.
stepFor :: HaarPaletteI -> Int -> OKLabI
stepFor g0 i =
  let gens = reconstructFixed g0
  in if i < 0 || i >= length gens
       then (0, 0, 0)
       else let (l, a, b) = gens !! i
                s v = if v >= 0 then stepQ16 else negate stepQ16
            in (s l, s a, s b)

-- | Build the override that nudges exactly the generators in @idxs@ (and no others).
overrideOn :: HaarPaletteI -> [Int] -> SigmaOverride
overrideOn g0 idxs =
  [ if i `elem` idxs then stepFor g0 i else (0, 0, 0) | i <- [0 .. generatorCount g0 - 1] ]

-- | Propose the competing pair @(δ_A, δ_B)@ from base genome @g0@ and a 'Ranking'.
-- δ_A nudges band @S_A@, δ_B the disjoint band @S_B@, so the pair is orthogonal, valid,
-- and distinct by construction. If @ranking@ is shorter than the generator count
-- (θ untrained), it falls back to the deterministic 'captureMeasureRanking', so the
-- result is a pure function of @g0@ and any supplied ranking ('lawPairDeterministic').
sampleOrthogonalPair :: HaarPaletteI -> Ranking -> GenomePair
sampleOrthogonalPair g0 ranking =
  let g        = generatorCount g0
      rank     = if length ranking >= g then ranking else captureMeasureRanking g0
      (sA, sB) = chooseDisjointBands rank g
  in (overrideOn g0 sA, overrideOn g0 sB)

-- ---------------------------------------------------------------------------
-- Laws (predicates; to be exercised by Properties.GenomePair)
-- ---------------------------------------------------------------------------

-- | All @w > 0@ across the genome width ⇒ 'genomeInner' is a true (positive-definite)
-- inner product. Holds because 'bandWeights' is uniform @1.0@.
lawWeightsPositiveDefinite :: Bool
lawWeightsPositiveDefinite = all (> 0) (take maxGenerators bandWeights)

-- | The headline: @genomeInner bandWeights δ_A δ_B == 0@ EXACTLY (band-disjoint support,
-- exact Q16) — A and B are a genuinely orthogonal choice, for any base genome\/ranking.
lawPairOrthogonalExact :: HaarPaletteI -> Ranking -> Bool
lawPairOrthogonalExact g0 r =
  not (wellFormedI g0) ||
  let (da, db) = sampleOrthogonalPair g0 r
  in genomeInner bandWeights da db == 0

-- | Each candidate has W-norm @≥ minGenomeStep@ AND @δ_A /= δ_B@ — both are real,
-- distinct looks (requires @generatorCount g0 ≥ 2@ so both bands are non-empty).
lawPairDistinct :: HaarPaletteI -> Ranking -> Bool
lawPairDistinct g0 r =
  not (wellFormedI g0) || generatorCount g0 < 2 ||
  let (da, db) = sampleOrthogonalPair g0 r
  in genomeNorm bandWeights da >= minGenomeStep
     && genomeNorm bandWeights db >= minGenomeStep
     && da /= db

-- | Each candidate keeps the palette σ-fixed — validity is unconditional. Reuses
-- 'SixFour.Spec.LeafOverride.lawSigmaOverridePreservesSymmetry' on both displacements.
lawPairValidSigma :: HaarPaletteI -> Ranking -> Bool
lawPairValidSigma g0 r =
  not (wellFormedI g0) ||
  let (da, db) = sampleOrthogonalPair g0 r
  in lawSigmaOverridePreservesSymmetry da g0
     && lawSigmaOverridePreservesSymmetry db g0

-- | Each candidate palette round-trips the σ-pair transform exactly:
-- @reconstructPairedFixed (analyzePairedFixed pal) == pal@. True because the candidate
-- is already σ-symmetric (it is a 'SigmaOverride'), and the forward analyser is the exact
-- projection onto the σ-pair subspace — identity on σ-symmetric palettes. Stated PER
-- candidate; it is not coupled to orthogonality.
lawPairReversible :: HaarPaletteI -> Ranking -> Bool
lawPairReversible g0 r =
  not (wellFormedI g0) ||
  let (da, db) = sampleOrthogonalPair g0 r
      ok d     = let pal = applySigmaOverride d g0
                 in reconstructPairedFixed (analyzePairedFixed pal) == pal
  in ok da && ok db

-- | 'sampleOrthogonalPair' is a pure integer function ⇒ identical @(δ_A, δ_B)@
-- cross-device. Tautological in pure Haskell by design; pinned as a regression guard so
-- a future refactor cannot smuggle in @Float.random@\/non-associative float without this
-- intent being recorded. The real guarantee is the integer-only construction.
lawPairDeterministic :: HaarPaletteI -> Ranking -> Bool
lawPairDeterministic g0 r = sampleOrthogonalPair g0 r == sampleOrthogonalPair g0 r

-- | @support δ_A ∩ support δ_B = ∅@ — the construction that makes orthogonality exact.
lawBandDisjoint :: HaarPaletteI -> Ranking -> Bool
lawBandDisjoint g0 r =
  not (wellFormedI g0) ||
  let (da, db) = sampleOrthogonalPair g0 r
  in null (support da `intersect` support db)

-- | The cold-start ranking is a deterministic, full-width function of @g0@ alone (no θ),
-- so day-1 candidates are identical cross-device.
lawColdStartRankingDeterministic :: HaarPaletteI -> Bool
lawColdStartRankingDeterministic g0 =
  captureMeasureRanking g0 == captureMeasureRanking g0
  && length (captureMeasureRanking g0) == generatorCount g0

-- | Even with NO training (an empty ranking forces the cold-start path), the proposed
-- pair is band-disjoint and exactly orthogonal — the "NN proposes two" promise holds
-- from the first capture, before any Compare.
lawColdStartStillOrthogonal :: HaarPaletteI -> Bool
lawColdStartStillOrthogonal g0 =
  not (wellFormedI g0) ||
  let (da, db) = sampleOrthogonalPair g0 []
  in null (support da `intersect` support db)
     && genomeInner bandWeights da db == 0

-- | The partition selector only assigns ALREADY-disjoint generator bands; it can never
-- produce overlapping support, for any ranking and width. This pins that the demoted
-- spatial-vs-temporal heuristic rides on top of the exact guarantee and cannot weaken it.
lawSelectorRidesOnDisjoint :: Ranking -> Int -> Bool
lawSelectorRidesOnDisjoint scores g =
  let (sA, sB) = chooseDisjointBands scores (max 0 g)
  in null (sA `intersect` sB)

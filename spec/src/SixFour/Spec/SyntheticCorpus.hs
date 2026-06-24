{- |
Module      : SixFour.Spec.SyntheticCorpus
Description : A SYNTHETIC corpus that proves the encode PIPELINE works and the SPEC GUARANTEES encoding across an entropy × Lab taxonomy. Realness is irrelevant (per the owner): the canonical clip MIX is a training-regiment choice deferred to later; here we test that EVERY entropy/Lab category encodes to a valid floor, and that the floor RESPONDS to both axes.

Clips are categorised by ENTROPY (Flat / Low / Mid / High — the detail-band energy) and by the
Lab AXIS the palette varies along (L / a / b / full Lab). For each category, the pipeline is
@synthOctants → liftOct → detailColumn → the three modality bands → clipLoad → corpusFloor@, all
pure-integer (byte-stable across hosts). The guarantee, not a magic number, is the deliverable:

  * 'lawEveryCategoryEncodes' — the SPEC GUARANTEES ENCODING: for EVERY entropy×Lab category, the
    clip's loads are finite non-negative bits AND @corpusFloorOf [clip]@ sums to exactly 512 (a
    valid waist partition). Totality across the whole taxonomy — the pipeline never fails to encode.
  * 'lawEntropyCategoriesSpanTheFloor' — the floor RESPONDS to entropy: a Flat clip has strictly
    less perceptual load than a High-entropy one (the detail axis is real, not constant).
  * 'lawLabAxesSpanThePaletteLoad' — the floor RESPONDS to colour: a full-Lab palette earns strictly
    more palette load than a greyscale (L-only) one (the chroma axis is real).

The pinned per-category INTEGERS (the goldens) are computed inside the tests from the frozen
'synthOctants'/'synthPalette' — never hand-typed — so a re-route is caught. The canonical corpus
mix (proportions) is intentionally NOT blessed here; that is the training-regiment decision.

GHC-boot-only; re-pins nothing. Laws QuickCheck'd in "Properties.SyntheticCorpus".
-}
-- COMPARTMENT: MLX-MODEL | tag:MacTag
module SixFour.Spec.SyntheticCorpus
  ( EntropyClass(..)
  , LabAxis(..)
  , ClipKind(..)
  , entropyClasses
  , labAxes
  , allCategories
  , synthOctants
  , synthPalette
  , synthClip
  , hfOct
  , lawEveryCategoryEncodes
  , lawEntropyCategoriesSpanTheFloor
  , lawEntropyTaxonomyIsMonotone
  , lawLabAxesSpanThePaletteLoad
  ) where

import SixFour.Spec.Color          (OKLab(..))
import SixFour.Spec.OctreeCell     (V8(..), liftOct, ocDetail)
import SixFour.Spec.DetailEntropy  (detailColumn)
import SixFour.Spec.EncoderCorpus  (Clip(..), clipLoad, corpusFloorOf)

-- | The entropy categories — the detail-band energy a clip carries.
data EntropyClass = Flat | LowEnt | MidEnt | HighEnt deriving (Eq, Show)

-- | The perceptual axis the palette varies along (the further L,a,b sub-categorisation).
data LabAxis = AxisL | AxisA | AxisB | AxisLab deriving (Eq, Show)

-- | One taxonomy cell: an entropy class × a Lab axis.
data ClipKind = ClipKind EntropyClass LabAxis deriving (Eq, Show)

entropyClasses :: [EntropyClass]
entropyClasses = [Flat, LowEnt, MidEnt, HighEnt]

labAxes :: [LabAxis]
labAxes = [AxisL, AxisA, AxisB, AxisLab]

-- | The full taxonomy: every entropy class × every Lab axis.
allCategories :: [ClipKind]
allCategories = [ ClipKind e a | e <- entropyClasses, a <- labAxes ]

-- | A high-frequency octant (max internal alternation) — pure integer, parameterised by @i@ so
-- the DETAIL band VARIES across octants (the per-octant @i@ is what carries entropy across the
-- corpus, not a fixed within-octant pattern).
hfOct :: Int -> V8 Int
hfOct i = V8 (g 37 199) (g 53 211) (g 71 223) (g 97 199) (g 113 211) (g 131 223) (g 17 199) (g 29 211)
  where g p q = (i * p) `mod` q

-- | A flat octant — zero detail.
flatOct :: V8 Int
flatOct = V8 0 0 0 0 0 0 0 0

-- | The synthetic octant list for an entropy class. Entropy is spanned by the COUNT of
-- detail-carrying (high-frequency) octants — Flat 0 / Low 4 / Mid 10 / High 16 of 16 — so the
-- detail-band entropy is genuinely MONOTONE across the classes (the rest are flat). The active
-- octants use the per-@i@ 'hfOct' so their detail bands differ across the corpus.
synthOctants :: EntropyClass -> [V8 Int]
synthOctants Flat    = replicate 16 flatOct
synthOctants LowEnt  = [ if i <= 4  then hfOct i else flatOct | i <- [1 .. 16] ]
synthOctants MidEnt  = [ if i <= 10 then hfOct i else flatOct | i <- [1 .. 16] ]
synthOctants HighEnt = [ hfOct i                              | i <- [1 .. 16] ]

-- | The synthetic palette for a Lab axis — the colour set varies along exactly that axis.
synthPalette :: LabAxis -> [(OKLab, Double)]
synthPalette AxisL   = [(OKLab 0 0 0, 1), (OKLab 80 0 0, 1)]
synthPalette AxisA   = [(OKLab 40 0 0, 1), (OKLab 40 70 0, 1)]
synthPalette AxisB   = [(OKLab 40 0 0, 1), (OKLab 40 0 70, 1)]
synthPalette AxisLab = [(OKLab 0 0 0, 1), (OKLab 80 60 40, 1), (OKLab 30 70 20, 1)]

-- | Build the EncoderCorpus 'Clip' for a taxonomy cell: the index band (detail band 0) and the
-- held perceptual band (detail band 6) come from the lifted synthetic octants; the palette from
-- the Lab axis. Never hand-typed — the bands are computed via the one reversible lift.
synthClip :: ClipKind -> Clip
synthClip (ClipKind ent axis) =
  let details = map (ocDetail . liftOct) (synthOctants ent)
  in Clip { clipIndexBand      = detailColumn 0 details
          , clipPalette        = synthPalette axis
          , clipPerceptualBand = detailColumn 6 details
          }

-- =============================================================================
-- Laws
-- =============================================================================

-- | THE SPEC GUARANTEES ENCODING: every entropy×Lab category encodes to finite non-negative bit
-- loads AND a valid 512-summing floor partition — totality across the whole taxonomy, no category
-- ever fails to encode.
lawEveryCategoryEncodes :: Bool
lawEveryCategoryEncodes =
  all ok allCategories
  where
    ok k = let (i, p, c) = clipLoad (synthClip k)
           in i >= 0 && p >= -1e-9 && c >= 0
              && not (isNaN i || isNaN p || isNaN c)
              && sum (corpusFloorOf [synthClip k]) == 512

-- | The floor RESPONDS to entropy: a Flat clip carries strictly less perceptual load than a
-- High-entropy one (same Lab axis), so the detail axis is real — a constant pipeline would fail.
lawEntropyCategoriesSpanTheFloor :: Bool
lawEntropyCategoriesSpanTheFloor =
  perc (ClipKind Flat AxisLab) < perc (ClipKind HighEnt AxisLab)
  where perc k = let (_, _, c) = clipLoad (synthClip k) in c

-- | The entropy taxonomy is MONOTONE: the perceptual load is non-decreasing
-- @Flat ≤ Low ≤ Mid ≤ High@ (same Lab axis), strictly increasing across the endpoints — so the
-- four classes genuinely span the detail-band entropy, not collapse to two.
lawEntropyTaxonomyIsMonotone :: Bool
lawEntropyTaxonomyIsMonotone =
  and (zipWith (<=) ps (tail ps)) && head ps < last ps
  where
    perc e = let (_, _, c) = clipLoad (synthClip (ClipKind e AxisLab)) in c
    ps     = map perc [Flat, LowEnt, MidEnt, HighEnt]

-- | The floor RESPONDS to colour: a full-Lab palette earns strictly more palette load than a
-- greyscale (L-only) one (same entropy), so the chroma sub-categorisation is real.
lawLabAxesSpanThePaletteLoad :: Bool
lawLabAxesSpanThePaletteLoad =
  pal (ClipKind HighEnt AxisLab) > pal (ClipKind HighEnt AxisL)
  where pal k = let (_, p, _) = clipLoad (synthClip k) in p

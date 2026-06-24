{- |
Module      : SixFour.Spec.EncoderCorpus
Description : The bridge from a CORPUS of clips to the earned encoder floor — the producer of the @[[Double]]@ corpus-mean loads that "SixFour.Spec.EncoderEntropyFloor" @corpusFloor@ consumes. Each clip's three modality bands (index / palette / perceptual) go through "SixFour.Spec.EncoderModalityLoad" to a load triple; the corpus aggregates them and Hamilton-apportions the 512 waist. This is the step that turns "form earned" into "numbers pinned" — once a REAL corpus exists, these laws pin the actual integers.

The same clips that size the encoder are the clips the masked-band data engine
("SixFour.Spec.JepaData") manufactures training records from — one corpus, measured and trained
through the one reversible lift. This module pins the SIZING half (the loads → floor); the
TRAINING half (the masked-band records) is JepaData over the same clips.

  * 'clipLoad' — a clip's @(index, palette, perceptual)@ load triple via @modalityLoads@.
  * 'corpusFloorOf' — @corpusFloor . corpusLoads@: the earned channel floor for a corpus.
  * 'lawCorpusFloorSumsTo512' — the corpus floor preserves the @lawFuseIsMidpoint@ waist.
  * 'lawColourfulCorpusEarnsMorePaletteFloor' (TEETH) — the floor is a REAL function of corpus
    content: a corpus of colourful clips earns a strictly larger palette floor than a greyscale
    corpus (index/perceptual bands held fixed). A constant/uniform floor would fail this — which is
    the whole point: the pinned numbers respond to the actual data, so a real corpus pins real numbers.

The clip SOURCE (the device-side data engine that yields representative clips from captures or
synthesis) is out of spec scope — these laws prove the MECHANISM responds to content, not the
provenance of the clips. The witnesses here are synthetic.

GHC-boot-only; re-pins nothing. Byte-exact path untouched. Laws QuickCheck'd in "Properties.EncoderCorpus".
-}
-- COMPARTMENT: MLX-MODEL | tag:MacTag
module SixFour.Spec.EncoderCorpus
  ( Clip(..)
  , clipLoad
  , corpusLoads
  , corpusFloorOf
  , lawCorpusFloorSumsTo512
  , lawColourfulCorpusEarnsMorePaletteFloor
  , lawEveryClipSizesTheFloor
  ) where

import SixFour.Spec.Color              (OKLab(..))
import SixFour.Spec.EncoderModalityLoad (modalityLoads)
import SixFour.Spec.EncoderEntropyFloor (corpusFloor)
import SixFour.Spec.HalfwayLatent      (vitDModel)

-- | One clip's three modality inputs — the bands a real reversible lift would expose from a
-- 64³ capture. (Synthetic in the witnesses here; the device data engine supplies the real ones.)
data Clip = Clip
  { clipIndexBand      :: [Int]            -- ^ the index detail band (discrete Shannon load)
  , clipPalette        :: [(OKLab, Double)]-- ^ the per-frame palette (ridged colour-rate load)
  , clipPerceptualBand :: [Int]            -- ^ the held perceptual detail band (conditional load)
  }

-- | A clip's @(index, palette, perceptual)@ load triple, on the one non-negative bit axis.
clipLoad :: Clip -> (Double, Double, Double)
clipLoad c = modalityLoads (clipIndexBand c) (clipPalette c) (clipPerceptualBand c)

-- | The corpus loads as the @[[Double]]@ rows @corpusFloor@ consumes.
corpusLoads :: [Clip] -> [[Double]]
corpusLoads = map (\c -> let (i, p, k) = clipLoad c in [i, p, k])

-- | The earned encoder floor for a corpus: aggregate the per-clip loads, then Hamilton-apportion 512.
corpusFloorOf :: [Clip] -> [Int]
corpusFloorOf = corpusFloor . corpusLoads

-- =============================================================================
-- Witnesses
-- =============================================================================

-- | Shared index/perceptual bands, so only the palette differs between the two corpora.
sharedBand :: [Int]
sharedBand = [0,1,1,2,0,3,1,0]

mkClip :: [(OKLab, Double)] -> Clip
mkClip pal = Clip sharedBand pal sharedBand

-- | Two colourful clips (palettes spread across all three OKLab axes).
colourfulCorpus :: [Clip]
colourfulCorpus = map mkClip
  [ [(OKLab 0 0 0, 1), (OKLab 80 60 40, 1), (OKLab 30 70 20, 1)]
  , [(OKLab 10 0 0, 1), (OKLab 70 50 60, 1), (OKLab 40 80 30, 1)] ]

-- | Two greyscale clips (a=b=0; palette varies only on L).
greyscaleCorpus :: [Clip]
greyscaleCorpus = map mkClip
  [ [(OKLab 0 0 0, 1), (OKLab 80 0 0, 1)]
  , [(OKLab 10 0 0, 1), (OKLab 60 0 0, 1)] ]

paletteFloor :: [Int] -> Int
paletteFloor [_, p, _] = p
paletteFloor _         = -1

-- =============================================================================
-- Laws
-- =============================================================================

-- | The corpus floor preserves the waist: it sums to exactly @vitDModel@ (so @lawFuseIsMidpoint@
-- holds at the corpus level, not just per clip).
lawCorpusFloorSumsTo512 :: Bool
lawCorpusFloorSumsTo512 =
     sum (corpusFloorOf colourfulCorpus) == vitDModel
  && sum (corpusFloorOf greyscaleCorpus) == vitDModel

-- | TEETH — the floor is a REAL function of corpus content: a colourful corpus earns a strictly
-- larger palette floor than a greyscale one (index/perceptual bands held fixed). A constant or
-- uniform floor would fail this, which is exactly why a real corpus will pin real numbers.
lawColourfulCorpusEarnsMorePaletteFloor :: Bool
lawColourfulCorpusEarnsMorePaletteFloor =
  paletteFloor (corpusFloorOf colourfulCorpus) > paletteFloor (corpusFloorOf greyscaleCorpus)

-- | Every clip in the corpus contributes a load row to the floor — no clip is silently dropped
-- from the sizing (so the floor reflects the whole corpus, not a sample). Teeth: a generator that
-- subsampled the corpus would break the length identity.
lawEveryClipSizesTheFloor :: Bool
lawEveryClipSizesTheFloor =
     length (corpusLoads colourfulCorpus) == length colourfulCorpus
  && all (\row -> length row == 3) (corpusLoads colourfulCorpus)

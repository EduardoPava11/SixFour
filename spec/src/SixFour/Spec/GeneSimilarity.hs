{- |
Module      : SixFour.Spec.GeneSimilarity
Description : Gene similarity as a PULLBACK pseudometric — a flat θ vector is never compared word-by-word; it is EXPRESSED on a pinned probe lattice (the same @predictDetail@ that runs on device, Q16 commit included) into a P6 cloud, and the proven @d6@ cloud distance is pulled back along that expression map. Flat comparison lies (gauge); expression does not.

The GeneAtlas needs "how similar are two genes?". The WRONG answer is a new
metric on the flat 21-word θ vector: parameters are a gauge-ridden chart, not
the object (the house has proved this shape twice — palettes compare only in
fused @buildPixels@ space, and the σ-genome is an S₂₅₆ ORBIT invariant, never a
slot vector). The RIGHT answer is a projection lift:

@
  θ (flat words)  ──express on the probe lattice──▶  [P6] cloud
                                                        │
  d_gene(θ₁,θ₂)  =  cloudDistance(express θ₁, express θ₂)   (pullback)
@

A pullback of a pseudometric along ANY map is a pseudometric — so
non-negativity, symmetry and the triangle inequality are INHERITED from
"SixFour.Spec.CrossEncoderDistance" 'cloudDistance' (itself inherited from
@d6@), not re-proved ('lawPullbackPseudometric' asserts them as teeth against a
broken expression map, not as new mathematics). What the pullback ADDS is the
honest quotient: two θ vectors that express identically are at distance 0
however different their words ('lawGaugeQuotient' exhibits a real pair — a
sub-quantum θ that the Q16 commit floors to the zero gene).

== Discrete geometry + algebraic number theory

Everything here lives on the established lattices, nothing on ℝ:

  * The 7 detail bands are the A₇ detail axes ("1 coarse + 7 detail" — the
    refinement-system root lattice); expression evaluates θ band-by-band, so
    the cloud is indexed (probe × band), 9·7 = 63 points.
  * Values re-enter the Q16 floor INSIDE 'predictDetail' (the single sanctioned
    'SixFour.Spec.ByteCarrier.reenterQ16' crossing) — the ℤ[1\/2]-module scale
    window. The metric therefore reads COMMITTED BYTES, never raw floats.
  * Both clouds ride the SAME probe frame, so position axes cancel pointwise
    ('lawPositionsCancel') and the distance concentrates entirely on the
    invented values — the probe is a shared coordinate frame, not data.
  * 'expressedEnergy' (distance to the zero gene) is the L¹ mass of invented
    detail above the floor — distance-to-origin IS detail energy.

== The sandwich (the port map, compartmentalized)

One large kernel cannot do everything; each algorithm step is its own
compartment, integer stages in Zig SIMT with the single float layer between,
every seam Q16-committed and separately oracle-gated (the
@v21AccumulateHistKernel@ pattern):

@
  [1] probe gather      — INTEGER: pinned Q16 stimuli, lattice positions   (Zig \/ Metal int twin)
  [2] express + commit  — the ONE FLOAT layer: rawBands θ·φ(v), fenced by
                          reenterQ16 INSIDE predictDetail                  (MPS \/ tensor-op stage)
  [3] d6 accumulate     — INTEGER: cloudDistance sum                       (Zig \/ Metal int twin)
@

The 'geneDistance' type (@… -> Int@) is the witness: everything after the
commit is on the integer floor.

Honest scope: θ_up-shaped genes only (the 'defaultPredictorShape' 21-word
family; 'lawWireSizesFromRegistry' in "SixFour.Spec.SwapCarrier" guarantees
carried genes are comparable within a name family). The σ-look genome (384
generators) needs its OWN expression map (palette reconstruction) before it
joins the atlas metric — do not fake it with a flat dot product. Similarity of
genes from DIFFERENT registry families is undefined by design. GHC-boot-only.
Laws QuickCheck'd in @Properties.GeneSimilarity@.
-}
-- COMPARTMENT: MLX-MODEL | tag:MacTag
module SixFour.Spec.GeneSimilarity
  ( -- * The probe lattice (the shared frame)
    canonicalProbe
  , probePosition
  , posQuantum
    -- * Expression (the projection lift)
  , expressGene
    -- * The pullback metric
  , geneDistance
  , expressedEnergy
    -- * Laws (QuickCheck'd in @Properties.GeneSimilarity@)
  , lawPullbackPseudometric
  , lawGaugeQuotient
  , lawFloorIsOrigin
  , lawPositionsCancel
  , lawProbeSeparates
  ) where

import SixFour.Spec.CrossEncoderDistance (cloudDistance)
import SixFour.Spec.DetailPredictor      (PredictorShape (..), defaultPredictorShape,
                                          paramCount, predictDetail, zeroParams)
import SixFour.Spec.OctreeCell           (detailToList)
import SixFour.Spec.RelationalResidual   (P6 (..))

-- ---------------------------------------------------------------------------
-- The probe lattice
-- ---------------------------------------------------------------------------

-- | The pinned probe stimuli: nine coarse Q16 values spanning the signed unit
-- window @[-65536, 65536]@ symmetrically (0 = the floor stimulus). Pinned so
-- every backend expresses on the SAME frame; changing this list is a metric
-- version bump, not a tweak.
canonicalProbe :: [Int]
canonicalProbe = [-65536, -32768, -16384, -4096, 0, 4096, 16384, 32768, 65536]

-- | The position-lattice quantum for probe coordinates (a pinned Q16 step).
-- Positions are a FRAME, not data — they cancel pointwise ('lawPositionsCancel').
posQuantum :: Int
posQuantum = 4096

-- | The lattice position of (probe index, band index): @x = i·q, y = j·q, t = 0@.
probePosition :: Int -> Int -> (Int, Int, Int)
probePosition i j = (i * posQuantum, j * posQuantum, 0)

-- ---------------------------------------------------------------------------
-- Expression: the projection lift θ → [P6]
-- ---------------------------------------------------------------------------

-- | Express a gene on the probe lattice: run the REAL device forward
-- ('predictDetail' — raw band readout θ·φ(v) re-entering Q16 inside it) at every
-- probe stimulus, and lay each committed band byte out as a P6 point (the byte on
-- the L axis, chroma zero, the (probe, band) lattice position). @|probe| × 7@
-- points, in a fixed order shared by every expression — which is what makes the
-- pointwise 'cloudDistance' zip meaningful.
expressGene :: PredictorShape -> [Double] -> [P6]
expressGene sh ps =
  [ P6 bandByte 0 0 x y t
  | (i, v) <- zip [0 ..] canonicalProbe
  , let bands = detailToList (predictDetail sh ps v)
  , (j, bandByte) <- zip [0 ..] bands
  , let (x, y, t) = probePosition i j
  ]

-- ---------------------------------------------------------------------------
-- The pullback metric
-- ---------------------------------------------------------------------------

-- | THE gene distance: 'cloudDistance' pulled back along 'expressGene'. Integer-
-- valued (the sandwich witness: the metric reads committed bytes, and everything
-- after the commit is integer arithmetic). A pseudometric by pullback.
geneDistance :: PredictorShape -> [Double] -> [Double] -> Int
geneDistance sh a b = cloudDistance (expressGene sh a) (expressGene sh b)

-- | A gene's invented-detail mass above the floor: its distance to the zero gene
-- (whose expression is the all-floor cloud). Distance-to-origin IS detail energy.
expressedEnergy :: PredictorShape -> [Double] -> Int
expressedEnergy sh g = geneDistance sh g (zeroParams sh)

-- ---------------------------------------------------------------------------
-- Laws (QuickCheck'd in Properties.GeneSimilarity)
-- ---------------------------------------------------------------------------

-- | The pullback IS a pseudometric: reflexive-zero, symmetric, triangle — over
-- any three genes. Inherited from @d6@ by the pullback theorem; asserted here as
-- teeth against a broken expression map (an unstable order or a frame mismatch
-- would break symmetry\/triangle immediately).
lawPullbackPseudometric :: [Double] -> [Double] -> [Double] -> Bool
lawPullbackPseudometric a b c =
  let sh = defaultPredictorShape
      d  = geneDistance sh
  in d a a == 0
     && d a b == d b a
     && d a c <= d a b + d b c

-- | THE QUOTIENT: flat comparison lies, expression does not. A sub-quantum θ
-- (every word @1e-12@) differs from the zero gene word-by-word, but the Q16
-- commit inside 'predictDetail' floors every band readout, so the two express
-- identically and sit at distance 0. This is the same theorem-shape as the
-- palette gauge ("compare in fused space") — the pullback measures the ORBIT,
-- not the chart.
lawGaugeQuotient :: Bool
lawGaugeQuotient =
  let sh    = defaultPredictorShape
      zero  = zeroParams sh
      tiny  = replicate (paramCount sh) 1e-12
  in tiny /= zero
     && expressGene sh tiny == expressGene sh zero
     && geneDistance sh tiny zero == 0

-- | The zero gene is the ORIGIN: it expresses as the all-floor cloud (every band
-- byte 0 — @zeroParams@ is the floor by arithmetic), and its self-distance is 0.
lawFloorIsOrigin :: Bool
lawFloorIsOrigin =
  let sh    = defaultPredictorShape
      cloud = expressGene sh (zeroParams sh)
  in all (\p -> p6L p == 0 && p6A p == 0 && p6B p == 0) cloud
     && geneDistance sh (zeroParams sh) (zeroParams sh) == 0

-- | Positions are a shared FRAME: both expressions ride the same probe lattice,
-- so the position axes contribute exactly 0 to every pointwise comparison — the
-- distance concentrates entirely on the invented values.
lawPositionsCancel :: [Double] -> [Double] -> Bool
lawPositionsCancel a b =
  let sh = defaultPredictorShape
      pa = expressGene sh a
      pb = expressGene sh b
  in sum [ abs (p6X p - p6X q) + abs (p6Y p - p6Y q) + abs (p6T p - p6T q)
         | (p, q) <- zip pa pb ] == 0

-- | The pinned probe SEPARATES real differences: a gene with one honest constant
-- readout (θ₀₀ = 0.25 ⇒ band-0 commits to 16384 at every stimulus) sits at
-- positive distance from the zero gene, and every expression has the full
-- @|probe| × 7@ frame.
lawProbeSeparates :: Bool
lawProbeSeparates =
  let sh   = defaultPredictorShape
      unit = 0.25 : replicate (paramCount sh - 1) 0
  in geneDistance sh unit (zeroParams sh) > 0
     && length (expressGene sh unit) == length canonicalProbe * 7

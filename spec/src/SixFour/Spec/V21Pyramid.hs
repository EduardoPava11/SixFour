{- |
Module      : SixFour.Spec.V21Pyramid
Description : V2.1 two-scale spatial field pyramid: the 64×64 sub-bins block-pool into 16×16 bins. A byte-exact aggregate (bins are the sum of their sub-bins), lossy DOWNWARD (real context, not redundant), and the coarse bins ARE the palette basis for the barycentric-coordinate value head.

The shipped V2.1 field ("SixFour.Spec.V21Field", @accumulateHist@\/@poolV21Counts@) is the burst POOLED
over time: per @64×64@ spatial bin, per channel, a value histogram over @0..nLevels-1@. The time axis is
carried separately by the transport flow ("SixFour.Spec.V21Transport"). This module adds the SPATIAL
pyramid the model wants as super-resolution context: a second, COARSER field at @16×16@ (the @'poolSpatial'@
of the fine one by a @4×4@ block), so the model sees the colour distribution at two scales — the @16³@
Analysis "coarse plan" and the @64³@ Pivot "capture" of the proven scale spine
("SixFour.Spec.HJepaLevels") — when it re-derives the palettes for the @256³@ Synthesis output.

The design is honest about what the coarse level is: NOT new signal. It is the EXACT @4×4@ block-sum of
the fine field, so it adds no observation the fine field lacks ('lawMassConserved',
'lawCoarseIsBlockSumOfFine'), and it is the SAME box grouping the capture kernel already applies, one step
coarser ('lawPoolMatchesAccumulateBoxGrouping'). Its value is twofold:

  * __Faithful multi-scale context.__ Pooling is TRANSITIVE ('lawPyramidTransitive'): decimating straight
    to @16×16@ equals decimating to @64×64@ first and then block-summing @4×4@. So "bins" and "sub-bins"
    can never disagree — the coarse plan is a true consensus of the fine capture, not a rival measurement.
    Its honest twin: you CANNOT run the pooling backwards ('lawFineNotRecoverableFromCoarse'), so the
    coarse field is genuine context the model reads, not a redundant copy of the fine one.
  * __The palette basis.__ Each coarse bin's per-channel histogram ('coarseBasis') is one candidate colour
    distribution. At @16×16@ there are @16² = 256 = 'nLevels'@ of them ('lawSixteenIsPaletteBasis'), one per
    palette slot — the spec's "a @16³@ frame IS a palette" ("SixFour.Spec.SynthesisPolicyValue")
    materialised at the sensor. And every basis colour is REALISABLE: the coarse mode is a value genuinely
    present in the fine region ('lawCoarseModeIsRealizable'), so a palette expressed as a barycentric
    combination of this basis stays in the captured gamut hull (the Wasserstein-barycentric-coordinate
    value head rides on top of this, in a later module).

== Scope

Additive and byte-exact (integer count sums, no division, no float, no colour-ring choice), so the V2
colour-substrate gate-wall is untouched. It reuses "SixFour.Spec.V21Field" ('nLevels', 'modeOfCounts',
'accumulateHist'); it introduces no new spine. The barycentric-coordinate solve (the Bonneel inverse: fit
a target palette to this basis) is a Mac-side trainer step and lives in a separate module — only the
byte-exact FORWARD (basis + coordinates -> palette, the per-rank barycenter of "SixFour.Spec.V21Transport")
is device floor.
-}
-- COMPARTMENT: ZIG-FLOOR | tag:DeviceTag
module SixFour.Spec.V21Pyramid
  ( -- * The two-scale spatial field pyramid
    Side
  , Factor
  , coarseSide
  , poolSpatial
    -- * The colour basis (each coarse bin is a candidate palette distribution)
  , binChannelHist
  , coarseBasis
  , coarseMode
    -- * Laws (QuickCheck'd in @Properties.V21Pyramid@)
  , lawCoarseIsBlockSumOfFine
  , lawPyramidTransitive
  , lawMassConserved
  , lawCoarseBinMassIsBlockMass
  , lawCoarseModeIsRealizable
  , lawFineNotRecoverableFromCoarse
  , lawPoolMatchesAccumulateBoxGrouping
  , lawSixteenIsPaletteBasis
  ) where

import SixFour.Spec.V21Field (nLevels, modeOfCounts, accumulateHist)

-- | The side of a square spatial bin grid (e.g. @64@ for the fine sub-bins, @16@ for the coarse bins).
type Side = Factor

-- | A spatial pooling factor: how many fine sub-bins per axis fold into one coarse bin (e.g. @4@ for
--   @64×64 -> 16×16@). A 'Side' is the same underlying @Int@; the alias names its role.
type Factor = Int

-- | The coarse grid side after pooling a @side×side@ field by @factor@: @side \`div\` factor@. The caller
--   guarantees divisibility (@64@ and @16@ are both powers of two, so @4@ divides @64@ exactly).
coarseSide :: Side -> Factor -> Side
coarseSide side f = side `div` f

-- The flat offset of (spatial bin, channel, value) in a field, layout @((bin*3 + ch)*levels + value)@,
-- with @bin = y*side + x@. The SAME layout "SixFour.Spec.V21Field" @accumulateHist@ emits for a single
-- time slice (its @coarseVoxel@ reduces to @y*side + x@ when the @t@ axis is fully decimated).
offsetAt :: Int -> Int -> Int -> Int -> Int
offsetAt levels bin ch v = (bin * 3 + ch) * levels + v

-- | POOL the fine field into the coarse one: each coarse bin's per-channel value histogram is the SUM of
--   the histograms of the @factor×factor@ fine sub-bins it covers. Pure integer addition (no division, no
--   float), so it stays on the byte-exact ring ℤ. Input is a @side×side@ field flat in the
--   @((bin*3 + ch)*levels + value)@ layout; output is a @'coarseSide' side factor@-square field in the
--   same layout. The @64×64 -> 16×16@ capture pyramid is @poolSpatial 256 64 4@.
poolSpatial :: Int -> Side -> Factor -> [Int] -> [Int]
poolSpatial levels side f fine =
  [ blockSum cy cx ch v
  | cy <- [0 .. cs - 1], cx <- [0 .. cs - 1], ch <- [0 .. 2], v <- [0 .. levels - 1] ]
  where
    cs  = coarseSide side f
    len = length fine
    get i = if i >= 0 && i < len then fine !! i else 0
    blockSum cy cx ch v =
      sum [ get (offsetAt levels ((cy * f + dy) * side + (cx * f + dx)) ch v)
          | dy <- [0 .. f - 1], dx <- [0 .. f - 1] ]

-- | The per-channel value HISTOGRAM of one bin (@0..levels-1@): the candidate colour distribution the
--   barycentric-coordinate value head treats as a basis atom. A pure slice of the field, no arithmetic.
binChannelHist :: Int -> [Int] -> Int -> Int -> [Int]
binChannelHist levels field bin ch =
  [ get (offsetAt levels bin ch v) | v <- [0 .. levels - 1] ]
  where
    len = length field
    get i = if i >= 0 && i < len then field !! i else 0

-- | THE PALETTE BASIS: every coarse bin as one concatenated 3-channel distribution (layout
--   @[ch0 over all values, ch1 …, ch2 …]@, length @3*levels@). At @16×16@ this is @256@ basis atoms — one
--   per palette slot ('lawSixteenIsPaletteBasis') — and each is realisable in the captured gamut
--   ('lawCoarseModeIsRealizable'). The set a target palette is expressed as Wasserstein barycentric
--   coordinates OVER, in the trainer.
coarseBasis :: Int -> Side -> [Int] -> [[Int]]
coarseBasis levels side field =
  [ concat [ binChannelHist levels field bin ch | ch <- [0 .. 2] ]
  | bin <- [0 .. side * side - 1] ]

-- | The coarse bin's per-channel GIF byte: the mode of its value histogram, exactly
--   "SixFour.Spec.V21Field" 'modeOfCounts' (lowest index wins ties). The coarse "colour" of a bin.
coarseMode :: Int -> [Int] -> Int -> Int -> Int
coarseMode levels field bin ch = modeOfCounts (binChannelHist levels field bin ch)

-- ---------------------------------------------------------------------------
-- Laws (predicates; QuickCheck'd in Properties.V21Pyramid). Fine fields are
-- built from a raw int seed cycled into small non-negative counts, the same
-- "coerce raw generators into legal payloads" discipline as V21Field/V21Transport.
-- ---------------------------------------------------------------------------

-- Build a legal count field of dims @side×side×3×levels@ from a raw seed (cycled, small non-negative).
mkField :: Int -> Side -> [Int] -> [Int]
mkField levels side seed =
  let n = side * side * 3 * levels
      s = if null seed then [0] else map (\x -> abs x `mod` 5) seed
  in take n (cycle s)

-- | THE DEFINING EQUATION — a coarse bin is the block-sum of its sub-bins: 'poolSpatial' equals, for every
--   coarse @(bin, channel)@, the elementwise sum of the @factor×factor@ fine sub-bin histograms (computed
--   here by an independent per-channel-histogram traversal). Correct indexing, ordering, and layout.
lawCoarseIsBlockSumOfFine :: Int -> Int -> Int -> [Int] -> Bool
lawCoarseIsBlockSumOfFine lraw sraw fraw seed =
  let levels = 1 + abs lraw `mod` 4
      f      = 1 + abs fraw `mod` 3
      cs     = 1 + abs sraw `mod` 3
      side   = cs * f
      fine   = mkField levels side seed
      coarse = poolSpatial levels side f fine
      blockBins cy cx = [ (cy * f + dy) * side + (cx * f + dx) | dy <- [0 .. f - 1], dx <- [0 .. f - 1] ]
      sumHists = foldr1 (zipWith (+))
      refBin cy cx = concat [ sumHists [ binChannelHist levels fine b ch | b <- blockBins cy cx ]
                            | ch <- [0 .. 2] ]
      ref = concat [ refBin cy cx | cy <- [0 .. cs - 1], cx <- [0 .. cs - 1] ]
  in coarse == ref

-- | THE KEYSTONE — POOLING IS TRANSITIVE ("bins and sub-bins never disagree"): decimating a field straight
--   to the coarse grid equals decimating halfway and then again. @poolSpatial by 4@ equals
--   @poolSpatial by 2 . poolSpatial by 2@. This is what makes the coarse plan a faithful consensus of the
--   fine capture rather than a second, possibly-conflicting measurement — the whole justification for
--   shipping both scales.
lawPyramidTransitive :: Int -> Int -> [Int] -> Bool
lawPyramidTransitive lraw sraw seed =
  let levels = 1 + abs lraw `mod` 4
      cs     = 1 + abs sraw `mod` 3
      f      = 2
      g      = 2
      side   = cs * f * g
      fine   = mkField levels side seed
      direct = poolSpatial levels side (f * g) fine
      staged = poolSpatial levels (coarseSide side f) g (poolSpatial levels side f fine)
  in direct == staged

-- | MASS IS CONSERVED: pooling neither creates nor destroys an observation, so the coarse field totals
--   exactly what the fine field totals. The coarse level carries no signal the fine one lacks.
lawMassConserved :: Int -> Int -> Int -> [Int] -> Bool
lawMassConserved lraw sraw fraw seed =
  let levels = 1 + abs lraw `mod` 4
      f      = 1 + abs fraw `mod` 3
      cs     = 1 + abs sraw `mod` 3
      side   = cs * f
      fine   = mkField levels side seed
  in sum (poolSpatial levels side f fine) == sum fine

-- | LOCAL CONSERVATION (no cross-channel or cross-bin leakage): each coarse @(bin, channel)@ mass equals
--   the sum of its @factor×factor@ fine sub-bins' masses in the SAME channel. Stronger than the global
--   'lawMassConserved': mass stays inside its own bin and channel.
lawCoarseBinMassIsBlockMass :: Int -> Int -> Int -> [Int] -> Bool
lawCoarseBinMassIsBlockMass lraw sraw fraw seed =
  let levels = 1 + abs lraw `mod` 4
      f      = 1 + abs fraw `mod` 3
      cs     = 1 + abs sraw `mod` 3
      side   = cs * f
      fine   = mkField levels side seed
      coarse = poolSpatial levels side f fine
      blockBins cy cx = [ (cy * f + dy) * side + (cx * f + dx) | dy <- [0 .. f - 1], dx <- [0 .. f - 1] ]
      coarseMass cy cx ch = sum (binChannelHist levels coarse (cy * cs + cx) ch)
      fineMass   cy cx ch = sum [ sum (binChannelHist levels fine b ch) | b <- blockBins cy cx ]
  in and [ coarseMass cy cx ch == fineMass cy cx ch
         | cy <- [0 .. cs - 1], cx <- [0 .. cs - 1], ch <- [0 .. 2] ]

-- | THE BASIS IS REALISABLE (gamut-closed): the coarse bin's mode is a value that genuinely occurred in
--   at least one of its fine sub-bins. So a coarse "colour" is never invented — it is present in the
--   captured region — which is why a palette expressed as a barycentric combination of 'coarseBasis' stays
--   in the fine field's gamut hull. Empty bins (zero mass) are vacuously fine.
lawCoarseModeIsRealizable :: Int -> Int -> Int -> [Int] -> Bool
lawCoarseModeIsRealizable lraw sraw fraw seed =
  let levels = 2 + abs lraw `mod` 4
      f      = 1 + abs fraw `mod` 3
      cs     = 1 + abs sraw `mod` 2
      side   = cs * f
      fine   = mkField levels side seed
      coarse = poolSpatial levels side f fine
      blockBins cy cx = [ (cy * f + dy) * side + (cx * f + dx) | dy <- [0 .. f - 1], dx <- [0 .. f - 1] ]
      ok cy cx ch =
        let h = binChannelHist levels coarse (cy * cs + cx) ch
        in sum h == 0 ||
             let m = modeOfCounts h
             in h !! m > 0
                && any (\b -> binChannelHist levels fine b ch !! m > 0) (blockBins cy cx)
  in and [ ok cy cx ch | cy <- [0 .. cs - 1], cx <- [0 .. cs - 1], ch <- [0 .. 2] ]

-- | THE HONEST TWIN — the fine field is NOT recoverable from the coarse one: two DIFFERENT fine fields
--   pool to the SAME coarse field (the @4@ sub-bins @[1,0],[0,1],[1,0],[0,1]@ and @[1,0],[1,0],[0,1],[0,1]@
--   both sum to @[2,2]@). Pooling is not injective, so the coarse level is genuine downward-lossy CONTEXT
--   the model reads, not a redundant copy of the fine capture. The complement to 'lawPyramidTransitive'.
lawFineNotRecoverableFromCoarse :: Bool
lawFineNotRecoverableFromCoarse =
  let levels = 2
      side   = 2                                   -- 2×2 fine -> 1×1 coarse (factor 2)
      -- Per (bin,ch) a length-2 histogram; ch1 and ch2 identical between A and B, only ch0 differs.
      chH v0 v1 = [v0, v1]
      -- bin order 0..3; each bin: [ch0 hist, ch1 hist, ch2 hist] concatenated.
      binOf a0 = concat [chH a0 (1 - a0), chH 1 0, chH 0 1]
      fineA = concatMap binOf [1, 0, 1, 0]         -- ch0 sub-bins: [1,0],[0,1],[1,0],[0,1]
      fineB = concatMap binOf [1, 1, 0, 0]         -- ch0 sub-bins: [1,0],[1,0],[0,1],[0,1]
  in fineA /= fineB
     && poolSpatial levels side 2 fineA == poolSpatial levels side 2 fineB

-- | THE PYRAMID IS THE CAPTURE BOX, ONE STEP COARSER: pooling the @accumulateHist@ field by @2@ equals
--   running @accumulateHist@ at twice the decimation directly on the same raw sensor grid. So the coarse
--   bins are the SAME box grouping the capture kernel already applies (counting is additive over the
--   disjoint sub-boxes that tile a box), not a new measurement layered on top. Concrete @4×4@ sensor grid.
lawPoolMatchesAccumulateBoxGrouping :: Bool
lawPoolMatchesAccumulateBoxGrouping =
  let levels = 4
      raw    = [ i `mod` 4 | i <- [0 .. 47] ]      -- fx=fy=4, ft=1, 3 channels -> 4*4*3 = 48 samples
      f2     = accumulateHist (4, 4, 1) (2, 2, 1) levels raw   -- 2×2 field
      f1     = accumulateHist (4, 4, 1) (4, 4, 1) levels raw   -- 1×1 field
  in poolSpatial levels 2 2 f2 == f1

-- | @16×16 = 256 = 'nLevels'@: the coarse grid has EXACTLY one bin per palette slot, so the coarse basis
--   is palette-sized ("a @16³@ frame IS a palette"). Checked with the arithmetic identity and a small
--   witness that 'coarseBasis' yields one atom per coarse bin.
lawSixteenIsPaletteBasis :: Bool
lawSixteenIsPaletteBasis =
     16 * 16 == nLevels
  && length (coarseBasis 2 4 (replicate (4 * 4 * 3 * 2) 0)) == 4 * 4

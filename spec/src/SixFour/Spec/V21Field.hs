{- |
Module      : SixFour.Spec.V21Field
Description : V2.1 pre-collapse field: colour curves collapse to the GIF89a byte; the byte-exact core (collapse, opponent delta, octant spine, metric).

V2.1 is the PRE-COLLAPSE distributional lift of the V2 latent. Per voxel a colour channel is
a probability curve, stored ENERGY-FIRST as an INTEGER vector over the 256 value levels
(@'Curve'@); energy is the count-complement @E = N - count@ and is NOT @2^16@-scaled (the "Q16" in
@'EnergyQ16'@ is legacy naming, only the mass twin 'massFromCount' is Q16-scaled). The byte the
user sees in the GIF89a is the energy-MINIMISING level (@'collapseQ16'@ = @argmin@), and because
collapse is order-only it is exact under any monotone recode. This module promotes ONLY the
byte-exact, colour-ring-INDEPENDENT core of that design:

  * 'collapseQ16', the seam to the existing byte path (@collapse@ of a curve == the sRGB byte the
    V2 boundary already consumes). Lowest-index tie-break, like @nearestCentroidQ16@.
  * 'opponentI' \/ 'labDeltaAt', the integer opponent transform @(L,a,b) = (R+G+B, R-G, R+G-2B)@
    applied to the per-level NEIGHBOUR DELTA. Linear, so it commutes with the delta
    ('lawOpponentCommutesWithDelta'), the licence to encode deltas and rebuild opponent colour.
  * 'liftOctList' \/ 'unliftOctList', a thin list adapter over the already-gated reversible octant
    spine "SixFour.Spec.OctreeCell" @liftOct@\/@unliftOct@ (REUSED, not re-derived). The 8 octant
    children are the @±1@ neighbourhood; the coarse is the floored-mean lineage (bounded).
  * 'axisWeight', the metric: @x@ and @y@ share one linear weight; @t@ is weighted by the
    per-frame palette delta.
  * 'centeredEnergy' \/ 'modeRelative' \/ 'anchorAt', the CANONICAL ENCODER-INPUT presentation
    (the design is @spec\/exploration\/V2.1-ENCODER-INPUT.md@): the learnable input is ENERGY (not
    counts\/mass\/surprisal), presented referred to the ground state and reindexed about its own
    mode, so the encoder input WITHHOLDS the absolute mode and the GIF (the mode) supplies it. Field
    and GIF are then non-redundant by construction ('lawModeIsNotAFunctionOfField',
    'lawFieldPlusGifReconstructs'). 'liftOctCurves' \/ 'detailAt' lift the curves level-wise for the
    I-JEPA target band ('lawTargetNotDeterminedByGifModes', the vector no-leak guarantee).
  * 'kContract' \/ 'onFloor' \/ 'bandLength' \/ 'readDepth', the S\/K two-level reading (S barred on
    the reversible floor) and the well-founded PonderNet read-depth.

== Scope (what is deliberately NOT here)

The probability\/softmax view (the @exp(-E)@ Boltzmann normalisation and Shannon entropy) is a
REAL-valued training diagnostic OFF the byte-exact path; it stays in the exploration module
@spec\/exploration\/V21Definitions.hs@. No colour-ring choice (Eisenstein vs opponent storage, the
\/3 substrate) is introduced here, so the V2 colour-substrate gate-wall (the locked M1→M2→M3
sequence) is untouched: this module is additive and reuses the gated 'SixFour.Spec.OctreeCell'
spine. Energy is the plain-integer count-complement (NOT @2^16@-scaled); 'collapseQ16' is order-only,
so it is exact under any monotone code.
-}
-- COMPARTMENT: ZIG-FLOOR | tag:DeviceTag
module SixFour.Spec.V21Field
  ( -- * The fibre and the field
    Level
  , EnergyQ16
  , Curve
  , BinQ16(..)
  , Voxel
  , Axis(..)
  , nLevels
    -- * The collapse (the GIF89a byte)
  , collapseQ16
    -- * Opponent transform on the neighbour delta
  , opponentI
  , curveDelta
  , labDeltaAt
    -- * The metric (x,y linear; t weighted)
  , PaletteDelta
  , Palette
  , paletteChannelHist
  , paletteDelta
  , paletteW1
  , axisWeight
    -- * The canonical encoder-input presentation (mode-relative energy; field + GIF non-redundant)
  , centeredEnergy
  , modeRelative
  , anchorAt
  , liftOctCurves
  , detailAt
    -- * The reversible octant spine (reuses "SixFour.Spec.OctreeCell")
  , octantVoxels
  , liftOctList
  , unliftOctList
    -- * S / K two-level + PonderNet read-depth
  , kContract
  , onFloor
  , bandLength
  , readDepth
    -- * The captured-bin curve model (empirical histogram; abstracts s4_board_counts_to_mass_q16)
  , q16One
  , massFromCount
  , countsToMass
  , energyFromCount
  , countsToEnergy
  , modeOfCounts
  , accumulateHist
    -- * The sub-LSB soft-splat construction (uses the discarded 10-bit sensor bits)
  , splatContribAt
  , accumulateHistSoft
    -- * Laws (QuickCheck'd in @Properties.V21Field@)
  , lawCollapseIsArgmin
  , lawOpponentCommutesWithDelta
  , lawXyLinearTimeWeighted
  , lawOctantLiftReversible
  , lawOctantCoarseBounded
  , lawSBarredOnFloor
  , lawReadDepthWellFounded
  , lawMassMatchesBoardAlgo
  , lawCollapseEnergyIsMode
  , lawEnergyMassOrderDual
  , lawHistTotalPreserved
  , lawHistCellSumsToCellSize
  , lawHistUniformIsSpike
  , lawCenteredEnergyDeployRoundTrips
  , lawModeRelativeWithholdsMode
  , lawModeIsNotAFunctionOfField
  , lawFieldPlusGifReconstructs
  , lawTargetNotDeterminedByGifModes
  , lawPaletteDeltaZeroOnEqual
  , lawPaletteDeltaSymmetric
  , lawPaletteDeltaGaugeInvariant
  , lawPaletteDeltaStaticTimeFree
  , lawSoftSplatMassConserved
  , lawSoftSplatCentroidExact
  , lawSoftSplatIsLocal
  , lawSoftHistTotalPreserved
  , lawWDistZeroOnEqual
  , lawWDistSymmetric
  , lawWDistGaugeInvariant
  , lawWDistStaticTimeFree
  , lawWDistChargesDistance
  ) where

import SixFour.Spec.OctreeCell (V8(..), OctBand(..), liftOct, unliftOct)

-- | A discrete value level in one colour channel (the fibre coordinate). For byte-exact GIF89a the
--   alphabet is @0..nLevels-1@.
type Level = Int

-- | An energy sample, Q16 fixed-point. Energy is the stored representation; probability is a derived
--   (real-valued) view that lives in the exploration module, off the byte-exact path.
type EnergyQ16 = Int

-- | A probability curve, stored energy-first as its sampled Q16 energies over the value alphabet
--   (length 'nLevels'). The fixed length is the SIMT contract: one thread fills one bin, no
--   neighbour reads.
type Curve = [EnergyQ16]

-- | A voxel coordinate @(x, y, t)@ in the @64×64×64@ box.
type Voxel = (Int, Int, Int)

-- | The SIMT bin payload: three energy curves, one per primary (R, G, B).
data BinQ16 = BinQ16
  { binR :: !Curve   -- ^ red   energy curve
  , binG :: !Curve   -- ^ green energy curve
  , binB :: !Curve   -- ^ blue  energy curve
  } deriving (Eq, Show)

-- | The three neighbour axes. @X@ and @Y@ are spatial (linear); @T@ is temporal (weighted).
data Axis = X | Y | T deriving (Eq, Show)

-- | The number of value levels per curve (the fibre dimension): 256, byte-exact for GIF89a.
nLevels :: Int
nLevels = 256

-- | THE COLLAPSE: the GIF89a byte is the energy-minimising level, @argmin_l E(l)@, with the LOWEST
--   index winning ties (the same strict-@<@ discipline as @nearestCentroidQ16@). This is the seam to
--   the existing byte path: @collapseQ16@ of a curve is the sRGB byte the V2 boundary consumes.
collapseQ16 :: Curve -> Level
collapseQ16 []      = 0
collapseQ16 (e : es) = fst (go (0, e) 1 es)
  where
    go best _ [] = best
    go best@(_, bv) i (v : rest) = go (if v < bv then (i, v) else best) (i + 1) rest

-- | The integer opponent transform: @(L, a, b) = (R+G+B, R-G, R+G-2B)@. Linear, so it commutes with
--   the neighbour delta. Identical arithmetic to the V2 opponent latent.
opponentI :: (Int, Int, Int) -> (Int, Int, Int)
opponentI (rr, gg, bb) = (rr + gg + bb, rr - gg, rr + gg - 2 * bb)

-- | The per-level delta of two curves (the encode target): @C1(l) - C2(l)@.
curveDelta :: Curve -> Curve -> Curve
curveDelta = zipWith (-)

-- | The opponent @(L,a,b)@ delta between two bins at one level: build the three channel deltas, then
--   apply 'opponentI'. By linearity this equals the delta of the opponent-transformed colours.
labDeltaAt :: BinQ16 -> BinQ16 -> Level -> (Int, Int, Int)
labDeltaAt v1 v2 l =
  opponentI ( at (binR v1) - at (binR v2)
            , at (binG v1) - at (binG v2)
            , at (binB v1) - at (binB v2) )
  where at c = if l >= 0 && l < length c then c !! l else 0

-- | A per-frame palette delta: a scalar measuring how much frame @t@'s palette differs from the
--   next frame's. The temporal axis is charged at this cost.
type PaletteDelta = Int

-- | The metric weight on a neighbour delta per axis: @x@ and @y@ share one linear weight (1); @t@ is
--   weighted by the per-frame palette delta. The single place the box's anisotropy lives.
axisWeight :: PaletteDelta -> Axis -> Int
axisWeight _  X = 1
axisWeight _  Y = 1
axisWeight pd T = pd

-- | A palette: colours as a flat SLOT-MAJOR integer list, layout @(slot*3 + channel)@, each channel a
--   value level in @0..levels-1@. For GIF89a there are up to 256 slots. This is the data a
--   'PaletteDelta' is computed FROM (per frame).
type Palette = [Int]

-- | The per-channel VALUE HISTOGRAM of a palette: for each channel (R, G, B) and each value level, the
--   number of slots whose value in that channel is that level. Layout @(ch*levels + value)@, length
--   @3*levels@. It counts VALUES, not slots, so it is invariant to the palette index gauge (reordering
--   slots leaves it unchanged) -- the invariance 'paletteDelta' inherits.
paletteChannelHist :: Int -> Palette -> [Int]
paletteChannelHist levels pal =
  [ length [ () | (i, v) <- zip [0 :: Int ..] pal, i `mod` 3 == ch, v == lvl ]
  | ch <- [0 .. 2 :: Int], lvl <- [0 .. levels - 1] ]

-- | THE PER-FRAME PALETTE DELTA (the temporal metric weight; @axisWeight T = pd@): the L1 \/ total
--   variation between two palettes' per-channel value histograms,
--   @sum_{ch,v} |hist1(ch,v) - hist2(ch,v)|@. Byte-exact integer and PERMUTATION-INVARIANT (reordering
--   a palette's slots -- the palette index gauge -- does not change it), so it charges only a genuine
--   change in the colour DISTRIBUTION from one frame to the next, never the gauge. A static palette
--   gives 0, which makes a temporal step free ('lawPaletteDeltaStaticTimeFree'), the design's
--   "flat palette =\> free time". This is the cheapest byte-exact metric; a joint-3D \/ earth-mover
--   refinement is deferred (open Q3 in @spec\/exploration\/V2.1-PROBABILISTIC-FIELD.md@).
paletteDelta :: Int -> Palette -> Palette -> PaletteDelta
paletteDelta levels p1 p2 =
  sum (zipWith (\a b -> abs (a - b))
               (paletteChannelHist levels p1)
               (paletteChannelHist levels p2))

-- | TRUE 1-D WASSERSTEIN-1 between two palettes' per-channel value histograms: the L1 distance between
--   their CDFs, @sum_{ch,v} |CDF1(ch,v) - CDF2(ch,v)|@, where the CDF is the running cumulative sum of
--   the histogram over the ordered value levels. Where 'paletteDelta' (total variation, L1 of the
--   HISTOGRAMS) is horizontal-blind (a one-level colour drift and a far colour jump of equal mass score
--   identically), this charges the GROUND DISTANCE mass must travel: a 1-level drift costs 1 per unit
--   mass, a 200-level jump costs 200 ('lawWDistChargesDistance'). Byte-exact integer (cumsum is linear,
--   no division) and permutation-invariant, like 'paletteDelta'. REQUIRES equal per-channel total mass
--   (true for two k-slot palettes, whose channels each total k); it does NOT normalize (that would
--   leave the ring). This is the 1-D optimal-transport metric (the deferred open Q3 "EMD" richer
--   metric) discharged on the byte-exact path, with no Sinkhorn and no float.
paletteW1 :: Int -> Palette -> Palette -> PaletteDelta
paletteW1 levels p1 p2 =
  let h1   = paletteChannelHist levels p1
      h2   = paletteChannelHist levels p2
      diff = zipWith (-) h1 h2
      -- per channel: cumulative sum of the signed diff, then sum the absolute running totals.
      channelW1 ch = sum (map abs (scanl1 (+) (take levels (drop (ch * levels) diff))))
  in sum (map channelW1 [0, 1, 2 :: Int])

-- | The eight @2×2×2@ octant corner voxels of a base voxel (Morton-style corner order). These ARE the
--   voxels reachable within a single @±1@ step on each axis, so the octant spine and the neighbour
--   stencil are the same discrete-geometry object.
octantVoxels :: Voxel -> [Voxel]
octantVoxels (xx, yy, tt) =
  [ (xx + dx, yy + dy, tt + dt) | dt <- [0, 1], dy <- [0, 1], dx <- [0, 1] ]

-- | List adapter over the gated 'SixFour.Spec.OctreeCell' octant lift: 8 cells -> (coarse, 7
--   residuals). REUSES @liftOct@; no spine math is re-derived here.
liftOctList :: [Int] -> (Int, [Int])
liftOctList [a, b, c, d, e, f, g, h] =
  let OctBand co (d0, d1, d2, d3, d4, d5, d6) = liftOct (V8 a b c d e f g h)
  in (co, [d0, d1, d2, d3, d4, d5, d6])
liftOctList xs = (sum xs, [])   -- non-octant input: degenerate (only called on length-8 lists)

-- | The exact inverse list adapter over 'SixFour.Spec.OctreeCell' @unliftOct@.
unliftOctList :: (Int, [Int]) -> [Int]
unliftOctList (co, [d0, d1, d2, d3, d4, d5, d6]) =
  let V8 a b c d e f g h = unliftOct (OctBand co (d0, d1, d2, d3, d4, d5, d6))
  in [a, b, c, d, e, f, g, h]
unliftOctList (co, _) = [co]

-- | K = pool\/contract: the total absolute residual mass (lower = more contracted).
kContract :: [Int] -> Int
kContract = sum . map abs

-- | Whether the octant is on the reversible floor: all eight children equal. On the floor the
--   residual band is exactly zero, so S (invent) is barred, you cannot add information to a bijection.
onFloor :: Eq a => [a] -> Bool
onFloor []       = True
onFloor (c : cs) = all (== c) cs

-- | The band length: the count of non-zero residuals. PonderNet's strictly-decreasing measure.
bandLength :: [Int] -> Int
bandLength = length . filter (/= 0)

-- | PonderNet read-depth: descend rungs while the residual band length strictly decreases; halt when
--   it bottoms. Well-founded recursion (the measure is a natural number bounded below), NOT a Banach
--   contraction.
readDepth :: [[Int]] -> Int
readDepth = go 0
  where
    go d (w1 : w2 : ws)
      | bandLength w2 < bandLength w1 = go (d + 1) (w2 : ws)
      | otherwise                     = d
    go d _ = d

-- ---------------------------------------------------------------------------
-- The captured-bin curve model: an empirical histogram, abstracting the existing
-- counts -> Q16 mass algorithm (Zig s4_board_counts_to_mass_q16) to the per-channel
-- value alphabet, plus its order-dual energy facet.
-- ---------------------------------------------------------------------------

-- | Q16 one (= 2^16). The probability scale.
q16One :: Int
q16One = 65536

-- | Round-half-up Q16 empirical mass of a count out of a total: @round(count/total * 2^16)@,
--   computed as @floor((count*2^16 + floor(total/2)) / total)@. This is BYTE-IDENTICAL to the
--   existing Zig @boardMassFromCount@ (the algorithm behind @s4_board_counts_to_mass_q16@); V2.1
--   reuses it as the probability face of the captured-bin curve. @total <= 0@ yields 0.
massFromCount :: Int -> Int -> Int
massFromCount count total
  | total <= 0 = 0
  | otherwise  = (count * q16One + total `div` 2) `div` total

-- | The probability (mass) face of a captured bin: per-level counts -> Q16 empirical PMF, total =
--   the number of observations. The 256-level generalisation of @s4_board_counts_to_mass_q16@.
countsToMass :: [Int] -> [Int]
countsToMass counts = let total = sum counts in map (`massFromCount` total) counts

-- | The energy of a single count out of a total: @E = total - count@. Monotone DECREASING in the
--   count, so @argmin E = argmax count@ (the most-observed level) -- unconditionally, with no
--   transcendental and no quantisation. This is the V2.1 (energy-first) face.
energyFromCount :: Int -> Int -> Int
energyFromCount count total = total - count

-- | The energy face of a captured bin: per-level counts -> the V2.1 energy curve (collapse-ready).
--   @collapseQ16 (countsToEnergy cs)@ is the MODE of the histogram (the most-observed value).
countsToEnergy :: [Int] -> Curve
countsToEnergy counts = let total = sum counts in map (`energyFromCount` total) counts

-- | The mode of a count histogram: the level with the most observations, lowest index winning ties.
--   Reuses 'collapseQ16' on the negated counts (argmax = argmin of the negation).
modeOfCounts :: [Int] -> Level
modeOfCounts counts = collapseQ16 (map negate counts)

-- | ACCUMULATE the captured histogram (the first half of make_bins): box-decimate a FINE grid into
--   coarse output voxels and, per voxel per channel, count the fine samples at each value level. The
--   coarse voxel of a fine sample is its integer floor-division by the decimation factor, the SAME
--   box grouping the cube-ladder reduction uses (this is its distributional sibling: keep the
--   per-cell value distribution instead of the reversible Haar detail). The fine grid is flat,
--   layout @(((ft*fy + fy_i)*fx + fx_i)*3 + ch)@ with values in @0 .. nLevels-1@; the output is flat,
--   layout @((coarseVoxel*3 + ch)*nLevels + value)@ over @ct*cy*cx@ coarse voxels. The per-axis
--   dimensions must be divisible by the decimation factors.
accumulateHist :: (Int, Int, Int) -> (Int, Int, Int) -> Int -> [Int] -> [Int]
accumulateHist (fx, fy, ft) (dx, dy, dt) levels fine =
  [ length [ () | (s, v) <- tagged, s == (cvi, ch), v == lvl ]
  | cvi <- [0 .. cVox - 1], ch <- [0 .. 2], lvl <- [0 .. levels - 1] ]
  where
    cx = fx `div` dx
    cy = fy `div` dy
    ct = ft `div` dt
    cVox = cx * cy * ct
    tagged = [ (slotOf i, v) | (i, v) <- zip [0 ..] fine ]
    slotOf i =
      let chn = i `mod` 3
          pp  = i `div` 3
          fxi = pp `mod` fx
          qq  = pp `div` fx
          fyi = qq `mod` fy
          fti = qq `div` fy
          cxi = fxi `div` dx
          cyi = fyi `div` dy
          cti = fti `div` dt
      in ((cti * cy + cyi) * cx + cxi, chn)

-- ---------------------------------------------------------------------------
-- The sub-LSB SOFT-SPLAT construction: use the 10-bit sensor bits the hard
-- round() throws away. A fine sample is a HIGH-PRECISION position hi over the
-- scale (nLevels-1)*W (its linear value scaled by the sub-level budget W, so
-- hi = level*W + subfraction). Instead of a hard +1 at round(hi/W), a UNIT of
-- integer mass W is split between the two adjacent value levels in proportion to
-- the sub-LSB fraction. This is the unique 2-point integer distribution on
-- adjacent levels whose weighted mean is EXACTLY hi (lawSoftSplatCentroidExact),
-- so the discarded bits survive as the histogram's first moment. All integer, no
-- non-unit division, so it stays on the byte-exact ring Z.
-- ---------------------------------------------------------------------------

-- | The contribution of one fine sample at high-precision position @hi@ (over budget @w@) to value
--   level @lvl@: @w - (hi \`mod\` w)@ at the floor level @hi \`div\` w@, @hi \`mod\` w@ at the next
--   level, and 0 everywhere else. A partition of unity in integers (the two weights sum to @w@), so
--   the per-sample mass is exactly conserved with no division by a non-unit. @w@ must be positive and
--   @hi@ non-negative; @hi <= (nLevels-1)*w@ keeps the upper level in range (at @hi@ a multiple of @w@
--   the fraction is 0, so no mass lands on the next level).
splatContribAt :: Int -> Int -> Int -> Int
splatContribAt w hi lvl =
  let vlo  = hi `div` w
      frac = hi `mod` w
  in if lvl == vlo then w - frac
     else if lvl == vlo + 1 then frac
     else 0

-- | ACCUMULATE the SOFT captured histogram (the sub-LSB construction; the trainer's field face). Same
--   box-decimation and layout as 'accumulateHist', but each fine sample is a HIGH-PRECISION position
--   @hi@ in @0 .. (levels-1)*w@ and instead of a hard @+1@ at @round(hi\/w)@ it SPLATS a unit of
--   integer mass @w@ across the two adjacent levels ('splatContribAt'). Each @(voxel, channel)@ cell
--   therefore totals @box * w@ instead of @box@; the energy face @E = total - count@ is unchanged in
--   form. The shipped GIF byte does NOT come from here (V2.1 is a separate pipeline from the k-means
--   palette that ships the GIF); this face enriches the model input with the sensor bits @round@
--   discards. Fine layout @(((ft*fy + y)*fx + x)*3 + ch)@, output @((coarseVoxel*3 + ch)*levels + v)@.
accumulateHistSoft :: Int -> (Int, Int, Int) -> (Int, Int, Int) -> Int -> [Int] -> [Int]
accumulateHistSoft w (fx, fy, ft) (dx, dy, dt) levels fine =
  [ sum [ splatContribAt w v lvl | (s, v) <- tagged, s == (cvi, ch) ]
  | cvi <- [0 .. cVox - 1], ch <- [0 .. 2], lvl <- [0 .. levels - 1] ]
  where
    cx = fx `div` dx
    cy = fy `div` dy
    ct = ft `div` dt
    cVox = cx * cy * ct
    tagged = [ (slotOf i, v) | (i, v) <- zip [0 :: Int ..] fine ]
    slotOf i =
      let chn = i `mod` 3
          pp  = i `div` 3
          fxi = pp `mod` fx
          qq  = pp `div` fx
          fyi = qq `mod` fy
          fti = qq `div` fy
          cxi = fxi `div` dx
          cyi = fyi `div` dy
          cti = fti `div` dt
      in ((cti * cy + cyi) * cx + cxi, chn)

-- | Split a list into consecutive chunks of @n@ (the per-cell histograms of an 'accumulateHist' output).
chunksOf :: Int -> [a] -> [[a]]
chunksOf _ [] = []
chunksOf n xs = take n xs : chunksOf n (drop n xs)

-- ---------------------------------------------------------------------------
-- The canonical ENCODER-INPUT presentation (design: spec/exploration/V2.1-ENCODER-INPUT.md).
-- The learnable input is ENERGY (not counts/mass/surprisal): integer, linear (commutes with the
-- opponent transform), order-correct (so the byte re-enters via argmin). It is presented
-- GROUND-STATE-CENTERED and MODE-RELATIVE so the absolute mode is withheld from the field and the
-- GIF supplies it -- field and GIF are then complementary, not redundant.
-- ---------------------------------------------------------------------------

-- | Left-rotate a list cyclically by @k@ (reduced mod the length). The cyclic group @Z/n@ acts on
--   the value fibre; rotations compose additively, the algebra behind 'modeRelative' \/ 'anchorAt'.
rotateLeft :: Int -> [a] -> [a]
rotateLeft _ [] = []
rotateLeft k xs = let n = length xs; k' = k `mod` n in drop k' xs ++ take k' xs

-- | GROUND-STATE CENTERING: subtract the curve's minimum, so the energy is the excess above the
--   ground state and the GIF byte (the @argmin@) sits at energy 0. A monotone shift, so it leaves
--   'collapseQ16' (and its lowest-index tie-break) unchanged: the byte re-enters byte-exactly.
centeredEnergy :: Curve -> Curve
centeredEnergy [] = []
centeredEnergy c  = let m = minimum c in map (subtract m) c

-- | THE ENCODER INPUT: the centered curve reindexed about its own mode (left-rotated by the mode
--   index), so the @argmin@ is pinned to relative-0 and the ABSOLUTE mode coordinate is withheld.
--   Two histograms differing only in WHERE the mode sits map to the SAME 'modeRelative' input
--   ('lawModeIsNotAFunctionOfField'); the GIF supplies the missing absolute mode (see 'anchorAt').
--   The reindex convention is cyclic, the simplest exact length-preserving bijection; the windowed
--   convention is an open question in the design doc.
modeRelative :: Curve -> Curve
modeRelative c = rotateLeft (collapseQ16 c) (centeredEnergy c)

-- | The left inverse of 'modeRelative' GIVEN the absolute mode (the GIF byte): re-attach the
--   mode-relative curve at its absolute level. @anchorAt (collapseQ16 e) (modeRelative e) ==
--   centeredEnergy e@ ('lawFieldPlusGifReconstructs'): field + GIF reconstruct the field.
anchorAt :: Int -> Curve -> Curve
anchorAt _ [] = []
anchorAt i v  = rotateLeft (negate i `mod` length v) v

-- | Lift eight equal-length curves LEVEL-WISE through the gated octant spine, returning the coarse
--   curve and the seven detail curves. The colour-agnostic per-level reuse of 'liftOctList'; the
--   held detail band is the I-JEPA target (see 'detailAt', 'lawTargetNotDeterminedByGifModes').
liftOctCurves :: [Curve] -> (Curve, [Curve])
liftOctCurves children =
  let n      = if null children then 0 else minimum (map length children)
      cols   = [ liftOctList [ ch !! l | ch <- children ] | l <- [0 .. n - 1] ]
      coarse = map fst cols
      detail = [ map ((!! k) . snd) cols | k <- [0 .. 6] ]
  in (coarse, detail)

-- | Select detail band @m@ (0..6) of a 'liftOctCurves' result; @[]@ if out of range.
detailAt :: Int -> [Curve] -> Curve
detailAt m bands = if m >= 0 && m < length bands then bands !! m else []

-- | THE COLLAPSE PICKS THE ENERGY MINIMUM AT THE LOWEST INDEX: for any non-empty curve, the chosen
--   level attains the minimum energy and no earlier level ties it.
lawCollapseIsArgmin :: Curve -> Bool
lawCollapseIsArgmin c =
  null c ||
    let i = collapseQ16 c
    in c !! i == minimum c && all (\j -> c !! j > c !! i) [0 .. i - 1]

-- | OPPONENT COMMUTES WITH THE DELTA: 'labDeltaAt' (opponent of the per-channel delta) equals the
--   delta of the opponent-transformed colours, at any level. The licence to encode deltas.
lawOpponentCommutesWithDelta :: BinQ16 -> BinQ16 -> Level -> Bool
lawOpponentCommutesWithDelta v1 v2 l =
  l < 0 || l >= n ||
    labDeltaAt v1 v2 l ==
      let (l1, a1, b1) = opponentI (at (binR v1), at (binG v1), at (binB v1))
          (l2, a2, b2) = opponentI (at (binR v2), at (binG v2), at (binB v2))
      in (l1 - l2, a1 - a2, b1 - b2)
  where
    n = minimum (map length [binR v1, binG v1, binB v1, binR v2, binG v2, binB v2])
    at c = c !! l

-- | x AND y ARE LINEAR TO EACH OTHER; t IS WEIGHTED at the per-frame palette delta. A flat palette
--   (@pd = 0@) makes a temporal step free of palette cost.
lawXyLinearTimeWeighted :: PaletteDelta -> Bool
lawXyLinearTimeWeighted pd =
     axisWeight pd X == axisWeight pd Y
  && axisWeight 0 T == 0
  && axisWeight pd T == pd

-- Coerce an arbitrary int list into a legal palette for @levels@ (values in range, length a multiple
-- of 3). Not exported; drives the palette-delta laws from QuickCheck's raw generators.
clampPalette :: Int -> [Int] -> Palette
clampPalette levels xs =
  let n = length xs - (length xs `mod` 3)
  in [ abs x `mod` max 1 levels | x <- take n xs ]

-- Reverse the SLOT order of a palette (keeping each RGB triple intact): a non-trivial permutation
-- witness for the gauge-invariance law. Not exported.
reverseSlots :: Palette -> Palette
reverseSlots = concat . reverse . chunksOf 3

-- | THE DELTA VANISHES ON AN IDENTICAL PALETTE: a palette has zero delta to itself, so an unchanging
--   palette costs nothing on the temporal axis.
lawPaletteDeltaZeroOnEqual :: Int -> [Int] -> Bool
lawPaletteDeltaZeroOnEqual lraw xs =
  let levels = 1 + abs lraw `mod` 8
      p      = clampPalette levels xs
  in paletteDelta levels p p == 0

-- | THE DELTA IS SYMMETRIC (L1 is a metric): @paletteDelta a b == paletteDelta b a@.
lawPaletteDeltaSymmetric :: Int -> [Int] -> [Int] -> Bool
lawPaletteDeltaSymmetric lraw a b =
  let levels = 1 + abs lraw `mod` 8
      pa     = clampPalette levels a
      pb     = clampPalette levels b
  in paletteDelta levels pa pb == paletteDelta levels pb pa

-- | GAUGE INVARIANCE (the key property): reordering a palette's SLOTS (the palette index gauge) leaves
--   the delta unchanged, because the per-channel histogram counts values, not positions. Reversing the
--   slot order is the permutation witness. This is why the temporal weight charges only genuine colour
--   change, not a re-indexing of the same colours.
lawPaletteDeltaGaugeInvariant :: Int -> [Int] -> [Int] -> Bool
lawPaletteDeltaGaugeInvariant lraw a b =
  let levels = 1 + abs lraw `mod` 8
      pa     = clampPalette levels a
      pb     = clampPalette levels b
  in paletteDelta levels pa pb == paletteDelta levels (reverseSlots pa) pb

-- | A STATIC PALETTE MAKES TIME FREE: an unchanging palette has delta 0, and 'axisWeight' then charges
--   nothing on the @T@ axis -- the design's "flat palette =\> temporal step free", closing the loop
--   with 'lawXyLinearTimeWeighted' (which pins @axisWeight 0 T == 0@).
lawPaletteDeltaStaticTimeFree :: Int -> [Int] -> Bool
lawPaletteDeltaStaticTimeFree lraw xs =
  let levels = 1 + abs lraw `mod` 8
      p      = clampPalette levels xs
  in axisWeight (paletteDelta levels p p) T == 0

-- | W1 VANISHES ON AN IDENTICAL PALETTE (the CDFs coincide), so an unchanging palette costs nothing.
lawWDistZeroOnEqual :: Int -> [Int] -> Bool
lawWDistZeroOnEqual lraw xs =
  let levels = 1 + abs lraw `mod` 8
      p      = clampPalette levels xs
  in paletteW1 levels p p == 0

-- | W1 IS SYMMETRIC (the CDF difference is negated when the arguments swap; the absolute value is even).
lawWDistSymmetric :: Int -> [Int] -> [Int] -> Bool
lawWDistSymmetric lraw a b =
  let levels = 1 + abs lraw `mod` 8
      pa     = clampPalette levels a
      pb     = clampPalette levels b
  in paletteW1 levels pa pb == paletteW1 levels pb pa

-- | W1 IS GAUGE-INVARIANT: reordering a palette's slots leaves it unchanged, because the per-channel
--   histogram (hence its cumulative sum, the CDF) counts values, not slot positions.
lawWDistGaugeInvariant :: Int -> [Int] -> [Int] -> Bool
lawWDistGaugeInvariant lraw a b =
  let levels = 1 + abs lraw `mod` 8
      pa     = clampPalette levels a
      pb     = clampPalette levels b
  in paletteW1 levels pa pb == paletteW1 levels (reverseSlots pa) pb

-- | A STATIC PALETTE MAKES TIME FREE under the W1 weight too (delta 0, 'axisWeight' charges nothing).
lawWDistStaticTimeFree :: Int -> [Int] -> Bool
lawWDistStaticTimeFree lraw xs =
  let levels = 1 + abs lraw `mod` 8
      p      = clampPalette levels xs
  in axisWeight (paletteW1 levels p p) T == 0

-- | THE LOAD-BEARING DISCRIMINATOR, why W1 beats total variation: a ONE-LEVEL colour drift costs
--   strictly LESS than a FAR jump of equal mass, the exact ground-distance information TV cannot see.
--   Three single-slot palettes: at level 0, at level 1 (a 1-level drift), and at the top level (a far
--   jump). W1 charges the drift 1 and the jump @levels-1@ (strictly more), while 'paletteDelta' (TV)
--   scores BOTH the same (2, "one slot moved"), blind to the distance.
lawWDistChargesDistance :: Int -> Bool
lawWDistChargesDistance lraw =
  let levels = 3 + abs lraw `mod` 200        -- at least 3 levels so drift and jump differ
      p0     = [0, 0, 0]                      -- one slot, all channels at level 0
      pNear  = [1, 0, 0]                      -- red drifts one level
      pFar   = [levels - 1, 0, 0]             -- red jumps to the top level
  in  paletteW1 levels p0 pNear < paletteW1 levels p0 pFar          -- W1 SEES the distance
   && paletteW1 levels p0 pNear == 1                                -- drift costs exactly 1
   && paletteW1 levels p0 pFar  == levels - 1                       -- jump costs the full distance
   && paletteDelta levels p0 pNear == paletteDelta levels p0 pFar   -- TV is BLIND to it (both 2)

-- | THE SOFT SPLAT CONSERVES MASS (partition of unity in integers): the contributions of one sample
--   over all value levels sum to the budget @w@, so no observation is created or destroyed and no
--   non-unit division is needed. This is what keeps the sub-LSB construction on the byte-exact ring.
lawSoftSplatMassConserved :: Int -> Int -> Bool
lawSoftSplatMassConserved wRaw hiRaw =
  let w   = 1 + abs wRaw `mod` 256
      hi  = abs hiRaw `mod` 100000
      vlo = hi `div` w
  in sum [ splatContribAt w hi lvl | lvl <- [0 .. vlo + 2] ] == w

-- | THE DISCARDED BITS ARE RECOVERABLE, the headline theorem: the mass-weighted MEAN (first moment) of
--   a sample's splat is EXACTLY its high-precision position @hi@, not the rounded level. So the field's
--   centroid reconstructs the full 10-bit value that @round@ would have thrown away: the soft splat is
--   the unique 2-point integer distribution on adjacent levels with mean @hi@.
lawSoftSplatCentroidExact :: Int -> Int -> Bool
lawSoftSplatCentroidExact wRaw hiRaw =
  let w   = 1 + abs wRaw `mod` 256
      hi  = abs hiRaw `mod` 100000
      vlo = hi `div` w
  in sum [ lvl * splatContribAt w hi lvl | lvl <- [vlo, vlo + 1] ] == hi

-- | THE SPLAT IS LOCAL: a sample deposits mass ONLY on its two adjacent levels @vlo@ and @vlo+1@, never
--   elsewhere. So the soft curve differs from the hard spike by at most one level, and its collapse
--   ('collapseQ16') drifts at most one LSB from the hard bin: the construction refines the field
--   without relocating a colour.
lawSoftSplatIsLocal :: Int -> Int -> Int -> Bool
lawSoftSplatIsLocal wRaw hiRaw lvlRaw =
  let w   = 1 + abs wRaw `mod` 256
      hi  = abs hiRaw `mod` 100000
      vlo = hi `div` w
      lvl = abs lvlRaw `mod` 1000
  in lvl == vlo || lvl == vlo + 1 || splatContribAt w hi lvl == 0

-- | EVERY FINE SAMPLE CONTRIBUTES ITS FULL BUDGET: the soft-accumulated histogram totals
--   @(number of fine samples) * w@, the box-count times the budget. The 'accumulateHist' total law
--   lifted to the soft face.
lawSoftHistTotalPreserved :: Bool
lawSoftHistTotalPreserved =
  let w    = 4
      fine = [ i `mod` 13 | i <- [0 .. 47] ]   -- hi in 0..12 = (levels-1)*w for levels=4
      h    = accumulateHistSoft w (4, 2, 2) (2, 2, 2) 4 fine
  in sum h == length fine * w

-- | THE OCTANT SPINE ROUND-TRIPS EXACTLY (reuses the gated 'SixFour.Spec.OctreeCell' edge): for any
--   eight cells, @unliftOctList . liftOctList == id@.
lawOctantLiftReversible :: [Int] -> Bool
lawOctantLiftReversible xs =
  length xs /= 8 || unliftOctList (liftOctList xs) == xs

-- | THE COARSE IS THE FLOORED-MEAN LINEAGE, SO IT IS BOUNDED: the coarse lies within @[min,max]@ of
--   the eight inputs (volume-preserving), why it never breaches the substrate bound (a sum-DC would).
lawOctantCoarseBounded :: [Int] -> Bool
lawOctantCoarseBounded xs =
  length xs /= 8 ||
    let (co, _) = liftOctList xs in co >= minimum xs && co <= maximum xs

-- | S IS BARRED ON THE REVERSIBLE FLOOR: equal children give a zero residual band (nothing to invent
--   or contract); an unequal octant has a non-empty band.
lawSBarredOnFloor :: Int -> Bool
lawSBarredOnFloor v =
  let (_, floorRes) = liftOctList (replicate 8 v)
      (_, edgeRes)  = liftOctList [v, v + 1, v, v + 1, v, v + 1, v, v + 2]
  in onFloor (replicate 8 v)
     && kContract floorRes == 0
     && bandLength floorRes == 0
     && kContract edgeRes > 0

-- | PONDERNET READ-DEPTH IS WELL-FOUNDED: it halts, and halts exactly when the band stops shrinking.
lawReadDepthWellFounded :: Bool
lawReadDepthWellFounded =
     readDepth [[1, 2, 3, 4], [0, 2, 3, 0], [0, 0, 3, 0], [0, 0, 0, 0]] == 3
  && readDepth [[1, 2, 3], [1, 2, 3]] == 0
  && readDepth [[1, 1], [1, 0], [1, 0]] == 1

-- | THE MASS FACE IS THE EXISTING BOARD ALGORITHM: 'massFromCount' reproduces the exact Q16 values
--   the shipped Zig @s4_board_counts_to_mass_q16@ pins in its golden (round-half-up), so the V2.1
--   probability face IS that algorithm, not a re-derivation.
lawMassMatchesBoardAlgo :: Bool
lawMassMatchesBoardAlgo =
     massFromCount 1 3 == 21845    -- (1*65536 + 1) `div` 3
  && massFromCount 2 3 == 43691    -- (2*65536 + 1) `div` 3
  && massFromCount 1 6 == 10923    -- (1*65536 + 3) `div` 6
  && massFromCount 0 10 == 0
  && massFromCount 5 5 == q16One   -- a certain level is full mass

-- | COLLAPSE OF THE ENERGY FACE IS THE MODE: for any count histogram, collapsing the energy curve
--   (argmin) returns the most-observed level (argmax count, lowest-index tie) -- the captured byte
--   is the value the bin saw most. Unconditional (no monotonicity precondition).
lawCollapseEnergyIsMode :: [Int] -> Bool
lawCollapseEnergyIsMode counts =
  null counts || collapseQ16 (countsToEnergy counts) == modeOfCounts counts

-- | THE TWO FACES ARE ORDER-DUAL: when the total fits the Q16 scale (so the mass is strictly
--   monotone in the count), the energy minimum and the mass maximum agree -- the byte path may use
--   either face. Guarded by @sum counts <= q16One@ (always true for a real per-bin observation count).
lawEnergyMassOrderDual :: [Int] -> Bool
lawEnergyMassOrderDual counts =
  null counts || sum counts > q16One
    || collapseQ16 (countsToEnergy counts) == modeOfCounts (countsToMass counts)

-- | EVERY FINE SAMPLE IS COUNTED ONCE: the total of the accumulated histogram equals the number of
--   fine samples (fx*fy*ft*3). No sample is dropped or double-counted.
lawHistTotalPreserved :: Bool
lawHistTotalPreserved =
  let fine = [ i `mod` 4 | i <- [0 .. 47] ]      -- 4*2*2*3 = 48 fine samples
      h    = accumulateHist (4, 2, 2) (2, 2, 2) 4 fine
  in sum h == length fine

-- | EACH COARSE-VOXEL-CHANNEL HISTOGRAM SUMS TO THE CELL SIZE: every (voxel, channel) cell counts
--   exactly dx*dy*dt fine samples (the box it decimates from). 6 cells (2 voxels x 3 channels) here.
lawHistCellSumsToCellSize :: Bool
lawHistCellSumsToCellSize =
  let fine     = [ i `mod` 4 | i <- [0 .. 47] ]
      h        = accumulateHist (4, 2, 2) (2, 2, 2) 4 fine
      cellSize = 2 * 2 * 2
      cells    = chunksOf 4 h                      -- nLevels = 4 per cell
  in length cells == 6 && all ((== cellSize) . sum) cells

-- | A UNIFORM FINE CELL IS A SPIKE: when every fine sample is the same value, each cell histogram is
--   a single spike (count = cell size) at that value -- a flat region collapses to a confident byte.
lawHistUniformIsSpike :: Bool
lawHistUniformIsSpike =
  let fine  = replicate 48 2
      h     = accumulateHist (4, 2, 2) (2, 2, 2) 4 fine
      cells = chunksOf 4 h
  in all (== [0, 0, 8, 0]) cells

-- | DEPLOY ROUND-TRIP: ground-state centering is a monotone recode, so the GIF byte is the zero of
--   the centered curve, 'collapseQ16' is unchanged, and the integer<->float seam round-trips exactly
--   (@round . fromIntegral@ is its left inverse) on the observation-count regime.
lawCenteredEnergyDeployRoundTrips :: [Int] -> Bool
lawCenteredEnergyDeployRoundTrips cs =
  null cs ||
    let e  = countsToEnergy cs
        ce = centeredEnergy e
        i  = collapseQ16 e
    in  ce !! i == 0
        && collapseQ16 ce == i
        && map (round . (fromIntegral :: Int -> Double)) ce == ce

-- | NON-REDUNDANCY, the field WITHHOLDS the mode: the encoder input's own @argmin@ is pinned to
--   relative-0 for EVERY curve, so the field carries no absolute-mode bit. The GIF (the mode) is
--   therefore independent information, not a copy of the field.
lawModeRelativeWithholdsMode :: [Int] -> Bool
lawModeRelativeWithholdsMode cs =
  null cs || collapseQ16 (modeRelative (countsToEnergy cs)) == 0

-- | NON-REDUNDANCY, witnessed: two histograms of the SAME shape but DIFFERENT modes map to the
--   identical 'modeRelative' field input, while their GIF bytes ('collapseQ16') differ. The absolute
--   mode is provably NOT a function of the field, so feeding both field and GIF is not redundant.
lawModeIsNotAFunctionOfField :: Bool
lawModeIsNotAFunctionOfField =
  let e1 = countsToEnergy [9, 0, 0, 0]      -- a spike whose mode is level 0
      e2 = countsToEnergy [0, 9, 0, 0]      -- the same spike, relocated to level 1
  in  modeRelative e1 == modeRelative e2
      && collapseQ16 e1 /= collapseQ16 e2

-- | RECONSTRUCTION (field + GIF recover the field): anchoring the mode-relative input at the
--   GIF-given mode reproduces the centered curve. The witness that the two streams are complementary.
lawFieldPlusGifReconstructs :: [Int] -> Bool
lawFieldPlusGifReconstructs cs =
  null cs ||
    let e = countsToEnergy cs
    in  anchorAt (collapseQ16 e) (modeRelative e) == centeredEnergy e

-- | VECTOR NO-LEAK: the held detail band is NOT determined by the context modes (the GIF). Two
--   octants of curves with IDENTICAL per-child modes (hence identical GIF) have DIFFERENT lifted
--   detail bands, so a context that saw every mode still could not copy the vector target -- the
--   JEPA prediction is real work. This replaces the old scalar-@disagree@ argument with the true
--   (vector) object.
lawTargetNotDeterminedByGifModes :: Bool
lawTargetNotDeterminedByGifModes =
  let base  = replicate 8 [0, 5, 5, 5]                          -- every child: mode at level 0
      moved = [0, 5, 5, 4] : replicate 7 [0, 5, 5, 5]           -- child 0 perturbed OFF its mode
  in  map collapseQ16 base == map collapseQ16 moved             -- GIF (all modes) identical
      && snd (liftOctCurves base) /= snd (liftOctCurves moved)  -- but the detail bands differ

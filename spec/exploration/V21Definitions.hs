{- |
Module      : V21Definitions
Description : EXPLORATION (NOT WIRED, base-only, runghc). V2.1 = the PRE-COLLAPSE distributional
              lift of V2. R, G, B, x, y, t are defined as PURE FUNCTIONS at the very top of the
              spec. The colour channels are PROBABILITY CURVES (energy landscapes) over a bin's
              value domain; the GIF89a the user sees is the energy-MINIMISING collapse of those
              curves. What we TRAIN on is the curves themselves. The six pure functions are the
              SIMT bin payload: one GPU thread fills one of the 64x64 bins with no neighbour
              dependence. Discrete geometry (the 2x2x2 octant lattice = the +/-1 neighbourhood)
              + algebraic number theory (the reversible lift = nested floor pair-lifts, each a unit
              of GL2(Z[1/2]); matches the shipped Zig s4_octant_lift byte-for-byte).

  Check:  cd spec/exploration && runghc V21Definitions.hs

  WHERE THIS SITS RELATIVE TO V2 (no locked decision is reopened):
    * V2Latent stores the COLLAPSED scalar latent [L=R+G+B, a=R-G, b=R+G-2B, x, y, t]. That is
      the post-measurement object: six numbers per voxel.
    * V2.1 is the object BEFORE collapse: per voxel, R, G and B are each a probability curve
      p(level), equivalently an energy E(level) with p ~ exp(-E). The "collapsed energy level"
      argmin_level E(level) is the byte V2Latent.encodeBoundary consumes. So:
            collapse . V2.1-curve  ==  the sRGB byte that feeds V2's boundary.
      V2.1 does not compete with the locked opponent latent; it is the layer above its boundary.
    * THE ENCODE TARGET IS THE DELTA, NOT THE ABSOLUTE CURVE. For neighbour voxels at +/-1 in
      x and/or y and/or t we take the per-channel curve DELTA; the opponent (L,a,b) transform is
      applied to that delta (linear, so opp(delta) == delta(opp)). x and y share one linear metric;
      t (and +/-1 t) is weighted by the per-frame palette delta.
    * THE SPINE IS UNCHANGED. Energy is the curve itself (E = -log p). The 2x2x2 -> 1 coarse + 7
      residual reversible octant lift, the S (expand/invent) / K (pool/contract) two-level reading,
      and the PonderNet read-depth search all ride on the curves exactly as they ride on V2 scalars,
      because the 8 octant children ARE the 8 +/-1 neighbours.

  Base-only, runghc, NOT in cabal/Map/gate. Trainer untouched.
-}
module V21Definitions where

import Data.List (foldl', minimumBy, sortBy)
import Data.Ord  (comparing)

-- ===========================================================================
-- (0) The value domain and the SIMT layout constants
-- ===========================================================================

-- | A discrete level in one colour channel's value domain. For byte-exact GIF89a this is 0..255;
--   kept as a parameter (nLevels) so the SIMT bin layout is explicit.
type Level = Int

-- | The number of sampled levels per curve. The curve is materialised as a fixed-length vector of
--   this many energies, so a bin has no variable-length payload -> embarrassingly parallel SIMT.
nLevels :: Int
nLevels = 256

levels :: [Level]
levels = [0 .. nLevels - 1]

-- | The frame side and burst length: the 64x64 bins of one frame, 64 frames per burst. One SIMT
--   thread per bin builds that bin's three curves.
side, frameCount :: Int
side       = 64
frameCount = 64

-- ===========================================================================
-- (1) THE HIGHEST-LEVEL DEFINITIONS: R, G, B, x, y, t as PURE FUNCTIONS
-- ===========================================================================

-- | A probability curve, written ENERGY-FIRST: a pure function from a level to its energy. The
--   probability is p(level) ~ exp(-E(level)). This is the mathematical object the model trains on;
--   "the GIF89a" is its collapse, never the curve.
type Curve = Level -> Double

-- | A voxel coordinate in the 64x64x64 box: (x, y, t).
type Voxel = (Int, Int, Int)

-- | A FIELD is the scene as the camera delivers it: every voxel carries its three colour curves.
--   This is the pre-collapse latent. R, G, B, x, y, t are all read off a Field + a Voxel.
type Field = Voxel -> Bin

-- | THE SIMT BIN PAYLOAD: three sampled energy curves (one per primary), each a fixed-length vector
--   of nLevels doubles. No pointers, no variable length, no neighbour reads => one thread per bin.
--   This is the type we hand to the GPU at the creation of the 64x64 bins.
data Bin = Bin
  { binR :: ![Double]   -- ^ sampled red   energy curve, length nLevels
  , binG :: ![Double]   -- ^ sampled green energy curve, length nLevels
  , binB :: ![Double]   -- ^ sampled blue  energy curve, length nLevels
  } deriving (Eq, Show)

-- | Materialise a pure Curve into the SIMT-flat sampled vector (what a thread writes into a Bin).
sampleCurve :: Curve -> [Double]
sampleCurve c = map c levels

-- | Read a sampled bin vector back as a pure Curve (out-of-range levels are +infinity = impossible).
asCurve :: [Double] -> Curve
asCurve xs lvl
  | lvl < 0 || lvl >= length xs = 1 / 0
  | otherwise                   = xs !! lvl

-- THE SIX PURE FUNCTIONS ------------------------------------------------------

-- | R as a pure function: the red probability curve at a voxel.
r :: Field -> Voxel -> Curve
r f v = asCurve (binR (f v))

-- | G as a pure function: the green probability curve at a voxel.
g :: Field -> Voxel -> Curve
g f v = asCurve (binG (f v))

-- | B as a pure function: the blue probability curve at a voxel.
b :: Field -> Voxel -> Curve
b f v = asCurve (binB (f v))

-- | x, y, t as pure coordinate functions on a voxel. x and y are spatial (linear, isotropic); t is
--   temporal (weighted, see axisWeight).
x, y, t :: Voxel -> Int
x (xx, _, _) = xx
y (_, yy, _) = yy
t (_, _, tt) = tt

-- ===========================================================================
-- (2) ENERGY / PROBABILITY SEMANTICS + THE COLLAPSE (the GIF89a the user sees)
-- ===========================================================================

-- | The Boltzmann probability of a level: p(l) = exp(-E(l)) / Z. The curve IS the energy; this is
--   "we still need energy" for free -- no separate energy head, the landscape is the channel.
prob :: Curve -> Level -> Double
prob c l = exp (negate (c l)) / partition c

-- | The partition function Z = sum_l exp(-E(l)).
partition :: Curve -> Double
partition c = sum [ exp (negate (c l)) | l <- levels ]

-- | Shannon entropy of a curve's induced distribution (nats). Used by the S/K two-level reading.
entropy :: Curve -> Double
entropy c = negate (sum [ let p = prob c l in if p > 1e-300 then p * log p else 0 | l <- levels ])

-- | THE COLLAPSE: the byte the user sees in the GIF89a is the energy-MINIMISING level = the mode of
--   the PMF = argmax_l p(l) = argmin_l E(l). The "collapsed energy levels" are exactly this.
collapse :: Curve -> Level
collapse c = fst (minimumBy (comparing snd) [ (l, c l) | l <- levels ])

-- | The collapsed sRGB byte triple at a voxel -- this is precisely what V2Latent.encodeBoundary
--   would receive. V2's whole opponent latent is collapse-then-encode of V2.1's curves.
collapsePixel :: Field -> Voxel -> (Int, Int, Int)
collapsePixel f v = (collapse (r f v), collapse (g f v), collapse (b f v))

-- ===========================================================================
-- (3) NEIGHBOURS at +/-1 and the DELTA we actually encode
-- ===========================================================================

-- | The three spatial/temporal axes. X and Y are linear to each other; T is weighted.
data Axis = X | Y | T deriving (Eq, Show)

-- | The +/-1 stencil: the six von Neumann neighbours of a voxel (one step along exactly one axis).
--   Pixel1 and pixel2 "distance +/-1 (x and/or y and/or t)" in the owner's words.
neighbours :: Voxel -> [(Axis, Voxel)]
neighbours (xx, yy, tt) =
  [ (X, (xx + 1, yy, tt)), (X, (xx - 1, yy, tt))
  , (Y, (xx, yy + 1, tt)), (Y, (xx, yy - 1, tt))
  , (T, (xx, yy, tt + 1)), (T, (xx, yy, tt - 1))
  ]

-- | The DELTA of two curves, level by level: deltaCurve c1 c2 l = c1 l - c2 l. THIS is the encode
--   target -- not the absolute curve. A flat region has near-zero delta (cheap); an edge spends.
deltaCurve :: Curve -> Curve -> Curve
deltaCurve c1 c2 l = c1 l - c2 l

-- | Per-channel curve delta between a voxel and a neighbour, for one primary selector (r, g or b).
channelDelta :: (Field -> Voxel -> Curve) -> Field -> Voxel -> Voxel -> Curve
channelDelta chan f v1 v2 = deltaCurve (chan f v1) (chan f v2)

-- ===========================================================================
-- (4) BUILD (L, a, b) FROM THE DELTAS -- opponent transform, in colour space
-- ===========================================================================

-- | The opponent (luma/red-green/yellow-blue) transform on an (R,G,B) triple. Identical arithmetic
--   to V2Latent: L = R+G+B, a = R-G, b = R+G-2B. LINEAR, so it commutes with the delta.
opponent :: (Double, Double, Double) -> (Double, Double, Double)
opponent (rr, gg, bb) = (rr + gg + bb, rr - gg, rr + gg - 2 * bb)

-- | The (L,a,b) curve-delta between two voxels, built FROM the three channel deltas at one level.
--   By linearity opp(deltaR, deltaG, deltaB) == (deltaL, deltaA, deltaB) -- we encode this directly.
labDeltaAt :: Field -> Voxel -> Voxel -> Level -> (Double, Double, Double)
labDeltaAt f v1 v2 l =
  opponent ( channelDelta r f v1 v2 l
           , channelDelta g f v1 v2 l
           , channelDelta b f v1 v2 l )

-- ===========================================================================
-- (5) THE METRIC: x, y LINEAR; t (and +/-1 t) WEIGHTED by the per-frame palette delta
-- ===========================================================================

-- | A per-frame palette delta: a scalar measuring how much frame t's 256-colour palette differs
--   from frame t+1's. In V2.1 the time axis is NOT isotropic with x,y -- a temporal step is charged
--   at the cost of repainting the palette. (Stand-in scalar here; the trainer supplies the real one.)
type PaletteDelta = Double

-- | The weight applied to a neighbour delta along each axis. x and y share ONE linear weight (they
--   are linear to each other); t is weighted at the per-frame palette delta. This is the single
--   place the box's anisotropy lives.
axisWeight :: PaletteDelta -> Axis -> Double
axisWeight _  X = 1                 -- x linear ...
axisWeight _  Y = 1                 -- ... and y linear to x (shared isotropic spatial metric)
axisWeight pd T = pd                -- t weighted at the per-frame palette delta

-- | The cost of a neighbour delta: the (L,a,b) magnitude of the curve-delta, scaled by the axis
--   weight. Spatial edges cost their colour change; temporal edges additionally pay the palette delta.
neighbourCost :: PaletteDelta -> Field -> Voxel -> (Axis, Voxel) -> Double
neighbourCost pd f v1 (ax, v2) =
  axisWeight pd ax * sum [ let (dl, da, db) = labDeltaAt f v1 v2 l
                           in abs dl + abs da + abs db
                         | l <- levels ]

-- ===========================================================================
-- (6) ENERGY SPINE: the 2x2x2 -> 1 coarse + 7 residual REVERSIBLE octant lift
--     MATCHES the shipped Zig s4_octant_lift (kernels.zig:857) byte-for-byte:
--     nested floor pair-lifts (the S-transform / lazy lifting), AVERAGE-lineage.
-- ===========================================================================

-- | The reversible integer pair-lift (Zig sLift64): sLift x y = (low, high) with
--   low = y + floor((x-y)/2) = floor((x+y)/2) (the AVERAGE, not the sum), high = x - y.
--   As a Z[1/2]-linear map this is [[1/2,1/2],[1,-1]] (det -1, a UNIT of Z[1/2]); the floor
--   makes it an exact bijection on Z^2. (Haskell `div` = floor division = Zig @divFloor.)
sLift :: Int -> Int -> (Int, Int)
sLift xx yy = let d = xx - yy in (yy + (d `div` 2), d)

-- | The inverse pair-lift (Zig sUnlift64): from (low, high) recover (x, y).
sUnlift :: (Int, Int) -> (Int, Int)
sUnlift (low, high) = let yy = low - (high `div` 2) in (yy + high, yy)

-- | 2x2 separable Haar on a row-major quad (Zig rgbtLiftQuad): four sLift applications,
--   rows then columns. [q0,q1,q2,q3] -> [ll, lh, hl, hh].
rgbtLiftQuad :: [Int] -> [Int]
rgbtLiftQuad [q0, q1, q2, q3] =
  let (la, ha) = sLift q0 q1
      (lc, hc) = sLift q2 q3
      (ll, lh) = sLift la lc
      (hl, hh) = sLift ha hc
  in [ll, lh, hl, hh]
rgbtLiftQuad xs = xs   -- non-quad: identity (only called on length-4 inputs)

-- | The inverse 2x2 Haar (Zig rgbtUnliftQuadChecked, minus the bound checks).
rgbtUnliftQuad :: [Int] -> [Int]
rgbtUnliftQuad [ll, lh, hl, hh] =
  let (la, lc) = sUnlift (ll, lh)
      (ha, hc) = sUnlift (hl, hh)
      (q0, q1) = sUnlift (la, ha)
      (q2, q3) = sUnlift (lc, hc)
  in [q0, q1, q2, q3]
rgbtUnliftQuad xs = xs

-- | THE OCTANT LIFT (Zig s4_octant_lift): 8 cells (near face 0..3, far face 4..7) -> 1 coarse +
--   7 residuals. Two face quad-lifts, then one z pair-lift on the two coarse (LL) values. The
--   coarse is the floored MEAN lineage, so it stays within [min,max] of the inputs (volume-
--   preserving, never breaches SUBSTRATE_BOUND) -- the correction over the earlier sum-DC form.
liftOct8 :: [Int] -> (Int, [Int])
liftOct8 cells =
  let [r0, g0, b0, t0] = rgbtLiftQuad (take 4 cells)
      [r1, g1, b1, t1] = rgbtLiftQuad (drop 4 cells)
      (rr, dz)         = sLift r0 r1
  in (rr, [g0, b0, t0, g1, b1, t1, dz])

-- | The exact inverse (Zig s4_octant_unlift): unlift the z stage, then each face quad.
unliftOct8 :: (Int, [Int]) -> [Int]
unliftOct8 (rr, [g0, b0, t0, g1, b1, t1, dz]) =
  let (r0, r1) = sUnlift (rr, dz)
      near     = rgbtUnliftQuad [r0, g0, b0, t0]
      far      = rgbtUnliftQuad [r1, g1, b1, t1]
  in near ++ far

-- | Apply the octant lift to the 8 +/-1 neighbours of a voxel, PER LEVEL of a chosen channel curve.
--   The 8 children are the 2x2x2 corner voxels around (x,y,t); this is the discrete-geometry
--   identification "octant children == +/-1 neighbourhood".
octantVoxels :: Voxel -> [Voxel]
octantVoxels (xx, yy, tt) =
  [ (xx + dx, yy + dy, tt + dt) | dt <- [0, 1], dy <- [0, 1], dx <- [0, 1] ]

-- | Quantize a real energy to a Q16 fixed-point integer: the boundary where the (real-valued)
--   probability curve meets the (integer, byte-exact) spine. The spine never sees doubles.
quantizeQ16 :: Double -> Int
quantizeQ16 e = round (e * 65536)

-- | Lift one channel's curve over the 8 octant voxels at a single level into (coarse, 7 residuals).
--   The Double energies are quantized to Q16 first, so the integer spine (matching Zig) drives them.
liftChannelAt :: (Field -> Voxel -> Curve) -> Field -> Voxel -> Level -> (Int, [Int])
liftChannelAt chan f v l = liftOct8 [ quantizeQ16 (chan f w l) | w <- octantVoxels v ]

-- ===========================================================================
-- (7) S / K TWO-LEVEL + PonderNet read-depth
-- ===========================================================================

-- | S = expand / invent. Level 1 (the coarse) is where the model is ALLOWED to add information:
--   S inflates entropy. We measure it as the entropy of the coarse curve (higher = more invented).
sExpand :: Curve -> Double
sExpand = entropy

-- | K = pool / contract. Level 2 (the 7 residuals) is where the model WEAKENS: K shrinks the
--   residual band. We measure it as the total absolute residual mass (lower = more contracted).
kContract :: [Int] -> Int
kContract = sum . map abs

-- | S IS BARRED ON THE REVERSIBLE FLOOR. On the identity floor (all 8 children equal) the residuals
--   are exactly zero: there is nothing to invent and nothing to contract -- you may not add
--   information to a bijection. This is the BCI "no contraction on the floor" guard.
onFloor :: Eq a => [a] -> Bool
onFloor children = all (== head children) children

-- | A PonderNet read step descends one rung: it halts when the residual band has bottomed out
--   (well-founded recursion on a strictly-decreasing band-length measure, NOT a Banach contraction).
--   bandLength is the count of non-zero residuals; it strictly decreases or we halt.
bandLength :: [Int] -> Int
bandLength = length . filter (/= 0)

-- | Read depth: keep contracting the residual word until its band length stops decreasing. Returns
--   the number of rungs read (the halt depth). Terminates because bandLength is a natural-number
--   measure bounded below by 0.
readDepth :: [[Int]] -> Int
readDepth = go 0
  where
    go d (w1 : w2 : ws)
      | bandLength w2 < bandLength w1 = go (d + 1) (w2 : ws)
      | otherwise                     = d
    go d _ = d

-- ===========================================================================
-- (8) SAMPLE FIELD (deterministic, no randomness) for the laws
-- ===========================================================================

-- | A parabolic energy curve centred at level mu with curvature k: E(l) = k * (l - mu)^2. Its
--   collapse is mu, its probability is a (discrete) Gaussian. Stand-in for a real per-bin curve.
gaussCurve :: Double -> Level -> Curve
gaussCurve k mu l = k * fromIntegral ((l - mu) * (l - mu))

-- | Build a Bin whose three channels are parabolas centred at (cr, cg, cb).
binAt :: (Level, Level, Level) -> Bin
binAt (cr, cg, cb) =
  Bin (sampleCurve (gaussCurve 0.02 cr))
      (sampleCurve (gaussCurve 0.02 cg))
      (sampleCurve (gaussCurve 0.02 cb))

-- | A deterministic test field: the centre of each channel's parabola is a simple linear ramp in the
--   voxel coordinates, so neighbouring voxels differ by a small, predictable delta.
testField :: Field
testField (xx, yy, tt) =
  binAt ( clamp (40 + xx + yy + tt)
        , clamp (80 + 2 * xx - yy)
        , clamp (120 + tt) )
  where clamp v = max 0 (min (nLevels - 1) v)

-- ===========================================================================
-- (9) LAWS
-- ===========================================================================

-- | COLLAPSE IS THE GIF89a BYTE: the energy-minimising level of a parabola is its centre, so the
--   collapsed pixel reads back the ramp centres. The user-visible GIF is collapse . curve.
lawCollapseIsArgminEnergy :: Bool
lawCollapseIsArgminEnergy =
     collapse (gaussCurve 0.02 137) == 137
  && collapsePixel testField (3, 4, 5) == ( clamp (40 + 3 + 4 + 5)
                                          , clamp (80 + 2*3 - 4)
                                          , clamp (120 + 5) )
  where clamp v = max 0 (min (nLevels - 1) v)

-- | COLLAPSE == ARGMAX PROBABILITY: the energy minimum is the probability mode (the Boltzmann link
--   is order-reversing), so "energy level" and "most likely level" are the same collapse.
lawCollapseIsMode :: Bool
lawCollapseIsMode =
  all (\mu -> let c = gaussCurve 0.02 mu
                  modeP = fst (minimumBy (comparing (negate . snd)) [ (l, prob c l) | l <- levels ])
              in collapse c == mu && modeP == mu)
      [10, 64, 128, 200, 250]

-- | THE SIMT BIN IS FIXED-LENGTH: every channel vector is exactly nLevels long, no variable payload,
--   so the 64x64 bins are an embarrassingly-parallel write (one thread, one bin, no neighbour read).
lawBinIsSimtFlat :: Bool
lawBinIsSimtFlat =
  let Bin rr gg bb = testField (7, 8, 9)
  in all ((== nLevels) . length) [rr, gg, bb]

-- | OPPONENT COMMUTES WITH THE DELTA (linearity): building (L,a,b) from the curve-delta equals the
--   delta of the opponent-transformed curves. This is why we may encode deltas and recover L,a,b.
lawOpponentCommutesWithDelta :: Bool
lawOpponentCommutesWithDelta =
  let v1 = (2, 2, 2); v2 = (3, 2, 2)
      lhs l = labDeltaAt testField v1 v2 l
      rhs l = let o1 = opponent (r testField v1 l, g testField v1 l, b testField v1 l)
                  o2 = opponent (r testField v2 l, g testField v2 l, b testField v2 l)
                  (l1,a1,b1) = o1; (l2,a2,b2) = o2
              in (l1 - l2, a1 - a2, b1 - b2)
  in all (\l -> close3 (lhs l) (rhs l)) levels
  where close3 (a,b,c) (d,e,f) = abs (a-d) < 1e-9 && abs (b-e) < 1e-9 && abs (c-f) < 1e-9

-- | x AND y ARE LINEAR TO EACH OTHER; t IS WEIGHTED. The spatial axes share one weight (1); the
--   temporal axis carries the per-frame palette delta, which a flat-palette burst (pd=0) zeroes out
--   while any palette change makes a temporal step strictly more expensive than the same colour
--   change in space.
lawXyLinearTimeWeighted :: Bool
lawXyLinearTimeWeighted =
     axisWeight pd X == axisWeight pd Y         -- x linear to y
  && axisWeight 0 T == 0                         -- flat palette: a temporal step is free of palette cost
  && axisWeight pd T == pd                       -- otherwise charged at the per-frame palette delta
  && pd > axisWeight pd X                        -- with this pd, a t-step weighs more than an x-step
  where pd = 3.5

-- | THE OCTANT LIFT IS REVERSIBLE (1 coarse + 7 residuals round-trips), EXACTLY (integer equality,
--   not float-close): 2x2x2 -> 1+7 -> 2x2x2 is the identity. The fourth case feeds the 8 collapsed
--   red levels of a real octant, so the spine is exercised on actual curve-collapse data.
lawOctantLiftReversible :: Bool
lawOctantLiftReversible =
  all (\vs -> unliftOct8 (liftOct8 vs) == vs)
      [ [1, 2, 3, 4, 5, 6, 7, 8]
      , replicate 8 10
      , [0, 5, 0, 5, 9, 1, 2, 3]
      , [ collapse (r testField w) | w <- octantVoxels (4, 4, 4) ] ]

-- | THE COARSE IS THE FLOORED-MEAN LINEAGE, SO IT IS BOUNDED: coarse lies within [min,max] of the 8
--   inputs (volume-preserving), which is why it never breaches SUBSTRATE_BOUND. A sum-DC would reach
--   8x the input range -- this law is the tooth on the sum-vs-average correction.
lawOctantCoarseBounded :: Bool
lawOctantCoarseBounded =
  all (\vs -> let (c, _) = liftOct8 vs in c >= minimum vs && c <= maximum vs)
      [ [0, 255, 0, 255, 0, 255, 0, 255]
      , [10, 20, 30, 40, 50, 60, 70, 80]
      , replicate 8 137 ]

-- | THE OCTANT CHILDREN ARE THE +/-1 NEIGHBOURHOOD (discrete geometry): the 8 corners of the 2x2x2
--   octant are all within a single +/-1 step on each axis of the base voxel.
lawOctantIsNeighbourhood :: Bool
lawOctantIsNeighbourhood =
  let base@(bx,by,bt) = (5,6,7)
  in length (octantVoxels base) == 8
     && all (\(wx,wy,wt) -> abs (wx-bx) <= 1 && abs (wy-by) <= 1 && abs (wt-bt) <= 1)
            (octantVoxels base)

-- | S IS BARRED ON THE REVERSIBLE FLOOR: when the 8 children are equal the residual band is all
--   zero, so kContract == 0 and there is nothing for S to expand -- you cannot inject information
--   into a bijection. Off the floor, the residual band is non-empty (S/K have room to act).
lawSBarredOnFloor :: Bool
lawSBarredOnFloor =
  let (_, floorRes) = liftOct8 (replicate 8 42)
      (_, edgeRes)  = liftOct8 [1,2,3,4,5,6,7,8]
  in onFloor (replicate 8 42)
     && kContract floorRes == 0
     && bandLength floorRes == 0
     && not (onFloor [1,2,3,4,5,6,7,8])
     && kContract edgeRes > 0

-- | PONDERNET READ-DEPTH IS WELL-FOUNDED: it halts, and it halts exactly when the residual band
--   stops shrinking. A strictly-shrinking word reads to the bottom; a stalled word halts at once.
lawReadDepthWellFounded :: Bool
lawReadDepthWellFounded =
     readDepth [ [1,2,3,4], [0,2,3,0], [0,0,3,0], [0,0,0,0] ] == 3   -- 3,2,1,0 strictly shrinks: depth 3
  && readDepth [ [1,2,3], [1,2,3] ] == 0                              -- no shrink: halt immediately
  && readDepth [ [1,1], [1,0], [1,0] ] == 1                          -- shrinks once then stalls

-- ===========================================================================
-- (10) RUNNER
-- ===========================================================================

laws :: [(String, Bool)]
laws =
  [ ("lawCollapseIsArgminEnergy   (GIF89a byte = energy-min level)",        lawCollapseIsArgminEnergy)
  , ("lawCollapseIsMode           (energy-min == probability mode)",        lawCollapseIsMode)
  , ("lawBinIsSimtFlat            (fixed-length bin = SIMT-parallel)",       lawBinIsSimtFlat)
  , ("lawOpponentCommutesWithDelta(L,a,b from delta == delta of L,a,b)",    lawOpponentCommutesWithDelta)
  , ("lawXyLinearTimeWeighted     (x,y linear; t at palette delta)",        lawXyLinearTimeWeighted)
  , ("lawOctantLiftReversible     (2x2x2 -> 1+7 round-trips, exact int)",   lawOctantLiftReversible)
  , ("lawOctantCoarseBounded      (coarse in [min,max]; mean not sum)",     lawOctantCoarseBounded)
  , ("lawOctantIsNeighbourhood    (octant children == +/-1 stencil)",       lawOctantIsNeighbourhood)
  , ("lawSBarredOnFloor           (no invention on the reversible floor)",  lawSBarredOnFloor)
  , ("lawReadDepthWellFounded     (PonderNet halts on band bottom)",        lawReadDepthWellFounded)
  ]

main :: IO ()
main = do
  putStrLn "V21Definitions.hs  -- EXPLORATION (NOT WIRED): V2.1 R,G,B,x,y,t as pure probability functions"
  putStrLn (replicate 78 '-')
  mapM_ (\(n, ok) -> putStrLn (verdict ok ++ "  " ++ n)) laws
  putStrLn (replicate 78 '-')
  let passed = length (filter snd laws); total = length laws
  putStrLn ("SUMMARY: " ++ show passed ++ "/" ++ show total ++ " laws PASS"
            ++ if passed == total then "  (all green)" else "  (FAILURES present)")
  putStrLn ""
  putStrLn ("collapsePixel testField (3,4,5)        = " ++ show (collapsePixel testField (3, 4, 5)))
  putStrLn ("opponent of that pixel (the V2 latent) = "
            ++ let (cr,cg,cb) = collapsePixel testField (3,4,5)
               in show (opponent (fromIntegral cr, fromIntegral cg, fromIntegral cb)))
  putStrLn ("octantVoxels (4,4,4)                   = " ++ show (octantVoxels (4, 4, 4)))
  putStrLn ("neighbourCost pd=2 from (2,2,2) ->     = "
            ++ show [ (ax, neighbourCost 2 testField (2,2,2) (ax, w)) | (ax, w) <- neighbours (2,2,2) ])
  putStrLn ""
  putStrLn "V2.1 = the pre-collapse distributional lift of V2. R,G,B are energy curves; the GIF89a is"
  putStrLn "their argmin-energy collapse; we train on the curves; we encode the +/-1 neighbour deltas;"
  putStrLn "L,a,b are the (linear) opponent transform of those deltas; x,y are linear, t is weighted at"
  putStrLn "the per-frame palette delta; the 2x2x2->1+7 lift, S/K, and PonderNet ride the curves."
  where
    verdict True  = "PASS"
    verdict False = "FAIL"

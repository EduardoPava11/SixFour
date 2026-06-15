{- |
Module      : SixFour.Spec.QuartetDelta
Description : Act II — the 4-frame quartet: barycenter "core" + per-colour displacement (motion outline).

The authoring story's second act (`docs/SIXFOUR-PALETTE-STORY-WORKFLOW.md`). The user picks **4 frames**
(the @4⁴@ quartet, @T = 4@). Each palette slot then has a **4-sample OKLab trajectory**. Two readouts:

  * __core__ — the slot's mean (its central colour); the quartet's overall barycenter is "the core of the
    whole". Slots that barely move sit AT the core.
  * __displacement__ — the total OKLab path length over the 3 transitions: @|f1→f2| + |f2→f3| + |f3→f4|@.
    Small ⇒ stable/structural (outline as core); large ⇒ moving (the motion the eye should read).

So __the inter-frame deltas outline the colours closest to the core of the whole__ — the OT motion field
(@v_t = T_{μ̄→μ_t} − x@, see @docs/SIXFOUR-PALETTE-IS-MOTION-WORKFLOW.md@) turned into a per-slot cue. The
core set found here is carried into Act III (@2⁸@ Haar ribbon) as the *protected* leaves.

SIMD-shaped: a slot is a fixed __4-sample__ window (NEON 4-lane); @K@ slots = @K@ vector rows. Cheap enough
to recompute live; in shipping it is precomputed once per quartet.

Contract-first reference in 'Double' (mirrors the 'SixFour.Spec.Collapse' baseline style); a Q16 mirror
follows for the byte-exact device path. Laws are the parity gate (Properties.QuartetDelta).
-}
module SixFour.Spec.QuartetDelta
  ( -- * The quartet
    QSlot(..)
  , quartetFrames
  , toSlots
  , slotTrajectory
    -- * Readouts
  , slotDeltas
  , slotDisplacement
  , slotMean
  , quartetCore
    -- * The core outline (Act II → Act III protect-set)
  , corenessRanked
  , coreColors
  , medianDisplacementThreshold
    -- * Laws (predicates; QuickCheck'd in Properties.QuartetDelta)
  , lawStaticSlotZeroDisplacement
  , lawDisplacementGeqEndpoints
  , lawDeltaCount
  , lawSlotCountPreserved
  , lawCoreMonotoneInThreshold
  , lawCoreIsLowDisplacement
  ) where

import Data.List (sort, sortBy, foldl')
import Data.Ord  (comparing)

import SixFour.Spec.Color (OKLab(..), okLabDistanceSquared)

-- | The number of frames in a quartet — fixed at 4 (the @T@ axis of @4⁴@).
quartetFrames :: Int
quartetFrames = 4

-- | One palette slot's 4-frame OKLab trajectory (f1..f4). Exactly 4 samples — the @T@ window.
data QSlot = QSlot !OKLab !OKLab !OKLab !OKLab
  deriving (Eq, Show)

-- | Zip 4 aligned palettes (each @K@ colours, slot-aligned) into @K@ trajectories. Requires exactly 4
-- palettes of equal length; a malformed input yields @[]@ (caught by 'lawSlotCountPreserved').
toSlots :: [[OKLab]] -> [QSlot]
toSlots [a, b, c, d]
  | sameLen   = zipWith4Q a b c d
  | otherwise = []
  where
    sameLen = let n = length a in all ((== n) . length) [b, c, d]
    zipWith4Q (w:ws) (x:xs) (y:ys) (z:zs) = QSlot w x y z : zipWith4Q ws xs ys zs
    zipWith4Q _ _ _ _                     = []
toSlots _ = []

-- | The 4 samples as a list (f1..f4).
slotTrajectory :: QSlot -> [OKLab]
slotTrajectory (QSlot a b c d) = [a, b, c, d]

-- | The 3 transition distances @[|f1→f2|, |f2→f3|, |f3→f4|]@ (OKLab Euclidean, sqrt of squared).
slotDeltas :: QSlot -> [Double]
slotDeltas (QSlot a b c d) = [dist a b, dist b c, dist c d]

-- | Total path length over the quartet = the slot's motion magnitude. 0 ⇔ the slot never moves.
slotDisplacement :: QSlot -> Double
slotDisplacement = sum . slotDeltas

-- | The slot's central colour: the mean of its 4 samples (its piece of the barycenter).
slotMean :: QSlot -> OKLab
slotMean (QSlot a b c d) = scaleOK 0.25 (a `addOK` b `addOK` c `addOK` d)

-- | The quartet's overall barycenter — "the core of the whole": the mean of all slot means.
quartetCore :: [QSlot] -> OKLab
quartetCore [] = OKLab 0 0 0
quartetCore ss =
  let n = fromIntegral (length ss)
  in scaleOK (1 / n) (foldl' addOK (OKLab 0 0 0) (map slotMean ss))

-- | Slots ranked by displacement, ascending — @(slotIndex, displacement)@. Lowest displacement first =
-- most "core". Ties resolve to the lower slot index (a total, device-stable order).
corenessRanked :: [QSlot] -> [(Int, Double)]
corenessRanked ss =
  sortBy (comparing (\(i, dsp) -> (dsp, i)))
         (zip [0 ..] (map slotDisplacement ss))

-- | The core-colour set: slot indices whose displacement is @<=@ the threshold — the colours the UI
-- outlines as structural / closest to the core, and the protect-set passed to Act III.
coreColors :: Double -> [QSlot] -> [Int]
coreColors thr ss = [ i | (i, dsp) <- zip [0 ..] (map slotDisplacement ss), dsp <= thr ]

-- | The median per-slot displacement — the relative core/motion cut used by the Review overlay and
-- pinned by 'SixFour.Codegen.QuartetDelta' (so the emitter and the Swift port share one rule). On a
-- spread of displacements this guarantees a non-trivial split (some slots core, some motion).
-- Recomputed per quartet; @0@ for the empty quartet.
medianDisplacementThreshold :: [QSlot] -> Double
medianDisplacementThreshold ss =
  let ds = sort (map slotDisplacement ss)
  in if null ds then 0 else ds !! (length ds `div` 2)

--------------------------------------------------------------------------------
-- internal OKLab vector helpers
--------------------------------------------------------------------------------

dist :: OKLab -> OKLab -> Double
dist x y = sqrt (okLabDistanceSquared x y)

addOK :: OKLab -> OKLab -> OKLab
addOK (OKLab l a b) (OKLab l' a' b') = OKLab (l + l') (a + a') (b + b')

scaleOK :: Double -> OKLab -> OKLab
scaleOK s (OKLab l a b) = OKLab (s * l) (s * a) (s * b)

--------------------------------------------------------------------------------
-- Laws (predicates; exercised by Properties.QuartetDelta)
--------------------------------------------------------------------------------

infix 1 ==>
(==>) :: Bool -> Bool -> Bool
p ==> q = not p || q

-- | A slot that holds one colour across all 4 frames has zero displacement (no motion ⇒ pure core).
lawStaticSlotZeroDisplacement :: OKLab -> Bool
lawStaticSlotZeroDisplacement c = slotDisplacement (QSlot c c c c) == 0

-- | The path length never undershoots the straight endpoint distance @|f1→f4|@ (triangle inequality):
-- a slot's measured motion is at least how far it actually got.
lawDisplacementGeqEndpoints :: QSlot -> Bool
lawDisplacementGeqEndpoints s@(QSlot a _ _ d) =
  slotDisplacement s + 1e-9 >= dist a d

-- | A slot has exactly 3 deltas and a 4-sample trajectory (the @T = 4@ window).
lawDeltaCount :: QSlot -> Bool
lawDeltaCount s = length (slotDeltas s) == 3 && length (slotTrajectory s) == quartetFrames

-- | Zipping 4 equal-length palettes yields one slot per colour (no loss, no invention).
lawSlotCountPreserved :: [OKLab] -> [OKLab] -> [OKLab] -> [OKLab] -> Bool
lawSlotCountPreserved a b c d =
  let n = minimum (map length [a, b, c, d])
      a' = take n a; b' = take n b; c' = take n c; d' = take n d
  in length (toSlots [a', b', c', d']) == n

-- | The core set only grows as the threshold rises (monotone): more tolerance ⇒ superset of core colours.
lawCoreMonotoneInThreshold :: [QSlot] -> Bool
lawCoreMonotoneInThreshold ss =
  subsetOf (coreColors 0.05 ss) (coreColors 0.10 ss)
  where subsetOf xs ys = all (`elem` ys) xs

-- | Everything in the core set genuinely has low displacement (≤ threshold) — the outline is honest.
lawCoreIsLowDisplacement :: Double -> [QSlot] -> Bool
lawCoreIsLowDisplacement thr ss =
  thr >= 0 ==>
    all (\i -> slotDisplacement (ss !! i) <= thr) (coreColors thr ss)

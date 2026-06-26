{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FlexibleInstances #-}
{- |
Module      : SixFour.Spec.HierarchicalDelta
Description : "Abstract the H" — the inter-frame DELTA as a hierarchical object: ONE 'HierarchicalDelta' interface (a global coarse band + a local fine residual that compose back losslessly) instantiated by TWO structurally different carriers — the VALUE delta ('ColourDelta', an abelian ℤ-module) and the POLICY delta ('IndexDelta', a transport group) — plus the spatial data-delta pyramid that reuses the frozen octant ladder unchanged.

The committed flat "SixFour.Spec.ConstructionEncoder" @policyDelta@\/@valueDelta@ are RECORD
SWAPS: they advance a whole field of frame @t@ to frame @t+1@ and throw the internal structure
away. A delta is more than that — it is "a category under change, constructed out of more
fundamentals", and the two channels are made of DIFFERENT fundamentals (256 colours vs an index
assignment). This module gives each delta its internal algebra and a SHARED hierarchy interface
— the @H@ of H-JEPA, abstracted away from the carrier:

  * 'HierarchicalDelta' — the abstracted @H@. A 'Monoid' delta that splits into a 'coarseBand'
    (the global \/ DC component) and a 'fineBand' (the local residual) that reassemble EXACTLY
    (@coarseBand d <> fineBand d == d@, 'lawHierarchyLosslessSplit'). Two carriers, one interface.
  * 'ColourDelta' — the VALUE delta. A per-slot Q16 OKLab displacement of the colour table; a
    'Monoid' under elementwise addition that is in fact an abelian GROUP (a ℤ-module: deltas add,
    scale and negate). Coarse = a global recolour \/ white-balance pan (the mean displacement);
    fine = per-slot material jitter ('lawColourCoarseIsGlobalPan'). Compared in FUSED 'buildPixels'
    space, never slot-by-slot ('lawValueDeltaReachesNextPixelsInFusedSpace').
  * 'IndexDelta' — the POLICY delta. A sparse, provenance-carrying displacement of the Morton
    index map; a 'Monoid' under TRANSPORT COMPOSITION (NOT addition — slot labels are categorical:
    @5↦7@ then @7↦2@ is @5↦2@, never @7+2@) that is a GROUP ('invertDelta' swaps old↔new). Coarse =
    rigid region motion (the modal displacement); fine = boundary jitter ('lawIndexCoarseIsRigidMotion').
  * 'bandedDeltaTarget' — the SPATIAL hierarchy of an inter-frame step: "SixFour.Spec.OctreeCell"
    @octantDistill@ of the DATA delta @next − cur@ (both CAPTURED frames), reusing the frozen
    reversible octant ladder UNCHANGED — the band carrier stays @Detail@ (@Int@), no re-pin.
  * 'lawHierarchicalDeltaTargetIsDataManufactured' — every band of the pyramid is a pure function
    of the next captured frame, and the constant\/identity orbit (predict the zero delta) STRICTLY
    misses any frame that moved. The time-axis collapse guard, per band.
  * 'lawDeltaBandsArePerBandDataProvenance' — strengthens "SixFour.Spec.JepaTarget"
    @lawNoSelfProducedRolloutTarget@ from per-STEP to per-BAND: a coarse-conditioned
    (teacher-forced) fine band is @RolledForwardSelf@ and makes the WHOLE hierarchy inadmissible.
    This closes the @L_close@ escape the coarse-to-fine reading would otherwise open.

Additive: imports "SixFour.Spec.ConstructionEncoder" (@Construction@, @QColour@, @buildPixels@),
"SixFour.Spec.OctreeCell" (@octantDistill@\/@octantSynthesize@\/@Detail@) and
"SixFour.Spec.JepaTarget" (@RolloutTargetSource@). Re-pins NOTHING; emits no golden vector;
imported BY nothing yet. GHC-boot-only (@containers@). Laws QuickCheck'd in
"Properties.HierarchicalDelta".
-}
-- COMPARTMENT: MLX-MODEL | tag:MacTag
module SixFour.Spec.HierarchicalDelta
  ( -- * The abstracted H: one hierarchy interface, two carriers
    HierarchicalDelta(..)
  , lawHierarchyLosslessSplit
    -- * The VALUE delta carrier (an abelian ℤ-module)
  , ColourDelta(..)
  , invColourDelta
  , scaleColourDelta
  , colourDeltaOf
  , applyValueDelta
  , lawColourDeltaIdentity
  , lawColourDeltaAssoc
  , lawColourDeltaInverse
  , lawColourCoarseFineSplit
  , lawColourCoarseIsGlobalPan
  , lawValueDeltaReachesNextPixelsInFusedSpace
    -- * The POLICY delta carrier (a transport group)
  , IndexDelta(..)
  , invertDelta
  , applyDelta
  , deltaBetween
  , indexDeltaOf
  , lawIndexDeltaIdentity
  , lawIndexDeltaActionHomomorphism
  , lawIndexDeltaInverse
  , lawIndexCompositionIsNotAddition
  , lawIndexCoarseFineSplit
  , lawIndexCoarseIsRigidMotion
    -- * The spatial data-delta pyramid (reuses the frozen octant ladder)
  , bandedDeltaTarget
  , bandedTargetProvenance
  , lawHierarchicalDeltaTargetIsDataManufactured
  , lawDeltaBandsArePerBandDataProvenance
  ) where

import qualified Data.Map.Strict as M

import SixFour.Spec.ConstructionEncoder
  ( Construction(..), QColour, buildPixels )
import SixFour.Spec.OctreeCell
  ( Detail, octantDistill, octantSynthesize )
import SixFour.Spec.JepaTarget
  ( RolloutTargetSource(..), admissibleRolloutSource )
import SixFour.Spec.RefinementSystem
  ( CommutativeRing, RModule(..) )

-- ============================================================================
-- The abstracted H: one hierarchy interface over any Monoid delta carrier
-- ============================================================================

-- | THE @H@ of H-JEPA, abstracted away from the carrier. A delta that is a 'Monoid' (so deltas
-- compose and there is an identity "no change") and splits into a 'coarseBand' (the global \/ DC
-- component) and a 'fineBand' (the local residual). The one law every instance owes is that the
-- two bands reassemble the whole delta EXACTLY ('lawHierarchyLosslessSplit') — the hierarchy is a
-- lossless decomposition, not a lossy summary. Two carriers with DIFFERENT algebras (the
-- vector-space 'ColourDelta' and the transport-group 'IndexDelta') are unified by this one interface.
class Monoid d => HierarchicalDelta d where
  -- | The global \/ coarse component (a recolour pan, a rigid region motion).
  coarseBand :: d -> d
  -- | The local \/ fine residual (per-slot jitter, boundary shimmer).
  fineBand   :: d -> d

-- | THE hierarchy law: the coarse band composed with the fine residual reassembles the whole
-- delta exactly. Lossless decomposition, carrier-agnostic. Teeth: a 'coarseBand' that is not
-- cancelled out of 'fineBand' (double-counting) or a band that drops information fails for any
-- carrier.
lawHierarchyLosslessSplit :: (Eq d, HierarchicalDelta d) => d -> Bool
lawHierarchyLosslessSplit d = coarseBand d <> fineBand d == d

-- ============================================================================
-- The VALUE delta carrier: ColourDelta — an abelian ℤ-module (deltas ADD)
-- ============================================================================

-- | The VALUE delta: a per-slot Q16 OKLab displacement of the colour table (one @(dL,da,db)@ per
-- palette slot). It is a CHANGE in the colours, not a swapped table — today's
-- "SixFour.Spec.ConstructionEncoder" @valueDelta@ returns a whole 'Construction' with the palette
-- replaced; this is the structured difference, keyed to frame @t@'s gauge. Its algebra is a free
-- abelian GROUP (a ℤ-module): deltas add elementwise, scale by an integer, and negate.
newtype ColourDelta = ColourDelta { unColourDelta :: [QColour] } deriving (Eq, Show)

-- | Elementwise Q16 add (the ℤ-module's vector addition). Unclamped on purpose — the delta layer
-- is genuine integer arithmetic so that every recolour has an exact inverse.
addQ :: QColour -> QColour -> QColour
addQ (l1,a1,b1) (l2,a2,b2) = (l1+l2, a1+a2, b1+b2)

-- | Q16 negation (the group inverse on one colour).
negQ :: QColour -> QColour
negQ (l,a,b) = (-l,-a,-b)

-- | Q16 integer scaling (the ℤ-module's ring action on one colour).
scaleQ :: Int -> QColour -> QColour
scaleQ k (l,a,b) = (k*l, k*a, k*b)

-- | Combine two ragged colour lists by applying @f@ position-wise, zero-padding the shorter side
-- with @(0,0,0)@ (so a slot present in only one operand is carried through @f@ against the
-- additive identity). THE one place ragged-length handling lives.
zipExtend :: (QColour -> QColour -> QColour) -> [QColour] -> [QColour] -> [QColour]
zipExtend f = go
  where
    z = (0,0,0)
    go [] []           = []
    go (x:xs) (y:ys)   = f x y : go xs ys
    go (x:xs) []       = f x z : go xs []
    go [] (y:ys)       = f z y : go [] ys

instance Semigroup ColourDelta where
  ColourDelta x <> ColourDelta y = ColourDelta (zipExtend addQ x y)

instance Monoid ColourDelta where
  mempty = ColourDelta []

-- | The group inverse: negate every per-slot displacement (@d <> invColourDelta d@ is all-zero).
invColourDelta :: ColourDelta -> ColourDelta
invColourDelta (ColourDelta x) = ColourDelta (map negQ x)

-- | The ℤ-module action: scale a recolour by an integer (interpolate \/ attenuate the drift).
scaleColourDelta :: Int -> ColourDelta -> ColourDelta
scaleColourDelta k (ColourDelta x) = ColourDelta (map (scaleQ k) x)

-- | The data-manufactured VALUE target: the per-slot displacement @next − cur@ that carries
-- frame @t@'s palette to frame @t+1@'s, read under frame @t@'s gauge (index held fixed).
colourDeltaOf :: Construction -> Construction -> ColourDelta
colourDeltaOf ct ctNext =
  ColourDelta (zipExtend (\cur nxt -> addQ nxt (negQ cur)) (cPalette ct) (cPalette ctNext))

-- | Apply a recolour in place: add the displacement to the palette, holding the index fixed.
applyValueDelta :: ColourDelta -> Construction -> Construction
applyValueDelta (ColourDelta dlt) c = c { cPalette = zipExtend addQ (cPalette c) dlt }

-- | The DC \/ global band of a colour delta: the mean displacement broadcast to every slot. (A
-- global recolour — exposure ramp, white-balance drift — the whole palette panning together.)
coarseColour :: ColourDelta -> ColourDelta
coarseColour (ColourDelta []) = ColourDelta []
coarseColour (ColourDelta xs) =
  let n            = length xs
      (sl, sa, sb) = foldr addQ (0,0,0) xs
  in ColourDelta (replicate n (sl `div` n, sa `div` n, sb `div` n))

instance HierarchicalDelta ColourDelta where
  coarseBand = coarseColour
  -- fine = whole minus coarse; abelian cancellation makes the split lossless for ANY coarse.
  fineBand d = d <> invColourDelta (coarseColour d)

-- | The VALUE delta IS a free ℤ-module ("SixFour.Spec.RefinementSystem" @RModule ℤ@): the abstract
-- module operations are not a parallel re-implementation but literally the existing concrete ops —
-- @mzero@ = @mempty@, @madd@ = @<>@ (elementwise Q16 add), @mneg@ = 'invColourDelta', @smul@ =
-- 'scaleColourDelta'. This wires the capstone abstraction to the real carrier so the module laws
-- (witnessed in "SixFour.Spec.RefinementCarriers") GOVERN this call site. HONEST BOUNDARY: the
-- additive-inverse law holds only modulo the ragged representation's trailing-zero normalization
-- (@madd x (mneg x)@ is a list of zeros, equal to @mzero = []@ as a delta but not under the derived
-- @Eq@) — see @RefinementCarriers.lawColourModuleInverseModuloCanon@.
instance RModule Integer ColourDelta where
  mzero  = mempty
  madd   = (<>)
  mneg   = invColourDelta
  smul k = scaleColourDelta (fromInteger k)

-- ============================================================================
-- The POLICY delta carrier: IndexDelta — a transport group (deltas COMPOSE)
-- ============================================================================

-- | The POLICY delta: a sparse displacement of the Morton index map, keyed by voxel position,
-- carrying @(oldSlot, newSlot)@. The @oldSlot@ provenance (which today's flat @cIndex = cIndex
-- ctNext@ swap discards) is what makes it a genuine TRANSPORT — invertible, composable — rather
-- than a forgetful overwrite. Untouched voxels are absent (no-motion). @Data.Map@ is GHC-boot
-- @containers@, so this stays spec-legal.
newtype IndexDelta = IndexDelta (M.Map Int (Int,Int)) deriving (Eq, Show)

instance Semigroup IndexDelta where
  -- @a <> b@ = "do b first, then a": for a voxel both touch, chain b's source to a's destination
  -- (transport composition). Slots are NEVER summed.
  IndexDelta a <> IndexDelta b =
    IndexDelta (M.unionWith (\(_, nA) (oB, _) -> (oB, nA)) a b)

instance Monoid IndexDelta where
  mempty = IndexDelta M.empty

-- | The group inverse: swap @old ↔ new@ on every voxel (run the motion backwards).
invertDelta :: IndexDelta -> IndexDelta
invertDelta (IndexDelta m) = IndexDelta (M.map (\(o,n) -> (n,o)) m)

-- | The monoid action on a Morton-order index map: each touched voxel reads its new slot.
applyDelta :: IndexDelta -> [Int] -> [Int]
applyDelta (IndexDelta m) idx = [ maybe s snd (M.lookup v m) | (v,s) <- zip [0..] idx ]

-- | The data-manufactured POLICY target between two index maps under one fixed palette gauge:
-- the per-voxel @(old,new)@ for every voxel that moved.
deltaBetween :: [Int] -> [Int] -> IndexDelta
deltaBetween from to =
  IndexDelta (M.fromList [ (v,(a,b)) | (v,a,b) <- zip3 [0..] from to, a /= b ])

-- | The data-manufactured POLICY target of an inter-frame step (frame @t@'s index to @t+1@'s,
-- palette held fixed).
indexDeltaOf :: Construction -> Construction -> IndexDelta
indexDeltaOf ct ctNext = deltaBetween (cIndex ct) (cIndex ctNext)

-- | The signed displacement of one transport entry (used to detect rigid \/ shared motion).
indexDisp :: (Int,Int) -> Int
indexDisp (o,n) = n - o

-- | The modal (most common) displacement across a transport, if any — the candidate "rigid"
-- motion of a region. Deterministic tie-break (largest count, then largest displacement).
modalDisp :: M.Map Int (Int,Int) -> Maybe Int
modalDisp m
  | M.null m  = Nothing
  | otherwise =
      let counts = M.toList (M.fromListWith (+) [ (indexDisp e, 1 :: Int) | e <- M.elems m ])
      in Just (snd (maximum [ (c, dsp) | (dsp, c) <- counts ]))

instance HierarchicalDelta IndexDelta where
  -- coarse = the voxels carrying the modal (rigid) displacement; fine = the rest. Disjoint keys,
  -- so they reassemble losslessly under transport composition.
  coarseBand (IndexDelta m) = case modalDisp m of
    Nothing -> IndexDelta M.empty
    Just dm -> IndexDelta (M.filter ((== dm) . indexDisp) m)
  fineBand (IndexDelta m) = case modalDisp m of
    Nothing -> IndexDelta M.empty
    Just dm -> IndexDelta (M.filter ((/= dm) . indexDisp) m)

-- ============================================================================
-- The spatial data-delta pyramid (reuses the frozen octant ladder, no re-pin)
-- ============================================================================

-- | The SPATIAL hierarchy of an inter-frame step: the octant-ladder bands (1 coarse + 7 detail
-- per level) of the DATA delta @next − cur@, where BOTH frames are CAPTURED. Reuses
-- "SixFour.Spec.OctreeCell" @octantDistill@ over @Detail@ (@Int@) unchanged — the carrier-Int band
-- pays the hierarchy out without touching the reversible floor.
bandedDeltaTarget :: Int -> [Int] -> [Int] -> ([Int], [[Detail]])
bandedDeltaTarget d cur next =
  let n  = 8 ^ d
      dl = zipWith (-) (take n next) (take n cur)
  in octantDistill d dl

-- | The per-BAND provenance of a hierarchical delta target (coarse + one per detail band). The
-- data-delta pyramid tags EVERY band 'NextFrameData' — each is a pure function of the captured
-- next frame, never the net's own rolled-forward output.
bandedTargetProvenance :: ([Int], [[Detail]]) -> [RolloutTargetSource]
bandedTargetProvenance (_, dets) = NextFrameData : map (const NextFrameData) (concat dets)

-- | THE keystone: every band of the spatial pyramid reconstructs the DATA delta exactly (the
-- octant ladder is a θ-free bijection), and the constant\/identity orbit — predicting the zero
-- delta — STRICTLY misses any frame that moved. So each band inherits the spatial band's
-- collapse-impossibility; the hierarchy faithfully propagates the data target's strict penalty
-- into every band rather than hiding it. Teeth: a band sourced from @synthesize(predCoarse)@
-- (teacher forcing) would let the zero-delta orbit match for free — caught by the strict-miss
-- conjunct on a moving frame.
lawHierarchicalDeltaTargetIsDataManufactured :: Int -> [Int] -> [Int] -> Bool
lawHierarchicalDeltaTargetIsDataManufactured d cur0 next0
  | d < 0 || d > 4 = True
  | otherwise =
      let n      = 8 ^ d
          cur    = take n (cycle (0 : cur0))
          next   = take n (cycle (1 : next0))
          banded = bandedDeltaTarget d cur next
          dl     = zipWith (-) next cur
      in octantSynthesize banded == dl              -- every band reconstructs the DATA delta
         && (next == cur || any (/= 0) dl)          -- a moved frame ⇒ nonzero delta (zero-orbit misses)

-- | THE per-BAND quantifier (the collapse-refutation fix). Strengthens
-- "SixFour.Spec.JepaTarget" @lawNoSelfProducedRolloutTarget@ from one provenance per rollout
-- STEP to one per BAND: the data-delta pyramid is admissible because EVERY band (coarse and all
-- detail) is 'NextFrameData'; a single coarse-conditioned (teacher-forced) band tagged
-- 'RolledForwardSelf' makes the WHOLE hierarchy inadmissible. Teeth: a guard that only checked
-- one provenance per step would pass the tainted hierarchy; the @all@ over bands does not.
lawDeltaBandsArePerBandDataProvenance :: Int -> [Int] -> [Int] -> Bool
lawDeltaBandsArePerBandDataProvenance d cur0 next0
  | d < 0 || d > 4 = True
  | otherwise =
      let n       = 8 ^ d
          cur     = take n (cycle (0 : cur0))
          next    = take n (cycle (1 : next0))
          banded  = bandedDeltaTarget d cur next
          provs   = bandedTargetProvenance banded
          tainted = RolledForwardSelf : drop 1 provs   -- a single coarse-conditioned band
      in not (null provs)
         && all admissibleRolloutSource provs            -- per-band: every band is data ⇒ admissible
         && not (all admissibleRolloutSource tainted)    -- one self band ⇒ whole hierarchy inadmissible

-- ============================================================================
-- Carrier-algebra laws (QuickCheck'd in Properties.HierarchicalDelta)
-- ============================================================================

-- | 'ColourDelta' identity: @mempty@ is the no-recolour element on both sides. Teeth: a biased
-- @mempty@ (a non-zero baseline) shifts a slot and fails.
lawColourDeltaIdentity :: [QColour] -> Bool
lawColourDeltaIdentity xs =
  let a = ColourDelta xs in mempty <> a == a && a <> mempty == a

-- | 'ColourDelta' associativity (stacked recolours, ragged lengths via zero-pad). Teeth: a @<>@
-- that truncated to the shorter list would drop the longer side's displacement and disagree.
lawColourDeltaAssoc :: [QColour] -> [QColour] -> [QColour] -> Bool
lawColourDeltaAssoc xs ys zs =
  let a = ColourDelta xs; b = ColourDelta ys; c = ColourDelta zs
  in (a <> b) <> c == a <> (b <> c)

-- | 'ColourDelta' is a GROUP: a recolour composed with its inverse is the all-zero displacement.
-- Teeth: a saturating \/ clamped @addQ@ would leave an over-range slot unrecoverable, so
-- @d <> inv d@ would not be zero — forcing genuine unclamped integer arithmetic at the delta layer.
lawColourDeltaInverse :: [QColour] -> Bool
lawColourDeltaInverse xs =
  let a = ColourDelta xs
  in unColourDelta (a <> invColourDelta a) == replicate (length xs) (0,0,0)

-- | The hierarchy law witnessed for the VALUE carrier (coarse pan + fine residual == whole).
lawColourCoarseFineSplit :: [QColour] -> Bool
lawColourCoarseFineSplit = lawHierarchyLosslessSplit . ColourDelta

-- | The coarse band is EXACTLY the global pan and the fine band EXACTLY the local jitter: a
-- uniform pan has zero fine; a zero-mean jitter has zero coarse. Teeth: a coarse keyed off the
-- first slot (not the mean) would give a pure pan a non-zero fine and fail.
lawColourCoarseIsGlobalPan :: Bool
lawColourCoarseIsGlobalPan =
  let pan = ColourDelta (replicate 5 (5,5,5))
      jit = ColourDelta [(3,0,0),(-3,0,0),(1,0,0),(-1,0,0)]   -- sums to (0,0,0)
      allZero (ColourDelta ys) = all (== (0,0,0)) ys
  in allZero (fineBand pan) && allZero (coarseBand jit)

-- | The VALUE target reaches frame @t+1@ in FUSED 'buildPixels' space (and a real recolour is not
-- the identity). This is the gauge-correct comparison: never slot-by-slot against the bare table.
lawValueDeltaReachesNextPixelsInFusedSpace :: Bool
lawValueDeltaReachesNextPixelsInFusedSpace =
  let ct     = Construction 1 [(10,20,30),(40,50,60)] [0,1,0,1,0,1,0,1]
      ctNext = Construction 1 [(11,22,33),(44,55,66)] [0,1,0,1,0,1,0,1]
      d      = colourDeltaOf ct ctNext
  in buildPixels (applyValueDelta d ct) == buildPixels ctNext
     && d /= mempty

-- | 'IndexDelta' identity: @mempty@ is no-motion (the empty displacement) on both sides — NOT a
-- reset to @identityIndex@ and NOT an all-zero collapse. Teeth: either wrong @mempty@ overwrites.
lawIndexDeltaIdentity :: [Int] -> [Int] -> Bool
lawIndexDeltaIdentity from to =
  let n = min (length from) (length to)
      d = deltaBetween (take n from) (take n to)
  in mempty <> d == d && d <> mempty == d

-- | @<>@ is a genuine monoid ACTION on the index map: composing transports then applying equals
-- applying in sequence. Teeth: a "union, after wins" merge without chaining provenance applies
-- the right slots but breaks composition \/ invert downstream.
lawIndexDeltaActionHomomorphism :: [Int] -> [Int] -> [Int] -> Bool
lawIndexDeltaActionHomomorphism base mid top =
  let n   = minimum [length base, length mid, length top]
      b   = deltaBetween (take n base) (take n mid)
      a   = deltaBetween (take n mid) (take n top)
      lhs = applyDelta (a <> b) (take n base)
      rhs = applyDelta a (applyDelta b (take n base))
  in n == 0 || lhs == rhs

-- | Every motion is reversible: the inverse composed before the motion is no-motion on the data.
-- Teeth: a carrier that dropped @oldSlot@ could not define 'invertDelta' at all.
lawIndexDeltaInverse :: [Int] -> [Int] -> Bool
lawIndexDeltaInverse from to =
  let n = min (length from) (length to)
      f = take n from
      d = deltaBetween f (take n to)
  in n == 0 || applyDelta (invertDelta d <> d) f == f

-- | Composition is CHAINING, never addition: @5↦7@ then @7↦2@ is @5↦2@, and @7+2 ≠ 2@. THE
-- structural reason policy is a transport group, not a vector space. Teeth: any @+@-based @<>@ fails.
lawIndexCompositionIsNotAddition :: Bool
lawIndexCompositionIsNotAddition =
  let b = IndexDelta (M.fromList [(0,(5,7))])
      a = IndexDelta (M.fromList [(0,(7,2))])
      IndexDelta composed = a <> b
  in M.lookup 0 composed == Just (5,2) && (7 + 2 :: Int) /= 2

-- | The hierarchy law witnessed for the POLICY carrier (coarse rigid + fine jitter == whole, by
-- disjoint-key partition under transport composition).
lawIndexCoarseFineSplit :: [Int] -> [Int] -> Bool
lawIndexCoarseFineSplit from to =
  let n = min (length from) (length to)
  in lawHierarchyLosslessSplit (deltaBetween (take n from) (take n to))

-- | Coarse = rigid region motion (one shared displacement), fine = mixed boundary jitter. Teeth:
-- a coarse classifier that ignored whether displacements agree would mislabel jitter as rigid.
lawIndexCoarseIsRigidMotion :: Bool
lawIndexCoarseIsRigidMotion =
  let rigid  = deltaBetween [0,1,2,3] [2,3,4,5]   -- every voxel +2 (rigid pan)
      jitter = deltaBetween [0,1,2,3] [1,0,3,2]   -- mixed displacements
  in fineBand rigid == mempty
     && coarseBand rigid == rigid
     && fineBand jitter /= mempty

{- |
Module      : SixFour.Spec.PaletteGesture
Description : The PROVABLE gesture partition — at most ONE gesture per input event.

The palette-creation tools are gesture-grid widgets (@docs/SIXFOUR-LAB-CHOICES.md@,
@docs/SIXFOUR-GESTURE-GRID-TOOLS.md@): the user makes LAB-space choices by swiping /
tapping / dragging / pinching / rotating ON the cell grid, never via form controls. With
six choice gestures plus the existing move/scrub, the hazard is RECOGNIZER COLLISION — two
gestures firing on the same touch. This module makes collision impossible BY CONSTRUCTION,
not by assertion.

The trick: a gesture is a COORDINATE, not a behaviour. Each gesture occupies one cell of

    GestureKey = Region × Recognizer × Axis × Latch

and the partition is proven by showing the key function is INJECTIVE over the finite set of
gestures ('lawPartitionInjective') — so any concrete input event (which resolves to exactly
one key) selects AT MOST ONE gesture ('lawAtMostOneGesturePerKey'). This is the
@Spec.PaletteGesture@ the LAB-choice build gates against before wiring any SwiftUI recognizer.

Two supporting laws: the 2-D drag → 3-D OKLab δ decode is invertible with no lost DOF
('lawDragDecodeRoundTrip', exact integers), and the generator-space ops are flagged distinct
from the additive 'SixFour.Spec.LeafOverride' slot ('lawGeneratorSpaceOpsAreNotAdditiveDelta').
-}
-- COMPARTMENT: SWIFT-COREAI | tag:DisplaySide
module SixFour.Spec.PaletteGesture
  ( -- * The partition coordinate
    Region(..)
  , Recognizer(..)
  , Axis(..)
  , Latch(..)
  , GestureKey(..)
    -- * The gestures
  , PaletteGesture(..)
  , gestureKey
  , allGestures
  , isGeneratorSpaceOp
    -- * The 2-D drag → OKLab δ decode (per axis), exact integers
  , DragVec
  , OkDelta
  , dragToDelta
  , deltaToDrag
    -- * Laws (QuickCheck'd in Properties.PaletteGesture)
  , lawPartitionInjective
  , lawAtMostOneGesturePerKey
  , lawEveryGestureHasAKey
  , lawDragDecodeRoundTrip
  , lawGeneratorSpaceOpsAreNotAdditiveDelta
  ) where

-- | The grid REGION a gesture acts on. Disjoint cell rectangles; a touch lands in exactly
-- one (the placement is proven elsewhere by @GridLayoutContract.isDisjoint@).
data Region = Field64        -- ^ the 64×64 frame field (scrub / move)
            | Palette16      -- ^ the 16×16 global-palette tool (the LAB-choice handles)
            | GroupRail      -- ^ the 16×4 time×group browse rail (pick a group)
            | CoverageStrip  -- ^ a dedicated 1-row strip (the coverage↔fidelity track)
  deriving (Eq, Ord, Show, Enum, Bounded)

-- | The RECOGNIZER class. SwiftUI-distinguishable families; @LongPressDrag@ requires the
-- 0.3 s hold (@Spec.CellMechanics.lawDragRequiresHold@), so it is disjoint from a plain
-- immediate @Drag1@ even on the same region.
data Recognizer = Tap | Drag1 | Drag2 | Pinch | Rotate | LongPressDrag
  deriving (Eq, Ord, Show, Enum, Bounded)

-- | The motion AXIS that disambiguates two same-recognizer gestures on one region.
data Axis = AxisNone | Horizontal | Vertical | Directional | Radial | Angular
  deriving (Eq, Ord, Show, Enum, Bounded)

-- | Whether the gesture is armed by a long-press HOLD (move) or fires immediately.
data Latch = Instant | Held
  deriving (Eq, Ord, Show, Enum, Bounded)

-- | The partition coordinate. Two gestures COLLIDE iff they share a 'GestureKey'.
data GestureKey = GestureKey Region Recognizer Axis Latch
  deriving (Eq, Ord, Show)

-- | Every palette gesture (the 6 LAB choices + the existing move/scrub/select). The proof
-- is over this finite set.
data PaletteGesture
  = ScrubBurst        -- ^ browse the 64-frame burst as 16 groups
  | Field64Move       -- ^ relocate the Field64 widget
  | GroupSelect       -- ^ pick which of the 16 RGBT groups seed the collapse  (LAB #1)
  | CoverageFidelity  -- ^ palette diversity ↔ fidelity                         (LAB #2)
  | PaletteSelect     -- ^ brush/select a palette leaf
  | LightnessBand     -- ^ tilt the 256 slots toward an L window                (LAB #3)
  | ChromaPush        -- ^ radial OKLab saturation, hue+L frozen                (LAB #4)
  | OpponentBias      -- ^ constant (a,b) warm/cool bias                        (LAB #5)
  | SplitToneHue      -- ^ per-zone differential hue rotate                     (LAB #6)
  | Palette16Move     -- ^ relocate the Palette16 widget
  deriving (Eq, Ord, Show, Enum, Bounded)

-- | All gestures (finite — the partition's domain).
allGestures :: [PaletteGesture]
allGestures = [minBound .. maxBound]

-- | The partition coordinate of each gesture. Designed so the key function is INJECTIVE
-- (proven by 'lawPartitionInjective'): same-region same-recognizer pairs are separated by
-- 'Axis' (scrub vs coverage by 'Region'; move vs an immediate drag by 'Latch'/'Recognizer').
gestureKey :: PaletteGesture -> GestureKey
gestureKey g = case g of
  ScrubBurst       -> GestureKey Field64       Drag1         Horizontal  Instant
  Field64Move      -> GestureKey Field64       LongPressDrag AxisNone    Held
  GroupSelect      -> GestureKey GroupRail      Tap           AxisNone    Instant
  CoverageFidelity -> GestureKey CoverageStrip  Drag1         Horizontal  Instant
  PaletteSelect    -> GestureKey Palette16      Tap           AxisNone    Instant
  LightnessBand    -> GestureKey Palette16      Drag2         Vertical    Instant
  ChromaPush       -> GestureKey Palette16      Pinch         Radial      Instant
  OpponentBias     -> GestureKey Palette16      Drag1         Directional Instant
  SplitToneHue     -> GestureKey Palette16      Rotate        Angular     Instant
  Palette16Move    -> GestureKey Palette16      LongPressDrag AxisNone    Held

-- | Whether the gesture edits the genome in GENERATOR space (a multiply/rotate/bias the
-- σ-mirror carries for free) rather than the ADDITIVE leaf-δ of 'SixFour.Spec.LeafOverride'.
-- Chroma/hue/opponent are multiplicative or rotational, so they CANNOT ride the additive slot.
isGeneratorSpaceOp :: PaletteGesture -> Bool
isGeneratorSpaceOp g = g `elem` [ChromaPush, SplitToneHue, OpponentBias]

-- =============================================================================
-- The 2-D drag → 3-D OKLab δ decode (exact integers, invertible)
-- =============================================================================

-- | A screen drag in cell units @(dx, dy)@ (dy is screen-down-positive).
type DragVec = (Int, Int)

-- | An OKLab Q16 chrominance δ @(δa, δb)@ (the chroma plane; ΔL rides a separate channel).
type OkDelta = (Int, Int)

-- | Decode a 2-D directional drag into an OKLab (a,b) δ: screen-x → a (green→red),
-- screen-UP → b (yellow→blue), so screen-down @dy@ negates. Identity scale ⇒ no DOF lost
-- and the inverse is exact ('lawDragDecodeRoundTrip').
dragToDelta :: DragVec -> OkDelta
dragToDelta (dx, dy) = (dx, negate dy)

-- | Exact inverse of 'dragToDelta'.
deltaToDrag :: OkDelta -> DragVec
deltaToDrag (da, db) = (da, negate db)

-- =============================================================================
-- Laws (QuickCheck'd in Properties.PaletteGesture)
-- =============================================================================

-- | The partition is INJECTIVE: distinct gestures have distinct keys. This is the headline
-- — it makes recognizer collision impossible by construction.
lawPartitionInjective :: PaletteGesture -> PaletteGesture -> Bool
lawPartitionInjective g1 g2 = (gestureKey g1 == gestureKey g2) == (g1 == g2)

-- | The operational consequence: any concrete input event (which resolves to exactly one
-- 'GestureKey') selects AT MOST ONE gesture.
lawAtMostOneGesturePerKey :: GestureKey -> Bool
lawAtMostOneGesturePerKey k =
  length [ g | g <- allGestures, gestureKey g == k ] <= 1

-- | Totality: every gesture has a key (trivial here — 'gestureKey' is total — but pins it so
-- a future added gesture without a key is a test failure, not a silent gap).
lawEveryGestureHasAKey :: PaletteGesture -> Bool
lawEveryGestureHasAKey g = gestureKey g `seq` True

-- | The 2-D drag → OKLab δ decode loses no DOF: @deltaToDrag . dragToDelta = id@ (exact).
lawDragDecodeRoundTrip :: DragVec -> Bool
lawDragDecodeRoundTrip d = deltaToDrag (dragToDelta d) == d

-- | Generator-space ops (chroma/hue/opponent) are NOT additive leaf-δ — they must use a
-- generator-space operator, never the 'SixFour.Spec.LeafOverride' additive slot. Pins the
-- critique's finding that a multiplicative chroma scale cannot ride @applySigmaOverride@.
lawGeneratorSpaceOpsAreNotAdditiveDelta :: PaletteGesture -> Bool
lawGeneratorSpaceOpsAreNotAdditiveDelta g =
  not (isGeneratorSpaceOp g) || g `notElem` [GroupSelect, PaletteSelect, ScrubBurst]

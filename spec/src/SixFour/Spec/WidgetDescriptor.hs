{- |
Module      : SixFour.Spec.WidgetDescriptor
Description : ONE row per widget — geometry + mechanics + render, folded into a single
              descriptor so "add a widget" is one declaration, not six scattered switches.

A widget's truth is spread across two proof-owners today: "SixFour.Spec.MovableLayout"
(geometry — the 'ColorWidget' class + the disjoint 'move') and
"SixFour.Spec.CellMechanics" (feel — 'mechanicsFor'). Authoring a widget therefore means
editing two modules and six parallel per-identity switches in the codegen. This module
folds them into ONE 'WidgetDescriptor' row, and adds two ORTHOGONAL columns the geometry
proof never reads ('wdRenderMode' / 'wdPaletteScope'), so the unified table can describe
what a widget DRAWS without disturbing 'move' / 'placementScene' / 'isDisjoint'.

== Derived, not duplicated

'descriptorFor' READS the existing owners ('cwFootprint' …, 'mechanicsFor'); it does not
restate their numbers. So the descriptor is a faithful VIEW — 'lawDescriptorMatchesClass'
and 'lawDescriptorMatchesMechanics' prove every field equals its source — and the Phase-2
codegen can emit ONE table that the @MoveContract@ / @CellMechanicsContract@ accessors
delegate to, with @goldenAfter@ / @goldenPulse@ byte-identical (the geometry is the same
numbers, just read through one struct).

== The two new columns

  * 'RenderMode'   — WHAT the widget draws (the GIF field, the 16² palette, the diversity
                     gauge, the compressed GIFC rung). Orthogonal to geometry.
  * 'PaletteScope' — for palette widgets, WHICH palette (per-frame vs the one global table);
                     'ScopeNone' for the image field. 'lawScopeCoherent' ties the two.

GHC-boot-only: base, plus "SixFour.Spec.MovableLayout" / ".CellMechanics".
-}
-- COMPARTMENT: SWIFT-COREAI | tag:DisplaySide
module SixFour.Spec.WidgetDescriptor
  ( -- * What a widget draws (orthogonal to geometry)
    RenderMode(..), allRenderModes, renderModeName, renderModeFor
  , PaletteScope(..), allPaletteScopes, paletteScopeName, paletteScopeFor
    -- * The one row
  , WidgetDescriptor(..)
  , descriptorFor, allDescriptors
    -- * Laws (the descriptor is a faithful view of its owners)
  , lawDescriptorMatchesClass
  , lawDescriptorMatchesMechanics
  , lawDescriptorTotal
  , lawScopeCoherent
  ) where

import SixFour.Spec.MovableLayout
  ( ColorIdentity(..), allIdentities
  , cwFootprint, cwDefaultCol, cwDefaultRow, cwInteractive, cwWidgetId, cwPriority )
import SixFour.Spec.CellMechanics
  ( Mechanics(..), mechanicsFor, PulseSpec, Haptic )

-- =============================================================================
-- The two orthogonal render columns
-- =============================================================================

-- | WHAT a widget draws — orthogonal to its footprint, so the geometry proof never reads
-- it. The closed set the unified renderer switches on (one generic @WidgetView@, Phase 5).
data RenderMode
  = GifField        -- ^ the 64² live preview / committed GIF animation (the image)
  | PaletteGrid     -- ^ the 16² assignable-axis palette grid (≡ the shutter)
  | DiversityGauge  -- ^ the per-frame diversity ring gauge
  | GifcCompressed  -- ^ the 16³ compressed GIFC rung (downsample of the global palette)
  deriving (Eq, Ord, Enum, Bounded, Show)

-- | Every render mode, in 'Enum' order (for the coherence law + table generation).
allRenderModes :: [RenderMode]
allRenderModes = [minBound .. maxBound]

-- | Stable cross-language token for a render mode.
renderModeName :: RenderMode -> String
renderModeName GifField       = "gifField"
renderModeName PaletteGrid    = "paletteGrid"
renderModeName DiversityGauge = "diversityGauge"
renderModeName GifcCompressed = "gifcCompressed"

-- | The render mode of each closed identity (the as-built assignment).
renderModeFor :: ColorIdentity -> RenderMode
renderModeFor Field64       = GifField
renderModeFor Palette16     = PaletteGrid
renderModeFor DiversityRing = DiversityGauge

-- | For a palette-bearing widget, WHICH palette it reads; 'ScopeNone' for the image field.
data PaletteScope
  = ScopeNone      -- ^ not a palette widget (the GIF image itself)
  | ScopePerFrame  -- ^ this frame's own 256-colour palette
  | ScopeGlobal    -- ^ the one global palette table (GIFB / GIFC)
  deriving (Eq, Ord, Enum, Bounded, Show)

-- | Every palette scope, in 'Enum' order.
allPaletteScopes :: [PaletteScope]
allPaletteScopes = [minBound .. maxBound]

-- | Stable cross-language token for a palette scope.
paletteScopeName :: PaletteScope -> String
paletteScopeName ScopeNone     = "none"
paletteScopeName ScopePerFrame = "perFrame"
paletteScopeName ScopeGlobal   = "global"

-- | The default palette scope of each identity ('lawScopeCoherent' ties it to the render
-- mode). The runtime may still flip a palette widget per-frame↔global; this is the seed.
paletteScopeFor :: ColorIdentity -> PaletteScope
paletteScopeFor Field64       = ScopeNone        -- the image, not a palette
paletteScopeFor Palette16     = ScopePerFrame
paletteScopeFor DiversityRing = ScopePerFrame

-- =============================================================================
-- The one row
-- =============================================================================

-- | ONE widget's full declaration: geometry (folded from 'ColorWidget'), feel (folded
-- from 'Mechanics'), and the two render columns. Built by 'descriptorFor', which READS
-- the owners rather than restating them — so it is a faithful view, proven by the laws.
data WidgetDescriptor = WidgetDescriptor
  { wdIdentity     :: !ColorIdentity
  , wdFootprint    :: !(Int, Int)   -- ^ (w, h) cells — from 'cwFootprint'
  , wdDefaultCol   :: !Int          -- ^ dock column (atoms) — from 'cwDefaultCol'
  , wdDefaultRow   :: !Int          -- ^ dock row (atoms) — from 'cwDefaultRow'
  , wdInteractive  :: !Bool         -- ^ touch target? — from 'cwInteractive'
  , wdWidgetId     :: !Int          -- ^ owner id — from 'cwWidgetId'
  , wdPriority     :: !Int          -- ^ contest tiebreak — from 'cwPriority'
  , wdHoldTicks    :: !Int          -- ^ long-press ticks — from 'mcHoldTicks'
  , wdLiftHaptic   :: !Haptic       -- ^ lift pop — from 'mcLiftHaptic'
  , wdTickEvery    :: !Int          -- ^ detent coarseness — from 'mcTickEvery'
  , wdPulse        :: !PulseSpec     -- ^ resting pulse — from 'mcPulse'
  , wdRenderMode   :: !RenderMode    -- ^ WHAT it draws — from 'renderModeFor'
  , wdPaletteScope :: !PaletteScope  -- ^ WHICH palette — from 'paletteScopeFor'
  } deriving (Eq, Show)

-- | Build the descriptor for one identity by READING its owners (no restated numbers).
descriptorFor :: ColorIdentity -> WidgetDescriptor
descriptorFor i = WidgetDescriptor
  { wdIdentity     = i
  , wdFootprint    = cwFootprint i
  , wdDefaultCol   = cwDefaultCol i
  , wdDefaultRow   = cwDefaultRow i
  , wdInteractive  = cwInteractive i
  , wdWidgetId     = cwWidgetId i
  , wdPriority     = cwPriority i
  , wdHoldTicks    = mcHoldTicks m
  , wdLiftHaptic   = mcLiftHaptic m
  , wdTickEvery    = mcTickEvery m
  , wdPulse        = mcPulse m
  , wdRenderMode   = renderModeFor i
  , wdPaletteScope = paletteScopeFor i
  }
  where m = mechanicsFor i

-- | The whole table, one row per identity (Enum order — the deterministic key order the
-- codegen and the disjoint scene both rely on).
allDescriptors :: [WidgetDescriptor]
allDescriptors = map descriptorFor allIdentities

-- =============================================================================
-- Laws — the descriptor is a faithful view of its owners
-- =============================================================================

-- | Every GEOMETRY field of 'descriptorFor' equals its 'ColorWidget' source. This is what
-- lets Phase-2 codegen read geometry through the ONE table without moving any number — so
-- @placementScene@ / @move@ / @goldenAfter@ stay byte-identical.
lawDescriptorMatchesClass :: Bool
lawDescriptorMatchesClass = all ok allIdentities
  where
    ok i = let d = descriptorFor i in
         wdFootprint   d == cwFootprint   i
      && wdDefaultCol  d == cwDefaultCol  i
      && wdDefaultRow  d == cwDefaultRow  i
      && wdInteractive d == cwInteractive i
      && wdWidgetId    d == cwWidgetId    i
      && wdPriority    d == cwPriority    i

-- | Every FEEL field of 'descriptorFor' equals its 'mechanicsFor' source — so the unified
-- table reproduces 'SixFour.Spec.CellMechanics' (hold / detent / pulse) exactly.
lawDescriptorMatchesMechanics :: Bool
lawDescriptorMatchesMechanics = all ok allIdentities
  where
    ok i = let d = descriptorFor i; m = mechanicsFor i in
         wdHoldTicks  d == mcHoldTicks  m
      && wdLiftHaptic d == mcLiftHaptic m
      && wdTickEvery  d == mcTickEvery  m
      && wdPulse      d == mcPulse      m

-- | The table covers exactly the closed identity set, one row each, keyed by identity —
-- no missing or duplicated widget.
lawDescriptorTotal :: Bool
lawDescriptorTotal =
     length allDescriptors == length allIdentities
  && and [ wdIdentity (descriptorFor i) == i | i <- allIdentities ]

-- | Render mode and palette scope agree: the GIF image carries 'ScopeNone'; every
-- palette-bearing mode carries a REAL scope. Catches a row that claims to show a palette
-- but names no source (or vice versa).
lawScopeCoherent :: Bool
lawScopeCoherent = all ok allIdentities
  where
    ok i = let d = descriptorFor i in case wdRenderMode d of
      GifField -> wdPaletteScope d == ScopeNone
      _        -> wdPaletteScope d /= ScopeNone

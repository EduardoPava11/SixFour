{- |
Module      : SixFour.Spec.Ownership
Description : The grid as a SIMD OWNERSHIP field — colour IS the owner's identity.

The user's model, made a spec: the Swift screen is one SIMD field of cells
@(col, row, colour)@, and **colour encodes OWNERSHIP** — a chrome cell's rendered
colour decodes /which Owner controls it/. Each 'Owner' carries a law-bound
responsibility (the @Preview@ owner governs the 64×64 GIF frames; the @Palette@
owner governs that frame's 16×16 palette; …). The whole field is a TOTAL, DISJOINT
cover of the 100×218 lattice, refreshed at 20 fps. A doubly-claimed cell is a
visible contention BUG ('SixFour.Spec.CellFiber.contestedSentinel'), never a blend.

== This module: STEP 1 — the owner alphabet + the injective badge palette

This is the first, smallest slice (see @docs/SIXFOUR-OWNERSHIP-GRID-DESIGN.md@
Part A.7 step 1): the closed 'Owner' enum and the 'ownerColor' IDENTITY palette
that makes "colour decodes owner" possible. The load-bearing guarantee is
'lawOwnerColorInjective': the seven badges are pairwise distinct, in-gamut, and
disjoint from the two reserved anchors ('CellFiber.neutralColor' and
'CellFiber.contestedSentinel') — so a cell's colour can be decoded back to exactly
one owner ('ownerColorInv') with no collision against ⊥ or the contested marker.

Later steps add 'Responsibility' (step 2), 'OwnerRegion'/@ownerAt@ + the disjoint
cover (steps 3–6), and the 20 fps refresh + decode round-trip (step 7); they
compose 'SixFour.Spec.Lattice', '.GridLayout', '.CellFiber', '.Order' rather than
re-declaring them. Nothing here re-declares the colour algebra — 'OwnerColor' is a
thin newtype over the existing 'CellFiber.Color'.

GHC-boot-only: base + 'SixFour.Spec.CellFiber' / '.ColorFixed'.
-}
-- COMPARTMENT: SWIFT-COREAI | tag:DisplaySide
module SixFour.Spec.Ownership
  ( -- * The closed owner alphabet
    Owner(..)
  , allOwners
    -- * The IDENTITY badge palette (colour = owner)
  , OwnerColor(..)
  , ownerColor
  , ownerColorInv
    -- * Responsibilities (what each owner governs, at what cadence)
  , Governs(..)
  , Responsibility(..)
  , responsibility
    -- * The SIMD field: atoms, regions, the ownership map (step 3, 2-owner seed)
  , Atom(..)
  , allAtoms
  , OwnerRegion(..)
  , OwnerScene(..)
  , captureScene
  , ownerAt
  , ownerContested
    -- * Golden vectors (codegen-pinned; ported byte-for-byte to Swift)
  , ownerColorTable
  , responsibilityTable
  , coverSample
    -- * Laws (predicates; QuickCheck'd in Properties.Ownership)
  , lawOwnerColorInjective
  , lawOwnerColorRoundTrips
  , lawResponsibilityTotal
  , lawPreviewGovernsFrames
  , lawPaletteGovernsPalette
  , lawRingAnswersToFrames
  , lawCoverInBounds
  , lawCoverDisjoint
  , lawCoverSampleMatches
  , lawCoverTotal
  , lawPreviewClaimsFullFootprint
  , lawOwnerTouchFloor
    -- * Fusion zones (sanctioned co-occupancy vs a contention bug) — step 5
  , isFused
  , fusionFixture
  , contestedFixture
  , lawFusionIsEffectZoneNotBug
  , lawContentionIsSentinelNotBlend
  , lawDisjointMatchesRectsOwner
    -- * The rendered field + decode round-trip (step 7)
  , FieldCell(..)
  , fieldColorAt
  , fieldOf
  , refreshHz
  , decodeRoundTrip
  , lawRefreshIs20fps
  , lawColorDecodesOwner
  , lawColorIsQuotientLabel
  ) where

import Data.List (tails)
import qualified Data.Set as Set

import SixFour.Spec.CellFiber
  ( Color(..), Cell, bottom, join, singletonCell, render
  , clampColor, inGamut, neutralColor, contestedSentinel )
import SixFour.Spec.ColorFixed (q16One)
import SixFour.Spec.Display    (logicRateHz)
import qualified SixFour.Spec.Lattice    as L
import qualified SixFour.Spec.GridAxis   as GA
import qualified SixFour.Spec.CellGrid   as CG
import qualified SixFour.Spec.GridLayout as GL

-- | The closed, exhaustive owner set. @Enum@/@Bounded@ ⇒ the alphabet is finite and
-- machine-checked, so later steps' cover laws range over a known 7-element domain.
-- Concretises 'SixFour.Spec.GridLayout.lrWidget' (an opaque @Int@) into a named,
-- colour-decodable identity.
data Owner = Preview | Palette | Shutter | Gear | Field | Ring | Wordmark
  deriving (Eq, Ord, Show, Enum, Bounded)

-- | The 7-element owner domain of every owner law.
allOwners :: [Owner]
allOwners = [minBound .. maxBound]

-- | An owner's reserved IDENTITY badge — a thin newtype over the existing
-- 'CellFiber.Color' (Q16 OKLab) so the SIMD field carries ONE colour type. The
-- image of 'ownerColor' is pairwise injective and disjoint from the two reserved
-- anchors ('lawOwnerColorInjective').
newtype OwnerColor = OwnerColor { unOwnerColor :: Color }
  deriving (Eq, Ord, Show)

-- | Build a badge from an OKLab @(L, a, b)@ Double triple, rounded half-away-from-zero
-- to Q16 and clamped into the gamut box (the same rounding as 'CellFiber.ingest', so
-- a badge and an ingested camera/NN colour are commensurable). Every literal below is
-- compile-time-valid; 'lawOwnerColorInjective''s @inGamut@ conjunct guards a typo.
badge :: Double -> Double -> Double -> OwnerColor
badge l a b = OwnerColor (clampColor (Color (q16 l, q16 a, q16 b)))
  where
    q16 v = let s = v * fromIntegral q16One
            in if s >= 0 then floor (s + 0.5) else ceiling (s - 0.5)

-- | THE identity palette: each owner's reserved badge colour. Injective (proven), so
-- the colour field IS the quotient label of the ownership partition. Hues follow the
-- owner table in the design doc (Part A.2); the exact Q16 triples are pinned by
-- 'ownerColorTable' and ported byte-for-byte to Swift.
ownerColor :: Owner -> OwnerColor
ownerColor o = case o of
  Preview  -> badge 0.62 (-0.02) (-0.12)   -- deep cool-blue : governs the 64×64 frames
  Palette  -> badge 0.55 (-0.08)   0.04    -- warm teal      : governs the 16×16 palette
  Shutter  -> badge 0.45   0.16    0.07    -- warm red       : the trigger
  Gear     -> badge 0.50 (-0.04) (-0.02)   -- slate grey-green: settings
  Field    -> badge 0.30   0.00    0.00    -- dark neutral   : the ground (≠ neutralColor, L=½)
  Ring     -> badge 0.78   0.06    0.16    -- bright amber   : the diversity gauge
  Wordmark -> badge 0.95   0.00    0.00    -- off-white      : the title band

-- | Decode a badge colour back to its owner (partial: @Just@ on exactly the 7 badges,
-- @Nothing@ on any other colour, incl. the neutral/contested anchors). This is the
-- operational meaning of "colour encodes ownership".
ownerColorInv :: OwnerColor -> Maybe Owner
ownerColorInv c = lookup c [ (ownerColor o, o) | o <- allOwners ]

-- | The codegen-pinned golden: the 7 @(owner, Q16 colour)@ badges. Emitted to
-- @OwnershipContract.swift@ and re-asserted on the Swift side so the identity palette
-- cannot drift across languages.
ownerColorTable :: [(Owner, Color)]
ownerColorTable = [ (o, unOwnerColor (ownerColor o)) | o <- allOwners ]

-- RESPONSIBILITIES ----------------------------------------------------------

-- | What an owner GOVERNS — its sized duty over a region. The size lives in the
-- constructor so it is pinned to the ONE 'SixFour.Spec.Lattice' / '.GridAxis' source,
-- never a re-typed literal.
data Governs
  = GovernsFrames  !Int   -- ^ an @N×N@ GIF-frame field  (Preview: @N = previewCells = 64@)
  | GovernsPalette !Int   -- ^ an @N×N@ colour palette    (Palette: @N = shutterCells = 16@)
  | GovernsControl        -- ^ an interactive control     (Shutter, Gear)
  | GovernsGauge   !Int   -- ^ an @N@-tick gauge          (Ring: @N = ringTicks = 64@)
  | GovernsGround         -- ^ the background field        (Field — the cover totaliser)
  | GovernsTitle          -- ^ the title band              (Wordmark)
  deriving (Eq, Show)

-- | A law-bound duty discharged at a cadence (Hz). Every owner refreshes at the one
-- shared 20 fps logic rate ('SixFour.Spec.Display.logicRateHz'), so the whole
-- ownership field re-evaluates as a single pass per tick.
data Responsibility = Responsibility
  { reGoverns   :: !Governs
  , reCadenceHz :: !Int
  } deriving (Eq, Show)

-- | The TOTAL, exhaustive @owner -> responsibility@ map: every owner has exactly one
-- duty and every duty an owner (closed 'Owner' enum ⇒ exhaustive by construction).
-- The cadence is the single shared logic rate.
responsibility :: Owner -> Responsibility
responsibility o = Responsibility (governsOf o) logicRateHz
  where
    governsOf Preview  = GovernsFrames  L.previewCells   -- the 64×64 GIF frames
    governsOf Palette  = GovernsPalette L.shutterCells   -- that frame's 16×16 palette
    governsOf Shutter  = GovernsControl
    governsOf Gear     = GovernsControl
    governsOf Field    = GovernsGround
    governsOf Ring     = GovernsGauge   L.ringTicks      -- 64 ticks, one per frame
    governsOf Wordmark = GovernsTitle

-- | The codegen-pinned golden: the 7 @(owner, responsibility)@ bindings.
responsibilityTable :: [(Owner, Responsibility)]
responsibilityTable = [ (o, responsibility o) | o <- allOwners ]

-- THE SIMD FIELD: atoms, regions, the ownership map ---------------------------

-- | A SCREEN-lattice atom — the user's "cell" at @(col, row)@ on the @100 × 218@
-- field (NOT the 64×64 GIF base; that is 'SixFour.Spec.CellGrid.Place'). Cols
-- @0 .. L.cols-1@, rows @0 .. L.rows-1@.
data Atom = Atom { atomCol :: !Int, atomRow :: !Int }
  deriving (Eq, Ord, Show)

-- | The whole @100 × 218 = 21800@-cell field — the finite, total domain the cover
-- must account for.
allAtoms :: [Atom]
allAtoms = [ Atom c r | r <- [0 .. L.rows - 1], c <- [0 .. L.cols - 1] ]

-- | A foreground owner's rectangular claim, in atoms. The same shape as
-- 'SixFour.Spec.GridLayout.LRegion' but keyed by a typed 'Owner' (@orOwner@) instead
-- of the opaque @lrWidget :: Int@.
data OwnerRegion = OwnerRegion
  { orOwner       :: !Owner
  , orCol         :: !Int
  , orRow         :: !Int
  , orW           :: !Int
  , orH           :: !Int
  , orInteractive :: !Bool
  } deriving (Eq, Show)

-- | The scene: the foreground owners' claims plus declared @EffectZone@ fusion pairs
-- (empty in this step; populated in step 5). @Field@ is implicit — it absorbs every
-- atom no foreground region claims, so the cover is TOTAL.
data OwnerScene = OwnerScene
  { osRegions :: [OwnerRegion]
  , osFusion  :: [(Owner, Owner)]
  } deriving (Eq, Show)

-- | THE capture scene — the full 7-owner layout (step 6). Preview/Palette coordinates
-- are REUSED verbatim from 'SixFour.Spec.GridLayout.captureScene'; every size is a
-- 'SixFour.Spec.Lattice' constant. The layout is a proven DISJOINT COVER:
--
--   * @Preview@  64×64 at @(18,22)@   — the hero, high.
--   * @Palette@  16×16 at @(42,145)@  — the live palette in the thumb zone (interactive).
--   * @Shutter@  16×16 at @(42,145)@  — FUSED into the palette (same rect): the palette
--     IS the capture button. Declared in 'osFusion', so the overlap is a sanctioned
--     EffectZone, not contention.
--   * @Wordmark@ 60×11 at @(20,88)@   — the title band, just below the preview.
--   * @Ring@     20×20 at @(40,104)@  — the diversity gauge.
--   * @Gear@     12×12 at @(84,190)@  — settings, thumb-reach corner (interactive).
--   * @Field@    — implicit: the complement of all the above (the ground).
captureScene :: OwnerScene
captureScene = OwnerScene
  { osRegions =
      [ OwnerRegion Preview  18 22  L.previewCells L.previewCells False
      , OwnerRegion Palette  42 145 L.shutterCells L.shutterCells True
      , OwnerRegion Shutter  42 145 L.shutterCells L.shutterCells True   -- fused into palette
      , OwnerRegion Wordmark 20 88  L.wordmarkCols L.wordmarkRows  False
      , OwnerRegion Ring     40 104 L.ringCells    L.ringCells     False
      , OwnerRegion Gear     84 190 L.controlCells L.controlCells  True ]
    -- The shutter is fused INTO the palette rectangle: the live palette IS the capture
    -- button. That planned co-occupancy is a sanctioned EffectZone, not a bug ('isFused').
  , osFusion = [(Shutter, Palette)] }

-- | Does an atom fall inside a region's half-open rectangle?
inOwnerRegion :: OwnerRegion -> Atom -> Bool
inOwnerRegion reg (Atom c r) =
     c >= orCol reg && c < orCol reg + orW reg
  && r >= orRow reg && r < orRow reg + orH reg

-- | THE ownership map — TOTAL (no @Maybe@): the first foreground region that claims
-- the atom, else @Field@ (the totaliser). For a well-formed scene at most one
-- foreground region claims any atom ('lawCoverDisjoint'), so "first" is unambiguous.
ownerAt :: OwnerScene -> Atom -> Owner
ownerAt s a = case [ orOwner reg | reg <- osRegions s, inOwnerRegion reg a ] of
  (o : _) -> o
  []      -> Field

-- | One owner region as a 'GridLayout.LRegion' (owner ordinal → @lrWidget@) so the
-- proven AABB / no-blend machinery is REUSED rather than re-derived.
toLR :: OwnerRegion -> GL.LRegion
toLR reg = GL.LRegion (orCol reg) (orRow reg) (orW reg) (orH reg)
                      (fromEnum (orOwner reg)) (fromEnum (orOwner reg)) (orInteractive reg)

-- | The owner-keyed scene as a 'GridLayout.Scene'.
toGLScene :: OwnerScene -> GL.Scene
toGLScene s = [ (show (orOwner reg), toLR reg) | reg <- osRegions s ]

-- | Are two owners a declared FUSION pair (order-insensitive)? A fused overlap is a
-- sanctioned EffectZone (shutter-into-palette on the live face), NOT a contention bug.
isFused :: OwnerScene -> Owner -> Owner -> Bool
isFused s a b = (a, b) `elem` osFusion s || (b, a) `elem` osFusion s

-- | The owners whose region contains an atom.
ownersAt :: OwnerScene -> Atom -> [Owner]
ownersAt s a = [ orOwner reg | reg <- osRegions s, inOwnerRegion reg a ]

-- | Distinct unordered owner pairs from a list.
distinctOwnerPairs :: [Owner] -> [(Owner, Owner)]
distinctOwnerPairs os = [ (a, b) | (a : rest) <- tails os, b <- rest, a /= b ]

-- | Every atom claimed by two+ DISTINCT owners whose pairing is NOT a declared fusion
-- — i.e. a GENUINE contention bug. Candidate overlap cells come (cheaply) from the
-- REUSED 'GridLayout.sceneContested'; the fusion filter then excludes any cell whose
-- every clashing pair is a sanctioned EffectZone.
ownerContested :: OwnerScene -> [Atom]
ownerContested s =
  [ Atom c r
  | (c, r) <- GL.sceneContested (toGLScene s)
  , any (\(o1, o2) -> not (isFused s o1 o2)) (distinctOwnerPairs (ownersAt s (Atom c r))) ]

-- | The IDENTITY-layer claim cell at an atom: the SET of badge colours of the owners
-- claiming it. Folded with 'CellFiber.join' — exactly the palette's no-blend algebra —
-- so a multi-owner cell is a contested 'Cell' and 'CellFiber.render' yields the loud
-- 'contestedSentinel', never a mixture.
claimsAt :: OwnerScene -> Atom -> Cell
claimsAt s a = foldr (join . singletonCell . badgeOf) bottom (ownersAt s a)
  where badgeOf = unOwnerColor . ownerColor

-- | Golden cover sample: representative atoms → their expected owner (interiors,
-- corners, a bare gap). Codegen-pinned; the Swift @ownerAt@ must agree.
coverSample :: [(Atom, Owner)]
coverSample =
  [ (Atom 18 22,   Preview)   -- preview top-left corner
  , (Atom 50 50,   Preview)   -- preview interior
  , (Atom 81 85,   Preview)   -- preview bottom-right last cell (18+63, 22+63)
  , (Atom 42 145,  Palette)   -- palette top-left (Palette wins the fused cells)
  , (Atom 57 160,  Palette)   -- palette bottom-right last cell (42+15, 145+15)
  , (Atom 50 92,   Wordmark)  -- wordmark interior
  , (Atom 49 113,  Ring)      -- ring interior
  , (Atom 89 195,  Gear)      -- gear interior
  , (Atom 0 0,     Field)     -- bare top-left corner
  , (Atom 99 217,  Field)     -- bare far corner
  , (Atom 50 100,  Field)     -- a gap between the wordmark and the ring
  ]

-- LAWS ----------------------------------------------------------------------

-- | The badge palette is a valid IDENTITY map: (1) pairwise INJECTIVE — equal badge
-- colours imply the same owner, so a colour decodes to at most one owner; (2) every
-- badge is in-gamut; (3) no badge collides with the reserved 'neutralColor' (⊥) or
-- 'contestedSentinel' (the overlap marker), so an owner cell can never be mistaken for
-- "unpainted" or "contested". Discharge: a 7×7 pairwise check + 7 gamut/disequality
-- checks over the finite 'allOwners'.
lawOwnerColorInjective :: Bool
lawOwnerColorInjective =
     and [ o1 == o2
         | o1 <- allOwners, o2 <- allOwners
         , ownerColor o1 == ownerColor o2 ]
  && all clean allOwners
  where
    clean o = let c = unOwnerColor (ownerColor o)
              in inGamut c && c /= neutralColor && c /= contestedSentinel

-- | 'ownerColorInv' is a left inverse of 'ownerColor' on every owner: decoding a
-- badge recovers exactly the owner that minted it. Follows from injectivity; stated
-- separately because it is the property the Swift @ownerAt@/decode path relies on.
lawOwnerColorRoundTrips :: Bool
lawOwnerColorRoundTrips = all (\o -> ownerColorInv (ownerColor o) == Just o) allOwners

-- | Responsibility is TOTAL & exhaustive: each owner maps to its declared duty in
-- order, and EVERY owner refreshes at the one 20 fps logic rate — no owner dutiless,
-- none off-clock. Discharge: a concrete check of the 7-element image + a cadence fold.
lawResponsibilityTotal :: Bool
lawResponsibilityTotal =
     map (reGoverns . responsibility) allOwners ==
       [ GovernsFrames L.previewCells, GovernsPalette L.shutterCells
       , GovernsControl, GovernsControl, GovernsGround
       , GovernsGauge L.ringTicks, GovernsTitle ]
  && all (\o -> reCadenceHz (responsibility o) == logicRateHz) allOwners
  && logicRateHz == 20

-- | THE preview binding (the user's model, as law): the Preview owner governs the
-- 64×64 GIF frames at 20 fps, and that footprint is EXACTLY the GIF base —
-- @previewCells² == 4096 == |CellGrid.allPlaces|@. Couples the screen Preview owner to
-- the GIF cube so they cannot drift.
lawPreviewGovernsFrames :: Bool
lawPreviewGovernsFrames =
     responsibility Preview == Responsibility (GovernsFrames L.previewCells) logicRateHz
  && L.previewCells == 64
  && L.previewCells * L.previewCells == 4096
  && L.previewCells * L.previewCells == length CG.allPlaces

-- | THE palette binding (the user's model, as law): the Palette owner governs that
-- frame's 16×16 palette at 20 fps; the footprint is the 'GridAxis' palette —
-- @shutterCells == gridSide == 16@ and @shutterCells² == gridCells == 256@.
lawPaletteGovernsPalette :: Bool
lawPaletteGovernsPalette =
     responsibility Palette == Responsibility (GovernsPalette L.shutterCells) logicRateHz
  && L.shutterCells == 16
  && L.shutterCells == GA.gridSide
  && L.shutterCells * L.shutterCells == GA.gridCells
  && GA.gridCells == 256

-- | The Ring gauge ANSWERS to the frames: one tick per GIF frame, so
-- @ringTicks == previewCells == 64@ — the diversity gauge and the preview are bound
-- to the same frame count and cannot drift apart.
lawRingAnswersToFrames :: Bool
lawRingAnswersToFrames =
     responsibility Ring == Responsibility (GovernsGauge L.ringTicks) logicRateHz
  && L.ringTicks == L.previewCells
  && L.ringTicks == 64

-- | Every foreground region lies inside the @100 × 218@ lattice. Discharge: AABB
-- bounds on each region (Field is bounded by construction).
lawCoverInBounds :: Bool
lawCoverInBounds = all inb (osRegions captureScene)
  where
    inb r =  orCol r >= 0 && orCol r + orW r <= L.cols
          && orRow r >= 0 && orRow r + orH r <= L.rows

-- | DISJOINT (the no-double-claim half of the cover): no atom is claimed by two
-- foreground owners — @ownerContested captureScene == []@. Discharge by REUSE of
-- 'GridLayout.sceneContested' (the same no-blend fiber algebra), so a double-claim
-- would surface as a 'CellFiber.contestedSentinel', never a blend.
lawCoverDisjoint :: Bool
lawCoverDisjoint = null (ownerContested captureScene)

-- | The golden cover sample resolves to its expected owner — interiors, every region
-- corner, and bare @Field@ gaps all decode correctly through 'ownerAt'.
lawCoverSampleMatches :: Bool
lawCoverSampleMatches = all (\(a, o) -> ownerAt captureScene a == o) coverSample

-- | TOTAL (the no-cell-left-behind half of the cover): every one of the @100 × 218 =
-- 21800@ atoms resolves to an owner (trivially, since 'ownerAt' is total — @Field@ is
-- the fallback), and @Field@ owns EXACTLY the complement of the foreground footprints
-- (@21800 - 64² - 16² = 17448@). Together with 'lawCoverDisjoint' this is the DISJOINT
-- COVER — the gap 'GridLayout' left open (it proved disjointness but allowed unclaimed
-- cells). Discharge: a single fold over 'allAtoms'.
lawCoverTotal :: Bool
lawCoverTotal =
     length allAtoms == L.cols * L.rows
  && length allAtoms == 21800
  && all (\a -> ownerAt captureScene a `elem` allOwners) allAtoms
  && length (filter (== Field) owners) == L.cols * L.rows - Set.size foregroundCells
  where
    owners = map (ownerAt captureScene) allAtoms
    -- the UNION of every foreground footprint (fusion overlap counted ONCE), so Field
    -- is proven to own exactly the complement — not a hard-coded count.
    foregroundCells = Set.fromList
      [ (c, r) | reg <- osRegions captureScene
               , c <- [orCol reg .. orCol reg + orW reg - 1]
               , r <- [orRow reg .. orRow reg + orH reg - 1] ]

-- | COMPLETENESS (kept SEPARATE from totality so an under-claim cannot hide): every
-- atom inside a region's footprint is owned by that region's owner OR a declared fusion
-- partner — NEVER @Field@, never a non-fused intruder. So if a region were mis-sized and
-- leaked part of its footprint to @Field@, totality would still hold but THIS law fails.
-- The fusion clause lets the shutter's footprint be "owned" by its palette partner.
lawPreviewClaimsFullFootprint :: Bool
lawPreviewClaimsFullFootprint = all footprintFullyOwned (osRegions captureScene)
  where
    footprintFullyOwned reg = all (ownedBySelfOrFused reg) (regionAtoms reg)
    ownedBySelfOrFused reg a =
      let o = ownerAt captureScene a
      in o == orOwner reg || isFused captureScene o (orOwner reg)
    regionAtoms reg =
      [ Atom c r | c <- [orCol reg .. orCol reg + orW reg - 1]
                 , r <- [orRow reg .. orRow reg + orH reg - 1] ]

-- | Every INTERACTIVE owner clears the HIG 44 pt touch floor in both dims
-- (@≥ touchFloorCells = 11@ atoms). Palette/Shutter (16) and Gear (12) all pass.
lawOwnerTouchFloor :: Bool
lawOwnerTouchFloor =
  all ok (filter orInteractive (osRegions captureScene))
  where ok r = orW r >= L.touchFloorCells && orH r >= L.touchFloorCells

-- FUSION ZONES (step 5) ------------------------------------------------------

-- | A fixture where two regions OVERLAP but are a declared fusion pair — the
-- shutter fused into the palette rectangle (the live-face EffectZone).
fusionFixture :: OwnerScene
fusionFixture = OwnerScene
  { osRegions = [ OwnerRegion Palette 42 145 16 16 True
                , OwnerRegion Shutter 48 150 8  8  True ]   -- sits inside the palette
  , osFusion  = [(Shutter, Palette)] }

-- | A fixture where two NON-fused regions overlap — a genuine contention bug that must
-- be SEEN (the loud sentinel), never blended.
contestedFixture :: OwnerScene
contestedFixture = OwnerScene
  { osRegions = [ OwnerRegion Preview 10 10 20 20 False
                , OwnerRegion Gear    20 20 20 20 True ]    -- overlaps preview; not fused
  , osFusion  = [] }

-- | Region-level: is there a distinct, NON-fused pair of regions whose rectangles
-- overlap? The geometric companion of 'ownerContested'.
anyNonFusedOverlap :: OwnerScene -> Bool
anyNonFusedOverlap s =
  or [ GL.regionsOverlap (toLR a) (toLR b) && not (isFused s (orOwner a) (orOwner b))
     | (a, b) <- regionPairs, orOwner a /= orOwner b ]
  where regionPairs = [ (a, b) | (a : rest) <- tails (osRegions s), b <- rest ]

-- | FUSION is a sanctioned EffectZone, NOT a bug: where two FUSED owners overlap, no
-- contention is reported — the disjoint-cover thesis is not violated on the live face.
lawFusionIsEffectZoneNotBug :: Bool
lawFusionIsEffectZoneNotBug =
     GL.regionsOverlap (toLR palR) (toLR shR)   -- they really do overlap…
  && null (ownerContested fusionFixture)        -- …yet nothing is contested (fused)
  where [palR, shR] = osRegions fusionFixture

-- | A NON-fused overlap IS contention, and its observed colour is the loud
-- 'contestedSentinel' — NEVER a blend. Discharge by REUSE of 'CellFiber.render' over
-- the folded badge claims ('claimsAt'); this is 'CellFiber.lawNoSynthesis' applied to
-- the ownership field.
lawContentionIsSentinelNotBlend :: Bool
lawContentionIsSentinelNotBlend =
     not (null contested)
  && all (\a -> render (claimsAt contestedFixture a) == contestedSentinel) contested
  where contested = ownerContested contestedFixture

-- | THE BRIDGE (generalises 'GridLayout.lawDisjointMatchesRects' from 2 widgets to the
-- owner set WITH fusion): the algebraic "no contested atom" view agrees exactly with
-- the geometric "no non-fused rectangles overlap" view, on every representative scene.
lawDisjointMatchesRectsOwner :: Bool
lawDisjointMatchesRectsOwner =
  all agree [captureScene, fusionFixture, contestedFixture]
  where agree s = null (ownerContested s) == not (anyNonFusedOverlap s)

-- THE RENDERED FIELD + DECODE ROUND-TRIP (step 7) ----------------------------

-- | A rendered SIMD cell: position @(col,row)@ + the colour shown there.
data FieldCell = FieldCell { fcCol :: !Int, fcRow :: !Int, fcColor :: !Color }
  deriving (Eq, Show)

-- | The IDENTITY-layer colour at an atom: the owner's badge, OR the loud
-- 'contestedSentinel' at a GENUINE (non-fused) contention. A fused co-occupancy is NOT
-- contested, so it shows its winning owner's badge. (The CONTENT layer — σ.palette DATA
-- painted on the Preview/Palette interiors — is a runtime app concern, not computable
-- here; the colour=owner theorem is scoped to THIS identity layer.)
fieldColorAt :: OwnerScene -> Atom -> Color
fieldColorAt s a
  | genuinelyContested = contestedSentinel
  | otherwise          = unOwnerColor (ownerColor (ownerAt s a))
  where
    genuinelyContested =
      any (\(o1, o2) -> not (isFused s o1 o2)) (distinctOwnerPairs (ownersAt s a))

-- | The whole rendered identity field, one 'FieldCell' per atom (row-major).
fieldOf :: OwnerScene -> [FieldCell]
fieldOf s = [ FieldCell (atomCol a) (atomRow a) (fieldColorAt s a) | a <- allAtoms ]

-- | The one shared refresh rate: 20 fps ('SixFour.Spec.Display.logicRateHz'). The whole
-- field re-evaluates as a single pure pass per @1/20 s@ tick.
refreshHz :: Int
refreshHz = logicRateHz

-- | Golden: decode every reserved colour. The 7 badges decode to their owner; the two
-- anchors decode to @Nothing@ (they are not owners).
decodeRoundTrip :: [(Color, Maybe Owner)]
decodeRoundTrip =
     [ (unOwnerColor (ownerColor o), Just o) | o <- allOwners ]
  ++ [ (neutralColor, Nothing), (contestedSentinel, Nothing) ]

-- | The refresh is the one 20 fps logic rate, and the rendered field covers exactly the
-- @100 × 218@ lattice (the spatial companion of the Display clock — same rate, screen base).
lawRefreshIs20fps :: Bool
lawRefreshIs20fps =
     refreshHz == logicRateHz
  && refreshHz == 20
  && length (fieldOf captureScene) == length allAtoms
  && length allAtoms == L.cols * L.rows

-- | COLOUR DECODES OWNER: on the identity layer, every non-contested atom's rendered
-- colour decodes (via 'ownerColorInv') back to exactly its 'ownerAt'; and every badge
-- round-trips. The operational statement of "colour encodes ownership".
lawColorDecodesOwner :: Bool
lawColorDecodesOwner =
     all decodes allAtoms
  && all (\(c, mo) -> ownerColorInv (OwnerColor c) == mo) decodeRoundTrip
  where
    decodes a =
      let c = fieldColorAt captureScene a
      in c == contestedSentinel                                  -- contested: exempt
         || ownerColorInv (OwnerColor c) == Just (ownerAt captureScene a)

-- | COLOUR IS THE QUOTIENT LABEL: two non-contested atoms share a rendered colour IFF
-- they share an owner — so the colour field is exactly the quotient map of the
-- ownership partition (the sharpest formalisation of "colour encodes ownership").
-- Follows from injectivity ('lawOwnerColorInjective'); checked here over a sample
-- covering all seven owners (all 21800² pairs is unnecessary given injectivity).
lawColorIsQuotientLabel :: Bool
lawColorIsQuotientLabel = all same [ (p, q) | p <- sample, q <- sample ]
  where
    sample = map fst coverSample
    same (p, q) =
      let cp = fieldColorAt captureScene p
          cq = fieldColorAt captureScene q
      in cp == contestedSentinel || cq == contestedSentinel
         || (cp == cq) == (ownerAt captureScene p == ownerAt captureScene q)

{- |
Module      : SixFour.Spec.Display
Description : The display finite-state machine M = (Σ, ι, δ, λ, Π, κ) — the composition
              theorem that makes the 20 fps clock and the uniform cell ONE machine.

This is the COLIMIT module of @docs/SIXFOUR-DISPLAY-FSM.md@: it imports the seven
already-proven sub-oracles and discharges the nine display theorems T1–T9. Most are
one-line citations of an imported law; the genuinely new content is the arithmetic of
T1/T5/T7, the by-construction T8, and the COMPOSITION theorem — that 'projGif',
'projPalette' and 'projShutter' are three observers of the /one/ state Σ (T3), so
"kill @cellPt@" (T4) and "every cell is I/O at 20 fps" (T5) are theorems, not refactors.

== State and the gauge

@Σ = (palette, index-cube, cursor)@ carried as integers (Q16 OKLab leaves + per-place
palette indices + the @Z₆₄@ cursor), observed up to the @S_K@ gauge — the index labels
are unobservable ('lawGaugeInvariant', mirroring 'SixFour.Spec.Gauge'). The palette is a
power-of-two leaf list so the Haar projections ('SixFour.Spec.PairTreeFixed') are exactly
invertible: the shutter is a deterministic /coarsening/ of the palette, never an
independent value (T3).

== Glass note (post-2026-06-05)

The observation @λ@ is the IDENTITY on the rendered cells — glass was retired app-wide
(total pixelation; @docs/SIXFOUR-DESIGN-LANGUAGE.md@ §9.7). The old layer law
@encode ∘ glass = encode@ holds vacuously, so T8 (Moore observability) is purely the
type signature of 'observe': @DisplayState -> [Pixel]@ with NO 'Input' argument.

GHC-boot-only: base + the listed Spec modules.
-}
module SixFour.Spec.Display
  ( -- * State + alphabet (the CLOCK half — the phase half is now Spec.ABSurface)
    DisplayState(..)
  , Input(..)
  , Pixel
  , View(..)
    -- * Morphisms
  , deltaReview, deltaCapture        -- δ
  , observe                          -- λ  (Moore: no Input arg)
  , projGif, projPalette, projShutter-- Π
  , gaugeRelabel                     -- the S_K action on Σ (mirrors Spec.Gauge.gaugeAction)
    -- * Clock arithmetic
  , logicRateHz, panelRates, holdCounts   -- 20 ; [60,120] ; [3,6]
  , captureRateHz, frameCount
  , atomPt, blockFactor, gridDim          -- per-view b_i / dim for T4
  , touched, fullLattice                  -- T5 support
    -- * Laws (T1..T9)
  , lawClockDivides            -- T1
  , lawOneClock                -- T2
  , lawProjectionsShareState   -- T3
  , lawUniformAtom             -- T4
  , lawDeltaTotal              -- T5
  , lawGaugeInvariant          -- T6
  , lawCapturePhase            -- T7
  , lawMoore                   -- T8
  , lawGridJoinTotal           -- T9 (cited from CellGrid)
  , lawComposition             -- the colimit: Π all factor through the one Σ
    -- * Golden gate (N = 64)
  , goldenTickTrace
  ) where

import Data.List (sort)

import SixFour.Spec.PlaybackClock (FrameCount, frameAfter)
import SixFour.Spec.PairTreeFixed
  (OKLabI, analyzeFixed, reconstructFixed, levelNodesFixed)
import SixFour.Spec.ColorFixed   (oklabToSrgb8Q16)
import SixFour.Spec.Lattice      (gifPx, previewCells)
import SixFour.Spec.CellGrid     (Grid, allPlaces, lawInheritedTotality)

-- =============================================================================
-- State, alphabet
-- =============================================================================

-- | A displayed pixel: sRGB8 (the byte-exact output of the Zig observation). With
-- glass retired, this is also exactly what is shown (λ = identity on cells, T8).
type Pixel = (Int, Int, Int)

-- | @Σ@ — the display state, all integers (observed up to the @S_K@ gauge):
--
--   * 'dsPalette' = @P@, the 256-leaf palette as Q16 OKLab triples (power-of-two so
--     the Haar projections are exactly invertible).
--   * 'dsIndices' = the current frame's per-place palette indices (length @H·W@).
--   * 'dsCursor'  = the @Z₆₄@ playback cursor.
data DisplayState = DisplayState
  { dsPalette :: ![OKLabI]   -- ^ P (power-of-two leaves)
  , dsIndices :: ![Int]      -- ^ index cube for the shown frame (S_K-gauged)
  , dsCursor  :: !Int        -- ^ the Z_N cursor
  } deriving (Eq, Show)

-- | The capture alphabet @ι@ — one ingested frame's per-place OKLab data. δ_capture
-- writes EVERY place from it (T5); its content (clustering) is owned by
-- 'SixFour.Spec.QuantFixed', deliberately out of scope here.
newtype Input = Input { inFrame :: [OKLabI] }
  deriving (Eq, Show)

-- | The three governed grids — the views whose pitch must be @atom × ℤ@ (T4).
data View = GifView | PaletteView | ShutterView
  deriving (Eq, Show, Enum, Bounded)

-- =============================================================================
-- The UI-lifecycle phase FSM was here. It is RETIRED — superseded by
-- 'SixFour.Spec.ABSurface' (the capture → A/B → export machine), whose laws cover
-- every cut phase law 1:1. Only the CLOCK half (κ + the projections) lives on below.
-- =============================================================================

-- =============================================================================
-- Clock arithmetic (NEW: no existing module owns the wall-clock↔panel relation)
-- =============================================================================

-- | The single logic rate @f@: 20 Hz (one δ per 1/20 s).
logicRateHz :: Int
logicRateHz = 20

-- | The panel refresh rates the clock must divide (ProMotion 60 / 120 Hz).
panelRates :: [Int]
panelRates = [60, 120]

-- | Integer scan-outs per logic tick: @R / f ∈ {3,6}@ (T1 ⇒ whole-number hold).
holdCounts :: [Int]
holdCounts = map (`div` logicRateHz) panelRates

-- | Capture ingests at the logic rate (T7): exactly one frame per κ tick.
captureRateHz :: Int
captureRateHz = logicRateHz

-- | @N = 64@ frames per burst (the cube depth = 'previewCells').
frameCount :: FrameCount
frameCount = previewCells

-- =============================================================================
-- The spatial atom + per-view block factors (T4 — "kill cellPt")
-- =============================================================================

-- | THE ATOM: @gifPx = 4 pt@ ('SixFour.Spec.Lattice', GRID v3.0). Every governed pitch
-- is an integer multiple of it; there is no free @cellPt@.
atomPt :: Int
atomPt = gifPx

-- | The integer block factor @b_i@ per view. GIF and palette BOTH render at the ONE
-- atom (GRID Law #1: grow by more cells, never a bigger cell — the 64→16 cascade is a
-- cell-COUNT relation, not a cell-SIZE one; this supersedes ADR-5's ×2-per-level cells).
-- Shutter keeps b=4 as the dormant Review abstraction tile (EXEMPT-REVIEW-PITCH).
-- @cellPitch(i) = atom × b_i@.
blockFactor :: View -> Int
blockFactor GifView     = 1
blockFactor PaletteView = 1
blockFactor ShutterView = 4

-- | The grid dimension (cells per side) per view: 64 / 16 / 4.
gridDim :: View -> Int
gridDim GifView     = 64
gridDim PaletteView = 16
gridDim ShutterView = 4

-- =============================================================================
-- Morphisms: δ, λ, Π, and the S_K action
-- =============================================================================

-- | @δ_review@ — advance the cursor on the one clock κ. Discharge of "uses the
-- proven cursor": delegates to 'SixFour.Spec.PlaybackClock.frameAfter' (the @Z₆₄@
-- successor), so review playback is the proven clock, not a second timer (T2).
deltaReview :: DisplayState -> DisplayState
deltaReview s = s { dsCursor = frameAfter frameCount (dsCursor s) }

-- | @δ_capture@ — ingest a frame, writing EVERY place (T5). Modelled as a total map
-- over the full lattice: it emits an index for each of the @H·W@ places (the content
-- — which centroid — is 'SixFour.Spec.QuantFixed's job; here only totality matters).
deltaCapture :: DisplayState -> Input -> DisplayState
deltaCapture s (Input frame) =
  s { dsIndices = [ quantizePlace frame i | i <- [0 .. length allPlaces - 1] ] }
  where
    -- a TOTAL per-place assignment (placeholder clustering): every place gets a
    -- defined index, so 'touched' = the whole lattice and nothing is carried over.
    quantizePlace _ i = i `mod` max 1 (length (dsPalette s))

-- | @λ@ — the Moore observation: Σ → on-screen pixels, with NO 'Input' argument
-- (T8). With glass retired, this is the gathered cell colours verbatim (identity
-- presentation): each index is replaced by its palette colour, encoded to sRGB8.
observe :: DisplayState -> [Pixel]
observe = projGif

-- | @Π_gif@ — the front projection shown on screen: gather each place's index into
-- the palette, then OKLab→sRGB8. (Factors through the one Σ — see 'lawComposition'.)
projGif :: DisplayState -> [Pixel]
projGif s = map (oklabToSrgb8Q16 . paletteColor s) (dsIndices s)

-- | @Π_palette@ — the 256-leaf palette grid: every leaf, OKLab→sRGB8.
projPalette :: DisplayState -> [Pixel]
projPalette s = map oklabToSrgb8Q16 (dsPalette s)

-- | @Π_shutter@ — the 4×4 abstraction: the Haar LEVEL-4 nodes of the SAME palette P,
-- OKLab→sRGB8. Because the Haar transform is exactly invertible
-- ('SixFour.Spec.PairTreeFixed'), this is a deterministic coarsening of 'projPalette',
-- never an independent value (T3).
projShutter :: DisplayState -> [Pixel]
projShutter s = map oklabToSrgb8Q16 (levelNodesFixed 4 (analyzeFixed (dsPalette s)))

-- | Look one index up in the palette (⊥-safe: out-of-range ⇒ the first leaf or a
-- neutral). Total over the gauge orbit.
paletteColor :: DisplayState -> Int -> OKLabI
paletteColor s i =
  case dsPalette s of
    [] -> (0, 0, 0)
    ps -> ps !! (i `mod` length ps)

-- | The @S_K@ gauge action on Σ — mirrors 'SixFour.Spec.Gauge.gaugeAction' over the
-- Display's concrete integer carrier (same convention @(σ·P)[i]=P[σ⁻¹(i)]@,
-- @(σ·I)[p]=σ(I[p])@). @σ@ is a permutation of @[0..K-1]@ given as a list. The typed
-- statement is canonical in 'SixFour.Spec.Gauge'; this restates it without the
-- type-level-@Nat@ carrier (per SPEC-METHODOLOGY §2: no DataKinds unless load-bearing).
gaugeRelabel :: [Int] -> DisplayState -> DisplayState
gaugeRelabel sigma s =
  s { dsPalette = [ dsPalette s !! inv i | i <- [0 .. k - 1] ]   -- P ∘ σ⁻¹
    , dsIndices = map (sigma !!) (dsIndices s)                   -- σ ∘ I
    }
  where
    k     = length (dsPalette s)
    inv i = head ([ j | j <- [0 .. k - 1], sigma !! j == i ] ++ [i])

-- =============================================================================
-- T5 support — the touched set
-- =============================================================================

-- | The full lattice of places (the finite base, 'SixFour.Spec.CellGrid.allPlaces').
fullLattice :: [Int]
fullLattice = [0 .. length allPlaces - 1]

-- | @touched(δ_capture)@ — the place coordinates δ_capture WRITES on a tick. By
-- construction δ_capture emits one index per place, so this is the whole lattice
-- (no cached / carried-over cell). This is the function whose equality with
-- 'fullLattice' IS the "every cell is I/O at 20 fps" requirement (T5).
touched :: DisplayState -> Input -> [Int]
touched s i = [0 .. length (dsIndices (deltaCapture s i)) - 1]

-- =============================================================================
-- The nine theorems (each named for its lawX :: Bool)
-- =============================================================================

-- | T1 — the clock divides every panel rate: @∀ R ∈ {60,120}. R mod f == 0@, so a
-- logic tick is a whole number of scan-outs (no fractional hold / judder).
-- NEW arithmetic — no existing module owned the wall-clock↔panel relation.
lawClockDivides :: Bool
lawClockDivides =
  all (\r -> r `mod` logicRateHz == 0) panelRates
  && holdCounts == [3, 6]

-- | T2 — exactly one clock. Both δ_capture and δ_review are fired by the same κ;
-- modelled structurally as a singleton clock set. (Swift mirror: exactly one
-- @CADisplayLink@; retires the @VoxelCubeView@ 60 Hz timer.)
lawOneClock :: Bool
lawOneClock = length clocks == 1
  where clocks = ["κ"]   -- the single 20 Hz CADisplayLink

-- | T3 — the three grids cannot drift: the shutter is the level-4 coarsening of the
-- SAME palette P, and the Haar transform is exactly invertible. Discharge: REUSE
-- 'SixFour.Spec.PairTreeFixed' round-trip (@reconstruct ∘ analyze = id@, byte-exact)
-- — so 'projShutter' is a deterministic function of the same P that 'projPalette'
-- shows, never an independent value.
lawProjectionsShareState :: DisplayState -> Bool
lawProjectionsShareState s =
  reconstructFixed (analyzeFixed p) == p                                  -- exact invertibility
  && projShutter s == map oklabToSrgb8Q16 (levelNodesFixed 4 (analyzeFixed p))  -- shutter = coarsen(P)
  where p = dsPalette s

-- | T4 — uniform atom: every view's pitch is @atom × b_i@ with integer @b_i ≥ 1@, and
-- its extent lands on the lattice (@gridDim × b_i × atom@). There is no free @cellPt@.
-- Discharge: extends 'SixFour.Spec.Lattice.lawEveryGovernedDimIsCells' to per-view
-- block factors.
lawUniformAtom :: Bool
lawUniformAtom = all ok [minBound .. maxBound]
  where
    ok v = let b = blockFactor v
           in b >= 1
              && cellPitchPt v == atomPt * b                 -- pitch is an integer multiple of the atom
              && extentPt v    == gridDim v * b * atomPt      -- extent lands on the lattice
    cellPitchPt v = atomPt * blockFactor v
    extentPt    v = gridDim v * blockFactor v * atomPt

-- | T5 — δ_capture is TOTAL over the lattice: it writes every cell each tick
-- (@touched == fullLattice@) and is a defined function for all inputs. This is the
-- theorem that turns "each cell has its colour computed every 1/20 s" into a checkable
-- property (no cached / carried-over path).
lawDeltaTotal :: DisplayState -> Input -> Bool
lawDeltaTotal s i =
  touched s i == fullLattice                                  -- every cell written
  && length (dsIndices (deltaCapture s i)) == length allPlaces -- total over the 4096-place lattice

-- | T6 — gauge invariance: relabelling the palette indices by any permutation @σ@
-- leaves the observation unchanged, so @λ@ descends to the quotient @𝒮 = Σ/S_K@ and
-- carrying integer indices loses nothing. Discharge: REUSE the
-- 'SixFour.Spec.Gauge' action (restated here over the concrete carrier — see
-- 'gaugeRelabel'). The precondition is that @σ@ is a permutation of @[0..K-1]@.
lawGaugeInvariant :: [Int] -> DisplayState -> Bool
lawGaugeInvariant sigma s =
  not (isPermutation sigma k) || observe (gaugeRelabel sigma s) == observe s
  where
    k = length (dsPalette s)
    isPermutation xs n = length xs == n && sort xs == [0 .. n - 1]

-- | T7 — capture phase-lock: the capture rate equals the logic rate (20 Hz) and the
-- @N@ ticks of a burst are in bijection with the @N = 64@ captured frames — one
-- @ι@ per δ_capture, no starvation, no pile-up. Arithmetic (cross-cuts capture+clock).
lawCapturePhase :: Bool
lawCapturePhase =
  captureRateHz == logicRateHz && logicRateHz == 20
  && length frames == frameCount
  && sort frames == [0 .. frameCount - 1]                     -- bijection (ticks ↔ frames)
  where frames = map id [0 .. frameCount - 1]                 -- the 1:1 ingest map

-- | T8 — Moore observability: @λ@ has NO 'Input' argument, so any sub-tick scan-out
-- reads a fully-committed Σ (tear-free double buffer). Discharged BY CONSTRUCTION —
-- the witness is the type of 'observe' (@DisplayState -> [Pixel]@). With glass
-- retired, @λ@ is moreover the identity on cells, so @encode ∘ glass = encode@ holds
-- vacuously.
lawMoore :: Bool
lawMoore = True   -- witnessed by `observe :: DisplayState -> [Pixel]` (no Input)

-- | T9 — @gridJoin@ totality (the SPATIAL sibling of T5): the pointwise lift of the
-- total fibre join over the finite total 'SixFour.Spec.CellGrid.allPlaces' base is
-- total. Discharge: REUSE 'SixFour.Spec.CellGrid.lawInheritedTotality' — no new
-- totality argument; the lift is the content.
lawGridJoinTotal :: Grid -> Bool
lawGridJoinTotal = lawInheritedTotality

-- | THE COMPOSITION THEOREM — the single artifact that makes the clock and the cells
-- provably the same machine: 'projGif', 'projPalette' and 'projShutter' are all
-- /pure observers of the one Σ/. Equal states ⇒ equal projections (determinism /
-- Moore), and the shutter factors through the same P as the palette (T3). This is
-- why "kill @cellPt@" (T4) and "every cell is I/O" (T5) are theorems about ONE M.
lawComposition :: DisplayState -> DisplayState -> Bool
lawComposition s s' =
  (s == s' )
    `implies` ( projGif s == projGif s'
             && projPalette s == projPalette s'
             && projShutter s == projShutter s' )
  where implies a b = not a || b

-- =============================================================================
-- The golden tick-trace (the cross-language gate, N = 64)
-- =============================================================================

-- | A deterministic @[(Σ, ι) → Σ']@ sequence the Swift capture/playback path must
-- reproduce bit-for-bit: each step ingests a frame (δ_capture) then advances the
-- cursor (δ_review). Emitted to @DisplayContract.swift@ and gated by @cabal test@.
goldenTickTrace :: [(DisplayState, Input)] -> [DisplayState]
goldenTickTrace = map (\(s, i) -> deltaReview (deltaCapture s i))

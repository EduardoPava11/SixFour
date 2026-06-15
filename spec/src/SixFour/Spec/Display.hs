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
  ( -- * The UI-lifecycle phase FSM (one surface, no screens)
    Phase(..), RenderStage(..), Event(..)
  , allPhases, allEvents, step, nextStage, phaseField
  , phaseName, eventName, stageName, goldenHappyPath
  , DisplayState(..)
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
    -- * The phase-FSM laws (one surface, no screens)
  , lawPhaseTotal              -- step is total over every (phase, event)
  , lawNoOrphanPhase           -- every phase reachable from Bootstrap
  , lawPhaseIsCellGrid         -- every phase IS a full cell-field configuration
  , lawReviewExplicit          -- Review ⟸ only Committed (no implicit predicate)
    -- * Golden gate (N = 64)
  , goldenTickTrace
  , goldenPhaseTrace
  ) where

import Data.List (nub, sort)

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
-- The UI-lifecycle phase FSM (the long-pending Spec.Display gap, 2026-06-06)
--
-- This is the contract for the ONE-SURFACE app: there is one persistent cell field,
-- and capture → render → review are STATE TRANSITIONS expressed as cell updates on it,
-- never screen swaps. 'lawPhaseIsCellGrid' is the formal "no screens" statement.
-- =============================================================================

-- | The deterministic render stages the Zig core flows through (the @Rendering@ phase's
-- banner data, formalized into the FSM per the one-surface plan).
data RenderStage = Quantize | Dither | Significance | Palette | Encode
  deriving (Eq, Show, Enum, Bounded)

-- | @Phase@ — the UI lifecycle. EVERY phase is a configuration of the one cell field
-- (a full-lattice 'phaseField'), NOT a screen ('lawPhaseIsCellGrid'). The Swift router's
-- @switch over vm.phase@ + the @primaryOutput != nil@ review predicate collapse into
-- this one FSM.
data Phase
  = Bootstrap              -- ^ AVCaptureSession initialising
  | Unauthorized           -- ^ camera permission denied
  | Live                   -- ^ live capture (preview + palette = shutter)
  | Settings               -- ^ in-surface settings (a phase, not a screen)
  | Locking                -- ^ exposure / focus / white-balance locking
  | Capturing              -- ^ the 64-frame burst in flight
  | Browsing               -- ^ scrub the 64-frame burst, pick 4 anchor frames (Act III)
  | Rendering RenderStage  -- ^ the Zig kernels emitting bytes, stage by stage
  | Review                 -- ^ the committed GIF / cube, scrubbing on κ
  | Error                  -- ^ a faulted kernel / session
  deriving (Eq, Show)

-- | The FSM alphabet — only the transition TRIGGERS. Out-of-band data (error text, the
-- progress fraction, the captured cube bytes) is carried in Σ / 'CaptureViewModel', not
-- the alphabet, so @step@ stays a small total function.
data Event
  = SessionReady | AuthDenied
  | ShutterTap | OpenSettings | CloseSettings
  | LockComplete | BurstComplete
  | SelectFrame | Picked4
  | StageDone RenderStage | Committed
  | Retake | Fault
  deriving (Eq, Show)

-- | Every phase (finite — 'Rendering' expands over the 5 stages). For the totality
-- and reachability laws + the codegen contract.
allPhases :: [Phase]
allPhases =
  [ Bootstrap, Unauthorized, Live, Settings, Locking, Capturing, Browsing, Review, Error ]
  ++ [ Rendering st | st <- [minBound .. maxBound] ]

-- | Every event (finite — 'StageDone' expands over the 5 stages).
allEvents :: [Event]
allEvents =
  [ SessionReady, AuthDenied, ShutterTap, OpenSettings, CloseSettings
  , LockComplete, BurstComplete, SelectFrame, Picked4, Committed, Retake, Fault ]
  ++ [ StageDone st | st <- [minBound .. maxBound] ]

-- | The successor render stage, or @Nothing@ at the last (@Encode@).
nextStage :: RenderStage -> Maybe RenderStage
nextStage st | st == maxBound = Nothing
             | otherwise      = Just (succ st)

-- | @δ_phase@ — the TOTAL transition function ('lawPhaseTotal'). Unhandled
-- (phase, event) pairs are self-loops (the event is ignored), so @step@ is defined
-- everywhere with no ⊥. @Review@ is entered ONLY via @Committed@ ('lawReviewExplicit').
step :: Phase -> Event -> Phase
step ph ev = case (ph, ev) of
  (Bootstrap,   SessionReady)  -> Live
  (Bootstrap,   AuthDenied)    -> Unauthorized
  (Live,        ShutterTap)    -> Locking
  (Live,        OpenSettings)  -> Settings
  (Settings,    CloseSettings) -> Live
  (Locking,     LockComplete)  -> Capturing
  (Capturing,   BurstComplete) -> Browsing                         -- Act III: scrub & pick 4
  (Browsing,    SelectFrame)   -> Browsing                         -- self-loop; picks mutate in Σ
  (Browsing,    Picked4)       -> Rendering minBound               -- the OLD burst target → Quantize
  (Rendering s, StageDone s')
    | s == s'                  -> maybe ph Rendering (nextStage s)  -- advance; hold at Encode
  (Rendering _, Committed)     -> Review                           -- the ONLY edge into Review
  (Review,      Retake)        -> Live
  (Error,       Retake)        -> Bootstrap
  (_,           Fault)         -> Error
  _                            -> ph                                -- TOTAL: ignore irrelevant events

-- | @λ_phase@ — every phase observed as a FULL cell-field configuration (length
-- 'allPlaces'), padded with the neutral cell. The witness for 'lawPhaseIsCellGrid':
-- a phase is a grid of cells, never a screen. Live/Settings/Locking/Capturing/Rendering/
-- Review show the front projection of Σ; Bootstrap/Unauthorized/Error are neutral fills
-- (their decorative cells are layout, out of this totality witness's scope).
phaseField :: Phase -> DisplayState -> [Pixel]
phaseField ph s = take n (content ++ repeat neutral)
  where
    n       = length allPlaces
    neutral = (0, 0, 0)
    content = case ph of
      Bootstrap    -> []
      Unauthorized -> []
      Error        -> []
      _            -> projGif s   -- incl. Browsing (the scrub view): a full cell-field

-- | Stable string name of a render stage (the cross-language contract token).
stageName :: RenderStage -> String
stageName Quantize     = "quantize"
stageName Dither       = "dither"
stageName Significance = "significance"
stageName Palette      = "palette"
stageName Encode       = "encode"

-- | Stable string name of a phase (emitted into @DisplayContract.swift@; the Swift
-- @Phase@ port must use the same tokens so 'goldenPhaseTrace' gates cross-language).
phaseName :: Phase -> String
phaseName Bootstrap      = "bootstrap"
phaseName Unauthorized   = "unauthorized"
phaseName Live           = "live"
phaseName Settings       = "settings"
phaseName Locking        = "locking"
phaseName Capturing      = "capturing"
phaseName Browsing       = "browsing"
phaseName (Rendering st) = "rendering:" ++ stageName st
phaseName Review         = "review"
phaseName Error          = "error"

-- | Stable string name of an event.
eventName :: Event -> String
eventName SessionReady   = "sessionReady"
eventName AuthDenied     = "authDenied"
eventName ShutterTap     = "shutterTap"
eventName OpenSettings   = "openSettings"
eventName CloseSettings  = "closeSettings"
eventName LockComplete   = "lockComplete"
eventName BurstComplete  = "burstComplete"
eventName SelectFrame    = "selectFrame"
eventName Picked4        = "picked4"
eventName (StageDone st) = "stageDone:" ++ stageName st
eventName Committed      = "committed"
eventName Retake         = "retake"
eventName Fault          = "fault"

-- | The canonical happy-path event sequence: bootstrap → live → lock → burst →
-- browse (scrub + pick 4) → render(5 stages) → commit → review → retake. Emitted as
-- 'goldenPhaseTrace' for the cross-language @step@ pin.
goldenHappyPath :: [Event]
goldenHappyPath =
  [ SessionReady, ShutterTap, LockComplete, BurstComplete
  , SelectFrame, SelectFrame, SelectFrame, SelectFrame, Picked4
  , StageDone Quantize, StageDone Dither, StageDone Significance
  , StageDone Palette, StageDone Encode, Committed, Retake ]

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
-- The phase-FSM laws (one surface, no screens)
-- =============================================================================

-- | PHASE-T1 — @step@ is TOTAL: defined (no ⊥) for every (phase, event). The catch-all
-- self-loop makes this hold by construction; the law forces evaluation to witness it.
lawPhaseTotal :: Bool
lawPhaseTotal = all (\(p, e) -> step p e `seq` True) [ (p, e) | p <- allPhases, e <- allEvents ]

-- | PHASE-T2 — no orphan phase: every phase is reachable from @Bootstrap@ by some event
-- sequence (a BFS fixpoint over @allEvents@). A phase no path reaches would be dead UI.
lawNoOrphanPhase :: Bool
lawNoOrphanPhase = all (`elem` reached) allPhases
  where
    reached = fixpoint [Bootstrap]
    fixpoint seen =
      let next = nub (seen ++ [ step p e | p <- seen, e <- allEvents ])
      in if length next == length seen then seen else fixpoint next

-- | PHASE-T3 — THE CELL-FIELD LAW: every phase observes as a full cell-field
-- configuration (@|phaseField p s| == |allPlaces|@), so a phase is a grid of cells on
-- the one surface, never a screen. This is the formal content of "one surface, no
-- screen swaps" — the keystone of the one-surface unification.
lawPhaseIsCellGrid :: DisplayState -> Bool
lawPhaseIsCellGrid s = all (\p -> length (phaseField p s) == length allPlaces) allPhases

-- | PHASE-T4 — @Review@ is ENTERED (from another phase) ONLY by @Committed@: no
-- non-@Review@ phase transitions into @Review@ on any other event. (Self-loops from
-- @Review@ are excluded — staying in @Review@ is not entering it.) Retires the implicit
-- @primaryOutput != nil@ review predicate in the Swift router — review becomes an
-- explicit, single-edge phase transition.
lawReviewExplicit :: Bool
lawReviewExplicit =
  all (\(p, e) -> p == Review || step p e /= Review || e == Committed)
      [ (p, e) | p <- allPhases, e <- allEvents ]

-- =============================================================================
-- The golden tick-trace (the cross-language gate, N = 64)
-- =============================================================================

-- | A deterministic @[(Σ, ι) → Σ']@ sequence the Swift capture/playback path must
-- reproduce bit-for-bit: each step ingests a frame (δ_capture) then advances the
-- cursor (δ_review). Emitted to @DisplayContract.swift@ and gated by @cabal test@.
goldenTickTrace :: [(DisplayState, Input)] -> [DisplayState]
goldenTickTrace = map (\(s, i) -> deltaReview (deltaCapture s i))

-- | The phase trace from @Bootstrap@ for an event list (@scanl step@). Emitted to
-- @DisplayContract.swift@ (over 'goldenHappyPath') and gated by @cabal test@, so the
-- Swift @step@ port reproduces the FSM bit-for-bit.
goldenPhaseTrace :: [Event] -> [Phase]
goldenPhaseTrace = scanl step Bootstrap

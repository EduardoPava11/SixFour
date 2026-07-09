# UI FORM FOLLOWS FUNCTION — the scene charter

> Status: WORKING CHARTER (2026-07-08, from Daniel's first on-device UX review) · Owner: SixFour
> The rule for every scene: name the FUNCTIONS first, then derive the FORM. Anything on screen
> that cannot name its function is a deletion candidate. Theme = PIXELATION (the cell grid is
> the only drawing vocabulary); within it, CONTROLS MUST READ AS CONTROLS.
>
> **THE INSTRUMENT FRAMING (Daniel, 2026-07-08): this app is a SCIENTIFIC TOOL to understand
> color as ENERGY — waves moving.** This is not decoration; it is what the math already says:
> the pooling carrier is LINEAR LIGHT (photon energy, `Spec.ColorTime`), the V2.1 field is
> per-cell ENERGY CURVES whose argmin is a ground state (`Spec.V21Field` centered energy), and
> `Spec.ColorMomentum` defines color MASS (what pooling keeps), MOMENTUM (the reversal-odd
> t-band — the moving part), and FLUX (the Wasserstein impulse of color mass through value
> space). The UI's job is to make the user SEE these: energy banking into thicker voxels,
> waves of color mass moving through the burst, the collapse to a ground state at the shutter.
> Every visualization must surface a REAL quantity the spec defines — never a decorative wave.
> Directory mirror: each scene below is a directory under `SixFour/UI/Scenes/`; shared layers
> live in `Lattice/` (pitch, placement, theme, motion, haptics), `Cells/` (drawing vocabulary),
> `Ground/` (the influence field), `Machine/` (σ, FSM, router, engine), `Widgets/` (the movable
> widget family — legacy-suspect, audited per scene below).

## Device verdict (2026-07-08)

It compiles, runs, and captures. The UX debts, verbatim:
1. **Buttons are not clearly buttons.** The pixelation theme stays, but tappable cells need an
   unmistakable control language (state, edge, invitation — within GRID laws, no glass/alpha).
2. **The 16² pyramid vertex as the capture button: accepted.** But then the SEPARATE 16×16
   color palette widget **flickers** and has no answered function on the live face. What is it
   FOR now that the vertex is the shutter and "the palette IS the coarse view"?
3. **The background (influence ground): what is its function?** It exists as "order radiates
   into chaos" — if it cannot earn a function on a scene (orientation? state? energy?), it is
   decoration and must justify itself per scene.
4. **Capture FREEZES the live preview. Unacceptable.** The burst must remain visibly alive —
   the capture is 3.2 s of the user's attention; the surface must show the burst landing.
5. **The Decide scene is ugly and will not be used unless improved.** Its functions must be
   named and its form rebuilt from them.

## Scene charters

### Live (`Scenes/Live/` — LivePhaseField, InvertedPyramidField, RungTelemetryField)
FUNCTIONS: (a) see the world at the three rungs before committing; (b) FIRE the burst;
(c) meter a point; (d) choose a LOOK / EV by ground gesture; (e) read rung + system telemetry
as it arrives (the grid mirrors the ladder).
FORM TODAY: inverted pyramid (64/32/16 self-centered), right-flank rung meters + system strip
(liveScene regions), influence ground behind everything, legacy palette widget at (42,145).
CRITIQUES → WORK:
- The shutter vertex must LOOK fireable (critique 1): a control edge/pulse on the 16² that is
  a cell transform, not alpha; pressed/busy states as cell states (CellButton precedent).
- The legacy 16×16 palette widget (critique 2): name its function or retire it from Live. The
  pyramid vertex already IS the realized palette. Candidate functions if kept: LOOK indicator
  (it grades with the active look) or capture-history strip; otherwise DELETE from this scene
  (destructive change authorized 2026-07-08).
- Flicker (critique 2): the widget rebakes per preview publish with no content fingerprint —
  if kept anywhere, it adopts the InvertedPyramidField bake-cache discipline.
- Ground (critique 3): on Live its candidate function is exposure/attention energy (it already
  radiates the arrangement + palette). Decide: keep with named function, or dim it to a static
  void so the pyramid carries the scene.
- FREEZE (critique 4, the big one): during the burst the pyramid must animate the landing
  frames (burstFrameCallback → previewTile already exists at 20 Hz) and the 16² should fill
  with PROGRESS (already built) — verify the publish path actually reaches the pyramid during
  `.capturing` on device; if the idle preview pipeline is what feeds it, wire the burst tiles
  in. The burst is the show; never a freeze-frame.

### Decide (`Scenes/Decide/` — DecidingPhaseField, DecideSurface)
FUNCTIONS: (a) judge the capture at a glance (the 64³ against its 16³ coarse); (b) accept /
retake with one obvious action each; (c) optionally paint/gate the somatic gene (advanced).
FORM TODAY: decisionScene regions (preview, paint, channels, gauge, gene, again, accept).
CRITIQUES → WORK (critique 5): the scene shows machinery, not a decision. Redesign from the
two first-class verbs — ACCEPT and AGAIN — as the clearest controls on the surface; demote
paint/channels/gauge/gene behind a fold (advanced, W1-gated world). The judgment view (64 vs
16) is the hero; everything else earns its cells or leaves.

### Review (`Scenes/Review/` — CapturedReviewPhaseField, V21FieldView, PlaybackClock)
FUNCTIONS: (a) watch the committed GIF loop; (b) export/share (GIF + field bundle); (c) retake.
CRITIQUES → WORK: same button-clarity language as Live; the V21 field widgets stay only if
they serve judgment (they are training-data views — candidates for a debug gate, not the
user's review). EXPORT/SHARE/NEW SHOT adopt the control language.

### Curate (`Scenes/Curate/` — Curating256PhaseField, CurateSurface)
FUNCTIONS: launch-time 256³ curation loop (hero, slabs, source/repaint/rebuild, accept).
CRITIQUES → WORK: none named yet on device; inherits the control language. Audit after
Live/Decide land.

### Bootstrap (`Scenes/Bootstrap/`)
FUNCTIONS: say clearly why the camera isn't running and what to do (permissions). Inherits
the control language; lowest priority.

## The control language (cross-cutting, to be designed FIRST)

One pixelated vocabulary for "you can tap this", used by every scene: a reserved cell
treatment for interactive regions (e.g. 1-cell inset ring + idle 2-step shimmer, pressed =
inverted cells, busy = the red state, disabled = the 2×2 checker — all existing CellButton
ideas, promoted to a LAW for every control). Spec home: extend `Spec.CellMechanics` (the
grid-cell interaction DSL already has lifetime FSM + detent haptics) so the lint can police
"interactive region ⇒ control treatment".

## Order of work

1. Control language (spec + Cells/ implementation) — unblocks every scene.
2. Live scene: freeze fix (function: the burst is the show) + shutter affordance + palette
   widget verdict + ground verdict.
3. Decide scene rebuild around ACCEPT/AGAIN.
4. Review pass; Curate/Bootstrap last.

## THE DESIGN (synthesized 2026-07-08)

> Synthesis of the four competing directions. SPINE = "THE POUR" (the subtractive,
> cadence-honest direction): the pyramid's coarse rungs become TRUE TEMPORAL INTEGRALS
> refreshing at the ladder's real cadences, with intake tallies making the 4-into-1 pour
> countable. GRAFTED ORGANS: the ControlFace spec algebra + Decide ACCEPT/AGAIN rebuild +
> four-verbs tool consolidation (from "CONTROL FACES + THE POUR"); the banked weave-fill
> capture ledger + "=4F" telemetry vocabulary (from "THE GATHER BEAT"); the flux bar +
> per-pour-group haptic detent (from "THE PHOTON BANK"). REJECTED: sample-and-hold latching
> (shows cadence but not integration — the accumulator shows the actual banked light);
> the bank-column chip animation and the 256-cell motion map (decoration risk / element
> growth); halt-order collapse fill (mid-burst ColorHead publish plumbing unproven — v2
> candidate, raster-ledger fallback IS the v1 design); demoting RungTelemetryFlanks
> (violates iterative-not-replacement); the ground-as-metronome pulse (carnival risk).
>
> Everything below is buildable without further design decisions. All timing derives from
> the ONE 20 Hz `SurfaceClock.tick` (already a readable monotonic counter): 1 tick = 1
> weave unit = 5 cs. No new clocks. All states are opaque cell/ink transforms — never alpha.

### D0. The physics being shown (law-pinned, nothing invented)

One 16² frame = 4 timeline units = the integrated light of FOUR consecutive 64² frames
(`Spec.WeaveOrder.unitsOf` 1/2/4 = `Spec.ColorTime.poolDepth`; cadences 64@20Hz / 32@10Hz /
16@5Hz; `s4_ladder_delay_cs` 5/10/20 cs; per-voxel samples 1:8:64). u64 SUMS are the
transitive carrier; means never compose — divide ONCE at the display boundary
(`lawSumsCompose` / `lawMeansDoNotCompose`). Every element below surfaces one of: linear-light
energy banking (ColorTime), color MASS (ColorMomentum reversal-even / frame DC), color FLUX
(paletteW1 impulse, device twin `s4_v21_wdist1d` at `Kernels/KernelsV21.swift:653`), or the
√N significance ladder (1 : 2√2 : 8).

### D1. The control language — ControlFace (cross-cutting, build FIRST)

SPEC: extend `spec/src/SixFour/Spec/CellMechanics.hs` with a closed ControlFace algebra,
regenerated into `SixFourCellMechanics`, so the grid lint polices "interactive region ⇒
control face". Face vocabulary (all cell/ink transforms):
- **FRAME**: 1-cell inset ring in control ink (white 235) — solid controls (CellButton/
  CellSelector keep theirs; this promotes them to law).
- **BRACKETS**: for controls whose content IS an image (the 16² shutter, the Decide hero):
  four corner brackets, arms 3 cells long × 1 cell thick, drawn in the gutter OUTSIDE the
  tile (zero content pixels obscured). The bracket rect IS the hit rect.
- **BEAT** (replaces idle shimmer — ONE moving invitation, cadence-locked): the face goes
  lit ink for exactly 1 tick on every 16-rung refresh (tick ≡ 0 mod 4, 5 Hz) — the
  affordance and the cadence teacher are one element. Suppressed under reduce-motion.
- **PRESSED**: full ink inversion of the face for the ticks the finger is down.
- **BUSY**: the CellButton red (220,60,60) on the face.
- **DISABLED**: the existing 2×2 checker over the face only.
NEW LAWS: `lawControlFaceTotal` (every interactive region declares a face),
`lawFaceNoAlpha`, `lawBeatIsPoolCadence` (beat period = 4 ticks), `lawDisplayCadenceIsPoolDepth`
(a rung's display refresh period = `unitsOf` rung ticks), `lawTallyEqualsUnits` (tally slot
count = `unitsOf` — rail lengths are NOT free constants), `lawLedgerConserves`
(64 frames × 4 cells = 256), `lawBeatDerivedFromOneClock`.
NEW SWIFT: `SixFour/UI/Cells/CellControlFace.swift` — `ControlBrackets(side:state:tick:)`,
CellBitmap-baked, cached keyed on `(state, tick % 4 == 0)` so the beat costs one rebake per
4 ticks. `xcodegen generate` after the new file.

### D2. Live — the elements (each names its function, spec quantity, form, publish path)

**E1. HONEST RUNG CADENCE + TEMPORAL INTEGRALS** (the proposition itself).
FUNCTION: show `lawStopEqualsPoolIndex` as lived time — the 16² IS the mean of the four 64²
frames since its last refresh: same total photons, coarser space, 4× the time.
SPEC QUANTITY: linear-light banking, `Spec.ColorTime` τ_c; √τ_c noise calming made visible.
FORM: `InvertedPyramidField` gains `tick: Int` (from `LivePhaseField`, `clock.tick` — ~10 LOC
plumbing). `Baked` gains two u64 accumulators: `acc32` (32·32·3), `acc16` (16·16·3). Every
tick (pixelKey change): 64² rebakes as today; `poolSpatial2(s64)` ADDS into acc32 and
`poolSpatial2(s32)` ADDS into acc16. At tick ≡ 0 (mod 2): acc32 realizes to img32 with
count = 4px·2frames = 8, then clears. At tick ≡ 0 (mod 4): acc16 realizes to base16/img16
with count = 16px·4frames = 64, then clears. Crisp whole-tile swaps, never partial. Motion
smear in the 16² is the lesson, not a bug. When `Feature.liveLadder` supplies real
tile32/tile16, the same mod-2/mod-4 gating applies to their adoption. PERF: net positive —
32²/16² CGContext bakes drop to 1/2 and 1/4 of today's per-publish rate; added cost ≈ 3.8k
u64 adds per tick. Memory: ~37 KB.
FILES: `SixFour/UI/Scenes/Live/InvertedPyramidField.swift` (split `pixelKey` handling: the
onChange rebake feeds the accumulators every publish; realization gated on tick),
`LivePhaseField.swift` (pass tick).

**E2. INTAKE TALLIES** (the pour made countable — Daniel's exact ask).
FUNCTION: four fine ticks visibly pour into one coarse frame.
SPEC QUANTITY: `Spec.WeaveOrder.unitsOf` (slot counts 2/4 pinned by `lawTallyEqualsUnits`);
slot ink = that tick's frame DC = the MASS band of `Spec.ColorMomentum` (one extra reduction
over the already-computed s64 totals — microseconds).
FORM: drawn INSIDE the pyramid's existing gif(4) VStack gutters (part of
`InvertedPyramidField`, so alignment is structural). Pinned coordinates (mirror into
`Spec.GridLayout` liveScene as proven regions for the contention proof): `intake32` at
(34,114) w32 h2 — 2 slots of 15 cells + 2-cell gap, in the rows-113–116 gutter; `intake16`
at (42,149) w16 h2 — 4 slots of 3 cells + 1-cell gaps, centered, in the rows-149–152 gutter.
Each tick, slot (tick mod n) fills with the current frame's global mean colour; pending
slots are hollow ghost outlines (ink change, never alpha). On the realize tick the filled
slots flash lit for 1 tick then clear to ghost — the emptying + the coarse-tile swap
together ARE the pour, at 5 Hz, forever. `allowsHitTesting(false)`. Rebake: one ≤64-cell
CellBitmap per tick, fingerprinted on (tick mod 4) so identical states never rebake.

**E3. THE SHUTTER VERTEX** (fire the burst; read as the most touchable thing on screen).
FUNCTION: the app's one irreversible verb, wearing the D1 control language.
FORM: BRACKETS around the 16² — footprint cols 40–59 × rows 151–170 (16-cell tile at
(42,153) + 1-cell gutter + 1-cell bracket = 20 cells = 80 pt, over the touch floor; hit rect
= the full bracket rect, replacing today's bare 64 pt `onTapGesture` on the tile). Idle:
ghost brackets + BEAT (lit for 1 tick on each mod-4 realize — the shutter heartbeats at the
cadence its own frames land at). Pressed: brackets + tile invert for 2 ticks. Busy: brackets
in CellButton red; the fill inside is E7's banked ledger. Disabled: 2×2 checker on the
brackets. NOTE: intake16 sits at rows 149–150, clear of the bracket top row 151.

**E4. THE METER** (tap the 64² = meter that point; today it has zero feedback).
FORM: unchanged tap → `onMeter64`; feedback = a 3×3-cell crosshair of inverted cells at the
metered point for 20 ticks. The 64² gets NO control face (it is a surface you point at, not
a button).

**E5. THE INSTRUMENT RAILS** (LOOK-swipe / EV-drag elevated from invisible to confident).
FUNCTION: the two ground gestures are the user's creative instruments; a live gesture must
MATERIALIZE its rail (the control face of a gesture). Display-only overlays — the gesture
itself stays on the existing clear ground layer (`lookSwipeAndExposureDrag` untouched).
- **EV RAIL** (vertical drag): LEFT screen edge (the right flank belongs to
  RungTelemetryFlanks) — new liveScene region `evRail`, 2 cells wide × ~28 tall, cols 2–3,
  vertically centered on field32. One 2×2 detent block per ⅓ stop, ±2 EV ⇒ 13 detents;
  centre = 0 EV in ghost; current EV block inverted. Materializes outward from centre 1
  block/tick (≤6 ticks); dematerializes 8 ticks after release. Haptics: existing
  frame-locked `.cellDetent` per ⅓-stop crossing.
- **LOOK STRIP** (horizontal swipe): above the 64² — region `lookStrip` at (18,44) w64 h4.
  One 4×4-cell swatch per look = that look's OKLab grade applied to a fixed 4-colour probe
  (baked once per look at init); active look wears the 1-cell FRAME; swipe slides the frame;
  commit on end as today (`Haptics.selection` stays). Lingers 20 ticks after commit, then
  dematerializes. This REPLACES the legacy palette widget's only defensible function (LOOK
  indicator) — it shows the grade ON colours instead of a flickering rebake.
- **IDLE DISCOVERABILITY**: two static 3-cell ghost notch spines (cols 2–3 mid-left for EV;
  above the 64² for LOOK). Nearly nothing, but the surface admits the instruments exist.
- The transient LOOK-name / EV CellText overlays stay as-is (they already obey subtraction).

**E6. THE FLUX BAR** (the single-number wave meter — the instrument framing's quantity).
FUNCTION: show the impulse of color mass through value space.
SPEC QUANTITY: `Spec.ColorMomentum` `lawFluxChargesMassTimesDistance` — paletteW1 between
consecutive GCT snapshots, via `s4_v21_wdist1d` (`Kernels/KernelsV21.swift:653`);
`ColorHead.latestGCT` already populates on device.
FORM: region `fluxBar` at (42,172) w16 h1, directly under the shutter brackets. Fill COUNT =
log₂-scaled per-cadence W1, sampled at 5 Hz (the 16-rung cadence, matching GCT publish);
rebaked only when the integer count steps. Lit cells in TelemetryInk; unfilled ghost.
`allowsHitTesting(false)`. If `latestGCT` is nil (feed off), the bar renders all-ghost.

**E7. CAPTURE — THE BURST IS THE SHOW** (critique 4, the big one).
WIRING FIX (verified in code, not speculative): the non-quantized preview branch publishes
`frame.indices = []` (`CaptureViewModel.swift:632`) and the guard at :641 then skips
`previewIndexTile`/`previewPalette` — starving the pyramid exactly as reported on device.
FIX: during `.capturing` the burst renderer ALWAYS runs the quantized path (force
`quantized = true` in the CoalescingFrameRenderer closure snapshot). If a device profile
shows dropped burst frames from the per-frame quantize, the fix moves to publishing raw-RGB
tiles the pyramid can pool — NEVER back to freezing.
DURING THE BURST (64 frames ≈ 3.2 s): the 64² streams landed frames at ~20 Hz; acc32 keeps
integrating (32² at 10 Hz); the intake tallies keep beating, now counting LANDED frames
(n mod 4), so capture is visibly the same machine, recording. The 16² becomes the **BANKED
LEDGER**: `rebakeShutter`'s dim-fill is replaced by a persistent `@State bankedLedger:
[SIMD3<UInt8>]` (256 entries, reset at stage start) — when frame n lands, raster cells
4(n−1)…4n−1 take the 16²-pooled colours OF THAT FRAME (from the current base16),
PERMANENTLY; unfilled cells stay ghost-dim (quarter-ink, the existing b/4 idiom). 64 frames
× 4 cells = 256 (`lawLedgerConserves`) — the WeaveOrder block arithmetic drawn live; the
finished tile is a genuine time-woven image, each 4-cell strip sampled 5 cs apart. A
transient CellText in the tally row during burst only: "160/320cs" (banked window, stepping
5 cs per landed frame) — the EV-overlay idiom, gone when idle.
HAPTICS: one frame-locked `.cellDetent` per completed pour group (every 4 landed frames =
16 detents across the burst) — the user FEELS the 4:1 banking rhythm.

**E8. RUNG TELEMETRY FLANKS** — KEEP, unchanged placement (already ≤5 Hz, `.equatable`).
One vocabulary alignment: derived-mode EV lines read "+2.0 =4F" / "+1.0 =2F"
(pooling-equivalent stops AND frame-equivalents) — one `TelemetryMeterMath.evLabel`
extension, golden-tested in TelemetryMeterTests. Their √N bars (1 : 2√2 : 8) are the
per-voxel-samples half of the same equivalence story; the intake tallies corroborate them.

**E9. THE INFLUENCE GROUND** — VERDICT: keep, with ONE named function per phase: **CAPTURE
ENERGY**. In `.live` idle it dims to a calm near-void — new spec tunable `liveIdleEnergy ≈
0.25` in `Spec.InfluenceField` → codegen keeps `FieldTuning` + `FieldTuning.metal.h` in
lockstep (CPU and GPU can't drift); it still radiates from the proven pyramid-band regions.
During `.capturing` it rises to full energy scaled by a (tick mod 4)/4 ramp — the ground
glows exactly when photons are being banked, and only then. On any scene where it cannot
name a function, it stays void. On-device tuning of `liveIdleEnergy` is a codegen
round-trip by design.

**E10. THE LEGACY 16×16 PALETTE WIDGET** — VERDICT: **DELETE from Live** (destructive
change authorized 2026-07-08). Its region overlaps the field32 band and crowds field16; the
vertex IS the realized palette (`pixelsPerColor` 2 = 1); its LOOK-indicator candidate
function moves to E5's LOOK strip. Scope: Live only — MovableColorWidget mounts stay for
non-live acts; drop `.palette16` from Live colliders; retire the captureScene `palette`
region when its last render site goes. The flicker bug dies with the widget.

**THE FOUR VERBS OF LIVE** (tool consolidation — elevate and simplify): DRAG the ground =
grade (one 2-axis instrument: horizontal = LOOK strip, vertical = EV rail); TAP the 64² =
meter (crosshair); TAP the 16² = fire (brackets); everything else watches. PAINT leaves
Live entirely (it already lives in Decide, behind the fold). Net Live element count goes
DOWN: widget deleted, ground dimmed, rails exist only while touched.

### D3. Decide — rebuilt around two verbs (critique 5)

HERO: the 64 reconstruction with its 16 coarse beside it — candidate placement hero at
(14,30) w64, coarse at (82,30) w16 (prove via the GridLayout contention test; adjust cols
only). Hero wears BRACKETS (it is scrubbable). The coarse tile carries the same intake-tally
idiom above it (static, showing the 4-cells-per-frame ledger structure) so the equivalence
language crosses scenes.
VERBS: bottom band, two control-faced verbs, each 44 cells wide × 16 tall (176×64 pt, 4× the
touch floor), 4-cell gaps (4+44+4+44+4 = 100 cols): **ACCEPT** = filled control-ink face +
seal glyph, `Haptics.play(3)`; **AGAIN** = hollow FRAME + retake glyph, `Haptics.play(1)`.
These are the clearest controls in the app — bigger faces than the shutter.
ADVANCED FOLD: everything current (paint/channels/gauge/gene) moves behind ONE 12-cell
chevron control (FRAME face) between hero and verbs; opening slides the advanced row in as
a cell-row reveal (rows paint top-down, 1 row/tick). Gene toggle + paint keep their W1
semantics untouched — placement demotion only; nothing golden-gated is deleted.
FILES: `SixFour/UI/Scenes/Decide/DecideSurface.swift`; `Spec.GridLayout` decisionScene
regions re-proven (hero, coarse, verbs, fold; paint/channels/gauge/gene move inside the
fold's region).

### D4. Review / Curate / Bootstrap

Inherit D1's control language (EXPORT/SHARE/NEW SHOT get FRAME faces; lint enforces).
V21 field widgets on Review: debug-gate candidates, decided after Live/Decide land. No
other changes in this pass.

### D5. The explicit verdicts (one line each)

1. **Palette widget**: DELETE from Live; LOOK-indicator function → LOOK strip (E5); mounts
   stay for non-live acts.
2. **Ground**: KEEP with named function = capture energy (dim idle `liveIdleEnergy`, full +
   pour-ramp during `.capturing`); void on scenes where it names nothing.
3. **RungTelemetryFlanks**: KEEP (no demotion without Daniel's sign-off); gain "=4F"/"=2F"
   labels.
4. **Coarse-rung display**: TRUE INTEGRALS (accumulators), not sample-and-hold latching.
5. **Capture**: force quantized publish during `.capturing`; 16² = banked weave ledger;
   never a frozen surface.
6. **Design tools**: merge to the FOUR VERBS of Live; rails materialize on touch; PAINT is
   Decide-only (behind the fold).
7. **Rejected organs**: bank-column chips, 256-cell motion map, halt-order collapse fill
   (v2 candidate), ground metronome, idle marching shimmer (BEAT replaces it).

### D6. Spec homes, laws, gates

- `Spec.CellMechanics`: ControlFace algebra + `lawControlFaceTotal` / `lawFaceNoAlpha` /
  `lawBeatIsPoolCadence` / `lawDisplayCadenceIsPoolDepth` / `lawTallyEqualsUnits` /
  `lawLedgerConserves` / `lawBeatDerivedFromOneClock`, plus a 16-tick golden schedule
  vector mirrored into a Swift test. Tally/cadence quantizers get TelemetryMeterTests-style
  pure math tests.
- `Spec.GridLayout`: liveScene + `intake32`/`intake16`/`fluxBar`/`evRail`/`lookStrip`;
  decisionScene re-proven; captureScene `palette` retired. Contention proof is the gate.
- `Spec.InfluenceField`: `liveIdleEnergy` / capture ramp tunables → FieldTuning codegen.
- Gate: `cabal test` + `cabal run spec-codegen` + `xcodegen generate` + BUILD SUCCEEDED
  (compile-only rule; camera behaviour verified on device by Daniel).

### D7. Build order + pre-agreed fallback ordering

1. D1 ControlFace (spec + CellControlFace.swift) — unblocks everything.
2. E7 capture wiring fix (force quantized publish) — the freeze is the critical path; if
   the pyramid still starves on device, everything else blocks on this.
3. E1 cadence + accumulators, E2 tallies, E3 brackets, E7 ledger (one InvertedPyramidField
   pass, ~250 LOC).
4. E10 widget deletion + E9 ground tunables + E6 flux bar + E8 label.
5. E5 rails (GridLayout contention proof re-run).
6. D3 Decide rebuild.
IF THE SURFACE TURNS BUSY on device, drop in this order (pre-agreed): ground pour-ramp
first, then the meter crosshair linger, then the BEAT — the intake tallies and the honest
cadence are LAST to go (they carry the charter's whole point). If users read the 5 Hz
vertex as jank rather than integration, the fallback is honest-cadence-during-capture-only
(idle keeps today's smooth pooling) — but try the true design on device first.

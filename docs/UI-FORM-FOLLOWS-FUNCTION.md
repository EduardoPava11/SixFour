# UI FORM FOLLOWS FUNCTION — the scene charter

> Status: WORKING CHARTER (2026-07-08, from Daniel's first on-device UX review) · Owner: SixFour
> The rule for every scene: name the FUNCTIONS first, then derive the FORM. Anything on screen
> that cannot name its function is a deletion candidate. Theme = PIXELATION (the cell grid is
> the only drawing vocabulary); within it, CONTROLS MUST READ AS CONTROLS.
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

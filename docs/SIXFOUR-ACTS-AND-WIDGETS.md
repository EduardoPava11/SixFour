# SixFour — the acts of the GIF-making process, and their widgets

> One surface, five acts. Making a GIF is a single linear story —
> **Live → Capture → Browse → Render → Review** — and each act is just a different
> *cell-grid configuration* of the one `Surface` (a phase change is a cell update,
> never a view swap). This doc is the canonical **Act × Widget** matrix: which
> registry widgets (`docs/SIXFOUR-CELL-WIDGET-LANGUAGE.md`) appear at each step.

Reconciles the two pre-existing "Act" numbering systems:
- **Lifecycle acts (I–V)** = the FSM phases (`Surface.swift` `SurfacePhase`), the
  spine of this doc. Authoritative design: `docs/SIXFOUR-ACTS-WORKFLOW.md`.
- **Palette-story acts (16²/4⁴/2⁸/export)** = NOT a parallel timeline — they are the
  **curation sub-acts inside Act V (Review)**. Design: `docs/SIXFOUR-PALETTE-STORY-WORKFLOW.md`.

Legend: ✅ built · 🔶 partial/gated · 🔲 proposed (designed, not built).

---

## Act I — LIVE (phase `live`) — *aim & begin*
The resting state; the only entry to capture. The screen is the live camera as a
64² cell field, with the per-frame palette doubling as the shutter.

| Widget | Footprint | State | Role |
|---|---|---|---|
| **Field64** hero (live preview) | 64×64 | ✅ | the camera, quantised live to cells |
| **Palette16** = shutter | 16×16 | ✅ | live per-frame palette; **tap = begin capture** |
| look-swipe (gesture, no chrome) | — | ✅ | horizontal swipe cycles `captureLook` |
| influence-field ground | full field | ✅ | the persistent breathing substrate |
| **DiversityRing** (coverage arc) | 20×20 | 🔲 | readiness: LAB coverage of the frame |

*Data:* `previewTile`, `previewPalette`, `palette` (live 256), `clock.tick`.
*Aside:* `settings` phase (the sampler/engine/look toggles — `CellSelector`/`CellToggle`)
is reachable from Live; it is an interlude, not an act of the GIF story.

---

## Act II — CAPTURE (phases `locking` → `capturing`) — *the burst, visible*
The 64-frame burst in flight. The live preview **stays alive** (no freeze); the
palette fills as a progress bar.

| Widget | Footprint | State | Role |
|---|---|---|---|
| **Field64** hero (live, newest frame) | 64×64 | ✅ | burst visible, no preview freeze |
| **Palette16** = progress bar | 16×16 | ✅ | captured slots solid, rest ghost-fade |
| phase banner | content cells | ✅ | "Locking…" / "Capturing 64 frames…" |
| reverse-cursor "build backwards" | — | 🔲 | retracted (jarring 4-frame loop); the honest build is shown in Act IV instead |

*Data:* `previewTile`, `palette` (growing 0..256), `phaseEnteredTick`.

---

## Act III — BROWSE & PICK-FOUR (phase `browsing`) — *curate 4 frames* 🔲 NOT BUILT
Designed (`SIXFOUR-ACTS-WORKFLOW.md` §III), **not built**: today `.burstComplete`
wires straight to Render. The decided semantics (2026-06-08): pick-four = **quad
anchors** that feed the collapse lever. This is the act that *authors the input to
palette-story Act II (4⁴)*.

| Widget | Footprint | State | Role |
|---|---|---|---|
| **Field64** scrubber | 64×64 | 🔲 | scrub the 64-frame burst |
| scrub rail + filmstrip (4 picks) | M×11 + 4·(N²) | 🔲 | the 4 chosen anchor frames |
| **Palette16** (inert) | 16×16 | 🔲 | the scrubbed frame's palette |
| **DiversityRing** (coverage) | 20×20 | 🔲 | how much gamut the 4 picks span |
| continue gate (`CellActionButton`) | 11×N | 🔲 | commit the 4 → Render |

*Needs:* new `Browsing` phase + `SelectFrame`/`Picked4` events + `picks:[Int]` Σ field.

---

## Act IV — RENDER (phase `rendering`: quantize→dither→significance→palette→encode) — *deterministic reveal*
No spinner: the deterministic Zig core is made visible stage-by-stage as the GIFA
resolves under a serpentine sweep.

| Widget | Footprint | State | Role |
|---|---|---|---|
| **Field64** resolve hero (serpentine sweep) | 64×64 | ✅ | cells flip to true GIFA as each stage front passes |
| stage banner + progress | content cells | ✅ | "rendering:dither" + monotonic 0→1 |
| stage ladder (5 rungs) | 5·(N×11) | 🔲 | the 5 stages as a lit ladder |
| per-stage metrics / byte-meter | content cells | 🔲 | quantize MSE, coverage, encoded bytes |
| **Palette16** (collapsing) + **DiversityRing** arc | 16² / 20² | 🔲 | the global palette forming |

*Data:* `indexCube` (streaming), `renderProgress`, frozen `previewTile` backdrop.

---

## Act V — REVIEW (phase `review`) — *commit, curate, export*
The committed GIFA loops. This is where the **palette-story acts live as curation
sub-acts** — the user steers the global palette, then ships a rung or retakes.

### Act V chrome (the lifecycle widgets)
| Widget | Footprint | State | Role |
|---|---|---|---|
| **Field64** GIFA hero (2D loop) | 64×64 | ✅ | the product, playing frame-exact |
| **Palette16** per-frame (cursor-cycled) | 16×16 | ✅ | the palette breathing with the loop |
| Action row: Share · Save · Retake | 11×N each | ✅ | ship / save-rung / restart |
| Export **LUT** (`.cube`) | 11×N | 🔶 | only when a `captureLook` grade is on |
| **Atlas** · **Groups** tools | 11×N | 🔶 | flag-gated curation sub-states |

### Palette-story curation sub-acts (embedded in Review)
| Sub-act | Widget(s) | Footprint | State | What it does |
|---|---|---|---|---|
| **16²** per-frame | the Palette16 strip | 16×16 | ✅ | the atom: one frame's 256 colours |
| **4⁴** quartet core/motion | **Motion toggle** + **threshold slider** | 11×N + 16×11 | ✅ | core (low-displacement) vs motion colours — *the QuartetDelta widget shipped this session*; the slider is the first **frame-locked-detent** widget |
| **2⁸** Haar abstraction | collapse lever: radix grid + scope/branching `CellSelector` + **CUT slider** | tree + M×11 | 🔲 | scroll the Haar level to collapse → global 256 |
| **export** | Save rung picker {16³/64³/256³} | 11×N + N·(N×11) | ✅ | the global pack result |

*Data:* `palettesPerFrame`, `indexCube`, `cursor` (user-driven Z₆₄), `gifURL`.

---

## Interludes (not acts of the GIF story)
`bootstrap` (camera configuring — breathing square), `unauthorized` (deny screen),
`settings` (sampler/engine/look toggles, reachable from Live), `error` (fault). All
cells-only; none of the three ColorWidgets. Listed for completeness.

---

## The three ColorWidgets travel the whole story
`Field64`, `Palette16`, `DiversityRing` are placed at ONE shared, movable global
position (`AppSettings.widgetPlacement`, governed by `MoveContract`/`Spec.MovableLayout`).
A widget keeps its position across act boundaries — the surface geometry is continuous;
only what each widget *renders* changes per act. `Field64` is the spine (present in
I, II, III, IV, V); `Palette16` is present in every act but `settings`; `DiversityRing`
is designed-in but renders nothing yet (🔲 in I/III/IV).

---

## Build state, at a glance
- **Built (✅):** Acts I, II, IV, V and their core widgets; the 16² and 4⁴ curation
  sub-acts (the 4⁴ motion outline + frame-locked slider shipped this session).
- **The two biggest open acts:** **Act III (Browse & Pick-Four)** — needs the new
  `Browsing` phase + filmstrip — and the **2⁸ collapse lever** inside Act V.
- **Enforcement (proposed):** spec the phase→widget-set map (`Spec.Display` already
  owns the phase FSM; add a `widgetsFor : Phase → Set Widget`, golden-pin it, and lint
  that each `*PhaseField.body` renders exactly that set) so this matrix cannot drift
  from the code as acts are built.

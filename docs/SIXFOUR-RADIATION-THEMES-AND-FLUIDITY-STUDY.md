# SixFour — Radiation Themes & Transition Fluidity (large study + organization)

> Keywords: radiation taxonomy, composable radiation axes, per-act radiation theme, RadiationTheme
> preset, act1→act2 disjoint, preview freeze on shutter tap, previewIndexTile burst gap, no-freeze
> reverse playback, widget-move black space, lift occlusion, move-feels-like-preview, order vs chaos.

**Status:** STUDY + organization doc (2026-06-09). Companion to
`SIXFOUR-INFLUENCE-FIELD-WORKFLOW.md` (the field), `SIXFOUR-CELL-FLUIDITY-WORKFLOW.md` (20 fps
per-tick easing — A/B/C shipped), `SIXFOUR-ACTS-WORKFLOW.md` (the five acts). Branch
`feat/influence-field-stage`. Everything stays **20 fps, cell-discrete, one-surface**.

This organizes three threads the user raised:
1. **Categorize the ways to do "radiation"** and give **each act its own theme**.
2. **act1→act2 is still disjointed** — tapping the 16×16 shutter **freezes the 64×64**.
3. **Tap-hold to MOVE a widget leaves a black space** where it was and doesn't feel fluid; it
   should feel as alive as the preview.

The invariant under all of it: **widgets (whatever they are) = ORDER; the rest = CHAOS radiating
out of them.** A "theme" is just *how* that chaos radiates for a given act.

---

## PART 1 — The radiation taxonomy (the design space)

"Radiation" is not one thing; it is a point in a **7-axis space**. A *mode* picks one value per
axis; a *theme* binds a mode (+ tuning) to an act.

| Axis | Values (composable) | What it controls |
|------|--------------------|------------------|
| **A. Emitter geometry** | center-point · edge-bleed (perimeter) · full-footprint halo · per-cell seed | WHERE the radiation springs from on the widget |
| **B. Colour source** | usage-weighted spokes · edge-pixel bleed · palette wheel (angle→rank) · single dominant · temporal (cursor-frame) · complement/contrast | WHICH colours are thrown |
| **C. Falloff** | linear · inverse · stepped/banded · gaussian | HOW fast energy decays with distance (reach) |
| **D. Texture** | blue-noise speckle · smooth gradient · concentric rings · scanlines · Voronoi shards · hatch | HOW a lit cell is filled (the grain) |
| **E. Motion (20 fps)** | outward drift · inward pull · tangential swirl · pulse/breathe · ripple-on-event · still | HOW the per-tick delta moves |
| **F. Seam / interplay** | muted neutral · contested shimmer (time-mux) · hard Voronoi edge · additive bloom | WHAT happens where two sources meet |
| **G. Global modifiers** | lift-dim · energy ceiling · far-void ink · reduce-motion floor | scene-wide scalars |

**Today's field** (shipped) is one point in this space — call it **BLOOM**:
A=edge-bleed + B=usage-weighted spokes + C=linear + D=blue-noise speckle + E=outward drift +
F=muted neutral seam + G=lift-dim. The taxonomy exists so each act can pick a *different* point
without new architecture — only a different `RadiationTheme`.

### Canonical named modes (presets in the space)

- **BLOOM** — calm potential radiating outward. (A:edge-bleed, B:usage spokes, E:outward drift,
  F:muted.) *Order at rest, inviting.*
- **INGEST** — energy pulls INWARD toward a focus widget as it fills. (E:inward pull, C:tightening
  reach, F:additive bloom at the focus.) *Gathering / capture.*
- **SURVEY** — low ambient energy; the *selected* items radiate brighter than the rest.
  (G:low ceiling, B:per-pick emphasis, E:still/gentle.) *Curation.*
- **CRYSTALLIZE** — chaos resolves into order along a front; speckle (D) tightens to smooth as
  cells lock; a bright resolve line emits from the front. (E:ripple-on-front, D:speckle→gradient.)
  *Deterministic render made visible.*
- **SETTLED** — stable, even radiation of the committed palette; slow breathe; a gentle bloom at
  the loop seam. (E:pulse, C:gaussian, F:additive.) *The verdict, celebratory.*

---

## PART 2 — Per-act themes (intent → mode → params)

Each act gets a theme = a named mode + a `FieldTuning`-style param set. The field reads the theme
from `surface.phase` (one switch), so the radiation *is* the act's signature while staying the same
engine + the same order/chaos law.

| Act | Phase | Intent (the feeling) | Mode | Signature params |
|-----|-------|----------------------|------|------------------|
| **I — Live** | `.live` | Calm potential; "compose, the world is open" | **BLOOM** | gentle `driftPerTick`, full reach, usage spokes; widgets at rest |
| **II — Capture** | `.locking`/`.capturing` | Urgent gathering; frames pulled IN to build the GIFA | **INGEST** | E flips to inward pull toward Field64; reach tightens with `capturedFrames/64`; seam → additive bloom; **NO freeze (Part 3)** |
| **III — Browse** | `browsing` (proposed) | Survey & curate; the 4 picks glow | **SURVEY** | low energy ceiling; picked-frame thumbnails radiate brighter; still motion |
| **IV — Render** | `.rendering(*)` | Chaos crystallizes into order along the serpentine front | **CRYSTALLIZE** | front emits a resolve line; speckle→smooth behind the front (ties to the shipped F4 reveal) |
| **V — Review** | `.review` | Settled verdict; the committed palette radiates evenly | **SETTLED** | slow pulse; gaussian falloff; bloom at the 64-frame loop seam |

> **Continuity rule (kills the act-to-act disjoint):** themes must MORPH, not cut. A phase change
> eases the theme params over `phaseEnteredTick` (the shipped F2 mechanism) — `driftPerTick`,
> reach, inward/outward sign, seam mode all `CellEase`-interpolate from the old theme to the new
> over ~8 ticks. So BLOOM→INGEST is a smooth re-aim of the same field, never a swap.

---

## PART 3 — Study: the act1→act2 disjoint (the preview FREEZE)

**Confirmed root cause (`file:line`):** on `.shutterTap`, `CaptureViewModel.capture()` runs the
burst and streams each captured frame to **`self.previewTile` (a `UIImage`)** via
`CoalescingFrameRenderer.onImage` (`CaptureViewModel.swift:425-427`). It NEVER updates
**`previewIndexTile`** (`:198`) — the σ-pure indexed tile the new one-surface hero reads
(`SurfaceView.swift:90-94` bridges `engine.previewIndexTile → surface.previewTile`). So during the
whole burst the 64×64 hero is pinned to the **last live frame → frozen**, while the old legacy
`previewTile` path (unused by the surface) is the only thing updating. The transition reads
disjoint because the ground keeps breathing but the hero is a still.

**Fix options:**
- **(A) Publish indexed burst frames into σ (RECOMMENDED).** In the burst renderer, also emit the
  quantized **index tile + palette** (the quantized path already computes
  `makeQuantizedPreviewImage(from: tile)` — extract its index buffer) and set
  `previewIndexTile`/`previewPalette` each frame. The hero then animates the burst at ~20 fps →
  **no freeze AND you literally watch the frames build the GIFA** (this also satisfies the user's
  earlier "frames build" ask, which F4 only approximated at render time). Pairs with the **INGEST**
  theme (Part 2): as frames land, the field pulls inward toward the now-live hero.
- **(B) Reverse-cursor playback over the captured prefix** (the Act II design): needs the engine to
  fold landed frames into `indexCube` early + a `captureReverseCursor`. More machinery; (A) gives
  the same "alive" feel with less.
- **(C) Synthesized ingest hold** (animate the last live frame inward): a fallback if the camera
  truly cannot surface burst frames in time — least honest.

**Recommendation:** (A) — smallest change. **USER CHOSE (B) reverse-cursor — SHIPPED (`44da9fc`).**
The burst renderer now carries the full `PreviewFrame` (indices+palette) and accumulates the
captured PREFIX (`CaptureViewModel.capturedFrames`/`capturedPalettes`), bridged into σ
(`Surface.capturedFrames`) by `SurfaceView` per landed frame; `CapturingPhaseField` plays it
BACKWARDS via `Surface.captureReverseCursor(count:tick:)` (newest→oldest, κ-advanced). Additive with
a live-tile fallback (no regression). **Camera path ⇒ verify on device.** Pairs next with the
INGEST theme (the chaos pulling inward as frames land).

---

## PART 4 — Study: widget-move fluidity (the BLACK SPACE)

**Confirmed root cause:** `InfluenceField.color` returns `nil` (→ transparent → black bezel) for any
cell inside a **source's placement rect** (the occlusion guard). On lift+drag the widget VIEW moves
via `.offset` (`MovableColorWidget.swift:91`), but the field still occludes the **old placement
rect** → a **black hole** where the widget was, and the field does not flow under the moving piece.
It feels dead because the chaos doesn't acknowledge the lift.

**Fix (contained, UI-only):** while a widget is lifted, **do not occlude its footprint** — let the
(lift-dimmed, Part shipped F3) field radiate THROUGH it. Then lifting reveals calm field, not void;
the vacated cell heals to chaos as the widget leaves; the lifted widget floats over live field.
Precise: pass `liftedWidget` into the field model; in the occlusion guard, skip the lifted source
(compute its colour instead of returning `nil`). *(Implemented this turn as the quick win.)*

**"Move feels like the preview" (the deeper goal):** the preview hero feels substantial because it
is large and *alive*. To give the MOVE the same life:
- **Heal trail:** as the widget leaves, the vacated cells briefly radiate *brighter* (an additive
  ripple from the old centre), then settle — the field "closing the wound." (E:ripple-on-event.)
- **Lift bloom:** the lifted widget carries a faint radiating halo with it (its own mini-source at
  the drag position), so it feels like moving a live thing, not a sticker. Requires the field to
  know the live drag offset (a transient `liftOffset` in σ, updated per drag detent — cheap, only
  while lifted).
- **Eased settle:** on drop, the heal ripple converges on the new cell (ties to the deferred F5).

These are the "move = alive" upgrades; the black-space fix is the prerequisite floor.

---

## PART 5 — Implementation architecture (how themes + fixes land)

- **`RadiationTheme`** value type = the 7-axis choices that vary + a param block (drift sign/speed,
  reach, falloff kind, texture kind, seam kind, energy ceiling). `FieldTuning` becomes the BLOOM
  default; other modes are presets. `InfluenceField` selects `theme(for: surface.phase)` and
  `CellEase`-morphs params across `phaseEnteredTick` (Part 2 continuity rule).
- **Motion sign** generalises the shipped outward drift: `driftPerTick` gains a direction term
  (outward for BLOOM, inward for INGEST, tangential for a swirl) — the existing drift code already
  computes `dir = unit(p − domCenter)`; INGEST just negates it and ties magnitude to progress.
- **Freeze fix (Part 3A):** `CaptureViewModel` emits `previewIndexTile`/`previewPalette` during the
  burst; no surface change needed (the bridge already exists).
- **Black-space fix (Part 4):** `InfluenceField` occlusion skips the lifted source. Optional
  `liftOffset` σ field for the lift-bloom/heal-trail upgrades.

## PART 6 — Sequencing

| Phase | Work | Risk | Needs |
|------|------|------|-------|
| **0 (done)** | Black-space occlusion fix (`99ed2e8`) | low | shipped |
| **0b (done)** | Freeze fix — reverse-cursor burst playback B (`44da9fc`) | med | shipped; **verify on device** |
| **1** | `RadiationTheme` scaffold + per-phase selection + cross-phase param morph (act1=BLOOM as-is) | med | user: confirm the 5 themes |
| **2** | INGEST theme for `.capturing` (chaos pulls inward as frames land) | med | **on-device** (camera) |
| **3** | CRYSTALLIZE (tie to F4) + SETTLED + SURVEY (after `browsing` lands) | med | per-act on-device tuning |
| **4** | Move-feels-alive upgrades (heal trail, lift bloom via `liftOffset`) | low–med | on-device feel |

## PART 7 — Open decisions for the user

- **Theme per act:** confirm/replace the 5 modes (BLOOM/INGEST/SURVEY/CRYSTALLIZE/SETTLED) — names
  and intent. Want a different feeling for any act?
- **Freeze fix:** approach (A) publish burst index tiles [rec] vs (B) reverse-cursor — (A) shows the
  build, (B) is the older Act II design.
- **INGEST direction:** does capture pull the chaos INWARD to the preview (gathering) or push it
  OUT harder (energetic)? (Leaning inward = "ingesting frames".)
- **Move life:** heal-trail + lift-bloom worth the `liftOffset` plumbing, or is the black-space fix
  + lift-dim ramp enough?
- **Per-act intensity:** should later acts get calmer (less chaos) as the GIF "settles," or keep
  uniform energy?

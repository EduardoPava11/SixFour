# SixFour — Proposals: Time-mapping of 2⁸/4⁴/16², and Zoomed GIFD Display

> Status: PROPOSAL MENU (2026-06-08). Two open decisions, each with options for the user to PICK.
> Math fact: `256 = 16² = 4⁴ = 2⁸`. With one axis = time (T): base = frames, exponent = #axes.
> So 16²→16 frames×16 colors, 4⁴→4 frames×64 colors, 2⁸→**2 frames**×128 colors. 2⁸ ≠ 8 frames.

---

## DECISION 1 — How do the three widgets map to TIME?

Only `4⁴` has exactly 4 axes (= R,G,B,T). So "what is time" in `16²` and `2⁸` is a choice. Pick one scheme.

### T1 — Only 4⁴ is temporal (simplest)
- **16²** = static 256-colour palette face (no time).
- **4⁴** = the quartet: R,G,B,T, **4 frames**, R,G,B bent to 4 levels. The delta lives here.
- **2⁸** = static Haar drill over the 256 colours (no time).
- *Pro:* matches "16² shows the palette"; one clear delta surface. *Con:* `2⁸`/`16²` carry no motion.

### T2 — Time/colour trade ladder (most symmetric) — answers "2⁸ = 2 frames"
- **16²** = **16 frames** × 16 colours (fine time, coarse colour).
- **4⁴** = **4 frames** × 64 colours (balanced — the quartet).
- **2⁸** = **2 frames** × 128 colours (fine colour, coarse time — a before/after pair).
- The widget you pick = your priority: time vs colour. Delta window = base frames {16, 4, 2}.
- *Pro:* fully symmetric, all three carry motion, mathematically exact. *Con:* `16²` only 16 colours in this mode (so it's a *motion* view, not the palette face — you'd keep a separate static 16² for the palette).

### T3 — Exponent = frames: temporal signatures (most radical)
- Each "colour" is a **trajectory**, base = levels per frame, exponent = frame count:
  - **2⁸** = **8-frame** binary signature (each frame on/off).
  - **4⁴** = **4-frame** 4-level trajectory.
  - **16²** = **2-frame** 16-level pair.
- Palette = motion patterns (temporal dither; cf. SATOR72). No R,G,B — purely temporal.
- *Pro:* "the palette IS motion" taken literally; richest time. *Con:* abandons R,G,B colour identity;
  biggest departure from the shipped colour palette.

> Note: T1 and T2 can co-exist — `16²` static palette (T1) for *choosing colours*, plus a `4⁴` quartet
> (both) for *seeing motion*. T3 is mutually exclusive with the colour-identity readings.

---

## DECISION 2 — How to show GIFD (256²) ZOOMED, on-atom, without looking bad?

You decided: GIFD doesn't fit, so **zoom in** — keep the 4pt atom and the grid cells, never shrink the
cell. All options below render GIFD pixels at the **standard 4pt** (crisp, on-atom); they differ in *how
you move through* the 1024pt canvas. None downsamples the live view (that's the "looks bad" trap).

### D1 — Region pan (a moving 64² window)
- Show a **64×64 region** of the 256² at 4pt = a 256pt square — pixel-identical crispness to GIFB. Drag to
  pan x/y across the 16 regions; scrub 256 frames.
- *Pro:* dead simple, reuses the GIFB hero exactly, fully crisp. *Con:* see only 1/16 at once; no overview.
```
256² canvas (1024pt)            visible: one 64² window @4pt
┌───────────────┐               ┌────────┐
│ ░░░░░░░░░░░░░ │               │ crisp  │  ← drag to pan
│ ░░░░░▓▓░░░░░░ │   →           │ 64²@4pt│
│ ░░░░░░░░░░░░░ │               └────────┘
└───────────────┘
```

### D2 — 4×4 tile navigator (structured zoom)
- The 256² = **16 tiles of 64²@4pt**. A small **16-cell map** (4×4) shows all tiles at a glance; tap a tile
  → its crisp 64²@4pt. The cube ladder's ×4 made literal.
- *Pro:* overview + crisp detail, on-atom, structured, reuses the 64² renderer 16×. *Con:* tile seams; you
  jump rather than pan smoothly.
```
[map 4×4]      tap → [crisp tile 64²@4pt]
■■■■
■■▣■   ▣ selected
■■■■
■■■■
```

### D3 — Focus + context loupe (best for "don't look bad")
- A **64² overview** of the WHOLE GIFD at 4pt (box-downsampled, shown small as context) + a **crisp 4pt
  loupe** you drag over it to inspect any region at native 256² resolution.
- *Pro:* you always see the whole frame AND a crisp detail; the classic big-image-small-screen answer.
  *Con:* two render passes; the overview is intentionally coarse.
```
overview 64²       loupe (crisp 64²@4pt of the boxed region)
┌──────┐           ┌────────┐
│ ▢▢▢▢ │  drag □   │ native │
│ ▢[□]▢ │  ───────►│ 256²px │
│ ▢▢▢▢ │           └────────┘
└──────┘
```

### D4 — Zoom-ladder in place (one viewport, LOD)
- One viewport; tap to step **16² → 64² → 256²**, each at 4pt (physical size grows 64→256→1024pt). At 256²
  the viewport scroll/pans (falls back to D1). Mirrors the collapse ladder GIFC→GIFB→GIFD.
- *Pro:* unifies all four GIFs in one control; honest LOD. *Con:* at full zoom it's D1 anyway.

---

## DECISION 3 — DISTINCT widget SHAPES (no two are the same shape)

Collision caught: drawing `2⁸` as a 16×16 grid makes it "another 16²" — the user can't tell it from the
palette. Fix: each widget owns a distinct form. **`16²` owns the square; nothing else may be a 16×16 grid.**

- **16²** = the **square** (16×16). The palette face. Static colours.
- **4⁴** = the **quartet** = a 1×4 strip of 4 mini-frames (time visible as 4 panels — not a square).
- **2⁸** = a distinct NON-square form. Pick one:
  - **P — pair-strip `128×2`**: a long thin ribbon of the 128 σ-pairs (cᵢ above σ(cᵢ)). Reads as a list,
    not a grid. (The "128:128 list" instinct.) *Leaning.*
  - **C — Haar cascade**: a triangle/tree `1→2→4→…→128`, the 8-level binary depth made visible.
  - **W — 8 wheels**: 8 spinnable binary digit-wheels (an 8-bit address picker; the old AddressPicker).

Principle: the SHAPE is the radix — square = "all colours at once", 4-panel = "across the quartet", ribbon/
cascade/wheels = "deep binary hierarchy of pairs". Distinct shapes ⇒ the user always knows which lens.

## How to pick
Tell me **one from Decision 1** (T1 / T2 / T3) and **one from Decision 2** (D1 / D2 / D3 / D4). I'll fold
the choice into `SIXFOUR-FOUR-GIF-UIUX-WORKFLOW.md` and start the spec (`Spec.QuartetDelta` first if you
keep a temporal quartet; the GIFD viewport mode after).

My leaning (yours to override): **T1 + D3** — keep `16²` as the honest palette face and `4⁴` as the only
motion surface (least confusing to a user), and show GIFD as focus+context so it never looks bad. But T2 is
the more beautiful structure if you want every widget to carry motion.

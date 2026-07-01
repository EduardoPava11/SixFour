# PICO-8 cell-grid RGB tools

> Status: LIVING · Last updated: 2026-06-30 · Owner: SixFour

The RGB representation of the SixFour iPhone cell-grid UI. PICO-8 is the
**look/demo sketchpad only**, the Haskell spec is the source of truth. These
tools *mirror* the spec so we can see the grid, the rounded corners, and widget
sizing in colour before any of it ports to Swift/Metal.

Mirrored from:
- `spec/src/SixFour/Spec/Lattice.hs`, the `100×218` @ 4pt lattice + the rounded
  corner (`cornerRadiusPt`, `cornerExponent`, `cellOnScreen`).
- `spec/src/SixFour/Spec/GridLayout.hs`, the capture-scene widgets
  (`preview 64×64`, `palette 16×16`) + `lawWidgetsClearCorners`.

## The tools

| File | What it does |
|---|---|
| `cellgrid.p8` | The PICO-8 **rectangle-making layout tool**. Make / name / move / resize widgets on the rounded iPhone 17 Pro cell grid, zoom, see coordinates + the layout laws live, then copy the numbers into the spec. Letters pick a tool, arrows act. `on_screen()` is a line-for-line port of `Lattice.cellOnScreen`. |
| `render_grid.py` | Headless full-RGB renderer + **parity harness**. Reads constants straight from the spec, re-checks the four proven laws over the Python port, and writes `cellgrid_overview.png` + `cellgrid_corner.png` (view the grid with no PICO-8 at all). Zero third-party deps. |
| `check_sync.py` | Fails loudly if the cart's constants have drifted from `Lattice.hs` / `GridLayout.hs`. |
| `verify.sh` | One-shot gate: sync + parity. Run after any spec change. |

## Rectangle-tool controls (press **H** in-cart for this menu)

Letters pick a tool, arrows act on the selected rectangle. A tap moves 1 cell;
**hold** to accelerate.

| Key | Action |
|---|---|
| **M** / **R** / **S** | tool: move / resize / select (in select, L-R arrows change selection) |
| **N** / **D** | new rectangle / delete selected |
| **E** | rename the selected rectangle (type, Enter or O/X to finish) |
| **I** | toggle the selected rectangle interactive (touch-floor law applies) |
| **G** | cycle grid snap (1 / 2 / 4 / 8 cells); moves, resizes, and drags all snap |
| **F** | recenter the view on the selection |
| **+ / -**, mouse wheel | zoom (recenters on the selection) |
| **mouse** | click to grab (widget under cursor, else the selection), drag to move; a crosshair cursor with the hovered cell coordinate is drawn |
| **Q** | toggle circle ↔ squircle (`cornerExponent`) to audition corner fidelity |
| **C** | copy the whole layout to the clipboard as spec-ready `lrCol/lrRow/lrW/lrH` |
| **V** | revert all rectangles to the spec's `captureScene` |

Live readout: coordinates around the selected rectangle (top-left, bottom-right,
`w×h`), a HUD line with cells + points, and the scene law flags `cor`(clears
corners) / `dis`(disjoint) / `fl`(touch floor) / `sa`(safe-area clearance). The
flag line is green only when all four pass, which means the layout would pass all
five `GridLayout` laws under `cabal test`.

Performance note: the background (rounded phone + safe bands) is cached and
blitted with `memcpy` each frame, and the view does not auto-pan while you move a
rectangle, so dragging stays smooth even at fit zoom.

The **C** shortcut is the discover→spec bridge: nudge a layout you like, press
**C**, paste the numbers into `GridLayout.captureScene`, and `cabal test`. The
sketchpad proposes; the spec still decides.

## Colour legend (RGB representation)

| Colour | Cell class |
|---|---|
| black | off-display (clipped rounded corner) |
| dark blue | on-screen background |
| purple | OS safe-area band (Dynamic Island / home indicator) |
| green | preview widget (`64×64`, non-interactive) |
| red | palette / capture widget (`16×16`, interactive) |

(The `.p8` cart uses the nearest PICO-8 palette indices; `render_grid.py` uses
true RGB, since the phone is not limited to 16 colours.)

## Running

**No purchase / no install**, the cart runs in the free PICO-8 Education
Edition: open <https://www.pico-8-edu.com>, then paste the contents of
`cellgrid.p8` into the code editor and press the run button (Ctrl-R). It also
loads unchanged in the paid PICO-8 desktop app (`load cellgrid.p8` / `run`).

Prefer no runtime at all? `python3 render_grid.py` writes the PNGs.

```bash
cd studio/pico8
./verify.sh                 # sync + parity gate
python3 render_grid.py      # write cellgrid_overview.png + cellgrid_corner.png
```

## The discipline (spec-first)

If the alignment changes, change the **Haskell spec first**, prove it with
`cabal test`, then update `cellgrid.p8` to match and run `./verify.sh`. The cart
never leads the spec. `cornerExponent` is the one knob to audition here: press
**Q** (and zoom into a corner) to compare a squircle against the `n=2` circle,
then, if you like it, change `cornerExponent` in `Lattice.hs`, re-prove, and
re-sync.

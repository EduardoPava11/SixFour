# Session notes: iPhone cell-grid alignment + PICO-8 tooling (2026-06-30)

> Status: HANDOFF · Owner: SixFour

## What this session did

Started the **iPhone 17 Pro cell-grid alignment** work (the screen layout grid),
spec-first, and built a PICO-8 tool set to visualize and iterate it.

### Spec (the source of truth)
- `Spec.Lattice`: modeled the **rounded display**: `cornerRadiusPt = 56`
  (14 atoms, snapped from the ~55 pt physical radius; device-verify pending for
  17 Pro), `cornerExponent` (2 = circle now, ~5 = squircle), `cellOnScreen`
  (all-integer superellipse, no float), `onScreenCells`. Laws:
  `lawCornerRadiusIsCells`, `lawCornersSymmetric`, `lawCornerMonotone`,
  `lawGridSpansScreen` (full-bleed, clip only in corners).
- `Spec.GridLayout`: `lawWidgetsClearCorners` (the widget-sizing law: every
  widget cell lands on the rounded display).
- Wired into `cabal test`: **1314 green**.

### studio/pico8 (PICO-8 = the RGB look/demo sketchpad ONLY)
- `cellgrid.p8`: a rectangle-making layout tool. Letters pick a tool
  (m/r/s = move/resize/select), arrows act; n/d/e/i/c/v/g/f/q commands; mouse
  click+drag; showable crosshair cursor; grid snap (g); cached-background fast
  dragging (memcpy, no auto-pan on move); zoom (+/-, wheel); live coordinates
  around the selection; live law flags `cor/dis/fl/sa` (green = would pass
  `cabal test`). `on_screen()` is a line-for-line port of `Lattice.cellOnScreen`.
- `render_grid.py`: headless zero-dep PNG renderer + parity harness (reads
  constants from the spec, re-checks the four laws over the Python port).
- `check_sync.py`: fails if the cart's constants drift from the spec.
- `verify.sh`: one-shot sync + parity gate.
- `README.md`, `UX-IDEAS.md`.

### Docs
- `docs/tools/{PICO-8,VOXATRON,PICOTRON}.md`: Lexaloffle tool living references.
- `spec/exploration/VOXEL-PIXEL-GIF89A-FRAMEWORK.md`: the GIF89a to voxel-pixel design.
- `studio/TOOLING-STANDARDS.md`: from the standardization workflow.

## How to run
```bash
# the tool (free PICO-8 Edu Edition or the desktop app)
/Applications/PICO-8.app/Contents/MacOS/pico8 -run \
  "$HOME/Library/Application Support/pico-8/carts/cellgrid.p8"
# gates
cd studio/pico8 && ./verify.sh
python3 render_grid.py          # writes cellgrid_overview.png + cellgrid_corner.png
cd spec && cabal test spec-tests
```

## Discipline (do not break)
Alignment changes go **spec-first**: edit `Lattice.hs` / `GridLayout.hs`, run
`cabal test`, regenerate contracts, then sync the cart and run `./verify.sh`. The
PICO-8 cart never leads the spec. In-cart, press **C** to copy the current layout
as spec-ready numbers to paste into `GridLayout.captureScene`.

## Known gaps / next steps (ranked)
1. **Parity vs Haskell ground truth** (top of `TOOLING-STANDARDS.md` backlog):
   `render_grid.py` re-checks laws over a Python PORT of `cellOnScreen`, not
   against the Haskell output, so a mis-port could pass. Fix: dump a golden
   vector from the spec that both the Python and the cart must match.
2. **Codegen to Swift**: the rounded-corner model is proven but NOT yet emitted
   to `LatticeContract.swift` or used to mask the full-bleed field on device.
3. **UX backlog**: see `studio/pico8/UX-IDEAS.md` (red-flag "why", on-canvas
   resize handles, magnetic guides, undo/redo, multi-select).

## Git state at sunset
- All work committed to **master** (`ba98a07` + this notes commit + the merge).
- Branch `studio/cellgrid-rect-tool` exists on origin (github.com/EduardoPava11/
  SixFour); it is superseded by master and recorded as merged (`-s ours`).
- Gotcha observed: the working tree was switched off the feature branch mid-session
  (to master); the work was safe because it was committed + pushed. Rescue
  untracked files before any git operation.

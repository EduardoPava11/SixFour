# Cell-grid tool: UI/UX improvement ideas

> Status: LIVING · Last updated: 2026-06-30 · Owner: SixFour

A running idea list for the studio/pico8 cell-grid tooling. The ★ items are
quick wins. This complements the prioritized backlog in
`studio/TOOLING-STANDARDS.md` (which is more about correctness and conventions);
this file is about interaction and feel.

## In-cart interaction

1. ★ **Red-flag "why".** When `cor / dis / fl / sa` goes red, name the offender
   (for example "palette overlaps preview", "r3 pokes a corner", "r2 enters the
   Dynamic Island"). Turns a fail into an actionable fix instead of a guess.
2. ★ **Duplicate (Y) + numeric entry.** Duplicate the selected rectangle, and let
   the user type an exact `col,row,w,h` for precision beyond arrow nudging.
3. **On-canvas resize handles.** Drag a rectangle's corner or edge with the mouse
   to resize, not only the arrow keys.
4. **Magnetic guides.** Snap a rectangle edge to another rectangle's edge, the
   screen centre, or the safe-area line (alignment snapping, on top of grid snap).
5. **Multi-select + align/distribute.** Select several rectangles and move them
   together; align-left / centre / distribute-evenly (the layout-tool staples).
6. **Undo / redo.** A small state stack. Essential once many rectangles exist.
7. **Overlay toggles.** Safe-area band, corner-radius guide, and a touch-floor
   "ghost" minimum-size ring around interactive rectangles.
8. **Pan tool for zoomed views.** Space-drag or a dedicated pan mode, so the view
   is not tied only to the selection when zoomed in.
9. **In-cart sync indicator.** Show whether the current layout equals the spec's
   `captureScene` (an in-cart echo of `check_sync.py`), so drift is visible.
10. **Copy as Haskell.** Alongside the raw numbers, offer a copy that emits a
    ready-to-paste `LRegion` record for `GridLayout.captureScene`.

## Toolset DX (studio-wide)

11. ★ **`launch.sh`.** One command to copy the cart into the PICO-8 carts folder
    and launch it (currently done by hand).
12. ★ **Auto-open the PNG** after `render_grid.py`, and a `--watch` mode that
    re-runs the sync + parity gate when the spec changes.
13. **The real parity fix (top backlog item).** Dump a golden vector from the
    Haskell `cellOnScreen` so the Python port and the cart are checked against
    ground truth, not just against each other. See `studio/TOOLING-STANDARDS.md`.
14. **Consistent `--help`** across the Python tools, and a single `studio` entry
    point that lists every tool.

## Notes

Anything here that changes the LAYOUT itself (sizes, positions, corner shape)
must still go spec-first: change `Lattice.hs` / `GridLayout.hs`, run `cabal test`,
then sync the cart. The tool proposes; the spec decides.

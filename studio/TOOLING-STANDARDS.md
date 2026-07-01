# SixFour Studio Tooling Standards

> Status: DRAFT

These standards govern the design/sketchpad tooling under `studio/` (today: `studio/pico8/`). They do NOT govern the shipped iOS app, which is bound by the stricter contract in `/Users/daniel/SixFour/CLAUDE.md`. Where the two overlap, the CLAUDE.md contract wins.

## 1. Scope and principles

The `studio/` tools exist to let humans SEE and NUDGE a layout in colour before it becomes spec. They are auditioning surfaces, never authorities.

1. **Spec-first.** The Haskell spec (`spec/src/SixFour/Spec/*.hs`) is the single source of truth. A studio tool may only MIRROR spec values, never define them. If a layout should change, the change lands in the spec first (edit `.hs`, `cabal test`, `cabal run spec-codegen`), then the mirror is re-synced. The cart never leads the spec. The `C` (copy) bridge in `cellgrid.p8` proposes numbers for a human to paste into `GridLayout.captureScene`; the spec still decides.
2. **Zero-dependency.** Studio Python tools are stdlib-only (today: `re`, `sys`, `pathlib`, `struct`, `zlib`), no pip, no venv. The PICO-8 cart is a single self-contained `.p8`. This mirrors the shipped app's zero-third-party contract even though the tooling is not shipped.
3. **PICO-8 is sketchpad-only.** `cellgrid.p8` is the RGB LOOK/DEMO of the cell-grid UI. It produces no shipped artifact and carries no authority. Its only output that matters is the numbers a human copies into the spec.
4. **Byte-exact where the spec is exact.** Any geometry a tool ports (for example `Lattice.cellOnScreen`) must reproduce the spec's EXACT arithmetic, integer-for-integer, not a mathematically-equivalent float rewrite. Rendered pixels (PNGs) are derived artifacts and are NOT byte-gated, because stdlib `zlib` output is not guaranteed stable across platforms; determinism attaches to the pure integer geometry, not to compressed image bytes.

## 2. Conventions

### 2.1 File and directory layout

- One directory per tool family under `studio/` (today `studio/pico8/`).
- Each family contains: the interactive artifact (`cellgrid.p8`), a spec-parsing/sync guard (`check_sync.py`), a headless renderer plus parity harness (`render_grid.py`), a one-shot gate (`verify.sh`), and a `README.md`.
- `check_sync.py` is the ONE canonical parser of spec constants. Other tools in the family import its helpers (`LATTICE`, `GRIDLAYOUT`, `hs_int`, `hs_regions`) rather than re-regexing the spec, as `render_grid.py:24` already does. This coupling must be stated in both file headers and the README tools table, so a rename of `check_sync.py` does not silently break the harness.
- Derived outputs (`cellgrid_overview.png`, `cellgrid_corner.png`, `__pycache__/`) are gitignored and regenerable, never committed as golden.

### 2.2 Naming

Three tiers spell the same atom three ways. The convention is: spec camelCase is authoritative; the cart uses short snake/abbrev; Python uses UPPER_SNAKE.

- Every mirrored constant in every tool file carries a comment naming its origin, using the cart's existing convention (for example `corner_pt = 56 -- Lattice.cornerRadiusPt` at `cellgrid.p8:25`). This convention MUST be applied in `render_grid.py` too; today `GIFPX`, `COLS`, `CORNER_N`, `RAD_HALF` (`render_grid.py:31-38`) carry no `Spec.Name` annotation and a reader cannot map `CORNER_N` back to `cornerExponent` without opening `check_sync.py`.
- Unit suffixes are unambiguous: `_pt` for points, `_cells` for cell counts, `_rows` for row counts. Never reuse one suffix for two quantities. Today `render_grid.py` overloads `_R`: `CORNER_R` is a radius in cells while `SAFE_TOP_R`/`SAFE_BOT_R` are sizes in rows. Rename to `CORNER_CELLS`, `SAFE_TOP_ROWS`, `SAFE_BOT_ROWS`.
- The README carries ONE crosswalk table mapping spec name to cart name to Python name for every mirrored constant.

### 2.3 How a tool MIRRORS the spec

- No bare numeric literal in a mirror may duplicate a value that ALSO exists as a named spec binding. If the spec names it, the mirror reads it through `check_sync`'s parser and `check_sync` compares it. A duplicated-but-unguarded literal is a lint failure.
- This rule is currently violated by the safe-area band: `safeTopPt = 62` and `safeBottomPt = 34` exist as named bindings (`Lattice.hs:159,164`) but are hardcoded as `62`/`34` in both `render_grid.py:37-38` and `cellgrid.p8:30-31`, and `check_sync.py` never compares them. Fix: read them via `hs_int(lat, "safeTopPt")` / `hs_int(lat, "safeBottomPt")`, add named `safe_top_pt`/`safe_bot_pt` bindings to the cart, and add both to the `spec` and `cartv` dicts in `check_sync.py:67-90`.
- Adding a mirrored constant means adding it to `check_sync`'s spec+cart dicts in the SAME commit, so guard coverage grows with the surface.

### 2.4 How a tool GATES (sync + parity)

Two distinct guards, both wired into `verify.sh`:

- **Sync** (`check_sync.py`): parses pinned constants out of the spec and the cart and fails on any drift. Extraction MUST anchor to a named binding or a named scene entry, never a positional whole-file regex. Today `hs_regions()` (`check_sync.py:35-39`) matches ANY `(lrCol,lrRow,lrW,lrH)` tuple across the whole `GridLayout.hs` and assigns `regions[0]->preview`, `regions[1]->palette` by position. Reordering `captureScene` or adding another example region above it silently mis-maps the guard while it reports IN SYNC. Anchor to the `captureScene` block and the quoted `"preview"`/`"palette"` names, or parse the spec-emitted `Generated/` contract instead.
- **Parity** (`render_grid.py --verify`): today re-checks paraphrased laws (symmetry, monotonicity, spans-screen, widgets-clear-corners) over the Python port. This is NECESSARY BUT NOT SUFFICIENT: many different clip functions satisfy those four laws, so a mis-ported `dc`/`dr` formula that stays symmetric and monotone would pass. Nothing in the pipeline ever executes the real Haskell `cellOnScreen` and compares per-cell output, and the cart's own Lua `on_screen()` (`cellgrid.p8:45-52`) is executed by NO gate at all. The README/`verify.sh` phrase "parity against what cabal test proves" and the cart's "line-for-line port" claim therefore overclaim. See the backlog: parity must become byte-equality against a spec-dumped golden.

Exit-code contract for every gate script, documented in its docstring and in `verify.sh`: `0` = pass/in-sync, `1` = drift, `2` = tool error (missing file or unparseable binding). `check_sync.py:22-24` already exits `2` via `die()` but documents only `0`/`1`. `verify.sh` runs under `set -euo pipefail` so any non-zero fails the gate; keep it that way so a parse error is never misread as clean.

Law-mirroring completeness: the cart's on-screen status must verify EVERY scene law the spec proves. Today `scene_status()` (`cellgrid.p8:240-249`) reports `cor`/`dis`/`fl` (corners, disjoint, touch-floor) but omits `lawSafeAreaClearance` (`GridLayout.hs:157-161`). A rectangle over the Dynamic Island band shows all-green while `cabal test` would fail, defeating the copy-to-spec bridge. Add a `sa` flag folded over all rects (`lrRow*gifPx >= safeTopPt` and `(lrRow+lrH)*gifPx <= screenHeightPt - safeBottomPt`) and include it in `ok` and the HUD line. Green in the sketchpad must mean green in `cabal test`, never a subset.

### 2.5 Documentation requirements

- The in-cart `H` menu (`draw_menu`, `cellgrid.p8:265-280`) is the canonical in-cart reference: every binding present in `_update` appears in the menu, INCLUDING how to exit every mode (rename, select). Today `e rename` gives no exit hint.
- The README tools table lists each tool, its inter-file dependencies (for example that `render_grid.py` reuses `check_sync.py`'s parsers), and the exit-code contract.
- Any doc that states "the N proven laws" must match the number and names actually run. Today `render_grid.py:6-9` and `README.md:21` say "four" but `verify()` runs FIVE checks (the extra `physical corner (0,0) is clipped`, `render_grid.py:110-111`). Prefer wording that does not hardcode a brittle count, and label sanity checks separately from proven-law-parity checks so each parity check cites the named spec law it mirrors.
- Prose rule (from CLAUDE.md and the user's standing instruction): NO em-dashes anywhere in studio prose or tool output. Use commas, periods, or colons. `verify.sh` should grep the studio tree for U+2014 and U+2013 and fail on a hit so the rule is self-enforcing.

### 2.6 Portability

- Studio Python tools are stdlib-only with a pinned floor (Python >= 3.8, no pip, no venv). `verify.sh` grep-guards every studio `*.py` import block against a stdlib allowlist so the zero-dep promise is gated, not just asserted in prose.
- Sibling imports must be CWD-independent. `render_grid.py:24` does `from check_sync import ...` relying on its own directory being on `sys.path`; this holds via `verify.sh` (which `cd`s) but breaks under `python -m` or from another CWD. Add `sys.path.insert(0, str(Path(__file__).resolve().parent))` before the import.
- Document the runtime matrix per tool: which features work in the free PICO-8 Education Edition / browser player versus which require the desktop app. The `C` copy bridge uses `printh(s,"@clip")` (`cellgrid.p8:123`); the Edu sandbox may not support clipboard output, so the one feature that closes the sketchpad->spec loop can silently no-op on the runtime the README pushes users toward (`README.md:64-69`). Every interactive feature a runtime cannot support gets an on-screen fallback (for the `C` bridge: also print the `lrCol/lrRow/lrW/lrH` block to the PICO-8 console so it is readable and retypable). The cart's devkit dependency (`poke(0x5f2d,1)`, `cellgrid.p8:71`) must be commented in-cart as REQUIRES devkit keyboard+mouse.

## 3. Adding a new studio tool (checklist)

1. Stdlib-only and self-contained. No pip, no venv, Python >= 3.8. A single `.p8` if it is a cart. CWD-independent invocation (resolve paths from `Path(__file__)`).
2. Reuse `check_sync.py`'s spec parser (`hs_int`, `hs_regions`, `LATTICE`, `GRIDLAYOUT`). Do NOT re-regex the spec.
3. Mirror the spec's EXACT arithmetic (integer forms), not a float rewrite. Every mirrored constant is read from the spec or added to `check_sync`'s compared dicts in the same commit. No unguarded duplicated literal.
4. Every ported function is EXECUTED against a spec-dumped golden (see backlog item 1), not just checked against paraphrased laws. Cite the named spec law each parity check mirrors.
5. Register the tool in `verify.sh` in the same commit that introduces it, so the one-shot gate stays the complete gate.
6. Gitignore its derived artifacts (PNGs, `__pycache__`).
7. Add a README row, a crosswalk-table entry for any new mirrored constant, and a runtime-matrix note. Document the tool's exit-code contract (0/1/2).
8. Annotate every ported constant with its `Spec.Name` origin comment. Use unambiguous unit suffixes (`_pt`, `_cells`, `_rows`).
9. No em-dashes in prose or output.

## 4. Prioritized improvement backlog

Most impactful first. Effort is S (under an hour), M (a few hours), L (a day-plus). Dimension keys: SP = sync-parity, UX = cart-ux, DN = docs-naming, PR = portability-repro.

| # | Item | Why | Effort | Dimension |
|---|---|---|---|---|
| 1 | **Parity is NOT checked against Haskell ground truth.** Replace paraphrased-law checks with byte-equality against a golden dumped FROM the spec (for example the 28x28 corner bitmap of `cellOnScreen`, the total clipped-cell count, and a hash of `onScreenCells`), emitted into `SixFour/Generated/` via `spec-codegen`. Assert `render_grid.py` and, ideally, the cart's Lua `on_screen` reproduce it exactly. | Four laws are necessary but not sufficient; a mis-ported formula that stays symmetric+monotone passes today, and `verify.sh`/README claim "parity against what cabal test proves" and "line-for-line port" without any executed equality check. This is the headline gap. | L | SP |
| 2 | **Guard `safeTopPt`/`safeBottomPt`.** Read `62`/`34` from the spec in `render_grid.py:37-38` and the cart, and add both to `check_sync.py`'s `spec`+`cartv` dicts. | Two named spec bindings are hardcoded as magic numbers in both mirrors and compared by nothing, so the purple safe band can drift while `verify.sh` reports IN SYNC. Flagged by three of four audits. | S | SP, DN, PR |
| 3 | **Add the safe-area flag to the cart HUD.** Extend `scene_status()` (`cellgrid.p8:240-249`) with an `sa` flag mirroring `lawSafeAreaClearance` and fold it into `ok`. | The cart's whole purpose is "copy numbers so the spec passes"; a false green over the Dynamic Island band wastes a spec round-trip. Mirror all five scene laws or none. | S | UX |
| 4 | **Wire the gate into the automated pipeline.** Emit the cart golden as part of `spec-codegen` (so a stale mirror shows as a dirty `Generated/` file) and/or add `check_sync.py`+`render_grid.py --verify` next to `cabal test`. | Today `verify.sh` is standalone and manual; drift is caught only if a human remembers to run it after a spec change. Spec-first must be enforced, not remembered. | M | SP |
| 5 | **Port the exact-integer corner form for all `n`.** Replace the float rewrite `(dc/RAD_HALF)**n + (dr/RAD_HALF)**n <= 1` (`render_grid.py:61-63`, `cellgrid.p8:51`) with the spec's integer `dc**n + dr**n <= radHalf**n` (`Lattice.hs`), and add a golden at `n=2` AND one `n!=2` value. In the cart, where `radHalf**5` overflows 16.16 fixed point, label the `Q`-key squircle audition explicitly as approximate, not parity, in code and menu. | The `cornerExponent != 2` branch silently diverges from spec arithmetic with zero gate coverage; the `Q` audition path can mislead. | M | SP, UX |
| 6 | **Anchor `hs_regions()` to named scene entries.** Bind extraction to the `captureScene` block and the quoted `"preview"`/`"palette"` names, or parse the spec-emitted `GridLayout` contract; fail loudly on an unexpected region count. | A positional whole-file regex mis-maps if `captureScene` is reordered or another region is added above it, while reporting IN SYNC. | M | SP |
| 7 | **Fix rename-mode double-binding.** Confirm rename on Enter only in `cellgrid.p8:134`; drop `btnp(4)/btnp(5)` or gate them behind `k==""`. Then correct the README "Enter or O/X to finish" and add an exit hint to the `H` menu. | PICO-8 face buttons map O=Z/C and X=X/V, so typing `box`, `crop`, `nav` silently terminates rename. Text entry must not double-bind printable keys to gamepad buttons. | S | UX |
| 8 | **Well-formed exported identifiers.** Use a monotonic `rid` counter for new-rect names instead of `"r"..(#rects+1)` (`cellgrid.p8:110`), and guard backspace so a name is never empty (`cellgrid.p8:135`). | After a delete, `#rects+1` reuses a prior number, so `copy_layout` can emit two lines with the same name; an empty name emits a label-less line. Both produce invalid spec paste. | S | UX |
| 9 | **Single-source the HUD point readout.** Replace the four literal `4`s in `cellgrid.p8:258` with `gifpx`. | `gifpx` is defined precisely to be single-sourced; the spec rebased 6->4pt once already, and a future rebase would leave the HUD reporting wrong points while every other number updates. | S | UX |
| 10 | **Reconcile the law count in docs.** Update `render_grid.py:6-9` and `README.md:21` to match the five checks `verify()` runs, label the corner-clipped check as a sanity check distinct from proven-law parity, and cite each parity check's named spec law. | Docs say "four", code runs five; a reader cannot map Python checks to actual theorems. | S | DN, PR |
| 11 | **Reframe the control vocabulary.** In the header (`cellgrid.p8:16`) and `draw_menu` (`cellgrid.p8:268`), distinguish stateful TOOLS (`m`/`r`/`s`) from instantaneous COMMANDS (`n`/`d`/`e`/`i`/`c`/`v`/`q`/`h`). | "letters=tool arrows=act" is true for only 3 of 12 bindings and mis-teaches the interaction. | S | UX |
| 12 | **Make sibling import CWD-independent and pin the runtime.** Add `sys.path.insert(0, ...)` before `from check_sync import` (`render_grid.py:24`); document Python >= 3.8, stdlib-only, and add a `verify.sh` grep-guard for non-stdlib imports and for em-dashes. | Protects portability and the zero-dep promise as more tools are added; makes the no-em-dash rule self-enforcing. | M | PR, DN |
| 13 | **Document the runtime matrix and the `C` bridge fallback.** State that `printh("@clip")` needs the desktop app, add an on-screen print of the layout block as an Edu-Edition fallback, and comment the devkit `poke`. | The one feature that closes the sketchpad->spec loop can silently no-op on the Edu Edition the README recommends. | M | PR, UX |
| 14 | **Clarify the colour legend and hold-to-accelerate.** Note in the README that green=preview/red=palette is `render_grid.py`'s semantic mapping while the cart tints by draw order (`rcols`, `cellgrid.p8:40,229`); make select-mode arrow repeat consistent with move/resize acceleration (`cellgrid.p8:179-181`). | Legend does not describe the cart's actual colouring for a 3rd+ rect; hold acceleration silently does nothing in select mode. | S | DN, UX |
| 15 | **Rename overloaded `_R` suffix.** `SAFE_TOP_R`/`SAFE_BOT_R` -> `SAFE_TOP_ROWS`/`SAFE_BOT_ROWS`; consider `CORNER_R` -> `CORNER_CELLS` (`render_grid.py:34,37-38`). | One suffix denotes two units (cells vs rows); ambiguous. | S | DN |

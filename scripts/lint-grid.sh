#!/usr/bin/env bash
#
# lint-grid.sh — the GRID design-language build gate (v3.0, the 4 pt atom).
#
# Enforces "operations follow the grid" from docs/SIXFOUR-DESIGN-LANGUAGE.md across
# ALL of SixFour/UI (not just the capture HUD). The invariants:
#
#   LINT-PLACEMENT     — a governed widget is placed ONLY by claiming cells
#                        (`.place(_:)`); no raw `.position`/`.offset` at a composition
#                        site (except the sanctioned primitive + `// LINT-ALLOW-POSITION`).
#   LINT-SINGLE-LATTICE— there is ONE pitch owner (`GlobalLattice`/`SixFourLattice`);
#                        no second atom (`CaptureGrid`-style) may re-appear.
#   LINT-DRAW-VOCAB    — (capture HUD) no glass / opacity-on-a-cell / raw vector prims.
#   LINT-SINGLE-PITCH  — (capture HUD, hard) every dimension goes through
#                        GlobalLattice.pt()/.gif(); (other screens, WARN) legacy
#                        bare-literal debt is reported, not yet failed.
#   LINT-DETENT        — the cellTick haptic (`Haptics.play(1)`) is fired ONLY by the
#                        frame-locked flush in CellDetent.swift (≤1/20fps-frame); a direct
#                        `play(1)` elsewhere is an un-frame-locked detent.
#   LINT-GOLDEN        — the Spec.* sources of truth + generated contracts exist.
#
# SCOPE: the composition layer (screens that ASSEMBLE widgets). Primitive internals
# (Cell*/PixelGrid/the place primitive/rasterizers) legitimately use Text/UIKit/
# Canvas/.position to draw — police usage, not the framework's guts.
#
# Exit 0 = clean; exit 1 = drift (fails the build). Run from the repo root.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 2

UI_DIR="SixFour/UI"
# The capture HUD is now the live phase field of the ONE surface (the old
# Screens/Capture/CaptureView.swift was demolished in the one-surface collapse).
HUD="SixFour/UI/Scenes/Live/LivePhaseField.swift"
fail=0

note() { printf '  ✘ %s\n' "$1"; fail=1; }
ok()   { printf '  ✓ %s\n' "$1"; }
warn() { printf '  ⚠ %s\n' "$1"; }

# Files where raw drawing vocab / .position is legitimate (primitives & rasterizers).
is_primitive() {
  case "$(basename "$1")" in
    ScreenLattice.swift) return 0 ;;          # THE placement primitive (owns .position)
    Cell*.swift)         return 0 ;;          # cell rasterizers (CellText/CellSprite/CellShapes/…)
    PixelGrid.swift)     return 0 ;;          # GraphicsContext flat-fill primitive
    ContestedCellGridView.swift) return 0 ;;  # the contention-surfacing view
    GIFPlayer.swift)     return 0 ;;          # video surface
    GridlineField.swift) return 0 ;;          # bakes an indexed bitmap (CoreGraphics)
    CameraPreview.swift) return 0 ;;          # UIViewRepresentable
    PaletteCloudView.swift|VoxelCubeView.swift) return 0 ;;  # Metal / 3D canvases
    *) return 1 ;;
  esac
}

# Gather composition-site files (everything in UI that is not a primitive).
COMP=()
while IFS= read -r f; do
  is_primitive "$f" || COMP+=("$f")
done < <(find "$UI_DIR" -name '*.swift' | sort)

# ── LINT-PLACEMENT (all composition sites) ─────────────────────────────────
echo "GRID lint — LINT-PLACEMENT (grid-following placement, all of $UI_DIR)"
placement_fail=0
for f in "${COMP[@]}"; do
  hits=$(grep -nE '\.(position|offset)\(' "$f" | grep -v 'LINT-ALLOW-POSITION')
  if [ -n "$hits" ]; then
    note "raw .position/.offset at a composition site (use .place(_:) on a GridRegion): $f"
    printf '%s\n' "$hits" | sed 's/^/      /'
    placement_fail=1
  fi
done
[ "$placement_fail" -eq 0 ] && ok "every governed widget is placed by .place(_:) (no raw positioning)"

# ── LINT-SINGLE-LATTICE (all of UI) ────────────────────────────────────────
echo "GRID lint — LINT-SINGLE-LATTICE (one pitch owner)"
# The retired 4 pt CaptureGrid (or any clone) must never re-appear.
if grep -rn 'CaptureGrid' "$UI_DIR" --include='*.swift' | grep -q .; then
  note "retired second lattice 'CaptureGrid' re-introduced:"
  grep -rn 'CaptureGrid' "$UI_DIR" --include='*.swift' | sed 's/^/      /'
else ok "no CaptureGrid (the retired second pitch stays gone)"; fi
# Only GlobalLattice may declare the atom constants; everything else is a facade.
atom_owners=$(grep -rnE 'static let (gifPx|subPt|cellPt)[[:space:]]*[:=]' "$UI_DIR" --include='*.swift' \
              | grep -vE 'GlobalLattice\.swift')
if [ -n "$atom_owners" ]; then
  note "a second owner of the atom constants (gifPx/subPt/cellPt) — only GlobalLattice may:"
  printf '%s\n' "$atom_owners" | sed 's/^/      /'
else ok "GlobalLattice is the sole owner of cell↔point math (Law #5)"; fi

# ── LINT-DRAW-VOCAB (capture HUD) ──────────────────────────────────────────
echo "GRID lint — LINT-DRAW-VOCAB ($HUD)"
if grep -nE '\.opacity\(' "$HUD" | grep -vE '\.opacity\(0\)|\.opacity\(0\.0\)' | grep -q .; then
  note "opacity-on-a-cell (only .opacity(0) passthrough is allowed):"
  grep -nE '\.opacity\(' "$HUD" | grep -vE '\.opacity\(0\)|\.opacity\(0\.0\)' | sed 's/^/      /'
else ok "no shading opacity"; fi
if grep -nE '\b(dimText|hairline)\b' "$HUD" | grep -q .; then
  note "retired opacity token (dimText/hairline) on the HUD:"
  grep -nE '\b(dimText|hairline)\b' "$HUD" | sed 's/^/      /'
else ok "no retired opacity tokens"; fi
if grep -nE 'Glass(InfoChip|IconButton|ToolbarCluster|EffectContainer)|glassEffect|cardCorner' "$HUD" | grep -q .; then
  note "glass material on the HUD (retired; Review/Settings only):"
  grep -nE 'Glass(InfoChip|IconButton|ToolbarCluster|EffectContainer)|glassEffect|cardCorner' "$HUD" | sed 's/^/      /'
else ok "no glass on the HUD"; fi
if grep -nE '\bRoundedRectangle\b|\bCircle\(\)|\.stroke\(|\bText\(' "$HUD" | grep -q .; then
  note "raw SwiftUI primitive on the HUD (use CellText/CellShapes):"
  grep -nE '\bRoundedRectangle\b|\bCircle\(\)|\.stroke\(|\bText\(' "$HUD" | sed 's/^/      /'
else ok "no raw vector primitives"; fi

# ── LINT-SINGLE-PITCH (all composition sites, HARD) ────────────────────────
# Every dimension goes through GlobalLattice.pt()/.gif(). The check matches the
# SwiftUI layout MODIFIERS (`.frame(` / `.padding(`) and the `spacing:` / `minLength:`
# labels with a literal digit INSIDE the call — so a data field like `var frame: Int`
# (the GIF frame index) never trips it. `#Preview` blocks are debug-only scaffolding
# (raw SwiftUI is legitimate there) and are skipped. A literal 0 ("no gutter") is exempt.
echo "GRID lint — LINT-SINGLE-PITCH (all of $UI_DIR, #Preview excluded)"
pitch_scan() {   # prints "file:line:text" for each SHIPPED bare-pitch literal in $1
  awk '
    BEGIN { inprev = 0; depth = 0 }
    {
      if ($0 ~ /#Preview/) { inprev = 1; depth = 0 }
      if (inprev) {
        d = $0; o = gsub(/{/, "", d); c = gsub(/}/, "", d); depth += o - c
        if (depth <= 0 && (o > 0 || c > 0)) inprev = 0
        next
      }
      if ($0 ~ /(\.frame\(|\.padding\(|spacing:|minLength:)[^)]*[0-9]/) {
        if ($0 ~ /GlobalLattice\.(pt|gif)/) next
        if ($0 ~ /[(:,][ \t]*0(\.0)?[ \t]*[),]/) next
        printf "%s:%d:%s\n", FILENAME, NR, $0
      }
    }' "$1"
}
pitch_hits=""
for f in "${COMP[@]}"; do
  h=$(pitch_scan "$f")
  [ -n "$h" ] && pitch_hits="${pitch_hits}${h}
"
done
if [ -n "$(printf '%s' "$pitch_hits" | tr -d '[:space:]')" ]; then
  note "bare point literal bypassing GlobalLattice.pt()/.gif() (shipped, non-preview):"
  printf '%s' "$pitch_hits" | sed 's/^/      /'
else ok "every shipped dimension goes through GlobalLattice.pt()/.gif() (single pitch)"; fi

# ── LINT-DETENT ────────────────────────────────────────────────────────────
# The frame-locked cell detent (Spec.CellMechanics.lawTicksFrameMonotone): the
# cellTick haptic `Haptics.play(1)` may be fired ONLY by the one coalescing flush
# in CellDetent.swift (≤1 Taptic per 20 fps frame). A direct `play(1)` anywhere
# else is an un-frame-locked detent that can outrun the tick on a fast drag —
# route it through `.cellDetent(tick:every:position:)`, or, if it is a DISCRETE
# event (not a per-cell detent), use `Haptics.selection()`/`.impact()`.
# See docs/SIXFOUR-CELL-WIDGET-LANGUAGE.md §4.
echo "GRID lint — frame-locked detent (cellTick via .cellDetent only)"
detent_hits=$(grep -rn 'Haptics\.play(1)' "$UI_DIR" --include='*.swift' 2>/dev/null \
  | grep -v 'CellDetent.swift' \
  | grep -vE ':[0-9]+:[[:space:]]*//')      # ignore comment lines that merely mention it
if [ -n "$detent_hits" ]; then
  note "cellTick play(1) fired outside CellDetent.swift (un-frame-locked detent):"
  printf '%s\n' "$detent_hits" | sed 's/^/      /'
else ok "cellTick play(1) is fired only by the frame-locked .cellDetent flush"; fi

# ── LINT-GOLDEN ────────────────────────────────────────────────────────────
echo "GRID lint — golden sources of truth"
for f in spec/src/SixFour/Spec/Lattice.hs \
         spec/src/SixFour/Spec/CellShapes.hs \
         spec/src/SixFour/Spec/GridLayout.hs \
         SixFour/Generated/LatticeContract.swift \
         SixFour/Generated/CellShapesContract.swift \
         SixFour/Generated/GridLayoutContract.swift \
         spec/src/SixFour/Spec/CellMechanics.hs \
         spec/src/SixFour/Spec/ColorTimeDisplay.hs \
         SixFour/Generated/CellMechanicsContract.swift; do
  if [ -f "$f" ]; then ok "present: $f"; else note "MISSING golden: $f"; fi
done
for m in SixFour.Spec.Lattice SixFour.Spec.CellShapes SixFour.Spec.GridLayout \
         SixFour.Spec.CellMechanics SixFour.Spec.ColorTimeDisplay; do
  if grep -q "$m" spec/spec.cabal; then ok "exposed: $m"; else note "NOT in spec.cabal: $m"; fi
done

# ── LINT-CONTROL-FACE ──────────────────────────────────────────────────────
# The control language (Spec.CellMechanics ControlFace, THE DESIGN D1): every
# INTERACTIVE region in the generated GridLayoutContract must declare a control
# face in the generated CellMechanicsContract `controlFaces` table — "interactive
# region ⇒ control face", the lint mirror of lawControlFaceTotal (which proves the
# same totality over the Haskell scenes at `cabal test` time). An interactive
# region with no face is an unmarked control — the exact device-review drift.
echo "GRID lint — LINT-CONTROL-FACE (interactive region ⇒ declared control face)"
GLC="SixFour/Generated/GridLayoutContract.swift"
CMC="SixFour/Generated/CellMechanicsContract.swift"
if [ -f "$GLC" ] && [ -f "$CMC" ]; then
  face_fail=0
  while IFS= read -r nm; do
    [ -z "$nm" ] && continue
    if ! grep -q "\"$nm\": \"" "$CMC"; then
      note "interactive region '$nm' has no control face (add it to Spec.CellMechanics controlFaces)"
      face_fail=1
    fi
  done < <(grep 'interactive: true' "$GLC" | sed -E 's/.*name: "([^"]+)".*/\1/' | sort -u)
  [ "$face_fail" -eq 0 ] && ok "every interactive region declares a control face (lawControlFaceTotal mirror)"
else
  note "MISSING contracts for the control-face check: $GLC / $CMC"
fi

# ── LINT-LAUNCH-PLIST ──────────────────────────────────────────────────────
# The pre-main null-deref keys. An EMPTY `UILaunchStoryboardName: ""` makes UIKit call
# -[UIStoryboard storyboardWithName:@"" bundle:] during launch and null-derefs deep in UIKit
# (EXC_BAD_ACCESS at a system PC) BEFORE any app code runs — a persistent WHITE screen with no
# "SF-" trace. The modern launch is an EMPTY `UILaunchScreen: {}` dict (no storyboard file). Ban
# both keys from project.yml so the crash config can never be reintroduced. Comment lines that
# merely MENTION the keys (the warning next to UILaunchScreen) are excluded.
echo "GRID lint — launch-plist (no pre-main UILaunchStoryboardName/UIColorName)"
launch_bad=$(grep -nE 'UILaunchStoryboardName|UIColorName' project.yml 2>/dev/null \
  | grep -vE '^[0-9]+:[[:space:]]*#')
if [ -n "$launch_bad" ]; then
  note "launch-plist regression (UILaunchStoryboardName/UIColorName reintroduced in project.yml):"
  printf '%s\n' "$launch_bad" | sed 's/^/      /'
else ok "launch-plist clean (modern UILaunchScreen:{}, no storyboard/colorname keys)"; fi

echo
if [ "$fail" -eq 0 ]; then
  echo "GRID lint: PASS — UI conformant (grid-following placement, one pitch)."
  exit 0
else
  echo "GRID lint: FAIL — drift above violates docs/SIXFOUR-DESIGN-LANGUAGE.md."
  exit 1
fi

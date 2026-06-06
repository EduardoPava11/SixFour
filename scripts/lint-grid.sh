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
HUD="SixFour/UI/Screens/Capture/CaptureView.swift"
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

# ── LINT-SINGLE-PITCH (capture HUD hard; other screens WARN) ───────────────
echo "GRID lint — LINT-SINGLE-PITCH"
PITCH='(spacing|padding|frame|minLength)[[:space:]]*[(:][^)]*[0-9]'
ZERO='[(:,][[:space:]]*0(\.0)?[[:space:]]*[),]'
hud_hits=$(grep -nE "$PITCH" "$HUD" | grep -vE 'GlobalLattice\.(pt|gif)' | grep -vE "$ZERO")
if [ -n "$hud_hits" ]; then
  note "HUD: bare point literal bypassing GlobalLattice.pt()/.gif():"
  printf '%s\n' "$hud_hits" | sed 's/^/      /'
else ok "HUD: no bare-point bypass (single owner)"; fi
# Other composition screens: report legacy bare-literal debt (non-failing, tracked).
legacy=0
for f in "${COMP[@]}"; do
  [ "$f" = "$HUD" ] && continue
  n=$(grep -nE "$PITCH" "$f" | grep -vE 'GlobalLattice\.(pt|gif)' | grep -vE "$ZERO" | wc -l | tr -d ' ')
  if [ "$n" -gt 0 ]; then warn "legacy bare-pitch literals (tracked, not yet failed): $n in $f"; legacy=$((legacy+n)); fi
done
[ "$legacy" -eq 0 ] && ok "no legacy bare-pitch literals anywhere" || warn "TOTAL legacy bare-pitch debt: $legacy (migrate to GlobalLattice.pt()/.gif())"

# ── LINT-GOLDEN ────────────────────────────────────────────────────────────
echo "GRID lint — golden sources of truth"
for f in spec/src/SixFour/Spec/Lattice.hs \
         spec/src/SixFour/Spec/CellShapes.hs \
         spec/src/SixFour/Spec/GridLayout.hs \
         SixFour/Generated/LatticeContract.swift \
         SixFour/Generated/CellShapesContract.swift \
         SixFour/Generated/GridLayoutContract.swift; do
  if [ -f "$f" ]; then ok "present: $f"; else note "MISSING golden: $f"; fi
done
for m in SixFour.Spec.Lattice SixFour.Spec.CellShapes SixFour.Spec.GridLayout; do
  if grep -q "$m" spec/spec.cabal; then ok "exposed: $m"; else note "NOT in spec.cabal: $m"; fi
done

echo
if [ "$fail" -eq 0 ]; then
  echo "GRID lint: PASS — UI conformant (grid-following placement, one pitch)."
  exit 0
else
  echo "GRID lint: FAIL — drift above violates docs/SIXFOUR-DESIGN-LANGUAGE.md."
  exit 1
fi

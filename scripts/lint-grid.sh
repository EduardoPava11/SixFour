#!/usr/bin/env bash
#
# lint-grid.sh — the GRID design-language build gate.
#
# Enforces the capture-HUD invariants from docs/SIXFOUR-DESIGN-LANGUAGE.md so the
# Phase 1–3a gains cannot silently regress. Three checks, each from the §6 re-map
# procedure in docs/SIXFOUR-DESIGN-MAP.md:
#
#   LINT-DRAW-VOCAB   (Law #2 / §6.10) — no glass, no opacity-on-a-cell, no raw
#                     SwiftUI vector primitives on the capture HUD.
#   LINT-SINGLE-PITCH (Laws #5/#6)      — no bare point literal in spacing/padding/
#                     frame; every dimension goes through GlobalLattice.pt().
#   LINT-GOLDEN       (Law #8)          — the Spec.* sources of truth + their
#                     generated contracts exist.
#
# SCOPE: the composition layer (the screen that ASSEMBLES widgets), not the
# primitive internals (CellText/CellSprite legitimately use Text/UIKit to
# rasterize). Police usage, not the framework's guts.
#
# Exit 0 = clean; exit 1 = drift (fails the build). Run from the repo root.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 2

HUD="SixFour/UI/Screens/Capture/CaptureView.swift"
fail=0

note() { printf '  ✘ %s\n' "$1"; fail=1; }
ok()   { printf '  ✓ %s\n' "$1"; }

echo "GRID lint — $HUD"

# ── LINT-DRAW-VOCAB ────────────────────────────────────────────────────────
# Opacity on a cell is shading (forbidden), EXCEPT .opacity(0) — alpha 0 is
# structural invisibility (the CameraPreview tap-to-focus passthrough), not shade.
if grep -nE '\.opacity\(' "$HUD" | grep -vE '\.opacity\(0\)|\.opacity\(0\.0\)' | grep -q .; then
  note "opacity-on-a-cell (only .opacity(0) passthrough is allowed):"
  grep -nE '\.opacity\(' "$HUD" | grep -vE '\.opacity\(0\)|\.opacity\(0\.0\)' | sed 's/^/      /'
else ok "no shading opacity"; fi

# Retired opacity tokens must not appear on the HUD.
if grep -nE '\b(dimText|hairline)\b' "$HUD" | grep -q .; then
  note "retired opacity token (dimText/hairline) on the HUD:"
  grep -nE '\b(dimText|hairline)\b' "$HUD" | sed 's/^/      /'
else ok "no retired opacity tokens"; fi

# Glass material is retired on the capture HUD.
if grep -nE 'Glass(InfoChip|IconButton|ToolbarCluster|EffectContainer)|glassEffect|cardCorner' "$HUD" | grep -q .; then
  note "glass material on the HUD (retired; Review/Settings only):"
  grep -nE 'Glass(InfoChip|IconButton|ToolbarCluster|EffectContainer)|glassEffect|cardCorner' "$HUD" | sed 's/^/      /'
else ok "no glass on the HUD"; fi

# Raw SwiftUI vector primitives are off-vocabulary (use the Cell* primitives).
if grep -nE '\bRoundedRectangle\b|\bCircle\(\)|\.stroke\(|\bText\(' "$HUD" | grep -q .; then
  note "raw SwiftUI primitive on the HUD (use CellText/CellShapes):"
  grep -nE '\bRoundedRectangle\b|\bCircle\(\)|\.stroke\(|\bText\(' "$HUD" | sed 's/^/      /'
else ok "no raw vector primitives"; fi

# ── LINT-SINGLE-PITCH ──────────────────────────────────────────────────────
# Every NON-ZERO spacing/padding/frame/minLength point value goes through
# GlobalLattice.pt(). `[(:]` matches both call style `.padding(16)` and label style
# `VStack(spacing: 16)`. A literal 0 is the "no gutter" identity (like .opacity(0)) —
# exempt, alongside anything already routed through GlobalLattice.pt().
PITCH='(spacing|padding|frame|minLength)[[:space:]]*[(:][^)]*[0-9]'
ZERO='[(:,][[:space:]]*0[[:space:]]*[),]'
pitch_hits=$(grep -nE "$PITCH" "$HUD" | grep -v 'GlobalLattice.pt' | grep -vE "$ZERO")
if [ -n "$pitch_hits" ]; then
  note "bare point literal bypassing GlobalLattice.pt():"
  printf '%s\n' "$pitch_hits" | sed 's/^/      /'
else ok "no bare-point bypass (single owner)"; fi

# ── LINT-GOLDEN ────────────────────────────────────────────────────────────
echo "GRID lint — golden sources of truth"
for f in spec/src/SixFour/Spec/Lattice.hs \
         spec/src/SixFour/Spec/CellShapes.hs \
         SixFour/Generated/LatticeContract.swift \
         SixFour/Generated/CellShapesContract.swift; do
  if [ -f "$f" ]; then ok "present: $f"; else note "MISSING golden: $f"; fi
done
for m in SixFour.Spec.Lattice SixFour.Spec.CellShapes; do
  if grep -q "$m" spec/spec.cabal; then ok "exposed: $m"; else note "NOT in spec.cabal: $m"; fi
done

echo
if [ "$fail" -eq 0 ]; then
  echo "GRID lint: PASS — capture HUD conformant."
  exit 0
else
  echo "GRID lint: FAIL — drift above violates docs/SIXFOUR-DESIGN-LANGUAGE.md."
  exit 1
fi

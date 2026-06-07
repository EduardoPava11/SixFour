#!/usr/bin/env bash
# scripts/verify-doc-claims.sh
# Gates the load-bearing facts in docs/STATUS.md. Run before trusting a status claim.
# Asserts CURRENT truth (must pass today). Dependency-free: grep/test/find only.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

FAILS=0
check() {
  # check "<fact>" <command...>
  local fact="$1"; shift
  if "$@" >/dev/null 2>&1; then
    echo "PASS: $fact"
  else
    echo "FAIL: $fact"
    FAILS=$((FAILS + 1))
  fi
}

# --- META-GUARD: every source file a grep-based check reads MUST exist ---
# A grep against a MISSING file silently FAILs (false-fail) or, under `! grep`, silently
# PASSes (false-green) — so a deleted/renamed path can masquerade as a doc-claim result
# (this is exactly how the GIFReviewView.swift checks rotted). This pre-flight makes a
# missing grep target a distinct, loud GATE BUG, not a fake pass/fail. (Design doc D2.)
# Existence/absence checks (`test ! -e`, `test -z "$(find …)"`, `stat`) are NOT listed
# here — for those a missing path is the point, not a bug.
GREP_TARGETS=(
  SixFour/UI/Screens/Capture/CaptureViewModel.swift
  SixFour/Encoder/DeterministicRenderer.swift
  SixFour/Native/SixFourNative.swift
  SixFour/Settings/AppSettings.swift
  SixFour/UI/Surface/ReviewPhaseField.swift
  Native/src/kernels.zig
  Native/src/fixture_test.zig
  Native/include/sixfour_native.h
  trainer/generated/look_net_mlx.py
  trainer/train_look_net_mlx.py
  spec/src/SixFour/Spec/Quad4.hs
  spec/src/SixFour/Spec/PairTree.hs
  SixFour/UI/MovableColorWidget.swift
  SixFour/Generated/MoveContract.swift
)
for f in "${GREP_TARGETS[@]}"; do
  if [ ! -e "$f" ]; then
    echo "GATE BUG: grep target missing: $f (a check below reads it; fix the path, do not delete the check)"
    FAILS=$((FAILS + 1))
  fi
done

# --- ANCHOR 1: GIFA->GIFB global collapse keystone is WIRED (>=1 production caller) ---
check "renderDeterministicGlobal exists (CaptureViewModel routes to global path)" \
  grep -q 'renderDeterministicGlobal' SixFour/UI/Screens/Capture/CaptureViewModel.swift
check "DeterministicRenderer.renderGlobalPalette exists" \
  grep -q 'func renderGlobalPalette' SixFour/Encoder/DeterministicRenderer.swift
check "renderGlobalPalette calls SixFourNative.globalCollapse (Zig s4_global_collapse)" \
  grep -q 'SixFourNative.globalCollapse' SixFour/Encoder/DeterministicRenderer.swift
check "global path is gated on settings.paletteScope == .global" \
  grep -q 'paletteScope == .global' SixFour/UI/Screens/Capture/CaptureViewModel.swift
check "globalCollapse wraps the Zig s4_global_collapse symbol" \
  grep -q 's4_global_collapse' SixFour/Native/SixFourNative.swift

# --- ANCHOR 2: loadLookNet has ZERO production callers (NN spine unwired) ---
check "loadLookNet has zero production callers (only its own definition references it)" \
  test "$(grep -rn 'loadLookNet' SixFour/ --include='*.swift' | grep -v 'func loadLookNet' | grep -v '///' | wc -l | tr -d ' ')" -eq 0
check "no on-device NN forward-pass symbol exists" \
  test -z "$(grep -rn 'look_net_forward\|lookNetForward\|forward_l' SixFour/ Native/ --include='*.swift' --include='*.zig' --include='*.h' 2>/dev/null)"

# --- ANCHOR 3: training-data dirs empty/absent (synthetic-only) ---
check "trainer/data/captured_frames has no committed files" \
  test -z "$(ls -A trainer/data/captured_frames 2>/dev/null)"
check "trainer/data/reference_gifs has no committed files" \
  test -z "$(ls -A trainer/data/reference_gifs 2>/dev/null)"

# --- ANCHOR 4: decoder output dim is 384, not 768 ---
check "DECODER_OUT_DIM == 384 in generated MLX module" \
  grep -qE 'DECODER_OUT_DIM[[:space:]]*=[[:space:]]*384' trainer/generated/look_net_mlx.py

# --- ANCHOR 4b: NN not shipped (trainer is grayscale-L-only; no weight blob bundled) ---
check "trainer is grayscale-L-only nucleus" \
  grep -q 'grayscale' trainer/train_look_net_mlx.py
check "no look-net weight .blob is bundled in the app target" \
  test -z "$(find SixFour -iname '*.blob' 2>/dev/null)"
check "trained deploy blob exists (133923 bytes) and Zig loader is fixture-tested" \
  test "$(stat -f%z trainer/out/look_net_trained.s4ln 2>/dev/null || echo 0)" = "133923"
check "Zig blob loader verified by fixture test" \
  grep -q 's4_load_look_net' Native/src/fixture_test.zig

# --- BUILT: deterministic core implementations are real, not stubs ---
check "s4_gif_encode_burst is a real impl (folds and returns s4_gif_assemble)" \
  grep -q 'return s4_gif_assemble' Native/src/kernels.zig
check "Native header exports 18 distinct s4_* symbols" \
  test "$(grep -hoE 's4_[a-z_0-9]+' Native/include/sixfour_native.h | sort -u | wc -l | tr -d ' ')" -eq 18

# --- BUILT: zero deps, deterministic default ---
check "useDeterministicCore defaults to true" \
  grep -qE 'useDeterministicCore\) as\? Bool \?\? true' SixFour/Settings/AppSettings.swift
check "no live SwiftUI .glassEffect calls (HUD de-glassed)" \
  test "$(grep -rn '\.glassEffect' SixFour/ --include='*.swift' | grep -v '///' | wc -l | tr -d ' ')" -eq 0

# --- BUILT: explorer surfaces shipped; stale components gone ---
# NOTE: the former GIFReviewView.swift review screen was replaced by the one-surface
# ReviewPhaseField (Surface/). The stale "PaletteGridView wired into review" claim is
# reconciled separately (design doc D3); here we assert the LIVE review surface exists.
check "live review surface (ReviewPhaseField) is present" \
  test -f SixFour/UI/Surface/ReviewPhaseField.swift
check "GridLayout shipped" \
  test -f SixFour/Palette/GridLayout.swift
check "PaletteCloudView shipped" \
  test -f SixFour/UI/Components/PaletteCloudView.swift
check "StatsFooterView deleted (not a live component)" \
  test ! -e SixFour/UI/Components/StatsFooterView.swift
check "GlobalPaletteCollapse.swift removed (collapse is the Zig kernel)" \
  test ! -e SixFour/Palette/GlobalPaletteCollapse.swift
check "PaletteStripView absent from current source" \
  test -z "$(find SixFour -name 'PaletteStripView*' 2>/dev/null)"
check "PaletteSphereView absent from current source" \
  test -z "$(grep -rln 'PaletteSphereView' SixFour/ --include='*.swift')"
check "review renderer docstring has no stale 'globe' reference" \
  bash -c "! grep -qi 'globe' SixFour/UI/Surface/ReviewPhaseField.swift"

# --- DESIGN-ONLY: REVEAL modules not on disk ---
check "ColorBleed.hs not yet on disk (reveal axis dormant)" \
  test ! -e spec/src/SixFour/Spec/ColorBleed.hs
check "ChromaAllocation.hs not yet on disk" \
  test ! -e spec/src/SixFour/Spec/ChromaAllocation.hs
check "Obfuscation keystone landed" \
  test -e spec/src/SixFour/Spec/Obfuscation.hs

# --- DESIGN-ONLY: spec'd but unconsumed ---
check "PaletteSearch spec exists (no iOS consumer)" \
  test -f spec/src/SixFour/Spec/PaletteSearch.hs
check "quad4Analyze exists in spec (skeleton-design 'TO ADD' is stale)" \
  grep -q 'quad4Analyze' spec/src/SixFour/Spec/Quad4.hs
check "AppSettings has the three versioned representation/grid-axis keys" \
  bash -c "grep -q 'sixfour.paletteRepresentation.v1' SixFour/Settings/AppSettings.swift && grep -q 'sixfour.gridAxisX.v1' SixFour/Settings/AppSettings.swift && grep -q 'sixfour.gridAxisY.v1' SixFour/Settings/AppSettings.swift"

# --- BUILT: movable ColorWidgets (Field64/Palette16/DiversityRing share ONE layout) ---
check "Spec.MovableLayout is the source of truth (move operator + laws)" \
  test -f spec/src/SixFour/Spec/MovableLayout.hs
check "Properties.MovableLayout registered in the spec test suite" \
  grep -q 'MovableLayout.tests' spec/test/Spec.hs
check "the move operator mirror reuses GridLayoutContract.isDisjoint (no reinvented AABB)" \
  grep -q 'GridLayoutContract.isDisjoint' SixFour/Generated/MoveContract.swift
check "MovableColorWidget calls the generated MoveContract.move" \
  grep -q 'MoveContract.move' SixFour/UI/MovableColorWidget.swift
check "the .movable gesture modifier exists (long-press lift → drag → snap)" \
  grep -q 'func movable' SixFour/UI/MovableColorWidget.swift
check "AppSettings has the three versioned ColorWidget position keys" \
  bash -c "grep -q 'sixfour.field64Position.v1' SixFour/Settings/AppSettings.swift && grep -q 'sixfour.palette16Position.v1' SixFour/Settings/AppSettings.swift && grep -q 'sixfour.diversityRingPosition.v1' SixFour/Settings/AppSettings.swift"

# --- INVARIANTS that must NOT regress ---
check "PairTree uses Euclidean okLabDistanceSquared ([4,2,1] weighting gone)" \
  grep -q 'okLabDistanceSquared' spec/src/SixFour/Spec/PairTree.hs

echo "----------------------------------------"
if [ "$FAILS" -ne 0 ]; then
  echo "$FAILS load-bearing fact(s) FAILED — docs/STATUS.md may be stale."
  exit 1
fi
echo "All load-bearing facts verified."

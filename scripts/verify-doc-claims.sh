#!/usr/bin/env bash
# scripts/verify-doc-claims.sh
# Gates the load-bearing facts of the project canon (CLAUDE.md + SixFour.Spec.Map).
# Asserts CURRENT truth (must pass today). Dependency-free: grep/test/find only.
#
# Historical note: this script formerly gated docs/STATUS.md, which was deleted (the canon
# is now CLAUDE.md + the Haskell spec + module doc-comments; do not recreate docs/STATUS.md).
# It was also stale against the look-net retirement and the H-JEPA rebuild; this is the lean
# rewrite that checks only facts that are true today.
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
# PASSes (false-green) — so a deleted/renamed path can masquerade as a doc-claim result.
# This pre-flight makes a missing grep target a distinct, loud GATE BUG, not a fake pass/fail.
# (Existence/absence checks via `test`/`find` are NOT listed — for those a missing path is the point.)
GREP_TARGETS=(
  SixFour/Settings/Feature.swift
  SixFour/UI/Machine/CaptureViewModel.swift
  SixFour/Settings/AppSettings.swift
  SixFour/Kernels/KernelsGif.swift
  SixFour/Kernels/sixfour_kernels_abi.h
  spec/src/SixFour/Spec/PairTree.hs
  spec/test/Spec.hs
  SixFour/UI/Widgets/MovableColorWidget.swift
)
for f in "${GREP_TARGETS[@]}"; do
  if [ ! -e "$f" ]; then
    echo "GATE BUG: grep target missing: $f (a check below reads it; fix the path, do not delete the check)"
    FAILS=$((FAILS + 1))
  fi
done

# --- PALETTE: MVP1 is per-frame; the global (GIFB) path is kept + compiled but V2-deferred ---
check "MVP1 ships global OFF (Feature.globalPaletteV2 = false)" \
  grep -q 'static let globalPaletteV2 = false' SixFour/Settings/Feature.swift
check "the live capture router is gated by Feature.globalPaletteV2 (per-frame only in MVP1)" \
  grep -q 'Feature.globalPaletteV2 ? settings.paletteScope : .perFrame' SixFour/UI/Machine/CaptureViewModel.swift

# --- THE LEARNED OBJECT: theta_B ships HAND-WRITTEN, golden-gated, no Core AI ---
# CLAUDE.md: the only learned object is the 63-param theta_B; its on-device forward pass is a
# hand-written Swift port verified bit-exact against the spec golden.
check "theta_B forward ships hand-written (MaskedBandForward.swift)" \
  test -f SixFour/Native/MaskedBandForward.swift
check "theta_B forward is golden-gated (MaskedBandGolden.swift)" \
  test -f SixFour/Generated/MaskedBandGolden.swift
check "no on-device NN forward-pass symbol leaked (theta_B is the only learned object)" \
  test -z "$(grep -rn 'look_net_forward\|lookNetForward\|forward_l' SixFour/ --include='*.swift' --include='*.h' 2>/dev/null)"
check "the retired look-net loader has zero production callers" \
  test "$(grep -rn 'loadLookNet' SixFour/ --include='*.swift' | grep -v 'func loadLookNet' | grep -v '///' | wc -l | tr -d ' ')" -eq 0
check "no learned-weight .blob is bundled in the app target (synthetic-only, hand-written forward)" \
  test -z "$(find SixFour -iname '*.blob' 2>/dev/null)"

# --- H-JEPA TRAINER: the spec is the authority for the trainer (spec-emitted goldens) ---
check "the H-JEPA trainer gate exists (trainer/mlx/gate_trainer.py)" \
  test -f trainer/mlx/gate_trainer.py
check "the spec emits the I-JEPA head golden (jepa_head_golden.json)" \
  test -f trainer/generated/jepa_head_golden.json
check "the spec emits the temporal (t,t+1) data golden (temporal_data_golden.json)" \
  test -f trainer/generated/temporal_data_golden.json
check "training-data dir captured_frames is empty/absent (synthetic corpus only)" \
  test -z "$(ls -A trainer/data/captured_frames 2>/dev/null)"
check "training-data dir reference_gifs is empty/absent (synthetic corpus only)" \
  test -z "$(ls -A trainer/data/reference_gifs 2>/dev/null)"

# --- NATIVE CORE: real impls, header/export parity, deterministic default ---
check "s4_gif_encode_burst is a real impl (folds and returns s4_gif_assemble)" \
  grep -q 'return s4_gif_assemble' SixFour/Kernels/KernelsGif.swift
check "header s4_* symbol set == Swift @_cdecl export set (no undeclared exports)" \
  bash -c 'diff <(grep -hoE "s4_[a-z_0-9]+" SixFour/Kernels/sixfour_kernels_abi.h | sort -u) <(grep -hoE "@_cdecl\(\"s4_[a-z_0-9]+\"\)" SixFour/Kernels/*.swift | grep -hoE "s4_[a-z_0-9]+" | sort -u) >/dev/null'
check "useDeterministicCore defaults to true" \
  grep -qE 'useDeterministicCore\) as\? Bool \?\? true' SixFour/Settings/AppSettings.swift

# --- INVARIANTS that must NOT regress ---
check "PairTree uses Euclidean okLabDistanceSquared ([4,2,1] learned-metric weighting gone)" \
  grep -q 'okLabDistanceSquared' spec/src/SixFour/Spec/PairTree.hs
check "Spec.MovableLayout is the source of truth (move operator + laws)" \
  test -f spec/src/SixFour/Spec/MovableLayout.hs
check "Properties.MovableLayout registered in the spec test suite" \
  grep -q 'MovableLayout.tests' spec/test/Spec.hs
check "MovableColorWidget calls the generated MoveContract.move" \
  grep -q 'MoveContract.move' SixFour/UI/Widgets/MovableColorWidget.swift

echo "----------------------------------------"
if [ "$FAILS" -ne 0 ]; then
  echo "$FAILS load-bearing fact(s) FAILED — a canon claim (CLAUDE.md / Spec.Map) may be stale."
  exit 1
fi
echo "All load-bearing facts verified."

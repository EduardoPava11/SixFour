#!/usr/bin/env bash
#
# lint-no-global-palette.sh — Phase 0 of the per-frame / orthogonal-A/B migration
# (docs/SIXFOUR-PER-FRAME-GENOME-AB-MIGRATION-WORKFLOW.md §6).
#
# The single-global-palette collapse is DEFERRED TO V2 (behind Feature.globalPaletteV2 = false),
# not deleted. MVP1 is per-frame only; the global code stays compiled + golden-gated for V2.
# This lint FREEZES the blast radius: it fails if any tagged global-palette symbol appears in a
# file that was NOT already a call site on 2026-06-18 — so the deferred path can't spread in MVP1.
# It STAYS a freeze (not a forbid) precisely because the code is kept for V2.
#
# To intentionally retire a frozen file (e.g. when Phase 5 flips the live path), remove it
# from the matching allowlist below in the same commit.
#
# Exit 0 = frozen (no new callers). Exit 1 = a NEW caller appeared.

set -euo pipefail
cd "$(dirname "$0")/.."

ROOTS=(SixFour spec)
INCLUDES=(--include='*.swift' --include='*.hs')
fail=0

# check_frozen <symbol/pattern> <allowlisted-file>...
check_frozen() {
  local pattern="$1"; shift
  local -a allow=("$@")
  local f a ok
  # files currently referencing the pattern (portable to bash 3.2 — no mapfile)
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    ok=0
    for a in "${allow[@]}"; do [ "$f" = "$a" ] && ok=1 && break; done
    if [ "$ok" -eq 0 ]; then
      echo "FAIL: new caller of DEPRECATED-GLOBAL-PALETTE symbol '$pattern':"
      echo "        $f"
      echo "      Use the per-frame + orthogonal-A/B path instead"
      echo "      (docs/SIXFOUR-PER-FRAME-GENOME-AB-MIGRATION-WORKFLOW.md §4)."
      fail=1
    fi
  done < <(grep -rl "$pattern" "${ROOTS[@]}" "${INCLUDES[@]}" 2>/dev/null | sort -u)
}

# --- frozen allowlists (call sites as of 2026-06-18) ----------------------------------------

# substring 'globalCollapse' also covers globalCollapseQ16 / GlobalCollapseResult (same file set)
check_frozen 'globalCollapse' \
  SixFour/Generated/CollapseGolden.swift \
  SixFour/Native/SixFourNative.swift \
  SixFour/Encoder/DeterministicRenderer.swift \
  SixFour/Palette/PaletteCollapse.swift \
  SixFour/Kernels/KernelsQuantize.swift \
  spec/app/Fixtures.hs \
  spec/test/Properties/GroupRGBT.hs \
  spec/test/Properties/Collapse.hs \
  spec/test/Properties/GlobalCollapseQ16.hs \
  spec/src/SixFour/Spec/Barycenter.hs \
  spec/src/SixFour/Spec/GroupRGBT.hs \
  spec/src/SixFour/Spec/Bures.hs \
  spec/src/SixFour/Spec/Collapse.hs \
  spec/src/SixFour/Spec/GlobalCollapseQ16.hs \
  spec/src/SixFour/Spec/Map.hs \
  spec/src/SixFour/Codegen/Collapse.hs

check_frozen 's4_global_collapse' \
  SixFour/UI/Machine/CaptureViewModel.swift \
  SixFour/Native/SixFourNative.swift \
  SixFour/Encoder/DeterministicRenderer.swift \
  SixFour/Kernels/KernelsQuantize.swift \
  spec/app/Fixtures.hs \
  spec/src/SixFour/Spec/GlobalCollapseQ16.hs \
  spec/src/SixFour/Spec/Map.hs

check_frozen 'renderGlobalPalette' \
  SixFour/UI/Machine/CaptureViewModel.swift \
  SixFour/Encoder/DeterministicRenderer.swift \
  SixFour/Atlas/AtlasCollapse.swift \
  SixFour/Atlas/AtlasBoard.swift

check_frozen 'renderDeterministicGlobal' \
  SixFour/UI/Machine/CaptureViewModel.swift \
  SixFour/Atlas/AtlasCollapse.swift

if [ "$fail" -eq 0 ]; then
  echo "lint-no-global-palette: OK — global-palette blast radius frozen (no new callers)."
fi
exit "$fail"

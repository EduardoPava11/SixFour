#!/usr/bin/env bash
# find-stubs.sh — scan the SIMT + MPS (+ pivot) surfaces for unfinished work.
#
# PURPOSE: a reusable, honest inventory of stubs / spikes / TODOs so the NN-stack
# pivot (docs/NN-STACK.generated.md) never silently overclaims readiness. Run it
# before trusting any "done"; it is the gate for the "What is real vs stub"
# section of the canonical map.
#
# Usage:
#   scripts/find-stubs.sh            # scan the default pivot surfaces
#   scripts/find-stubs.sh PATH ...   # scan specific paths instead
#
# Exit code: number of files containing matches (0 = clean), capped at 255.
set -euo pipefail
cd "$(dirname "$0")/.."

# Default scope: SIMT (Zig core + Metal kernels), MPS (on-device trainer), and
# the pivot seams. Override by passing paths as arguments.
if [ "$#" -gt 0 ]; then
  SCOPE=("$@")
else
  SCOPE=(
    Native/src                      # SIMT: Zig integer core
    SixFour/Metal                   # SIMT: Metal kernels
    SixFour/CoreAI                  # pivot: L inference seam (orphaned audit record)
    SixFour/GeneLibrary             # gene-RAG (flat JSON -> SIMT vector RAG)
    SixFour/RGBT4D                  # cube-ladder Swift orchestration
    trainer/coreai_export           # pivot: L deploy bridge (orphaned)
    trainer/mlx                     # the H-JEPA trainer
  )
  # Dropped 2026-06-25: SixFour/Atlas (retired A/B trainer) and
  # spec/src/SixFour/Spec/ExportFamily.hs (abandoned scaffolding) — both deleted.
fi

# Markers that signal unfinished / provisional work, by language idiom.
PATTERN='TODO|FIXME|XXX|HACK|NOT_IMPLEMENTED|S4_RC_NOT_IMPLEMENTED'
PATTERN+='|NotImplementedError|raise NotImplementedError|fatalError'
PATTERN+='|error "TODO"|error "todo"|unimplemented'
PATTERN+='|\bSPIKE\b|\bscaffold\b|\bplaceholder\b|\bstub\b|\bhollow\b'

echo "== SixFour stub / unfinished-work scan =="
echo "scope: ${SCOPE[*]}"
echo

# Prefer ripgrep; fall back to grep -r. Case-insensitive, with line numbers.
existing=()
for p in "${SCOPE[@]}"; do [ -e "$p" ] && existing+=("$p"); done
if [ "${#existing[@]}" -eq 0 ]; then echo "(no scope paths exist)"; exit 0; fi

if command -v rg >/dev/null 2>&1; then
  rg -n -i --no-heading -g '!*.bin' -g '!*.png' -g '!*.svg' -e "$PATTERN" "${existing[@]}" || true
  files=$(rg -l -i -g '!*.bin' -g '!*.png' -g '!*.svg' -e "$PATTERN" "${existing[@]}" 2>/dev/null | wc -l | tr -d ' ')
else
  grep -rniE --binary-files=without-match "$PATTERN" "${existing[@]}" || true
  files=$(grep -rliE --binary-files=without-match "$PATTERN" "${existing[@]}" 2>/dev/null | wc -l | tr -d ' ')
fi

echo
echo "== $files file(s) with unfinished-work markers =="
[ "$files" -gt 255 ] && files=255
exit "$files"

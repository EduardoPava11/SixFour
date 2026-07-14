#!/usr/bin/env bash
# find-stubs.sh — scan the live app/trainer/spec surfaces for unfinished work.
#
# PURPOSE: a reusable, honest inventory of stubs / spikes / TODOs so no arc
# silently overclaims readiness. Run it before trusting any "done"; it feeds the
# "What is real vs stub" question every handoff has to answer.
#
# Usage:
#   scripts/find-stubs.sh            # scan the default pivot surfaces
#   scripts/find-stubs.sh PATH ...   # scan specific paths instead
#
# Exit code: number of files containing matches (0 = clean), capped at 255.
set -euo pipefail
cd "$(dirname "$0")/.."

# Default scope: every live shipped surface plus the trainer and the spec.
# Override by passing paths as arguments.
# (Scope refresh 2026-07-13: dropped SixFour/CoreAI + trainer/coreai_export,
# both deleted 2026-06-26; added the live app surfaces that had grown since.)
if [ "$#" -gt 0 ]; then
  SCOPE=("$@")
else
  SCOPE=(
    SixFour/Kernels                 # the owned byte-exact Swift kernel core
    SixFour/Metal                   # SIMT: Metal kernels
    SixFour/Capture                 # burst capture + ColorHead circuit
    SixFour/Encoder                 # deterministic GIF pipeline drivers
    SixFour/Core                    # promoted spec twins (TemporalLoop, ...)
    SixFour/Train                   # per-capture on-device trainers
    SixFour/UI                      # the one-surface cell-grid UI
    SixFour/Native                  # Swift/ObjC glue (bridging header home)
    SixFour/GeneLibrary             # gene-RAG (flat JSON -> SIMT vector RAG)
    SixFour/RGBT4D                  # cube-ladder Swift orchestration
    trainer/mlx                     # the H-JEPA trainer
    spec/src                        # the Haskell spec itself
  )
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

# KernelsLUTData.swift is generated base64 (false positives) whose one fatalError is a
# documented integrity trap, not a stub.
if command -v rg >/dev/null 2>&1; then
  rg -n -i --no-heading -g '!*.bin' -g '!*.png' -g '!*.svg' -g '!KernelsLUTData.swift' -e "$PATTERN" "${existing[@]}" || true
  files=$(rg -l -i -g '!*.bin' -g '!*.png' -g '!*.svg' -g '!KernelsLUTData.swift' -e "$PATTERN" "${existing[@]}" 2>/dev/null | wc -l | tr -d ' ')
else
  grep -rniE --binary-files=without-match "$PATTERN" "${existing[@]}" || true
  files=$(grep -rliE --binary-files=without-match "$PATTERN" "${existing[@]}" 2>/dev/null | wc -l | tr -d ' ')
fi

echo
echo "== $files file(s) with unfinished-work markers =="
[ "$files" -gt 255 ] && files=255
exit "$files"

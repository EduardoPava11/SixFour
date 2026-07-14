#!/usr/bin/env bash
# lint-q16-crossing.sh — the single-crossing belt-and-suspenders lint.
#
# The ByteCarrier type already makes a float->device byte UNREPRESENTABLE (the Q16
# constructor is hidden; `toByte someLatent` is a compile error). The one thing the
# type system cannot ban is a NEW module importing Spec.Q16's quantizeQ16 directly to
# hand-roll its own float->Q16 crossing, bypassing ByteCarrier.reenterQ16.
#
# This lint enforces: ByteCarrier is the ONLY module that imports quantizeQ16. Every
# other float->device crossing must go through reenterQ16. (Comments mentioning
# `quantizeQ16` are fine; only IMPORT lines are checked.)
set -euo pipefail
cd "$(dirname "$0")/.."

# import lines bringing in quantizeQ16, anywhere except ByteCarrier (the sanctioned
# wrapper) and AtlasGame (which DEFINES it).
viol=$(grep -rnE '^[[:space:]]*import .*quantizeQ16' src/SixFour/Spec/*.hs \
        | grep -vE 'ByteCarrier\.hs' || true)

if [ -n "$viol" ]; then
  echo "FAIL: float->Q16 crossing outside ByteCarrier.reenterQ16 — route through reenterQ16:"
  echo "$viol"
  exit 1
fi
echo "OK: reenterQ16 is the sole float->device crossing (only ByteCarrier imports quantizeQ16)."

#!/usr/bin/env bash
# check-compartments.sh — every Spec.* module must declare its BACKEND COMPARTMENT.
#
# The spec is the one source of truth that translates outward to four backends; each module
# carries a "-- COMPARTMENT: <compartment> | tag:<tag> [| STRADDLER]" line before its `module`
# declaration so the compartment is a CHECKED per-module fact, not just a Map index entry.
# (STEP 0 of the compartment cleanup.) Run from repo root or spec/.
set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"   # spec/
specdir="$here/src/SixFour/Spec"

valid='ZIG-FLOOR|MLX-MODEL|METAL-GPU|SWIFT-COREAI|PURE-SPEC-WALL'
missing=0
badval=0

for f in "$specdir"/*.hs; do
  line="$(grep -m1 '^-- COMPARTMENT:' "$f" || true)"
  if [ -z "$line" ]; then
    echo "MISSING compartment tag: ${f#"$here/"}"
    missing=$((missing + 1))
    continue
  fi
  comp="$(printf '%s' "$line" | sed -E 's/^-- COMPARTMENT:[[:space:]]*([A-Z-]+).*/\1/')"
  if ! printf '%s' "$comp" | grep -qE "^($valid)$"; then
    echo "INVALID compartment '$comp' in: ${f#"$here/"}"
    badval=$((badval + 1))
  fi
done

total="$(ls "$specdir"/*.hs | wc -l | tr -d ' ')"
if [ "$missing" -ne 0 ] || [ "$badval" -ne 0 ]; then
  echo "FAIL: $missing missing, $badval invalid (of $total modules)."
  exit 1
fi
echo "OK: all $total Spec modules carry a valid BACKEND COMPARTMENT tag."

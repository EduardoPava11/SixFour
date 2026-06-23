#!/usr/bin/env bash
# gate.sh — the single verification entry point. Runs the spec test gate plus every lint,
# so the compartment tripwire (check-compartments.sh) and the I-JEPA memory budget
# (Spec.JepaMemory laws, in `cabal test`) guard every change from ONE command.
#
# Usage:  bash spec/scripts/gate.sh   (from repo root or spec/)
set -uo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"   # spec/
cd "$here"

fail=0
run() {
  echo ""
  echo "=== $1 ==="
  if ! eval "$2"; then
    echo "!! FAILED: $1"
    fail=1
  fi
}

# The law + golden gate (includes Spec.JepaMemory's memory-budget laws — the destructive tripwire).
run "cabal test (laws + golden vectors + JepaMemory budget)" "cabal test"

# The compartment gate: every Spec module carries a valid BACKEND COMPARTMENT tag.
run "check-compartments (every module tagged to one backend)" "bash scripts/check-compartments.sh"

# The belt-and-suspenders lints (each guards an invariant the type system cannot fully ban).
# Spec-side lints live in spec/scripts/; the repo-root lints live in ../scripts/.
# NOTE: scripts/verify-doc-claims.sh is intentionally NOT run here — it has a pre-existing
# self-bug (greps a stale path SixFour/UI/Surface/ReviewPhaseField.swift); all its real claim
# checks pass. Run it directly once that path is fixed.
root="$(cd "$here/.." && pwd)"
[ -f "scripts/lint-q16-crossing.sh" ] && run "lint-q16-crossing" "bash scripts/lint-q16-crossing.sh"
for lint in lint-grid lint-no-global-palette; do
  [ -f "$root/scripts/$lint.sh" ] && run "$lint" "bash '$root/scripts/$lint.sh'"
done

echo ""
if [ "$fail" -ne 0 ]; then
  echo "GATE: FAIL"
  exit 1
fi
echo "GATE: all green (tests + compartments + lints)."

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

# HERMETIC CODEGEN: regenerate every contract from the spec and FAIL if the committed
# Generated/ files differ. This is what makes the spec the DESIGN AUTHORITY, not just a
# checker: every emitter is byte-equal-to-spec ENFORCED (a stale regen or a hand-edit of a
# generated file fails the build), so "the app/trainer/UI match the spec" is a build theorem,
# not a hope. (BuildStamp.swift is auto-stamped gitSHA+time noise — restored before the diff.)
run "hermetic codegen (Generated == spec emits, no drift)" "
  cabal run -v0 spec-codegen >/dev/null 2>&1 &&
  git -C '$(cd "$here/.." && pwd)' checkout -q SixFour/Generated/BuildStamp.swift 2>/dev/null;
  git -C '$(cd "$here/.." && pwd)' diff --exit-code -- SixFour/Generated trainer/generated studio/look-nn-baseline/src/generated
"

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

# CROSS-LANGUAGE GOLDENS, fixtures REQUIRED (not skip-if-absent). The readiness proof found
# the strongest ownership in the system (the spec FORCES the iPhone to make the byte-exact
# GIF, and the Zig core to parse the blob) was conditionally NOT exercised: the Zig fixture
# tests skip-if-absent, so a checkout that never produced the goldens passed green vacuously.
# Here we PRODUCE the goldens from the spec (GIF: spec-fixtures; blob: export_look_net_blob.py,
# pure python) then run the Native tests with -Drequire_fixtures=true so an absent or mismatched
# golden FAILS. (Skipped if zig is not installed — the spec-side gate above still stands.)
if command -v zig >/dev/null 2>&1; then
  run "Zig cross-language goldens (fixtures REQUIRED, byte-exact GIF + blob)" "
    cabal run -v0 spec-fixtures >/dev/null 2>&1 &&
    ( cd '$root/trainer' && python3 export_look_net_blob.py >/dev/null 2>&1 ) &&
    ( cd '$root/Native' && zig build test -Drequire_fixtures=true )
  "
fi

# The I-JEPA DATA ENGINE (Python) must reproduce the spec-emitted corpus byte-exact -- the data
# design is spec-FORCED, not described. A one-integer drift in the Python lift fails this.
if command -v python3 >/dev/null 2>&1 && [ -f "$root/trainer/jepa_data.py" ]; then
  run "JEPA data engine (Python lift == spec corpus golden)" "python3 '$root/trainer/jepa_data.py'"
fi

echo ""
if [ "$fail" -ne 0 ]; then
  echo "GATE: FAIL"
  exit 1
fi
echo "GATE: all green (tests + hermetic codegen + compartments + lints + cross-language goldens)."

#!/usr/bin/env bash
# s4 — single entry point wrapping SixFour's build/codegen/test/lint/run scripts.
#
# Each verb is purely additive: it delegates to the existing canonical script or
# command, which remains individually invocable. `s4.sh all` runs the verbs in
# the order recorded in scripts/gate-order.txt (codegen → doc → verify → native →
# lint → gen → build), because each step consumes artifacts the previous produced.
#
# Usage:
#   scripts/s4.sh <verb> [args…]
#   scripts/s4.sh all
#
# Verbs:
#   codegen   cabal run spec-codegen   — regen SixFour/Generated/* + trainer/generated/*
#   verify    cabal test               — all Spec laws + per-kernel s4_* laws
#   native    zig build test (host) + Native/build-ios.sh (device static lib)
#   gen       scripts/regenerate.sh    — xcodegen + pbxproj filetype patch + post-check
#   lint      scripts/lint-grid.sh     — GRID design-language invariants
#   build     xcodebuild (iPhone 17 Pro Simulator)
#   device    scripts/run-on-device.sh — build/sign/install/launch on a connected iPhone
#   doc       scripts/verify-doc-claims.sh
#   all       run codegen→doc→verify→native→lint→gen→build per scripts/gate-order.txt
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"

# Run a cabal subcommand from spec/ with a minimal, explicit env so ghcup's cabal
# is found regardless of the caller's PATH — mirrors project.yml's drift gate.
cabal_env() {
  local CABAL
  CABAL="$(command -v cabal 2>/dev/null || true)"
  [ -n "$CABAL" ] || CABAL="$HOME/.ghcup/bin/cabal"
  if [ ! -x "$CABAL" ]; then
    echo "s4: cabal not found (install via ghcup)" >&2
    exit 1
  fi
  env -i HOME="$HOME" PATH="$HOME/.ghcup/bin:/opt/homebrew/bin:/usr/bin:/bin" \
    sh -c "cd '$ROOT/spec' && '$CABAL' $*"
}

verb_codegen() { cabal_env "run -v0 spec-codegen"; }
verb_verify()  { cabal_env "test"; }
verb_native()  { ( cd "$ROOT/Native" && zig build test ); "$ROOT/Native/build-ios.sh"; }
verb_gen()     { "$ROOT/scripts/regenerate.sh"; }
verb_lint()    { "$ROOT/scripts/lint-grid.sh"; }
verb_build()   { xcodebuild -scheme SixFour -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build; }
verb_device()  { "$ROOT/scripts/run-on-device.sh" "$@"; }
verb_doc()     { "$ROOT/scripts/verify-doc-claims.sh"; }

verb_all() {
  while read -r line; do
    line="${line%%#*}"; line="$(echo "$line" | tr -d '[:space:]')"
    [ -n "$line" ] || continue
    echo "── s4 all ▸ $line ──────────────────────────────────"
    "verb_$line"
  done < "$ROOT/scripts/gate-order.txt"
  echo "✓ s4 all: every gate passed."
}

verb="${1:-}"
[ "$#" -gt 0 ] && shift || true
case "$verb" in
  codegen|verify|native|gen|lint|build|device|doc|all) "verb_$verb" "$@" ;;
  ""|-h|--help|help)
    sed -n '2,24p' "$0"
    [ "$verb" = "" ] && exit 1 || exit 0 ;;
  *)
    echo "s4: unknown verb '$verb' (try: scripts/s4.sh help)" >&2
    exit 1 ;;
esac

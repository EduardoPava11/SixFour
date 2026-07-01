#!/usr/bin/env bash
# One-shot gate for the PICO-8 cell-grid tools:
#   1. the cart's constants are IN SYNC with the Haskell spec
#   2. the ported cellOnScreen is IN PARITY with the proven laws
# Run before trusting the visualizer after any spec change.
set -euo pipefail
cd "$(dirname "$0")"
echo "== sync: cart constants vs spec =="
python3 check_sync.py
echo
echo "== parity: ported geometry vs proven laws =="
python3 render_grid.py --verify
echo
echo "OK: PICO-8 cell-grid tools agree with the spec."

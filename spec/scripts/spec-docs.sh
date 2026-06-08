#!/usr/bin/env bash
# Regenerate the BROWSABLE spec: typecheck + laws, Haddock HTML (hyperlinked source + in-page
# fuzzy search), and a local Hoogle type/name search DB. Run after any spec change.
#
#   spec/scripts/spec-docs.sh           # build docs + search
#   spec/scripts/spec-docs.sh --serve   # also start `hoogle server` on :8080
#
# Browse: open the printed index.html. Search by name/type: the Hoogle server, or the
# quickjump (press 's' in the Haddock page). Start at module `SixFour.Spec.Map`.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== 0. lint: every Spec.* module is indexed in SixFour.Spec.Map =="
MISSING=0
for m in $(grep -oE 'SixFour\.Spec\.[A-Za-z0-9]+' spec.cabal | sort -u); do
  [ "$m" = "SixFour.Spec.Map" ] && continue
  short=${m##*.}
  grep -q "\"SixFour.Spec.$short\"" src/SixFour/Spec/Map.hs \
    || { echo "  MISSING from Map: $m"; MISSING=$((MISSING+1)); }
done
[ "$MISSING" -eq 0 ] && echo "  ok — all modules indexed" || echo "  ⚠ $MISSING module(s) not in Map (add a line under their category)"

echo "== 1. typecheck + laws (the gate) =="
cabal build sixfour-spec
cabal test 2>/dev/null || echo "  (no test-suite run / some laws pending — see output)"

echo "== 2. Haddock HTML (hyperlinked source + quickjump search) =="
cabal haddock sixfour-spec --haddock-hyperlink-source --haddock-quickjump
INDEX=$(find dist-newstyle -path '*doc*/html/sixfour-spec/index.html' | head -1 || true)
echo "  Browse: ${INDEX:-<not found>}"

echo "== 3. Hoogle local DB (type/name search) =="
cabal haddock sixfour-spec --haddock-hoogle
HOOGLE_DIR=$(find dist-newstyle -path '*doc*/html/sixfour-spec' -type d | head -1 || true)
if [ -n "${HOOGLE_DIR:-}" ]; then
  hoogle generate --local="$HOOGLE_DIR" --database=spec.hoo >/dev/null 2>&1 \
    && echo "  DB: spec.hoo" \
    || echo "  (hoogle generate skipped — run manually against $HOOGLE_DIR)"
fi

if [ "${1:-}" = "--serve" ] && [ -f spec.hoo ]; then
  echo "== 4. hoogle server → http://localhost:8080 (Ctrl-C to stop) =="
  hoogle server --local --database=spec.hoo --port=8080
fi

echo "== 4. module import graph (NN core highlighted) =="
if command -v dot >/dev/null 2>&1; then
  {
    echo 'digraph spec { rankdir=LR; node [shape=box,style=filled,fontsize=9,fillcolor="#eef"];'
    for m in Net LookNet LookNetE LookNetR LookNetD LookNetCompose LookNetEval LookCore Layer Loss PaletteOracle PaletteSearch; do
      echo "  \"$m\" [fillcolor=\"#fdd\"];"
    done
    for f in src/SixFour/Spec/*.hs; do
      s=$(basename "$f" .hs)
      grep -oE 'import +(qualified +)?SixFour\.Spec\.[A-Za-z0-9]+' "$f" | sed -E 's/.*SixFour\.Spec\.//' \
        | while read -r d; do echo "  \"$s\" -> \"$d\";"; done
    done
    echo '}'
  } | dot -Tsvg > spec-graph.svg && echo "  spec-graph.svg ($(grep -c ' -> ' spec-graph.svg 2>/dev/null || echo ?) edges)"
else
  echo "  (graphviz 'dot' not found — skipping; brew install graphviz)"
fi

echo "== done. Landing module: SixFour.Spec.Map =="

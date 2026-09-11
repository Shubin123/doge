#!/usr/bin/env bash
#
# Build the web (wasm) version of the game with love.js.
#
#   ./buildjs.sh              -> dist/web/  (open with a static server, not file://)
#
# Notes on the two knobs that matter:
#
#   * COMPATIBILITY MODE (-c) is not optional for us. love.js's default
#     "release" runtime is threaded, which needs SharedArrayBuffer, which needs
#     the COOP/COEP response headers -- and GitHub Pages cannot set headers.
#     The compat runtime is single-threaded and works on any static host.
#
#   * MEMORY (-m) is a FIXED emscripten heap, and love.js refuses a value
#     smaller than the packaged assets. The atlas dominates it: 8.8 MB on disk
#     unpacks to a 16384x16384 DXT5 surface (256 MB) that is briefly resident
#     before it is uploaded to the GPU. Override with LOVEJS_MEMORY if you
#     change the atlas.

set -euo pipefail
cd "$(dirname "$0")"
ROOT="$PWD"

OUT="${OUT:-$ROOT/dist/web}"
LOVEFILE="$ROOT/dist/doge.love"
TITLE="${TITLE:-doge}"
MEMORY="${LOVEJS_MEMORY:-1610612736}"   # 1.5 GiB

LOVEJS="$ROOT/node_modules/.bin/love.js"
if [ ! -x "$LOVEJS" ]; then
    echo "love.js not installed; running npm install ..." >&2
    npm install --silent
fi
[ -x "$LOVEJS" ] || { echo "error: $LOVEJS still missing after npm install." >&2; exit 1; }

# The web runtime is plain Lua 5.1, not LuaJIT: goto/labels and other 5.2+
# syntax parse fine on the desktop build and are a fatal error here.
echo "==> checking Lua 5.1 compatibility"
python3 "$ROOT/tools/check_lua51.py" "$ROOT/src"

echo "==> packaging $LOVEFILE"
"$ROOT/tools/make_love.sh" "$LOVEFILE"

echo "==> love.js (compat runtime, ${MEMORY} bytes heap)"
rm -rf "$OUT"
"$LOVEJS" --compatibility --title "$TITLE" --memory "$MEMORY" "$LOVEFILE" "$OUT"

# love.js writes its own stock index.html; ours replaces it (canvas sizing,
# real progress bar, and an up-front WebGL/S3TC capability check).
if [ -f "$ROOT/tools/web/index.html" ]; then
    echo "==> installing custom shell page"
    sed "s/__LOVEJS_MEMORY__/$MEMORY/" "$ROOT/tools/web/index.html" > "$OUT/index.html"
fi
# .nojekyll stops GitHub Pages' Jekyll pass from dropping files it considers
# special; harmless everywhere else.
touch "$OUT/.nojekyll"

echo
echo "built $OUT"
du -sh "$OUT" | awk '{print "  total: " $1}'
echo
echo "serve it (file:// will NOT work -- wasm needs http):"
echo "  npx http-server dist/web -p 8080   # or: python3 -m http.server -d dist/web 8080"

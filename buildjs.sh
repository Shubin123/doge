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
MEMORY="${LOVEJS_MEMORY:-2060045843}"   # ~1.92 GiB heap (required for 16k atlas upload)

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

# Patch node_modules/love.js with the custom S3TC/DXT5 C++ love engine build
CUSTOM_DIR="$ROOT/tools/web/custom-love"
if [ -d "$CUSTOM_DIR" ] && [ -f "$CUSTOM_DIR/love.wasm" ]; then
    echo "==> patching love.js with custom S3TC/DXT5-enabled C++ engine build"
    if [ -d "$ROOT/node_modules/love.js/src/compat" ]; then
        cp "$CUSTOM_DIR/love.js" "$ROOT/node_modules/love.js/src/compat/love.js"
        cp "$CUSTOM_DIR/love.wasm" "$ROOT/node_modules/love.js/src/compat/love.wasm"
    fi
    if [ -d "$ROOT/node_modules/love.js/src/release" ]; then
        cp "$CUSTOM_DIR/love.js" "$ROOT/node_modules/love.js/src/release/love.js"
        cp "$CUSTOM_DIR/love.wasm" "$ROOT/node_modules/love.js/src/release/love.wasm"
    fi
fi

echo "==> love.js (compat runtime, ${MEMORY} bytes heap)"
rm -rf "$OUT"
"$LOVEJS" --compatibility --title "$TITLE" --memory "$MEMORY" "$LOVEFILE" "$OUT"

# Ensure custom S3TC/DXT5 love engine artifacts and theme are installed into output
if [ -d "$CUSTOM_DIR" ] && [ -f "$CUSTOM_DIR/love.wasm" ]; then
    echo "==> installing custom S3TC/DXT5 love engine artifacts into $OUT"
    cp "$CUSTOM_DIR/love.wasm" "$OUT/love.wasm"
    cp "$CUSTOM_DIR/love.js" "$OUT/love.js"
    [ -f "$CUSTOM_DIR/love.worker.js" ] && cp "$CUSTOM_DIR/love.worker.js" "$OUT/love.worker.js"
    [ -d "$CUSTOM_DIR/theme" ] && cp -r "$CUSTOM_DIR/theme" "$OUT/theme"
fi

# love.js writes its own stock index.html; ours replaces it (canvas sizing,
# real progress bar, and an up-front WebGL/S3TC capability check).
if [ -f "$ROOT/tools/web/index.html" ]; then
    echo "==> installing custom shell page with cache-busting"
    BUILD_HASH="$(git rev-parse --short HEAD 2>/dev/null || date +%s)-$(date +%s)"
    sed -e "s/__LOVEJS_MEMORY__/$MEMORY/g" \
        -e "s/__CACHE_BUST__/$BUILD_HASH/g" \
        "$ROOT/tools/web/index.html" > "$OUT/index.html"
fi

# Dummy favicon.ico so browsers don't report 404
touch "$OUT/favicon.ico"

# .nojekyll stops GitHub Pages' Jekyll pass from dropping files it considers
# special; harmless everywhere else.
touch "$OUT/.nojekyll"

echo
echo "built $OUT"
du -sh "$OUT" | awk '{print "  total: " $1}'
echo
echo "serve it (file:// will NOT work -- wasm needs http):"
echo "  npx http-server dist/web -p 8080   # or: python3 -m http.server -d dist/web 8080"

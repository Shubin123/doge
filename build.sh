#!/usr/bin/env bash
#
# Build distributable desktop packages into dist/.
#
#   dist/doge.love   always
#   dist/doge.app    if /Applications/love.app is present (macOS)
#   dist/doge.exe    if misc/love-11.5-win64/love.exe is present (Windows)
#
# The .love itself is built by tools/make_love.sh, which drops the atlas
# source sheets listed in tools/shipping-excludes.txt.

set -euo pipefail
cd "$(dirname "$0")"
ROOT="$PWD"
DIST="$ROOT/dist"
LOVEFILE="$DIST/doge.love"

"$ROOT/tools/make_love.sh" "$LOVEFILE"

# --- macOS .app ----------------------------------------------------------
LOVE_APP="${LOVE_APP:-/Applications/love.app}"
if [ -d "$LOVE_APP" ]; then
    rm -rf "$DIST/doge.app"
    cp -R "$LOVE_APP" "$DIST/doge.app"
    cp "$LOVEFILE" "$DIST/doge.app/Contents/Resources/"
    # Drop the ad-hoc signature the copy invalidates, so Gatekeeper doesn't
    # refuse to launch it on the build machine.
    codesign --remove-signature "$DIST/doge.app" 2>/dev/null || true
    echo "built dist/doge.app"
else
    echo "skip .app: $LOVE_APP not found (set LOVE_APP=/path/to/love.app)"
fi

# --- Windows .exe (fused love.exe + .love) -------------------------------
WIN_DIR="${WIN_DIR:-$ROOT/misc/love-11.5-win64}"
if [ -f "$WIN_DIR/love.exe" ]; then
    cat "$WIN_DIR/love.exe" "$LOVEFILE" > "$DIST/doge.exe"
    echo "built dist/doge.exe"
    echo "  (ship it alongside the DLLs in $(basename "$WIN_DIR")/)"
else
    echo "skip .exe: $WIN_DIR/love.exe not found"
    echo "  download the 64-bit Windows LÖVE 11.5 zip and unpack it there"
fi

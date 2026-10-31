#!/bin/sh
# Render the weapon model turntables (main.lua) and DXT5-encode them into
# src/gfx/3d/<model>.dds, the held-model sheets gun.lua loads.
#
#   tools/weapon_models/build.sh            # every model
#   tools/weapon_models/build.sh pistol bow # just these
#
# Needs LOVE 11 ($LOVE, /Applications/love.app, or love on PATH) and gcc
# (bc-encoder/bc3enc is built on first use).
set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

LOVE="${LOVE:-/Applications/love.app/Contents/MacOS/love}"
[ -x "$LOVE" ] || LOVE=love

ENC="$ROOT/bc-encoder/bc3enc"
[ -x "$ENC" ] || gcc -O2 -o "$ENC" "$ROOT/bc-encoder/main.c" -lm

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

"$LOVE" "$ROOT/tools/weapon_models" "$TMP" "$@"
for png in "$TMP"/*.png; do
    name="$(basename "$png" .png)"
    "$ENC" "$png" "$ROOT/src/gfx/3d/$name.dds" > /dev/null
    echo "src/gfx/3d/$name.dds"
done

#!/usr/bin/env bash
#
# Package src/ into a .love archive, minus the assets listed in
# tools/shipping-excludes.txt (atlas source sheets and stale pipeline
# artifacts — see that file for why, and how the list was derived).
#
# Usage: tools/make_love.sh [output.love]
#   default output: dist/doge.love

set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
OUT="${1:-$ROOT/dist/doge.love}"
EXCLUDES="$ROOT/tools/shipping-excludes.txt"

command -v zip >/dev/null || { echo "error: 'zip' is required but not installed." >&2; exit 1; }
[ -f "$ROOT/src/main.lua" ] || { echo "error: src/main.lua not found." >&2; exit 1; }

mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"

# Build the zip exclude args from the list (strip comments/blank lines).
# `zip -x` patterns are matched against the archive-relative path.
zipargs=()
while IFS= read -r line; do
    line="${line%%#*}"                      # drop trailing comment
    line="$(printf '%s' "$line" | sed -e 's/[[:space:]]*$//')"
    [ -z "$line" ] && continue
    zipargs+=(-x "$line")
done < "$EXCLUDES"

# Housekeeping junk that should never ship regardless.
zipargs+=(-x '*.DS_Store' -x '*/.DS_Store' -x '*.aseprite' -x '*.pxo')

# LÖVE requires main.lua at the archive root, so zip from inside src/.
( cd "$ROOT/src" && zip -9 -r -q "$OUT" . "${zipargs[@]}" )

size=$(stat -f%z "$OUT" 2>/dev/null || stat -c%s "$OUT")
printf 'built %s (%.1f MB, %s files)\n' \
    "${OUT#$ROOT/}" "$(echo "$size" | awk '{print $1/1048576}')" \
    "$(unzip -l "$OUT" | tail -1 | awk '{print $2}')"

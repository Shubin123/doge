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

[ -f "$ROOT/src/main.lua" ] || { echo "error: src/main.lua not found." >&2; exit 1; }

mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"

if ! command -v zip >/dev/null 2>&1; then
    python3 - <<PYEOF
import os, zipfile, fnmatch
root = "$ROOT"
src = os.path.join(root, "src")
out = "$OUT"
excludes_file = "$EXCLUDES"
excludes = ['*.DS_Store', '*/.DS_Store', '*.aseprite', '*.pxo']
if os.path.exists(excludes_file):
    with open(excludes_file) as f:
        for line in f:
            line = line.split('#')[0].strip()
            if line: excludes.append(line)
def match_exclude(rel):
    for pat in excludes:
        if fnmatch.fnmatch(rel, pat) or fnmatch.fnmatch(os.path.basename(rel), pat): return True
        if pat.startswith("*/") and fnmatch.fnmatch(rel, pat[2:]): return True
        if pat.endswith("/*") and rel.startswith(pat[:-2]): return True
    return False
count = 0
with zipfile.ZipFile(out, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
    for dirpath, dirnames, filenames in os.walk(src):
        for f in filenames:
            full = os.path.join(dirpath, f)
            rel = os.path.relpath(full, src).replace("\\\\", "/")
            if not match_exclude(rel):
                zf.write(full, rel)
                count += 1
size = os.path.getsize(out) / 1048576
print(f"built {os.path.relpath(out, root)} ({size:.1f} MB, {count} files)")
PYEOF
    exit 0
fi

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

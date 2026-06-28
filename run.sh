#!/usr/bin/env bash
#
# Run the game in development mode.
#
# The entire game has ONE entry point: ./src
# LÖVE loads src/conf.lua first (defines the global `var`) then src/main.lua.
#
# Optional argument selects a multiplayer instance id (read by conf.lua as
# arg[2], e.g. `./run.sh 1`). Omit it for normal single-player.
# To launch two networked instances at once:
#     ./run.sh 1 & ./run.sh 2
#
# Override the LÖVE binary with the LOVE env var if it lives elsewhere:
#     LOVE=/usr/bin/love ./run.sh

set -euo pipefail

# Run from the repo root regardless of where the script is invoked from,
# so the relative ./src path always resolves.
cd "$(dirname "$0")"

LOVE="${LOVE:-/Applications/love.app/Contents/MacOS/love}"

if [ ! -x "$LOVE" ]; then
    echo "error: LÖVE binary not found at '$LOVE'." >&2
    echo "Install LÖVE 11.5 (https://love2d.org) or set LOVE=/path/to/love." >&2
    exit 1
fi

if [ ! -f ./src/main.lua ]; then
    echo "error: ./src/main.lua not found (run this from the project root)." >&2
    exit 1
fi

# exec replaces the shell so Ctrl-C and exit codes pass straight through.
exec "$LOVE" ./src "$@"

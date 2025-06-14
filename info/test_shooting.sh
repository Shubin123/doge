#!/bin/bash

echo "Testing weapon shooting in DOGE game..."
echo "Instructions:"
echo "1. Press number keys 1-5 to switch weapons"
echo "2. Click left mouse button to shoot"
echo "3. Press F key to force a shooting test"
echo "4. Watch the console for debug logs"
echo ""
echo "Starting game..."

# Run the game and filter for weapon-related logs
'/Applications/love.app/Contents/MacOS/love' ./src 2>&1 | grep -E "\[WEAPONS_CORE_MOD\]|\[PROJECTILES_MOD\]|\[DEBUG\]|\[ERROR\]"
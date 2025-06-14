#!/bin/bash
# Test script for multiplayer PvP damage

echo "Testing Multiplayer PvP Damage System"
echo "====================================="
echo ""
echo "This script will help you test PvP damage in multiplayer mode."
echo ""
echo "Instructions:"
echo "1. Run this script to start the host"
echo "2. In another terminal, run: '/Applications/love.app/Contents/MacOS/love' ./src 2 127.0.0.1"
echo "3. Use number keys 1-5 to switch weapons"
echo "4. Click to shoot at the other player"
echo "5. Verify that damage is applied correctly"
echo ""
echo "Starting host in 3 seconds..."
sleep 3

# Start the game as host
'/Applications/love.app/Contents/MacOS/love' ./src 1
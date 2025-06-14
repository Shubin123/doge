#!/bin/bash
# Test script to check mod loading output

cd /Users/amanson/Desktop/Projects_Main_Folder/CanvasTools/doge
./run.sh 2>&1 | grep -E "(MOD_SYSTEM|WEAPONS_CORE_MOD|Failed|Error)" | head -50
#!/bin/bash

# unpack.sh - Extract .love file from a LÖVE game executable
# Usage: ./unpack.sh <input_exe> [output_love]

set -e

if [ $# -lt 1 ]; then
    echo "Usage: $0 <input_exe> [output_love]"
    echo "Extract .love file from a LÖVE game executable"
    exit 1
fi

INPUT_FILE="$1"
OUTPUT_FILE="${2:-${INPUT_FILE%.*}.love}"

if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: Input file '$INPUT_FILE' not found"
    exit 1
fi

echo "Searching for ZIP signature in '$INPUT_FILE'..."

# Search for ZIP file signature (PK 03 04) - marks beginning of ZIP file
# .love files are ZIP archives, so we look for this signature
OFFSET=$(grep -abo $'\x50\x4b\x03\x04' "$INPUT_FILE" | head -1 | cut -d: -f1)

if [ -z "$OFFSET" ]; then
    echo "Error: No ZIP signature found. This may not be a valid LÖVE executable."
    exit 1
fi

echo "Found ZIP signature at byte offset: $OFFSET"

# Extract from the offset to end of file
echo "Extracting .love file to '$OUTPUT_FILE'..."
tail -c +$((OFFSET + 1)) "$INPUT_FILE" > "$OUTPUT_FILE"

# Verify the extracted file is a valid ZIP
echo "Verifying extracted file..."
if unzip -t "$OUTPUT_FILE" >/dev/null 2>&1; then
    echo "Success! Extracted valid .love file: $OUTPUT_FILE"
    
    # Show some info about the extracted file
    echo "File size: $(wc -c < "$OUTPUT_FILE") bytes"
    echo "Contents:"
    unzip -l "$OUTPUT_FILE" | head -10
    
    if [ $(unzip -l "$OUTPUT_FILE" | wc -l) -gt 15 ]; then
        echo "... (showing first few files only)"
    fi
else
    echo "Warning: Extracted file may not be a valid .love archive"
    echo "File created: $OUTPUT_FILE ($(wc -c < "$OUTPUT_FILE") bytes)"
fi
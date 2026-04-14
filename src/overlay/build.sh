#!/usr/bin/env bash
# Compile the LockScreen Swift binary
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT="${1:-$SCRIPT_DIR/../../bin/zzz-overlay}"

echo "Compiling LockScreen overlay..."
swiftc \
  -O \
  -o "$OUTPUT" \
  -framework Cocoa \
  -framework CoreGraphics \
  "$SCRIPT_DIR/LockScreen.swift"

chmod +x "$OUTPUT"
echo "Built: $OUTPUT"

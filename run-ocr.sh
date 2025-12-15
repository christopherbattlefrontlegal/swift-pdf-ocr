#!/bin/bash
# Simple wrapper for Automator to call pdf-ocr

# Enable logging
LOG="/tmp/pdf-ocr-debug.log"
exec >> "$LOG" 2>&1

echo "=== PDF OCR Started at $(date) ==="
echo "Shell: $SHELL"
echo "User: $USER"
echo "PWD: $PWD"
echo "Received $# arguments:"

# Show all arguments
for i in "$@"; do
    echo "  - $i"
done

# Path to OCR tool
TOOL="/Users/homestuff/Documents/Development/swift.ocr/.build/release/pdf-ocr"

echo ""
echo "Tool path: $TOOL"
echo "Tool exists: $([ -x "$TOOL" ] && echo "YES" || echo "NO")"
echo ""

# Run the tool
echo "Executing OCR..."
"$TOOL" "$@"
EXIT_CODE=$?

echo ""
echo "Exit code: $EXIT_CODE"
echo "=== Completed at $(date) ==="

exit $EXIT_CODE

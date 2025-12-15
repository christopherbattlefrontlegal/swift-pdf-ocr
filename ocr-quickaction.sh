#!/bin/zsh
PDF_OCR="/Users/homestuff/Documents/Development/swift.ocr/pdf-ocr"
for f in "$@"; do
    "$PDF_OCR" "$f"
done

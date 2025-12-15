# PDF OCR - Apple Vision Framework

A high-performance command-line tool for macOS that adds searchable text layers to PDFs using Apple's Vision framework. Creates "sandwich PDFs" with the original content preserved and an invisible, searchable text layer overlaid.

## Features

- **Native Apple Vision OCR** - Leverages Apple's state-of-the-art Vision framework for accurate text recognition
- **Sandwich PDF Creation** - Preserves original PDF appearance while adding searchable text
- **Word-Level Positioning** - Precisely positions text at word boundaries for accurate search results
- **Image Enhancement** - Optional preprocessing with contrast, brightness, and sharpness adjustments
- **Multi-Language Support** - Supports all languages available in Apple's Vision framework
- **Fast & Accurate Modes** - Choose between speed and accuracy based on your needs
- **Batch Processing** - Process individual files or entire folders recursively
- **Smart Skip Detection** - Automatically skips PDFs that already have text
- **Atomic Operations** - Safe in-place replacement with temporary file protection

## Requirements

- macOS 13.0 (Ventura) or later
- Xcode 14.0+ or Swift 5.9+ (for building from source)
- Apple Silicon or Intel Mac

## Installation

### Build from Source

```bash
# Clone the repository
git clone https://github.com/YOUR_USERNAME/swift-pdf-ocr.git
cd swift-pdf-ocr

# Build using Swift Package Manager
swift build -c release

# The executable will be at .build/release/pdf-ocr
# Optionally, copy to your PATH
cp .build/release/pdf-ocr /usr/local/bin/
```

### Using the Swift Script Directly

```bash
# Make executable
chmod +x ocrpdf.swift

# Run directly
./ocrpdf.swift path/to/file.pdf
```

## Usage

### Basic Usage

```bash
# Process a single PDF (in-place replacement)
pdf-ocr document.pdf

# Process a folder of PDFs
pdf-ocr ~/Documents/Scans/
```

### Advanced Options (ocrpdf.swift)

```bash
# Custom DPI for better accuracy (default: 600)
./ocrpdf.swift file.pdf --dpi 300

# Disable image enhancement (faster, less accurate)
./ocrpdf.swift file.pdf --no-enhance

# Fast mode (speed over accuracy)
./ocrpdf.swift file.pdf --fast

# Multiple languages
./ocrpdf.swift file.pdf --lang en-US,es-ES,fr-FR

# Create separate output file instead of in-place
./ocrpdf.swift file.pdf --no-in-place

# Process multiple files/folders
./ocrpdf.swift *.pdf ~/Downloads/ --dpi 300 --lang en-US
```

## How It Works

1. **Page Rendering** - Each PDF page is rendered to a high-resolution image (default 600 DPI)
2. **Image Enhancement** (optional) - Applies Core Image filters to improve text clarity:
   - Desaturation to grayscale
   - Contrast enhancement
   - Noise reduction
   - Unsharp mask for edge definition
3. **OCR Processing** - Apple Vision framework recognizes text with word-level bounding boxes
4. **Text Layer Creation** - Invisible text is positioned precisely over recognized words
5. **PDF Generation** - Original page is drawn with the invisible text layer on top
6. **Atomic Replacement** - Safe file replacement using temporary files

## Comparison: Two Implementations

This repository contains two implementations:

### `ocrpdf.swift` - Advanced CLI Tool
- Full command-line argument parsing
- Image enhancement filters
- Word-level text tokenization for precise positioning
- Configurable DPI, languages, and processing modes
- Atomic file replacement
- Direct use of CGPDFDocument and CGContext

### `Sources/main.swift` - Swift Package Version
- Simpler, cleaner architecture
- Uses PDFKit for easier PDF handling
- Automatic detection of existing text
- Progress reporting for multi-page documents
- Better structured for library use

Both create proper sandwich PDFs with excellent search accuracy.

## Performance

- **Speed**: ~1-3 seconds per page (accurate mode), ~0.5-1 second per page (fast mode)
- **Accuracy**: Excellent for printed text, good for clean handwriting
- **File Size**: Output PDFs are typically 10-30% larger than input due to text layer

## Supported Languages

Query available languages programmatically:

```swift
import Vision
let languages = try VNRecognizeTextRequest().supportedRecognitionLanguages()
print(languages)
```

Common languages include: English, Spanish, French, German, Italian, Portuguese, Chinese, Japanese, Korean, and many more.

## Troubleshooting

**PDF has no searchable text after processing:**
- Try increasing DPI: `--dpi 600` or `--dpi 1200`
- Enable enhancement: Remove `--no-enhance` flag
- Use accurate mode: Remove `--fast` flag

**Processing is too slow:**
- Use fast mode: `--fast`
- Reduce DPI: `--dpi 300`
- Disable enhancement: `--no-enhance`

**Text positioning is inaccurate:**
- Use word-level version (`ocrpdf.swift`)
- Increase DPI for better recognition

## Related Projects

- [OCRmyPDF-AppleOCR](https://github.com/mkyt/OCRmyPDF-AppleOCR) - Plugin for OCRmyPDF using Apple Vision
- [SwiftOCR-Vision](https://github.com/adiaholic/SwiftOCR-Vision) - Swift OCR examples using Vision framework
- [swiftocr](https://github.com/fny/swiftocr) - macOS OCR CLI for various image formats

## Technical Details

**Sandwich PDF Architecture:**
- Layer 1: Original PDF page rendered exactly as-is
- Layer 2: Invisible text positioned at word coordinates
- Text rendering mode: `.invisible` (PDF spec compliance)
- Font: Helvetica with dynamic sizing and horizontal scaling to match bounding boxes

**Vision Framework Configuration:**
- Recognition level: `.accurate` (neural network-based) or `.fast`
- Language correction: Enabled by default
- Minimum text height: 0.01 (normalized coordinates)

## License

MIT License - See LICENSE file for details

## Contributing

Contributions welcome! Please feel free to submit issues or pull requests.

## Acknowledgments

Built with Apple's Vision framework and Core Graphics. Inspired by the OCR community's work on creating searchable PDFs.

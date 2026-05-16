# PDF OCR - Apple Vision Framework

A high-performance command-line tool for macOS that adds searchable text layers to PDFs using Apple's Vision framework. Creates "sandwich PDFs" with the original content preserved and an invisible, searchable text layer overlaid.

## Features

- **Native Apple Vision OCR** - Leverages Apple's state-of-the-art Vision framework for accurate text recognition
- **Sandwich PDF Creation** - Preserves original PDF appearance while adding searchable text
- **Word-Level Positioning** - Precisely positions text at word boundaries for pixel-accurate highlight selection
- **Exact Dimension Preservation** - Maintains original document size (8.5x11, A4, etc.) with zero scaling
- **In-Place Replacement** - Always overwrites original files atomically (no separate output files)
- **Image Enhancement** - Optional preprocessing with contrast, brightness, and sharpness adjustments
- **Multi-Language Support** - Supports all languages available in Apple's Vision framework
- **Fast & Accurate Modes** - Choose between speed and accuracy based on your needs
- **Batch Processing** - Process individual files or entire folders recursively
- **Smart Skip Detection** - Automatically skips PDFs that already have text
- **Atomic Operations** - Safe file replacement using temporary files, then deletion after success

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
# Process a single PDF (overwrites original file)
pdf-ocr document.pdf

# Process a folder of PDFs (all files overwritten in-place)
pdf-ocr ~/Documents/Scans/
```

### Advanced Options

```bash
# Custom DPI for better accuracy (default: 600)
pdf-ocr file.pdf --dpi 300

# Disable image enhancement (faster, less accurate)
pdf-ocr file.pdf --no-enhance

# Fast mode (speed over accuracy)
pdf-ocr file.pdf --fast

# Multiple languages
pdf-ocr file.pdf --lang en-US,es-ES,fr-FR

# Verbose output with per-page timing and dimensions
pdf-ocr file.pdf --verbose

# Check version
pdf-ocr --version

# List all supported languages
pdf-ocr --list-languages

# Process multiple files/folders
pdf-ocr *.pdf ~/Downloads/ --dpi 300 --lang en-US
```

**IMPORTANT:** All files are modified **in-place** with atomic replacement. The original file is overwritten after successful OCR processing. A temporary file is created during processing, then replaces the original upon success.

## How It Works

1. **Page Rendering** - Each PDF page is rendered to a high-resolution image (default 600 DPI)
2. **Dimension Preservation** - Original page dimensions are captured and maintained exactly (no scaling)
3. **Image Enhancement** (optional) - Applies Core Image filters to improve text clarity:
   - Desaturation to grayscale
   - Contrast enhancement
   - Noise reduction
   - Unsharp mask for edge definition
4. **OCR Processing** - Apple Vision framework recognizes text with word-level bounding boxes
5. **Text Layer Creation** - Invisible text is positioned precisely over recognized words at pixel-accurate coordinates
6. **PDF Generation** - Original page is drawn with the invisible text layer on top using exact original dimensions
7. **Atomic Replacement** - Temporary file replaces original file safely, then temp file is deleted

## Implementation Details

The tool uses a unified, optimized implementation (`Sources/main.swift`) that combines:

- **Word-level tokenization** for pixel-accurate text positioning
- **Image enhancement filters** for better OCR accuracy
- **Atomic file operations** for safe in-place replacement
- **Dimension preservation** to maintain exact document sizes
- **Smart text detection** to skip already-processed PDFs
- **Performance tracking** with verbose mode for optimization

The `ocrpdf.swift` file is a legacy standalone script. The recommended approach is to build with Swift Package Manager for the full-featured version.

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

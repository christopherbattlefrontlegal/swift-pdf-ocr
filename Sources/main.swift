#!/usr/bin/env swift
//
//  PDF OCR Tool - Apple Vision Framework
//  Creates searchable sandwich PDFs with word-level precision
//

import Foundation
import Vision
import CoreGraphics
import CoreText
import CoreImage
import ImageIO
import AppKit
import Quartz
import PDFKit

// MARK: - Configuration

let version = "1.0.0"

struct Options {
    var dpi: CGFloat = 1200  // Increased from 600 - blow it up HUGE for better OCR
    var enhance: Bool = true
    var languages: [String] = ["en-US"]
    var fast: Bool = false
    var skipExisting: Bool = true
    var verbose: Bool = false
    var flatten: Bool = false  // Disable flattening - it may destroy OCR-able content
}

// MARK: - CLI Argument Parsing

func parseArguments() -> (Options, [String]) {
    let argv = CommandLine.arguments
    var opt = Options()
    var inputs: [String] = []

    var i = 1
    while i < argv.count {
        let a = argv[i]
        switch a {
        case "--dpi":
            guard i + 1 < argv.count, let v = Double(argv[i + 1]) else {
                fputs("Error: --dpi requires a numeric value\n", stderr)
                exit(2)
            }
            opt.dpi = CGFloat(v)
            i += 2
        case "--no-enhance":
            opt.enhance = false
            i += 1
        case "--lang":
            guard i + 1 < argv.count else {
                fputs("Error: --lang requires comma-separated language codes\n", stderr)
                exit(2)
            }
            opt.languages = argv[i + 1].split(separator: ",").map(String.init)
            i += 2
        case "--fast":
            opt.fast = true
            i += 1
        case "--force":
            opt.skipExisting = false
            i += 1
        case "--verbose", "-v":
            opt.verbose = true
            i += 1
        case "--version":
            print("pdf-ocr version \(version)")
            exit(0)
        case "--list-languages":
            listSupportedLanguages()
            exit(0)
        case "--help", "-h":
            printUsage()
            exit(0)
        default:
            inputs.append(a)
            i += 1
        }
    }

    return (opt, inputs)
}

func listSupportedLanguages() {
    print("Querying supported languages from Vision framework...")
    do {
        let request = VNRecognizeTextRequest()
        let languages = try request.supportedRecognitionLanguages()
        print("\nSupported Languages (\(languages.count) total):")
        for lang in languages.sorted() {
            print("  - \(lang)")
        }
    } catch {
        print("Error querying languages: \(error)")
    }
}

func printUsage() {
    print("""
    PDF OCR - Apple Vision Framework v\(version)

    Usage:
      pdf-ocr <file-or-folder> [options]

    Arguments:
      <file-or-folder>    PDF file or directory to process

    Options:
      --dpi <value>       Resolution for OCR (default: 600)
      --no-enhance        Disable image enhancement
      --lang <codes>      Comma-separated language codes (default: en-US)
      --fast              Use fast recognition mode (less accurate)
      --force             Process PDFs even if they already have text
      -v, --verbose       Show detailed processing information
      --version           Show version information
      --list-languages    List all supported OCR languages
      -h, --help          Show this help message

    Note:
      Files are ALWAYS modified in-place with atomic replacement.
      Original document dimensions are preserved exactly.
      Temporary files are used during processing then deleted.

    Examples:
      pdf-ocr document.pdf
      pdf-ocr ~/Documents/Scans/ --dpi 300
      pdf-ocr file.pdf --lang en-US,es-ES --fast
      pdf-ocr folder/ --no-enhance --verbose
    """)
}

// MARK: - File Management

let fm = FileManager.default

func expandPDFs(_ paths: [String]) -> [URL] {
    var out: [URL] = []
    for p in paths {
        let u = URL(fileURLWithPath: (p as NSString).expandingTildeInPath)
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: u.path, isDirectory: &isDir) else {
            fputs("Warning: Not found: \(u.path)\n", stderr)
            continue
        }
        if isDir.boolValue {
            if let e = fm.enumerator(at: u, includingPropertiesForKeys: [.isRegularFileKey],
                                     options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
                for case let f as URL in e where f.pathExtension.lowercased() == "pdf" {
                    out.append(f)
                }
            }
        } else if u.pathExtension.lowercased() == "pdf" {
            out.append(u)
        }
    }
    out.sort { $0.path < $1.path }
    return out
}

// MARK: - PDF Text Detection

func pdfHasText(_ url: URL) -> Bool {
    guard let doc = CGPDFDocument(url as CFURL) else { return false }
    let pagesToCheck = min(3, doc.numberOfPages)

    for i in 1...pagesToCheck {
        guard let page = doc.page(at: i),
              let dict = page.dictionary else { continue }

        var contentsObj: CGPDFObjectRef?
        guard CGPDFDictionaryGetObject(dict, "Contents", &contentsObj) else { continue }

        var stream: CGPDFStreamRef?
        if CGPDFObjectGetValue(contentsObj!, .stream, &stream) {
            var format = CGPDFDataFormat.raw
            if let data = CGPDFStreamCopyData(stream!, &format) as Data? {
                let content = String(data: data, encoding: .utf8) ?? ""
                if content.contains("Tj") || content.contains("TJ") || content.contains("'") || content.contains("\"") {
                    return true
                }
            }
        }
    }

    return false
}

// MARK: - PDF Geometry

struct PageGeom {
    let box: CGPDFBox
    let rect: CGRect
}

func geom(for page: CGPDFPage) -> PageGeom {
    let crop = page.getBoxRect(.cropBox)
    if !crop.isEmpty { return PageGeom(box: .cropBox, rect: crop) }
    return PageGeom(box: .mediaBox, rect: page.getBoxRect(.mediaBox))
}

// MARK: - Image Rendering

func renderPageImageUsingPDFKit(pdfURL: URL, pageNum: Int, dpi: CGFloat) -> CGImage? {
    // Use PDFKit like Preview does - this works way better!
    guard let pdfDoc = PDFDocument(url: pdfURL),
          let page = pdfDoc.page(at: pageNum) else {
        return nil
    }

    let bounds = page.bounds(for: .mediaBox)
    let scale = dpi / 72.0
    let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)

    // PDFPage.thumbnail() renders correctly for OCR (what Preview uses)
    let nsImage = page.thumbnail(of: size, for: .mediaBox)

    // Convert NSImage to CGImage
    guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        return nil
    }

    return cgImage
}

func renderPageImage(page: CGPDFPage, geom: PageGeom, dpi: CGFloat) -> CGImage? {
    let scale = dpi / 72.0
    let pxW = max(1, Int((geom.rect.width * scale).rounded(.up)))
    let pxH = max(1, Int((geom.rect.height * scale).rounded(.up)))

    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil,
        width: pxW,
        height: pxH,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: pxW, height: pxH))

    let target = CGRect(x: 0, y: 0, width: CGFloat(pxW), height: CGFloat(pxH))
    let t = page.getDrawingTransform(geom.box, rect: target, rotate: 0, preserveAspectRatio: true)
    ctx.concatenate(t)
    ctx.drawPDFPage(page)

    return ctx.makeImage()
}

// MARK: - Image Enhancement

func enhanceImage(_ cg: CGImage) -> CGImage? {
    let input = CIImage(cgImage: cg)
    let ciCtx = CIContext(options: nil)

    // AGGRESSIVE enhancement - convert to grayscale and REALLY increase contrast
    guard let color = CIFilter(name: "CIColorControls") else { return cg }
    color.setValue(input, forKey: kCIInputImageKey)
    color.setValue(0.0, forKey: kCIInputSaturationKey)
    color.setValue(2.0, forKey: kCIInputContrastKey)  // Increased from 1.25 to 2.0
    color.setValue(0.1, forKey: kCIInputBrightnessKey)  // Increased from 0.02 to 0.1
    let out1 = (color.outputImage ?? input)

    // Reduce noise
    guard let noise = CIFilter(name: "CINoiseReduction") else {
        return ciCtx.createCGImage(out1, from: out1.extent)
    }
    noise.setValue(out1, forKey: kCIInputImageKey)
    noise.setValue(0.02, forKey: "inputNoiseLevel")
    noise.setValue(0.4, forKey: "inputSharpness")
    let out2 = (noise.outputImage ?? out1)

    // Sharpen edges
    guard let sharp = CIFilter(name: "CIUnsharpMask") else {
        return ciCtx.createCGImage(out2, from: out2.extent)
    }
    sharp.setValue(out2, forKey: kCIInputImageKey)
    sharp.setValue(0.8, forKey: kCIInputIntensityKey)
    sharp.setValue(1.5, forKey: kCIInputRadiusKey)
    let out3 = (sharp.outputImage ?? out2)

    return ciCtx.createCGImage(out3, from: out3.extent)
}

// MARK: - Vision OCR

func recognizeWords(on cg: CGImage, languages: [String], fast: Bool) throws -> [(String, CGRect)] {
    let req = VNRecognizeTextRequest()
    req.recognitionLevel = fast ? .fast : .accurate
    req.usesLanguageCorrection = true
    req.recognitionLanguages = languages
    req.minimumTextHeight = 0.01

    let handler = VNImageRequestHandler(cgImage: cg, options: [:])
    try handler.perform([req])

    let obs = req.results ?? []
    var out: [(String, CGRect)] = []

    for o in obs {
        guard let best = o.topCandidates(1).first else { continue }
        let s = best.string
        if s.isEmpty { continue }

        // Tokenize into words for precise positioning
        let tokens = s.split(whereSeparator: { $0.isWhitespace })
        var start = s.startIndex

        for tokSub in tokens {
            let tok = String(tokSub)
            guard let r = s.range(of: tok, range: start..<s.endIndex) else { continue }
            start = r.upperBound

            guard let rectObs = try? best.boundingBox(for: r) else { continue }
            let bb = rectObs.boundingBox
            out.append((tok, bb))
        }
    }

    return out
}

func normToPDF(_ bb: CGRect, pageRect: CGRect) -> CGRect {
    CGRect(
        x: pageRect.minX + bb.minX * pageRect.width,
        y: pageRect.minY + bb.minY * pageRect.height,
        width: bb.width * pageRect.width,
        height: bb.height * pageRect.height
    )
}

// MARK: - Text Layer Rendering

func drawInvisibleWord(_ ctx: CGContext, word: String, rect: CGRect) {
    let h = max(1.0, rect.height)
    let fontSize = h * 0.92

    let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
    let descent = CTFontGetDescent(font)

    let astr = NSAttributedString(
        string: word,
        attributes: [kCTFontAttributeName as NSAttributedString.Key: font]
    )
    let line = CTLineCreateWithAttributedString(astr)

    let naturalWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    let targetWidth = max(0.1, rect.width)
    let xScale = max(0.05, targetWidth / max(0.1, naturalWidth))

    ctx.saveGState()
    ctx.setTextDrawingMode(.invisible)
    ctx.translateBy(x: rect.minX, y: rect.minY + descent)
    ctx.scaleBy(x: xScale, y: 1.0)
    ctx.textMatrix = .identity
    CTLineDraw(line, ctx)
    ctx.restoreGState()
}

// MARK: - PDF Flattening

func flattenPDF(input: URL, output: URL, opt: Options) throws {
    guard let doc = CGPDFDocument(input as CFURL) else {
        throw OCRError.cannotOpenPDF(input.path)
    }
    guard let outCtx = CGContext(output as CFURL, mediaBox: nil, nil) else {
        throw OCRError.cannotSavePDF(output.path)
    }

    let pages = doc.numberOfPages
    if opt.verbose {
        print("  Flattening PDF: removing form fields, annotations, and layers...")
    }

    for p in 1...pages {
        guard let page = doc.page(at: p) else { continue }
        let g = geom(for: page)

        // Preserve exact dimensions
        var media = g.rect
        outCtx.beginPage(mediaBox: &media)

        // Render page as high-res image to flatten everything
        // Use same DPI as OCR will use for best quality
        if let flatImage = renderPageImage(page: page, geom: g, dpi: opt.dpi) {
            // Draw the flattened image at original size
            outCtx.draw(flatImage, in: media)
        }

        outCtx.endPage()

        if opt.verbose && pages > 5 && p % 5 == 0 {
            print("  Flattened \(p)/\(pages) pages...")
        }
    }

    outCtx.closePDF()

    if opt.verbose {
        print("  ✓ Flattening complete")
    }
}

// MARK: - Sandwich PDF Creation

func sandwichPDF(input: URL, output: URL, opt: Options) throws {
    guard let doc = CGPDFDocument(input as CFURL) else {
        throw OCRError.cannotOpenPDF(input.path)
    }
    guard let outCtx = CGContext(output as CFURL, mediaBox: nil, nil) else {
        throw OCRError.cannotSavePDF(output.path)
    }

    let pages = doc.numberOfPages
    var totalWords = 0

    for p in 1...pages {
        let pageStart = Date()
        guard let page = doc.page(at: p) else { continue }
        let g = geom(for: page)

        // Preserve EXACT original dimensions - no scaling or resizing
        var media = g.rect

        if opt.verbose {
            let width = media.width / 72.0
            let height = media.height / 72.0
            print("  Page \(p) dimensions: \(String(format: "%.2f", width))\" x \(String(format: "%.2f", height))\" (preserved)")
        }

        outCtx.beginPage(mediaBox: &media)

        // Draw original page
        outCtx.saveGState()
        let t = page.getDrawingTransform(g.box, rect: g.rect, rotate: 0, preserveAspectRatio: true)
        outCtx.concatenate(t)
        outCtx.drawPDFPage(page)
        outCtx.restoreGState()

        // OCR and text layer - use PDFKit rendering like Preview!
        var pageWords = 0
        if let base = renderPageImageUsingPDFKit(pdfURL: input, pageNum: p - 1, dpi: opt.dpi) {
            let ocrImg = opt.enhance ? (enhanceImage(base) ?? base) : base
            let words = try recognizeWords(on: ocrImg, languages: opt.languages, fast: opt.fast)
            pageWords = words.count
            totalWords += pageWords

            for (w, nbb) in words {
                let r = normToPDF(nbb, pageRect: g.rect)
                if r.width < 0.5 || r.height < 0.5 { continue }
                drawInvisibleWord(outCtx, word: w, rect: r)
            }
        }

        outCtx.endPage()

        let pageTime = Date().timeIntervalSince(pageStart)
        if opt.verbose {
            print("  Page \(p)/\(pages): \(pageWords) words, \(String(format: "%.2f", pageTime))s")
        } else if pages > 5 && p % 5 == 0 {
            print("  \(p)/\(pages) pages...")
        }
    }

    outCtx.closePDF()

    if opt.verbose {
        print("  Total: \(totalWords) words recognized")
    }
}

func atomicReplace(tmp: URL, dst: URL) throws {
    // Better atomic replacement - don't remove until we're sure we can move
    let backup = dst.deletingLastPathComponent().appendingPathComponent(".\(dst.lastPathComponent).backup")

    // Step 1: Move original to backup (if it exists)
    if fm.fileExists(atPath: dst.path) {
        // Remove any old backup first
        try? fm.removeItem(at: backup)
        try fm.moveItem(at: dst, to: backup)
    }

    // Step 2: Move temp to final destination
    do {
        try fm.moveItem(at: tmp, to: dst)
        // Success! Remove backup
        try? fm.removeItem(at: backup)
    } catch {
        // Failed! Restore backup
        if fm.fileExists(atPath: backup.path) {
            try? fm.moveItem(at: backup, to: dst)
        }
        throw error
    }
}

// MARK: - Error Types

enum OCRError: LocalizedError {
    case cannotOpenPDF(String)
    case cannotSavePDF(String)

    var errorDescription: String? {
        switch self {
        case .cannotOpenPDF(let p): return "Cannot open PDF: \(p)"
        case .cannotSavePDF(let p): return "Cannot save PDF: \(p)"
        }
    }
}

// MARK: - Main

let (opt, inputs) = parseArguments()

guard !inputs.isEmpty else {
    printUsage()
    exit(1)
}

let pdfs = expandPDFs(inputs)
if pdfs.isEmpty {
    print("No PDF files found")
    exit(0)
}

print("PDF OCR - Apple Vision Framework v\(version)")
print("Found \(pdfs.count) PDF file(s)\n")

let overallStart = Date()
var processed = 0
var skipped = 0
var failed = 0

for (index, pdf) in pdfs.enumerated() {
    print("[\(index + 1)/\(pdfs.count)] \(pdf.lastPathComponent)")

    // Check if PDF already has text
    if opt.skipExisting && pdfHasText(pdf) {
        print("  Skipping - already has text\n")
        skipped += 1
        continue
    }

    // Always use in-place replacement with atomic file operation
    let dir = pdf.deletingLastPathComponent()
    let tmp = dir.appendingPathComponent(".\(pdf.lastPathComponent).tmp.\(UUID().uuidString).pdf")
    let flattened = dir.appendingPathComponent(".\(pdf.lastPathComponent).flat.\(UUID().uuidString).pdf")

    do {
        let fileStart = Date()

        // Step 1: Flatten PDF first (removes form fields, annotations, layers)
        if opt.flatten {
            try flattenPDF(input: pdf, output: flattened, opt: opt)

            // Step 2: OCR the flattened version
            try sandwichPDF(input: flattened, output: tmp, opt: opt)

            // Clean up flattened intermediate file
            try? fm.removeItem(at: flattened)
        } else {
            // Direct OCR without flattening
            try sandwichPDF(input: pdf, output: tmp, opt: opt)
        }

        // Atomic replacement: tmp -> original (same file, same location)
        try atomicReplace(tmp: tmp, dst: pdf)

        let fileTime = Date().timeIntervalSince(fileStart)
        print("  ✓ \(pdf.lastPathComponent) (in-place, \(String(format: "%.1f", fileTime))s)\n")
        processed += 1
    } catch {
        _ = try? fm.removeItem(at: tmp)
        _ = try? fm.removeItem(at: flattened)
        fputs("  ✗ Error: \(error.localizedDescription)\n\n", stderr)
        failed += 1
    }
}

let totalTime = Date().timeIntervalSince(overallStart)
print("Summary: \(processed) processed, \(skipped) skipped, \(failed) failed")
print("Total time: \(String(format: "%.1f", totalTime))s")

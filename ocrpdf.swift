#!/usr/bin/env swift

import Foundation
import Vision
import CoreGraphics
import CoreText
import CoreImage
import ImageIO
import AppKit

// =====================
// CLI
// =====================

struct Options {
    var dpi: CGFloat = 600
    var inPlace: Bool = true
    var enhance: Bool = true
    var languages: [String] = ["en-US"]
    var fast: Bool = false
}

let argv = CommandLine.arguments
var opt = Options()
var inputs: [String] = []

var i = 1
while i < argv.count {
    let a = argv[i]
    switch a {
    case "--dpi":
        guard i + 1 < argv.count, let v = Double(argv[i + 1]) else { exit(2) }
        opt.dpi = CGFloat(v)
        i += 2
    case "--no-enhance":
        opt.enhance = false
        i += 1
    case "--no-in-place":
        opt.inPlace = false
        i += 1
    case "--lang":
        guard i + 1 < argv.count else { exit(2) }
        opt.languages = argv[i + 1].split(separator: ",").map(String.init)
        i += 2
    case "--fast":
        opt.fast = true
        i += 1
    default:
        inputs.append(a)
        i += 1
    }
}

guard !inputs.isEmpty else {
    fputs("""
usage:
  ocrpdf.swift <pdf-or-folder> [more...] [--dpi 600] [--no-enhance] [--lang en-US,es-ES] [--fast] [--no-in-place]

defaults:
  in-place overwrite (atomic replace)
  dpi=600
  enhance=on
  lang=en-US
""", stderr)
    exit(1)
}

let fm = FileManager.default

func expandPDFs(_ paths: [String]) -> [URL] {
    var out: [URL] = []
    for p in paths {
        let u = URL(fileURLWithPath: (p as NSString).expandingTildeInPath)
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: u.path, isDirectory: &isDir) else { continue }
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

let pdfs = expandPDFs(inputs)
if pdfs.isEmpty { exit(0) }

// =====================
// PDF geometry + render
// =====================

struct PageGeom {
    let box: CGPDFBox
    let rect: CGRect
}

func geom(for page: CGPDFPage) -> PageGeom {
    let crop = page.getBoxRect(.cropBox)
    if !crop.isEmpty { return PageGeom(box: .cropBox, rect: crop) }
    return PageGeom(box: .mediaBox, rect: page.getBoxRect(.mediaBox))
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

// =====================
// Core Image preflight
// =====================

func enhanceImage(_ cg: CGImage) -> CGImage? {
    let input = CIImage(cgImage: cg)
    let ciCtx = CIContext(options: nil)

    // CIColorControls
    guard let color = CIFilter(name: "CIColorControls") else { return cg }
    color.setValue(input, forKey: kCIInputImageKey)
    color.setValue(0.0, forKey: kCIInputSaturationKey)
    color.setValue(1.25, forKey: kCIInputContrastKey)
    color.setValue(0.02, forKey: kCIInputBrightnessKey)
    let out1 = (color.outputImage ?? input)

    // CINoiseReduction
    guard let noise = CIFilter(name: "CINoiseReduction") else {
        return ciCtx.createCGImage(out1, from: out1.extent)
    }
    noise.setValue(out1, forKey: kCIInputImageKey)
    noise.setValue(0.02, forKey: "inputNoiseLevel")
    noise.setValue(0.4, forKey: "inputSharpness")
    let out2 = (noise.outputImage ?? out1)

    // CIUnsharpMask
    guard let sharp = CIFilter(name: "CIUnsharpMask") else {
        return ciCtx.createCGImage(out2, from: out2.extent)
    }
    sharp.setValue(out2, forKey: kCIInputImageKey)
    sharp.setValue(0.8, forKey: kCIInputIntensityKey)
    sharp.setValue(1.5, forKey: kCIInputRadiusKey)
    let out3 = (sharp.outputImage ?? out2)

    return ciCtx.createCGImage(out3, from: out3.extent)
}

// =====================
// Vision OCR (word boxes)
// =====================

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

        let tokens = s.split(whereSeparator: { $0.isWhitespace })
        var start = s.startIndex

        for tokSub in tokens {
            let tok = String(tokSub)
            guard let r = s.range(of: tok, range: start..<s.endIndex) else { continue }
            start = r.upperBound

            // macOS 26: boundingBox(for:) returns VNRectangleObservation
            guard let rectObs = try? best.boundingBox(for: r) else { continue }
            let bb = rectObs.boundingBox // normalized, lower-left
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

// =====================
// Draw invisible real PDF text (content stream)
// =====================

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

// =====================
// Sandwich PDF write
// =====================

func sandwichPDF(input: URL, output: URL, opt: Options) throws {
    guard let doc = CGPDFDocument(input as CFURL) else { throw NSError(domain: "OCR", code: 1) }
    guard let outCtx = CGContext(output as CFURL, mediaBox: nil, nil) else { throw NSError(domain: "OCR", code: 2) }

    let pages = doc.numberOfPages
    for p in 1...pages {
        guard let page = doc.page(at: p) else { continue }
        let g = geom(for: page)

        var media = g.rect
        outCtx.beginPage(mediaBox: &media)

        // draw original page
        outCtx.saveGState()
        let t = page.getDrawingTransform(g.box, rect: g.rect, rotate: 0, preserveAspectRatio: true)
        outCtx.concatenate(t)
        outCtx.drawPDFPage(page)
        outCtx.restoreGState()

        // OCR render + preflight
        if let base = renderPageImage(page: page, geom: g, dpi: opt.dpi) {
            let ocrImg = opt.enhance ? (enhanceImage(base) ?? base) : base
            let words = try recognizeWords(on: ocrImg, languages: opt.languages, fast: opt.fast)

            for (w, nbb) in words {
                let r = normToPDF(nbb, pageRect: g.rect)
                if r.width < 0.5 || r.height < 0.5 { continue }
                drawInvisibleWord(outCtx, word: w, rect: r)
            }
        }

        outCtx.endPage()
    }

    outCtx.closePDF()
}

func atomicReplace(tmp: URL, dst: URL) throws {
    if fm.fileExists(atPath: dst.path) { try fm.removeItem(at: dst) }
    try fm.moveItem(at: tmp, to: dst)
}

// =====================
// Run
// =====================

for pdf in pdfs {
    let dir = pdf.deletingLastPathComponent()
    let tmp = dir.appendingPathComponent(".\(pdf.lastPathComponent).tmp.\(UUID().uuidString).pdf")
    let out: URL

    if opt.inPlace {
        out = pdf
    } else {
        let base = pdf.deletingPathExtension().lastPathComponent
        out = dir.appendingPathComponent(base + "_ocr.pdf")
    }

    do {
        try sandwichPDF(input: pdf, output: tmp, opt: opt)
        try atomicReplace(tmp: tmp, dst: out)
        print("OK: \(out.path)")
    } catch {
        _ = try? fm.removeItem(at: tmp)
        fputs("FAIL: \(pdf.path)\n\(error)\n", stderr)
    }
}
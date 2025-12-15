// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "pdf-ocr",
    platforms: [
        .macOS(.v13)  // macOS 13+ for Vision framework improvements
    ],
    products: [
        .executable(
            name: "pdf-ocr",
            targets: ["pdf-ocr"]
        )
    ],
    targets: [
        .executableTarget(
            name: "pdf-ocr",
            path: "Sources"
        )
    ]
)

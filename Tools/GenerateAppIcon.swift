//
//  GenerateAppIcon.swift
//  Dowey — developer tool, not part of the app target.
//
//  Renders Dowey/Assets.xcassets/AppIcon.appiconset from DoweyGlyph, so the icon
//  has exactly one definition in the repo and the PNGs are reproducible:
//
//      swiftc -O Dowey/DoweyGlyph.swift Tools/GenerateAppIcon.swift -o /tmp/dowey-icon
//      /tmp/dowey-icon
//

import AppKit

@main
enum GenerateAppIcon {

    static let sizes: [(name: String, points: Int, scale: Int)] = [
        ("16x16", 16, 1), ("16x16", 16, 2),
        ("32x32", 32, 1), ("32x32", 32, 2),
        ("128x128", 128, 1), ("128x128", 128, 2),
        ("256x256", 256, 1), ("256x256", 256, 2),
        ("512x512", 512, 1), ("512x512", 512, 2),
    ]

    static func render(pixels: Int) -> Data? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: pixels, pixelsHigh: pixels,
                                         bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = NSSize(width: pixels, height: pixels) // 1 point == 1 pixel

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.cgContext.interpolationQuality = .high
        DoweyGlyph.drawAppIcon(side: CGFloat(pixels))
        NSGraphicsContext.restoreGraphicsState()

        return rep.representation(using: .png, properties: [:])
    }

    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let output = root.appendingPathComponent("Dowey/Assets.xcassets/AppIcon.appiconset")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        var images: [[String: String]] = []

        for entry in sizes {
            let pixels = entry.points * entry.scale
            let filename = "icon_\(entry.name)\(entry.scale == 2 ? "@2x" : "").png"
            guard let data = render(pixels: pixels) else {
                FileHandle.standardError.write(Data("failed to render \(filename)\n".utf8))
                exit(1)
            }
            try data.write(to: output.appendingPathComponent(filename))
            images.append(["size": entry.name, "idiom": "mac", "filename": filename, "scale": "\(entry.scale)x"])
            print("wrote \(filename) (\(pixels)px)")
        }

        let contents: [String: Any] = [
            "images": images,
            "info": ["version": 1, "author": "xcode"],
        ]
        let json = try JSONSerialization.data(withJSONObject: contents,
                                              options: [.prettyPrinted, .sortedKeys])
        try json.write(to: output.appendingPathComponent("Contents.json"))
        print("wrote Contents.json")
    }
}

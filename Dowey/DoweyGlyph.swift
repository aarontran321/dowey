//
//  DoweyGlyph.swift
//  Dowey
//
//  Dowey's one piece of iconography: a circle. It is the same shape the gesture
//  puts under the cursor — the center target that means "maximize" — so the menu
//  bar button and the app icon are literally the product's own mark rather than
//  a separate illustration.
//
//  Self-contained on purpose: `Tools/GenerateAppIcon.swift` compiles this file
//  directly to render the asset catalog, so the icon art has one definition and
//  no build-time dependency on the rest of the app.
//

import AppKit

enum DoweyGlyph {

    /// Menu bar button. A template image, so macOS inverts it for dark menu bars
    /// and dims it while the menu is open — the same treatment Apple's own
    /// status items get.
    static func statusItem(size: CGFloat = 16) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            // 1.5 pt at the menu bar's 16 pt, matching SF Symbols' "circle"
            // weight; deliberately not rounded up, which reads as bold.
            let lineWidth = size * 0.095
            let inset = lineWidth / 2 + size * 0.06
            let path = NSBezierPath(ovalIn: rect.insetBy(dx: inset, dy: inset))
            path.lineWidth = lineWidth
            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Dowey"
        return image
    }

    /// App icon artwork for a square canvas of `side` points: a gray squircle
    /// with the circle centered in it, drawn to Apple's 824-in-1024 icon grid.
    static func drawAppIcon(side: CGFloat) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        let canvas = CGRect(x: 0, y: 0, width: side, height: side)
        let shape = canvas.insetBy(dx: side * 0.0977, dy: side * 0.0977)
        let cornerRadius = side * 0.1811
        let squircle = CGPath(roundedRect: shape,
                              cornerWidth: cornerRadius,
                              cornerHeight: cornerRadius,
                              transform: nil)

        // Shadow under the plate, the way macOS icons sit on the Dock.
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -side * 0.012),
                          blur: side * 0.03,
                          color: NSColor.black.withAlphaComponent(0.28).cgColor)
        context.addPath(squircle)
        context.setFillColor(NSColor.black.cgColor)
        context.fillPath()
        context.restoreGState()

        // Gray plate. Light at the top edge, falling off toward the bottom — a
        // single soft gradient, no texture, no bevel.
        context.saveGState()
        context.addPath(squircle)
        context.clip()
        let top = NSColor(srgbRed: 0.36, green: 0.37, blue: 0.40, alpha: 1).cgColor
        let bottom = NSColor(srgbRed: 0.19, green: 0.20, blue: 0.22, alpha: 1).cgColor
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: [top, bottom] as CFArray,
                                     locations: [0, 1]) {
            context.drawLinearGradient(gradient,
                                       start: CGPoint(x: shape.midX, y: shape.maxY),
                                       end: CGPoint(x: shape.midX, y: shape.minY),
                                       options: [])
        }
        context.restoreGState()

        // Hairline along the top edge: the only highlight in the whole icon.
        context.saveGState()
        context.addPath(squircle)
        context.setLineWidth(side * 0.004)
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.18).cgColor)
        context.strokePath()
        context.restoreGState()

        // The circle.
        let ringLineWidth = side * 0.052
        let ringRadius = side * 0.232
        let ring = CGRect(x: canvas.midX - ringRadius, y: canvas.midY - ringRadius,
                          width: ringRadius * 2, height: ringRadius * 2)

        context.saveGState()
        context.setFillColor(NSColor.white.withAlphaComponent(0.14).cgColor)
        context.fillEllipse(in: ring)
        context.setLineWidth(ringLineWidth)
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.96).cgColor)
        context.strokeEllipse(in: ring)
        context.restoreGState()
    }
}

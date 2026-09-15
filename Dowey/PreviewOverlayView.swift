//
//  PreviewOverlayView.swift
//  Dowey
//
//  Destination preview: a thin outline plus a soft flat-gray tint at the rect
//  the window will land in. No screen capture, no blur, no image processing —
//  two CoreGraphics calls per redraw, and a redraw only when the rect changes.
//

import AppKit
import CoreGraphics

final class PreviewOverlayView: NSView {

    private enum Metrics {
        static let cornerRadius: CGFloat = 10
        static let borderWidth: CGFloat = 2
        static let fillAlpha: CGFloat = 0.82
        static let borderAlpha: CGFloat = 1.0
    }

    /// In view-local coordinates. `nil` draws nothing.
    var destinationRect: CGRect? {
        didSet {
            guard oldValue != destinationRect else { return }
            needsDisplay = true
        }
    }

    override var isFlipped: Bool { false }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let rect = destinationRect,
              let context = NSGraphicsContext.current?.cgContext else { return }

        // A centered stroke would be half-clipped where the rect meets a screen
        // edge, so the path is inset by half the line width.
        let path = CGPath(roundedRect: rect.insetBy(dx: Metrics.borderWidth / 2, dy: Metrics.borderWidth / 2),
                          cornerWidth: Metrics.cornerRadius,
                          cornerHeight: Metrics.cornerRadius,
                          transform: nil)

        context.addPath(path)
        context.setFillColor(NSColor(white: 0.5, alpha: Metrics.fillAlpha).cgColor)
        context.fillPath()

        context.addPath(path)
        context.setStrokeColor(NSColor(white: 1.0, alpha: Metrics.borderAlpha).cgColor)
        context.setLineWidth(Metrics.borderWidth)
        context.strokePath()
    }
}

// MARK: - Controller

final class PreviewOverlayController {

    private var window: OverlayWindow?
    private var view: PreviewOverlayView?
    private var currentScreenFrame: CGRect?

    private func makeWindowIfNeeded() -> (OverlayWindow, PreviewOverlayView) {
        if let window, let view { return (window, view) }

        let view = PreviewOverlayView(frame: .zero)
        let window = OverlayWindow(level: .statusBar, contentView: view)
        self.window = window
        self.view = view
        return (window, view)
    }

    /// `rect` is in Cocoa screen coordinates; the overlay window spans `screen`
    /// and the rect is converted to window-local space.
    func show(rect: CGRect, on screen: NSScreen) {
        let (window, view) = makeWindowIfNeeded()
        let screenFrame = screen.frame

        if currentScreenFrame != screenFrame {
            window.setFrame(screenFrame, display: false)
            view.frame = NSRect(origin: .zero, size: screenFrame.size)
            currentScreenFrame = screenFrame
        }

        view.destinationRect = rect.offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY)

        if !window.isVisible {
            window.orderFrontRegardless()
        }
    }

    func hide() {
        window?.orderOut(nil)
        view?.destinationRect = nil
    }
}

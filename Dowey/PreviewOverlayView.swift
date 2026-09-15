//
//  PreviewOverlayView.swift
//  Dowey
//
//  Destination preview: a thin outline plus a flat tint at the rect the window
//  will land in. No screen capture, no blur, no image processing.
//
//  The view never rasterizes anything. Its backing layer holds the fill, border
//  and corner radius as properties, and the overlay *window* is sized to the
//  destination rect — so changing zones is a window frame change plus zero
//  drawing, rather than a redraw of a screen-sized view.
//

import AppKit
import QuartzCore

final class PreviewOverlayView: NSView {

    private enum Metrics {
        static let cornerRadius: CGFloat = 10
        static let borderWidth: CGFloat = 2
        static let fillAlpha: CGFloat = 0.82
        static let borderAlpha: CGFloat = 1.0
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .never

        let layer = self.layer ?? CALayer()
        layer.backgroundColor = NSColor(white: 0.5, alpha: Metrics.fillAlpha).cgColor
        layer.borderColor = NSColor(white: 1.0, alpha: Metrics.borderAlpha).cgColor
        layer.borderWidth = Metrics.borderWidth
        layer.cornerRadius = Metrics.cornerRadius
        layer.masksToBounds = true
        self.layer = layer
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isOpaque: Bool { false }
}

// MARK: - Controller

final class PreviewOverlayController {

    private var window: OverlayWindow?
    private var currentRect: CGRect?

    private func makeWindowIfNeeded() -> OverlayWindow {
        if let window { return window }
        let view = PreviewOverlayView(frame: .zero)
        let window = OverlayWindow(level: .statusBar, contentView: view)
        self.window = window
        return window
    }

    /// `rect` is in Cocoa screen coordinates and becomes the window's frame.
    func show(rect: CGRect) {
        let window = makeWindowIfNeeded()

        if currentRect != rect {
            // Without this, resizing the window implicitly animates the backing
            // layer, which would keep the compositor busy for ~0.25 s after
            // every zone change instead of settling immediately.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            window.setFrame(rect, display: false)
            CATransaction.commit()
            currentRect = rect
        }

        if !window.isVisible {
            window.orderFrontRegardless()
        }
    }

    func hide() {
        window?.orderOut(nil)
    }
}

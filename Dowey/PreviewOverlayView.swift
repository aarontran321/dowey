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
        static let borderWidth: CGFloat = 2
    }

    private var style: Style

    init(style: Style) {
        self.style = style
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        applyStyle()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func apply(_ style: Style) {
        guard style != self.style else { return }
        self.style = style
        applyStyle()
    }

    private func applyStyle() {
        guard let layer = self.layer else { return }

        // The tinted variant is deliberately not the raw accent color at full
        // strength — a half-screen rectangle of saturated color reads as an
        // error state. Desaturating toward gray keeps it a hint.
        let fill: NSColor = style.previewUsesTint
            ? style.tint.blended(withFraction: 0.45, of: NSColor(white: 0.5, alpha: 1)) ?? style.tint
            : NSColor(white: 0.5, alpha: 1)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.backgroundColor = fill.withAlphaComponent(style.previewOpacity).cgColor
        layer.borderColor = (style.previewUsesTint ? style.tint : NSColor.white).cgColor
        layer.borderWidth = Metrics.borderWidth
        layer.cornerRadius = style.previewCornerRadius
        layer.masksToBounds = true
        CATransaction.commit()
    }

    override var isOpaque: Bool { false }
}

// MARK: - Controller

final class PreviewOverlayController {

    private var window: OverlayWindow?
    private var view: PreviewOverlayView?
    private var currentRect: CGRect?

    private func makeWindowIfNeeded(_ style: Style) -> (OverlayWindow, PreviewOverlayView) {
        if let window, let view { return (window, view) }
        let view = PreviewOverlayView(style: style)
        let window = OverlayWindow(level: .statusBar, contentView: view)
        self.window = window
        self.view = view
        return (window, view)
    }

    /// `rect` is in Cocoa screen coordinates and becomes the window's frame.
    func show(rect: CGRect) {
        let style = Settings.shared.style
        guard style.showPreview else { return }

        let (window, view) = makeWindowIfNeeded(style)
        view.apply(style)

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

//
//  RadialHUDView.swift
//  Dowey
//
//  The radial ring shown around the gesture origin. Six stroked arc segments,
//  hollow center (the center *is* the maximize/deadzone target).
//

import AppKit
import CoreGraphics
import QuartzCore

/// Shared chrome for both overlays (ring + destination preview): borderless,
/// transparent, click-through, above normal windows, never activates Dowey.
final class OverlayWindow: NSWindow {

    init(level: NSWindow.Level, contentView: NSView) {
        super.init(contentRect: contentView.bounds,
                   styleMask: [.borderless],
                   backing: .buffered,
                   defer: true)

        self.level = level
        self.contentView = contentView
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        // Suppresses the window-server fade on order-in/order-out; the overlay
        // must appear and vanish on the exact frame the gesture changes.
        animationBehavior = .none
        // `.stationary` keeps the overlay from sliding during a Space swipe, and
        // `.fullScreenAuxiliary` lets it draw over a fullscreen app.
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
    }

    // Borderless windows already refuse key status; stated explicitly so the
    // menu-bar-only app can never be pulled into the foreground by an overlay.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - View

/// Seven `CAShapeLayer`s — six zone arcs plus the center maximize target —
/// whose paths are built once. Changing the highlighted zone assigns two colors
/// and two line widths; nothing is re-rasterized from a `draw(_:)` call.
final class RadialHUDView: NSView {

    private enum Metrics {
        static let ringRadius: CGFloat = 52
        static let strokeWidth: CGFloat = 5
        static let activeStrokeWidth: CGFloat = 7
        /// Angular padding trimmed off each end of a segment, in degrees.
        static let segmentGap: CGFloat = 4
        /// Room for the widest stroke plus antialiasing bleed.
        static let padding: CGFloat = 8

        static var side: CGFloat { (ringRadius + activeStrokeWidth / 2 + padding) * 2 }
    }

    static var preferredSize: NSSize { NSSize(width: Metrics.side, height: Metrics.side) }

    private var segmentLayers: [(zone: Zone, layer: CAShapeLayer)] = []
    private var centerLayer = CAShapeLayer()

    /// `nil` means the maximize target is selected: no segment lit, center lit.
    var activeZone: Zone? {
        didSet {
            guard oldValue != activeZone else { return }
            applyHighlight()
        }
    }

    override var isFlipped: Bool { false } // y-up, matching ZoneMath's angles
    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        buildLayers()
        applyHighlight()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func buildLayers() {
        guard let root = layer else { return }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)

        for zone in Zone.allCases {
            let arc = zone.arc
            let path = CGMutablePath()
            path.addArc(center: center,
                        radius: Metrics.ringRadius,
                        startAngle: (arc.start + Metrics.segmentGap) * .pi / 180,
                        endAngle: (arc.end - Metrics.segmentGap) * .pi / 180,
                        clockwise: false)

            let shape = CAShapeLayer()
            shape.path = path
            shape.fillColor = nil
            shape.lineCap = .round
            shape.frame = bounds
            root.addSublayer(shape)
            segmentLayers.append((zone, shape))
        }

        // Radius comes from ZoneMath so the circle the user aims at is exactly
        // the threshold the state machine tests.
        let r = ZoneMath.deadzoneRadius
        centerLayer.path = CGPath(ellipseIn: CGRect(x: center.x - r, y: center.y - r,
                                                    width: r * 2, height: r * 2),
                                  transform: nil)
        centerLayer.frame = bounds
        root.addSublayer(centerLayer)
    }

    private func applyHighlight() {
        // Implicit animations would fade every color change over ~0.25 s, which
        // both lags the highlight and keeps the compositor working after it.
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let dim = resolved(NSColor.white.withAlphaComponent(0.22))
        let accent = resolved(NSColor.controlAccentColor)

        for (zone, shape) in segmentLayers {
            let isActive = (zone == activeZone)
            shape.strokeColor = isActive ? accent : dim
            shape.lineWidth = isActive ? Metrics.activeStrokeWidth : Metrics.strokeWidth
        }

        let isMaximizeTargeted = (activeZone == nil)
        centerLayer.strokeColor = isMaximizeTargeted ? accent : dim
        centerLayer.lineWidth = isMaximizeTargeted ? Metrics.activeStrokeWidth : Metrics.strokeWidth
        centerLayer.fillColor = isMaximizeTargeted
            ? resolved(NSColor.controlAccentColor.withAlphaComponent(0.20))
            : nil

        CATransaction.commit()
    }

    /// Layers hold resolved colors, so dynamic colors such as `controlAccentColor`
    /// must be flattened against the current appearance rather than stored raw.
    private func resolved(_ color: NSColor) -> CGColor {
        var result = color.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance { result = color.cgColor }
        return result
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyHighlight()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 2
        for (_, shape) in segmentLayers { shape.contentsScale = scale }
        centerLayer.contentsScale = scale
    }
}

// MARK: - Controller

final class RadialHUDController {

    private var window: OverlayWindow?
    private var view: RadialHUDView?

    /// Built on first use so an app that has been idle since launch owns no
    /// window-server resources at all.
    private func makeWindowIfNeeded() -> (OverlayWindow, RadialHUDView) {
        if let window, let view { return (window, view) }

        let view = RadialHUDView(frame: NSRect(origin: .zero, size: RadialHUDView.preferredSize))
        let window = OverlayWindow(level: NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1),
                                   contentView: view)
        self.window = window
        self.view = view
        return (window, view)
    }

    /// Anchors the ring on the gesture origin — not on the live cursor — because
    /// the hollow center represents the deadzone, which is measured from origin.
    func show(at origin: CGPoint) {
        let (window, view) = makeWindowIfNeeded()
        view.activeZone = nil

        let size = RadialHUDView.preferredSize
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        window.setFrame(NSRect(x: origin.x - size.width / 2,
                               y: origin.y - size.height / 2,
                               width: size.width,
                               height: size.height),
                        display: false)
        CATransaction.commit()
        window.orderFrontRegardless()
    }

    func update(activeZone: Zone?) {
        view?.activeZone = activeZone
    }

    func hide() {
        window?.orderOut(nil)
        view?.activeZone = nil
    }
}

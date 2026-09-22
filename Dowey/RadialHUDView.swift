//
//  RadialHUDView.swift
//  Dowey
//
//  The radial ring shown around the gesture origin. Six stroked arc segments,
//  hollow center (the center *is* the maximize/deadzone target).
//
//  Every metric and color comes from an `Style` snapshot, so the same view
//  class draws the real HUD and the live preview inside the settings window.
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
        // `.stationary` keeps the overlay from sliding during a Space swipe,
        // `.fullScreenAuxiliary` lets it draw over a fullscreen app, and
        // `.transient` hides it in Mission Control so a gesture interrupted by
        // the Mission Control/Show-All-Windows swipe doesn't leave the ring
        // floating on top of the window thumbnails.
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary, .transient]
    }

    // Borderless windows already refuse key status; stated explicitly so the
    // menu-bar-only app can never be pulled into the foreground by an overlay.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - View

/// Seven `CAShapeLayer`s — six zone arcs plus the center maximize target —
/// whose paths are built once per style. Changing the highlighted zone
/// assigns two colors and two line widths; nothing is re-rasterized from a
/// `draw(_:)` call.
final class RadialHUDView: NSView {

    private enum Metrics {
        /// Angular padding trimmed off each end of a segment, in degrees.
        static let segmentGap: CGFloat = 4
        /// Room for the widest stroke plus antialiasing bleed.
        static let padding: CGFloat = 8
    }

    /// Side length the ring needs at this style — the window and the
    /// settings preview both size themselves from it.
    static func preferredSize(for style: Style) -> NSSize {
        let side = (style.ringRadius + style.activeRingThickness / 2 + Metrics.padding) * 2
        return NSSize(width: side, height: side)
    }

    private var style: Style
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

    init(style: Style) {
        self.style = style
        super.init(frame: NSRect(origin: .zero, size: RadialHUDView.preferredSize(for: style)))
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        rebuild()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Resizes to fit and redraws. Cheap enough (seven shape layers, no
    /// rasterization) to call on every tick of a slider drag.
    func apply(_ style: Style) {
        guard style != self.style else { return }
        self.style = style
        setFrameSize(RadialHUDView.preferredSize(for: style))
        rebuild()
    }

    private func rebuild() {
        layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
        segmentLayers.removeAll()
        centerLayer = CAShapeLayer()
        buildLayers()
        applyHighlight()
        viewDidChangeBackingProperties()
    }

    private func buildLayers() {
        guard let root = layer else { return }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)

        for zone in Zone.allCases {
            let arc = zone.arc
            let path = CGMutablePath()
            path.addArc(center: center,
                        radius: style.ringRadius,
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

        // Radius comes from the same number the state machine tests, so the
        // circle the user aims at is exactly the threshold.
        let r = style.triggerDistance
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
        let accent = resolved(style.tint)

        for (zone, shape) in segmentLayers {
            let isActive = (zone == activeZone)
            shape.strokeColor = isActive ? accent : dim
            shape.lineWidth = isActive ? style.activeRingThickness : style.ringThickness
        }

        let isMaximizeTargeted = (activeZone == nil)
        centerLayer.strokeColor = isMaximizeTargeted ? accent : dim
        centerLayer.lineWidth = isMaximizeTargeted ? style.activeRingThickness : style.ringThickness
        centerLayer.fillColor = isMaximizeTargeted
            ? resolved(style.tint.withAlphaComponent(0.20))
            : nil

        CATransaction.commit()
    }

    /// Layers hold resolved colors, so dynamic colors such as `controlAccentColor`
    /// must be flattened against the current style rather than stored raw.
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
    private func makeWindowIfNeeded(_ style: Style) -> (OverlayWindow, RadialHUDView) {
        if let window, let view { return (window, view) }

        let view = RadialHUDView(style: style)
        let window = OverlayWindow(level: NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1),
                                   contentView: view)
        self.window = window
        self.view = view
        return (window, view)
    }

    /// Anchors the ring on the gesture origin — not on the live cursor — because
    /// the hollow center represents the deadzone, which is measured from origin.
    ///
    /// The style is read here, once per gesture: a settings change mid-hold
    /// cannot resize the ring out from under the user.
    func show(at origin: CGPoint) {
        let style = Settings.shared.style
        guard style.showRing else { return }

        let (window, view) = makeWindowIfNeeded(style)
        view.apply(style)
        view.activeZone = nil

        let size = RadialHUDView.preferredSize(for: style)
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

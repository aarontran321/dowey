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

final class RadialHUDView: NSView {

    private enum Metrics {
        /// Room for the widest stroke, the glow, and antialiasing bleed.
        static let padding: CGFloat = 8
        /// Screen aspect used by the Screen Map design.
        static let mapAspect: CGFloat = 0.625
    }

    /// How far from the center the design actually paints. Drives the window
    /// size, so nothing is ever clipped by its own overlay.
    private static func outerReach(_ style: Style) -> CGFloat {
        switch style.design {
        case .segments, .wedges: return style.ringRadius + style.activeRingThickness / 2
        case .dots:              return style.ringRadius + style.detail * 1.7
        case .blade:             return style.ringRadius + 6 + style.detail / 2
        case .halo:              return style.ringRadius + style.activeRingThickness / 2 + style.detail
        case .map:               return style.ringRadius * 1.2
        }
    }

    static func preferredSize(for style: Style) -> NSSize {
        let side = (outerReach(style) + Metrics.padding) * 2
        return NSSize(width: side, height: side)
    }

    private var style: Style
    /// One layer per direction, in `Zone.allCases` order.
    private var zoneLayers: [(zone: Zone, layer: CAShapeLayer)] = []
    /// The maximize target: the center circle, or the whole screen on Screen Map.
    private var centerLayer = CAShapeLayer()
    /// Decoration that never changes with the selection — Halo's hairline
    /// circle, Screen Map's outline.
    private var chromeLayers: [CAShapeLayer] = []

    /// `nil` means the maximize target is selected: no direction lit, center lit.
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

    /// Resizes to fit and redraws. Cheap enough — a handful of shape layers, no
    /// rasterization — to call on every tick of a slider drag.
    func apply(_ style: Style) {
        guard style != self.style else { return }
        self.style = style
        setFrameSize(RadialHUDView.preferredSize(for: style))
        rebuild()
    }

    private func rebuild() {
        layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
        zoneLayers.removeAll()
        chromeLayers.removeAll()
        centerLayer = CAShapeLayer()
        buildLayers()
        applyHighlight()
        viewDidChangeBackingProperties()
    }

    // MARK: - Geometry

    private var center: CGPoint { CGPoint(x: bounds.midX, y: bounds.midY) }

    /// Screen Map's miniature display, in the same y-up space as `Zone.rect`.
    private var mapScreen: CGRect {
        let w = style.ringRadius * 2.4
        let h = w * Metrics.mapAspect
        return CGRect(x: center.x - w / 2, y: center.y - h / 2, width: w, height: h)
    }

    private func point(atAngle degrees: CGFloat, radius: CGFloat) -> CGPoint {
        let a = degrees * .pi / 180
        return CGPoint(x: center.x + cos(a) * radius, y: center.y + sin(a) * radius)
    }

    private func midAngle(of zone: Zone) -> CGFloat {
        let arc = zone.arc
        return (arc.start + arc.end) / 2
    }

    private func newLayer(into list: inout [CAShapeLayer]) -> CAShapeLayer {
        let shape = CAShapeLayer()
        shape.frame = bounds
        shape.fillColor = nil
        layer?.addSublayer(shape)
        list.append(shape)
        return shape
    }

    // MARK: - Build

    private func buildLayers() {
        guard layer != nil else { return }

        switch style.design {
        case .segments: buildArcs(gap: style.detail, cap: .round)
        case .halo:     buildHalo()
        case .wedges:   buildWedges()
        case .dots:     buildDots()
        case .blade:    buildBlades()
        case .map:      buildMap()
        }

        buildCenterTarget()
    }

    /// Shared by Segments and Halo: one stroked arc per zone.
    private func buildArcs(gap: CGFloat, cap: CAShapeLayerLineCap) {
        for zone in Zone.allCases {
            let arc = zone.arc
            let path = CGMutablePath()
            path.addArc(center: center,
                        radius: style.ringRadius,
                        startAngle: (arc.start + gap) * .pi / 180,
                        endAngle: (arc.end - gap) * .pi / 180,
                        clockwise: false)

            let shape = CAShapeLayer()
            shape.path = path
            shape.fillColor = nil
            shape.lineCap = cap
            shape.frame = bounds
            layer?.addSublayer(shape)
            zoneLayers.append((zone, shape))
        }
    }

    private func buildHalo() {
        // The hairline circle is the whole idle state — the arcs only appear
        // once a direction is live.
        let ring = newLayer(into: &chromeLayers)
        ring.path = CGPath(ellipseIn: CGRect(x: center.x - style.ringRadius,
                                             y: center.y - style.ringRadius,
                                             width: style.ringRadius * 2,
                                             height: style.ringRadius * 2), transform: nil)
        ring.lineWidth = max(1, style.ringThickness * 0.32)
        buildArcs(gap: 3, cap: .round)
    }

    private func buildWedges() {
        let inner = style.triggerDistance + 8
        for zone in Zone.allCases {
            let arc = zone.arc
            let path = CGMutablePath()
            path.addArc(center: center, radius: style.ringRadius,
                        startAngle: (arc.start + 2) * .pi / 180,
                        endAngle: (arc.end - 2) * .pi / 180, clockwise: false)
            path.addArc(center: center, radius: inner,
                        startAngle: (arc.end - 2) * .pi / 180,
                        endAngle: (arc.start + 2) * .pi / 180, clockwise: true)
            path.closeSubpath()

            let shape = CAShapeLayer()
            shape.path = path
            shape.frame = bounds
            layer?.addSublayer(shape)
            zoneLayers.append((zone, shape))
        }
    }

    private func buildDots() {
        for zone in Zone.allCases {
            let shape = CAShapeLayer()
            shape.frame = bounds
            shape.strokeColor = nil
            layer?.addSublayer(shape)
            zoneLayers.append((zone, shape))
        }
        // Paths are assigned in applyHighlight, where the live dot grows.
    }

    private func buildBlades() {
        for zone in Zone.allCases {
            let angle = midAngle(of: zone)
            let path = CGMutablePath()
            path.move(to: point(atAngle: angle, radius: style.triggerDistance + 12))
            path.addLine(to: point(atAngle: angle, radius: style.ringRadius + 6))

            let shape = CAShapeLayer()
            shape.path = path
            shape.fillColor = nil
            shape.lineCap = .round
            shape.lineWidth = style.detail
            shape.frame = bounds
            layer?.addSublayer(shape)
            zoneLayers.append((zone, shape))
        }
    }

    private func buildMap() {
        let screen = mapScreen
        let outline = newLayer(into: &chromeLayers)
        outline.path = CGPath(roundedRect: screen, cornerWidth: style.detail,
                              cornerHeight: style.detail, transform: nil)
        outline.lineWidth = max(1, style.ringThickness * 0.4)

        let tileRadius = max(0, style.detail * 0.6)
        for zone in Zone.allCases {
            let shape = CAShapeLayer()
            shape.path = CGPath(roundedRect: zone.rect(in: screen).insetBy(dx: 1.5, dy: 1.5),
                                cornerWidth: tileRadius, cornerHeight: tileRadius, transform: nil)
            shape.strokeColor = nil
            shape.frame = bounds
            layer?.addSublayer(shape)
            zoneLayers.append((zone, shape))
        }
    }

    private func buildCenterTarget() {
        if style.design == .map {
            // Releasing inside the trigger distance maximizes, so the map's
            // maximize target is the whole screen.
            let screen = mapScreen
            centerLayer.path = CGPath(roundedRect: screen.insetBy(dx: 1.5, dy: 1.5),
                                      cornerWidth: max(0, style.detail * 0.6),
                                      cornerHeight: max(0, style.detail * 0.6), transform: nil)
            centerLayer.strokeColor = nil
        } else {
            // Radius comes from the same number the state machine tests, so the
            // circle the user aims at is exactly the threshold.
            let r = style.triggerDistance
            centerLayer.path = CGPath(ellipseIn: CGRect(x: center.x - r, y: center.y - r,
                                                        width: r * 2, height: r * 2), transform: nil)
        }
        centerLayer.frame = bounds
        layer?.addSublayer(centerLayer)
    }

    // MARK: - Highlight

    private func applyHighlight() {
        // Implicit animations would fade every color change over ~0.25 s, which
        // both lags the highlight and keeps the compositor working after it.
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let dim = resolved(NSColor.white.withAlphaComponent(0.22))
        let accent = resolved(style.tint)
        let isMaximizeTargeted = (activeZone == nil)

        for layer in chromeLayers {
            layer.fillColor = nil
            layer.strokeColor = resolved(NSColor.white.withAlphaComponent(style.design == .map ? 0.35 : 0.18))
        }

        for (zone, shape) in zoneLayers {
            let on = (zone == activeZone)
            shape.isHidden = false
            shape.shadowOpacity = 0

            switch style.design {
            case .segments:
                shape.strokeColor = on ? accent : dim
                shape.lineWidth = on ? style.activeRingThickness : style.ringThickness

            case .halo:
                // Only the live arc is drawn; the hairline circle carries the rest.
                shape.isHidden = !on
                shape.strokeColor = accent
                shape.lineWidth = style.activeRingThickness
                shape.shadowColor = accent
                shape.shadowRadius = style.detail
                shape.shadowOffset = .zero
                shape.shadowOpacity = style.detail > 0 ? 0.9 : 0
                shape.shadowPath = shape.path

            case .wedges:
                shape.fillColor = on
                    ? resolved(style.tint.withAlphaComponent(style.detail))
                    : resolved(NSColor.white.withAlphaComponent(0.09))
                shape.strokeColor = on ? accent : resolved(NSColor.white.withAlphaComponent(0.16))
                shape.lineWidth = on ? 1.5 : 1

            case .dots:
                let r = on ? style.detail * 1.7 : style.detail
                let p = point(atAngle: midAngle(of: zone), radius: style.ringRadius)
                shape.path = CGPath(ellipseIn: CGRect(x: p.x - r, y: p.y - r,
                                                      width: r * 2, height: r * 2), transform: nil)
                shape.fillColor = on ? accent : dim

            case .blade:
                shape.isHidden = !on
                shape.strokeColor = accent
                shape.lineWidth = style.detail

            case .map:
                shape.isHidden = !on
                shape.fillColor = resolved(style.tint.withAlphaComponent(0.55))
            }
        }

        if style.design == .map {
            centerLayer.isHidden = !isMaximizeTargeted
            centerLayer.fillColor = resolved(style.tint.withAlphaComponent(0.55))
        } else {
            centerLayer.isHidden = false
            centerLayer.strokeColor = isMaximizeTargeted ? accent : dim
            centerLayer.lineWidth = isMaximizeTargeted ? style.activeRingThickness : style.ringThickness
            centerLayer.fillColor = isMaximizeTargeted
                ? resolved(style.tint.withAlphaComponent(0.20))
                : nil
        }

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
        for (_, shape) in zoneLayers { shape.contentsScale = scale }
        for shape in chromeLayers { shape.contentsScale = scale }
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

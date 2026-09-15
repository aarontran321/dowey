//
//  RadialHUDView.swift
//  Dowey
//
//  The radial ring shown around the gesture origin. Six stroked arc segments,
//  hollow center (the center *is* the maximize/deadzone target).
//

import AppKit
import CoreGraphics

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

    /// `nil` means Armed-but-neutral: the ring is on screen with no zone lit.
    var activeZone: Zone? {
        didSet {
            guard oldValue != activeZone else { return }
            needsDisplay = true
        }
    }

    override var isFlipped: Bool { false } // y-up, matching ZoneMath's angles

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let dim = NSColor.white.withAlphaComponent(0.22)
        let accent = NSColor.controlAccentColor

        context.setLineCap(.round)

        for zone in Zone.allCases {
            let isActive = (zone == activeZone)
            let arc = zone.arc
            let start = (arc.start + Metrics.segmentGap) * .pi / 180
            let end = (arc.end - Metrics.segmentGap) * .pi / 180

            context.beginPath()
            context.addArc(center: center,
                           radius: Metrics.ringRadius,
                           startAngle: start,
                           endAngle: end,
                           clockwise: false)
            context.setStrokeColor((isActive ? accent : dim).cgColor)
            context.setLineWidth(isActive ? Metrics.activeStrokeWidth : Metrics.strokeWidth)
            context.strokePath()
        }
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
        window.setFrame(NSRect(x: origin.x - size.width / 2,
                               y: origin.y - size.height / 2,
                               width: size.width,
                               height: size.height),
                        display: false)
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

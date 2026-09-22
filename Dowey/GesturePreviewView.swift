//
//  GesturePreviewView.swift
//  Dowey
//
//  The live preview at the top of the settings window: a miniature desktop with
//  the real ring drawn over it at actual size.
//
//  It is not a mock-up. The ring is a `RadialHUDView`, the destination tile is a
//  `PreviewOverlayView`, and the direction under the pointer is resolved by
//  `ZoneMath` — the same three pieces the gesture itself uses. Anything that
//  looks right here looks right on screen.
//

import AppKit
import QuartzCore

final class GesturePreviewView: NSView {

    private enum Metrics {
        static let stageInset: CGFloat = 0
        static let stageCornerRadius: CGFloat = 12
        /// Height of the fake menu bar, as a fraction of the stage. The tiles
        /// are laid out below it, exactly as `visibleFrame` excludes the real one.
        static let menuBarFraction: CGFloat = 0.075
    }

    private let stage = NSView()
    private let wallpaper = CAGradientLayer()
    private let menuBar = CALayer()
    /// Two stand-in app windows. They exist so the destination tile has
    /// something to cover: without them, "Opacity" would have no visible effect.
    private let stubWindows = [CALayer(), CALayer()]
    private var destination: PreviewOverlayView
    private var hud: RadialHUDView

    private var style: Style
    private var activeZone: Zone?
    private var isPointerInside = false
    private var trackingArea: NSTrackingArea?

    /// Height the preview needs so that no design, at any setting, is clipped
    /// by the stage. Derived from the ranges themselves, so widening a slider
    /// cannot quietly start cropping the ring.
    static var preferredHeight: CGFloat {
        var tallest: CGFloat = 0
        for design in RingDesign.allCases {
            var extreme = Style.default
            extreme.design = design
            extreme.ringRadius = CGFloat(Settings.Range.ringRadius.upperBound)
            extreme.ringThickness = CGFloat(Settings.Range.ringThickness.upperBound)
            extreme.detail = CGFloat(design.detail.range.upperBound)
            tallest = max(tallest, RadialHUDView.preferredSize(for: extreme).height)
        }
        return tallest + 12
    }

    init(style: Style) {
        self.style = style
        self.destination = PreviewOverlayView(style: style)
        self.hud = RadialHUDView(style: style)
        super.init(frame: .zero)

        wantsLayer = true

        stage.wantsLayer = true
        stage.layer?.cornerRadius = Metrics.stageCornerRadius
        stage.layer?.masksToBounds = true
        stage.layer?.addSublayer(wallpaper)
        for stub in stubWindows {
            stub.cornerRadius = 5
            stub.borderWidth = 1
            stage.layer?.addSublayer(stub)
        }
        stage.layer?.addSublayer(menuBar)
        addSubview(stage)

        stage.addSubview(destination)
        stage.addSubview(hud)

        applyStageColors()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { false } // y-up, matching ZoneMath's angles

    // MARK: - Style

    func apply(_ style: Style) {
        self.style = style
        hud.apply(style)
        destination.apply(style)
        // A ring that just changed size has a new frame, and the tile it points
        // at may have changed with the trigger distance.
        needsLayout = true
        layoutSubtreeIfNeeded()
        updateDestination()
    }

    private func applyStageColors() {
        guard stage.layer != nil else { return }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let isDark = self.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            // Deliberately mid-dark in both themes: the ring's unlit segments are
            // white at 22%, so a pale desktop here would hide them.
            let top = isDark ? NSColor(srgbRed: 0.23, green: 0.24, blue: 0.27, alpha: 1)
                             : NSColor(srgbRed: 0.53, green: 0.55, blue: 0.59, alpha: 1)
            let bottom = isDark ? NSColor(srgbRed: 0.16, green: 0.17, blue: 0.19, alpha: 1)
                                : NSColor(srgbRed: 0.41, green: 0.43, blue: 0.47, alpha: 1)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.wallpaper.colors = [top.cgColor, bottom.cgColor]
            self.wallpaper.startPoint = CGPoint(x: 0.5, y: 1)
            self.wallpaper.endPoint = CGPoint(x: 0.5, y: 0)
            self.menuBar.backgroundColor = NSColor.white.withAlphaComponent(isDark ? 0.10 : 0.28).cgColor
            for stub in self.stubWindows {
                stub.backgroundColor = NSColor.white.withAlphaComponent(isDark ? 0.14 : 0.22).cgColor
                stub.borderColor = NSColor.white.withAlphaComponent(isDark ? 0.18 : 0.30).cgColor
            }
            CATransaction.commit()
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyStageColors()
    }

    // MARK: - Layout

    override func layout() {
        super.layout()

        stage.frame = bounds.insetBy(dx: Metrics.stageInset, dy: Metrics.stageInset)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        wallpaper.frame = stage.bounds
        let barHeight = (stage.bounds.height * Metrics.menuBarFraction).rounded()
        menuBar.frame = CGRect(x: 0, y: stage.bounds.maxY - barHeight,
                               width: stage.bounds.width, height: barHeight)
        CATransaction.commit()

        // Offset from each other so the stack reads as two overlapping windows.
        let bar = (stage.bounds.height * Metrics.menuBarFraction).rounded()
        let field = stage.bounds.insetBy(dx: stage.bounds.width * 0.1, dy: stage.bounds.height * 0.14)
        let stubSize = CGSize(width: field.width * 0.52, height: field.height * 0.66)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        stubWindows[0].frame = CGRect(x: field.minX, y: field.maxY - stubSize.height - bar,
                                      width: stubSize.width, height: stubSize.height)
        stubWindows[1].frame = CGRect(x: field.maxX - stubSize.width, y: field.minY,
                                      width: stubSize.width, height: stubSize.height)
        CATransaction.commit()

        let size = RadialHUDView.preferredSize(for: style)
        hud.frame = NSRect(x: (stage.bounds.width - size.width) / 2,
                           y: (stage.bounds.height - size.height) / 2,
                           width: size.width, height: size.height)

        updateDestination()
    }

    /// The stage minus its menu bar — the preview's stand-in for `visibleFrame`.
    private var visibleFrame: CGRect {
        let barHeight = (stage.bounds.height * Metrics.menuBarFraction).rounded()
        return CGRect(x: 0, y: 0, width: stage.bounds.width, height: stage.bounds.height - barHeight)
    }

    private func updateDestination() {
        let target: SnapTarget = activeZone.map { .zone($0) } ?? .maximize
        let rect = target.rect(in: visibleFrame)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        destination.frame = rect
        destination.isHidden = !style.showPreview
        hud.isHidden = !style.showRing
        CATransaction.commit()
    }

    // MARK: - Pointer

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                                  owner: self,
                                  userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isPointerInside = true
        mouseMoved(with: event) // entering already tells us a direction
    }

    override func mouseExited(with event: NSEvent) {
        isPointerInside = false
        setActiveZone(nil)
    }

    /// Same two decisions the state machine makes, against the same helpers:
    /// inside the trigger distance means maximize, outside means a direction.
    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let origin = CGPoint(x: stage.frame.midX, y: stage.frame.midY)

        if ZoneMath.isInsideDeadzone(origin: origin, point: point) {
            setActiveZone(nil)
        } else {
            setActiveZone(Zone.forDirection(origin: origin, point: point))
        }
    }

    private func setActiveZone(_ zone: Zone?) {
        guard zone != activeZone else { return }
        activeZone = zone
        hud.activeZone = zone
        updateDestination()
    }
}

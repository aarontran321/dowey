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
    /// `style` is the gesture's snapshot, taken once at key-down.
    func show(rect: CGRect, style: Style) {
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

// MARK: - Keyboard mode

/// What the keyboard is doing while Globe is held, shown on the window it is
/// doing it to.
///
/// `pick` (🌐 + ⌥ held): choosing which window. `move` (🌐 alone): the chosen
/// window will snap with the arrows. Each gets its own color and a label in
/// the window's middle, so the two can never be mistaken for each other.
enum KeyboardMode {
    case pick, move

    var title: String {
        switch self {
        case .pick: return "Pick"
        case .move: return "Move"
        }
    }

    var hint: String {
        switch self {
        case .pick: return "⌥ + arrows to choose · let go of ⌥ to move it"
        case .move: return "arrows to snap · two for a corner"
        }
    }

    var symbolName: String {
        switch self {
        case .pick: return "macwindow.on.rectangle"
        case .move: return "arrow.up.and.down.and.arrow.left.and.right"
        }
    }

    /// Move wears the ring color, so it reads as the same thing as the
    /// gesture. Pick wears orange — or teal when the ring color is itself warm
    /// enough to be confused with orange.
    func color(tint: NSColor) -> NSColor {
        switch self {
        case .move:
            return tint
        case .pick:
            let rgb = tint.usingColorSpace(.deviceRGB) ?? tint
            let warm = rgb.saturationComponent > 0.25
                && (rgb.hueComponent < 0.19 || rgb.hueComponent > 0.9)
            return warm ? .systemTeal : .systemOrange
        }
    }
}

final class KeyboardModeView: NSView {

    private let pill = NSView()
    private let icon = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let hintLabel = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.borderWidth = 5

        pill.wantsLayer = true
        pill.layer?.cornerRadius = 14
        pill.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.78).cgColor
        pill.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pill)

        icon.symbolConfiguration = .init(pointSize: 20, weight: .semibold)
        titleLabel.font = .systemFont(ofSize: 20, weight: .bold)
        hintLabel.font = .systemFont(ofSize: 12, weight: .medium)
        hintLabel.textColor = NSColor.white.withAlphaComponent(0.82)

        let heading = NSStackView(views: [icon, titleLabel])
        heading.spacing = 8
        let stack = NSStackView(views: [heading, hintLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(stack)

        NSLayoutConstraint.activate([
            pill.centerXAnchor.constraint(equalTo: centerXAnchor),
            pill.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: pill.topAnchor, constant: 11),
            stack.bottomAnchor.constraint(equalTo: pill.bottomAnchor, constant: -11),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func apply(_ mode: KeyboardMode, color: NSColor) {
        layer?.borderColor = color.cgColor
        layer?.backgroundColor = color.withAlphaComponent(0.14).cgColor
        icon.image = NSImage(systemSymbolName: mode.symbolName, accessibilityDescription: nil)
        icon.contentTintColor = color
        titleLabel.stringValue = mode.title
        titleLabel.textColor = color
        hintLabel.stringValue = mode.hint
    }
}

/// Draws `KeyboardModeView` over a window's frame. Built on first use, like
/// the other overlays, so a Dowey that never sees ⌥ owns no window for it.
final class KeyboardModeOverlay {

    private var window: OverlayWindow?
    private var view: KeyboardModeView?
    private var hideTimer: Timer?
    /// Set while a fade-out runs, so a show that lands mid-fade wins.
    private var fadingOut = false

    /// `frame` is in Cocoa screen space. With `briefly`, the overlay fades
    /// on its own: the case where Globe was already let go by the time the
    /// window landed, so nothing else will take it down.
    func show(_ mode: KeyboardMode, on frame: CGRect, color: NSColor, briefly: Bool = false) {
        hideTimer?.invalidate()
        hideTimer = nil
        fadingOut = false

        let view = self.view ?? KeyboardModeView(frame: CGRect(origin: .zero, size: frame.size))
        let window = self.window ?? OverlayWindow(level: .statusBar, contentView: view)
        self.view = view
        self.window = window

        view.apply(mode, color: color)
        if window.isVisible, window.frame != frame {
            // Follows the window to where it snapped rather than jumping.
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.14
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().setFrame(frame, display: true)
            }
        } else {
            window.setFrame(frame, display: true)
        }
        window.alphaValue = 1
        if !window.isVisible { window.orderFrontRegardless() }

        if briefly {
            let timer = Timer(timeInterval: 0.6, repeats: false) { [weak self] _ in self?.hide() }
            timer.tolerance = 0.1
            RunLoop.main.add(timer, forMode: .common)
            hideTimer = timer
        }
    }

    func hide() {
        hideTimer?.invalidate()
        hideTimer = nil
        guard let window, window.isVisible, !fadingOut else { return }
        fadingOut = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, self.fadingOut else { return }
            self.fadingOut = false
            window.orderOut(nil)
            window.alphaValue = 1
        })
    }
}

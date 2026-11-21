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
/// `pick` (🌐 + ⌘ held): choosing which window. `move` (🌐 alone): the chosen
/// window will snap with the arrows. Told apart by line, not by color — a
/// dashed outline is the familiar "selecting" mark, a solid one is the window
/// you have — and by a small frosted label that names the mode.
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
        case .pick: return "⌘ arrows choose"
        case .move: return "arrows snap"
        }
    }

    var symbolName: String {
        switch self {
        case .pick: return "macwindow.on.rectangle"
        case .move: return "arrow.up.and.down.and.arrow.left.and.right"
        }
    }

    var isDashed: Bool { self == .pick }
}

final class KeyboardModeView: NSView {

    private enum Metrics {
        static let cornerRadius: CGFloat = 12
        static let inset: CGFloat = 2.5
    }

    /// A soft dark edge under a thin light line, so the outline reads on a
    /// white document and a dark one alike without any color of its own.
    private let halo = CAShapeLayer()
    private let line = CAShapeLayer()

    private let label = NSVisualEffectView()
    private let icon = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let hintLabel = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        for (shape, color, width) in [(halo, NSColor.black.withAlphaComponent(0.28), CGFloat(4)),
                                      (line, NSColor.white.withAlphaComponent(0.92), CGFloat(1.5))] {
            shape.fillColor = nil
            shape.strokeColor = color.cgColor
            shape.lineWidth = width
            shape.lineCap = .round
            layer?.addSublayer(shape)
        }

        // The system HUD look: dark frosted glass, white type.
        label.material = .hudWindow
        label.blendingMode = .behindWindow
        label.state = .active
        label.appearance = NSAppearance(named: .vibrantDark)
        label.wantsLayer = true
        label.layer?.cornerRadius = 10
        label.layer?.masksToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        icon.symbolConfiguration = .init(pointSize: 13, weight: .medium)
        icon.contentTintColor = .white
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = .white
        hintLabel.font = .systemFont(ofSize: 12)
        hintLabel.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [icon, titleLabel, hintLabel])
        stack.spacing = 7
        stack.setCustomSpacing(10, after: titleLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        label.addSubview(stack)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: label.leadingAnchor, constant: 13),
            stack.trailingAnchor.constraint(equalTo: label.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: label.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: label.bottomAnchor, constant: -8),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func layout() {
        super.layout()
        let rect = bounds.insetBy(dx: Metrics.inset, dy: Metrics.inset)
        let path = CGPath(roundedRect: rect, cornerWidth: Metrics.cornerRadius,
                          cornerHeight: Metrics.cornerRadius, transform: nil)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        halo.path = path
        line.path = path
        CATransaction.commit()
    }

    func apply(_ mode: KeyboardMode) {
        let dash: [NSNumber]? = mode.isDashed ? [7, 5] : nil
        halo.lineDashPattern = dash
        line.lineDashPattern = dash
        icon.image = NSImage(systemSymbolName: mode.symbolName, accessibilityDescription: nil)
        titleLabel.stringValue = mode.title
        hintLabel.stringValue = mode.hint
    }
}

/// Draws `KeyboardModeView` over a window's frame. Built on first use, like
/// the other overlays, so a Dowey that never sees ⌘ owns no window for it.
final class KeyboardModeOverlay {

    private var window: OverlayWindow?
    private var view: KeyboardModeView?
    private var hideTimer: Timer?
    /// Set while a fade-out runs, so a show that lands mid-fade wins.
    private var fadingOut = false

    /// `frame` is in Cocoa screen space. With `briefly`, the overlay fades
    /// on its own: the case where Globe was already let go by the time the
    /// window landed, so nothing else will take it down.
    func show(_ mode: KeyboardMode, on frame: CGRect, briefly: Bool = false) {
        hideTimer?.invalidate()
        hideTimer = nil
        fadingOut = false

        let view = self.view ?? KeyboardModeView(frame: CGRect(origin: .zero, size: frame.size))
        let window = self.window ?? OverlayWindow(level: .statusBar, contentView: view)
        self.view = view
        self.window = window

        view.apply(mode)
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

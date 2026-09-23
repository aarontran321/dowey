//
//  Settings.swift
//  Dowey
//
//  One store, one source of truth. Everything the user can customize lives
//  here and is written to UserDefaults the moment it changes.
//
//  There is no "Apply" or "Save" anywhere in Dowey by design — the setter is the
//  commit. The settings window observes the store directly; the overlays read a
//  snapshot of it when a gesture begins, which is the only moment they can act
//  on one.
//

import AppKit
import Combine
import ServiceManagement

// MARK: - Snapshot

/// An immutable read of the store, in the units AppKit wants. The overlays take
/// one of these instead of the store itself so nothing in the drawing code has
/// to know about UserDefaults, SwiftUI or Combine.
struct Style: Equatable {
    var design: RingDesign
    /// The value of the one slider that is unique to `design` — segment gap,
    /// dot size, glow radius and so on. One number, because a design that needs
    /// two dials to look right is a design that has not been decided yet.
    var detail: CGFloat
    var tint: NSColor
    var ringRadius: CGFloat
    var ringThickness: CGFloat
    var showRing: Bool
    var showPreview: Bool
    var previewOpacity: CGFloat
    var previewCornerRadius: CGFloat
    var previewUsesTint: Bool
    var triggerDistance: CGFloat

    static let `default` = Style(design: .segments,
                                 detail: RingDesign.segments.detail.value,
                                 tint: .controlAccentColor,
                                      ringRadius: 52,
                                      ringThickness: 5,
                                      showRing: true,
                                      showPreview: true,
                                      previewOpacity: 0.82,
                                      previewCornerRadius: 10,
                                      previewUsesTint: false,
                                      triggerDistance: ZoneMath.defaultDeadzoneRadius)

    /// Stroke width of a lit segment. Derived rather than stored so the two
    /// widths can never drift apart.
    var activeRingThickness: CGFloat { ringThickness + 2 }

    /// A scaled-down copy for the design gallery's thumbnails. Lengths shrink
    /// with the radius; angles and opacities do not, because they are not
    /// lengths.
    func miniature(radius: CGFloat = 22) -> Style {
        let factor = radius / ringRadius
        var mini = self
        mini.ringRadius = radius
        mini.ringThickness = max(1.5, ringThickness * factor)
        mini.triggerDistance = max(5, triggerDistance * factor)
        switch design {
        case .dots, .blade, .map, .halo: mini.detail = max(1, detail * factor)
        case .segments, .wedges:         break
        }
        return mini
    }
}

// MARK: - Ring design

/// How the ring draws itself. Every design answers the same two questions —
/// which of the eight directions is live, and is the maximize target selected —
/// and each one carries a single parameter of its own.
enum RingDesign: String, CaseIterable, Identifiable {
    case segments, wedges, dots, blade, map, halo

    var id: String { rawValue }

    var name: String {
        switch self {
        case .segments: return "Segments"
        case .wedges:   return "Wedges"
        case .dots:     return "Dots"
        case .blade:    return "Blade"
        case .map:      return "Screen Map"
        case .halo:     return "Halo"
        }
    }

    var summary: String {
        switch self {
        case .segments: return "Eight arcs around the cursor. The one you are pointing at lights up and thickens."
        case .wedges:   return "Filled slices instead of strokes — the zones read as areas, not hints."
        case .dots:     return "A dot per direction. The live one swells and fills. The quietest design."
        case .blade:    return "Nothing but the center target until you commit, then one bar points the way."
        case .map:      return "A miniature screen at the cursor with the destination tile lit."
        case .halo:     return "A hairline circle; the live arc glows."
        }
    }

    /// The design's own slider: what to call it, its bounds, and its default.
    var detail: (label: String, range: ClosedRange<Double>, value: Double) {
        switch self {
        case .segments: return ("Segment gap", 0...12, 4)
        case .wedges:   return ("Fill", 0.15...0.7, 0.42)
        case .dots:     return ("Dot size", 3...12, 5)
        case .blade:    return ("Width", 6...20, 11)
        case .map:      return ("Map corners", 0...16, 7)
        case .halo:     return ("Glow", 0...18, 14)
        }
    }
}

// MARK: - Tint

/// The swatch row, in the order macOS uses in Style settings. `system`
/// tracks whatever accent color the user has picked system-wide.
enum Tint: String, CaseIterable, Identifiable {
    case system, blue, purple, pink, red, orange, yellow, green, graphite

    var id: String { rawValue }

    var color: NSColor {
        switch self {
        case .system:   return .controlAccentColor
        case .blue:     return .systemBlue
        case .purple:   return .systemPurple
        case .pink:     return .systemPink
        case .red:      return .systemRed
        case .orange:   return .systemOrange
        case .yellow:   return .systemYellow
        case .green:    return .systemGreen
        case .graphite: return NSColor(srgbRed: 0.55, green: 0.56, blue: 0.58, alpha: 1)
        }
    }

    var name: String {
        switch self {
        case .system:   return "Accent Color"
        case .graphite: return "Graphite"
        default:        return rawValue.capitalized
        }
    }
}

// MARK: - Store

final class Settings: ObservableObject {

    static let shared = Settings()

    private let defaults: UserDefaults

    private enum Key {
        static let design = "ringDesign"
        /// Per-design detail values, keyed by `RingDesign.rawValue`, so switching
        /// designs and switching back remembers how each one was tuned.
        static let details = "ringDetails"
        static let tint = "tint"
        static let ringRadius = "ringRadius"
        static let ringThickness = "ringThickness"
        static let showRing = "showRing"
        static let showPreview = "showPreview"
        static let previewOpacity = "previewOpacity"
        static let previewCornerRadius = "previewCornerRadius"
        static let previewUsesTint = "previewUsesTint"
        static let triggerDistance = "triggerDistance"
    }

    /// Slider bounds, kept next to the store so the settings window and any
    /// clamping on load read the same numbers.
    enum Range {
        static let ringRadius: ClosedRange<Double> = 32...84
        static let ringThickness: ClosedRange<Double> = 2...10
        static let previewOpacity: ClosedRange<Double> = 0.1...1
        static let previewCornerRadius: ClosedRange<Double> = 0...28
        static let triggerDistance: ClosedRange<Double> = 8...48
    }

    // MARK: Stored settings

    @Published var design: RingDesign { didSet { commit(design.rawValue, Key.design) } }

    private var details: [String: Double] { didSet { commit(details, Key.details) } }

    /// The selected design's own parameter. Reading falls back to that design's
    /// default, so a design that has never been touched still looks right.
    var detail: Double {
        get { details[design.rawValue] ?? design.detail.value }
        set {
            objectWillChange.send()
            details[design.rawValue] = min(max(newValue, design.detail.range.lowerBound),
                                           design.detail.range.upperBound)
        }
    }

    /// Either a `Tint` raw value or an `#RRGGBB` string from the custom well.
    @Published var tint: String { didSet { commit(tint, Key.tint) } }

    @Published var ringRadius: Double { didSet { commit(ringRadius, Key.ringRadius) } }
    @Published var ringThickness: Double { didSet { commit(ringThickness, Key.ringThickness) } }
    @Published var showRing: Bool { didSet { commit(showRing, Key.showRing) } }
    @Published var showPreview: Bool { didSet { commit(showPreview, Key.showPreview) } }
    @Published var previewOpacity: Double { didSet { commit(previewOpacity, Key.previewOpacity) } }
    @Published var previewCornerRadius: Double { didSet { commit(previewCornerRadius, Key.previewCornerRadius) } }
    @Published var previewUsesTint: Bool { didSet { commit(previewUsesTint, Key.previewUsesTint) } }

    @Published var triggerDistance: Double {
        didSet {
            // The gesture state machine reads the threshold straight from
            // ZoneMath, so the store pushes it there rather than having the
            // pure-geometry layer reach back into UserDefaults.
            ZoneMath.deadzoneRadius = CGFloat(triggerDistance)
            commit(triggerDistance, Key.triggerDistance)
        }
    }

    // MARK: Init

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let d = Style.default
        design = RingDesign(rawValue: defaults.string(forKey: Key.design) ?? "") ?? d.design
        details = defaults.dictionary(forKey: Key.details) as? [String: Double] ?? [:]
        tint = defaults.string(forKey: Key.tint) ?? Tint.system.rawValue
        ringRadius = Settings.read(defaults, Key.ringRadius, Double(d.ringRadius), Range.ringRadius)
        ringThickness = Settings.read(defaults, Key.ringThickness, Double(d.ringThickness), Range.ringThickness)
        previewOpacity = Settings.read(defaults, Key.previewOpacity, Double(d.previewOpacity), Range.previewOpacity)
        previewCornerRadius = Settings.read(defaults, Key.previewCornerRadius, Double(d.previewCornerRadius), Range.previewCornerRadius)
        triggerDistance = Settings.read(defaults, Key.triggerDistance, Double(d.triggerDistance), Range.triggerDistance)
        showRing = defaults.object(forKey: Key.showRing) as? Bool ?? d.showRing
        showPreview = defaults.object(forKey: Key.showPreview) as? Bool ?? d.showPreview
        previewUsesTint = defaults.object(forKey: Key.previewUsesTint) as? Bool ?? d.previewUsesTint

        ZoneMath.deadzoneRadius = CGFloat(triggerDistance)
    }

    /// Missing keys fall back to the default; out-of-range ones are clamped, so
    /// a hand-edited plist can never produce a ring that cannot be drawn.
    private static func read(_ defaults: UserDefaults, _ key: String,
                             _ fallback: Double, _ range: ClosedRange<Double>) -> Double {
        guard defaults.object(forKey: key) != nil else { return fallback }
        return min(max(defaults.double(forKey: key), range.lowerBound), range.upperBound)
    }

    private func commit(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
    }

    // MARK: Derived

    var style: Style {
        Style(design: design,
              detail: CGFloat(detail),
              tint: tintColor,
                   ringRadius: CGFloat(ringRadius),
                   ringThickness: CGFloat(ringThickness),
                   showRing: showRing,
                   showPreview: showPreview,
                   previewOpacity: CGFloat(previewOpacity),
                   previewCornerRadius: CGFloat(previewCornerRadius),
                   previewUsesTint: previewUsesTint,
                   triggerDistance: CGFloat(triggerDistance))
    }

    /// The detail value a design is tuned to, whether or not it is selected.
    func detail(for design: RingDesign) -> Double {
        details[design.rawValue] ?? design.detail.value
    }

    /// The current style as that design would draw it — what the gallery shows.
    func style(for design: RingDesign) -> Style {
        var s = style
        s.design = design
        s.detail = CGFloat(detail(for: design))
        return s
    }

    /// `nil` when the stored tint is a custom hex rather than one of the swatches.
    var selectedTint: Tint? { Tint(rawValue: tint) }

    var tintColor: NSColor {
        if let preset = selectedTint { return preset.color }
        return NSColor(hex: tint) ?? Tint.system.color
    }

    func setTint(_ preset: Tint) { tint = preset.rawValue }
    func setCustomTint(_ color: NSColor) { tint = color.hexString }

    func resetToDefaults() {
        let d = Style.default
        design = d.design
        details = [:]
        tint = Tint.system.rawValue
        ringRadius = Double(d.ringRadius)
        ringThickness = Double(d.ringThickness)
        showRing = d.showRing
        showPreview = d.showPreview
        previewOpacity = Double(d.previewOpacity)
        previewCornerRadius = Double(d.previewCornerRadius)
        previewUsesTint = d.previewUsesTint
        triggerDistance = Double(d.triggerDistance)
    }

    var isDefault: Bool { style == .default && selectedTint == .system && details.isEmpty }

    // MARK: Login item

    /// Not persisted by Dowey — `SMAppService` owns this state, so it is read
    /// back from the system rather than mirrored into UserDefaults.
    var opensAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("Dowey: could not \(newValue ? "enable" : "disable") open at login — \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Hex

extension NSColor {

    /// `#RRGGBB`. Returns nil for anything else, which sends the caller back to
    /// the system accent color.
    convenience init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                  green: CGFloat((value >> 8) & 0xFF) / 255,
                  blue: CGFloat(value & 0xFF) / 255,
                  alpha: 1)
    }

    var hexString: String {
        guard let rgb = usingColorSpace(.sRGB) else { return "#007AFF" }
        return String(format: "#%02X%02X%02X",
                      Int((rgb.redComponent * 255).rounded()),
                      Int((rgb.greenComponent * 255).rounded()),
                      Int((rgb.blueComponent * 255).rounded()))
    }
}

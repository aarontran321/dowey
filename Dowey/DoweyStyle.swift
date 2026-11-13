//
//  DoweyStyle.swift
//  Dowey
//
//  Dowey's own controls for the settings window: panel, section header, row,
//  slider, switch, swatch and button.
//
//  The stock grouped Form made the window read as System Settings rather than
//  as Dowey, and its controls draw in the system accent, which macOS greys out
//  whenever the window is not key. Everything here draws in the ring's tint
//  instead, carried in the environment, so the window wears the color the user
//  picked and keeps it while it sits behind another app.
//

import SwiftUI

// MARK: - Tint in the environment

private struct DoweyTintKey: EnvironmentKey {
    static let defaultValue = Color(nsColor: .controlAccentColor)
}

extension EnvironmentValues {
    /// The ring's color. Set once at the root of the settings window.
    var doweyTint: Color {
        get { self[DoweyTintKey.self] }
        set { self[DoweyTintKey.self] = newValue }
    }
}

// MARK: - Palette

/// Surface colors, each with a light and a dark value so the window follows
/// the system appearance.
enum DoweyPalette {

    static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }

    /// Laid over the window material to deepen it, so the panels have
    /// something darker to sit on.
    static let canvas = dynamic(light: NSColor(white: 0.97, alpha: 0.55),
                                dark: NSColor(white: 0.06, alpha: 0.62))

    static let panel = dynamic(light: NSColor(white: 1, alpha: 0.78),
                               dark: NSColor(white: 1, alpha: 0.045))

    /// The lit top edge of a panel.
    static let panelEdgeTop = dynamic(light: NSColor(white: 1, alpha: 1),
                                      dark: NSColor(white: 1, alpha: 0.11))
    static let panelEdgeBottom = dynamic(light: NSColor(white: 0, alpha: 0.07),
                                         dark: NSColor(white: 1, alpha: 0.025))

    static let panelShadow = dynamic(light: NSColor(white: 0, alpha: 0.07),
                                     dark: NSColor(white: 0, alpha: 0.35))

    static let hairline = dynamic(light: NSColor(white: 0, alpha: 0.07),
                                  dark: NSColor(white: 1, alpha: 0.06))

    static let track = dynamic(light: NSColor(white: 0, alpha: 0.10),
                               dark: NSColor(white: 1, alpha: 0.11))

    static let switchOff = dynamic(light: NSColor(white: 0, alpha: 0.13),
                                   dark: NSColor(white: 1, alpha: 0.14))

    static let fieldFill = dynamic(light: NSColor(white: 0, alpha: 0.05),
                                   dark: NSColor(white: 1, alpha: 0.07))
}

// MARK: - Section header

/// Small tracked capitals, the same voice as RING DESIGN in the left column,
/// so both halves of the window read as one design.
struct SectionHeader: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(0.9)
            .foregroundStyle(.tertiary)
            .padding(.leading, 4)
            .padding(.bottom, 8)
    }
}

// MARK: - Panel

/// A raised surface: a faint fill, an edge lit from above and a soft shadow
/// underneath. Rows inside it are separated by `PanelDivider`.
struct Panel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(DoweyPalette.panel)
                    .shadow(color: DoweyPalette.panelShadow, radius: 14, y: 6)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [DoweyPalette.panelEdgeTop, DoweyPalette.panelEdgeBottom],
                                                 startPoint: .top, endPoint: .bottom),
                                  lineWidth: 1)
            }
    }
}

struct PanelDivider: View {
    var body: some View {
        Rectangle().fill(DoweyPalette.hairline).frame(height: 1)
    }
}

/// Caption under a panel.
struct PanelFootnote: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
            .padding(.top, 8)
    }
}

// MARK: - Rows

/// Title on the left, control on the right.
struct ControlRow<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            Text(title).font(.system(size: 13))
            Spacer(minLength: 8)
            trailing
        }
        .frame(minHeight: 44)
    }
}

/// Title above, then the track with its two end labels. Kept two-line so the
/// track is long enough to aim with.
struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let low: String
    let high: String

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 13))
            HStack(spacing: 10) {
                Text(low).frame(minWidth: 40, alignment: .leading)
                DoweySlider(value: $value, range: range)
                Text(high).frame(minWidth: 40, alignment: .trailing)
            }
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 12)
        .opacity(isEnabled ? 1 : 0.45)
    }
}

// MARK: - Slider

/// A thin track filled in the ring's tint, with a white knob that swells under
/// the pointer.
///
/// VoiceOver and keyboard users get a real `Slider` through the accessibility
/// representation, so the custom drawing costs them nothing.
struct DoweySlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>

    @Environment(\.doweyTint) private var tint
    @Environment(\.isEnabled) private var isEnabled
    @State private var isDragging = false
    @State private var isHovering = false

    private let knob: CGFloat = 16
    private let trackHeight: CGFloat = 4

    var body: some View {
        GeometryReader { geometry in
            let usable = max(geometry.size.width - knob, 1)
            let span = range.upperBound - range.lowerBound
            let fraction = span > 0 ? CGFloat((value - range.lowerBound) / span) : 0
            let knobCenter = knob / 2 + usable * min(max(fraction, 0), 1)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(DoweyPalette.track)
                    .frame(height: trackHeight)

                Capsule()
                    .fill(LinearGradient(colors: [tint.opacity(0.6), tint],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(knobCenter, trackHeight), height: trackHeight)

                Circle()
                    .fill(.white)
                    .frame(width: knob, height: knob)
                    .overlay(Circle().strokeBorder(.black.opacity(0.08), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.35), radius: 2.5, y: 1)
                    .scaleEffect(isDragging ? 1.18 : (isHovering ? 1.08 : 1))
                    .offset(x: knobCenter - knob / 2)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        isDragging = true
                        let f = min(max((drag.location.x - knob / 2) / usable, 0), 1)
                        value = range.lowerBound + Double(f) * span
                    }
                    .onEnded { _ in isDragging = false }
            )
        }
        .frame(height: 22)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.14), value: isDragging)
        .animation(.easeOut(duration: 0.14), value: isHovering)
        .accessibilityRepresentation {
            Slider(value: $value, in: range)
        }
    }
}

// MARK: - Switch

/// A capsule that fills with the ring's tint when on. Drawn
/// rather than system, so it keeps its color when the window is not key.
struct DoweySwitchStyle: ToggleStyle {

    func makeBody(configuration: Configuration) -> some View {
        SwitchBody(configuration: configuration)
    }

    private struct SwitchBody: View {
        let configuration: ToggleStyleConfiguration

        @Environment(\.doweyTint) private var tint
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            HStack(spacing: 12) {
                configuration.label.font(.system(size: 13))
                Spacer(minLength: 8)
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        configuration.isOn.toggle()
                    }
                } label: {
                    track
                }
                .buttonStyle(.plain)
            }
            .frame(minHeight: 44)
            .opacity(isEnabled ? 1 : 0.45)
        }

        private var track: some View {
            let on = configuration.isOn
            return Capsule()
                .fill(on ? AnyShapeStyle(LinearGradient(colors: [tint.opacity(0.85), tint],
                                                       startPoint: .top, endPoint: .bottom))
                         : AnyShapeStyle(DoweyPalette.switchOff))
                .frame(width: 36, height: 21)
                .overlay {
                    Capsule().strokeBorder(.white.opacity(on ? 0.18 : 0.04), lineWidth: 0.5)
                }
                .overlay(alignment: on ? .trailing : .leading) {
                    Circle()
                        .fill(.white)
                        .frame(width: 17, height: 17)
                        .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
                        .padding(2)
                }
                .contentShape(Capsule())
        }
    }
}

extension ToggleStyle where Self == DoweySwitchStyle {
    static var dowey: DoweySwitchStyle { DoweySwitchStyle() }
}

// MARK: - Button

/// A quiet capsule. `prominent` fills it with the tint, for the one action in
/// a row that fixes something.
struct DoweyButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        ButtonBody(configuration: configuration, prominent: prominent)
    }

    private struct ButtonBody: View {
        let configuration: ButtonStyleConfiguration
        let prominent: Bool

        @Environment(\.doweyTint) private var tint
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background {
                    Capsule().fill(prominent ? AnyShapeStyle(tint)
                                             : AnyShapeStyle(DoweyPalette.fieldFill))
                }
                .overlay {
                    Capsule().strokeBorder(DoweyPalette.hairline, lineWidth: 1)
                }
                .brightness(configuration.isPressed ? -0.08 : (isHovering ? 0.05 : 0))
                .opacity(isEnabled ? 1 : 0.4)
                .onHover { isHovering = $0 }
                .contentShape(Capsule())
        }
    }
}

// MARK: - Swatch

/// A color dot. Selection is a ring in the dot's own color with a gap, so the
/// chosen color is marked by itself rather than by a grey outline.
struct DoweySwatch: View {
    let fill: AnyShapeStyle
    let ringColor: Color
    let isSelected: Bool

    @State private var isHovering = false

    var body: some View {
        Circle()
            .fill(fill)
            .frame(width: 18, height: 18)
            .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
            .padding(4)
            .overlay {
                Circle().strokeBorder(ringColor.opacity(isSelected ? 1 : 0), lineWidth: 2)
            }
            .scaleEffect(isHovering && !isSelected ? 1.1 : 1)
            .animation(.easeOut(duration: 0.12), value: isHovering)
            .animation(.easeOut(duration: 0.15), value: isSelected)
            .onHover { isHovering = $0 }
            .contentShape(Circle())
    }
}

/// The custom-color swatch: a spectrum dot that opens the system color panel.
/// When a custom color is in use the dot shows that color inside the spectrum.
struct CustomColorSwatch: View {
    let current: NSColor
    let isSelected: Bool
    let onChange: (NSColor) -> Void

    @StateObject private var bridge = ColorPanelBridge()

    var body: some View {
        DoweySwatch(fill: AnyShapeStyle(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red],
                                                        center: .center)),
                    ringColor: Color(nsColor: current),
                    isSelected: isSelected)
            .overlay {
                if isSelected {
                    Circle()
                        .fill(Color(nsColor: current))
                        .frame(width: 9, height: 9)
                        .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 1))
                }
            }
            .onTapGesture { bridge.open(with: current, onChange: onChange) }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Custom Color")
    }
}

/// `NSColorPanel` reports through target/action, which a SwiftUI view cannot
/// be; this object stands in for it while the panel is open.
final class ColorPanelBridge: NSObject, ObservableObject {
    private var onChange: ((NSColor) -> Void)?

    func open(with color: NSColor, onChange: @escaping (NSColor) -> Void) {
        self.onChange = onChange
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.setTarget(self)
        panel.setAction(#selector(colorChanged(_:)))
        panel.color = color
        panel.orderFront(nil)
    }

    @objc private func colorChanged(_ sender: NSColorPanel) {
        onChange?(sender.color)
    }
}

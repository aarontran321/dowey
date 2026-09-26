//
//  SettingsView.swift
//  Dowey
//
//  The General tab is the whole ring surface, in two even columns: what it looks like on the left
//  — the live preview, the design gallery and the zone layout — and the knobs
//  for whatever is selected on the right.
//
//  Neither column is privileged: both take half the window, so widening it
//  feeds the preview and the controls equally.
//
//  There is no Save button and no Apply button. Every control is bound straight
//  to the store, the store persists on write, and the preview is the real ring —
//  so the change you see is the change the gesture will use.
//

import SwiftUI

struct SettingsView: View {

    enum Metrics {
        /// Half of this is the narrowest a column may get: below it the
        /// gallery's three tiles stop being legible.
        static let minWindowWidth: CGFloat = 1000
    }

    @ObservedObject var settings: Settings
    @ObservedObject var navigation: SettingsNavigation
    @State private var permissions = PermissionStatus.current()

    var body: some View {
        Group {
            switch navigation.tab {
            case .general:   general
            case .shortcuts: ShortcutsView(settings: settings)
            }
        }
        .tint(Color(nsColor: settings.tintColor))
        // Event-driven, never polled: returning from System Settings reactivates
        // Dowey, which is exactly when the answer can have changed.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissions = .current()
        }
    }

    private var general: some View {
        HStack(spacing: 0) {
            stage.frame(maxWidth: .infinity)
            Divider()
            form.frame(maxWidth: .infinity)
        }
        // The two materials are painted behind the layout rather than inside
        // it, so they run up under the transparent titlebar while the controls
        // still respect it. Without this the titlebar strip stays see-through.
        .background(alignment: .leading) {
            HStack(spacing: 0) {
                VisualEffect(material: .contentBackground).frame(maxWidth: .infinity)
                VisualEffect(material: .sidebar).frame(maxWidth: .infinity)
            }
            .ignoresSafeArea()
        }
    }

    // MARK: - Left: preview and gallery

    private var stage: some View {
        ScrollView {
            stageContent
        }
    }

    /// Scrolled, because the preview is sized from the ring's own maximum and
    /// the gallery grows with the design count — neither is something the
    /// window height can be assumed to cover.
    private var stageContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            GesturePreview(style: settings.style)
                .frame(height: GesturePreviewView.preferredHeight)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text("Actual size — move the pointer here to try it")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 8)

            Text("RING DESIGN")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 28)
                .padding(.bottom, 12)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3), spacing: 18) {
                ForEach(RingDesign.allCases) { design in
                    DesignCell(style: settings.style(for: design).miniature(radius: 30),
                               name: design.name,
                               isSelected: settings.design == design)
                        .onTapGesture { settings.design = design }
                        .help(design.summary)
                }
            }

            Divider()
                .padding(.top, 24)
                .padding(.bottom, 16)

            Toggle("Six zones only", isOn: $settings.sixZones)
                .toggleStyle(.switch)

            Text(settings.sixZones
                 ? "Halves and quarters, the original ring. Left and Right take a generous 90° each."
                 : "Adds Top and Bottom. Left and Right narrow to 50° to make room, and the quarters to 45°.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

            Spacer(minLength: 0)
        }
        .padding(24)
    }

    // MARK: - Right: the knobs

    private var form: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Color")
                    swatches
                }

                slider("Size", value: $settings.ringRadius,
                       range: Settings.Range.ringRadius, low: "Small", high: "Large")

                slider("Thickness", value: $settings.ringThickness,
                       range: Settings.Range.ringThickness, low: "Thin", high: "Thick")

                slider(settings.design.detail.label,
                       value: Binding(get: { settings.detail }, set: { settings.detail = $0 }),
                       range: settings.design.detail.range, low: "Less", high: "More")

                Toggle("Show at the pointer", isOn: $settings.showRing)
            } header: {
                Text(settings.design.name)
            } footer: {
                Text(settings.design.summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Destination") {
                Toggle("Highlight the destination", isOn: $settings.showPreview)

                slider("Opacity", value: $settings.previewOpacity,
                       range: Settings.Range.previewOpacity, low: "Clear", high: "Solid")
                    .disabled(!settings.showPreview)

                slider("Corners", value: $settings.previewCornerRadius,
                       range: Settings.Range.previewCornerRadius, low: "Square", high: "Round")
                    .disabled(!settings.showPreview)

                Toggle("Use the ring color", isOn: $settings.previewUsesTint)
                    .disabled(!settings.showPreview)
            }

            Section {
                slider("Trigger distance", value: $settings.triggerDistance,
                       range: Settings.Range.triggerDistance, low: "Short", high: "Long")
            } header: {
                Text("Gesture")
            } footer: {
                Text("How far the pointer travels before Dowey picks a direction. Release inside this distance to maximize.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("General") {
                Toggle("Open at Login", isOn: Binding(get: { settings.opensAtLogin },
                                                      set: { settings.opensAtLogin = $0 }))

                permissionRow("Accessibility", granted: permissions.accessibility,
                              action: openAccessibilitySettings)
                permissionRow("Input Monitoring", granted: permissions.inputMonitoring,
                              action: openInputMonitoringSettings)
            }

            Section {
                HStack {
                    Button("Restore Defaults") { settings.resetToDefaults() }
                        .disabled(settings.isDefault)
                    Spacer()
                    Text(versionString)
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden) // lets the window's material show through
    }

    // MARK: - Pieces

    private var swatches: some View {
        HStack(spacing: 6) {
            ForEach(Tint.allCases) { tint in
                Swatch(color: Color(nsColor: tint.color),
                       isSelected: settings.selectedTint == tint)
                    .onTapGesture { settings.setTint(tint) }
                    .help(tint.name)
            }

            Divider().frame(height: 18)

            ColorPicker("Custom Color",
                        selection: Binding(get: { Color(nsColor: settings.tintColor) },
                                           set: { settings.setCustomTint(NSColor($0)) }),
                        supportsOpacity: false)
                .labelsHidden()
                .frame(width: 44)
                .help("Custom Color")
        }
    }

    /// Title above the track rather than beside it: the inspector is 340 pt
    /// wide, and a label-plus-track row would leave the track too short to aim
    /// with. The end labels are plain text rather than the slider's own value
    /// labels, which pick up the tint and would turn every row into colored type.
    private func slider(_ title: String, value: Binding<Double>,
                        range: ClosedRange<Double>, low: String, high: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
            HStack(spacing: 8) {
                Text(low)
                Slider(value: value, in: range)
                Text(high)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func permissionRow(_ title: String, granted: Bool, action: @escaping () -> Void) -> some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                Text(granted ? "Granted" : "Not granted")
                    .foregroundStyle(granted ? .secondary : Color(nsColor: .systemOrange))
                if !granted {
                    Button("Open…", action: action)
                }
            }
        }
    }

    private var versionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        return "Dowey \(version)"
    }

    private func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    private func openInputMonitoringSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    private func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Shortcuts tab

/// Globe + arrow bindings. One narrow column centered in the window: four rows
/// do not need the width the ring page uses.
private struct ShortcutsView: View {

    @ObservedObject var settings: Settings

    var body: some View {
        Form {
            Section {
                Toggle("Snap windows with 🌐 + arrow keys", isOn: $settings.globeShortcutsEnabled)
            } footer: {
                Text("Hold Globe and press an arrow to move the focused window on the screen it is already on. The keys are taken before the app sees them, so they will not scroll, jump to the end of a line, or page through what you are working on. Keys set to Nothing reach the app as usual.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Shortcuts") {
                ForEach(ArrowKey.allCases) { key in
                    Picker(selection: Binding(get: { settings.shortcut(for: key) },
                                              set: { settings.setShortcut($0, for: key) })) {
                        ForEach(ShortcutAction.allCases) { action in
                            Label {
                                Text(action.name)
                            } icon: {
                                Image(nsImage: action.thumbnail)
                            }
                            .tag(action)
                            if action == .none || action == .maximize || action == .bottom {
                                Divider()
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            KeyCap("🌐")
                            Text("+").foregroundStyle(.tertiary)
                            KeyCap(key.symbol)
                        }
                        .accessibilityLabel("Globe plus \(key.name)")
                    }
                }
            }
            .disabled(!settings.globeShortcutsEnabled)

            Section {
                HStack {
                    Button("Restore Defaults") { settings.resetShortcuts() }
                        .disabled(settings.shortcutsAreDefault)
                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .background {
            VisualEffect(material: .contentBackground).ignoresSafeArea()
        }
    }
}

extension ShortcutAction {

    /// A miniature screen with the destination filled in, so the menu shows
    /// where the window goes rather than only naming it. Drawn from the same
    /// `SnapTarget.rect` the snap uses, so it cannot disagree with the result.
    /// Template, so menus tint it for light and dark.
    var thumbnail: NSImage { Self.thumbnails[self]! }

    private static let thumbnails: [ShortcutAction: NSImage] = Dictionary(
        uniqueKeysWithValues: allCases.map { ($0, $0.drawThumbnail()) })

    private func drawThumbnail() -> NSImage {
        let image = NSImage(size: NSSize(width: 24, height: 16), flipped: false) { bounds in
            let screen = bounds.insetBy(dx: 1.5, dy: 1.5)
            NSColor.black.set()

            let outline = NSBezierPath(roundedRect: screen, xRadius: 2.5, yRadius: 2.5)
            outline.lineWidth = 1
            outline.stroke()

            if let target {
                let rect = target.rect(in: screen.insetBy(dx: 2, dy: 2))
                NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 1, yRadius: 1).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

private struct KeyCap: View {
    let label: String

    init(_ label: String) { self.label = label }

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .medium))
            .frame(minWidth: 22, minHeight: 20)
            .background(Color.primary.opacity(0.07),
                        in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5)
            }
    }
}

// MARK: - Swatch

private struct Swatch: View {
    let color: Color
    let isSelected: Bool

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 16, height: 16)
            .overlay(Circle().strokeBorder(.black.opacity(0.12), lineWidth: 0.5))
            .padding(2.5)
            .overlay {
                // The selection ring sits outside the swatch, the way the accent
                // color picker in System Settings marks its choice.
                Circle().strokeBorder(Color.primary.opacity(isSelected ? 0.55 : 0), lineWidth: 1.5)
            }
            .contentShape(Circle())
    }
}

// MARK: - Design gallery

/// One tile in the gallery. The thumbnail is a real `RadialHUDView` at a
/// miniature scale, so a design can never advertise itself as something other
/// than what it draws.
private struct DesignCell: View {
    let style: Style
    let name: String
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            RingThumbnail(style: style)
                .frame(height: 104)
                .frame(maxWidth: .infinity)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.10),
                                      lineWidth: isSelected ? 2.5 : 1)
                }

            Text(name)
                .font(.caption)
                .foregroundStyle(isSelected ? .primary : .secondary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
    }
}

private struct RingThumbnail: NSViewRepresentable {
    let style: Style

    func makeNSView(context: Context) -> ThumbnailContainer { ThumbnailContainer(style: style) }
    func updateNSView(_ view: ThumbnailContainer, context: Context) { view.apply(style) }
}

/// Centers a `RadialHUDView` whose own size changes with the style.
final class ThumbnailContainer: NSView {
    private let hud: RadialHUDView

    init(style: Style) {
        hud = RadialHUDView(style: style)
        super.init(frame: .zero)
        hud.activeZone = .topRight // the gallery always shows a live direction
        addSubview(hud)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func apply(_ style: Style) {
        hud.apply(style)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        hud.setFrameOrigin(CGPoint(x: (bounds.width - hud.frame.width) / 2,
                                   y: (bounds.height - hud.frame.height) / 2))
    }
}

// MARK: - Live preview

/// Hosts the real `GesturePreviewView` — the same AppKit view classes the
/// gesture draws with — inside the window.
private struct GesturePreview: NSViewRepresentable {

    let style: Style

    func makeNSView(context: Context) -> GesturePreviewView {
        GesturePreviewView(style: style)
    }

    func updateNSView(_ view: GesturePreviewView, context: Context) {
        view.apply(style)
    }
}

// MARK: - Material

/// The window is one plain container; each column brings its own material, the
/// way a sidebar and its content pane do everywhere else on the system.
struct VisualEffect: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}

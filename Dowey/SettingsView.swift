//
//  SettingsView.swift
//  Dowey
//
//  The Ring tab is the whole ring surface, in two even columns: what it looks
//  like on the left — the live preview and the design gallery — and the knobs
//  for whatever is selected on the right. Setup that is not about the ring
//  (login, updates, permissions) lives on the General tab.
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
        /// Half of this is the narrowest a column may get.
        static let minWindowWidth: CGFloat = 1000
    }

    @ObservedObject var settings: Settings
    @ObservedObject var navigation: SettingsNavigation
    @State private var permissions = PermissionStatus.current()

    var body: some View {
        Group {
            switch navigation.tab {
            case .ring:      ring
            case .shortcuts: ShortcutsView(settings: settings)
            case .general:   GeneralView(settings: settings, permissions: permissions)
            }
        }
        .tint(Color(nsColor: settings.tintColor))
        .environment(\.doweyTint, Color(nsColor: settings.tintColor))
        // Event-driven, never polled: returning from System Settings reactivates
        // Dowey, which is exactly when the answer can have changed.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissions = .current()
        }
    }

    private var ring: some View {
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
                ControlsCanvas().frame(maxWidth: .infinity)
            }
            .ignoresSafeArea()
        }
    }

    // MARK: - Left: preview and gallery

    /// Scrolled, because the preview is sized from the ring's own maximum —
    /// not something the window height can be assumed to cover.
    private var stage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                GesturePreview(style: settings.style)
                    .frame(height: GesturePreviewView.preferredHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                SectionHeader("Ring design")
                    .padding(.top, 28)

                // Turns the whole ring on or off, so it sits with the gallery
                // rather than inside any one design's panel.
                Panel {
                    Toggle("Show at the pointer", isOn: $settings.showRing)
                        .toggleStyle(.dowey)
                }
                .padding(.bottom, 16)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 2), spacing: 18) {
                    ForEach(RingDesign.allCases) { design in
                        DesignCell(style: settings.style(for: design).miniature(radius: 30),
                                   name: design.name,
                                   isSelected: settings.design == design)
                            .onTapGesture { settings.design = design }
                            .help(design.summary)
                    }
                }
                .opacity(settings.showRing ? 1 : 0.45)

                Spacer(minLength: 0)
            }
            .padding(24)
        }
    }

    // MARK: - Right: the knobs

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(settings.design.name)
                Panel {
                    ControlRow(title: "Color") { swatches }
                    PanelDivider()
                    SliderRow(title: "Size", value: $settings.ringRadius, range: Settings.Range.ringRadius)
                    PanelDivider()
                    SliderRow(title: settings.design.detail.label,
                              value: Binding(get: { settings.detail }, set: { settings.detail = $0 }),
                              range: settings.design.detail.range)
                    PanelDivider()
                    MoreOptions {
                        PanelDivider()
                        SliderRow(title: "Thickness", value: $settings.ringThickness,
                                  range: Settings.Range.ringThickness)
                    }
                }

                SectionHeader("Destination").padding(.top, 28)
                Panel {
                    Toggle("Highlight the destination", isOn: $settings.showPreview)
                        .toggleStyle(.dowey)
                    PanelDivider()
                    Group {
                        Toggle("Use the ring color", isOn: $settings.previewUsesTint)
                            .toggleStyle(.dowey)
                        PanelDivider()
                        MoreOptions {
                            PanelDivider()
                            SliderRow(title: "Opacity", value: $settings.previewOpacity,
                                      range: Settings.Range.previewOpacity)
                            PanelDivider()
                            SliderRow(title: "Corners", value: $settings.previewCornerRadius,
                                      range: Settings.Range.previewCornerRadius)
                        }
                    }
                    .disabled(!settings.showPreview)
                }

                SectionHeader("Gesture").padding(.top, 28)
                Panel {
                    Toggle("Eight zones", isOn: $settings.eightZones)
                        .toggleStyle(.dowey)
                    PanelDivider()
                    SliderRow(title: "Trigger distance", value: $settings.triggerDistance,
                              range: Settings.Range.triggerDistance)
                }

                HStack {
                    Button("Restore Defaults") { settings.resetToDefaults() }
                        .buttonStyle(DoweyButtonStyle())
                        .disabled(settings.isDefault)
                    Spacer()
                }
                .padding(.top, 24)
                .padding(.horizontal, 4)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
        }
    }

    // MARK: - Pieces

    private var swatches: some View {
        HStack(spacing: 2) {
            ForEach(Tint.allCases) { tint in
                let color = Color(nsColor: tint.color)
                DoweySwatch(fill: AnyShapeStyle(color), ringColor: color,
                            isSelected: settings.selectedTint == tint)
                    .onTapGesture { settings.setTint(tint) }
                    .help(tint.name)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel(tint.name)
            }

            Rectangle()
                .fill(DoweyPalette.hairline)
                .frame(width: 1, height: 18)
                .padding(.horizontal, 6)

            CustomColorSwatch(current: settings.tintColor,
                              isSelected: settings.selectedTint == nil,
                              onChange: { settings.setCustomTint($0) })
                .help("Custom Color")
        }
    }
}

// MARK: - General tab

/// App setup rather than ring styling: startup, updates, permissions. One
/// narrow centered column, like the Shortcuts tab.
private struct GeneralView: View {

    @ObservedObject var settings: Settings
    let permissions: PermissionStatus

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader("Startup")
                Panel {
                    Toggle("Open at Login", isOn: Binding(get: { settings.opensAtLogin },
                                                          set: { settings.opensAtLogin = $0 }))
                        .toggleStyle(.dowey)
                }

                SectionHeader("Updates").padding(.top, 28)
                Panel {
                    Toggle("Check for updates", isOn: $settings.checkForUpdates)
                        .toggleStyle(.dowey)
                    PanelDivider()
                    UpdateRow(updater: .shared)
                }

                SectionHeader("Permissions").padding(.top, 28)
                Panel {
                    permissionRow("Accessibility", granted: permissions.accessibility,
                                  url: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
                    PanelDivider()
                    permissionRow("Input Monitoring", granted: permissions.inputMonitoring,
                                  url: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background {
            ZStack {
                VisualEffect(material: .contentBackground)
                ControlsCanvas(material: nil)
            }
            .ignoresSafeArea()
        }
    }

    private func permissionRow(_ title: String, granted: Bool, url: String) -> some View {
        ControlRow(title: title) {
            HStack(spacing: 10) {
                Text(granted ? "Granted" : "Not granted")
                    .font(.system(size: 12))
                    .foregroundStyle(granted ? Color.secondary : Color(nsColor: .systemOrange))
                if !granted {
                    Button("Open…") { open(url) }
                        .buttonStyle(DoweyButtonStyle(prominent: true))
                }
            }
        }
    }

    private func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Updates

/// The installed version and whatever the Updater has to say about it, with
/// the one action that fits: check, install, or fall back to the release page.
private struct UpdateRow: View {
    @ObservedObject var updater: Updater

    var body: some View {
        ControlRow(title: "Dowey \(updater.currentVersion)") {
            HStack(spacing: 10) {
                status
                action
            }
        }
    }

    @ViewBuilder private var status: some View {
        switch updater.state {
        case .idle:
            EmptyView()
        case .checking:
            busy("Checking…")
        case .upToDate:
            note("Up to date")
        case .available(let release):
            note("\(release.version) is available")
        case .installing(let release):
            busy("Installing \(release.version)…")
        case .failed(let message, _):
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(Color(nsColor: .systemOrange))
        }
    }

    @ViewBuilder private var action: some View {
        switch updater.state {
        case .available:
            Button("Install") { updater.install() }
                .buttonStyle(DoweyButtonStyle(prominent: true))
        case .failed(_, let release?):
            Button("Open Release Page") { updater.openReleasePage(release) }
                .buttonStyle(DoweyButtonStyle())
        case .checking, .installing:
            EmptyView()
        default:
            Button("Check Now") { updater.checkNow() }
                .buttonStyle(DoweyButtonStyle())
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
    }

    private func busy(_ text: String) -> some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            note(text)
        }
    }
}

// MARK: - Shortcuts tab

/// Globe + arrow bindings. One narrow column centered in the window: four rows
/// do not need the width the ring page uses.
private struct ShortcutsView: View {

    @ObservedObject var settings: Settings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader("Keyboard")
                Panel {
                    Toggle("Snap windows with 🌐 + arrow keys", isOn: $settings.globeShortcutsEnabled)
                        .toggleStyle(.dowey)
                }
                PanelFootnote("Keys set to Nothing reach the app as usual.")

                SectionHeader("Shortcuts").padding(.top, 28)
                Panel {
                    ForEach(Array(ArrowKey.allCases.enumerated()), id: \.element) { index, key in
                        if index > 0 { PanelDivider() }
                        row(for: key)
                    }
                }
                .disabled(!settings.globeShortcutsEnabled)
                .opacity(settings.globeShortcutsEnabled ? 1 : 0.45)

                SectionHeader("Advanced").padding(.top, 28)
                Group {
                    Panel {
                        Toggle("Two arrows for corners", isOn: $settings.cornerChords)
                            .toggleStyle(.dowey)
                    }
                    PanelFootnote("🌐 + ↑ + → is top-right, 🌐 + ↓ + ← is bottom-left, and so on.")

                    Panel {
                        Toggle("Pick windows with 🌐 + ⌘ + arrow keys", isOn: $settings.windowSelection)
                            .toggleStyle(.dowey)
                    }
                    .padding(.top, 12)
                    PanelFootnote("A dashed outline means you are picking. Let go of ⌘ and it turns solid: arrows now move the window.")
                }
                .disabled(!settings.globeShortcutsEnabled)
                .opacity(settings.globeShortcutsEnabled ? 1 : 0.45)

                HStack {
                    Button("Restore Defaults") { settings.resetShortcuts() }
                        .buttonStyle(DoweyButtonStyle())
                        .disabled(settings.shortcutsAreDefault)
                    Spacer()
                }
                .padding(.top, 24)
                .padding(.horizontal, 4)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background {
            ZStack {
                VisualEffect(material: .contentBackground)
                ControlsCanvas(material: nil)
            }
            .ignoresSafeArea()
        }
    }

    private func row(for key: ArrowKey) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 5) {
                KeyCap("🌐")
                Text("+").font(.system(size: 11)).foregroundStyle(.tertiary)
                KeyCap(key.symbol)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Globe plus \(key.name)")

            Spacer(minLength: 8)

            Picker("Globe plus \(key.name)",
                   selection: Binding(get: { settings.shortcut(for: key) },
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
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
        .frame(minHeight: 48)
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
            .frame(minWidth: 26, minHeight: 24)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(DoweyPalette.fieldFill)
                    .shadow(color: DoweyPalette.panelShadow, radius: 1, y: 1)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [DoweyPalette.panelEdgeTop, DoweyPalette.hairline],
                                                 startPoint: .top, endPoint: .bottom), lineWidth: 1)
            }
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

    @Environment(\.doweyTint) private var tint
    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 6) {
            RingThumbnail(style: style)
                .frame(height: 104)
                .frame(maxWidth: .infinity)
                .background(DoweyPalette.panel)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(isSelected
                                      ? AnyShapeStyle(tint)
                                      : AnyShapeStyle(LinearGradient(colors: [DoweyPalette.panelEdgeTop.opacity(isHovering ? 1.6 : 1),
                                                                              DoweyPalette.panelEdgeBottom],
                                                                     startPoint: .top, endPoint: .bottom)),
                                      lineWidth: isSelected ? 2 : 1)
                }
                .shadow(color: DoweyPalette.panelShadow, radius: 6, y: 3)
                .onHover { isHovering = $0 }

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

// MARK: - Controls canvas

/// The controls column's background: the window material, deepened to a dark
/// grey so the panels have something to sit on.
private struct ControlsCanvas: View {
    var material: NSVisualEffectView.Material? = .sidebar

    var body: some View {
        ZStack {
            if let material { VisualEffect(material: material) }
            DoweyPalette.canvas
        }
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

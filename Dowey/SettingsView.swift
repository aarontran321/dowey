//
//  SettingsView.swift
//  Dowey
//
//  The whole app surface: one grouped form, System Settings' own layout.
//
//  There is no Save button and no Apply button. Every control is bound straight
//  to the store, the store persists on write, and the preview at the top is the
//  real ring — so the change you see is the change the gesture will use.
//

import SwiftUI

struct SettingsView: View {

    @ObservedObject var settings: Settings
    @State private var permissions = PermissionStatus.current()

    var body: some View {
        Form {
            Section {
                GesturePreview(style: settings.style)
                    .frame(height: GesturePreviewView.preferredHeight)
                    .listRowInsets(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
            } footer: {
                Text("Move the pointer across the preview to try each direction. Shown at actual size.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Ring") {
                LabeledContent("Color") { swatches }

                slider("Size", value: $settings.ringRadius,
                       range: Settings.Range.ringRadius, low: "Small", high: "Large")

                slider("Thickness", value: $settings.ringThickness,
                       range: Settings.Range.ringThickness, low: "Thin", high: "Thick")

                Toggle("Show the ring", isOn: $settings.showRing)
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
        .tint(Color(nsColor: settings.tintColor))
        // Event-driven, never polled: returning from System Settings reactivates
        // Dowey, which is exactly when the answer can have changed.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissions = .current()
        }
    }

    // MARK: - Pieces

    private var swatches: some View {
        HStack(spacing: 8) {
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

    /// The end labels are plain text rather than the slider's own value labels,
    /// which pick up the tint and would turn every row into colored type.
    private func slider(_ title: String, value: Binding<Double>,
                        range: ClosedRange<Double>, low: String, high: String) -> some View {
        LabeledContent(title) {
            HStack(spacing: 10) {
                Text(low)
                Slider(value: value, in: range).frame(width: 190)
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

// MARK: - Live preview

/// Hosts the real `GesturePreviewView` — the same AppKit view classes the
/// gesture draws with — inside the form.
private struct GesturePreview: NSViewRepresentable {

    let style: Style

    func makeNSView(context: Context) -> GesturePreviewView {
        GesturePreviewView(style: style)
    }

    func updateNSView(_ view: GesturePreviewView, context: Context) {
        view.apply(style)
    }
}

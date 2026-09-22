//
//  AppDelegate.swift
//  Dowey
//
//  Menu-bar-only lifecycle: permission check at launch, status item, the
//  Settings window, and ownership of the gesture monitor.
//

import AppKit
import ApplicationServices
import CoreGraphics

struct PermissionStatus {
    let accessibility: Bool
    let inputMonitoring: Bool

    var allGranted: Bool { accessibility && inputMonitoring }

    /// One-shot reads of the current TCC state. Never called on a timer — only
    /// at launch and whenever Dowey is reactivated with the Settings window
    /// open, which is the only moment the answer can have changed.
    static func current() -> PermissionStatus {
        PermissionStatus(accessibility: AXIsProcessTrusted(),
                         inputMonitoring: CGPreflightListenEventAccess())
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {

    private let monitor = GlobalEventMonitor()
    private var statusItem: NSStatusItem?

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()
        // Reading the store here is what pushes the saved trigger distance into
        // ZoneMath, before the first gesture can consult it.
        _ = Settings.shared
        monitor.start()

        let status = PermissionStatus.current()
        if !status.allGranted {
            presentPermissionAlert(for: status)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
    }

    /// Dowey has no Dock icon, so the only way to "open" an already-running copy
    /// is to launch it again from Finder or Spotlight. Treat that as a request
    /// for its one window rather than as nothing at all.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        SettingsWindowController.shared.show()
        return true
    }

    // MARK: - Status item

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        // The same circle as the app icon and the gesture's center target.
        item.button?.image = DoweyGlyph.statusItem()

        let menu = NSMenu()

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Dowey", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        item.menu = menu
        statusItem = item
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }

    // MARK: - Permissions

    private func presentPermissionAlert(for status: PermissionStatus) {
        var missing: [String] = []
        if !status.accessibility { missing.append("Accessibility (to move windows)") }
        if !status.inputMonitoring { missing.append("Input Monitoring (to see the Globe key)") }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Dowey needs permission to run"
        alert.informativeText = """
        Grant the following in System Settings → Privacy & Security:

        \(missing.map { "• \($0)" }.joined(separator: "\n"))

        Dowey will not ask again — the menu bar item's Settings window shows the current status once you have granted them.
        """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")

        if runAlertInForeground(alert) == .alertFirstButtonReturn {
            if !status.accessibility {
                // Prompts and deep-links in one call.
                AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
                openAccessibilitySettings()
            }
            if !status.inputMonitoring {
                CGRequestListenEventAccess()
                openInputMonitoringSettings()
            }
        }
    }

    /// LSUIElement apps are not frontmost, so an alert would otherwise open
    /// behind whatever the user is looking at.
    @discardableResult
    private func runAlertInForeground(_ alert: NSAlert) -> NSApplication.ModalResponse {
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal()
    }

    @objc private func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    @objc private func openInputMonitoringSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    private func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}

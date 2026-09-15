//
//  AppDelegate.swift
//  Dowey
//
//  Menu-bar-only lifecycle: permission checks at launch, status item, and
//  ownership of the gesture monitor.
//

import AppKit
import ApplicationServices
import CoreGraphics

struct PermissionStatus {
    let accessibility: Bool
    let inputMonitoring: Bool

    var allGranted: Bool { accessibility && inputMonitoring }

    /// One-shot reads of the current TCC state. Never called on a timer — only
    /// at launch, when the menu opens, and from "Recheck Permissions".
    static func current() -> PermissionStatus {
        PermissionStatus(accessibility: AXIsProcessTrusted(),
                         inputMonitoring: CGPreflightListenEventAccess())
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private let monitor = GlobalEventMonitor()
    private var statusItem: NSStatusItem?

    private let accessibilityItem = NSMenuItem(title: "", action: #selector(openAccessibilitySettings), keyEquivalent: "")
    private let inputMonitoringItem = NSMenuItem(title: "", action: #selector(openInputMonitoringSettings), keyEquivalent: "")

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()
        monitor.start()

        let status = PermissionStatus.current()
        refreshMenuItems(with: status)
        if !status.allGranted {
            presentPermissionAlert(for: status)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
    }

    // MARK: - Status item

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "macwindow.on.rectangle",
                                     accessibilityDescription: "Dowey")
        item.button?.image?.isTemplate = true

        let menu = NSMenu()
        menu.delegate = self

        accessibilityItem.target = self
        inputMonitoringItem.target = self
        menu.addItem(accessibilityItem)
        menu.addItem(inputMonitoringItem)
        menu.addItem(.separator())

        let recheck = NSMenuItem(title: "Recheck Permissions", action: #selector(recheckPermissions), keyEquivalent: "")
        recheck.target = self
        menu.addItem(recheck)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Dowey", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        item.menu = menu
        statusItem = item
    }

    /// NSMenuDelegate callback — status is re-read when the user opens the menu,
    /// which is what makes polling unnecessary.
    func menuNeedsUpdate(_ menu: NSMenu) {
        refreshMenuItems(with: .current())
    }

    private func refreshMenuItems(with status: PermissionStatus) {
        accessibilityItem.title = "Accessibility: \(status.accessibility ? "OK" : "Not granted")"
        inputMonitoringItem.title = "Input Monitoring: \(status.inputMonitoring ? "OK" : "Not granted")"
    }

    // MARK: - Permissions

    @objc private func recheckPermissions() {
        let status = PermissionStatus.current()
        refreshMenuItems(with: status)

        let alert = NSAlert()
        alert.alertStyle = status.allGranted ? .informational : .warning
        alert.messageText = status.allGranted ? "Dowey is ready" : "Dowey is missing permissions"
        alert.informativeText = """
        Accessibility: \(status.accessibility ? "granted" : "not granted")
        Input Monitoring: \(status.inputMonitoring ? "granted" : "not granted")
        """
        alert.addButton(withTitle: "OK")
        runAlertInForeground(alert)
    }

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

        Dowey will not ask again — use “Recheck Permissions” in the menu bar once you have granted them.
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

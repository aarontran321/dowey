//
//  AppDelegate.swift
//  Dowey
//
//  Menu-bar-only lifecycle: permission check at launch, status item, the
//  Settings window, and ownership of the gesture monitor.
//

import AppKit
import ApplicationServices
import Combine
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

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private let monitor = GlobalEventMonitor()
    private let shortcuts = GlobeShortcuts()
    private var statusItem: NSStatusItem?
    /// Top of the menu, shown only while there is an update to talk about.
    private let updateItem = NSMenuItem()
    private let updateSeparator = NSMenuItem.separator()
    private var cancellables: Set<AnyCancellable> = []

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()
        // Reading the store here is what pushes the saved trigger distance into
        // ZoneMath, before the first gesture can consult it.
        _ = Settings.shared
        monitor.start()
        setUpShortcuts()
        setUpUpdates()

        let status = PermissionStatus.current()
        if !status.allGranted {
            presentPermissionAlert(for: status)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.useExternalTrigger(false)
        shortcuts.stop()
        monitor.stop()
    }

    // MARK: - Shortcuts

    private func setUpShortcuts() {
        shortcuts.willAct = { [weak self] in self?.monitor.stepAside() }
        shortcuts.globeChanged = { [weak self] isDown in self?.monitor.globeChanged(isDown: isDown) }

        Settings.shared.$globeShortcutsEnabled
            .sink { [weak self] enabled in
                guard let self else { return }
                enabled ? self.shortcuts.start() : self.shortcuts.stop()
                self.monitor.useExternalTrigger(self.shortcuts.isRunning)
            }
            .store(in: &cancellables)

        // The tap cannot be installed without Accessibility. Coming back from
        // System Settings reactivates Dowey, which is when a grant can have
        // happened — try again then rather than on a timer.
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                guard let self, Settings.shared.globeShortcutsEnabled, !self.shortcuts.isRunning else { return }
                self.shortcuts.start()
                self.monitor.useExternalTrigger(self.shortcuts.isRunning)
            }
            .store(in: &cancellables)
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
        menu.delegate = self
        // The update item is greyed out while an install runs, which only
        // sticks with automatic enabling off.
        menu.autoenablesItems = false

        updateItem.target = self
        updateItem.action = #selector(updateItemChosen)
        menu.addItem(updateItem)
        menu.addItem(updateSeparator)

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

    func menuWillOpen(_ menu: NSMenu) {
        Updater.shared.checkIfDue()
    }

    // MARK: - Updates

    private func setUpUpdates() {
        Updater.shared.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in self?.showUpdateState(state) }
            .store(in: &cancellables)
        Updater.shared.checkIfDue()
    }

    private func showUpdateState(_ state: Updater.State) {
        var title: String?
        var enabled = true
        switch state {
        case .available(let release):
            title = "Update to Dowey \(release.version)"
        case .installing(let release):
            title = "Installing Dowey \(release.version)…"
            enabled = false
        case .failed(_, let release?):
            title = "Download Dowey \(release.version) from GitHub…"
        default:
            break
        }
        updateItem.title = title ?? ""
        updateItem.isEnabled = enabled
        updateItem.isHidden = title == nil
        updateSeparator.isHidden = title == nil
    }

    @objc private func updateItemChosen() {
        let updater = Updater.shared
        switch updater.state {
        case .available:
            updater.install()
        case .failed(_, let release):
            updater.openReleasePage(release)
        default:
            break
        }
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

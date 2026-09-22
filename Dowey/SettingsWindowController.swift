//
//  SettingsWindowController.swift
//  Dowey
//
//  The window around SettingsView: transparent titlebar, vibrant background,
//  nothing else. Built on first open and kept afterwards, so an app that has
//  never been configured still owns no window.
//

import AppKit
import SwiftUI

/// Dowey has no menu bar of its own (`.accessory` apps get none), so the two
/// shortcuts people will actually press are handled by the window itself.
private final class SettingsWindow: NSWindow {

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command else {
            return super.performKeyEquivalent(with: event)
        }
        switch event.charactersIgnoringModifiers {
        case "w": performClose(nil); return true
        case "q": NSApp.terminate(nil); return true
        default:  return super.performKeyEquivalent(with: event)
        }
    }
}

final class SettingsWindowController: NSWindowController {

    static let shared = SettingsWindowController()

    private init() {
        let window = SettingsWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 760),
                                    styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                    backing: .buffered,
                                    defer: false)
        window.title = "Dowey"
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        // The live preview tracks the pointer, and mouse-moved events are only
        // delivered to a window that asks for them.
        window.acceptsMouseMovedEvents = true
        window.contentMinSize = NSSize(width: 540, height: 460)
        window.contentMaxSize = NSSize(width: 540, height: CGFloat.greatestFiniteMagnitude)

        // The material is the window's background, so the window itself must not
        // paint one underneath it.
        window.isOpaque = false
        window.backgroundColor = .clear

        let material = NSVisualEffectView()
        material.material = .sidebar
        material.blendingMode = .behindWindow
        material.state = .active

        let host = NSHostingView(rootView: SettingsView(settings: .shared))
        host.translatesAutoresizingMaskIntoConstraints = false
        material.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: material.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: material.trailingAnchor),
            host.topAnchor.constraint(equalTo: material.topAnchor),
            host.bottomAnchor.constraint(equalTo: material.bottomAnchor),
        ])

        window.contentView = material
        window.center()
        window.setFrameAutosaveName("DoweySettings")

        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// An `.accessory` app is never frontmost on its own — without the activate
    /// the window would open behind whatever the user was looking at.
    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

//
//  SettingsWindowController.swift
//  Dowey
//
//  The window around SettingsView: transparent titlebar, vibrant columns,
//  nothing else. Built on demand and torn down again on close, so an app that
//  is not being configured owns no window and none of SwiftUI's machinery.
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

final class SettingsWindowController: NSWindowController, NSWindowDelegate {

    static let shared = SettingsWindowController()

    private static let defaultContentSize = NSSize(width: 1060, height: 720)

    private init() {
        super.init(window: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// An `.accessory` app is never frontmost on its own — without the activate
    /// the window would open behind whatever the user was looking at.
    func show() {
        NSApp.activate(ignoringOtherApps: true)
        if window == nil { window = makeWindow() }
        window?.makeKeyAndOrderFront(nil)
    }

    /// Closing frees the window and the whole SwiftUI hierarchy under it.
    ///
    /// This recovers a few MB, not the ~27 MB that opening Settings costs.
    /// Most of that is SwiftUI initializing itself, which stays up for the life
    /// of the process, and freed pages the allocator keeps rather than returns.
    /// `malloc_zone_pressure_relief` was measured here and made no difference,
    /// so it is deliberately absent. What this does buy is correct ownership:
    /// no retained view hierarchy, tracking area or store observer belonging to
    /// a window the user has dismissed.
    ///
    /// The release is deferred one turn of the run loop so the window is not
    /// deallocated mid-close.
    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.window?.delegate = nil
            self?.window = nil
        }
    }

    private func makeWindow() -> NSWindow {
        let window = SettingsWindow(contentRect: NSRect(origin: .zero, size: Self.defaultContentSize),
                                    styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                    backing: .buffered,
                                    defer: false)
        window.title = "Dowey"
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        // The live preview tracks the pointer, and mouse-moved events are only
        // delivered to a window that asks for them.
        window.acceptsMouseMovedEvents = true
        // The columns split the window evenly, so the minimum is set by the
        // narrower of the two halves rather than by either one on its own.
        window.contentMinSize = NSSize(width: SettingsView.Metrics.minWindowWidth, height: 620)
        window.contentMaxSize = NSSize(width: 1600, height: CGFloat.greatestFiniteMagnitude)

        // The material is the window's background, so the window itself must not
        // paint one underneath it.
        window.isOpaque = false
        window.backgroundColor = .clear
        // ARC owns the window now that the controller drops it on close; the
        // AppKit-era auto-release on close would free it a second time.
        window.isReleasedWhenClosed = false

        // No material here: each column of SettingsView brings its own, so the
        // sidebar and the content pane read as two surfaces rather than one.
        let host = NSHostingView(rootView: SettingsView(settings: .shared))
        // Without this the hosting view publishes its SwiftUI content size as
        // constraints on the window, and the window obeys them: the form's
        // natural height is over 1000 pt, which grew the window taller than a
        // laptop screen. The window owns its size; the columns scroll.
        host.sizingOptions = []

        window.contentView = host
        window.center()
        // Restores the size and position from the last visit, which is what
        // makes tearing the window down invisible to the user.
        window.setFrameAutosaveName("DoweySettings")
        // A frame saved by a build that let the hosting view dictate the size
        // can be taller than the display; AppKit restores it verbatim, so an
        // upgrade would inherit an unusable window. Trimming such a frame to
        // fit would leave it filling the screen edge to edge, so a frame that
        // does not fit is discarded for the default size instead.
        if let screen = window.screen ?? NSScreen.main,
           !screen.visibleFrame.contains(window.frame) {
            window.setContentSize(Self.defaultContentSize)
            window.center()
        }
        window.delegate = self

        return window
    }
}

//
//  GlobeShortcuts.swift
//  Dowey
//
//  Globe + arrow keys. Unlike the gesture, this has to *consume* what it
//  handles: Globe + arrow is Home / End / Page Up / Page Down to every app, so
//  an observe-only monitor would snap the window and scroll the document under
//  it. That takes a CGEventTap, which is the one place Dowey sits in the
//  keystroke path — so the callback does as little as possible and gets out.
//

import AppKit
import CoreGraphics

final class GlobeShortcuts {

    private static let globeKeyCode: CGKeyCode = 63

    /// Arrow keys, plus the codes an Apple keyboard sends *instead* of them
    /// while Globe is held: the fn layer is applied in the keyboard driver, so
    /// on a MacBook Globe + ← arrives as Home, never as ←.
    private static let arrowForKeyCode: [Int64: ArrowKey] = [
        126: .up,    116: .up,     // ↑, Page Up
        123: .left,  115: .left,   // ←, Home
        124: .right, 119: .right,  // →, End
        125: .down,  121: .down,   // ↓, Page Down
    ]

    /// Modifiers that make a press someone else's shortcut. Globe + Shift + ←
    /// is "select to start of line" and stays that way.
    private static let otherModifiers: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// Key codes whose key-down was eaten, so their key-up (and any repeats)
    /// are eaten too — even if Globe is let go first. An app that sees a
    /// key-up with no key-down is at best confused.
    private var swallowed: Set<Int64> = []

    /// Called before a snap so the gesture can hand its ring over to the
    /// shortcut: Globe is already down, so the HUD is on screen and would
    /// otherwise maximize on release.
    var willSnap: ((SnapTarget) -> Void)?

    var isRunning: Bool { tap != nil }

    // MARK: - Lifecycle

    /// Fails quietly without Accessibility; call again once it is granted.
    func start() {
        guard tap == nil else { return }

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
                 | CGEventMask(1 << CGEventType.keyUp.rawValue)

        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .defaultTap,
                                          eventsOfInterest: mask,
                                          callback: globeShortcutsCallback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            NSLog("Dowey: could not install the keyboard shortcut tap — Accessibility not granted?")
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.tap = tap
        self.runLoopSource = source
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil
        runLoopSource = nil
        swallowed.removeAll()
    }

    // MARK: - Events

    /// Returns nil to swallow the event.
    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> CGEvent? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // The system switches a slow tap off; switch it straight back on.
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return event

        case .keyUp:
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            return swallowed.remove(code) == nil ? event : nil

        case .keyDown:
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            if swallowed.contains(code) { return nil } // auto-repeat of a handled press

            guard let arrow = Self.arrowForKeyCode[code],
                  event.flags.intersection(Self.otherModifiers).isEmpty,
                  // Arrow events carry the fn flag whether or not Globe is
                  // held, so the flag proves nothing — ask the hardware.
                  CGEventSource.keyState(.combinedSessionState, key: Self.globeKeyCode),
                  let target = Settings.shared.shortcut(for: arrow).target else {
                return event
            }

            swallowed.insert(code)
            // Off the tap's callback: the AX calls can take up to a second on
            // a hung app, and every keystroke on the system waits for this
            // function to return.
            DispatchQueue.main.async { [weak self] in self?.snap(to: target) }
            return nil

        default:
            return event
        }
    }

    private func snap(to target: SnapTarget) {
        willSnap?(target)
        // The window's own screen, not the cursor's: a keyboard shortcut has
        // no pointer in it, and the window should not jump displays.
        let anchor = WindowEngine.focusedWindowCenter() ?? NSEvent.mouseLocation
        WindowEngine.snap(target, at: anchor) { result in
            if case .failure(let error) = result {
                NSLog("Dowey: shortcut to \(target.displayName) failed — \(error.description)")
            }
        }
    }
}

private func globeShortcutsCallback(proxy: CGEventTapProxy,
                                    type: CGEventType,
                                    event: CGEvent,
                                    userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let shortcuts = Unmanaged<GlobeShortcuts>.fromOpaque(userInfo).takeUnretainedValue()
    return shortcuts.handle(type, event).map { Unmanaged.passUnretained($0) }
}

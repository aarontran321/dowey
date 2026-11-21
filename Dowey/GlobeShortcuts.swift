//
//  GlobeShortcuts.swift
//  Dowey
//
//  Globe + arrow keys. Unlike the gesture, this has to *consume* what it
//  handles: Globe + arrow is Home / End / Page Up / Page Down to every app, so
//  an observe-only monitor would snap the window and scroll the document under
//  it. That takes a CGEventTap, the one place Dowey sits in the keystroke
//  path, so it sits there only while Globe is held. At rest a second tap sees
//  modifier changes and nothing else; typing never reaches Dowey at all.
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

    /// Always installed: sees modifier changes only, never ordinary typing.
    /// Its one job is to switch `keyTap` on the moment Globe goes down.
    private var trigger: Tap?

    /// Key-down / key-up. Installed with the trigger but *enabled* only while
    /// Globe is held (or a swallowed key is still waiting for its key-up), so
    /// the rest of the time no keystroke on the system passes through Dowey.
    ///
    /// Taps on one event stream run in order, and the trigger enables this
    /// one from inside its own callback, before it returns — so the first
    /// arrow after Globe is always seen. No race with a separate monitor.
    private var keyTap: Tap?

    /// Key codes whose key-down was eaten, so their key-up (and any repeats)
    /// are eaten too — even if Globe is let go first. An app that sees a
    /// key-up with no key-down is at best confused.
    private var swallowed: Set<Int64> = []

    private var globeDown = false

    /// Called before a snap so the gesture can hand its ring over to the
    /// shortcut: Globe is already down, so the HUD is on screen and would
    /// otherwise maximize on release.
    var willSnap: ((SnapTarget) -> Void)?

    var isRunning: Bool { trigger != nil && keyTap != nil }

    // MARK: - Lifecycle

    /// Fails quietly without Accessibility; call again once it is granted.
    func start() {
        guard !isRunning else { return }
        stop()

        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let trigger = Tap(mask: CGEventMask(1 << CGEventType.flagsChanged.rawValue),
                                callback: globeTriggerCallback, context: context),
              let keyTap = Tap(mask: CGEventMask(1 << CGEventType.keyDown.rawValue)
                                   | CGEventMask(1 << CGEventType.keyUp.rawValue),
                               callback: globeShortcutsCallback, context: context) else {
            NSLog("Dowey: could not install the keyboard shortcut tap — Accessibility not granted?")
            return
        }

        self.trigger = trigger
        self.keyTap = keyTap
        // Globe may already be down if this runs mid-press.
        globeDown = CGEventSource.keyState(.combinedSessionState, key: Self.globeKeyCode)
        trigger.setEnabled(true)
        updateKeyTap()
    }

    func stop() {
        trigger?.invalidate()
        keyTap?.invalidate()
        trigger = nil
        keyTap = nil
        swallowed.removeAll()
        globeDown = false
    }

    private func updateKeyTap() {
        keyTap?.setEnabled(globeDown || !swallowed.isEmpty)
    }

    // MARK: - Events

    fileprivate func handleTrigger(_ type: CGEventType, _ event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            trigger?.setEnabled(true)
        case .flagsChanged:
            guard event.getIntegerValueField(.keyboardEventKeycode) == Int64(Self.globeKeyCode) else { return }
            // Same rule as the gesture: down iff the fn flag survives the event.
            globeDown = event.flags.contains(.maskSecondaryFn)
            updateKeyTap()
        default:
            break
        }
    }

    /// Returns nil to swallow the event.
    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> CGEvent? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // The system switches a slow tap off; put it back the way it
            // should be rather than unconditionally on.
            updateKeyTap()
            return event

        case .keyUp:
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            guard swallowed.remove(code) != nil else { return event }
            updateKeyTap()
            return nil

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

/// One session event tap and its run-loop source, created disabled.
private final class Tap {

    private let port: CFMachPort
    private let source: CFRunLoopSource

    init?(mask: CGEventMask, callback: CGEventTapCallBack, context: UnsafeMutableRawPointer) {
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                           place: .headInsertEventTap,
                                           options: .defaultTap,
                                           eventsOfInterest: mask,
                                           callback: callback,
                                           userInfo: context) else { return nil }
        CGEvent.tapEnable(tap: port, enable: false)
        self.port = port
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }

    /// Asks the tap itself rather than a cached flag, so a tap the system
    /// switched off behind our back is noticed and put right.
    func setEnabled(_ on: Bool) {
        guard CGEvent.tapIsEnabled(tap: port) != on else { return }
        CGEvent.tapEnable(tap: port, enable: on)
    }

    func invalidate() {
        CGEvent.tapEnable(tap: port, enable: false)
        CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        CFMachPortInvalidate(port)
    }
}

private func globeTriggerCallback(proxy: CGEventTapProxy,
                                  type: CGEventType,
                                  event: CGEvent,
                                  userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if let userInfo {
        Unmanaged<GlobeShortcuts>.fromOpaque(userInfo).takeUnretainedValue().handleTrigger(type, event)
    }
    // Never consumes: modifier changes always reach their apps.
    return Unmanaged.passUnretained(event)
}

private func globeShortcutsCallback(proxy: CGEventTapProxy,
                                    type: CGEventType,
                                    event: CGEvent,
                                    userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let shortcuts = Unmanaged<GlobeShortcuts>.fromOpaque(userInfo).takeUnretainedValue()
    return shortcuts.handle(type, event).map { Unmanaged.passUnretained($0) }
}

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

    /// Arrows down right now with Globe and no other modifier, handled or
    /// not, by key code. Two of them at right angles make a corner.
    private var heldArrows: [Int64: Direction] = [:]

    /// The window picked with 🌐 + ⌘ + arrow during this Globe hold. Snaps
    /// act on it rather than asking which window is focused: activation is
    /// asynchronous, and an arrow pressed a moment after the pick could
    /// otherwise reach the window that had focus before it.
    private var selected: AXUIElement?

    /// Called before the keyboard acts — a snap, a pick, or entering Pick —
    /// so the gesture steps aside: Globe is already down, so its ring is on
    /// screen and would otherwise maximize on release.
    var willAct: (() -> Void)?

    /// ⌘ as of the last modifier change. With Globe down it switches between
    /// Pick (held) and Move (let go).
    private var commandDown = false

    /// What the window outline is showing, or nil when there is none.
    private var mode: KeyboardMode?
    private let overlay = KeyboardModeOverlay()

    /// Takes the outline down if Globe's release is ever missed. Runs only
    /// while an outline is up.
    private var releaseWatchdog: Timer?

    /// Globe went down (true) or up (false). While this tap is running it is
    /// the gesture's trigger too, so a modifier change on the system wakes
    /// Dowey once rather than once per listener. Delivered on a later
    /// main-queue turn: the tap returns at once and no modifier waits on the
    /// ring being drawn.
    var globeChanged: ((Bool) -> Void)?

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
        heldArrows.removeAll()
        selected = nil
        globeDown = false
        endKeyboardMode()
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
            let command = event.flags.contains(.maskCommand)
            if command != commandDown {
                commandDown = command
                if globeDown {
                    DispatchQueue.main.async { [weak self] in self?.commandChanged(command) }
                }
            }
            guard event.getIntegerValueField(.keyboardEventKeycode) == Int64(Self.globeKeyCode) else { return }
            // Down iff the fn flag survives the event.
            // Forwarded even when it repeats what was last seen: a release the
            // system swallowed must not make the next press look like a repeat.
            // The gesture ignores a down while armed and an up while idle.
            let isDown = event.flags.contains(.maskSecondaryFn)
            globeDown = isDown
            if let globeChanged {
                DispatchQueue.main.async { globeChanged(isDown) }
            }
            // Each Globe hold starts fresh: held arrows whose key-up was
            // missed, and the window picked last time, belong to the last one.
            heldArrows.removeAll()
            selected = nil
            updateKeyTap()
            DispatchQueue.main.async { [weak self] in
                // Globe pressed with ⌘ already down goes straight into Pick.
                if isDown, command { self?.commandChanged(true) }
                if !isDown { self?.endKeyboardMode() }
            }
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
            heldArrows.removeValue(forKey: code)
            guard swallowed.remove(code) != nil else { return event }
            updateKeyTap()
            return nil

        case .keyDown:
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            if swallowed.contains(code) { return nil } // auto-repeat of a handled press

            guard let arrow = Self.arrowForKeyCode[code],
                  // Arrow events carry the fn flag whether or not Globe is
                  // held, so the flag proves nothing — ask the hardware.
                  CGEventSource.keyState(.combinedSessionState, key: Self.globeKeyCode) else {
                return event
            }
            let settings = Settings.shared
            let modifiers = event.flags.intersection(Self.otherModifiers)

            // 🌐 + ⌘ + arrow: focus the next window that way.
            if modifiers == .maskCommand {
                guard settings.windowSelection else { return event }
                swallowed.insert(code)
                // Off the tap's callback, like a snap: the window list and
                // the AX lookups would hold every keystroke on the system.
                DispatchQueue.main.async { [weak self] in self?.select(toward: arrow.direction) }
                return nil
            }
            guard modifiers.isEmpty else { return event }

            // A second arrow at right angles to one already held: the corner
            // between them. Works in either order, and whether or not the
            // first arrow had anything assigned.
            let partner = heldArrows.first { $0.key != code && Direction.corner($0.value, arrow.direction) != nil }
            heldArrows[code] = arrow.direction
            if settings.cornerChords, let partner,
               let corner = Direction.corner(partner.value, arrow.direction) {
                swallowed.insert(code)
                DispatchQueue.main.async { [weak self] in self?.snap(to: .zone(corner)) }
                return nil
            }

            guard let target = settings.shortcut(for: arrow).target else { return event }
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
        willAct?()
        // The window's own screen, not the cursor's: a keyboard shortcut has
        // no pointer in it, and the window should not jump displays.
        let window = selected
        let anchor = window.flatMap(Self.center(of:)) ?? WindowEngine.focusedWindowCenter() ?? NSEvent.mouseLocation
        WindowEngine.snap(target, at: anchor, window: window) { [weak self] result in
            switch result {
            case .success(let frame):
                self?.present(.move, cocoaFrame: frame)
            case .failure(let error):
                NSLog("Dowey: shortcut to \(target.displayName) failed — \(error.description)")
            }
        }
    }
}

// MARK: - Picking a window

extension GlobeShortcuts {

    /// How many of the best-placed windows to try before giving up. A listed
    /// window with no AX twin (a helper app's backdrop, say) is skipped, but
    /// each try is an AX round trip, so the search stops somewhere.
    private static let selectionAttempts = 6

    /// Focuses the nearest window `direction` of the current one — the one
    /// picked last in this hold, else the focused window, else the pointer —
    /// and outlines it. Beeps when there is nothing that way.
    fileprivate func select(toward direction: Direction) {
        willAct?()
        let current: CGRect
        if let window = selected ?? WindowEngine.focusedWindow(), let frame = WindowEngine.frame(of: window) {
            current = frame
        } else {
            current = WindowEngine.cocoaToAccessibility(CGRect(origin: NSEvent.mouseLocation, size: .zero))
        }

        let listed = WindowEngine.listedWindows()
        let ranked = WindowNavigation.ranked(from: current, toward: direction, among: listed.map(\.frame))
        for index in ranked.prefix(Self.selectionAttempts) {
            guard let window = WindowEngine.element(for: listed[index]) else { continue }
            WindowEngine.focus(window)
            selected = window
            present(.pick, cocoaFrame: WindowEngine.cocoaToAccessibility(listed[index].frame))
            return
        }
        NSSound.beep()
    }

    // MARK: Pick and Move

    /// ⌘ went down or up while Globe is held. Down shows Pick on the window
    /// that would be picked from; up turns whatever is outlined into Move.
    fileprivate func commandChanged(_ down: Bool) {
        guard globeDown, Settings.shared.windowSelection else { return }
        if down {
            willAct?()
            presentOnCurrentWindow(.pick)
        } else if mode == .pick {
            presentOnCurrentWindow(.move)
        }
    }

    private func presentOnCurrentWindow(_ mode: KeyboardMode) {
        guard let window = selected ?? WindowEngine.focusedWindow(),
              let frame = WindowEngine.frame(of: window) else {
            self.mode = mode
            return
        }
        present(mode, cocoaFrame: WindowEngine.cocoaToAccessibility(frame))
    }

    /// Outlines `cocoaFrame` in `mode`'s style. If Globe is already up — a
    /// snap that landed after the release — it shows briefly and fades.
    fileprivate func present(_ mode: KeyboardMode, cocoaFrame: CGRect) {
        self.mode = mode
        overlay.show(mode, on: cocoaFrame, briefly: !globeDown)
        guard globeDown, releaseWatchdog == nil else { return }
        let watchdog = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            if !CGEventSource.keyState(.combinedSessionState, key: GlobeShortcuts.globeKeyCode) {
                self?.endKeyboardMode()
            }
        }
        watchdog.tolerance = 0.05
        RunLoop.main.add(watchdog, forMode: .common)
        releaseWatchdog = watchdog
    }

    fileprivate func endKeyboardMode() {
        releaseWatchdog?.invalidate()
        releaseWatchdog = nil
        mode = nil
        overlay.hide()
    }

    fileprivate static func center(of window: AXUIElement) -> CGPoint? {
        guard let frame = WindowEngine.frame(of: window) else { return nil }
        let cocoa = WindowEngine.cocoaToAccessibility(frame)
        return CGPoint(x: cocoa.midX, y: cocoa.midY)
    }
}

private extension ArrowKey {
    var direction: Direction {
        switch self {
        case .up:    return .up
        case .down:  return .down
        case .left:  return .left
        case .right: return .right
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

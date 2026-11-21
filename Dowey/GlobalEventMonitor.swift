//
//  GlobalEventMonitor.swift
//  Dowey
//
//  Owns the gesture state machine. Observe-only NSEvent monitors — no
//  CGEventTap — because the Globe key's system action is disabled by the user
//  (see README), so nothing needs to be consumed. Globe + arrow shortcuts do
//  need to consume, and live in GlobeShortcuts for that reason.
//

import AppKit
import CoreGraphics

/// Wraps the global + local halves of an NSEvent monitor pair.
///
/// The local half exists so a gesture cannot get stranded: global monitors stop
/// delivering while Dowey itself is frontmost (e.g. its permission alert is up),
/// and a missed Globe-key *release* would leave the state machine armed forever.
private final class EventMonitorPair {

    private var globalToken: Any?
    private var localToken: Any?

    init(mask: NSEvent.EventTypeMask, handler: @escaping (NSEvent) -> Void) {
        globalToken = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler)
        localToken = NSEvent.addLocalMonitorForEvents(matching: mask) { event in
            handler(event)
            return event
        }
    }

    deinit { stop() }

    func stop() {
        if let globalToken { NSEvent.removeMonitor(globalToken) }
        if let localToken { NSEvent.removeMonitor(localToken) }
        globalToken = nil
        localToken = nil
    }
}

final class GlobalEventMonitor {

    /// Globe / Fn. Reported through `flagsChanged` with `.function` set.
    private static let globeKeyCode: UInt16 = 63
    private static let escapeKeyCode: UInt16 = 53

    private enum State {
        case idle
        /// Globe held, cursor still within the deadzone — release means maximize.
        case armed(origin: CGPoint)
        /// Cursor past the deadzone — release means a directional snap.
        case tracking(origin: CGPoint, zone: Zone)

        var origin: CGPoint? {
            switch self {
            case .idle: return nil
            case .armed(let origin): return origin
            case .tracking(let origin, _): return origin
            }
        }

        var isActive: Bool {
            if case .idle = self { return false }
            return true
        }
    }

    private var state: State = .idle

    /// Always running: one flagsChanged monitor. This is the app's entire idle
    /// footprint — everything else is installed on key-down and torn down on
    /// key-up, so no mouse handler runs while idle.
    private var triggerMonitor: EventMonitorPair?

    /// Installed only between key-down and commit/cancel.
    private var gestureMonitors: [EventMonitorPair] = []

    /// Mission Control (and real Space switches) steal the trackpad away from
    /// Dowey without ever delivering the Globe-key release — a 4-finger swipe
    /// up while armed would otherwise strand the HUD on screen forever. This
    /// notification fires for both cases, so treat it like Escape.
    private var spaceChangeObserver: NSObjectProtocol?

    /// Last-resort safety net: reads the Globe key's actual hardware state
    /// instead of trusting any event to arrive. Whatever swallows the
    /// flagsChanged release (Mission Control, Spotlight, a screen saver...)
    /// cannot swallow this, because it isn't listening for a delivered event
    /// at all — it asks the HID system directly. Runs only while armed.
    private var releaseWatchdog: Timer?

    /// Hides the ring after a shortcut has lit it. Never set during a gesture.
    private var flashTimer: Timer?

    /// A window picked with 🌐 + ⌥ + arrow is outlined until Globe goes up.
    private var outliningSelection = false

    private let hud = RadialHUDController()
    private let preview = PreviewOverlayController()

    /// Read from the store once per gesture, at key-down. Building a `Style`
    /// resolves the tint color, so doing it on every zone change would be
    /// work repeated for an answer that cannot change mid-hold.
    private var style = Style.default

    /// `NSScreen.screens` allocates a bridged array on every access. During a
    /// sweep the cursor almost always stays on one display, so the lookup is
    /// cached for the gesture and redone only when the cursor actually leaves it.
    private var cachedScreen: NSScreen?

    // MARK: - Lifecycle

    func start() {
        guard triggerMonitor == nil else { return }
        triggerMonitor = EventMonitorPair(mask: [.flagsChanged]) { [weak self] event in
            self?.handleFlagsChanged(event)
        }
    }

    func stop() {
        cancel()
        triggerMonitor?.stop()
        triggerMonitor = nil
    }

    // MARK: - Trigger

    private func handleFlagsChanged(_ event: NSEvent) {
        guard event.keyCode == Self.globeKeyCode else { return }

        // flagsChanged carries no up/down flag — the key is down iff `.function`
        // is still present in the post-event modifier set.
        let isDown = event.modifierFlags.contains(.function)

        switch (isDown, state.isActive) {
        case (true, false):  arm()
        case (false, true):  commit()
        case (false, false): hideSelectionOutline()
        default:             break
        }
    }

    private func arm() {
        flashTimer?.invalidate()
        flashTimer = nil
        outliningSelection = false
        let origin = NSEvent.mouseLocation
        state = .armed(origin: origin)
        style = Settings.shared.style

        // Shown immediately with the center circle lit and the full-screen
        // destination already outlined, so the maximize target gets the same
        // preview treatment as the eight directional zones.
        hud.show(at: origin, style: style)
        showMaximizePreview(near: origin)

        gestureMonitors = [
            EventMonitorPair(mask: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]) { [weak self] _ in
                self?.handleMouseMoved()
            },
            EventMonitorPair(mask: [.keyDown]) { [weak self] event in
                guard event.keyCode == Self.escapeKeyCode else { return }
                self?.cancel()
            }
        ]

        spaceChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.cancel()
        }

        let watchdog = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in
            guard let self, self.state.isActive else { return }
            if !CGEventSource.keyState(.combinedSessionState, key: Self.globeKeyCode) {
                self.cancel()
            }
        }
        // A safety net, not a clock: firing a little late costs nothing, and
        // the slack lets the system fold these wakeups into ones it was
        // already going to take.
        watchdog.tolerance = 0.05
        RunLoop.main.add(watchdog, forMode: .common)
        releaseWatchdog = watchdog
    }

    // MARK: - Tracking

    private func handleMouseMoved() {
        guard let origin = state.origin else { return }
        let location = NSEvent.mouseLocation

        if ZoneMath.isInsideDeadzone(origin: origin, point: location) {
            guard case .tracking = state else { return }
            state = .armed(origin: origin)
            hud.update(activeZone: nil)
            showMaximizePreview(near: location)
            return
        }

        let zone = Zone.forDirection(origin: origin, point: location)

        if case .tracking(_, let currentZone) = state, currentZone == zone {
            return // Same zone: nothing to redraw.
        }

        state = .tracking(origin: origin, zone: zone)
        hud.update(activeZone: zone)

        if let screen = screen(containing: location) {
            preview.show(rect: zone.rect(in: screen.visibleFrame), style: style)
        }
    }

    private func screen(containing point: CGPoint) -> NSScreen? {
        if let cachedScreen, cachedScreen.frame.contains(point) { return cachedScreen }
        cachedScreen = WindowEngine.screen(containing: point)
        return cachedScreen
    }

    /// Outlines the whole visible frame — what a release inside the deadzone
    /// would produce.
    private func showMaximizePreview(near point: CGPoint) {
        guard let screen = screen(containing: point) else { return }
        preview.show(rect: SnapTarget.maximize.rect(in: screen.visibleFrame), style: style)
    }

    // MARK: - Commit / cancel

    private func commit() {
        let target: SnapTarget
        switch state {
        case .idle:                    return
        case .armed:                   target = .maximize
        case .tracking(_, let zone):   target = .zone(zone)
        }

        // Overlays go away before the window moves so the preview never briefly
        // paints on top of the window that just landed under it.
        teardown()

        // Completes on a later run-loop turn only for a window in macOS full
        // screen, which has to leave its Space before it can be placed.
        WindowEngine.snap(target, at: NSEvent.mouseLocation) { result in
            if case .failure(let error) = result {
                NSLog("Dowey: snap to \(target.displayName) failed — \(error.description)")
            }
        }
    }

    /// A Globe + arrow shortcut has fired. The gesture steps aside — Globe is
    /// down, so without this its release would maximize over the shortcut —
    /// and the ring stays up just long enough to show which way the window
    /// went. No destination outline: the window is already there.
    func flash(_ target: SnapTarget) {
        let origin = state.origin ?? NSEvent.mouseLocation
        teardown()

        hud.show(at: origin, style: Settings.shared.style)
        if case .zone(let zone) = target { hud.update(activeZone: zone) }

        let timer = Timer(timeInterval: 0.7, repeats: false) { [weak self] _ in
            self?.hud.hide()
            self?.flashTimer = nil
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        flashTimer = timer
    }

    /// A window was picked from the keyboard. As with `flash`, the gesture
    /// steps aside so letting go of Globe does not maximize it; the picked
    /// window is outlined, drawn even when destination highlights are off,
    /// since without it there is no telling which window has the focus.
    func outlineSelection(_ frame: CGRect) {
        teardown()
        var style = Settings.shared.style
        style.showPreview = true
        preview.show(rect: frame, style: style)
        outliningSelection = true
    }

    private func hideSelectionOutline() {
        guard outliningSelection else { return }
        outliningSelection = false
        preview.hide()
    }

    private func cancel() {
        guard state.isActive else { return }
        teardown()
    }

    private func teardown() {
        flashTimer?.invalidate()
        flashTimer = nil
        for monitor in gestureMonitors { monitor.stop() }
        gestureMonitors.removeAll()
        if let spaceChangeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(spaceChangeObserver)
        }
        spaceChangeObserver = nil
        releaseWatchdog?.invalidate()
        releaseWatchdog = nil
        preview.hide()
        outliningSelection = false
        hud.hide()
        cachedScreen = nil
        state = .idle
    }
}

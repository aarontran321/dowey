//
//  GlobalEventMonitor.swift
//  Dowey
//
//  Owns the gesture state machine. Observe-only NSEvent monitors — no
//  CGEventTap — because the Globe key's system action is disabled by the user
//  (see README), so nothing needs to be consumed.
//

import AppKit

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

    private let hud = RadialHUDController()
    private let preview = PreviewOverlayController()

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
        default:             break
        }
    }

    private func arm() {
        let origin = NSEvent.mouseLocation
        state = .armed(origin: origin)

        // Shown immediately but with no zone lit, so there is no popup flicker
        // when the cursor crosses the deadzone edge.
        hud.show(at: origin)

        gestureMonitors = [
            EventMonitorPair(mask: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]) { [weak self] _ in
                self?.handleMouseMoved()
            },
            EventMonitorPair(mask: [.keyDown]) { [weak self] event in
                guard event.keyCode == Self.escapeKeyCode else { return }
                self?.cancel()
            }
        ]
    }

    // MARK: - Tracking

    private func handleMouseMoved() {
        guard let origin = state.origin else { return }
        let location = NSEvent.mouseLocation

        if ZoneMath.isInsideDeadzone(origin: origin, point: location) {
            guard case .tracking = state else { return }
            state = .armed(origin: origin)
            hud.update(activeZone: nil)
            preview.hide()
            return
        }

        let zone = Zone.forDirection(origin: origin, point: location)

        if case .tracking(_, let currentZone) = state, currentZone == zone {
            return // Same zone: nothing to redraw.
        }

        state = .tracking(origin: origin, zone: zone)
        hud.update(activeZone: zone)

        if let screen = WindowEngine.screen(containing: location) {
            preview.show(rect: zone.rect(in: screen.visibleFrame), on: screen)
        }
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

        let result = WindowEngine.snap(target, at: NSEvent.mouseLocation)
        if case .failure(let error) = result {
            NSLog("Dowey: snap to \(target.displayName) failed — \(error.description)")
        }
    }

    private func cancel() {
        guard state.isActive else { return }
        teardown()
    }

    private func teardown() {
        for monitor in gestureMonitors { monitor.stop() }
        gestureMonitors.removeAll()
        preview.hide()
        hud.hide()
        state = .idle
    }
}

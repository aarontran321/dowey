//
//  WindowEngine.swift
//  Dowey
//
//  Accessibility-API window manipulation. One entry point: `snap(_:at:)`.
//

import AppKit
import ApplicationServices

enum WindowEngineError: Error, CustomStringConvertible {
    case accessibilityNotTrusted
    case noFrontmostApplication
    case noFocusedWindow
    case noTargetScreen
    case fullScreenNotExitable
    case axFailure(AXError)

    var description: String {
        switch self {
        case .accessibilityNotTrusted: return "Accessibility permission not granted"
        case .noFrontmostApplication:  return "No frontmost application"
        case .noFocusedWindow:         return "Frontmost app has no focused window"
        case .noTargetScreen:          return "No screen contains the cursor"
        case .fullScreenNotExitable:   return "Window is full screen and refuses to leave it"
        case .axFailure(let error):    return "Accessibility API error \(error.rawValue)"
        }
    }
}

enum WindowEngine {

    // MARK: - Screens

    /// The screen a gesture acts on: whichever one contains the cursor, not the
    /// one the window currently lives on.
    static func screen(containing point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
    }

    static func visibleFrame(containing point: CGPoint) -> CGRect? {
        screen(containing: point)?.visibleFrame
    }

    /// Center of the frontmost app's focused window, in Cocoa screen space —
    /// where a keyboard shortcut anchors its choice of screen.
    static func focusedWindowCenter() -> CGPoint? {
        guard AXIsProcessTrusted(),
              case .success(let window) = focusedWindowOfFrontmostApp(),
              let axFrame = frame(of: window) else { return nil }
        // The flip is its own inverse, so it converts back just as well.
        let frame = cocoaToAccessibility(axFrame)
        return CGPoint(x: frame.midX, y: frame.midY)
    }

    // MARK: - Public entry point

    /// Moves the frontmost app's focused window to `target`.
    ///
    /// Asynchronous only when the window is in macOS full screen: that window
    /// ignores position and size until it leaves its own Space, so the exit is
    /// asked for first and the frame is applied once the window settles. Every
    /// other window is placed synchronously, before this call returns.
    static func snap(_ target: SnapTarget,
                     at mouseLocation: CGPoint,
                     completion: ((Result<CGRect, WindowEngineError>) -> Void)? = nil) {
        guard AXIsProcessTrusted() else {
            completion?(.failure(.accessibilityNotTrusted))
            return
        }

        let window: AXUIElement
        switch focusedWindowOfFrontmostApp() {
        case .failure(let error):
            completion?(.failure(error))
            return
        case .success(let element):
            window = element
        }

        // A hung target app would otherwise block these (synchronous) AX calls
        // for the system default of 6s, freezing our commit path with it.
        AXUIElementSetMessagingTimeout(window, 1.0)

        guard isFullScreen(window) else {
            completion?(place(target, for: window, at: mouseLocation))
            return
        }

        guard isSettable(kAXFullScreenAttribute, of: window),
              AXUIElementSetAttributeValue(window, kAXFullScreenAttribute, kCFBooleanFalse) == .success else {
            completion?(.failure(.fullScreenNotExitable))
            return
        }

        // Leaving full screen is an animated Space switch: the window keeps
        // moving for several frames after the attribute flips, and a frame set
        // during that window is overwritten by the restore animation. The
        // destination is computed after the window settles too — `visibleFrame`
        // is only the desktop's once the desktop is back.
        whenSettled(window) { settled in
            guard settled else {
                completion?(.failure(.fullScreenNotExitable))
                return
            }
            completion?(place(target, for: window, at: mouseLocation))
        }
    }

    private static func place(_ target: SnapTarget,
                              for window: AXUIElement,
                              at mouseLocation: CGPoint) -> Result<CGRect, WindowEngineError> {
        guard let visible = visibleFrame(containing: mouseLocation) else { return .failure(.noTargetScreen) }
        let destination = target.rect(in: visible)
        if let error = setFrame(destination, for: window) { return .failure(error) }
        return .success(destination)
    }

    // MARK: - Full screen

    /// `kAXFullScreenAttribute` is the green-button state, not our maximize:
    /// true means the window owns a Space of its own.
    private static let kAXFullScreenAttribute = "AXFullScreen" as CFString

    private static func isFullScreen(_ window: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXFullScreenAttribute, &value) == .success,
              let value, CFGetTypeID(value) == CFBooleanGetTypeID() else {
            // Apps that never adopted full screen don't publish the attribute.
            return false
        }
        return CFBooleanGetValue((value as! CFBoolean))
    }

    private static func isSettable(_ attribute: CFString, of window: AXUIElement) -> Bool {
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(window, attribute, &settable) == .success else { return false }
        return settable.boolValue
    }

    /// Polls until the window is out of full screen and has held the same frame
    /// for two consecutive samples, then calls back on the main queue. Gives up
    /// after `timeout`, which is the case where the app took the attribute and
    /// did nothing with it.
    private static func whenSettled(_ window: AXUIElement,
                                    interval: TimeInterval = 0.05,
                                    timeout: TimeInterval = 1.5,
                                    _ body: @escaping (Bool) -> Void) {
        let deadline = Date().addingTimeInterval(timeout)
        var lastFrame: CGRect?

        let timer = Timer(timeInterval: interval, repeats: true) { timer in
            let expired = Date() >= deadline

            if !isFullScreen(window), let current = frame(of: window) {
                if current == lastFrame {
                    timer.invalidate()
                    body(true)
                    return
                }
                lastFrame = current
            }

            if expired {
                timer.invalidate()
                body(false)
            }
        }

        // `.common` so a menu tracking or a resize loop cannot stall the exit.
        RunLoop.main.add(timer, forMode: .common)
    }

    // MARK: - AX plumbing

    private static func focusedWindowOfFrontmostApp() -> Result<AXUIElement, WindowEngineError> {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return .failure(.noFrontmostApplication)
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        // A hung target app would otherwise block this (synchronous) AX call for
        // the system default of 6s, freezing our commit path with it.
        AXUIElementSetMessagingTimeout(appElement, 1.0)

        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &value)
        guard status == .success else {
            // .cannotComplete here is the usual symptom of a revoked Accessibility grant.
            return .failure(.axFailure(status))
        }
        guard let element = value, CFGetTypeID(element) == AXUIElementGetTypeID() else {
            return .failure(.noFocusedWindow)
        }

        return .success(element as! AXUIElement)
    }

    /// The window's own frame, in Accessibility coordinates. Used only to watch
    /// for movement, so it is never converted back.
    private static func frame(of window: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
            return nil
        }

        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue((positionValue as! AXValue), .cgPoint, &origin),
              AXValueGetValue((sizeValue as! AXValue), .cgSize, &size) else {
            return nil
        }
        return CGRect(origin: origin, size: size)
    }

    /// `rect` is in Cocoa screen space (bottom-left origin, y-up).
    private static func setFrame(_ rect: CGRect, for window: AXUIElement) -> WindowEngineError? {
        let axRect = cocoaToAccessibility(rect)

        var origin = axRect.origin
        var size = axRect.size

        guard let positionValue = AXValueCreate(.cgPoint, &origin),
              let sizeValue = AXValueCreate(.cgSize, &size) else {
            return .axFailure(.failure)
        }

        // Both attributes are set without returning to the run loop, so the
        // window server composites one frame change rather than a move-then-resize.
        let positionStatus = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
        let sizeStatus = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)

        // Apps that enforce a minimum size can push the window back off-origin
        // while honoring the resize. Re-asserting the position (still in this
        // same run-loop turn) lands those windows flush against the zone edge.
        if positionStatus == .success && sizeStatus == .success {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
        }

        if positionStatus != .success { return .axFailure(positionStatus) }
        if sizeStatus != .success { return .axFailure(sizeStatus) }
        return nil
    }

    /// Cocoa screen coordinates are bottom-left origin and y-up; the
    /// Accessibility API is top-left origin and y-down, anchored on the
    /// *primary* display (`NSScreen.screens[0]`), not on `NSScreen.main`.
    static func cocoaToAccessibility(_ rect: CGRect) -> CGRect {
        guard let primary = NSScreen.screens.first else { return rect }
        let flippedY = primary.frame.maxY - rect.maxY
        return CGRect(x: rect.minX, y: flippedY, width: rect.width, height: rect.height)
    }
}

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
    case axFailure(AXError)

    var description: String {
        switch self {
        case .accessibilityNotTrusted: return "Accessibility permission not granted"
        case .noFrontmostApplication:  return "No frontmost application"
        case .noFocusedWindow:         return "Frontmost app has no focused window"
        case .noTargetScreen:          return "No screen contains the cursor"
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

    // MARK: - Public entry point

    @discardableResult
    static func snap(_ target: SnapTarget, at mouseLocation: CGPoint) -> Result<CGRect, WindowEngineError> {
        guard AXIsProcessTrusted() else { return .failure(.accessibilityNotTrusted) }
        guard let visible = visibleFrame(containing: mouseLocation) else { return .failure(.noTargetScreen) }

        let destination = target.rect(in: visible)

        switch focusedWindowOfFrontmostApp() {
        case .failure(let error):
            return .failure(error)
        case .success(let window):
            if let error = setFrame(destination, for: window) { return .failure(error) }
            return .success(destination)
        }
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

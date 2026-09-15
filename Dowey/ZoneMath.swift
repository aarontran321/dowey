//
//  ZoneMath.swift
//  Dowey
//
//  Pure geometry. No AppKit state, no side effects — everything here is a
//  function of its arguments so it can be unit-tested without a running app.
//

import Foundation
import CoreGraphics

enum ZoneMath {

    /// Radius, in screen points, inside which a release means "maximize"
    /// instead of a directional snap.
    static let deadzoneRadius: CGFloat = 20

    /// Squared-distance comparison keeps the hot path (every mouse-moved
    /// event while armed) free of a sqrt.
    static func isInsideDeadzone(origin: CGPoint, point: CGPoint) -> Bool {
        let dx = point.x - origin.x
        let dy = point.y - origin.y
        return (dx * dx + dy * dy) < (deadzoneRadius * deadzoneRadius)
    }

    /// Standard math angle in degrees: 0° = East, increasing counterclockwise.
    ///
    /// Callers must pass points in `NSEvent.mouseLocation` space (bottom-left
    /// origin, y-up). Mixing in a y-down coordinate system here would mirror
    /// every vertical zone, so no flipping happens anywhere in this file.
    static func angleDegrees(from origin: CGPoint, to point: CGPoint) -> CGFloat {
        let radians = atan2(point.y - origin.y, point.x - origin.x)
        return normalizedDegrees(radians * 180 / .pi)
    }

    /// Folds any angle into [0, 360).
    static func normalizedDegrees(_ degrees: CGFloat) -> CGFloat {
        let wrapped = degrees.truncatingRemainder(dividingBy: 360)
        return wrapped < 0 ? wrapped + 360 : wrapped
    }
}

// MARK: - Zones

enum Zone: CaseIterable {
    case right
    case topRight
    case topLeft
    case left
    case bottomLeft
    case bottomRight

    /// Half-open arc `[start, end)` in normalized math degrees.
    ///
    /// `right` is stored as 315...405 rather than -45...45 so that every zone
    /// has `end > start`; the lookup and the HUD both rely on that ordering.
    var arc: (start: CGFloat, end: CGFloat) {
        switch self {
        case .right:       return (315, 405)
        case .topRight:    return (45, 90)
        case .topLeft:     return (90, 135)
        case .left:        return (135, 225)
        case .bottomLeft:  return (225, 270)
        case .bottomRight: return (270, 315)
        }
    }

    var displayName: String {
        switch self {
        case .right:       return "Right"
        case .topRight:    return "Top-Right"
        case .topLeft:     return "Top-Left"
        case .left:        return "Left"
        case .bottomLeft:  return "Bottom-Left"
        case .bottomRight: return "Bottom-Right"
        }
    }

    /// Maps an angle (any representation — it is normalized first) to a zone.
    static func forAngle(degrees: CGFloat) -> Zone {
        let angle = ZoneMath.normalizedDegrees(degrees)

        // `right` wraps across 0°, so it is tested as two half-open spans.
        if angle >= 315 || angle < 45 { return .right }

        for zone in [Zone.topRight, .topLeft, .left, .bottomLeft, .bottomRight] {
            let arc = zone.arc
            if angle >= arc.start && angle < arc.end { return zone }
        }

        // Unreachable for a normalized angle; `right` is the documented wrap zone.
        return .right
    }

    static func forDirection(origin: CGPoint, point: CGPoint) -> Zone {
        forAngle(degrees: ZoneMath.angleDegrees(from: origin, to: point))
    }

    /// Destination rect in the same (bottom-left origin) space as `visibleFrame`.
    func rect(in visibleFrame: CGRect) -> CGRect {
        let halfWidth = visibleFrame.width / 2
        let halfHeight = visibleFrame.height / 2
        let midX = visibleFrame.minX + halfWidth
        let midY = visibleFrame.minY + halfHeight

        switch self {
        case .right:
            return CGRect(x: midX, y: visibleFrame.minY, width: halfWidth, height: visibleFrame.height)
        case .left:
            return CGRect(x: visibleFrame.minX, y: visibleFrame.minY, width: halfWidth, height: visibleFrame.height)
        case .topRight:
            return CGRect(x: midX, y: midY, width: halfWidth, height: halfHeight)
        case .topLeft:
            return CGRect(x: visibleFrame.minX, y: midY, width: halfWidth, height: halfHeight)
        case .bottomLeft:
            return CGRect(x: visibleFrame.minX, y: visibleFrame.minY, width: halfWidth, height: halfHeight)
        case .bottomRight:
            return CGRect(x: midX, y: visibleFrame.minY, width: halfWidth, height: halfHeight)
        }
    }
}

// MARK: - Snap target

/// What a committed gesture resolves to. Maximize is deliberately just another
/// target rect, not a separate code path in WindowEngine.
enum SnapTarget: Equatable {
    case zone(Zone)
    case maximize

    func rect(in visibleFrame: CGRect) -> CGRect {
        switch self {
        case .zone(let zone): return zone.rect(in: visibleFrame)
        case .maximize:       return visibleFrame
        }
    }

    var displayName: String {
        switch self {
        case .zone(let zone): return zone.displayName
        case .maximize:       return "Maximize"
        }
    }
}

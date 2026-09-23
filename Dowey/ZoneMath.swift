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
    ///
    /// Settable because the user can change it, but written from exactly one
    /// place — `Settings.triggerDistance` — so this file keeps no dependency on
    /// UserDefaults and stays testable on its own.
    static let defaultDeadzoneRadius: CGFloat = 20
    static var deadzoneRadius: CGFloat = defaultDeadzoneRadius

    /// Which set of zones the ring offers. Written from exactly one place —
    /// `Settings.sixZones` — for the same reason as `deadzoneRadius`.
    static var layout: ZoneLayout = .eight

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

/// How many directions the ring offers.
///
/// `six` is Dowey's original layout, kept because the eight-zone table buys Top
/// and Bottom by narrowing everything else: a user who never flicks vertically
/// is paying for zones they do not want with tolerance on the ones they do.
enum ZoneLayout: String, CaseIterable {
    case eight, six

    var displayName: String {
        switch self {
        case .eight: return "Eight zones"
        case .six:   return "Six zones"
        }
    }
}

enum Zone: CaseIterable {
    case right
    case topRight
    case top
    case topLeft
    case left
    case bottomLeft
    case bottom
    case bottomRight

    /// Half-open arc `[start, end)` in normalized math degrees.
    typealias Arc = (start: CGFloat, end: CGFloat)

    /// Every zone of `layout`, with its arc, walking counterclockwise from
    /// Right. This is the single source of truth: the lookup and every ring
    /// design read it, so neither can disagree with the other about where a
    /// zone begins, and a zone absent from a layout simply is not in the list.
    ///
    /// The eight-zone widths are deliberately unequal. A blind flick's accuracy
    /// plateaus around ±20°, so the 90° `left` and `right` hold in the six-zone
    /// table was angle held for no return — 50° still hits without looking, and
    /// the harvested degrees pay for `top` and `bottom`. The diagonals keep 45°
    /// because a diagonal is the hardest direction to estimate, and the vertical
    /// halves take 40° rather than the leftovers because a vertical flick is an
    /// arm movement, not a wrist one. Nothing drops below ±20°.
    ///
    /// `right` wraps across 0° in both tables and is stored past 360 so that
    /// every arc has `end > start`; callers compare against the `+360` alias.
    static func arcs(in layout: ZoneLayout) -> [(zone: Zone, arc: Arc)] {
        switch layout {
        case .eight:
            return [(.right,       (335, 385)),
                    (.topRight,    (25, 70)),
                    (.top,         (70, 110)),
                    (.topLeft,     (110, 155)),
                    (.left,        (155, 205)),
                    (.bottomLeft,  (205, 250)),
                    (.bottom,      (250, 290)),
                    (.bottomRight, (290, 335))]
        case .six:
            return [(.right,       (315, 405)),
                    (.topRight,    (45, 90)),
                    (.topLeft,     (90, 135)),
                    (.left,        (135, 225)),
                    (.bottomLeft,  (225, 270)),
                    (.bottomRight, (270, 315))]
        }
    }

    /// The live table, for the layout the user has chosen.
    static var activeArcs: [(zone: Zone, arc: Arc)] { arcs(in: ZoneMath.layout) }

    static var active: [Zone] { activeArcs.map(\.zone) }

    var displayName: String {
        switch self {
        case .right:       return "Right"
        case .topRight:    return "Top-Right"
        case .top:         return "Top"
        case .topLeft:     return "Top-Left"
        case .left:        return "Left"
        case .bottomLeft:  return "Bottom-Left"
        case .bottom:      return "Bottom"
        case .bottomRight: return "Bottom-Right"
        }
    }

    /// Maps an angle (any representation — it is normalized first) to a zone.
    ///
    /// The `+360` alias is what lets the wrapping `right` arc be tested by the
    /// same comparison as every other zone.
    static func forAngle(degrees: CGFloat) -> Zone {
        let angle = ZoneMath.normalizedDegrees(degrees)

        for (zone, arc) in activeArcs {
            if (angle >= arc.start && angle < arc.end)
                || (angle + 360 >= arc.start && angle + 360 < arc.end) {
                return zone
            }
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
        case .top:
            return CGRect(x: visibleFrame.minX, y: midY, width: visibleFrame.width, height: halfHeight)
        case .bottom:
            return CGRect(x: visibleFrame.minX, y: visibleFrame.minY, width: visibleFrame.width, height: halfHeight)
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

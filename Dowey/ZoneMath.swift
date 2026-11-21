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
    /// `Settings.eightZones` — for the same reason as `deadzoneRadius`.
    static var layout: ZoneLayout = .six

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
/// `six` is Dowey's original layout and the default: the eight-zone table buys
/// Top and Bottom by narrowing everything else, so a user who never flicks
/// vertically would pay for zones they do not want with tolerance on the ones
/// they do. `eight` is opt-in from Settings.
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
        case .eight: return eightArcs
        case .six:   return sixArcs
        }
    }

    // Built once. `forAngle` runs on every mouse-moved event outside the
    // deadzone, and a literal in `arcs(in:)` would allocate a fresh array each
    // time; these are shared, so a lookup allocates nothing.
    private static let eightArcs: [(zone: Zone, arc: Arc)] = [
        (.right,       (335, 385)),
        (.topRight,    (25, 70)),
        (.top,         (70, 110)),
        (.topLeft,     (110, 155)),
        (.left,        (155, 205)),
        (.bottomLeft,  (205, 250)),
        (.bottom,      (250, 290)),
        (.bottomRight, (290, 335)),
    ]

    private static let sixArcs: [(zone: Zone, arc: Arc)] = [
        (.right,       (315, 405)),
        (.topRight,    (45, 90)),
        (.topLeft,     (90, 135)),
        (.left,        (135, 225)),
        (.bottomLeft,  (225, 270)),
        (.bottomRight, (270, 315)),
    ]

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

// MARK: - Corners from two arrows

/// One arrow key's direction, with no AppKit or settings attached.
enum Direction: CaseIterable {
    case up, down, left, right

    var isVertical: Bool { self == .up || self == .down }

    /// The corner two held arrows name, or nil when they do not make one
    /// (the same key twice, or ← with →).
    static func corner(_ a: Direction, _ b: Direction) -> Zone? {
        guard a.isVertical != b.isVertical else { return nil }
        let vertical = a.isVertical ? a : b
        let horizontal = a.isVertical ? b : a
        switch (vertical, horizontal) {
        case (.up, .left):    return .topLeft
        case (.up, .right):   return .topRight
        case (.down, .left):  return .bottomLeft
        case (.down, .right): return .bottomRight
        default:              return nil
        }
    }
}

// MARK: - Window navigation

/// Which window an arrow points at, from the one that has focus.
///
/// Rects are in window-server space — top-left origin, y grows downward —
/// because that is what both `CGWindowListCopyWindowInfo` and the
/// Accessibility API hand back, so nothing is flipped on the way in. In this
/// space `up` means a smaller y.
enum WindowNavigation {

    /// Indices into `candidates`, best first, of the windows lying `direction`
    /// of `current`. Judged by center: a window counts if its center is past
    /// `current`'s along the arrow and no more than twice as far off to the
    /// side as it is ahead (a ~63° cone each way), so → from a top-left window
    /// finds the top-right one before the bottom-right one. Off-axis distance
    /// costs double, which keeps the pick on the row or column you are in.
    /// Windows centered on `current` (stacked exactly behind it) never count.
    static func ranked(from current: CGRect,
                       toward direction: Direction,
                       among candidates: [CGRect]) -> [Int] {
        let origin = CGPoint(x: current.midX, y: current.midY)

        let scored: [(index: Int, score: CGFloat)] = candidates.enumerated().compactMap { index, rect in
            let dx = rect.midX - origin.x
            let dy = rect.midY - origin.y
            let ahead: CGFloat
            let aside: CGFloat
            switch direction {
            case .right: ahead = dx;  aside = abs(dy)
            case .left:  ahead = -dx; aside = abs(dy)
            case .down:  ahead = dy;  aside = abs(dx)
            case .up:    ahead = -dy; aside = abs(dx)
            }
            guard ahead > 1, aside <= ahead * 2 else { return nil }
            return (index, ahead + aside * 2)
        }

        // Ties go to the earlier candidate: callers pass windows front to
        // back, so of two equally placed windows the one you can see wins.
        return scored.sorted { ($0.score, $0.index) < ($1.score, $1.index) }.map(\.index)
    }
}

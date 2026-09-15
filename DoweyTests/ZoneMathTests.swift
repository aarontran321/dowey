//
//  ZoneMathTests.swift
//  DoweyTests
//
//  ZoneMath.swift is compiled directly into this bundle (no app host), so the
//  suite runs without launching Dowey or touching any permission.
//

import XCTest
import CoreGraphics

final class ZoneMathTests: XCTestCase {

    // MARK: - Boundary angles (§2)

    /// Every boundary is half-open `[start, end)`: the boundary value belongs to
    /// the zone that starts there.
    func testZoneBoundaries() {
        XCTAssertEqual(Zone.forAngle(degrees: 45), .topRight)
        XCTAssertEqual(Zone.forAngle(degrees: 90), .topLeft)
        XCTAssertEqual(Zone.forAngle(degrees: 135), .left)
        XCTAssertEqual(Zone.forAngle(degrees: 225), .bottomLeft)
        XCTAssertEqual(Zone.forAngle(degrees: 270), .bottomRight)
        XCTAssertEqual(Zone.forAngle(degrees: 315), .right)
    }

    func testJustBelowEachBoundary() {
        let epsilon: CGFloat = 0.001
        XCTAssertEqual(Zone.forAngle(degrees: 45 - epsilon), .right)
        XCTAssertEqual(Zone.forAngle(degrees: 90 - epsilon), .topRight)
        XCTAssertEqual(Zone.forAngle(degrees: 135 - epsilon), .topLeft)
        XCTAssertEqual(Zone.forAngle(degrees: 225 - epsilon), .left)
        XCTAssertEqual(Zone.forAngle(degrees: 270 - epsilon), .bottomLeft)
        XCTAssertEqual(Zone.forAngle(degrees: 315 - epsilon), .bottomRight)
    }

    func testWraparound() {
        XCTAssertEqual(Zone.forAngle(degrees: 0), .right)
        XCTAssertEqual(Zone.forAngle(degrees: 360), .right)
        XCTAssertEqual(Zone.forAngle(degrees: 359.999), .right)
        XCTAssertEqual(Zone.forAngle(degrees: -45), .right, "-45° is the start of the right zone")
        XCTAssertEqual(Zone.forAngle(degrees: -44.999), .right)
        XCTAssertEqual(Zone.forAngle(degrees: -45.001), .bottomRight)
        XCTAssertEqual(Zone.forAngle(degrees: 720), .right)
        XCTAssertEqual(Zone.forAngle(degrees: -720), .right)
        XCTAssertEqual(Zone.forAngle(degrees: 405), .topRight, "405° normalizes to 45°")
    }

    func testMidpointsOfEveryZone() {
        XCTAssertEqual(Zone.forAngle(degrees: 0), .right)
        XCTAssertEqual(Zone.forAngle(degrees: 67.5), .topRight)
        XCTAssertEqual(Zone.forAngle(degrees: 112.5), .topLeft)
        XCTAssertEqual(Zone.forAngle(degrees: 180), .left)
        XCTAssertEqual(Zone.forAngle(degrees: 247.5), .bottomLeft)
        XCTAssertEqual(Zone.forAngle(degrees: 292.5), .bottomRight)
    }

    func testNormalizedDegrees() {
        XCTAssertEqual(ZoneMath.normalizedDegrees(0), 0, accuracy: 0.0001)
        XCTAssertEqual(ZoneMath.normalizedDegrees(360), 0, accuracy: 0.0001)
        XCTAssertEqual(ZoneMath.normalizedDegrees(-90), 270, accuracy: 0.0001)
        XCTAssertEqual(ZoneMath.normalizedDegrees(450), 90, accuracy: 0.0001)
        XCTAssertEqual(ZoneMath.normalizedDegrees(-450), 270, accuracy: 0.0001)
    }

    // MARK: - Angle from points (y-up, bottom-left origin)

    func testAngleFromPointsUsesYUpConvention() {
        let origin = CGPoint(x: 100, y: 100)
        XCTAssertEqual(ZoneMath.angleDegrees(from: origin, to: CGPoint(x: 200, y: 100)), 0, accuracy: 0.0001)
        XCTAssertEqual(ZoneMath.angleDegrees(from: origin, to: CGPoint(x: 100, y: 200)), 90, accuracy: 0.0001)
        XCTAssertEqual(ZoneMath.angleDegrees(from: origin, to: CGPoint(x: 0, y: 100)), 180, accuracy: 0.0001)
        XCTAssertEqual(ZoneMath.angleDegrees(from: origin, to: CGPoint(x: 100, y: 0)), 270, accuracy: 0.0001)
    }

    /// Moving up must select an upper zone — the regression test for accidentally
    /// mixing in a y-down (CGEvent-style) coordinate system.
    func testUpwardMovementSelectsTopZones() {
        let origin = CGPoint(x: 500, y: 500)
        XCTAssertEqual(Zone.forDirection(origin: origin, point: CGPoint(x: 560, y: 590)), .topRight)
        XCTAssertEqual(Zone.forDirection(origin: origin, point: CGPoint(x: 440, y: 590)), .topLeft)
        XCTAssertEqual(Zone.forDirection(origin: origin, point: CGPoint(x: 440, y: 410)), .bottomLeft)
        XCTAssertEqual(Zone.forDirection(origin: origin, point: CGPoint(x: 560, y: 410)), .bottomRight)
    }

    /// An exact 45° diagonal sits on a boundary, so it resolves by the half-open
    /// rule rather than to the "nearest looking" corner zone. Pinned here so the
    /// behavior is a decision, not an accident.
    func testExactDiagonalsResolveByHalfOpenRule() {
        let origin = CGPoint(x: 500, y: 500)
        XCTAssertEqual(Zone.forDirection(origin: origin, point: CGPoint(x: 560, y: 560)), .topRight,   "45°")
        XCTAssertEqual(Zone.forDirection(origin: origin, point: CGPoint(x: 440, y: 560)), .left,       "135°")
        XCTAssertEqual(Zone.forDirection(origin: origin, point: CGPoint(x: 440, y: 440)), .bottomLeft, "225°")
        XCTAssertEqual(Zone.forDirection(origin: origin, point: CGPoint(x: 560, y: 440)), .right,      "315°")
    }

    // MARK: - Deadzone

    func testDeadzone() {
        let origin = CGPoint(x: 10, y: 10)
        XCTAssertTrue(ZoneMath.isInsideDeadzone(origin: origin, point: origin))
        XCTAssertTrue(ZoneMath.isInsideDeadzone(origin: origin, point: CGPoint(x: 29, y: 10)))
        XCTAssertFalse(ZoneMath.isInsideDeadzone(origin: origin, point: CGPoint(x: 30, y: 10)),
                       "exactly 20pt away is outside the deadzone")
        XCTAssertFalse(ZoneMath.isInsideDeadzone(origin: origin, point: CGPoint(x: 10, y: 40)))
        // 3-4-5 triangle: 25pt away.
        XCTAssertFalse(ZoneMath.isInsideDeadzone(origin: origin, point: CGPoint(x: 25, y: 30)))
        // 12-16 triangle: 20pt away exactly.
        XCTAssertFalse(ZoneMath.isInsideDeadzone(origin: origin, point: CGPoint(x: 22, y: 26)))
    }

    // MARK: - Destination rects (§2/§3)

    /// A 1000x800 visible frame offset to +100/+50, i.e. a secondary screen with
    /// a menu bar and Dock carved out, to catch any hardcoded origin assumption.
    private let visible = CGRect(x: 100, y: 50, width: 1000, height: 800)

    func testHalfAndQuarterRects() {
        XCTAssertEqual(Zone.left.rect(in: visible), CGRect(x: 100, y: 50, width: 500, height: 800))
        XCTAssertEqual(Zone.right.rect(in: visible), CGRect(x: 600, y: 50, width: 500, height: 800))
        XCTAssertEqual(Zone.topLeft.rect(in: visible), CGRect(x: 100, y: 450, width: 500, height: 400))
        XCTAssertEqual(Zone.topRight.rect(in: visible), CGRect(x: 600, y: 450, width: 500, height: 400))
        XCTAssertEqual(Zone.bottomLeft.rect(in: visible), CGRect(x: 100, y: 50, width: 500, height: 400))
        XCTAssertEqual(Zone.bottomRight.rect(in: visible), CGRect(x: 600, y: 50, width: 500, height: 400))
    }

    func testMaximizeFillsVisibleFrame() {
        XCTAssertEqual(SnapTarget.maximize.rect(in: visible), visible)
    }

    func testZonesTileTheScreenWithoutOverlap() {
        let halves = [Zone.left, .right].map { $0.rect(in: visible) }
        XCTAssertEqual(halves[0].union(halves[1]), visible)
        XCTAssertTrue(halves[0].intersection(halves[1]).isEmpty)

        let quarters = [Zone.topLeft, .topRight, .bottomLeft, .bottomRight].map { $0.rect(in: visible) }
        XCTAssertEqual(quarters.reduce(CGRect.null) { $0.union($1) }, visible)
        for (index, rect) in quarters.enumerated() {
            for other in quarters[(index + 1)...] {
                XCTAssertTrue(rect.intersection(other).isEmpty)
            }
        }
    }

    func testEveryZoneStaysWithinVisibleFrame() {
        for zone in Zone.allCases {
            XCTAssertTrue(visible.contains(zone.rect(in: visible)), "\(zone.displayName) escaped the visible frame")
        }
    }

    // MARK: - Arc table (§4 draws straight off this)

    func testArcsAreContiguousAndCoverTheCircle() {
        let ordered: [Zone] = [.right, .topRight, .topLeft, .left, .bottomLeft, .bottomRight]
        var total: CGFloat = 0
        for zone in ordered {
            let arc = zone.arc
            XCTAssertGreaterThan(arc.end, arc.start, "\(zone.displayName) arc must be forward-ordered")
            total += arc.end - arc.start
        }
        XCTAssertEqual(total, 360, accuracy: 0.0001)
    }

    func testEveryDegreeMapsToAZoneWhoseArcContainsIt() {
        for degree in stride(from: CGFloat(0), to: 360, by: 0.5) {
            let zone = Zone.forAngle(degrees: degree)
            let arc = zone.arc
            // `right` is stored as 315...405, so compare against both the raw
            // angle and its +360 alias.
            let inRange = (degree >= arc.start && degree < arc.end)
                || (degree + 360 >= arc.start && degree + 360 < arc.end)
            XCTAssertTrue(inRange, "\(degree)° mapped to \(zone.displayName), whose arc is \(arc)")
        }
    }
}

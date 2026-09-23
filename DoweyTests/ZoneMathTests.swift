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

    // `ZoneMath.layout` is process-wide, so every test states the layout it
    // means rather than inheriting whatever ran before it.
    override func setUp() {
        super.setUp()
        ZoneMath.layout = .eight
    }

    override func tearDown() {
        ZoneMath.layout = .eight
        super.tearDown()
    }

    // MARK: - Boundary angles (§2)

    /// Every boundary is half-open `[start, end)`: the boundary value belongs to
    /// the zone that starts there.
    func testZoneBoundaries() {
        XCTAssertEqual(Zone.forAngle(degrees: 25), .topRight)
        XCTAssertEqual(Zone.forAngle(degrees: 70), .top)
        XCTAssertEqual(Zone.forAngle(degrees: 110), .topLeft)
        XCTAssertEqual(Zone.forAngle(degrees: 155), .left)
        XCTAssertEqual(Zone.forAngle(degrees: 205), .bottomLeft)
        XCTAssertEqual(Zone.forAngle(degrees: 250), .bottom)
        XCTAssertEqual(Zone.forAngle(degrees: 290), .bottomRight)
        XCTAssertEqual(Zone.forAngle(degrees: 335), .right)
    }

    func testJustBelowEachBoundary() {
        let epsilon: CGFloat = 0.001
        XCTAssertEqual(Zone.forAngle(degrees: 25 - epsilon), .right)
        XCTAssertEqual(Zone.forAngle(degrees: 70 - epsilon), .topRight)
        XCTAssertEqual(Zone.forAngle(degrees: 110 - epsilon), .top)
        XCTAssertEqual(Zone.forAngle(degrees: 155 - epsilon), .topLeft)
        XCTAssertEqual(Zone.forAngle(degrees: 205 - epsilon), .left)
        XCTAssertEqual(Zone.forAngle(degrees: 250 - epsilon), .bottomLeft)
        XCTAssertEqual(Zone.forAngle(degrees: 290 - epsilon), .bottom)
        XCTAssertEqual(Zone.forAngle(degrees: 335 - epsilon), .bottomRight)
    }

    func testWraparound() {
        XCTAssertEqual(Zone.forAngle(degrees: 0), .right)
        XCTAssertEqual(Zone.forAngle(degrees: 360), .right)
        XCTAssertEqual(Zone.forAngle(degrees: 359.999), .right)
        XCTAssertEqual(Zone.forAngle(degrees: -25), .right, "-25° is the start of the right zone")
        XCTAssertEqual(Zone.forAngle(degrees: -24.999), .right)
        XCTAssertEqual(Zone.forAngle(degrees: -25.001), .bottomRight)
        XCTAssertEqual(Zone.forAngle(degrees: 720), .right)
        XCTAssertEqual(Zone.forAngle(degrees: -720), .right)
        XCTAssertEqual(Zone.forAngle(degrees: 385), .topRight, "385° normalizes to 25°")
    }

    /// The eight cardinal/diagonal directions a user actually aims at. Each one
    /// must sit in its own zone with room to spare, which is the point of the
    /// unequal arc widths.
    func testTheDirectionsUsersAimAt() {
        XCTAssertEqual(Zone.forAngle(degrees: 0), .right)
        XCTAssertEqual(Zone.forAngle(degrees: 45), .topRight)
        XCTAssertEqual(Zone.forAngle(degrees: 90), .top)
        XCTAssertEqual(Zone.forAngle(degrees: 135), .topLeft)
        XCTAssertEqual(Zone.forAngle(degrees: 180), .left)
        XCTAssertEqual(Zone.forAngle(degrees: 225), .bottomLeft)
        XCTAssertEqual(Zone.forAngle(degrees: 270), .bottom)
        XCTAssertEqual(Zone.forAngle(degrees: 315), .bottomRight)
    }

    /// No zone may be so narrow that a flick cannot land in it. ±20° is the
    /// floor the arc table was designed around.
    func testNoZoneIsNarrowerThanFortyDegrees() {
        for (zone, arc) in Zone.arcs(in: .eight) {
            let width = arc.end - arc.start
            XCTAssertGreaterThanOrEqual(width, 40, "\(zone.displayName) is only \(width)° wide")
        }
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
        XCTAssertEqual(Zone.forDirection(origin: origin, point: CGPoint(x: 500, y: 590)), .top)
        XCTAssertEqual(Zone.forDirection(origin: origin, point: CGPoint(x: 500, y: 410)), .bottom)
    }

    /// With six zones the exact diagonals sat *on* boundaries and resolved by
    /// the half-open rule, which meant a perfect 135° flick snapped Left. The
    /// eight-zone table centers each diagonal in its own 45° arc instead, so
    /// the surprising case is gone. Pinned so it cannot come back.
    func testExactDiagonalsLandInTheirOwnCorners() {
        let origin = CGPoint(x: 500, y: 500)
        XCTAssertEqual(Zone.forDirection(origin: origin, point: CGPoint(x: 560, y: 560)), .topRight,    "45°")
        XCTAssertEqual(Zone.forDirection(origin: origin, point: CGPoint(x: 440, y: 560)), .topLeft,     "135°")
        XCTAssertEqual(Zone.forDirection(origin: origin, point: CGPoint(x: 440, y: 440)), .bottomLeft,  "225°")
        XCTAssertEqual(Zone.forDirection(origin: origin, point: CGPoint(x: 560, y: 440)), .bottomRight, "315°")
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
        XCTAssertEqual(Zone.top.rect(in: visible), CGRect(x: 100, y: 450, width: 1000, height: 400))
        XCTAssertEqual(Zone.bottom.rect(in: visible), CGRect(x: 100, y: 50, width: 1000, height: 400))
        XCTAssertEqual(Zone.topLeft.rect(in: visible), CGRect(x: 100, y: 450, width: 500, height: 400))
        XCTAssertEqual(Zone.topRight.rect(in: visible), CGRect(x: 600, y: 450, width: 500, height: 400))
        XCTAssertEqual(Zone.bottomLeft.rect(in: visible), CGRect(x: 100, y: 50, width: 500, height: 400))
        XCTAssertEqual(Zone.bottomRight.rect(in: visible), CGRect(x: 600, y: 50, width: 500, height: 400))
    }

    func testMaximizeFillsVisibleFrame() {
        XCTAssertEqual(SnapTarget.maximize.rect(in: visible), visible)
    }

    func testZonesTileTheScreenWithoutOverlap() {
        let sideHalves = [Zone.left, .right].map { $0.rect(in: visible) }
        XCTAssertEqual(sideHalves[0].union(sideHalves[1]), visible)
        XCTAssertTrue(sideHalves[0].intersection(sideHalves[1]).isEmpty)

        let stackedHalves = [Zone.top, .bottom].map { $0.rect(in: visible) }
        XCTAssertEqual(stackedHalves[0].union(stackedHalves[1]), visible)
        XCTAssertTrue(stackedHalves[0].intersection(stackedHalves[1]).isEmpty)

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

    /// Both layouts must tile the circle exactly: no gap a flick could fall
    /// into, no overlap where two zones would claim the same angle.
    func testEveryLayoutTilesTheCircleWithoutGapOrOverlap() {
        for layout in ZoneLayout.allCases {
            let table = Zone.arcs(in: layout)
            var total: CGFloat = 0
            for (zone, arc) in table {
                XCTAssertGreaterThan(arc.end, arc.start,
                                     "\(zone.displayName) arc must be forward-ordered in \(layout)")
                total += arc.end - arc.start
            }
            XCTAssertEqual(total, 360, accuracy: 0.0001, "\(layout) does not cover the circle")

            // Each arc must start where the previous one ended, modulo the wrap.
            for index in 1..<table.count {
                XCTAssertEqual(table[index].arc.end.truncatingRemainder(dividingBy: 360),
                               ZoneMath.normalizedDegrees(table[(index + 1) % table.count].arc.start),
                               accuracy: 0.0001,
                               "\(layout) has a seam after \(table[index].zone.displayName)")
            }
        }
    }

    func testEveryDegreeMapsToAZoneWhoseArcContainsIt() {
        let table = Dictionary(uniqueKeysWithValues: Zone.activeArcs.map { ($0.zone, $0.arc) })
        for degree in stride(from: CGFloat(0), to: 360, by: 0.5) {
            let zone = Zone.forAngle(degrees: degree)
            guard let arc = table[zone] else {
                return XCTFail("\(degree)° mapped to \(zone.displayName), which is not in the layout")
            }
            // `right` wraps, so compare against both the raw angle and its
            // +360 alias.
            let inRange = (degree >= arc.start && degree < arc.end)
                || (degree + 360 >= arc.start && degree + 360 < arc.end)
            XCTAssertTrue(inRange, "\(degree)° mapped to \(zone.displayName), whose arc is \(arc)")
        }
    }

    // MARK: - Six-zone layout

    /// The original table, kept reachable by the "Six zones only" setting.
    func testSixZoneLayoutRestoresTheOriginalBoundaries() {
        ZoneMath.layout = .six

        XCTAssertEqual(Zone.active.count, 6)
        XCTAssertFalse(Zone.active.contains(.top))
        XCTAssertFalse(Zone.active.contains(.bottom))

        XCTAssertEqual(Zone.forAngle(degrees: 0), .right)
        XCTAssertEqual(Zone.forAngle(degrees: 45), .topRight)
        XCTAssertEqual(Zone.forAngle(degrees: 90), .topLeft, "90° is a boundary, not Top")
        XCTAssertEqual(Zone.forAngle(degrees: 135), .left)
        XCTAssertEqual(Zone.forAngle(degrees: 270), .bottomRight)
        XCTAssertEqual(Zone.forAngle(degrees: 315), .right)
        XCTAssertEqual(Zone.forAngle(degrees: -45), .right)
    }

    /// A straight-up flick has nowhere vertical to go in the six-zone layout,
    /// so it must resolve to a quarter rather than to nothing.
    func testStraightUpAndDownStillResolveInSixZoneLayout() {
        ZoneMath.layout = .six
        let origin = CGPoint(x: 500, y: 500)
        XCTAssertEqual(Zone.forDirection(origin: origin, point: CGPoint(x: 500, y: 600)), .topLeft)
        XCTAssertEqual(Zone.forDirection(origin: origin, point: CGPoint(x: 500, y: 400)), .bottomRight)
    }

    func testEveryDegreeMapsToAZoneInBothLayouts() {
        for layout in ZoneLayout.allCases {
            ZoneMath.layout = layout
            let expected = Set(Zone.arcs(in: layout).map(\.zone))
            for degree in stride(from: CGFloat(0), to: 360, by: 0.5) {
                XCTAssertTrue(expected.contains(Zone.forAngle(degrees: degree)),
                              "\(degree)° escaped the \(layout) layout")
            }
        }
    }
}

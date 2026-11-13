//
//  VersionTests.swift
//  DoweyTests
//
//  Version.swift is compiled directly into this bundle. These comparisons
//  decide whether an update is offered at all, so they are pinned here.
//

import XCTest

final class VersionTests: XCTestCase {

    func testParsesTagsWithAndWithoutPrefix() {
        XCTAssertEqual(Version("v1.4.3")?.parts, [1, 4, 3])
        XCTAssertEqual(Version("1.4.3")?.parts, [1, 4, 3])
    }

    func testRejectsAnythingThatIsNotANumber() {
        XCTAssertNil(Version(""))
        XCTAssertNil(Version("v"))
        XCTAssertNil(Version("1.4.x"))
        XCTAssertNil(Version("1..3"))
        XCTAssertNil(Version("1.5.0-beta"))
    }

    /// Numeric, not textual: 1.10 is newer than 1.9.
    func testComparesEachPartAsANumber() {
        XCTAssertLessThan(Version("1.9.0")!, Version("1.10.0")!)
        XCTAssertLessThan(Version("1.4.3")!, Version("1.4.4")!)
        XCTAssertLessThan(Version("1.4.9")!, Version("1.5.0")!)
        XCTAssertLessThan(Version("1.9.9")!, Version("2.0.0")!)
    }

    func testMissingPartsCountAsZero() {
        XCTAssertEqual(Version("1.5")!, Version("1.5.0")!)
        XCTAssertLessThan(Version("1.5")!, Version("1.5.1")!)
    }

    func testTheSameVersionIsNotAnUpdate() {
        XCTAssertFalse(Version("1.4.3")! > Version("v1.4.3")!)
        XCTAssertFalse(Version("1.4.2")! > Version("1.4.3")!)
    }

    func testDescriptionDropsThePrefix() {
        XCTAssertEqual(Version("v1.5.0")!.description, "1.5.0")
    }
}

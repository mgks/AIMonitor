import XCTest
@testable import AIMonitor

/// Tests for formatting helpers.
final class FormattingTests: XCTestCase {

    func testPercentWholeNumber() {
        XCTAssertEqual(Formatting.percent(81), "81%")
        XCTAssertEqual(Formatting.percent(0), "0%")
        XCTAssertEqual(Formatting.percent(99.7), "100%")   // rounds
    }

    func testPercentNil() {
        XCTAssertNil(Formatting.percent(nil))
    }

    func testCredits() {
        XCTAssertEqual(Formatting.credits(17.43, currency: "USD"), "$17.43")
        XCTAssertNil(Formatting.credits(nil))
    }

    func testTokensCompact() {
        XCTAssertEqual(Formatting.tokens(500), "500")
        XCTAssertEqual(Formatting.tokens(12000), "12.0k")
        XCTAssertEqual(Formatting.tokens(nil), nil)
    }

    func testRelativeShort() {
        let now = Date()
        XCTAssertEqual(Formatting.relativeShort(from: nil), "Never")
        XCTAssertEqual(Formatting.relativeShort(from: now, now: now), "Just now")
    }

    func testCountdown() {
        let now = Date()
        let future = now.addingTimeInterval(3 * 3600 + 18 * 60)   // 3h 18m
        XCTAssertEqual(Formatting.countdown(to: future, now: now), "3h 18m")
        XCTAssertNil(Formatting.countdown(to: nil))
    }
}

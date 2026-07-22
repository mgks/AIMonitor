import XCTest
@testable import AIMonitor

/// Tests for the quota model logic and thresholds.
final class ModelTests: XCTestCase {

    func testStateHealthy() {
        XCTAssertEqual(QuotaThresholds.state(forPercent: 100), .healthy)
        XCTAssertEqual(QuotaThresholds.state(forPercent: 60), .healthy)
    }

    func testStateWarning() {
        XCTAssertEqual(QuotaThresholds.state(forPercent: 49), .warning)
        XCTAssertEqual(QuotaThresholds.state(forPercent: 21), .warning)
    }

    func testStateCritical() {
        XCTAssertEqual(QuotaThresholds.state(forPercent: 19), .critical)
        XCTAssertEqual(QuotaThresholds.state(forPercent: 1), .critical)
    }

    func testStateExhausted() {
        XCTAssertEqual(QuotaThresholds.state(forPercent: 0), .exhausted)
    }

    func testStateUnknown() {
        XCTAssertEqual(QuotaThresholds.state(forPercent: nil), .unknown)
    }

    func testSeverityOrdering() {
        XCTAssertGreaterThan(QuotaState.error.severity, QuotaState.warning.severity)
        XCTAssertGreaterThan(QuotaState.critical.severity, QuotaState.warning.severity)
        XCTAssertGreaterThan(QuotaState.exhausted.severity, QuotaState.healthy.severity)
    }

    func testSnapshotDefaults() {
        let snap = QuotaSnapshot()
        XCTAssertNil(snap.remainingPercent)
        XCTAssertNil(snap.resetsAt)
        XCTAssertNil(snap.weeklyResetsAt)
        XCTAssertTrue(snap.rawHeaders.isEmpty)
    }

    func testProviderStatusShortNameFallback() {
        let status = ProviderStatus(
            providerID: "test",
            displayName: "Test Provider",
            shortName: "",
            state: .healthy
        )
        XCTAssertEqual(status.shortName, "Test Provider")   // falls back to displayName
    }
}

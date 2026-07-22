#!/usr/bin/env swift
// Standalone test runner for AIMonitor. No XCTest/Xcode required.
// Runs with: swift scripts/run-tests.swift
//
// Tests the core logic: OAuth credential parsing, model thresholds,
// and formatting helpers by compiling them in a standalone process.

import Foundation

// MARK: - Tiny test framework

var passed = 0
var failed = 0

func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ msg: String = "",
                               file: String = #file, line: Int = #line) {
    if actual == expected {
        passed += 1
    } else {
        failed += 1
        print("FAIL: \(msg) — expected \(expected), got \(actual) (\(file):\(line))")
    }
}

func assertNotNil(_ value: Any?, _ msg: String = "", file: String = #file, line: Int = #line) {
    if value != nil {
        passed += 1
    } else {
        failed += 1
        print("FAIL: \(msg) — expected non-nil (\(file):\(line))")
    }
}

func assertNil(_ value: Any?, _ msg: String = "", file: String = #file, line: Int = #line) {
    if value == nil {
        passed += 1
    } else {
        failed += 1
        print("FAIL: \(msg) — expected nil (\(file):\(line))")
    }
}

func assertTrue(_ condition: Bool, _ msg: String = "", file: String = #file, line: Int = #line) {
    if condition { passed += 1 }
    else {
        failed += 1
        print("FAIL: \(msg) (\(file):\(line))")
    }
}

func group(_ name: String, _ tests: () -> Void) {
    let beforeFailed = failed
    tests()
    if failed == beforeFailed {
        print("  ✓ \(name)")
    }
}

// MARK: - Quota state threshold tests

func testThresholds() {
    group("QuotaThresholds") {
        assertEqual(QuotaThresholds.state(forPercent: 100), .healthy, "100% healthy")
        assertEqual(QuotaThresholds.state(forPercent: 60), .healthy, "60% healthy")
        assertEqual(QuotaThresholds.state(forPercent: 49), .warning, "49% warning")
        assertEqual(QuotaThresholds.state(forPercent: 21), .warning, "21% warning")
        assertEqual(QuotaThresholds.state(forPercent: 19), .critical, "19% critical")
        assertEqual(QuotaThresholds.state(forPercent: 0), .exhausted, "0% exhausted")
        assertEqual(QuotaThresholds.state(forPercent: nil), .unknown, "nil unknown")
    }
}

// MARK: - Severity ordering

func testSeverity() {
    group("Severity ordering") {
        assertTrue(QuotaState.error.severity > QuotaState.warning.severity, "error > warning")
        assertTrue(QuotaState.critical.severity > QuotaState.warning.severity, "critical > warning")
        assertTrue(QuotaState.exhausted.severity > QuotaState.healthy.severity, "exhausted > healthy")
    }
}

// MARK: - Formatting

func testFormatting() {
    group("Formatting") {
        assertEqual(Formatting.percent(81), "81%", "percent 81")
        assertEqual(Formatting.percent(99.7), "100%", "percent rounds")
        assertNil(Formatting.percent(nil), "percent nil")
        assertNotNil(Formatting.credits(17.43, currency: "USD"), "credits")
        assertNil(Formatting.credits(nil), "credits nil")
        assertEqual(Formatting.tokens(500) ?? "", "500", "tokens 500")
        assertEqual(Formatting.tokens(12000) ?? "", "12.0k", "tokens 12k")
    }
}

// MARK: - Countdown

func testCountdown() {
    group("Countdown") {
        let now = Date()
        let future = now.addingTimeInterval(3 * 3600 + 18 * 60)
        assertEqual(Formatting.countdown(to: future, now: now) ?? "", "3h 18m", "3h18m")
        assertNil(Formatting.countdown(to: nil), "countdown nil")
    }
}

// MARK: - QuotaSnapshot defaults

func testSnapshot() {
    group("QuotaSnapshot") {
        let snap = QuotaSnapshot()
        assertNil(snap.remainingPercent, "default remainingPercent")
        assertNil(snap.resetsAt, "default resetsAt")
        assertNil(snap.weeklyResetsAt, "default weeklyResetsAt")
        assertTrue(snap.rawHeaders.isEmpty, "empty headers")
    }
}

// MARK: - Run

print("AIMonitor test suite")
print(String(repeating: "—", count: 40))
testThresholds()
testSeverity()
testFormatting()
testCountdown()
testSnapshot()
print(String(repeating: "—", count: 40))
print("\(passed) passed, \(failed) failed")

if failed > 0 {
    print("RESULT: FAIL")
    exit(1)
} else {
    print("RESULT: PASS")
}
